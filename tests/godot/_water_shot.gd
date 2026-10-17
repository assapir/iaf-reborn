# Dev helper (not run by tools/test.sh): real-render captures of the Extras "Water" switch (docs/rendering.md §1.3),
# Original then Detailed, at one pose, with the average / p95 frame over 600 frames (vsync off). SHOT_SCALE (e.g. 1.6)
# sets the 3D render scale so the GPU, not the display's refresh, sets the frame (docs/graphics-research.md §1).
# SHOT_BENCH=1 then times the switch in place (_bench). SHOT_REVERSE=1 takes Detailed first (to see the order's own effect on the frame). SHOT_SET="key=value,..." sets more Settings first (e.g. sky=atmospheric). Pose with terrain_view's user args:
#   IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/shots SHOT_NAME=coast godot --path game --resolution 1920x1080 \
#       -s ../tests/godot/_water_shot.gd -- --at X Y ALT HDG PITCH --freeze
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kv in OS.get_environment("SHOT_SET").split(",", false):
		var p := kv.split("=")
		Settings().set(p[0], str_to_var(p[1]) if str_to_var(p[1]) != null else p[1])
	for on in ([true, false] if OS.get_environment("SHOT_REVERSE") != "" else [false, true]):
		Settings().water = on
		change_scene_to_file("res://terrain/terrain_view.tscn")
		await frames(2)
		var tv: Node = null
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		if OS.get_environment("SHOT_SCALE") != "":
			tv.get_viewport().scaling_3d_scale = float(OS.get_environment("SHOT_SCALE"))
		var t0 := Time.get_ticks_msec()
		await frames(20)
		while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		await frames(60)
		var times: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in 600:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
		var sorted := times.duplicate()
		sorted.sort()
		var avg: float = times.reduce(func(a, b): return a + b, 0.0) / times.size()
		await RenderingServer.frame_post_draw
		var path := dir.path_join("%s_%s.png" % [OS.get_environment("SHOT_NAME"), "detailed" if on else "original"])
		root.get_viewport().get_texture().get_image().save_png(path)
		var to_sun: Vector3 = (tv.get_node("Sun") as Node3D).global_transform.basis.z
		print("SUN heading %.0f elevation %.0f" % [fposmod(rad_to_deg(atan2(to_sun.x, -to_sun.z)), 360.0), rad_to_deg(asin(to_sun.y))])
		print("SHOT water %-5s frame %6.2f ms (p95 %6.2f)  %s" % [on, avg, sorted[int(times.size() * 0.95)], path])
	Settings().water = false
	if OS.get_environment("SHOT_BENCH") != "":
		await _bench()


## SHOT_BENCH=1: in the last flight (water on), the global `terrain_water` switched 0 / 1 every 120 frames, 12 pairs:
## the median of the pairs' differences (on − off), robust to other processes on the machine.
func _bench() -> void:
	Settings().water = true
	var tv: Node = current_scene
	tv.apply_render_options()
	await frames(60)
	var diffs: Array[float] = []
	for pair in 12:
		var avg := [0.0, 0.0]
		for on in [0, 1]:
			RenderingServer.global_shader_parameter_set("terrain_water", float(on))
			await frames(20)
			var t0 := Time.get_ticks_usec()
			await frames(120)
			avg[on] = (Time.get_ticks_usec() - t0) / 120000.0
		diffs.append(avg[1] - avg[0])
		print("BENCH pair %2d  off %6.2f  on %6.2f ms" % [pair, avg[0], avg[1]])
	diffs.sort()
	print("BENCH water on - off: median %+.2f ms (quartiles %+.2f / %+.2f)" % [diffs[6], diffs[3], diffs[9]])
	Settings().water = false
