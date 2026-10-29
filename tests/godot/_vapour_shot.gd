# Dev helper (not run by tools/test.sh): real-render pictures of the jets' condensation (vapour_fx.gd, Detailed
# effects, docs/rendering.md §6): wingtip / LEX streamers in a 7 G turn, the vapour cone in a Mach 0.95 low pass,
# wing vapour in a 7.5 G turn at Mach 0.8, the turn from 3 km; and from the player's cockpit (straight back,
# back-left / -right, left / right) in a 7 G pull at 200 m/s, a 4.5 G pull at 120 m/s (the original's ribbon regime)
# and the Mach 0.95 pass.
# Needs a window:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 VAPOUR_OUT=/tmp/vapour -- --log-file /tmp/v.log --path game \
#     --resolution 1920x1080 --fixed-fps 30 -s ../tests/godot/_vapour_shot.gd
# (--fixed-fps: a software-rendered window draws a frame in ~0.3 s; the trails need even time steps.)
# Saves VAPOUR_OUT/<plane>_<model>_<scene>.png; VAPOUR_ONLY=cockpit takes only the cockpit pictures (the player's jet:
# VAPOUR_JET=f35i flies the F-35I, else the F-16; VAPOUR_MODEL=detailed its Detailed model), VAPOUR_PLANES
# picks the jets (default f16:original,f16:detailed,f35i:original), VAPOUR_CLEAR=1 a clear sky (no cloud layer,
# Atmospheric sky); terrain_view's `-- --hour 18.6` sets the time (dusk). VAPOUR_BEFORE=1 takes the same shots with
# Particle effects = Original (`<shot>_before.png`, else `<shot>_after.png`); VAPOUR_TAG prefixes the names.
extends "res://../tests/godot/base.gd"

var tv: Node
var cam: Camera3D
var out := ""
var vf: Node
var suffix := "_after"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("VAPOUR_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	settings().particle_effects = OS.get_environment("VAPOUR_BEFORE") != "1"
	suffix = "_after" if settings().particle_effects else "_before"
	settings().show_info = false
	if OS.get_environment("VAPOUR_CLEAR") == "1":
		settings().textured_sky = false
		settings().sky = "atmospheric"
	if OS.get_environment("VAPOUR_JET") == "f35i":
		settings().f35i_slot = 1
	settings().jet_id = 1
	if OS.get_environment("VAPOUR_MODEL") != "":
		settings().models = OS.get_environment("VAPOUR_MODEL")
	seed(1)  # the same cloud layer every run (cloud_layer.gd picks its texture at random)
	tv = await start_mission(231)
	tv.frozen = true
	tv.fm_stopped = true
	for c in tv.get_children():
		if c is CanvasLayer:
			c.visible = false
	vf = tv.effects.gpu.vapour if tv.effects.gpu != null else null
	var base: Vector3 = tv.rig.global_position
	var h = tv.terrain.height_at(base)
	base.y = (float(h) if h != null else 0.0) + 250.0
	await frames(90)  # the terrain around the start streamed in (the first shot of a run showed it flat)
	if OS.get_environment("VAPOUR_ONLY") != "cockpit":
		var keep := GDScript.new()
		keep.source_code = "extends Camera3D\nfunc _process(_d):\n\tmake_current()\n"
		keep.reload()
		cam = Camera3D.new()
		cam.set_script(keep)
		cam.process_priority = 1000
		cam.far = 60000.0
		cam.fov = 40.0
		tv.add_child(cam)
		var planes := OS.get_environment("VAPOUR_PLANES")
		for pm in (planes if planes != "" else "f16:original,f16:detailed,f35i:original").split(","):
			var c := pm.split(":")
			settings().models = c[1]
			var m: Node3D = load("res://aircraft/aircraft_model.gd").create(c[0], -1, false)
			tv.add_child(m)
			var name := OS.get_environment("VAPOUR_TAG") + c[0] + "_" + c[1]
			await _turn(m, base, 200.0, 7.0, 0.6, Vector3(-9, 4, 34), name + "_turn_chase")
			await _turn(m, base, 200.0, 7.0, 0.6, Vector3(-30, -6, 2), name + "_turn_side")
			# Near the 3 km where the condensation ends (vapour_fx.gd AI_RANGE): the jet a few pixels across.
			await _turn(m, base, 200.0, 7.0, 0.6, Vector3(-1500, 400, 2500), name + "_turn_far")
			await _pass(m, base, name)
			await _turn(m, base, 270.0, 7.5, 0.8, Vector3(-12, 9, 28), name + "_wing")
			m.queue_free()
		cam.queue_free()
		await frames(2)
	await _cockpit(base)


## Flies `m` on a level circle at `v` m/s and `g` for 1.5 s, the camera at `off` in the jet's frame (+X right of the
## turn's outside, +Y up, +Z aft), then saves `name`.
func _turn(m: Node3D, base: Vector3, v: float, g: float, mach: float, off: Vector3, name: String) -> void:
	var r := v * v / (9.81 * g)
	var bank := acos(1.0 / g)
	var st := {"g": g, "aoa": 9.0 + 2.0 * g, "mach": mach, "speed": v, "alt_ft": 800.0}
	var t := 0.0
	while t < 1.5:
		t += tv.get_process_delta_time()
		var a := v / r * t
		var p := base + Vector3(r * cos(a), 0, r * sin(a))
		var fwd := Vector3(-sin(a), 0, cos(a))
		var inward := Vector3(-cos(a), 0, -sin(a))
		var up := (Vector3.UP * cos(bank) + inward * sin(bank)).normalized()
		m.global_transform = Transform3D(Basis(fwd.cross(up), up, -fwd), p)
		_feed(m, st)
		var cb := Basis(-inward, Vector3.UP, -fwd)
		cam.global_position = p + cb * off
		cam.look_at(p, Vector3.UP)
		await process_frame
	await _save(name)


## A straight pass at Mach 0.95, 60 m up: one close chase picture and one from the side as it goes by.
func _pass(m: Node3D, base: Vector3, name: String) -> void:
	var st := {"g": 1.0, "aoa": 2.0, "mach": 0.95, "speed": 320.0, "alt_ft": 200.0}
	var fwd := Vector3(0, 0, -1)
	var p0 := base + Vector3(0, -190, 0)
	var t := 0.0
	while t < 1.5:
		t += tv.get_process_delta_time()
		var p := p0 + fwd * 320.0 * t
		m.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.UP, -fwd), p)
		_feed(m, st)
		cam.global_position = p + Vector3(-10, 3, 22)
		cam.look_at(p + fwd * 2.0, Vector3.UP)
		await process_frame
	await _save(name + "_cone_chase")
	t = 0.0
	var side := p0 + fwd * 320.0 * 1.6 + Vector3(-45, 2, 0)
	while t < 1.6:
		t += tv.get_process_delta_time()
		var p := p0 + fwd * 320.0 * (1.5 + t)
		m.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.UP, -fwd), p)
		_feed(m, st)
		cam.global_position = side
		cam.look_at(p, Vector3.UP)
		if t > 0.0 and (side - p).dot(fwd) < 2.0:
			break
		await process_frame
	await _save(name + "_cone_side")


## The player's own jet from its cockpit: a wings-level pull (7 G at 200 m/s; 4.5 G at 120 m/s, where the original
## draws its wingtip ribbons) and a Mach 0.95 pass 60 m up, each looked at straight back, back-left / -right and
## left / right along the wing.
func _cockpit(base: Vector3) -> void:
	tv.views.set_cockpit(tv.views.COCKPIT)
	for c in tv.get_children():
		if c is CanvasLayer:
			c.visible = true
	var tag := OS.get_environment("VAPOUR_TAG") + str(tv.player.plane) + "_" + str(settings().models) + "_cockpit_"
	# The snap views (views.gd SNAPS); at 90° and beyond the camera cannot pitch down (terrain_view.gd _apply_view).
	var looks := {"back": 180, "back_left": 225, "back_right": 135}
	var h = tv.terrain.height_at(base)
	var low := (float(h) if h != null else 0.0) + 60.0
	var flights := [
		["turn", 200.0, {"g": 7.0, "aoa": 20.0, "mach": 0.6, "speed": 200.0, "alt_ft": 800.0}],
		["slow", 120.0, {"g": 4.5, "aoa": 18.0, "mach": 0.36, "speed": 120.0, "alt_ft": 800.0}],
		["pass", 320.0, {"g": 1.0, "aoa": 2.0, "mach": 0.95, "speed": 320.0, "alt_ft": 200.0}],
	]
	var only_f := OS.get_environment("VAPOUR_FLIGHTS")
	var only_l := OS.get_environment("VAPOUR_LOOKS")
	for fl in flights:
		if only_f != "" and not fl[0] in only_f.split(","):
			continue
		for look in looks:
			if only_l != "" and not look in only_l.split(","):
				continue
			var v: float = fl[1]
			var st: Dictionary = fl[2]
			var g: float = st.g
			# A level turn to the left: banked acos(1/n), on a circle of radius v² / (g·√(n² − 1)), the nose the
			# angle of attack above the flight path.
			var bank := acos(1.0 / g)
			var r := v * v / (9.81 * sqrt(maxf(g * g - 1.0, 1e-6))) if g > 1.0 else 1e9
			var c := Vector3(base.x - r, low if fl[0] == "pass" else base.y, base.z)
			var t := 0.0
			while t < 1.0:
				t += tv.get_process_delta_time()
				var a := -v / r * t
				var p := c + Vector3(r * cos(a), 0, r * sin(a))
				var fwd := Vector3(sin(a), 0, -cos(a))
				var inward := Vector3(-cos(a), 0, -sin(a))
				var up := (Vector3.UP * cos(bank) + inward * sin(bank)).normalized()
				var right := fwd.cross(up)
				var b := Basis(right, up, -fwd).rotated(right, deg_to_rad(float(st.aoa)))
				tv.rig.global_transform = Transform3D(b, p)
				tv.views.head = tv.views.SNAPS[looks[look]]
				_feed(tv.aircraft, tv.vapour_state(st))
				await process_frame
			await _save(tag + fl[0] + "_" + look)


## One frame of the jet's condensation: Detailed through vapour_fx.gd; Original by the original's rule (the wingtip
## ribbons at 75 < V < 150 m/s with the stick past 0.7, taken as a pull of 3 G or more; FUN_004da090).
func _feed(m: Node3D, st: Dictionary) -> void:
	if vf != null:
		vf.update(m, st)
	elif tv.trails != null and st.speed > 75.0 and st.speed < 150.0 and st.g >= 3.0:
		var tips: Array = m.wingtips()
		for i in tips.size():
			tv.trails.emit([m, i], tips[i], tv.trails.WINGTIP)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + suffix + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
