# Dev helper (not run by tools/test.sh): Modern IAF's time of day (modern-iaf/docs/terrain.md §17), real renders of
# SHOT_MISSION (default the free flight) at SHOT_HOUR (h), posed by terrain_view's user args (`-- --at X Y ALT HDG
# PITCH`): the cockpit, with its HUD, and the chase view (SHOT_ORBIT "yaw,pitch,dist", default 150,8,40), saved to
# SHOT_OUT/<SHOT_NAME>_{cockpit,external}.jpg, and the mean frame time of each view over 4 s (vsync off, "BENCH").
# SHOT_EXPOSURE=k brightens the picture k times (a long exposure). SHOT_DATE=YYYY-MM-DD flies on that date (the
# moon's phase and place, the sun's day; default today's moon on the equinox's sun, as a mission).
# SHOT_SET=key=value,... sets settings first (all settings on:
# antialiasing=taa,upscaling=quality,clouds=volumetric); the free flight's jet: f16_variant=barak, or
# f35i_slot=0,jet_id=0 for the Adir.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_NAME=h22 \
#     SHOT_HOUR=22 -- --log-file <t> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_night_sky_shot.gd \
#     -- --at 670000 3440000 1500 0 0
extends "res://../tests/godot/base.gd"

const TimeOfDay := preload("res://shared/terrain/time_of_day.gd")


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	settings().vsync = false
	settings().show_info = false
	for kv in OS.get_environment("SHOT_SET").split(",", false):
		var p := kv.split("=")
		var cur = settings().get(p[0])
		settings().set(p[0], (p[1] == "true") if cur is bool else type_convert(p[1], typeof(cur)))
	var mission := OS.get_environment("SHOT_MISSION")
	var tv: Node = await start_mission(int(mission) if mission != "" else -1)
	var date := _env("SHOT_DATE", "").split("-")
	if date.size() == 3:
		TimeOfDay.year = int(date[0])
		TimeOfDay.day = IafFreeCombat.day_of_year(TimeOfDay.year, int(date[1]), int(date[2]))
		TimeOfDay.utc_offset = IafFreeCombat.utc_offset(TimeOfDay.year, int(date[1]), int(date[2]))
	var hour := float(_env("SHOT_HOUR", "11"))
	if tv.runtime != null:
		tv.runtime.misc["0x460"] = hour * 3600.0 - tv.runtime.now
	else:
		tv._sim_time = hour * 3600.0 - 39600.0  # a free flight's clock (_effects_shot.gd)
	tv._tod_t = -INF
	tv.cockpit.night = TimeOfDay.cockpit_night(tv.time_of_day())
	# The overlays off (messages, labels); the cockpit's layer stays: the HUD is drawn there.
	for c in tv.get_children():
		if c is CanvasLayer and c.name != "CockpitLayer":
			c.visible = false
	# SHOT_EXPOSURE=k: a photographer's longer exposure, the picture k times brighter (the game draws k = 1).
	var env: Environment = (tv.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.tonemap_exposure *= float(_env("SHOT_EXPOSURE", "1"))
	tv.frozen = true
	tv.fm_stopped = true
	await ground_streamed(tv, 30000, 20)
	# The towns' lights all made, their haze last (city_lights.gd): a picture before shows the town half lit.
	var lit_t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - lit_t < 60000:
		var cl: Node = tv.get_node_or_null("CityLights")
		if cl == null or not cl.visible or cl._glow != null and not cl._blocks.values().any(func(b): return b.asking):
			break
		await process_frame
	var o := _env("SHOT_ORBIT", "150,8,40").split(",")
	var dir := _env("SHOT_OUT", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for view in ["cockpit", "external"]:
		if view == "external":
			tv.in_cockpit = false
			tv.views.orbit_heading = deg_to_rad(float(o[0])) - PI
			tv.views.orbit_pitch = -deg_to_rad(float(o[1]))
			tv.views.dist = float(o[2])
			tv._apply_view()
		await create_timer(3.0).timeout  # the auto-exposure settles
		var n := 0
		var gpu := 0.0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 4e6:
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			n += 1
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var path := dir.path_join("%s_%s.jpg" % [_env("SHOT_NAME", "shot"), view])
		img.save_jpg(path, 0.88)
		print("BENCH %s %s frame %.2f ms gpu %.2f ms  %s" % [_env("SHOT_NAME", "shot"), view, ms, gpu / n, path])
	print("RESULT PASS")
	quit()
