# Dev helper (not run by tools/test.sh): real-render pictures of the player's jet from outside, for comparing
# Models: Original / Detailed (docs/aircraft-models.md). Needs a window.
#   SHOT_MODELS=detailed SHOT_OUT=/tmp/shots SHOT_START=airborne IAF_DEFAULT_SETTINGS=1 \
#       godot --path game --resolution 1920x1080 -s ../tests/godot/_model_shot.gd
# SHOT_START: "airborne" (mission 231, frozen 3000 m up, LOADOUT on the pylons) or "ground" (mission 311 on the
# runway, gear down). Each shot in SHOTS: the camera at `dist` m from the jet's origin, `yaw` degrees round from
# the nose (90 = from the right), `pitch` degrees above; the pose (gear / flaps / brakes / afterburner) set and
# settled; an optional 6th entry is the look-at point in the jet's frame (m, nose -Z). Writes
# SHOT_OUT/<models>_<name>.png and prints the frame time of a settled view. SHOT_BENCH=1: no pictures; the frame time
# (vsync off) and GPU time over 600 frames with the camera 50 m behind the jet (mission 231: the player's jet and the
# AI's F-16s drawn).
# SHOT_F16=sufa: every F-16 as the F-16I Sufa (docs/f16i.md §8.1). SHOT_AI=1: the shots of the first AI F-16 instead
# of the player's jet (the camera rides with it; no pose).
# SHOT_JET=0 (the F-15; any jet_id): mission 311 with that jet, also for "airborne" (lifted 3000 m, F15_LOADOUT), and
# the JET_SHOTS (docs/aircraft-models.md §6), named for the before / after pairs.
extends "res://../tests/godot/base.gd"

## AIM-9 on the tips, AIM-120 outboard, Mk-84 at C / G, tanks at D / F, an ECM pod at E (weapon ids by name below).
const LOADOUT := {0: "AIM9", 1: "AIM120", 2: "MK84", 3: "370", 4: "300", 5: "370", 6: "MK84", 7: "AIM120", 8: "AIM9"}
const AIR_SHOTS := [
	["fin_right", 7.0, 95.0, 6.0, {}, Vector3(0, 1.9, 5.0)],
	["photo_right", 24.0, 80.0, -8.0, {}],
	["photo_left", 24.0, 280.0, -8.0, {}],
	["photo_top", 20.0, 15.0, 40.0, {}],
	["fin_left", 7.0, 265.0, 6.0, {}, Vector3(0, 1.9, 5.0)],
	["front_quarter", 22.0, 35.0, 12.0, {}],
	["side", 24.0, 90.0, 2.0, {}],
	["below", 20.0, 150.0, -35.0, {}],
	["rear_quarter", 22.0, 145.0, 15.0, {}],
	["top", 26.0, 10.0, 70.0, {}],
	["brakes_flaps", 16.0, 120.0, 25.0, {"brakes": true, "flaps": 1.0}],
	["afterburner", 18.0, 160.0, 8.0, {"afterburner": 2, "rpm": 1.1}],
	["cockpit_close", 7.0, 60.0, 25.0, {}],
	["brakes_tail", 8.0, 140.0, 10.0, {"brakes": true}, Vector3(0, 0, 5.5)],
	["gear_transit", 12.0, 110.0, -25.0, {"gear_down": true, "gear": 0.8}],
	["belly_centre", 9.0, 100.0, -50.0, {}],
	["tip_rail", 5.0, 200.0, 15.0, {}, Vector3(-4.6, 0, 2.0)],
	["chase_50", 50.0, 175.0, 6.0, {}],
	["spine_close", 9.0, 130.0, 28.0, {}, Vector3(0, 0.9, 1.5)],
	["spine_side", 11.0, 90.0, 4.0, {}, Vector3(0, 0.9, 2.0)],
	["centre_pylon", 7.0, 80.0, -6.0, {}, Vector3(0, -0.9, 1.0)],
	["nose_front", 6.0, 8.0, 14.0, {}, Vector3(0, 0.2, -4.4)],
	["cft_close", 9.0, 300.0, 28.0, {}, Vector3(0, 0.6, 1.0)],
	["far_1000", 1000.0, 120.0, 5.0, {}],
	["far_2000", 2000.0, 120.0, 5.0, {}],
]
## The F-15's pylons: AIM-9 / AIM-7 / Mk-84 / AMRAAM / three Mk-82 on the centre line (as _stores_shot.gd's).
const F15_LOADOUT := [
	["AIM-9M", 1],
	["AIM-7M", 1],
	["MK-84", 1],
	["AMRAAM", 1],
	["MK-82", 3],
	["AMRAAM", 1],
	["MK-84", 1],
	["AIM-7M", 1],
	["AIM-9M", 1]
]
const JET_AIR_SHOTS := [
	["air_side", 24.0, 270.0, 2.0, {}],
	["air_top", 26.0, 10.0, 70.0, {}],
	["air_below", 24.0, 0.0, -80.0, {}],
	["air_front_quarter", 22.0, 35.0, 12.0, {}],
	["air_rear_quarter", 22.0, 145.0, 15.0, {}],
	[
		"air_roll_gear",
		18.0,
		205.0,
		12.0,
		{"gear_down": true, "gear": 0.8, "stick_x": 1.0, "stick_y": -0.6, "rudder": 1.0}
	],
	["air_gear_below", 14.0, 120.0, -30.0, {"gear_down": true, "gear": 0.8}],
	["air_brake_flaps", 16.0, 150.0, 25.0, {"brakes": true, "flaps": 1.0}],
	["air_afterburner", 18.0, 160.0, 8.0, {"afterburner": 2, "rpm": 1.1}],
]
const JET_GROUND_SHOTS := [
	["ground_front_left", 18.0, 325.0, 8.0, {}],
	["ground_rear", 20.0, 165.0, 10.0, {}],
	["ground_gear", 9.0, 250.0, -4.0, {}, Vector3(0, -0.8, 0)],
	["ground_cockpit", 7.0, 300.0, 20.0, {}, Vector3(0, 0.8, -5.5)],
	["ground_left", 22.0, 270.0, 4.0, {}],
	["ground_right", 22.0, 90.0, 4.0, {}],
	["ground_nose", 6.5, 280.0, 6.0, {}, Vector3(0, 0.3, -6.0)],
	["ground_nose_right", 6.5, 80.0, 6.0, {}, Vector3(0, 0.3, -6.0)],
	["ground_tail", 8.5, 245.0, 12.0, {}, Vector3(0, 2.2, 7.0)],
	["ground_tail_inner", 10.0, 300.0, 22.0, {}, Vector3(0, 2.2, 7.0)],
]
const GROUND_SHOTS := [
	["ground_front", 18.0, 30.0, 8.0, {}],
	["ground_side", 20.0, 90.0, 3.0, {}],
	["ground_left", 20.0, 270.0, 3.0, {}],
	["ground_gear", 8.0, 120.0, -2.0, {}],
	["ground_rear", 20.0, 150.0, 10.0, {}],
]

var tv: Node
var _cam_xf := Transform3D()
var _fov := 40.0
var _pose := {}
## SHOT_AI: the AI jet the camera rides with, and the camera in its frame.
var _follow: Node3D
var _cam_local := Transform3D()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var models := OS.get_environment("SHOT_MODELS")
	var out := OS.get_environment("SHOT_OUT")
	var ground := OS.get_environment("SHOT_START") == "ground"
	settings().models = models if models != "" else "original"
	settings().show_info = false
	if OS.get_environment("SHOT_F16") != "":
		settings().f16_variant = OS.get_environment("SHOT_F16")
	var jet := OS.get_environment("SHOT_JET")
	if jet != "":
		settings().jet_id = int(jet)
	tv = await start_mission(311 if ground or jet != "" else 231)
	await frames(60 if ground else 3)
	if jet != "":
		for c in tv.get_children():
			if c is CanvasLayer:
				c.visible = false  # the mission's messages
	if not ground:
		airborne_case(tv, _hardpoints() if jet == "" else _loadout(311, F15_LOADOUT))
		var st: Dictionary = tv.flight.state()
		tv.flight.start(
			settings().assets_dir().path_join("install"),
			tv.player.fm_section,
			tv.rig.position,
			Vector3(0.0, 0.0, st.heading),
			st.forward * 250.0,
			{"airborne": true, "engine_on": true, "real_data": settings().real_data()}
		)
	if OS.get_environment("SHOT_NO_NORMAL") == "1":  # (debug: the normal maps' share of the look)
		for mi: MeshInstance3D in tv.aircraft.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count() if mi.mesh != null else 0:
				var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if m != null:
					m.normal_enabled = false
					m.ao_enabled = false
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
	var pin := CamPin.new()
	pin.place = _place_camera
	pin.process_priority = 100000  # after the flight scene's own camera update
	tv.add_child(pin)
	if OS.get_environment("SHOT_BENCH") == "1":
		await _bench()
		return
	var only := OS.get_environment("SHOT_ONLY")
	var shots: Array = GROUND_SHOTS if ground else AIR_SHOTS
	if jet != "":
		shots = JET_GROUND_SHOTS if ground else JET_AIR_SHOTS
	for s in shots:
		if only != "" and not String(s[0]) in only.split(","):
			continue
		await _shot(s, out, settings().models)
	settings().jet_id = -1
	check(true, "shots done")


## The hardpoints for `loads` ([weapon name, count] per station), the ids from mission `mission`'s weapons.
func _loadout(mission: int, loads: Array) -> Array:
	var ids := {}
	for w in _weapons(mission).weapons:
		ids[String(w.name)] = int(w.id)
	var hp := []
	for l in loads:
		hp.append_array([int(ids.get(l[0], 0)), int(l[1]) if ids.has(l[0]) else 0])
	return hp


## Mission `mission`'s weapon database (loaded at run time: it needs the autoloads).
func _weapons(mission: int) -> RefCounted:
	return load("res://weapons/mission_weapons.gd").create(mission)


func _bench() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _shot(["bench", 50.0, 175.0, 6.0, {}], "", settings().models)
	var ft := []
	var gpu := 0.0
	for i in 600:
		var t := Time.get_ticks_usec()
		await process_frame
		ft.append((Time.get_ticks_usec() - t) / 1000.0)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	ft.sort()
	var avg: float = ft.reduce(func(a, b): return a + b) / ft.size()
	print(
		(
			"BENCH %s frame avg %.2f ms p95 %.2f ms gpu %.2f ms primitives %d"
			% [
				settings().models,
				avg,
				ft[int(ft.size() * 0.95)],
				gpu / 600.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			]
		)
	)
	check(true, "bench done")


func _hardpoints() -> Array:
	var hp := []
	var db: RefCounted = _weapons(231)
	for i in 9:
		var want: String = LOADOUT.get(i, "")
		var id := 0
		for w in db.weapons:
			if want != "" and String(w.name).replace("-", "").replace(" ", "").to_upper().contains(want):
				id = int(w.id)
				break
		hp.append_array([id, 1 if id != 0 else 0])
	print("loadout ", hp)
	return hp


func _shot(s: Array, out: String, models: String) -> void:
	var pose: Dictionary = s[4]
	var ac: Node3D = tv.aircraft
	_follow = null
	if OS.get_environment("SHOT_AI") == "1":
		for p in tv.ai.pilots:
			if int(p.ent.type_code) == 100 and p.node != null:
				ac = p.node
				_follow = ac
				break
	else:
		var input := {"gear_down": tv.gear_down, "on_ground": not tv.start_airborne}
		ac.update(input, 0.0)
		input.merge(pose, true)
		ac.update(input, 0.0)
		ac.settle()
		_pose = input
	var d := float(s[1])
	var yaw := deg_to_rad(float(s[2]))
	var pitch := deg_to_rad(float(s[3]))
	# Jet frame: nose -Z, up +Y, right +X.
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * d
	var aim: Vector3 = s[5] if s.size() > 5 else Vector3.ZERO  # look-at point, model metres (nose -Z)
	var c: Vector3 = ac.to_global(aim + off)
	var target: Vector3 = ac.to_global(aim)
	_cam_xf = Transform3D(Basis.looking_at(target - c, ac.global_basis.y.normalized()), c)
	_cam_local = ac.global_transform.affine_inverse() * _cam_xf
	_fov = 40.0 if d < 500.0 else 4.0
	var t0 := Time.get_ticks_msec()
	await frames(10)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	for i in 30:
		await process_frame
	var t1 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	var ms := (Time.get_ticks_usec() - t1) / 60000.0
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	var file := "%s_%s.png" % [models, s[0]]
	if OS.get_environment("SHOT_JET") != "":
		file = "%s_%s.png" % [s[0], "after" if models == "detailed" else "before"]
	img.save_png(out.path_join(file))
	print("shot %s %s %.2f ms/frame" % [models, s[0], ms])


## Every frame after the flight scene: our pose over the flight model's (gear, flaps, brakes, afterburner), the camera.
func _place_camera() -> void:
	if tv != null and tv.aircraft != null and not _pose.is_empty():
		tv.aircraft.update(_pose, 1.0 / 60.0)
		tv.aircraft.settle()
		for f in tv.aircraft.flames:
			f.rebuild()  # (the flames drew the flight model's level earlier this frame)
	if tv != null and tv.chase != null:
		tv.chase.global_transform = _follow.global_transform * _cam_local if is_instance_valid(_follow) else _cam_xf
		tv.chase.fov = _fov


class CamPin:
	extends Node
	var place: Callable

	func _process(_delta: float) -> void:
		place.call()
