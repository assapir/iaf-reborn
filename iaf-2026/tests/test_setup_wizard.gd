# Modern IAF's setup wizard (iaf-2026/setup/wizard.gd, iaf-2026/docs/setup.md) on an empty scratch assets folder:
#   IAF_ASSETS_DIR=<empty dir> IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_setup_wizard.gd --log-file <temp>
# The four pages in order, in English and in Hebrew (mirrored); the Survey choice off without sheets; the
# Attributions dialog from Welcome (opens, mirrored, the exact Copernicus lines, closes with Esc and with Close); the
# Install page's rows from the sim's plan and their preview; no other game named on any page; abandoned preview
# checks are fetched; a finished run survives a language change, and Back from Install forgets it; the time left's two
# forms; Done's Start the game opens the front end in the same process. It runs no step
# (the real run: iaf-2026/docs/setup.md "Checks"). It needs IAF_ASSETS_DIR (tools/test.sh gives it a scratch
# folder): without it the first check fails and nothing else runs.
extends "res://../tests/godot/base.gd"

## The Copernicus WorldDEM-30 licence's lines (b) and (c), word for word (iaf-2026/docs/terrain.md §5).
const LINE_B := (
	"produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 "
	+ "provided under COPERNICUS by the European Union and ESA; all rights reserved"
)
const LINE_C := (
	"The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for "
	+ "any use of the Copernicus WorldDEM-30"
)


func run() -> void:
	var assets := OS.get_environment("IAF_ASSETS_DIR")
	check(assets != "", "IAF_ASSETS_DIR is set (a scratch folder)")
	if assets == "":
		return
	change_scene_to_file("res://setup/wizard.tscn")
	await frames(5)
	var w: Control = current_scene
	check(w != null and w.PAGES[w.page] == "welcome", "the wizard opens on Welcome")
	check(get_root().title == "Modern IAF — Setup", "the window title")
	var tools: Dictionary = IafSetup.tools()
	check(w.req_ok == (tools.gdal and tools.curl), "Next waits for GDAL and curl (%s)" % tools)
	check(w.next_button.disabled != w.req_ok, "Next follows the requirements")
	check(w.find_child("Requirements", true, false) != null, "the requirements box")
	for lang in ["en", "he"]:
		w.show_page(0)
		w.set_language(lang)
		await frames(2)
		check(
			w.layout_direction == (Control.LAYOUT_DIRECTION_RTL if lang == "he" else Control.LAYOUT_DIRECTION_LTR),
			"%s: the layout's direction" % lang
		)
		check(
			w.page == 0 and w.lang_pick.selected == (1 if lang == "he" else 0),
			"%s: stays on Welcome, the picker shows it" % lang
		)
		check(w.next_button.text == ("הבא" if lang == "he" else "Next"), "%s: Next's label" % lang)
		check(w.PAGES.size() == 4, "%s: four pages" % lang)
		var all_text := ""
		for p in w.PAGES.size():
			w.show_page(p)
			await frames(1)
			all_text += _texts(w)
		for banned in ["Jane", "1998", "iafjets", "reborn"]:
			check(not banned.to_lower() in all_text.to_lower(), "%s: no page names %s" % [lang, banned])
		# The Attributions: a modal dialog from Welcome's button.
		w.show_page(0)
		var d: AcceptDialog = w.credits_dialog
		check(not d.visible, "%s: the Attributions are closed at first" % lang)
		var b: Button = w.find_child("Credits", true, false)
		check(b != null and b.text == ("קרדיט" if lang == "he" else "Attributions"), "%s: the button" % lang)
		b.pressed.emit()
		await frames(2)
		check(d.visible and d.exclusive, "%s: the button opens the modal" % lang)
		check(d.is_layout_rtl() == (lang == "he"), "%s: the modal's direction" % lang)
		var credits := _texts(d)
		check(LINE_B in credits, "%s: Copernicus line (b) verbatim" % lang)
		check(LINE_C in credits, "%s: Copernicus line (c) verbatim" % lang)
		for name in [
			"OpenStreetMap", "Sentinel", "Survey of Israel", "Piper", "FlightGear", "TP-1538", "Heebo", "ikbenraar"
		]:
			check(name in credits, "%s: the attributions name %s" % [lang, name])
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		get_root().push_input(esc)
		await frames(2)
		check(not d.visible, "%s: Esc closes the modal" % lang)
		b.pressed.emit()
		await frames(2)
		d.get_ok_button().pressed.emit()
		await frames(2)
		check(not d.visible and d.get_ok_button().text == ("סגירה" if lang == "he" else "Close"), "%s: Close" % lang)
		if lang == "he":
			for word in ["התקנה", "הקודם", "סיום", "תצלומי לוויין"]:
				check(word in all_text, "he: the approved wording %s" % word)
	check((w.theme.default_font as FontVariation).base_font.get_font_name() == "Heebo", "the Heebo font is loaded")
	w.show_page(1)
	check(
		w.sheets == 0 and w.survey_check.disabled and not w.survey,
		"no Survey sheets: the Survey choice is off, with what it needs"
	)
	check(w.s2_check.button_pressed, "Sentinel-2 everywhere is chosen")
	w._on_back()
	check(w.page == 0, "Back goes to Welcome")
	w.show_page(2)
	check(w.next_button.text == "התקנה" and not w.next_button.disabled, "Install waits for the button")
	check(
		w.rows.keys() == ["sim-terrain", "sim-db", "sim-fm", "sim-own", "sim-airbases", "sim-missions", "sim-scenery"],
		"the sim's steps in order"
	)
	var t := Time.get_ticks_msec()
	while not w.jobs.is_empty() and Time.get_ticks_msec() - t < 30000:
		await process_frame
	check(w.rows["sim-terrain"].state.text == "ירוץ", "an empty root: the terrain will run (the preview)")
	# Two checks at once: the first is abandoned, and both answers are fetched (IafSetup keeps no stale job).
	w._preview()
	w._preview()
	t = Time.get_ticks_msec()
	while not w.jobs.is_empty() and Time.get_ticks_msec() - t < 30000:
		await process_frame
	check(w.jobs.is_empty(), "an abandoned preview check is fetched and dropped")
	# A finished run (as IafSetup.poll ends one), then the language changes: Install and Done still show it.
	w.finished = true
	w.failed = ""
	w.last_steps = IafSetup.sim_plan(false).map(
		func(st): return {"id": st.id, "title": st.title, "state": "done", "fraction": 1.0}
	)
	w._show_result()
	w.set_language("en")
	check(
		w.page == 2 and w.rows["sim-missions"].state.text == "done" and w.next_button.text == "Next",
		"a finished run survives the language change"
	)
	check(w.done_label.text == "Modern IAF is set up.", "Done says so")
	w._on_back()
	check(w.page == 1 and not w.finished, "Back from Install forgets the run")
	w.show_page(2)
	check(
		w.next_button.text == "Install" and w.rows["sim-missions"].state.text != "done",
		"changed choices can be installed"
	)
	# The whole run's time left (IafSetup.poll's left / step / of): unmeasured, the step count; measured, "all steps".
	check(w.total_text({"left": -1.0, "step": 4, "of": 7}) == "All steps: step 4 of 7", "no measurement: step N of M")
	check(w.total_text({"left": 600.0, "step": 0, "of": 0}) == "All steps: about 10 min left", "measured: all steps")
	# Done: Start the game (primary) and Close; no instructions; Start opens the sim's front end in this process.
	w.show_page(3)
	for lang in ["he", "en"]:
		w.set_language(lang)
		await frames(1)
		check(
			w.next_button.text == ("להתחיל לשחק" if lang == "he" else "Start the game") and w.close_button.visible,
			"%s: Done has Start the game and Close" % lang
		)
		check(w.close_button.text == ("סגירה" if lang == "he" else "Close"), "%s: Close's label" % lang)
		check(
			w.next_button.theme_type_variation == "Primary" and w.close_button.theme_type_variation == "",
			"%s: Start the game is the primary button" % lang
		)
		check(not "modern-iaf" in _texts(w), "%s: no instructions to start it" % lang)
	w.next_button.pressed.emit()
	await frames(5)
	check(
		current_scene != null and current_scene.scene_file_path == get_root().get_node("Settings").front_end_scene(),
		"Start opens the front end"
	)


## Every visible text under `n` (labels, buttons, check boxes), one per line.
func _texts(n: Node) -> String:
	var out := ""
	if n is Label or n is Button:
		out += n.text + "\n"
	for c in n.get_children():
		out += _texts(c)
	return out
