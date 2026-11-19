# The F-35I Adir's DAS picture and FLC layers (avionics-plan.md slice 7 parts D and E): the DAS format with its forward
# picture, TSD-1 at each FLC layer setting, the display from the pilot's eye with DAS on a portal, and the whole window
# with the helmet's picture off, on the night camera and on the DAS video (fly it at night: `-- --hour 22`). Portal
# pictures are the PCD's glass cropped to portal 0, 1920 wide; the window pictures are the window. A real render: run
# it hidden, one at a time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_adir_s7d_shot.gd --log-file <temp> [-- --hour 22]
extends "res://../tests/godot/base.gd"

var dir := ""
var tv: Node
var pcd


func portal_shot(name: String, f: String) -> void:
	pcd._show(0, f)
	await fly(tv, 0.5)
	await RenderingServer.frame_post_draw
	var img: Image = (pcd.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var r: Rect2 = pcd.portals()[0]
	var crop := img.get_region(Rect2i(r.position.floor(), r.size.ceil()))
	crop.resize(1920, int(1920.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func window_shot(name: String) -> void:
	await fly(tv, 0.5)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var night := OS.get_cmdline_user_args().has("--hour")
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("s7d-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	pcd = tv.cockpit.pcd
	var st0: Dictionary = tv.flight.state()
	var pos: Vector3 = st0.position + Vector3(0, 1500.0, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 220.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.75
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	await fly(tv, 2.0)
	var tag := "night_" if night else ""
	await portal_shot(tag + "das", "DAS")
	# The DAS camera's GPU time (the Iris Xe budget, avionics-plan.md G35): its viewport's measured render time.
	var rid: RID = tv.das_viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var ms := 0.0
	for i in 60:
		await RenderingServer.frame_post_draw
		ms += RenderingServer.viewport_get_measured_render_time_gpu(rid) / 60.0
	print("das gpu ms %.2f" % ms)
	if not night:
		pcd._show(0, "TSD-1")
		pcd.lay.set_focus(0)
		for n in 3:
			await portal_shot("tsd_layer_%d" % n, "TSD-1")
			tv._command([302, 2, 0])
		pcd._show(2, "DAS")
		await window_shot("pcd_pilot_eye_das")
	else:
		pcd._show(0, "TSD-1")
		await window_shot("helmet_off")
		for n in ["helmet_night_camera", "helmet_das"]:
			tv._command([302, 3, 0])
			await window_shot(n)
	tv.queue_free()
	await frames(5)
