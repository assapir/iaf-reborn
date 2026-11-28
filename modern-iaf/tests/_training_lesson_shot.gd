# Real-render pictures of a course lesson's screens (front-end.md §10.3, §13.1, §3; training.md §11; Approvals
# A132-A135) in English and Hebrew at 1920 × 1080, to compare with the mocks: lesson 1.3's briefing at three scroll
# positions, a Marginal debrief of it (the sample take-off's recording, the taxi speed placed on it), the Pilot
# screen's logbook with the course box, and the flight's notebook on its LESSON tab:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <log> --path modern-iaf -s ../modern-iaf/tests/_training_lesson_shot.gd
# Writes <dir>/{brief_top,brief_exec,brief_end,debrief,pilot,lessons_p2,nb_1…}_<lang>.png.
extends "res://../tests/godot/base.gd"

var dir := ""
var vp: SubViewport


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	for l in [["ground.cockpit", "pass", "2026-11-20"], ["ground.engine", "pass", "2026-11-21"]]:
		var r := {"lesson": l[0], "grade": l[1], "plane": "f16i", "date": l[2] + "T08:00:00", "pass": true}
		IafPilotLog.log_sortie(s.records_db(), s.pilot(), 0, JSON.stringify(r))
	var id := _log_debrief(s)
	s.sim_jet = "f16i"
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		fe.open_phase(0)
		await frames(2)
		fe.open_lesson(2)
		await frames(30)  # the map's tiles
		await _shot("brief_top", lang)
		var scroll: ScrollContainer = fe.find_child("HowScroll", true, false)
		scroll.scroll_vertical = int((fe.find_child("Section_execution", true, false) as Control).position.y)
		await _shot("brief_exec", lang)
		scroll.scroll_vertical = 100000
		await _shot("brief_end", lang)
		fe.open_debrief(id)
		await frames(30)
		await _shot("debrief", lang)
		fe.show_page("pilot")
		await _shot("pilot", lang)
		fe.open_phase(1)  # phase 2: no flights yet, its panel says Coming later
		await _shot("lessons_p2", lang)
	vp.queue_free()
	for lang in ["en", "he"]:
		s.language = lang
		var tv := await start_mission(3132)
		await fly(tv, 3.0)
		var nb: Control = tv.addon.kneeboard.board
		nb.open("lesson")
		for pg in nb.page_count():
			if pg > 0:
				nb.turn(1)
			await fly(tv, 0.5)
			await save_shot(dir.path_join("nb_%d_%s.png" % [pg + 1, lang]))
	s.language = "en"
	s.pilot_name = ""


## Lesson 1.3 in the Sufa, Marginal, over the sample take-off's recording at Ramon: the taxi speed Below average where
## the taxi was fastest, the radio calls and the checklist above.
func _log_debrief(s: Node) -> int:
	var flight := ProjectSettings.globalize_path("res://tests/data/ramon_takeoff_flight.jsonl")
	var tr = JSON.parse_string(
		IafTraining.track(
			flight, s.disk_path("res://data/missions/f16i_ground_taxi.json"), s.disk_path("res://data/airbases")
		)
	)
	var at: Array = tr.at if tr is Dictionary and tr.has("at") else [0, 0]
	var k := int(at.size() / 2.0 * 0.25) * 2
	var g := func(id: String, flown: float, gap: float, grade: String, place) -> Dictionary:
		var c: Dictionary = (
			JSON.parse_string(FileAccess.get_file_as_string("res://data/training/course.json")).items[id]
		)
		var d := {
			"id": id, "label": c.label, "standard": c.standard, "flown": flown, "gap": gap, "grade": grade, "at": place
		}
		var com: Dictionary = c.get("comments", {})
		d.comment = (
			com.get("above") if grade == "above" else (com.get("below") if grade in ["below", "unsat"] else null)
		)
		d.tip = c.get("tip") if grade in ["below", "unsat"] else null
		return d
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
		"date": "2026-11-26T08:00:00",
		"elapsed_s": 891.0,
		"flight": flight,
		"graded":
		[
			g.call("tower_calls", 100.0, 0.0, "above", null),
			g.call("taxi_speed", 28.0, 3.0, "below", [at[k], at[k + 1]]),
			g.call("checklist_items", 100.0, 0.0, "above", null),
		],
		"faults": [],
		"strings": {"en": {}, "he": {}},
	}
	return IafPilotLog.log_sortie(s.records_db(), s.pilot(), 3132, JSON.stringify(r))


func _shot(name: String, lang: String) -> void:
	await frames(10)
	var path: String = dir.path_join("%s_%s.png" % [name, lang])
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
