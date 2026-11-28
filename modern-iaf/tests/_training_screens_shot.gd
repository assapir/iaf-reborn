# Real-render pictures of the Training screens (front-end.md, Approvals A130 and A131) in English and Hebrew at
# 1920 × 1080, with the A130 mock's sample progress (phase 1 passed, phase 2: 2.1 Pass, 2.2 Marginal, 2.6
# Unsatisfactory), the lesson list on phase 2 with the side panel on 2.2:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <log> --path modern-iaf -s ../modern-iaf/tests/_training_screens_shot.gd
# Writes <dir>/{phases,lessons}_<lang>.png.
extends "res://../tests/godot/base.gd"

var dir := ""
var vp: SubViewport


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	var lessons := [
		["ground.cockpit", "pass"],
		["ground.engine", "pass"],
		["ground.taxi", "pass"],
		["ground.night", "pass"],
		["ground.check", "pass"],
		["pattern.first_flight", "pass"],
		["pattern.overhead", "marginal"],
		["pattern.flameout", "unsat"],
	]
	for l in lessons:
		var r := {
			"lesson": l[0], "grade": l[1], "plane": "f16i", "date": "2026-11-26T08:00:00", "pass": l[1] != "unsat"
		}
		IafPilotLog.log_sortie(s.records_db(), s.pilot(), 0, JSON.stringify(r))
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
		fe.open_section("training")
		await _shot("phases", lang)
		fe.open_phase(1)
		await frames(2)
		var row: Control = fe.find_child("Lesson2", true, false)
		row.grab_focus()
		await _shot("lessons", lang)
	s.language = "en"
	s.pilot_name = ""


func _shot(name: String, lang: String) -> void:
	await frames(10)
	var path: String = dir.path_join("%s_%s.png" % [name, lang])
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
