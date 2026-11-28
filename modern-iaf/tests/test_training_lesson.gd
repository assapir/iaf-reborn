# Modern IAF's course lesson screens (modern-iaf/docs/front-end.md §2.2, training-plan.md §2.2, §2.4, §5), headless,
# in English and Hebrew: a lesson of the list opens its briefing in the IDF order (Approvals A132: the Mission and
# Target paragraphs on the card, the order's sections and the graded items with their standards on the text card;
# a lesson file's diagram drawn above its paragraph), Back and Esc to the lesson list; a lesson's debrief (A133: the
# MARGINAL stamp, each item with its standard, flown value, gap, grade and comment, a pinned item's number, the
# conclusions with the lesson's grade and "Next time"), its buttons back to the lesson list, the lesson again and the
# next lesson; the Pilot screen's logbook course box (A135); the notebook's pages with a picture block (A134).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_training_lesson.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## The overhead break (training.md §16.5; course.rs a_diagram_is_checked holds the same).
const OVERHEAD := "res://tests/data/overhead_diagram.json"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	load("res://tests/test_front_end.gd").fixture(s)
	s.pilot_name = "Noa Golan"
	s.sim_jet = "f16i"
	var id := _log_lesson(s)
	check(id > 0, "a lesson's record stored")
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	for lang in ["en", "he"]:
		s.language = lang
		await _briefing(fe, lang)
		await _debrief(fe, lang, id)
		await _logbook(fe, lang)
	s.language = "en"
	_notebook()
	s.pilot_name = ""


## Lesson 1.3 in the Sufa, Marginal: the taxi too fast (placed), the checklist in full; one fault, off the pavement.
func _log_lesson(s: Node) -> int:
	var std := {"limit": "max", "bands": [20, 25, 30], "unit": "kt"}
	var r := {
		"mission": "f16i_ground_taxi",
		"kind": "lesson",
		"pass": true,
		"reasons": [],
		"items": [],
		"goals": [],
		"lesson": "ground.taxi",
		"grade": "marginal",
		"plane": "f16i",
		"date": "2026-11-27T08:00:00",
		"graded":
		[
			{
				"id": "taxi_speed",
				"label": {"en": "Highest taxi speed", "he": "מהירות ההסעה הגבוהה ביותר"},
				"standard": std,
				"should": 25,
				"flown": 28.0,
				"gap": 3.0,
				"grade": "below",
				"at": [681000.0, 3390000.0],
				"comment": {"en": "Too fast on the taxiway.", "he": "מהר מדי במסלול ההסעה."},
				"tip": {"en": "Keep the taxi under 25 kt.", "he": "הסעה מתחת ל-25 קשר."},
			},
			{
				"id": "checklist_items",
				"label": {"en": "Checklist items done", "he": 'סעיפי הבד"ח שבוצעו'},
				"standard": {"limit": "min", "bands": [100, 100, 90], "unit": "%"},
				"should": 100,
				"flown": 100.0,
				"gap": 0.0,
				"grade": "above",
				"comment": {"en": "Every item done.", "he": "כל הסעיפים בוצעו."},
			},
		],
		"faults": [],
		"strings": {"en": {}, "he": {}},
	}
	return IafPilotLog.log_sortie(s.records_db(), s.pilot(), 3132, JSON.stringify(r))


func _briefing(fe: Control, lang: String) -> void:
	var he := lang == "he"
	fe.open_phase(0)
	await frames(2)
	(fe.find_child("Lesson3", true, false) as Button).pressed.emit()
	await frames(3)
	check(fe.page == "mission", "%s: a lesson opens its briefing" % lang)
	var mission: RichTextLabel = fe.find_child("LessonMission", true, false)
	var target: RichTextLabel = fe.find_child("LessonTarget", true, false)
	check(mission != null and mission.get_parsed_text().length() > 20, "%s: the Mission paragraph" % lang)
	check(target != null and target.get_parsed_text().length() > 20, "%s: the Target paragraph" % lang)
	check(fe.find_child("Objectives", true, false) == null, "%s: no objectives on a lesson's card" % lang)
	for k in ["enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]:
		check(fe.find_child("Section_" + k, true, false) != null, "%s: the section %s" % [lang, k])
	var graded: Control = fe.find_child("Graded", true, false)
	var rows := graded.get_children().filter(func(c): return c is HBoxContainer) if graded != null else []
	check(rows.size() == 3, "%s: the lesson's graded items (%d)" % [lang, rows.size()])
	var txt := _texts(graded)
	check(txt.contains("עד 25 קשר" if he else "max 25 kt"), "%s: a standard (%s)" % [lang, txt])
	var sub: Label = fe.find_child("Subtitle", true, false)
	check(sub.text.begins_with("שלב 1, תרגול 3" if he else "Phase 1, lesson 3"), "%s: %s" % [lang, sub.text])
	(fe.find_child("Back", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "lessons", "%s: Back to the lesson list" % lang)
	(fe.find_child("Lesson3", true, false) as Button).pressed.emit()
	await frames(2)
	fe.back()
	await frames(2)
	check(fe.page == "lessons", "%s: Esc to the lesson list" % lang)
	# A paragraph naming a diagram draws it above itself.
	var box := VBoxContainer.new()
	fe.add_child(box)
	var m: Dictionary = fe.mission_by_name("f16i_ground_taxi")
	var para := [{"en": "Fly the pattern.", "he": "הקפה.", "diagram": "overhead"}]
	load("res://menu/briefing_page.gd")._paragraphs(
		fe, m, box, para, {"overhead": JSON.parse_string(FileAccess.get_file_as_string(OVERHEAD))}
	)
	var d: Control = box.find_child("Diagram_overhead", true, false)
	check(d != null and d.get_index() == 0, "%s: the diagram over its paragraph" % lang)
	check(d != null and d.tooltip_text == ("ההקפה עם שבירה" if he else "The overhead break"), "%s: its title" % lang)
	box.free()


func _debrief(fe: Control, lang: String, id: int) -> void:
	var he := lang == "he"
	check(fe.open_debrief(id), "%s: the lesson's debrief opens" % lang)
	await frames(3)
	var stamp: Label = fe.find_child("Stamp", true, false)
	check(stamp.text == ("גבולי" if he else "MARGINAL"), "%s: the stamp (%s)" % [lang, stamp.text])
	var row: Control = fe.find_child("Item_taxi_speed", true, false)
	var t := _texts(row)
	check(row != null and row.find_child("Pin1", true, false) != null, "%s: the placed item's pin number" % lang)
	for w in (
		["מהר מדי", "עד 25 קשר", "28 קשר", "+3 קשר", "מתחת לממוצע"]
		if he
		else ["Too fast", "max 25 kt", "28 kt", "+3 kt", "Below average"]
	):
		check(t.contains(w), "%s: the item's row has %s (%s)" % [lang, w, t])
	var ok := _texts(fe.find_child("Item_checklist_items", true, false))
	check(ok.contains("מעל הממוצע" if he else "Above average") and ok.contains("—"), "%s: no gap above average" % lang)
	var line: Label = fe.find_child("GradeLine", true, false)
	check(line.text.contains("סעיף אחד" if he else "one item below"), "%s: the grade line (%s)" % [lang, line.text])
	var next := fe.find_children("NextTime", "RichTextLabel", true, false)
	check(next.size() == 1 and next[0].get_parsed_text().contains("25"), "%s: one Next time line" % lang)
	var sheet := _texts(fe.find_child("Sheet", true, false))
	check(sheet.contains(fe.s("db_items")) and sheet.contains(fe.s("db_conclusions")), "%s: parts 2 and 3" % lang)
	check(fe.find_child("NextMission", true, false) != null, "%s: Next mission (the next lesson)" % lang)
	(fe.find_child("FlyAgain", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "mission" and fe.find_child("LessonMission", true, false) != null, "%s: Fly again" % lang)
	fe.open_debrief(id)
	await frames(2)
	(fe.find_child("NextMission", true, false) as Button).pressed.emit()
	await frames(2)
	var sub: Label = fe.find_child("Subtitle", true, false)
	check(fe.page == "mission" and sub.text.contains("4"), "%s: Next mission: lesson 1.4 (%s)" % [lang, sub.text])
	fe.open_debrief(id)
	await frames(2)
	fe.back()
	await frames(2)
	check(fe.page == "lessons" and fe.phase_i == 0, "%s: Esc to the lesson's list" % lang)


func _logbook(fe: Control, lang: String) -> void:
	var he := lang == "he"
	fe.show_page("pilot")
	await frames(3)
	var box: Control = fe.find_child("Course_f16i", true, false)
	check(box != null, "%s: the Sufa's course box in the logbook" % lang)
	var t := _texts(box)
	check(t.contains("1.3") and t.contains("גבולי" if he else "Marginal"), "%s: its last lesson (%s)" % [lang, t])
	check(t.contains("שלב 1 מתוך 8" if he else "Phase 1 of 8"), "%s: its phase (%s)" % [lang, t])


## The notebook pages a picture block (a lesson's diagram) by its own height.
func _notebook() -> void:
	var nb: Control = load("res://flight/notebook.gd").new()
	root.add_child(nb)
	var img := Image.create(100, 300, false, Image.FORMAT_RGBA8)
	var blocks: Array = ["one", ImageTexture.create_from_image(img), "two", ImageTexture.create_from_image(img)]
	nb.set_sections([{"id": "lesson", "tab": "LESSON", "title": "LESSON", "blocks": blocks}], false)
	check(nb.page_count() == 2, "the notebook: two pictures of 300 px on two pages (%d)" % nb.page_count())
	nb.free()


func _texts(n: Node) -> String:
	if n == null:
		return ""
	var out := []
	for c in n.find_children("*", "", true, false):
		if c is Label:
			out.append(c.text)
		elif c is RichTextLabel:
			out.append(c.get_parsed_text())
	return " | ".join(out).replace("\u2066", "").replace("\u2069", "").replace("\u00a0", " ")  # fe._ltr
