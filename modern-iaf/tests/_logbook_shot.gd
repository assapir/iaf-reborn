# Real-render pictures of the Pilot screen (its logbook with the combat totals), the Pilot log, More stats and a combat
# flight's debrief with its More stats, sample flights stored in the test's own records, English and Hebrew, at
# 1920 × 1080:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_PREFIX=<prefix> -- --log-file <log> \
#     --path modern-iaf -s ../modern-iaf/tests/_logbook_shot.gd
# Writes <prefix>{pilot,log,more_pilot,debrief,more_debrief}_<lang>.png.
extends "res://../tests/godot/base.gd"

## Sample flights: [menu id, mission, date, pass, elapsed s, combat record (combat_log.rs) or none].
const FLIGHTS := [
	[2011, "ramon_startup", "2026-11-03T08:10:00", true, 540.0],
	[2013, "ramon_range", "2026-11-05T09:30:00", false, 1310.0],
	[
		2013,
		"ramon_range",
		"2026-11-06T10:05:00",
		true,
		1720.0,
		{
			"ground": {"target_t72": 3, "target_ural": 2},
			"weapons": {"MK-82": {"fired": 6, "hits": 4}, "20 MM": {"fired": 220, "hits": 12, "gun": true}}
		}
	],
	[
		2014,
		"ramon_four_ship",
		"2026-11-12T07:45:00",
		true,
		2480.0,
		{
			"kills": {"mig29a": 1},
			"weapons": {"PYTH-5": {"fired": 2, "hits": 1}},
			"lost": {"crashed": 1},
			"ejected": 1,
			"wingmen_lost": 1
		}
	],
	[2022, "ramat_david_takeoff", "2026-11-15T14:20:00", true, 700.0],
	[2023, "ramat_david_range", "2026-11-17T11:00:00", true, 1960.0],
	[2033, "nevatim_range", "2026-11-21T09:40:00", false, 880.0],
	[
		2014,
		"ramon_four_ship",
		"2026-11-22T16:15:00",
		true,
		2650.0,
		{
			"kills": {"mig29a": 2, "shahed-136": 1},
			"shared": {"mig29a": 1},
			"ground": {"5P85TE2": 1, "96L6E RADAR": 1},
			"weapons":
			{
				"AIM-120": {"fired": 2, "hits": 1},
				"PYTH-5": {"fired": 1, "hits": 1},
				"GBU-31": {"fired": 2, "hits": 2},
				"20 MM": {"fired": 180, "hits": 0, "gun": true}
			},
			"lost": {"sam": 1},
			"wingmen_lost": 1
		}
	],
]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	var pre := OS.get_environment("SHOT_PREFIX")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	var db: String = s.records_db()
	var last := 0
	for f in FLIGHTS:
		var d := {"mission": f[1], "pass": f[3], "date": f[2], "elapsed_s": f[4], "reasons": [] if f[3] else ["mock"]}
		d["items"] = []
		if f.size() > 5:
			d["combat"] = f[5]
		last = IafPilotLog.log_sortie(db, s.pilot(), f[0], JSON.stringify(d))
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		var he: bool = lang == "he"
		s.language = lang
		s.sim_jet = "f16i"
		s.pilot_name = "נועה גולן" if he else "Noa Golan"
		IafPilotLog.set_pilot(db, s.pilot(), "נועה גולן" if he else "Noa Golan", "עקרב" if he else "Viper")
		fe.show_page("credits")
		fe.show_page("pilot")
		await _shot(vp, dir, pre + "pilot_" + lang)
		fe.find_child("CombatMore", true, false).pressed.emit()
		await _shot(vp, dir, pre + "more_pilot_" + lang)
		fe.show_page("log")
		await _shot(vp, dir, pre + "log_" + lang)
		fe.open_debrief(last)
		fe.show_page("debrief")
		await _shot(vp, dir, pre + "debrief_" + lang)
		fe.find_child("CombatMore", true, false).pressed.emit()
		await _shot(vp, dir, pre + "more_debrief_" + lang)
	IafPilotLog.set_pilot(db, s.pilot(), "", "")
	s.language = "en"
	s.pilot_name = ""


func _shot(vp: SubViewport, dir: String, name: String) -> void:
	await frames(10)
	var path: String = dir.path_join(name + ".png")
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
