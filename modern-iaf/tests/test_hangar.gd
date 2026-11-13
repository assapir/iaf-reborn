# Modern IAF's Hangar (modern-iaf/docs/front-end.md §12), headless, in English and Hebrew: the first screen; the jets'
# full names, the F-15s greyed and out of reach, the jet flown last picked (else the first), a click picking another
# (Settings.sim_jet, the F-16 switch) with its card and its model; the card's facts and training; Missions and campaign
# greyed; the Preferences in the top bar; the mirrored layout in Hebrew; Fly opening the jet's missions with the
# Hangar crumb back; Esc on the Hangar asking to quit; the turntable rendering only while shown.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_hangar.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	load("res://tests/test_front_end.gd").fixture(s)
	s.pilot_name = "Noa Golan"
	s.sim_jet = ""
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	check(fe.page == "hangar", "the first screen is the Hangar")
	_tails_painted()
	check(s.sim_jet == "f16i", "no jet picked yet: the first, the Sufa, picked")
	for lang in ["en", "he"]:
		s.language = lang
		await walk(fe, lang)
	s.language = "en"
	s.sim_jet = "f35i"
	fe.show_page("hangar")
	await frames(2)
	check((fe.find_child("adir", true, false) as Button).button_pressed, "the jet picked last is picked on entry")
	key(fe, KEY_ESCAPE)
	await frames(2)
	var q := fe.find_child("Modal", true, false)
	check(fe.page == "hangar" and q != null and _has(q, "Quit the sim?"), "Esc on the Hangar asks to quit")
	fe.close_modal()
	await frames(1)
	var tt: TextureRect = fe.find_child("Turntable", true, false)
	# Headless, the window reports itself minimised: the turntable is told to render anyway, as in a real window.
	tt.ignore_minimised = true
	tt._update_mode()
	check(
		tt.vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS and tt.is_processing(),
		"the turntable renders and turns while it can be seen"
	)
	tt.ignore_minimised = false
	tt._update_mode()
	check(tt.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "minimised, the turntable renders nothing")
	tt.ignore_minimised = true
	tt.hide()
	check(
		tt.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and not tt.is_processing(),
		"hidden, the turntable renders nothing"
	)
	tt.ignore_minimised = false
	s.pilot_name = ""


func walk(fe: Control, lang: String) -> void:
	var he := lang == "he"
	var s := settings()
	s.sim_jet = "f16i"
	fe.show_page("hangar")
	await frames(3)
	check(fe.layout_direction == (Control.LAYOUT_DIRECTION_RTL if he else Control.LAYOUT_DIRECTION_LTR), lang + ": dir")
	check(_has(fe, "דת״ק" if he else "Hangar"), "%s: the crumb is the Hangar" % lang)
	var names := ["F-16I סופה", "F-16D ברק", "F-35I אדיר", "F-15I רעם", "F-15C בז"]
	if not he:
		names = ["F-16I Sufa", "F-16D Barak", "F-35I Adir", "F-15I Ra'am", "F-15C Baz"]
	var rows: Array = fe.find_child("Jets", true, false).get_children().filter(func(c): return c is Button)
	check(rows.size() == 5, "%s: five jets in the list" % lang)
	for i in rows.size():
		check(_has(rows[i], names[i]), "%s: row %d is %s" % [lang, i, names[i]])
		check(rows[i].disabled == (i >= 3), "%s: %s %s" % [lang, names[i], "greyed" if i >= 3 else "flyable"])
		check(rows[i].focus_mode == (Control.FOCUS_NONE if i >= 3 else Control.FOCUS_ALL), lang + ": focus " + names[i])
	check(not _has_part(fe, "later version") and not _has_part(fe, "בגרסה"), "%s: no text on the greyed jets" % lang)
	check(rows[0].button_pressed and not rows[1].button_pressed, "%s: the Sufa picked" % lang)
	var card: Control = fe.find_child("JetCard", true, false)
	check(_has(card, names[0]), "%s: the card names the Sufa" % lang)
	# The same three facts of this jet for every jet: squadron, base, tail number; no type facts.
	var fact_labels := ["טייסת", "בסיס", "מספר זנב"] if he else ["Squadron", "Base", "Tail number"]
	check(_facts(card) == fact_labels, "%s: the facts %s" % [lang, _facts(card)])
	check(_has(card, "201 האחת" if he else "201 The One") and _has(card, "רמון" if he else "Ramon"), lang + ": Sufa's")
	check(_has(card, "846"), "%s: the Sufa's tail number as painted" % lang)
	for t in ["23,582", "511", "104", "Gun rounds", "Radar range", "Maximum weight"]:
		check(not _has_part(card, t), "%s: no %s on the card" % [lang, t])
	if he:
		await _code_first(fe, "the Hangar")
	check(_has_part(card, "2 מתוך 2" if he else "2 of 2 passed"), "%s: the training's progress" % lang)
	var last: Label = fe.find_child("LastFlight", true, false)
	check(last.text.contains("המראה" if he else "Take-off"), "%s: the last flight: %s" % [lang, last.text])
	var camp: Button = fe.find_child("Campaign", true, false)
	check(camp.disabled and camp.focus_mode == Control.FOCUS_NONE and camp.tooltip_text == "", lang + ": campaign")
	check(fe.find_child("Preferences", true, false) is Button, "%s: the Preferences in the top bar" % lang)
	check(fe.find_child("PilotBlock", true, false) is Button, "%s: the pilot in the top bar" % lang)
	check(fe.find_child("pilot_log", true, false) == null, "%s: no Pilot log entry" % lang)
	var fly: Button = fe.find_child("Fly", true, false)
	check(fe.get_viewport().gui_get_focus_owner() == fly, "%s: Fly focused" % lang)
	# Hebrew mirrors: the list at the right, the card at the left.
	var list_x: float = fe.find_child("Jets", true, false).get_global_rect().get_center().x
	check((list_x > card.get_global_rect().get_center().x) == he, "%s: the list at the inline start" % lang)
	# A click on the Barak picks it: the F-16 switch, its card, its model; the F-15I takes no click.
	rows[3].pressed.emit()
	await frames(1)
	check(s.sim_jet == "f16i", "%s: a greyed jet takes no pick" % lang)
	rows[1].pressed.emit()
	await frames(2)
	check(s.sim_jet == "f16d" and s.f16_variant == "barak", "%s: the Barak picked (the F-16 switch)" % lang)
	card = fe.find_child("JetCard", true, false)
	check(_has(card, names[1]) and _has(card, "547"), "%s: the Barak's card" % lang)
	check(_facts(card) == fact_labels, "%s: the Barak's facts the same" % lang)
	if he:
		await _code_first(fe, "the Barak")
	check((fe.find_child("barak", true, false) as Button).button_pressed, "%s: its row lit" % lang)
	var tt: TextureRect = fe.find_child("Turntable", true, false)
	check(tt != null and not tt.failed, "%s: the Barak's model loaded" % lang)
	(fe.find_child("adir", true, false) as Button).pressed.emit()
	await frames(2)
	tt = fe.find_child("Turntable", true, false)
	check(s.sim_jet == "f35i" and tt != null and not tt.failed, "%s: the Adir picked, its model loaded" % lang)
	check(_facts(fe.find_child("JetCard", true, false)) == fact_labels, "%s: the Adir's facts the same" % lang)
	if he:
		await _code_first(fe, "the Adir")
	# Fly: the jet's missions and briefing; its Hangar crumb back.
	s.sim_jet = "f16i"
	fe.show_page("hangar")
	await frames(1)
	(fe.find_child("Fly", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "mission" and fe.find_child("Mission1", true, false) != null, "%s: Fly opens the missions" % lang)
	check(_has(fe, names[0]), "%s: the crumbs name the jet" % lang)
	if he:
		await _code_first(fe, "the missions")
	(fe.find_child("Crumb_hangar", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "hangar", "%s: the Hangar crumb goes back" % lang)
	fe.show_page("mission")
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "hangar", "%s: Esc on the missions: the Hangar" % lang)


## The texts as read: without the isolates that keep Latin codes left to right in a Hebrew line.
func _texts(root: Node) -> Array:
	return (
		root
		. find_children("*", "", true, false)
		. filter(func(c): return c is Label or c is Button)
		. map(func(c): return c.text.replace("\u2066", "").replace("\u2069", "").replace("\u200f", ""))
	)


## The card's fact labels in order.
func _facts(card: Control) -> Array:
	return (
		card
		. find_child("Facts", true, false)
		. find_children("*", "Label", true, false)
		. filter(func(l): return l.theme_type_variation == "Small")
		. map(func(l): return l.text)
	)


## In Hebrew every label naming a jet ("F-16I סופה") reads its code first: the code at the label's right (the user,
## A31: it showed "סופה F-16I", the code read last). The list, the card, the faint name, the crumbs, the pilot line.
func _code_first(fe: Control, where: String) -> void:
	await frames(1)
	var n := 0
	for l: Label in fe.find_children("*", "Label", true, false):
		var t := l.text.replace("\u200f", "")
		for code in ["F-16I", "F-16D", "F-35I", "F-15I", "F-15C"]:
			var i := t.find(code + " ")
			if i < 0 or not l.is_visible_in_tree():
				continue
			var at := l.text.find(code)
			var heb := l.text.find(" ", at) + 1
			n += 1
			check(
				l.get_character_bounds(at).position.x > l.get_character_bounds(heb).position.x,
				'he, %s: "%s" reads its code first' % [where, t]
			)
	check(n >= 1, "he, %s: jet names found (%d)" % [where, n])


## Each jet's unit record's tail number is the number painted on its model (the user, A31), and its squadron (its base
## file's `squadrons`) the one whose art the model wears (the user, 2026-11-13: "change the string"): as the model's
## sources record them.
func _tails_painted() -> void:
	var srcs := {
		"f16i": ["res://shared/extra/models/f16/SOURCES.md", "F-16I %s", "llrm", "%d Squadron's art"],
		"f16d": ["res://shared/extra/models/f16/SOURCES.md", "tail %s", "llrd", "(%d Squadron, tail"],
		"f35i": ["res://../docs/f35i.md", "tail number %s", "llnv", "%d Sqn badge"],
	}
	for u in srcs:
		var tail := str(settings().load_json("res://data/db/units/%s.json" % u).get("tail", ""))
		var text := FileAccess.get_file_as_string(srcs[u][0])
		check(tail != "" and text.contains(srcs[u][1] % tail), "%s: tail %s is the model's painted number" % [u, tail])
		var sq: Array = settings().load_json("res://data/airbases/%s.json" % srcs[u][2]).get("squadrons", [])
		sq = sq.filter(func(q): return q.unit == u)
		var n := int(sq[0].number) if sq.size() == 1 else 0
		check(n > 0 and text.contains(srcs[u][3] % n), "%s: squadron %d is the one painted on the model" % [u, n])


func _has(root: Node, t: String) -> bool:
	return t in _texts(root)


func _has_part(root: Node, t: String) -> bool:
	return _texts(root).any(func(x): return t in x)
