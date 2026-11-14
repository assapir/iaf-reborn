# Dev helper (not run by tools/test.sh): real-render pictures of the effects whose sprites Modern IAF draws itself
# (`iaf-sim own`, modern-iaf/docs/weapons.md §2) and the same moments in the original game: the afterburner from the
# rear quarter and the side, the engines at cruise from behind (the heat haze) over the ground and over a cloud deck,
# flares being released, a missile launch with its plume and a bomb hit. Runs in either project:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 EFX_OUT=/tmp/efx EFX_JET=sufa EFX_TAG=sufa -- \
#     --log-file /tmp/e.log --resolution 2560x1440 --path modern-iaf -s ../modern-iaf/tests/_effects_shot.gd \
#     -- --at 666059 3409044 3000 246 0
# EFX_JET=sufa|barak|f35i: the free flight's jet (EFX_MISSION=id: a mission's). EFX_HOUR=h: the clock (e.g. 17 for
# dusk); EFX_ONLY=name,...: some shots (ab_rear, ab_side, cruise_rear, cruise_side, cloud_ab, cloud_cruise, flares,
# missile, bomb).
# EFX_NOHAZE=1: the heat haze hidden (to compare). Saves EFX_OUT/<EFX_TAG>_<shot>.png.
extends "res://../tests/godot/base.gd"

## stores.gd FLARE (its preload fails before the autoloads in a -s script).
const FLARE := 550

var tv: Node
var out := ""
var tag := ""
var only: PackedStringArray


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("EFX_OUT")
	tag = OS.get_environment("EFX_TAG")
	only = OS.get_environment("EFX_ONLY").split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	settings().show_info = false
	seed(231)
	# EFX_JET: the free flight's jet (sufa, barak, f35i); EFX_MISSION: a mission's instead.
	match OS.get_environment("EFX_JET"):
		"sufa", "barak":
			settings().f16_variant = OS.get_environment("EFX_JET")
		"f35i":
			settings().f35i_slot = 0
			settings().jet_id = 0
	var mid := OS.get_environment("EFX_MISSION")
	tv = await start_mission(int(mid) if mid != "" else -1)
	tv.text_messages = false
	for c in tv.get_children():
		if c is CanvasLayer:
			c.visible = false
	var hour := OS.get_environment("EFX_HOUR")
	if hour != "" and tv.runtime != null:
		tv.runtime.misc["0x460"] = float(hour) * 3600.0 - tv.runtime.now
	elif hour != "":
		tv._sim_time = float(hour) * 3600.0 - 39600.0  # a free flight's clock (_imagery_shot.gd)
	tv._tod_t = -INF
	tv.gear_down = false
	await ground_streamed(tv, 30000, 30)
	var g = tv.terrain.height_at(tv.rig.global_position)
	print(
		(
			"EFX start %s agl %.0f flames %d"
			% [tv.rig.global_position, tv.rig.global_position.y - float(g), tv.aircraft.flames.size()]
		)
	)
	# 1. Flares while flying (the decoys move with the sim clock), the jet in afterburner.
	if _want("flares"):
		# From ahead, a little to the side: the flares falling back behind the jet.
		_orbit(25.0, 3.0, 55.0)
		var n := 0
		for i in 6:
			n += int(tv.weapons.dispense(FLARE))
			await _hold(100, 0.05)
		await _hold(100, 0.05)
		var fx = tv.weapons.decoy_fx
		var at: Array = []
		if fx != null:
			for f in fx._flares.values():
				at.append(f.node.global_position - tv.aircraft.global_position)
		print("EFX flares released %d, drawn at %s from the jet" % [n, at])
		await _shot("flares")
	tv.frozen = true
	tv.fm_stopped = true
	for f in tv.aircraft.flames:
		f.set_process(false)
	# 2. The afterburner and the engines at cruise over the ground.
	for s in [
		["ab_rear", 100, 155.0, 6.0, 20.0],
		["ab_side", 100, 95.0, 2.0, 24.0],
		["cruise_rear", 63, 165.0, 8.0, 22.0],
		["cruise_side", 63, 100.0, 3.0, 18.0]
	]:
		if _want(s[0]):
			_orbit(s[2], s[3], s[4])
			await _hold(s[1], 1.0)
			await _shot(s[0])
	# 3. A missile launch beside the jet, seen from its rear quarter.
	if _want("missile"):
		await _missile()
	# 4. A bomb's hit on the ground ahead (player_weapons.gd: flash + smoke streamers).
	if _want("bomb"):
		await _bomb()
	# 5. Over a cloud deck: the jet above the rain's deck, seen from above.
	if _want("cloud_ab") or _want("cloud_cruise"):
		settings().rain = "light"
		tv.apply_render_options()
		await frames(60)
		var deck: Vector2 = load("res://shared/terrain/weather.gd").deck()
		tv.rig.position.y = deck.y + 400.0
		print("EFX deck %s jet %.0f" % [deck, tv.rig.position.y])
		for s in [["cloud_ab", 100], ["cloud_cruise", 63]]:
			if _want(s[0]):
				_orbit(160.0, 25.0, 24.0)
				await ground_streamed(tv, 20000, 10)
				await _hold(s[1], 2.0)
				await _shot(s[0])


func _want(name: String) -> bool:
	return only.is_empty() or name in only


## The external view at yaw (180: from behind, along the heading), pitch (deg, + above) and distance.
func _orbit(yaw: float, pitch: float, dist: float) -> void:
	tv.in_cockpit = false
	tv.views.orbit_heading = deg_to_rad(yaw) - PI
	tv.views.orbit_pitch = -deg_to_rad(pitch)
	tv.views.dist = dist
	tv._apply_view()


## `secs` of frames with every flame at `level` (the flames' own update is off while frozen).
func _hold(level: int, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		for f in tv.aircraft.flames:
			f.level = level
			if not f.is_processing():
				f.rebuild()
			if f.haze != null and OS.get_environment("EFX_NOHAZE") == "1":
				f.haze.visible = false
		await process_frame


func _shot(name: String) -> void:
	for c in root.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	await process_frame
	await save_shot(out.path_join("%s_%s.png" % [tag, name]))


func _missile() -> void:
	var fwd: Vector3 = -tv.aircraft.global_basis.z
	var right: Vector3 = tv.aircraft.global_basis.x
	var p0: Vector3 = tv.aircraft.global_position + right * 4.0 - tv.aircraft.global_basis.y * 0.6
	var body := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.065
	c.bottom_radius = 0.065
	c.height = 3.0
	body.mesh = c
	tv.add_child(body)
	_orbit(145.0, 6.0, 35.0)
	var t := 0.0
	while t < 0.8:
		var dt: float = tv.get_process_delta_time()
		t += dt
		var p := p0 + fwd * (30.0 * t + 75.0 * t * t)  # as seen from the launching jet
		body.global_position = p
		body.basis = Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0)
		tv.trails.emit("efx_missile", p - fwd * 2.5, tv.trails.MISSILE)
		await _hold(63, 0.0)
	await _shot("missile")
	body.queue_free()


func _bomb() -> void:
	var keep := GDScript.new()
	keep.source_code = "extends Camera3D\nfunc _process(_d):\n\tmake_current()\n"
	keep.reload()
	var cam := Camera3D.new()
	cam.set_script(keep)
	cam.process_priority = 1000
	cam.far = 60000.0
	tv.add_child(cam)
	var fwd: Vector3 = -tv.rig.global_basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var a: Vector3 = tv.rig.global_position + fwd * 900.0
	var h = tv.terrain.height_at(a)
	var gp := Vector3(a.x, float(h) if h != null else a.y, a.z)
	cam.global_position = gp - fwd * 160.0 + side * 30.0 + Vector3(0, 30, 0)
	cam.look_at(gp + Vector3(0, 12, 0), Vector3.UP)
	await ground_streamed(tv, 20000, 30)
	tv.effects.explosion(gp, tv.effects.F_FLASH | tv.effects.F_SMOKE_TRAILS, 4.0, 95.0, gp.y)
	var t0 := Time.get_ticks_msec()
	for t in [0.15, 0.6, 2.0]:
		while Time.get_ticks_msec() - t0 < t * 1000.0:
			await process_frame
		await _shot("bomb_%s" % str(t))
	cam.queue_free()
