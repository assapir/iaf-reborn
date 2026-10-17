# Dev helper (not run by tools/test.sh): real-render captures at an airbase (docs/rendering.md §7, docs/imagery.md
# §3), one per configuration in SHOT_CONFIGS ("name:key=value,key=value;name2:…", Settings keys; default
# "now:" = the settings as they are), saved to SHOT_DIR/SHOT_NAME_<name>.png, with the average frame over 300
# frames (vsync off). SHOT_SCALE (e.g. 2.0) sets the 3D render scale so the GPU, not the display, sets the frame. SHOT_ORBIT="yaw,pitch,dist" draws from the external view. SHOT_BENCH=1 then times the global
# `terrain_airbases` 0 / 1 in place (12 pairs of 120 frames; the median difference). Pose with terrain_view's args:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/s SHOT_NAME=david_final SHOT_CONFIGS="o:airbases=\"original\";d:airbases=\"detailed\"" \
#       -- --log-file /tmp/g.log --path game --resolution 1920x1080 -s ../tests/godot/_airbase_shot.gd -- --mission 311 --at X Y ALT HDG PITCH --freeze
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	Settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var configs := OS.get_environment("SHOT_CONFIGS")
	var orbit := OS.get_environment("SHOT_ORBIT").split(",", false)
	var tv: Node = null
	for conf in (configs if configs != "" else "now:").split(";", false):
		var name_kv := conf.split(":", true, 1)
		for kv in name_kv[1].split(",", false):
			var p := kv.split("=")
			Settings().set(p[0], str_to_var(p[1]))
		change_scene_to_file("res://terrain/terrain_view.tscn")
		await frames(2)
		tv = null
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		if OS.get_environment("SHOT_SCALE") != "":
			tv.get_viewport().scaling_3d_scale = float(OS.get_environment("SHOT_SCALE"))
		if orbit.size() == 3:
			tv.in_cockpit = false
			tv.views.orbit_heading = deg_to_rad(float(orbit[0])) - PI
			tv.views.orbit_pitch = -deg_to_rad(float(orbit[1]))
			tv.views.dist = float(orbit[2])
			tv._apply_view()
		var t0 := Time.get_ticks_msec()
		await frames(20)
		while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		await frames(60)
		var m0 := Time.get_ticks_usec()
		await frames(300)
		var ms := (Time.get_ticks_usec() - m0) / 300000.0
		await RenderingServer.frame_post_draw
		var path := dir.path_join("%s_%s.png" % [OS.get_environment("SHOT_NAME"), name_kv[0]])
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT %-10s frame %6.2f ms  %s" % [name_kv[0], ms, path])
	if OS.get_environment("SHOT_BENCH") != "":
		await _bench()
	print("RESULT PASS")
	quit()


## In the last flight: the global `terrain_airbases` switched 0 / 1 every 120 frames, 12 pairs; the median of the
## pairs' differences (on − off), robust to other processes on the machine.
func _bench() -> void:
	var diffs: Array[float] = []
	for pair in 12:
		var avg := [0.0, 0.0]
		for on in [0, 1]:
			RenderingServer.global_shader_parameter_set("terrain_airbases", float(on))
			await frames(20)
			var t0 := Time.get_ticks_usec()
			await frames(120)
			avg[on] = (Time.get_ticks_usec() - t0) / 120000.0
		diffs.append(avg[1] - avg[0])
		print("BENCH pair %2d  off %6.2f  on %6.2f ms" % [pair, avg[0], avg[1]])
	diffs.sort()
	print("BENCH airbases on - off: median %+.2f ms (quartiles %+.2f / %+.2f)" % [diffs[6], diffs[3], diffs[9]])
