# Dev helper (not run by tools/test.sh): pictures of Modern IAF's enemy models (docs/ai.md §15.4, §16.4) on the
# Sufa's range, each from a free camera: an S-300 launcher, the 30N6E on its tower, the Tor-M1, the ZSU-23-4, the
# network's command post and search radar, the 96L6E, the 30N6E2 on its truck, the T-72 and Ural-4320 ground
# targets, and a Shahed-136 in flight. Runs on a tree without the models too (the stand-in shapes: the before
# pictures). SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_enemy_models_shot.gd
extends "res://../tests/godot/base.gd"

var gltf  # load()ed in run(): it uses Settings, which a test script compiles before (base.gd)

var tv: Node
var _cam: Camera3D
var _xf := Transform3D.IDENTITY


func _pre_draw() -> void:
	if is_instance_valid(_cam):
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(45.0, 0.05, 30000.0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
	print("saved ", name)


## The ground height at `at` (world), 0 where none is loaded.
func _ground(at: Vector3) -> float:
	var g = tv.mission_ground(at)
	return float(g) if g != null else 0.0


## The free camera `back` m from `at` (world) on bearing `brg` (degrees), `up` m above the ground, looking at the
## point `aim` m above the ground there (above `at` itself when it is airborne).
func _look(at: Vector3, brg: float, back: float, up: float, aim := 2.0, airborne := false) -> void:
	var b := deg_to_rad(brg)
	var eye := at + Vector3(sin(b), cos(b), 0) * back
	eye.z = (at.z if airborne else _ground(eye)) + up
	var target := Vector3(at.x, at.y, (at.z if airborne else _ground(at)) + aim)
	var e: Vector3 = tv.world_to_scene(eye)
	_xf = Transform3D(Basis.looking_at(tv.world_to_scene(target) - e, Vector3.UP), e)


func _shot(name: String) -> void:
	await ground_streamed(tv, 30000, 20)
	await frames(30)
	await _save(name)


## A radar's antenna turned `yaw` (radians, anticlockwise from the nose) where its model has one, and held there
## (air_defence.gd no longer turns it).
func _aim(ent: Dictionary, yaw: float) -> void:
	ent.erase("antenna")
	var a: Node3D = ent.node.find_child("antenna", true, false)
	if a != null:
		a.rotation.y = yaw


## A unit record's model (target_t72, target_ural) placed as the flight scene places a mission's units.
func _put_model(path: String, at: Vector3, heading: float) -> void:
	var model = gltf.model(gltf.objects_path(path))
	if model == null:
		return
	var n: Node3D = gltf.instance(model)
	tv.add_child(n)
	n.position = tv.world_to_scene(Vector3(at.x, at.y, _ground(at)))
	n.rotation.y = -deg_to_rad(heading)


func run() -> void:
	gltf = load("res://shared/util/gltf.gd")
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.show_info = false
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-models", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	s.invulnerable = true
	tv.addon.ui.visible = false
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	var at := j + Vector3(0, 30000, 0)
	# The tower where the tree has it (spawn's `mast`), else the truck's stand-in.
	var args := ["s300", at, 200.0, [], -1]
	if ad.get_method_argument_count("spawn") > 5:
		args.append(true)
	var s300: Array = ad.callv("spawn", args)
	var truck: Array = ad.spawn("s300", at + Vector3(0, 1200, 0), 200.0)  # the 30N6E2 on its truck
	var tor: Array = ad.spawn("tor", at + Vector3(-320, -420, 0), 160.0)
	var zsu: Array = ad.spawn("zsu", at + Vector3(-200, -480, 0), 200.0)
	var net: Array = ad.spawn_net(at + Vector3(700, 0, 0), at + Vector3(700, 150, 0), [ad.site_of(s300[0])], 90.0)
	var t72 := at + Vector3(-700, 0, 0)
	var units: Dictionary = gltf.get_script_constant_map().get("UNITS", {})
	if units.has("T-72"):
		_put_model(units["T-72"], t72, 30.0)
		_put_model(units["54K6E2"], t72 + Vector3(14, 6, 0), 300.0)
	var salvo: Dictionary = load("res://shared/ai/drones.gd").of(tv).spawn([at + Vector3(0, -2000, 0), at], 1)
	# The jet far south, so the cockpit's view does not matter.
	var sp: Vector3 = tv.world_to_scene(Vector3(j.x, j.y, _ground(j) + 3000.0))
	tv.rig.position = sp
	tv.flight.start(s.own_dir(), tv.player.fm_section, sp, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 4.0)
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	# Frozen from here: every part stands still while the cameras move (the drone too).
	tv.frozen = true
	var d = salvo.ents[0] if not salvo.is_empty() else null
	if d != null:
		var h := deg_to_rad(float(d.heading))
		var w: Vector3 = d.world
		_look(w, rad_to_deg(h) + 120.0, 9.0, 3.0, 0.0, true)
		await _shot("model_shahed136")
	_look(s300[2].world, 230.0, 22.0, 6.0)
	await _shot("model_s300_launcher")
	_look(s300[1].world, 230.0, 45.0, 10.0, 12.0)
	await _shot("model_30n6e_tower")
	_look(tor[0].world, 220.0, 16.0, 5.0)
	await _shot("model_tor_m1")
	_look(zsu[0].world, 220.0, 14.0, 4.0)
	await _shot("model_zsu23_4")
	_look(net[1].world, 220.0, 16.0, 5.0)
	await _shot("model_command_post")
	_look(t72 + Vector3(7, 3, 0), 220.0, 24.0, 7.0)
	await _shot("model_t72_ural_targets")
	# The search radars from the reference photographs' cameras (docs/ai.md §15.4): the 64N6E2 from its front left, its
	# array side on; the 96L6E from its front right.
	_aim(net[0], PI / 2)
	_look(net[0].world, float(net[0].heading) - 35.0, 19.0, 1.6, 4.5)
	await _shot("model_64n6e2")
	_aim(s300[0], -0.5)
	_look(s300[0].world, float(s300[0].heading) + 50.0, 15.0, 1.0, 3.6)
	await _shot("model_96l6e")
	_aim(truck[1], PI * 0.75)
	_look(truck[1].world, float(truck[1].heading) + 35.0, 14.0, 1.7, 3.5)
	await _shot("model_30n6e2")
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
