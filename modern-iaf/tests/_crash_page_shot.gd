# Dev helper (not run by tools/test.sh): the game manual's picture of the crash page, English and Hebrew
# (modern-iaf/docs/manuals.md §4), 1920 x 1080 in a viewport, a loading fault as the sample:
# SHOT_DIR/crash_page_<lang>.png and the numbered parts' boxes crash_page_<lang>.json (as _front_end_shot.gd).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --resolution 1920x1080 \
#     --path modern-iaf -s ../modern-iaf/tests/_crash_page_shot.gd
extends "res://tests/_front_end_shot.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var CrashPage: GDScript = load("res://menu/crash_page.gd")
	for lang in ["en", "he"]:
		settings().language = lang
		var cp: Control = CrashPage.new()
		cp.what = "A shader failed to compile: the graphics driver refuses it."
		cp.step = "terrain"
		cp.log_path = "~/.local/share/godot/app_userdata/Modern IAF/logs/godot.log"
		vp.add_child(cp)
		await frames(5)
		cp.get_child(1).get_child(0).get_child(0).name = "Title"
		await _shot(vp, dir, "crash_page_" + lang)
		_marks(cp, dir.path_join("crash_page_%s.json" % lang), ["Title", "What", "Step", "Log", "Report", "Quit"])
		cp.queue_free()
		await frames(2)
	settings().language = "en"
