# Dev helper (not run by tools/test.sh): pictures of the AWACS (docs/ai.md §24) from Ramon's Scramble start in the air
# with a known MiG-29A 20 km ahead: the radio menu's AWACS page in the cockpit (English and Hebrew), the picture's
# answer in the subtitle band, and the Eitam on its station from a camera beside and above it. SHOT_DIR names the
# folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_awacs_shot.gd
extends "res://../tests/godot/base.gd"

const FC := {"flight": 2, "area": "Hatzerim", "home": "Ramon", "seed": 7, "start": "air"}

var tv: Node
var _cam: Camera3D
var _dir := ""


## The camera 90 m beside, 25 m above and 40 m behind the Eitam, looking at it (global: the floating origin moves
## the scene, terrain_view.gd _rebase).
func _pre_draw() -> void:
	if not is_instance_valid(_cam):
		return
	var e: Dictionary = tv.radio.awacs.eitam()
	var h := deg_to_rad(float(e.heading))
	var fwd := Vector3(sin(h), cos(h), 0)
	var right := Vector3(cos(h), -sin(h), 0)
	var at: Vector3 = tv.world_to_global(e.pos)
	var eye: Vector3 = tv.world_to_global(e.pos - fwd * 40.0 + right * 90.0 + Vector3(0, 0, 25.0))
	var xf := Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
	_cam.global_transform = xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), xf)
	_cam.set_perspective(40.0, 0.5, 60000.0)


func run() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(_dir)
	var fly_gd: GDScript = load("res://flight/fly.gd")
	await require_data()
	var s := settings()
	s.show_info = false
	s.invulnerable = true
	s.sim_jet = "f16i"
	var id := sim_mission("ramon_free")
	fly_gd.prepare_free(id, FC)
	s.free_combat = FC
	tv = await start_mission(id)
	s.mission_files_override = []
	await fly(tv, 8.0)
	var me: Vector3 = tv.player_world()
	var nose := deg_to_rad(float(tv.runtime.player_entity().get("heading", 0.0)))
	var mig: Dictionary = tv.ai.spawn(
		"mig29a", me + Vector3(sin(nose), cos(nose), 0.0) * 20000.0, rad_to_deg(nose) + 180.0, []
	)
	mig.known = true
	await ground_streamed(tv, 30000, 10)
	var sim: Node = tv.addon
	for lang in ["en", "he"]:
		s.language = lang
		sim.set_open(true)
		sim.choose(3)
		await _shot("awacs_page_" + lang)
		sim.set_open(false)
		sim.awacs_pick("picture")
		await fly(tv, 6.0)
		await _shot("awacs_picture_" + lang)
	s.language = "en"
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await _shot("eitam_on_station")
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	print("RESULT PASS" if failures == 0 else "RESULT FAIL")


func _shot(name: String) -> void:
	await frames(30)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join(name + ".png"))
	print("saved " + name)
