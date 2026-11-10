# Real-render pictures of Modern IAF's setup wizard, every page in English and Hebrew (modern-iaf/docs/setup.md):
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/wiz -- --log-file /tmp/wiz.log --path modern-iaf \
#     --resolution 1100x720 -s ../modern-iaf/tests/_setup_wizard_shot.gd
# Writes SHOT_DIR/<page>_<lang>.png and attributions_<lang>.png (the dialog over Welcome). The Install page shows
# the preview of the assets root (IAF_ASSETS_DIR or the repo's assets/); nothing runs.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	change_scene_to_file("res://setup/wizard.tscn")
	await frames(5)
	var w: Control = current_scene
	for lang in ["en", "he"]:
		w.show_page(0)
		w.set_language(lang)
		for p in w.PAGES.size():
			w.show_page(p)
			if w.PAGES[p] == "install":
				var t := Time.get_ticks_msec()
				while not w.jobs.is_empty() and Time.get_ticks_msec() - t < 60000:
					await process_frame
			if w.PAGES[p] == "done":
				w.done_label.text = w.s("set_up")
			await frames(8)
			var path: String = dir.path_join("%s_%s.png" % [w.PAGES[p], lang])
			check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
			if w.PAGES[p] == "welcome":
				# The Attributions dialog over Welcome.
				w.credits_dialog.popup_centered(Vector2i(900, 560))
				await frames(8)
				path = dir.path_join("attributions_%s.png" % lang)
				check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
				w.credits_dialog.hide()
	w.set_language("en")
