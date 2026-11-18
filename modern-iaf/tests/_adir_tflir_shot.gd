# The F-35I Adir's TFLIR picture for its manual (modern-iaf/docs/manuals.md "The displays' pictures"): the FLIR page
# key starts the camera of the default layout's TFLIR, aimed at the range's Target 1, zoomed, the laser firing
# (`tflir`, the PCD's glass cropped to the portal, 1920 wide). A real render: run it hidden, one at a time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_adir_tflir_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var dir := ""
var tv: Node
var w
var c
var pcd


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


## Portal `i`, cropped from the PCD's glass, 1920 wide.
func portal_shot(name: String, i: int) -> void:
	await fly(tv, 0.5)
	await RenderingServer.frame_post_draw
	var img: Image = (pcd.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var r: Rect2 = pcd.portals()[i]
	var crop := img.get_region(Rect2i(r.position.floor(), r.size.ceil()))
	crop.resize(1920, int(1920.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("tflir-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	pcd = c.pcd
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	var t1: Dictionary = {}
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == "Target 1":
			t1 = e
	# 12 km south of Target 1 at 3,000 m, heading north.
	var g = tv.mission_ground(Vector3(t1.world.x, t1.world.y, 0.0))
	var gz := float(g if g != null else 0.0)
	var at := Vector3(t1.world.x, t1.world.y - 12000.0, gz + 3000.0)
	_put(tv.world_to_scene(at), Vector3(0, 0, -220), 0.0)
	await fly(tv, 1.0)
	# The FLIR page key with TFLIR on the fourth portal: the camera starts; on the hulks, zoomed, the laser firing.
	tv._command([90, 6, 0])
	await fly(tv, 0.5)
	w.eo.start(w.eo.FLIR, true, Vector3(t1.world.x, t1.world.y, gz), w.now)
	w.mfd_event(0x14)
	w.mfd_event(0x14)
	w.mfd_event(0x6a)
	await fly(tv, 1.5)
	check(w.eo.mode == w.eo.FLIR and c.eo.get("camera", false), "the TFLIR's camera runs")
	await portal_shot("tflir", 3)
	tv.queue_free()
	await frames(5)
