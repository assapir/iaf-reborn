# Real-render pictures of Modern IAF's text over the flight (modern-iaf/docs/front-end.md §8) and its pause menu, in
# English and Hebrew, in Ramon's take-off:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/fui -- --log-file /tmp/fui.log --path modern-iaf \
#     --resolution 1920x1080 -s ../modern-iaf/tests/_flight_ui_shot.gd
# Writes SHOT_DIR/band_<lang>.png (after the start-up call), pause_<lang>.png, prefs_<lang>.png (its Settings, the
# Graphics section), keys_<lang>.png (the Keys screen), accomplished_<lang>.png (a training mission's pass:
# sim_flight.gd _accomplished) and flight10_<lang>.png (10 s into the flight). SHOT_SIZE=1920x1080: the pictures at
# that size whatever the window's.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	# SHOT_SIZE (e.g. 1920x1080): the picture's size whatever the window's (a laptop screen caps the window's height).
	var size := OS.get_environment("SHOT_SIZE").split("x")
	if size.size() == 2:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(int(size[0]), int(size[1]))
	var s := settings()
	s.show_info = false
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"  # the pictures' sample pilot (_front_end_shot.gd)
		load("res://flight/fly.gd").start(2012)
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
			await process_frame
			tv = current_scene
		await frames(30)
		tv.addon.pick("startup")
		await frames(20)
		_save(dir.path_join("band_%s.png" % lang))
		tv._esc_key()
		await frames(10)
		_save(dir.path_join("pause_%s.png" % lang))
		# The Settings over the flight: its Graphics section (the longest, VSync its last row).
		tv.fe_overlay.pref_group = "graphics"
		tv.fe_overlay.show_page("prefs")
		await frames(10)
		_save(dir.path_join("prefs_%s.png" % lang))
		tv.fe_overlay.show_page("keys")
		await frames(10)
		_save(dir.path_join("keys_%s.png" % lang))
		tv.close_front_end()
		tv.addon._accomplished()
		await frames(10)
		_save(dir.path_join("accomplished_%s.png" % lang))
		tv.close_front_end()
		await create_timer(10.0, true, false, true).timeout
		_save(dir.path_join("flight10_%s.png" % lang))
	s.language = "en"
	check(true, "shots")


func _save(path: String) -> void:
	check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
