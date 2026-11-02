# Dev helper (not run by tools/test.sh): the F-16's 3D cockpit (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit") in a
# real render, the Barak's and the Sufa's: straight ahead, looking up a little (8°), left, right and down at the MFDs
# (25° down), and the Real HUD over a ground unit 8 km ahead. C3D_LOOK=2d takes the same frames with the 2D panel (side
# by side). The scene is _cockpit_show_shot.gd's cockpit_f16_day (Settings at their defaults, the switch set here);
# C3D_HOUR=22 the night (the mission then starts at night: pass `-- --hour 22` too). C3D_JET=f35i: the F-35I's instead
# (_f35i). C3D_ONLY=panel takes only the lamps and displays: the master caution and fire lamps lit, the gear down, an
# emitter and a launching one on the RWR scope; looking down at the panel, at the RWR scope and at the gear panel.
# C3D_ONLY=hud: only ahead and looking up 8° (the HUD's frame against the sky).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=$PWD/.shots/c3d -- \
#     --log-file /tmp/c3d.log --resolution 1920x1080 --path game -s ../tests/godot/_cockpit3d_shot.gd
extends "res://../tests/godot/_cockpit_show_shot.gd"

## [name, head yaw, head pitch] (deg; + right, + up).
const HEADS := [
	["front", 0.0, 0.0], ["up", 0.0, 8.0], ["left", -80.0, -30.0], ["right", 80.0, -30.0], ["down", 0.0, -25.0]
]


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var two_d := OS.get_environment("C3D_LOOK") == "2d"
	look = "2d" if two_d else "3d"
	settings().show_info = false
	settings().cockpit_3d = "original" if two_d else "3d"
	settings().hud_style = "real"
	var hour := float(OS.get_environment("C3D_HOUR")) if OS.get_environment("C3D_HOUR") != "" else 10.5
	if OS.get_environment("C3D_JET") == "f35i":
		await _f35i(hour)
		return
	for variant in ["barak", "sufa"]:
		settings().f16_variant = variant
		var spec: Array = COCKPITS.cockpit_f16_day.duplicate()
		spec[2] = hour
		await _cockpit_scene("f16_" + variant, spec)
		if OS.get_environment("C3D_ONLY") == "panel":
			await _panel(variant)
			continue
		for h in HEADS.slice(1):
			if OS.get_environment("C3D_ONLY") == "hud" and h[0] != "up":
				continue
			tv.views.snap = Vector2(deg_to_rad(h[1]), deg_to_rad(h[2]))
			await _settle()
			await _shot("f16_%s_%s" % [variant, h[0]], 0.0)
		tv.views.snap = null
		if OS.get_environment("C3D_ONLY") != "hud":
			await _target(variant)
	settings().jet_id = -1


## A ground unit 8 km ahead, about 11° under the nose: the Real HUD over it.
func _target(variant: String) -> void:
	var site := _ground_unit(tv)
	if site.is_empty():
		return
	var st: Dictionary = tv.flight.state()
	var w = tv.weapons
	var own: Dictionary = w.own()
	var o := {"pos": own.pos, "fwd": own.fwd}
	var p := _place(tv, w, site, o, 8000.0)
	print("target at ", p, " jet alt ", st.position)
	await _settle()
	await _shot("f16_%s_target" % variant, 0.0)


## The lamps and displays (cockpit3d.gd _setup_instruments) with something to show.
func _panel(variant: String) -> void:
	var c: Control = tv.cockpit
	c.indicators[0] = true
	c.indicators[1] = true
	tv.gear_down = true
	tv.gear_legs = [2, 2, 2]
	var own: Vector2 = c.state.world
	var h := deg_to_rad(float(c.state.heading))
	c.rwr = [
		{"type": 300, "pos": own + Vector2(sin(h + 0.6), cos(h + 0.6)) * 15000.0, "launch": false, "active": true},
		{"type": 100, "pos": own + Vector2(sin(h - 1.9), cos(h - 1.9)) * 25000.0, "launch": true, "active": true},
	]
	# The displays' SubViewports' GPU time (and an MFD's, to compare).
	var vps := {"MFD_L": c.mfds[0].get_parent()}
	for name in tv.cockpit_3d.displays:
		vps[name] = tv.cockpit_3d.displays[name].get_parent()
	for name in vps:
		RenderingServer.viewport_set_measure_render_time(vps[name].get_viewport_rid(), true)
	for v in [
		["panel", 0.0, -25.0],
		["rwr", -11.0, -20.0],
		["eyebrow", -24.0, -8.0],
		["gear", -28.0, -42.0],
		["ehsi", 0.0, -45.0],
		["ded", 9.0, -17.0]
	]:
		tv.views.snap = Vector2(deg_to_rad(v[1]), deg_to_rad(v[2]))
		await _settle()
		await _shot("f16_%s_%s" % [variant, v[0]], 0.0)
	await _gauges(variant)
	for name in vps:
		var rid: RID = vps[name].get_viewport_rid()
		print("GPU %-12s %.3f ms" % [name, RenderingServer.viewport_get_measured_render_time_gpu(rid)])
	tv.views.snap = null


## The ADI in a right turn on the ILS (30° bank, a standard-rate turn, a slight skid, the localizer right and the jet
## high), the right auxiliary console's gauges and the pilot fault list (a fuel leak, flag 10): the state written
## each frame between the flight's write and the 3D cockpit's read (process priority 5).
func _gauges(variant: String) -> void:
	var c: Control = tv.cockpit
	var c3: Node3D = tv.cockpit_3d
	var src := GDScript.new()
	src.source_code = (
		"extends Node\nvar c: Control\nvar vals := {}\nvar bars = null\n\nfunc _process(_d):\n"
		+ "\tc.state.merge(vals, true)\n\tif bars != null:\n\t\tc.state.better.pnp_bars = bars\n"
	)
	src.reload()
	var forcer := Node.new()
	forcer.set_script(src)
	forcer.c = c
	forcer.vals = {"roll": 30.0, "yaw_rate_dps": 3.0, "lateral_g": 0.06, "normal_g": 1.15}
	forcer.bars = Vector2(0.48, 0.43)  # 1.2° left of the localizer, 0.3° high (of ±2.5° / ±0.7°)
	forcer.process_priority = 5
	tv.add_child(forcer)
	var flags: Array = c.damage_flags
	flags[10] = true
	c.indicators[0] = false
	c.indicators[1] = false
	# The right auxiliary console's gauges about the EPU fuel gauge (HYD PRESS A / B, LOX, cabin, EPU).
	var epu: Node3D = c3._anims.filter(func(a): return a[2][0].prop == "f16/cockpit/hydrazine-minutes")[0][0]
	var adi := c3.find_child("ADI_glide-slope-index", true, false) as Node3D
	var zoom: float = c.zoom
	for v in [["adi", adi], ["aux", epu], ["pfd", c3.find_child("PFD_screen", true, false)]]:
		c.zoom = c.ZOOM_MAX if v[0] != "aux" else (c.ZOOM_MAX + zoom) / 2.0  # the true size; the console wider
		tv.views.snap = await _head_at(v[1])
		await _settle()
		await _shot("f16_%s_%s" % [variant, v[0]], 0.0)
	# The ADI level, no turn, no skid, no ILS: the turn needle and the ball centred, the bars hidden.
	forcer.vals = {"roll": 0.0, "yaw_rate_dps": 0.0, "lateral_g": 0.0, "normal_g": 1.0}
	tv.gear_down = false
	tv.views.snap = await _head_at(adi)
	await _settle()
	await _shot("f16_%s_adi_level" % variant, 0.0)
	c.zoom = zoom
	flags[10] = false
	forcer.queue_free()


## The head snap (yaw, pitch; rad) that brings `n` to the screen's middle: Newton steps on its place on the screen.
func _head_at(n: Node3D) -> Vector2:
	var s := Vector2(0.0, -0.4)
	var mid: Vector2 = tv.camera.get_viewport().get_visible_rect().size / 2.0
	for i in 3:
		var p: Vector2 = await _seen_at(n, s)
		var jx: Vector2 = (await _seen_at(n, s + Vector2(0.02, 0.0)) - p) / 0.02
		var jy: Vector2 = (await _seen_at(n, s + Vector2(0.0, 0.02)) - p) / 0.02
		s += Transform2D(jx, jy, Vector2.ZERO).affine_inverse().basis_xform(mid - p)
	return s


## Where `n` shows on the screen with the head at `s`.
func _seen_at(n: Node3D, s: Vector2) -> Vector2:
	tv.views.snap = s
	await frames(2)
	return tv.camera.unproject_position(n.global_position)


## C3D_JET=f35i: the F-35I's (by day; C3D_HOUR=22 its night scene): ahead, down at the panoramic display, left, right,
## back, and the gear panel with the lamps lit; the SubViewports' GPU time.
func _f35i(hour: float) -> void:
	var spec: Array = (COCKPITS.cockpit_f35i_night if hour >= 20.0 else COCKPITS.cockpit_f35i_day).duplicate()
	await _cockpit_scene("f35i", spec)
	var c: Control = tv.cockpit
	var vps := {}
	if tv.cockpit_3d != null:
		vps = {"PCD": c.pcd.get_parent(), "ESIS": tv.cockpit_3d.esis.get_parent()}
	for name in vps:
		RenderingServer.viewport_set_measure_render_time(vps[name].get_viewport_rid(), true)
	for v in [["down", 0.0, -20.0], ["left", -80.0, -30.0], ["right", 80.0, -30.0], ["back", 150.0, 0.0]]:
		tv.views.snap = Vector2(deg_to_rad(v[1]), deg_to_rad(v[2]))
		await _settle()
		await _shot("f35i_" + v[0], 0.0)
	c.indicators[0] = true
	c.indicators[1] = true
	tv.gear_down = true
	tv.views.snap = Vector2(deg_to_rad(-20.0), deg_to_rad(-38.0))
	await _settle()
	await _shot("f35i_gear", 0.0)
	for name in vps:
		var rid: RID = vps[name].get_viewport_rid()
		print("GPU %-6s %.3f ms" % [name, RenderingServer.viewport_get_measured_render_time_gpu(rid)])
	tv.views.snap = null
	settings().f35i_slot = -1
	settings().jet_id = -1
