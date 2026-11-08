# Dev helper (not run by tools/test.sh): Modern IAF's loading screen (flight/loading_screen.gd) in a real render, for
# the Ramon take-off mission at 60 %, in English and in Hebrew: SHOW_OUT/loading_en.png, loading_he.png.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> -- --log-file <temp> --resolution 1280x720 \
#     --path iaf-2026 -s ../iaf-2026/tests/_loading_shot.gd
extends "res://../tests/godot/base.gd"

const MISSION := "converted/iaf-2026/missions/ramon_takeoff.json"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
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
		screen.progress = 0.6
		await frames(90)
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out.path_join("loading_%s.png" % lang))
		check(true, "loading_%s.png" % lang)
		screen.free()
	s.mission_files_override = []
	s.language = "en"
