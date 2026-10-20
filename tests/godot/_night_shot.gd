# Dev helper (not run by tools/test.sh): real-render night captures (docs/rendering.md §4) of mission NIGHT_MISSION
# (default 214, the night start), once per Extras > Night lights value
# in NIGHT_LIGHTS (default original,detailed): the cockpit and the external view (SHOT_ORBIT "yaw,pitch,dist", default
# 150,12,40), saved to SHOT_DIR/night_<mission>_<value>_{cockpit,external}.png with the frame rate
# over 120 frames (vsync off).
#   SHOT_DIR=/tmp/shots IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 -s ../tests/godot/_night_shot.gd
# terrain_view's user args pose it, e.g. `-- --hour 22 --at X Y ALT HDG PITCH --freeze` (--hour: the start time).
extends "res://../tests/godot/base.gd"


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


func run() -> void:
	var dir := _env("SHOT_DIR", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var mission := int(_env("NIGHT_MISSION", "214"))
	var orbit := _env("SHOT_ORBIT", "150,12,40").split(",")
	for value in _env("NIGHT_LIGHTS", "original,detailed").split(","):
		settings().night_lights = value
		var tv = await start_mission(mission)
		tv.frozen = true
		var t0 := Time.get_ticks_msec()
		await frames(20)
		while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		for view in ["cockpit", "external"]:
			if view == "external":
				tv.in_cockpit = false
				tv.views.orbit_heading = deg_to_rad(float(orbit[0])) - PI
				tv.views.orbit_pitch = -deg_to_rad(float(orbit[1]))
				tv.views.dist = float(orbit[2])
				tv._apply_view()
			await frames(30)
			var f0 := Engine.get_frames_drawn()
			var m0 := Time.get_ticks_usec()
			await frames(120)
			var fps := 1e6 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_usec() - m0)
			await RenderingServer.frame_post_draw
			var path := dir.path_join("night_%d_%s_%s.png" % [mission, value, view])
			root.get_viewport().get_texture().get_image().save_png(path)
			print("SHOT %-9s %-8s %6.1f fps  %s" % [value, view, fps, path])
	settings().night_lights = "original"
	print("RESULT PASS")
	quit()
