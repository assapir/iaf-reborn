# Dev helper (not run by tools/test.sh): real-render captures of the Israel imagery layers (docs/imagery.md §8) at one
# pose, one per layer in SHOT_LAYERS (default original,mapi2015,mapi2015_modern), with the frame rate over 180
# frames (vsync off). Pose with terrain_view's user args (engine metres; `iaf-terrain game <points> lat lon`):
#   IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/shots SHOT_NAME=rishon godot --path game --resolution 1920x1080 \
#       -s ../tests/godot/_imagery_shot.gd -- --at X Y ALT HDG PITCH --freeze
# SHOT_ORBIT="yaw,pitch,dist" draws from the external view instead of the cockpit.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layers := OS.get_environment("SHOT_LAYERS").split(",", false)
	if layers.is_empty():
		layers = PackedStringArray(["original", "mapi2015", "mapi2015_modern"])
	var orbit := OS.get_environment("SHOT_ORBIT").split(",", false)
	for layer in layers:
		Settings().imagery_israel = layer
		change_scene_to_file("res://terrain/terrain_view.tscn")
		await frames(2)
		var tv: Node = null
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
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
		await frames(30)
		var f0 := Engine.get_frames_drawn()
		var m0 := Time.get_ticks_usec()
		for i in 180:
			await process_frame
		var fps := 1e6 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_usec() - m0)
		await RenderingServer.frame_post_draw
		var path := dir.path_join("%s_%s.png" % [OS.get_environment("SHOT_NAME"), layer])
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT %-16s %6.1f fps  layers %s  %s" % [layer, fps, tv.terrain.layers, path])
	Settings().imagery_israel = "original"
