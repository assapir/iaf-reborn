# The setup wizard (game/setup/wizard.gd, docs/setup.md) on an empty scratch assets folder:
#   IAF_ASSETS_DIR=<empty dir> IAF_DEFAULT_SETTINGS=1 godot --headless --path game -s \
#     ../tests/godot/test_setup_wizard.gd
# Startup opens the wizard without game data; the pages go in order; a bad file is rejected; Find in a folder finds
# the CD in the background; before a run the Install rows show which steps are up to date; with the English ISO
# (~/Downloads/…/Jane's IAF.iso) a short plan (extract, fonts, missions) runs to Done and a second run is all
# "up to date" (the run's log file in assets/logs), and a third with "redo" ticked on one step runs only that step.
# Without IAF_ASSETS_DIR it does nothing (it never writes into the real assets/).
extends "res://../tests/godot/base.gd"

const ISO := "Downloads/Janes-Combat-Simulations-IAF-Israeli-Air-Force_Win_EN_ISO-Version/Jane's IAF.iso"


func run() -> void:
	var assets := OS.get_environment("IAF_ASSETS_DIR")
	check(assets != "", "IAF_ASSETS_DIR is set (a scratch folder)")
	if assets == "":
		return
	change_scene_to_file("res://menu/startup.tscn")
	await frames(5)
	var w: Control = current_scene
	check(w != null and w.scene_file_path == "res://setup/wizard.tscn", "no game data: startup opens the setup wizard")
	if w == null or w.scene_file_path != "res://setup/wizard.tscn":
		return
	check(get_root().title == "Jane's IAF (reborn) — Setup", "the window title")
	check(w.PAGES[w.page] == "Welcome", "Welcome first")
	w._on_next()
	check(
		w.PAGES[w.page] == "Requirements" and not w.next_button.disabled, "then Requirements, nothing required missing"
	)
	w._on_next()
	check(w.PAGES[w.page] == "Your CD" and w.next_button.disabled, "Your CD: Next waits for the CD")
	w.set_row(w.cd_row, ProjectSettings.globalize_path("res://project.godot"))
	check(not w.cd_row.ok and w.next_button.disabled, "a file that is no CD image is rejected")
	var iso := OS.get_environment("HOME").path_join(ISO)
	if not FileAccess.file_exists(iso):
		print("skipped the run: no English ISO at " + iso)
		return
	# Find in a folder: in the background (frames go on), it fills the empty CD field.
	w.set_row(w.cd_row, "")
	w.scan_folder(iso.get_base_dir())
	var f0 := Engine.get_process_frames()
	var t1 := Time.get_ticks_msec()
	while w.jobs.has("scan") and Time.get_ticks_msec() - t1 < 60000:
		await process_frame
	check(
		w.cd_row.edit.text == iso and Engine.get_process_frames() > f0,
		"Find in a folder finds the English CD (%s)" % w.scan_note.text
	)
	w.set_row(w.cd_row, iso)
	check(w.cd_row.ok and not w.next_button.disabled, "the English CD is accepted")
	w._on_next()
	check(w.PAGES[w.page] == "Optional" and not w.next_button.disabled, "Optional: all may stay empty")
	w.set_row(w.patch_row, iso)
	check(w.next_button.disabled, "a CD image is no patch")
	w.set_row(w.patch_row, "")
	w.set_row(w.hebrew_row, iso)
	check(w.next_button.disabled, "the English CD is no Hebrew CD")
	w.set_row(w.hebrew_row, "")
	check(w.packs_box.visible, "without a Hebrew CD the packs are offered")
	w._on_next()
	check(w.PAGES[w.page] == "Extras", "then Extras")
	w._on_next()
	check(w.PAGES[w.page] == "Summary" and iso in w.summary_label.text, "Summary names the CD")
	w._on_next()
	check(w.PAGES[w.page] == "Install" and w.next_button.text == "Install", "Install waits for the button")
	w.only_steps = PackedStringArray(["fonts", "missions"])
	for pass_name in ["first", "second"]:
		w._on_next()
		var t := Time.get_ticks_msec()
		while not w.finished and Time.get_ticks_msec() - t < 180000:
			await process_frame
		var states := {}
		for id in w.rows:
			states[id] = w.rows[id].state.text
		print("%s run: %s" % [pass_name, states])
		check(w.finished and w.failed == "", "%s run finished without errors" % pass_name)
		var want := "done" if pass_name == "first" else "up to date"
		check(
			states.size() == 3 and states.values().all(func(s): return s == want),
			"%s run: every step %s" % [pass_name, want]
		)
		if pass_name == "first":
			check(FileAccess.file_exists(assets.path_join("setup.json")), "the inputs are saved (setup.json)")
			check(FileAccess.file_exists(assets.path_join("converted/fonts/hud.fnt")), "the fonts are written")
			var lf := FileAccess.get_file_as_string(w.log_file)
			check(
				w.log_file.begins_with(assets.path_join("logs/setup-")) and "fonts: [done]" in lf,
				"the run's log file in assets/logs, with full lines and states (%s)" % w.log_file
			)
			w._on_next()
			check(w.PAGES[w.page] == "Done", "Finish: Done")
			w.finished = false
			w.show_page(w.PAGES.find("Install"))
			var t0 := Time.get_ticks_msec()
			while w.jobs.keys().any(func(j): return j.begins_with("preview")) and Time.get_ticks_msec() - t0 < 60000:
				await process_frame
			await frames(2)
			var shown := ["extract", "fonts", "missions"].map(func(id): return w.rows[id].state.text)
			check(
				shown.all(func(t): return t == "up to date") and w.rows.cockpits.state.text == "will run",
				(
					"before the second run: the steps that ran show up to date, one that did not shows will run (%s)"
					% [shown]
				)
			)
	# Selective redo: only the ticked step runs again.
	w.show_page(w.PAGES.find("Install"))
	w.finished = false
	await frames(2)
	w.rows.fonts.redo.button_pressed = true
	w._on_next()
	var t := Time.get_ticks_msec()
	while not w.finished and Time.get_ticks_msec() - t < 180000:
		await process_frame
	check(
		w.rows.fonts.state.text == "done" and w.rows.missions.state.text == "up to date",
		"redo one step: only it runs (%s, %s)" % [w.rows.fonts.state.text, w.rows.missions.state.text]
	)
