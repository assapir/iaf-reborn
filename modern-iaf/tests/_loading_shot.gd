# Dev helper (not run by tools/test.sh): Modern IAF's loading screen (flight/loading_screen.gd) in a real render, for
# the Ramon take-off mission in the ground's step at half of it, in English and in Hebrew: SHOW_OUT/loading_en.png,
# loading_he.png. SHOT_SIZE=1920x1080: the pictures at that size whatever the window's (a laptop caps its height).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> -- --log-file <temp> --resolution 1280x720 \
#     --path modern-iaf -s ../modern-iaf/tests/_loading_shot.gd
extends "res://../tests/godot/base.gd"

const MISSION := "converted/modern-iaf/missions/ramon_takeoff.json"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var size := OS.get_environment("SHOT_SIZE").split("x")
	if size.size() == 2:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(int(size[0]), int(size[1]))
	var s := settings()
	var out := OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSION))
	check(not m.is_empty(), "the mission %s" % MISSION)
	s.mission_files_override = [{"name": "ramon_takeoff", "data": m}]
	for lang in ["en", "he"]:
		s.language = lang
		var screen: Control = load(s.loading_screen_scene()).new()
		root.add_child(screen)
		screen.step("terrain", 0.5)
		await frames(90)
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out.path_join("loading_%s.png" % lang))
		check(true, "loading_%s.png" % lang)
		screen.free()
	s.mission_files_override = []
	s.language = "en"
