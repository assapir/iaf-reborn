# Dev helper (not run by tools/test.sh): real-render captures of the Israel imagery layers (docs/imagery.md §8) at one
# pose, one per layer in SHOT_LAYERS (default original,mapi2015,mapi2015_modern), with the frame rate over 180
# frames (vsync off). Pose with terrain_view's user args (engine metres; `iaf-terrain game <points> lat lon`):
#   IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/shots SHOT_NAME=rishon godot --path iaf-reborn --resolution 1920x1080 \
#       -s ../tests/godot/_imagery_shot.gd -- --at X Y ALT HDG PITCH --freeze
# SHOT_ORBIT="yaw,pitch,dist" draws from the external view instead of the cockpit (yaw 180: looking along the
# heading). SHOT_SCENERY=on: with Scenery (docs/scenery.md). SHOT_SET=key=value,...: other settings (e.g.
# ground_roads=detailed,night_lights=detailed; show_info=false for the docs).
# SHOT_HIDE_JET=1: the player's jet hidden (pictures for the docs).
# SHOT_HOUR=h: the clock of a free flight (no mission; e.g. 22 for the city lights).
# IAF 2026's theatre (modern-iaf/docs/scenery.md): --path modern-iaf, SHOT_LAYERS=sim (its ground is its own), UTM metres.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layers := OS.get_environment("SHOT_LAYERS").split(",", false)
	if layers.is_empty():
		layers = PackedStringArray(["original", "mapi2015", "mapi2015_modern"])
	var orbit := OS.get_environment("SHOT_ORBIT").split(",", false)
	if OS.get_environment("SHOT_SCENERY") != "":
		settings().scenery = OS.get_environment("SHOT_SCENERY")
	for kv in OS.get_environment("SHOT_SET").split(",", false):
		var p := kv.split("=")
		if p.size() != 2 or not p[0] in settings():
			push_error("SHOT_SET: %s is not key=value of a setting" % kv)
			continue
		var cur = settings().get(p[0])
		var v = int(p[1]) if cur is int else (float(p[1]) if cur is float else p[1])
		settings().set(p[0], (p[1] == "true") if cur is bool else v)
	for layer in layers:
		if layer != "sim":  # the sim's ground is its own: no imagery setting (a "sim" layer would be refused)
			settings().imagery_israel = layer
		change_scene_to_file("res://shared/terrain/terrain_view.tscn")
		await frames(2)
		var tv: Node = null
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		if OS.get_environment("SHOT_HIDE_JET") == "1" and tv.aircraft != null:
			# Its children: the view shows the aircraft node again every frame outside the cockpit.
			for c in tv.aircraft.get_children():
				if c is Node3D:
					c.visible = false
		if OS.get_environment("SHOT_HOUR") != "" and tv.runtime == null:
			tv._sim_time = float(OS.get_environment("SHOT_HOUR")) * 3600.0 - 39600.0
			tv._tod_t = -INF
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
	if layers[0] != "sim":
		settings().imagery_israel = "original"
