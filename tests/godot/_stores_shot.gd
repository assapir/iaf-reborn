# Dev helper (not run by tools/test.sh): real-render pictures of the stores, Models Original against Detailed
# (docs/aircraft-models.md §5): loadouts on the ground (the Arming screen's loads, mission 311), a bomb falling and a
# missile in flight (mission 231, airborne); the MiG-29 / MiG-23 (Mission Creator mission 666) with the Soviet stores
# and an AA-10 in flight. Needs a window; run it once per look:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_MODELS=detailed SHOT_OUT=/tmp/shots -- --log-file /tmp/s.log \
#       --path game --resolution 1600x900 -s ../tests/godot/_stores_shot.gd
# Writes SHOT_OUT/<shot>_before.png (Original) or <shot>_after.png (Detailed). SHOT_ONLY=a,b picks cases.
extends "res://../tests/godot/base.gd"

## [case, Jet list id (or the Mission Creator's jet type: mission 666), loads by pylon A..I ([weapon name, count]),
## shots [name, dist, yaw, pitch, aim (jet frame)]].
const CASES := [
	[
		"f16_a",
		1,
		[
			["AIM-9M", 1],
			["AMRAAM", 1],
			["MK-84", 1],
			["2700LB", 1],
			["ECM", 1],
			["2100LB", 1],
			["MK-82", 3],
			["AGM-65", 1],
			["AIM-9L", 1]
		],
		[
			["f16_a_front", 15.0, 35.0, 6.0, Vector3(0, -0.5, 0)],
			["f16_a_left", 7.0, 300.0, -4.0, Vector3(-2.6, -0.7, 0.5)],
			["f16_a_right", 7.0, 60.0, -4.0, Vector3(2.6, -0.7, 0.5)],
		]
	],
	[
		"f16_b",
		1,
		[
			["AIM-9M", 1],
			["AGM88", 1],
			["CBU-87", 1],
			["MK-84L", 1],
			["FLIR", 1],
			["MK-83L", 1],
			["MK-82L", 1],
			["MK-83", 1],
			["AIM-7M", 1]
		],
		[
			["f16_b_left", 7.0, 300.0, -4.0, Vector3(-2.6, -0.7, 0.5)],
			["f16_b_right", 7.0, 60.0, -4.0, Vector3(2.6, -0.7, 0.5)],
			["f16_b_belly", 6.0, 100.0, -12.0, Vector3(0, -0.9, 0.5)],
		]
	],
	[
		"f15",
		0,
		[
			["AIM-9M", 1],
			["AIM-7M", 1],
			["MK-84", 1],
			["AMRAAM", 1],
			["MK-82", 3],
			["AMRAAM", 1],
			["MK-84", 1],
			["AIM-7M", 1],
			["AIM-9M", 1]
		],
		[["f15_front", 18.0, 35.0, 6.0, Vector3(0, -0.5, 0)], ["f15_left", 9.0, 300.0, -4.0, Vector3(-2.8, -0.7, 0.5)]]
	],
	[
		"f4",
		2,
		[
			["AIM-9L", 1],
			["AIM-7F", 1],
			["MK-83", 1],
			["MK-82", 3],
			["CBU-87", 1],
			["MK-82", 3],
			["MK-83", 1],
			["AIM-7F", 1],
			["AIM-9L", 1]
		],
		[["f4_front", 18.0, 35.0, 6.0, Vector3(0, -0.5, 0)], ["f4_left", 9.0, 300.0, -4.0, Vector3(-2.8, -0.7, 0.5)]]
	],
	[
		"mig29",
		{"type": MC_MIG29},
		[
			["AA-2", 1],
			["AA-11", 1],
			["AA-10", 1],
			["AA-10", 1],
			["3500LB", 1],
			["AA-10", 1],
			["AA-10", 1],
			["AA-11", 1],
			["AA-8", 1]
		],
		[
			["mig29_front", 16.0, 35.0, 6.0, Vector3(0, -0.5, 0)],
			["mig29_left", 8.0, 300.0, -4.0, Vector3(-2.6, -0.7, 0.5)]
		]
	],
	[
		"mig23",
		{"type": MC_MIG23},
		[["", 0], ["", 0], ["AA-2", 1], ["AA-8", 1], ["2800LB", 1], ["AA-8", 1], ["AA-2", 1], ["", 0], ["", 0]],
		[
			["mig23_front", 16.0, 35.0, 6.0, Vector3(0, -0.5, 0)],
			["mig23_left", 8.0, 300.0, -4.0, Vector3(-2.2, -0.9, 0.5)]
		]
	],
]
## The Mission Creator's jet types (its TYPE combo: docs/guides/mig29.shots.json).
const MC_MIG23 := 7
const MC_MIG29 := 8

var tv: Node
var _cam := func() -> Transform3D: return Transform3D()
var _fov := 40.0
var out := ""
var tag := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var models := OS.get_environment("SHOT_MODELS")
	settings().models = models if models != "" else "original"
	tag = "after" if settings().models == "detailed" else "before"
	settings().show_info = false
	out = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var only := OS.get_environment("SHOT_ONLY").split(",", false)
	for c in CASES:
		if only.is_empty() or c[0] in only:
			await _loadout_case(c)
	if only.is_empty() or "flight" in only:
		await _flight_case()
	if only.is_empty() or "flight29" in only:
		await _aa10_case()
	settings().jet_id = -1
	settings().arm_loadouts = {}
	check(true, "shots done")


func _ids(mission: int) -> Dictionary:
	var by_name := {}
	for w in load("res://weapons/mission_weapons.gd").create(mission).weapons:
		by_name[String(w.name)] = int(w.id)
	return by_name


func _loadout(mission: int, loads: Array) -> Array:
	var ids := _ids(mission)
	var arm := []
	for l in loads:
		if l[0] != "" and not ids.has(l[0]):
			print("no weapon ", l[0], " in ", ids.keys())
		arm.append([int(ids.get(l[0], 0)), int(l[1]) if ids.has(l[0]) else 0])
	return arm


func _loadout_case(c: Array) -> void:
	var mission := 311
	if c[1] is Dictionary:
		mission = _mc(int(c[1].type))
	else:
		settings().jet_id = int(c[1])
	var arm := _loadout(mission, c[2])
	var al := {}
	for n in 64:
		al[n] = arm
	settings().arm_loadouts = al
	tv = await start_mission(mission)
	await frames(3)
	_pin()
	await seconds(8)  # the ground at full detail
	for s in c[3]:
		var ac: Node3D = tv.aircraft
		var yaw := deg_to_rad(float(s[2]))
		var pitch := deg_to_rad(float(s[3]))
		var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * float(s[1])
		var aim: Vector3 = s[4]
		_cam = func() -> Transform3D:
			var c0: Vector3 = ac.to_global(aim + off)
			return Transform3D(Basis.looking_at(ac.to_global(aim) - c0, ac.global_basis.y.normalized()), c0)
		await _shot(String(s[0]))


## A Mk-84 dropped and an AMRAAM launched from 3000 m (mission 231), each seen from beside 1.2 s later, the clock
## stopped.
func _flight_case() -> void:
	settings().jet_id = 1
	settings().arm_loadouts = {}
	tv = await start_mission(231)
	await frames(3)
	var hp := []
	var ids := _ids(231)
	for n in ["AIM-9M", "AMRAAM", "MK-84", "", "", "", "MK-84", "AMRAAM", "AIM-9M"]:
		hp.append_array([int(ids.get(n, 0)), 1 if ids.has(n) else 0])
	var w = airborne_case(tv, hp)
	tv.fm_stopped = true  # the jet holds still; the clock runs for the stores
	_pin()
	for k in ["bomb", "missile"]:
		tv.frozen = false
		var node: Node3D
		if k == "bomb":
			w._drop_store(2, w.own().pos + w.own().fwd * 3000.0)
			node = w.bombs[-1].node
		else:
			var st: Dictionary = w.stores.station(1)
			var mis = w.launch_homing(st.w, w.body_to_world(st.attach), w.own(), "", 1.0, w._me())
			node = mis.get_meta("node")
		await fly(tv, 1.2 if k == "bomb" else 0.6)
		tv.frozen = true
		var side := 7.0 if k == "bomb" else 6.0
		_cam = func() -> Transform3D:
			var b := node.global_basis.orthonormalized()
			var c0: Vector3 = node.global_position + b.x * side + b.z * side * 0.6 + Vector3.UP * 1.5
			return Transform3D(Basis.looking_at(node.global_position - c0, Vector3.UP), c0)
		await _shot("%s_flight" % k)


## An AA-10 launched from a Mission Creator MiG-29 at 3000 m, seen from beside 0.6 s later, the clock stopped.
func _aa10_case() -> void:
	settings().arm_loadouts = {}
	tv = await start_mission(_mc(MC_MIG29))
	await frames(3)
	var hp := []
	var ids := _ids(666)
	for n in ["AA-11", "AA-11", "AA-10", "AA-10", "", "AA-10", "AA-10", "AA-11", "AA-11"]:
		hp.append_array([int(ids.get(n, 0)), 1 if ids.has(n) else 0])
	var w = airborne_case(tv, hp)
	tv.fm_stopped = true
	_pin()
	tv.frozen = false
	var st: Dictionary = w.stores.station(2)
	var mis = w.launch_homing(st.w, w.body_to_world(st.attach), w.own(), "", 1.0, w._me())
	var node: Node3D = mis.get_meta("node")
	await fly(tv, 0.6)
	tv.frozen = true
	_cam = func() -> Transform3D:
		var b := node.global_basis.orthonormalized()
		var c0: Vector3 = node.global_position + b.x * 6.0 + b.z * 3.6 + Vector3.UP * 1.5
		return Transform3D(Basis.looking_at(node.global_position - c0, Vector3.UP), c0)
	await _shot("aa10_flight")


## Mission 666 from a blank Mission Creator record: one flight of `type` against one of MiG-21s, weapons on
## (as docs/guides/mig29.shots.json); returns 666.
func _mc(type: int) -> int:
	settings().jet_id = -1
	var m: Dictionary = ClassDB.class_call_static("IafMcr", "blank")
	m.count[0] = 1
	m.count[2] = 1
	m.type[0] = type
	m.type[2] = 11
	m.weapons = 1
	m.target = 2
	settings().mc = m
	settings().mc_files = load("res://menu/mission_creator.gd").build(m)
	return 666


func _pin() -> void:
	var cam0: Transform3D = tv.chase.global_transform
	_cam = func() -> Transform3D: return cam0  # (the last case's lambda holds its freed jet)
	for c in tv.get_children():
		if c is CanvasLayer:
			c.visible = false  # the mission's messages
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.views.CHASE, true)
	var pin := CamPin.new()
	pin.place = func():
		if tv != null and tv.chase != null:
			tv.chase.global_transform = _cam.call()
			tv.chase.fov = _fov
	pin.process_priority = 100000
	tv.add_child(pin)


func _shot(name: String) -> void:
	var t0 := Time.get_ticks_msec()
	await frames(10)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	await frames(30)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out.path_join("%s_%s.png" % [name, tag]))
	print("shot ", name, " ", tag)


class CamPin:
	extends Node
	var place: Callable

	func _process(_delta: float) -> void:
		place.call()
