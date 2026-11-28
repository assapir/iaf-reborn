# The training course's grades through the game's own debrief record path (modern-iaf/docs/training.md §13),
# headless: mission ramon_startup flown a few seconds and ended (sim_flight.gd score and _finish, IafTraining.score,
# IafPilotLog.log_sortie into a temporary records database); its stored record carries each goal's gap and grade, the
# lesson's grade and the faults. Then the course's rules the screens call: IafTraining.course and
# check_ride_emergency, IafPilotLog.course_logbook.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_training_grades.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const GRADES := ["unsat", "below", "average", "above"]


func run() -> void:
	var s := settings()
	var id := sim_mission("ramon_startup")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	var dir := DirAccess.create_temp("modern-iaf-grades", false).get_current_dir()
	tv.addon.out_dir = dir
	await fly(tv, 2.0)
	var d: Dictionary = tv.addon.score()
	check(not d.has("error"), "scored: %s" % d.get("error", ""))
	tv.addon._finish(d)
	var db := dir.path_join("modern-iaf.sqlite")
	var rec = JSON.parse_string(IafPilotLog.debrief(db, int(tv.addon.sortie)))
	check(rec is Dictionary, "the sortie's record stored")
	if not rec is Dictionary:
		return
	# Not started in 2 s: not passed, so the lesson is Unsatisfactory; each goal graded with its gap.
	check(String(rec.get("grade", "")) == "unsat", "the lesson's grade: %s" % rec.get("grade"))
	check(rec.get("lesson") == null, "ramon_startup is no course lesson")
	check(rec.get("faults") is Array, "the faults with their place")
	var checks: Array = rec.get("checks", [])
	check(not checks.is_empty(), "the goals")
	for c in checks:
		check(String(c.get("grade", "")) in GRADES and c.has("gap"), "goal %s: %s" % [c.get("id"), c.get("grade")])
	check(String(rec.strings.en.get("lesson_unsat", "")) == "Unsatisfactory", "the grade's name in English")
	check(String(rec.strings.he.get("lesson_unsat", "")) != "", "and in Hebrew")
	# The course the screens show.
	var course = JSON.parse_string(IafTraining.course("f16i"))
	check(course is Dictionary and course.phases.size() == 8, "the Sufa's course: eight phases")
	check(JSON.parse_string(IafTraining.course("f15")) == null, "no course for a jet without one")
	var e = JSON.parse_string(IafTraining.check_ride_emergency("f16i", "pattern.check", 5))
	check(e is Dictionary and String(e.id) in ["engine_fire_roll", "engine_fire", "flameout"], "check ride 2: %s" % e)
	check(JSON.parse_string(IafTraining.check_ride_emergency("f16i", "ground.check", 5)) == null, "check ride 1: none")
	# A lesson's record in the logbook: its best attempt, the next lesson.
	var lesson := {"pass": true, "grade": "marginal", "lesson": "ground.cockpit", "plane": "f16i"}
	lesson.merge({"date": "2026-11-28T10:00:00", "elapsed_s": 60.0, "mission": "x", "reasons": [], "items": []})
	IafPilotLog.log_sortie(db, s.pilot(), 1, JSON.stringify(lesson))
	var book = JSON.parse_string(IafPilotLog.course_logbook(db, s.pilot(), "f16i"))
	check(book is Dictionary and String(book.phases[0].results[0].best) == "marginal", "the best attempt: Marginal")
	check(book is Dictionary and String(book.next) == "ground.engine", "the next lesson: %s" % book.get("next"))
