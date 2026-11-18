# Dev helper (not run by tools/test.sh): the 3D cockpit's sharpness with Upscaling (docs/cockpit.md "Cockpit at the
# origin", cockpit_sharp.gdshader), a real render on the runway of SHOT_MISSION (default 2012: the Sufa at Ramon; 2032:
# the F-35I at Nevatim; `-- --at x y alt heading pitch` places the jet in the air, as _cockpit_look_shot.gd), the head
# ahead, after 6 s, the flight then frozen: SHOT_OUT/SHOT_NAME.png. SHOT_SET=key=value,... sets settings
# first (e.g. upscaling=quality); SHOT_HOUR=h the clock (22: night); SHOT_SOFT=1 leaves the sharp layer out (the
# cockpit as before it); SHOT_BENCH=s then prints the mean frame time and the main view's GPU time over s seconds.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_NAME=sufa \
#     SHOT_SET=upscaling=quality -- --log-file <t> --resolution 1920x1080 --path modern-iaf \
#     -s ../modern-iaf/tests/_cockpit_sharp_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	settings().show_info = false
	for kv in OS.get_environment("SHOT_SET").split(",", false):
		var p := kv.split("=")
		var cur = settings().get(p[0])
		settings().set(p[0], (p[1] == "true") if cur is bool else p[1])
	var mission := OS.get_environment("SHOT_MISSION")
	load("res://flight/fly.gd").start(int(mission) if mission != "" else 2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await create_timer(4.0).timeout
	tv = current_scene  # --at starts the flight again in the air
	if OS.get_environment("SHOT_HOUR") != "":
		tv.runtime.misc["0x460"] = float(OS.get_environment("SHOT_HOUR")) * 3600.0 - tv.runtime.now
		tv._tod_t = -INF
		tv.cockpit.night = preload("res://shared/terrain/time_of_day.gd").cockpit_night(tv.time_of_day())
	if OS.get_environment("SHOT_SOFT") == "1" and tv.cockpit_origin != null:
		tv.cockpit_origin._sharp.get_child(1).visible = false  # the sharp layer and its probe left out
		tv.cockpit_origin._quad.material_override.set_shader_parameter("probe", false)
		tv.cockpit_origin._probe.visible = false
	await create_timer(2.0).timeout
	tv.frozen = true  # the same picture and load in every run
	tv.fm_stopped = true
	await frames(10)
	print("scale ", get_root().scaling_3d_scale, " origin ", tv.cockpit_origin != null)
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join(OS.get_environment("SHOT_NAME") + ".png"))
	var secs := float(OS.get_environment("SHOT_BENCH"))
	if secs <= 0.0:
		return
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await frames(30)
	var n := 0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < secs * 1e6:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		n += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("BENCH frames %d frame %.2f ms gpu %.2f ms" % [n, ms, gpu / n])
