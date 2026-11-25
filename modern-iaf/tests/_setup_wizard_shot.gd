# Real-render pictures of Modern IAF's setup wizard, every page in English and Hebrew (modern-iaf/docs/setup.md):
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/wiz -- --log-file /tmp/wiz.log --path modern-iaf \
#     --resolution 1100x720 -s ../modern-iaf/tests/_setup_wizard_shot.gd
# Writes SHOT_DIR/<page>_<lang>.png and attributions_<lang>.png (the dialog over Welcome), install_skipped_<lang>.png (a
# finished run with the buildings' step skipped for want of GDAL) and install_remove_<lang>.png (that step, built,
# unticked: Remove its data?), both staged in the page alone, nothing written. The Install page shows
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
			if w.PAGES[p] == "install":
				await _install_states(w, dir, lang)
			if w.PAGES[p] == "welcome":
				# The Attributions dialog over Welcome.
				w.credits_dialog.popup_centered(Vector2i(900, 560))
				await frames(8)
				path = dir.path_join("attributions_%s.png" % lang)
				check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
				w.credits_dialog.hide()
	w.set_language("en")


## The game manual's two Install states (modern-iaf/docs/manuals.md §4), staged on the page: a finished run with the
## buildings' step skipped, then that step built and unticked with its remove question (its downloads its own).
## Nothing runs or is written.
func _install_states(w: Control, dir: String, lang: String) -> void:
	var id := "sim-scenery"
	var steps := []
	for st in IafSetup.sim_plan(w.survey_id()):
		var skip: bool = st.id == id
		steps.append(
			{
				"id": st.id,
				"state": "skipped" if skip else "done",
				"fraction": 0.0 if skip else 1.0,
				"detail": "GDAL is needed (gdalwarp, ogr2ogr)" if skip else ""
			}
		)
	w.finished = true
	w._finished({"steps": steps})
	w._update()
	await frames(8)
	var path := dir.path_join("install_skipped_%s.png" % lang)
	check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
	w.finished = false
	w.last_steps = []
	w._fill_rows(IafSetup.sim_plan(w.survey_id()))
	w._note("")
	w.optional[id] = w.optional.get(id, {"download": 1.2e9, "sources": 1.9e9, "shared": false}).merged(
		{"built": true, "disk": 1.2e9, "shared": false, "sources": 1.9e9}, true
	)
	w._show_sizes(id)
	w.rows[id].include.set_pressed_no_signal(false)
	w.ask_remove(id)
	w._update()
	await frames(8)
	path = dir.path_join("install_remove_%s.png" % lang)
	check(get_root().get_texture().get_image().save_png(path) == OK, "saved " + path)
	w.remove_dialog.hide()
	w.rows[id].include.set_pressed_no_signal(true)
