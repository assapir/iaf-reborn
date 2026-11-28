# Phase 1's lessons (modern-iaf/docs/training.md §16), headless, for each jet (the Barak at Ramat David, the Sufa at
# Ramon, the Adir at Nevatim):
# - the content resolves: each lesson's briefing (its eight sections, the jet's and the base's names filled in), the
#   notebook's Lesson tab and the instructor's calls (check ride 1 none), every call's tests known, each `item:` a
#   card item of the jet, each `called:` a call of the radio menu; its mission compiled and naming the lesson;
# - each lesson loads: the lesson's rules, its card (the items it asks for, the lesson-only items left out
#   elsewhere), the notebook raised, the record scored with the course's graded items;
# - lessons 1.1 and 1.2 flown by the card's switches to their end: a Pass, every graded item at least Average.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_course_lessons.gd --log-file <temp> [-- --jet f16i] [-- --load-only]
extends "res://tests/test_mvp.gd"

const UNITS := ["f16d", "f16i", "f35i"]
const GOOD := ["average", "above"]


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-course-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	settings().language = "en"
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	var calls: Array = load("res://flight/sim_flight.gd").ITEMS.map(func(x): return x[0])
	for unit in UNITS:
		if only != "" and unit != only:
			continue
		var course = JSON.parse_string(IafTraining.course(unit))
		var lessons: Array = course.phases[0].lessons
		var ids := _card_ids(unit)
		for le: Dictionary in lessons:
			_content(unit, le, ids, calls)
		for le: Dictionary in lessons:
			await _loads(unit, le)
		if not args.has("--load-only"):
			await _fly_lesson(unit, "ground.cockpit")
			await _fly_lesson(unit, "ground.engine")
	Engine.time_scale = 1.0


## The card items of jet `unit`'s card, the lesson-only ones too.
func _card_ids(unit: String) -> Array:
	for f in DirAccess.get_files_at(settings().readable("res://data/checklists")):
		var d: Dictionary = settings().load_json("res://data/checklists/" + f)
		if unit in d.get("jets", []):
			var out_ids := []
			for sec in d.sections:
				out_ids.append_array(sec.items.map(func(it): return it.id))
			return out_ids
	return []


func _content(unit: String, le: Dictionary, ids: Array, calls: Array) -> void:
	var key := String(le.key)
	var what := "%s %s" % [unit, key]
	var text := JSON.stringify(le.briefing) + JSON.stringify(le.lesson_tab)
	for s in ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]:
		check(le.briefing.get(s, []).size() > 0, "%s: the briefing's %s" % [what, s])
	check(not "{jet}" in text and not "{base}" in text, "%s: the jet's and the base's names filled in" % what)
	check(le.lesson_tab is Array and le.lesson_tab.size() > 0, "%s: the notebook's Lesson tab" % what)
	var check_ride := String(le.kind) == "check"
	check(check_ride == (le.calls == null or le.calls.is_empty()), "%s: calls, none in a check ride" % what)
	var m: Dictionary = settings().load_json("res://data/missions/%s.json" % le.mission)
	var tests: Array = m.get("training", {}).get("end", []).duplicate()
	for c in le.calls if le.calls is Array else []:
		tests.append_array(c.when)
	for t: String in tests:
		var arg := t.get_slice(":", 1)
		match t.get_slice(":", 0):
			"item":
				check(arg in ids, "%s: %s is a card item" % [what, t])
			"called":
				check(arg in calls, "%s: %s is a radio call" % [what, t])
	for i in m.training.checklist:
		check(i in ids, "%s: the mission's %s is a card item" % [what, i])
	check(String(m.get("lesson", "")) == key, "%s: its mission %s names the lesson" % [what, le.mission])
	check(sim_mission(String(le.mission)) >= 0, "%s: its mission compiled" % what)


func _loads(unit: String, le: Dictionary) -> void:
	var what := "%s %s" % [unit, le.key]
	var tv := await _start(String(le.mission))
	var addon: Node = tv.addon
	check(String(addon.rules.get("kind", "")) == "lesson", "%s: loads as a lesson" % what)
	check(addon.kneeboard.raised, "%s: the notebook raised" % what)
	var asked: Array = addon.rules.checklist
	var on_card: Array = addon.card.flat.filter(func(it): return it.has("check")).map(func(it): return it.id)
	check(on_card == asked, "%s: the card holds the items it asks for (%s)" % [what, on_card])
	var night_item := "hmd_night" if unit == "f35i" else "interior_lights"
	check((night_item in on_card) == (String(le.kind) == "night"), "%s: the night lighting only at night" % what)
	await fly(tv, 1.0)
	var d: Dictionary = addon.score()
	check(String(d.get("lesson", "")) == String(le.key), "%s: the record's lesson (%s)" % [what, d.get("lesson")])
	var graded: Array = d.get("graded", [])
	check(graded.size() == le.items.size(), "%s: the course's graded items (%d)" % [what, graded.size()])
	addon.result = {"pass": true}  # not flown on: no sortie logged at the exit


## Lesson `key` flown by the card: the tower's calls it asks for when the card reaches them, the throttle to OFF and
## the power off by their switches; it ends in a Pass with every graded item at least Average.
func _fly_lesson(unit: String, key: String) -> void:
	var what := "%s %s" % [unit, key]
	var tv := await _start("%s_%s" % [unit, key.replace(".", "_")])
	var addon: Node = tv.addon
	var card = addon.card
	var calls: Array = addon.rules.calls
	if "startup" in calls:
		await _call(tv, "startup")
	Engine.time_scale = TIME_SCALE
	var checked := false
	for n in 80:
		await frames(1)
		var it: Dictionary = card.current()
		if it.is_empty():
			break
		if it.id in ["main_power_off", "batt_off"] and "radio_check" in calls and not checked:
			await _radio_check(tv, what)  # lesson 1.1: the radio checked before the power goes off
			checked = true
		if it.check.has("throttle_off"):
			addon.throttle_off()
		elif it.check.get("set", {}).has("BATT") or it.check.get("set", {}).has("MAIN_PWR"):
			await _until(
				tv, func(): return not tv.flight.state().engine_on and float(tv.flight.state().rpm) < 0.01, 120.0
			)
			await _do_item(tv, it, false)
		else:
			await _do_item(tv, it, false)
		var ticked := await _until(tv, func(): return card.done.has(it.id), 150.0)
		check(ticked, "%s: %s ticked" % [what, it.id])
		if not ticked:
			break
	# Lesson 1.1 ends dark: the power off by its switches (the F-35I's IPP, then BATT).
	for sw in ["IPP", "BATT"] if unit == "f35i" else ["MAIN_PWR"]:
		for k in 4:
			if tv.cockpit.power == 0 or (sw == "IPP" and not tv.flight.start_on("starter")):
				break
			await _click_control(tv, sw, _moves(tv, sw))
	var done := await _until(tv, func(): return not addon.result.is_empty(), 60.0)
	check(done and bool(addon.result.get("pass", false)), "%s: a Pass (%s)" % [what, addon.result.get("reasons")])
	for g in addon.result.get("graded", []):
		check(String(g.grade) in GOOD, "%s: %s %s (%s)" % [what, g.id, g.grade, g.get("flown")])
	Engine.time_scale = 1.0


## The radio menu's radio check, and the tower's answer.
func _radio_check(tv: Node, what: String) -> void:
	_press(tv, KEY_T, true)
	_press(tv, KEY_1)  # Tower
	var i: int = tv.addon.shown.find("radio_check")
	check(i >= 0, "%s: the radio menu lists the radio check (%s)" % [what, tv.addon.menu_text()])
	_press(tv, KEY_1 + i)
	await fly(tv, 0.5)
	var answered: bool = tv.radio.said.slice(-3).any(func(x): return String(x.template) == "ACFT_RADIO_CHECK")
	check(answered, "%s: the tower reads us five" % what)
