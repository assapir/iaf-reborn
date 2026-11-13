# Modern IAF's text over the flight (flight/flight_ui.gd, modern-iaf/docs/front-end.md §8) in English and Hebrew: the
# mission card (closed at the start, no pause menu either; the title, the objective with the keys as bound, the keys'
# rows; the flight frozen while it is open; Space closes it, the Mission card key opens it again), the radio lines in
# the sim's band (not the original's console), entirely in the game's language but for callsigns and runway
# designators, and the key hint line (shown at the start and briefly after the card closes, hidden while it is open,
# faded out after).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_flight_ui.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Latin words a Hebrew radio line may hold: callsigns and the key names, runway designators (digits and L / R / C).
const LATIN_OK := ["Alpha", "Bravo", "Charlie", "Delta"]


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	for lang in ["en", "he"]:
		s.language = lang
		var tv := await _start(2012)
		var sim_flight: Node = tv.addon
		var ui: Control = sim_flight.ui
		var hint: Control = ui.find_child("Hint", true, false)
		var pause_text := "תפריט השהיה" if lang == "he" else "Pause menu"
		check(hint != null and pause_text in _labels(hint), "%s: the key hint line in the game's language" % lang)
		check(hint.visible and hint.modulate.a > 0.9, "%s: the key hint shows at the start" % lang)
		check(
			not s.card_at_start and ui.card == null and tv.fe_overlay == null and not paused,
			"%s: a clean start: no mission card, no pause menu, the flight runs" % lang
		)
		check(ui.s("mission_card") in _labels(hint), "%s: the key hint names the Mission card key" % lang)
		if lang == "en":
			s.language = "he"  # as the pause menu's Preferences switch it over the flight
			await frames(2)
			hint = ui.find_child("Hint", true, false)
			check("תפריט השהיה" in _labels(hint), "en → he over the flight: the key hint in Hebrew")
			s.language = "en"
			await frames(2)
		ui.open_card(sim_flight._sim)
		await frames(1)
		var card: Control = ui.card
		var texts := _labels(card)
		var tower_key: String = ui.key_name(47).replace(" ", "\u00a0")
		check(paused and card != null, "%s: the card is open and the flight frozen" % lang)
		check(not ui.find_child("Hint", true, false).visible, "%s: no key hint while the card is open" % lang)
		check(
			texts.any(func(t): return tower_key in t and "{key:" not in t),
			"%s: the objective names %s" % [lang, tower_key]
		)
		check(texts.any(func(t): return "25R" in t), "%s: the objective names the runway" % lang)
		check(card.find_child("Keys", true, false).get_child_count() == 13, "%s: the take-off's 13 keys" % lang)
		var title := "המראה" if lang == "he" else "Take-off"
		check(title in texts, "%s: the mission's title" % lang)
		key(ui, KEY_SPACE)
		await frames(1)
		check(ui.card == null and not paused, "%s: Space closes the card and the flight runs" % lang)
		check(ui.find_child("Hint", true, false).visible, "%s: the key hint shows again after the card closes" % lang)
		var h := InputEventKey.new()
		h.keycode = KEY_H
		h.physical_keycode = KEY_H
		h.pressed = true
		tv._unhandled_input(h)
		await frames(1)
		check(ui.card != null, "%s: H opens the card again" % lang)
		ui.close_card()
		await frames(1)
		if lang == "en":  # the hint fades out (real time: the start's 8 s at most)
			await create_timer(ui.HINT_START_S + ui.HINT_FADE_S + 0.3, true, false, true).timeout
			await frames(1)
			check(not ui.find_child("Hint", true, false).visible, "en: the key hint faded out")
		# The tower's answer and the pilot's call: in the band, in the game's language.
		sim_flight.pick("startup")
		await frames(2)
		var band: Array = ui.band_texts()
		check(band.size() >= 2, "%s: the radio lines in the band (%s)" % [lang, band])
		check(tv.cockpit.subtitles.is_empty(), "%s: nothing in the original's console" % lang)
		if lang == "he":
			var radio: Node = tv.radio
			var missing: Array = radio.particles.keys().filter(func(k): return not radio.particles_he.has(k))
			check(missing.is_empty(), "he: every phrase particle has its Hebrew text (%s)" % [missing])
			var rx := RegEx.create_from_string("[A-Za-z]+")
			for line in band:
				var latin := rx.search_all(line).map(func(m): return m.get_string())
				var stray := latin.filter(func(w): return not w in LATIN_OK and not w in ["L", "R", "C"])
				check(stray.is_empty(), 'he: no English word in "%s" (%s)' % [line, stray])
		else:
			check(band.any(func(t): return "tower" in t), "en: the pilot's call (%s)" % [band])
		var panel_ok: bool = Rect2(Vector2.ZERO, ui.size).encloses(ui.find_child("Band", true, false).get_rect())
		check(panel_ok, "%s: the band inside the view" % lang)
		var sizes: Array = ui._lines.map(func(x): return x[0].get_child(0).get_theme_font_size("font_size"))
		check(
			sizes.all(func(z): return z == ui.SUBTITLE_PX), "%s: the band's lines at subtitle size (%s)" % [lang, sizes]
		)
	s.language = "en"
	# The start-up mission opens with its checklist card, not the mission card; the card shows one step.
	s.card_at_start = true
	var tv := await _start(2011)
	await frames(3)
	var ui: Control = tv.addon.ui
	var side: Control = ui.find_child("Checklist", true, false)
	check(ui.card == null and not paused, "start-up: no mission card at the start, the flight runs")
	check(side != null and side.visible, "start-up: the checklist card shows")
	var rows := side.find_children("*", "HBoxContainer", true, false)
	var first := String(tv.addon.checklist[0].en)
	check(rows.size() == 1 and String(rows[0].get_child(0).text).ends_with(first), "start-up: one step, the first")
	check(side.size.x <= 420, "start-up: the card is small (%d px wide)" % side.size.x)
	var info: String = tv.hud_label.text
	check(
		info.begins_with("mission: ramon_startup") and info.ends_with("fps"),
		"the F12 line: mission and FPS (%s)" % info
	)
	s.card_at_start = false


func _start(id: int) -> Node:
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	await process_frame
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	return tv


func _labels(root: Node) -> Array:
	return root.find_children("*", "Label", true, false).map(func(l): return String(l.text))
