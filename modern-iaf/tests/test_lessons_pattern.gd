# Phase 2's lessons (modern-iaf/docs/training.md §16.7), headless:
#   - each of the eight lessons in each jet (the Barak, the Sufa, the Adir) resolves: its mission compiled into the
#     sim and naming the lesson, the briefing's eight sections in English and Hebrew, the notebook's Lesson tab, the
#     calls (none in the check ride), the graded items with their standards;
#   - lesson 2.2's mission flown in each jet: the player's jet put in the air before the initial, the autopilot flies
#     the overhead pattern to a stop on the runway (instructor.gd demo, standing in for the pilot), and the recording,
#     its autopilot column cleared, is graded by the lesson's items (IafTraining.score): each flown, none
#     Unsatisfactory but the final's angle of attack (the autopilot's final is flown below 13°).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_lessons_pattern.gd --log-file <temp>
extends "res://../modern-iaf/tests/instructor_base.gd"

const SECTIONS := ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]
const JETS := {"f16d": "David", "f16i": "Ramon", "f35i": "Nevatim"}


func run() -> void:
	if sim_mission("f16i_pattern_first_flight") < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	for jet in JETS:
		_lessons(jet)
	for jet in JETS:
		await _overhead(jet)


## Jet `jet`'s eight phase-2 lessons resolve.
func _lessons(jet: String) -> void:
	var course = JSON.parse_string(IafTraining.course(jet))
	var phase: Dictionary = {}
	for p in course.phases:
		if p.id == "pattern":
			phase = p
	check(phase.get("lessons", []).size() == 8, "%s: eight lessons" % jet)
	for l in phase.get("lessons", []):
		var what := "%s %s" % [jet, l.key]
		var m := String(l.mission)
		check(sim_mission(m) >= 0, "%s: mission %s compiled" % [what, m])
		var readable = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions/%s.json" % m))
		check(readable is Dictionary and readable.get("lesson") == l.key, "%s: its mission names the lesson" % what)
		for s in SECTIONS:
			var ps: Array = l.briefing.get(s, [])
			var ok := not ps.is_empty()
			for p in ps:
				ok = ok and String(p.get("en", "")) != "" and String(p.get("he", "")) != ""
			check(ok, "%s: briefing %s in both languages" % [what, s])
		check(not l.lesson_tab.is_empty(), "%s: the Lesson tab" % what)
		var calls: Array = l.calls if l.calls is Array else []
		check(calls.is_empty() == (l.kind == "check"), "%s: %d calls" % [what, calls.size()])
		for c in calls:
			for line in c.lines:
				check(String(line.en) != "" and String(line.he) != "", "%s: call %s's lines" % [what, c.id])
		check(not l.items.is_empty(), "%s: graded items" % what)
		for i in l.items:
			check(i.has("label") and i.has("standard"), "%s: item %s with its standard" % [what, i.get("id")])


## Lesson 2.2 in `jet`, its pattern flown by the autopilot and graded.
func _overhead(jet: String) -> void:
	var tv: Node = await start_in_air("%s_pattern_overhead" % jet, JETS[jet])
	if tv == null:
		return
	var ins = Instructor.of(tv)
	check(ins.demo(), "%s: the autopilot flies the pattern" % jet)
	Engine.time_scale = TIME_SCALE
	var t0: float = tv._sim_time
	while ins.role == "demo" and tv._sim_time - t0 < 900.0 and not tv.flight.state().crashed:
		await process_frame
	Engine.time_scale = 1.0
	check(not tv.flight.state().crashed and tv.flight.state().on_ground, "%s: landed" % jet)
	tv._log.flush()
	var path := _pilot_flown(ProjectSettings.globalize_path(tv._log.get_path_absolute()))
	var trainer: RefCounted = ClassDB.instantiate("IafTraining")
	var d = JSON.parse_string(trainer.score(path, tv.addon._readable(), settings().disk_path("res://data/airbases")))
	check(d is Dictionary and not d.has("error"), "%s: scored %s" % [jet, d.get("error", "") if d is Dictionary else d])
	if not d is Dictionary:
		return
	var graded: Array = d.get("graded", [])
	check(graded.size() == 4, "%s: four items" % jet)
	for g in graded:
		print("%s %s: flown %s, gap %s, %s" % [jet, g.id, g.flown, g.gap, g.grade])
		check(g.flown != null, "%s: %s flown" % [jet, g.id])
		# The autopilot flies its own final (below 13°); the other items it flies within their standards.
		if g.id != "final_aoa_error":
			check(String(g.grade) != "unsat", "%s: %s graded %s" % [jet, g.id, g.grade])


## A copy of the recording `path` with its autopilot column cleared: the pattern the autopilot flew, graded as the
## pilot's.
func _pilot_flown(path: String) -> String:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var head = JSON.parse_string(lines[0])
	var k: int = head.columns.find("ap_mode")
	var out := PackedStringArray([lines[0]])
	for l in lines.slice(1):
		var v = JSON.parse_string(l) if l != "" else null
		if v is Array and k >= 0:
			v[k] = 0
			l = JSON.stringify(v)
		out.append(l)
	# KEEP_FLIGHTS=<dir>: the copies are kept there for a look (the records folder is a temporary one).
	var keep := OS.get_environment("KEEP_FLIGHTS")
	var copy := (keep.path_join(path.get_file().get_basename()) if keep != "" else path.get_basename()) + "-pilot.jsonl"
	var f := FileAccess.open(copy, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	return copy
