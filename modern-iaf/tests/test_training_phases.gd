# Modern IAF's Training screens (modern-iaf/docs/front-end.md §2.2, training-plan.md §5), headless, in English and
# Hebrew: Missions → Training opens the Hangar jet's eight phases (Approvals A130) with the course's names and each
# phase's lessons passed of its own, counted per jet (IafPilotLog.course_logbook); a phase opens its lessons (A131):
# numbered phase.lesson, each with its line and its best grade (Pass and Marginal in the pass chip, Unsatisfactory in
# the fail chip), the side panel on the lesson under the focus; Back and Esc go up a screen each.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_training_phases.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	load("res://tests/test_front_end.gd").fixture(s)
	# The Sufa's lessons: 1.1 passed, 1.2 Marginal, 2.1 Unsatisfactory; the Barak's 1.1 passed.
	for l in [
		["ground.cockpit", "pass", "f16i", "2026-11-20T08:00:00"],
		["ground.engine", "marginal", "f16i", "2026-11-26T08:00:00"],
		["pattern.first_flight", "unsat", "f16i", "2026-11-27T08:00:00"],
		["ground.cockpit", "pass", "f16d", "2026-11-21T08:00:00"],
	]:
		var r := {"lesson": l[0], "grade": l[1], "plane": l[2], "date": l[3], "pass": l[1] != "unsat"}
		IafPilotLog.log_sortie(s.records_db(), s.pilot(), 0, JSON.stringify(r))
	s.pilot_name = "Noa Golan"
	s.sim_jet = "f16i"
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	for lang in ["en", "he"]:
		s.language = lang
		await walk(fe, lang)
	s.language = "en"
	s.sim_jet = "f16d"
	fe.show_page("phases")
	await frames(2)
	check(_card(fe, 1).contains("1 of 5 passed"), "the Barak: its own course's count (%s)" % _card(fe, 1))
	check(_card(fe, 2).contains("0 of 8 passed"), "the Barak: phase 2 not flown")
	# Every lesson of the Sufa's phase 1 passed: Training focuses phase 2.
	s.sim_jet = "f16i"
	for k in ["ground.taxi", "ground.night", "ground.check"]:
		var r := {"lesson": k, "grade": "pass", "plane": "f16i", "date": "2026-11-28T08:00:00", "pass": true}
		IafPilotLog.log_sortie(s.records_db(), s.pilot(), 0, JSON.stringify(r))
	fe.open_section("training")
	await frames(2)
	check(fe.find_child("Phase2", true, false).has_focus(), "the focus on the first phase not passed (2)")
	s.sim_jet = "f16i"
	s.pilot_name = ""


func walk(fe: Control, lang: String) -> void:
	var he := lang == "he"
	fe.phase_i = 0
	fe.show_page("missions")
	await frames(2)
	check(_has(fe, "2 מתוך 47 עברו" if he else "2 of 47 passed"), "%s: missions: Training's progress" % lang)
	(fe.find_child("Section_training", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "phases", "%s: Training opens the phases" % lang)
	var grid: Control = fe.find_child("Phases", true, false)
	check(grid != null and grid.get_child_count() == 8, "%s: eight phase cards" % lang)
	check(_has(fe, "2 מתוך 47 עברו" if he else "2 of 47 passed"), "%s: the title: the course's count" % lang)
	var names := (
		["קרקע והתנעה", "שליטה בסיסית, המראה ונחיתה", "בקרה ותדלוק אווירי", "איומים ולוחמה אלקטרונית"]
		if he
		else [
			"Ground and start-up",
			"Basic handling, the pattern and landing",
			"AWACS, ground control, tanker",
			"Threats and electronic warfare"
		]
	)
	for i in 4:
		var n: int = [1, 2, 6, 8][i]
		check(_card(fe, n).contains(names[i]), "%s: phase %d: %s (%s)" % [lang, n, names[i], _card(fe, n)])
		check(_card(fe, n).contains("%02d" % n), "%s: phase %d: its number" % [lang, n])
	check(_card(fe, 1).contains("2 מתוך 5 עברו" if he else "2 of 5 passed"), "%s: phase 1: Marginal passes" % lang)
	check(_card(fe, 2).contains("0 מתוך 8 עברו" if he else "0 of 8 passed"), "%s: phase 2: Unsat does not" % lang)
	check(not _has_part(grid, "Next") and not _has_part(grid, "Ramon"), "%s: no Next, no base on the cards" % lang)
	var c1: Button = fe.find_child("Phase1", true, false)
	check(c1.has_focus(), "%s: the first phase focused" % lang)
	var back: Button = fe.find_child("Back", true, false)
	var c8: Button = fe.find_child("Phase8", true, false)
	check(c8.get_node(c8.focus_next) == back, "%s: Tab from the last phase to Back" % lang)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "missions", "%s: Esc on the phases: the Missions screen" % lang)
	fe.show_page("phases")
	await frames(2)
	(fe.find_child("Phase1", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "lessons", "%s: a phase opens its lessons" % lang)
	var rows: Array = fe.find_child("List", true, false).get_children()
	check(rows.size() == 5, "%s: phase 1's five lessons" % lang)
	check(_has(rows[0], "1.1") and _has(rows[4], "1.5"), "%s: numbered phase.lesson" % lang)
	check(_has(rows[0], "תא הטייס והזנת חשמל" if he else "Cockpit and power"), "%s: the lesson's title" % lang)
	check(_has_part(rows[0], "נורות האזהרה" if he else "the warning lights"), "%s: the lesson's line" % lang)
	var st := func(i: int) -> String: return str(rows[i].find_child("Status", true, false).text)
	check(rows[2].has_focus(), "%s: the focus on the first lesson not passed (1.3)" % lang)
	check(st.call(0) == ("עבר" if he else "Pass"), "%s: 1.1 Pass" % lang)
	check(st.call(1) == ("גבולי" if he else "Marginal"), "%s: 1.2 Marginal" % lang)
	check(st.call(2) == ("טרם בוצעה" if he else "Not flown yet"), "%s: 1.3 not flown" % lang)
	check(_has(fe, "שלב 1 · קרקע והתנעה" if he else "Phase 1 · Ground and start-up"), "%s: the title" % lang)
	rows[1].grab_focus()
	await frames(2)
	var side: Control = fe.find_child("Side", true, false)
	for t in (
		["שיעור 1.2", "התנעת המנוע ויישור INS", "מה לומדים", "גבולי · 26 בנובמבר 2026"]
		if he
		else ["Lesson 1.2", "Engine start and INS", "WHAT YOU WILL LEARN", "Marginal · 26 Nov 2026"]
	):
		check(_has(side, t), "%s: the side panel: %s" % [lang, t])
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "phases" and fe.find_child("Phase1", true, false).has_focus(), "%s: Esc: the phases" % lang)
	(fe.find_child("Phase2", true, false) as Button).pressed.emit()
	await frames(2)
	rows = fe.find_child("List", true, false).get_children()
	check(rows[0].has_focus(), "%s: 2.1 Unsatisfactory: not passed, focused" % lang)
	check(rows.size() == 8 and _has(rows[7], "2.8"), "%s: phase 2's eight lessons" % lang)
	check(str(rows[0].find_child("Status", true, false).text) == ("לא מספק" if he else "Unsatisfactory"), "unsat")
	fe.find_child("Back", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "phases" and fe.find_child("Phase2", true, false).has_focus(), "%s: Back: the phases" % lang)


## Phase card `n`'s texts, joined.
func _card(fe: Control, n: int) -> String:
	var c: Node = fe.find_child("Phase%d" % n, true, false)
	if c == null:
		return ""
	return " | ".join(_texts(c))


func _texts(root: Node) -> Array:
	var out := []
	for l in root.find_children("*", "Label", true, false):
		out.append(str(l.text))
	for l in root.find_children("*", "RichTextLabel", true, false):
		out.append(str(l.get_parsed_text()))
	return out


func _has(root: Node, t: String) -> bool:
	return t in _texts(root)


func _has_part(root: Node, t: String) -> bool:
	return _texts(root).any(func(x): return t in x)
