# Dev helper (not run by tools/test.sh): pictures of the range by Ovda (modern-iaf/docs/data-formats.md §5.2) from the
# air, in Ramon's start-up lesson (unscored) with the compiled range and its threats: the bull and the strafe row from
# a free camera, the SAM sites, and the whole range from 3,000 m. SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_ovda_range_shot.gd
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"

var tv: Node
var _cam: Camera3D
var _xf := Transform3D.IDENTITY


func _pre_draw() -> void:
	if is_instance_valid(_cam):
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(50.0, 0.5, 60000.0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
	print("saved ", name)


## The free camera `back` m from `at` (world) on bearing `brg` (degrees), `up` m above the ground, looking at it.
func _look(at: Vector3, brg: float, back: float, up: float) -> void:
	var b := deg_to_rad(brg)
	var eye := at + Vector3(sin(b), cos(b), 0) * back
	var g = tv.mission_ground(eye)
	eye.z = float(g if g != null else at.z) + up
	var tg = tv.mission_ground(at)
	var target: Vector3 = tv.world_to_scene(Vector3(at.x, at.y, float(tg if tg != null else 0.0) + 2.0))
	var e: Vector3 = tv.world_to_scene(eye)
	_xf = Transform3D(Basis.looking_at(target - e, Vector3.UP), e)


func _shot(name: String, at: Vector3, brg: float, back: float, up: float) -> void:
	_look(at, brg, back, up)
	await ground_streamed(tv, 30000, 20)
	await frames(60)
	await _save(name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.show_info = false
	var dir: String = s.assets_dir().path_join(MISSIONS)
	var ranges: Dictionary = s.load_json(dir.path_join("ranges.json"))
	var m: Dictionary = s.load_json(dir.path_join("ramon_startup.json"))
	m.sim["range"] = ranges.ovda
	m.sim["range_threats"] = true
	load("res://flight/fly.gd").set_jet(m)
	s.mission_files_override = [{"name": "ramon_startup", "data": m}]
	tv = await start_mission(int(m.sim.menu_id))
	s.mission_files_override = []
	s.invulnerable = true
	tv.addon.rules = {}
	tv.addon.ui.visible = false
	var rg: Node = tv.addon.get_node("Range")
	while rg.placed.is_empty():
		await process_frame
	var bull: Vector3 = rg.placed.targets[0].world
	var sp: Vector3 = tv.world_to_scene(Vector3(bull.x, bull.y - 4000.0, 3000.0))
	tv.rig.position = sp
	tv.flight.start(s.own_dir(), tv.player.fm_section, sp, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 6.0)  # the hulks re-stood on the finer heights
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await _shot("range_bull", bull, 200.0, 60.0, 25.0)
	await _shot("range_strafe", rg.placed.targets[2].world, 90.0, 160.0, 40.0)
	await _shot("range_bull_and_strafe", bull, 160.0, 900.0, 300.0)
	for i in rg.placed.sites.size():
		var e: Dictionary = rg.placed.sites[i].ents[0]
		await _shot("range_site_%d" % (i + 1), e.world, 200.0, 160.0, 45.0)
	await _shot("range_from_3000m", bull + Vector3(0, 3000, 0), 180.0, 9000.0, 3000.0)
