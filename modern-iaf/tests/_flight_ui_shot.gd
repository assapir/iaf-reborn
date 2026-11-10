# Real-render pictures of Modern IAF's text over the flight (modern-iaf/docs/front-end.md §8) and its pause menu, in
# English and Hebrew, in Ramon's take-off:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/fui -- --log-file /tmp/fui.log --path modern-iaf \
#     --resolution 1920x1080 -s ../modern-iaf/tests/_flight_ui_shot.gd
# Writes SHOT_DIR/card_<lang>.png, band_<lang>.png (after the start-up call), pause_<lang>.png and flight10_<lang>.png
# (10 s into the flight: the key hint faded out).
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	s.show_info = false
	for lang in ["en", "he"]:
		s.language = lang
		load("res://flight/fly.gd").start(2012)
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
			await process_frame
			tv = current_scene
		await frames(30)
		var ui: Control = tv.addon.ui
		ui.open_card(tv.addon._sim)
		await frames(10)
		_save(dir.path_join("card_%s.png" % lang))
		ui.close_card()
		tv.addon.pick("startup")
		await frames(20)
		_save(dir.path_join("band_%s.png" % lang))
		tv._esc_key()
		await frames(10)
		_save(dir.path_join("pause_%s.png" % lang))
		tv.close_front_end()
		await create_timer(10.0, true, false, true).timeout
		_save(dir.path_join("flight10_%s.png" % lang))
	s.language = "en"
	check(true, "shots")


func _save(path: String) -> void:
	check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
