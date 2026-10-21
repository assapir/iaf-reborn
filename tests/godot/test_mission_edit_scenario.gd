# The mission editor's Scenario tab (docs/mission-editor.md §18): a New mission gets an SA-6 (Target), a convoy with a
# route and a tank; two rules are built through the tab: "when the SA-6 is destroyed → the convoy starts its route"
# and "when Alpha comes within 10 km of the tank → play MiG's! MiG's! MiG's!". The rules read back from the saved
# mission; flown through the runtime (Settings.mission_files_override, as Fly does), the message plays, the convoy
# waits until the SA-6 dies and then drives. Writes only under user://missions_test_scn.
extends "res://../tests/godot/base.gd"

const DM := preload("res://mission/damage_model.gd")
const DIR := "user://missions_test_scn"
const LAND := Vector2(350000, 600000)  # inland, 212 m; 6.7 km from Ramat David's start
const BANDITS := 496  # bdb audio "MiG's! MiG's! MiG's!"


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func run() -> void:
	_clean()
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.size = Vector2i(1600, 1000)
	root.add_child(ed)
	await frames(3)
	ed.new_mission("Scenario 1", 1998.0, "Ramat David", 1, true)
	var sam: int = ed.add_unit(6, LAND.x, LAND.y, 2, 1)
	var tank: int = ed.add_unit(10, LAND.x - 2000.0, LAND.y, 2, 2)
	var convoy: int = ed.add_unit(10, LAND.x + 300.0, LAND.y, 2, 2)
	var c: Dictionary = ed.entity(convoy)
	var pts := PackedVector3Array([Vector3(c["0x2e4"], c["0x2ee"], 0), Vector3(c["0x2e4"] + 2000.0, c["0x2ee"], 0)])
	ed._edit(ed.api.set_route(ed.data, PackedInt64Array([convoy]), pts, 36.0, false))
	var alpha := -1
	for f in ed.data.formations.items:
		if int(f.get("0x3f2", 0)) == 1:
			alpha = int(f.members[0]["0x41a"])
	var sc = ed._ui.scenario
	var r1: int = sc.add_rule("destroyed")
	sc.set_value([r1, "when", "units", 0], sam)
	sc.drop_block(r1, {"then": "route"})
	check(sc.rules[r1].has("error"), "a route block without its unit is a draft: %s" % sc.rules[r1].get("error"))
	sc.set_value([r1, "then", 0, "unit"], convoy)
	var r2: int = sc.add_rule("enters")
	sc.set_value([r2, "when", "who"], alpha)
	sc.set_value([r2, "when", "center"], tank)
	sc.drop_block(r2, {"then": "message"})
	sc.set_value([r2, "then", 0, "audio"], BANDITS)
	var rules: Array = ed.api.rules(ed.data)
	check(rules.size() == 2 and sc.drafts.is_empty(), "two rules written (%d, drafts %s)" % [rules.size(), sc.drafts])
	var s1 := String(rules[0].get("summary", ""))
	var s2 := String(rules[1].get("summary", ""))
	check(s1 == "When %s is destroyed → %s starts its route" % [tank_name(ed, sam), tank_name(ed, convoy)], s1)
	check(s2 == "When Alpha comes within 10 km of %s → play \"MiG's! MiG's! MiG's!\"" % tank_name(ed, tank), s2)
	check(ed.errors() == 0, "no errors: %s" % [ed.issues])
	ed.save()
	ed.open_file(DIR.path_join("scenario_1.json"))
	check(ed.api.rules(ed.data).size() == 2, "the rules are kept by Save and Open")
	var files: Array = ed.files()
	var id: int = ed.source
	ed.queue_free()
	await frames(2)

	settings().mission_files_override = files
	var tv = await start_mission(id)
	var rec := record_mission(tv)
	var rt = tv.runtime
	var ent: Dictionary = rt.entities["0:%d" % convoy]
	var at: Vector3 = ent.world
	await fly(tv, 6.0)
	var sub: String = rt.audio.get(BANDITS, {}).get("subtitle", "")
	check(
		sub != "" and rec.subtitles.has(sub), "Alpha within 10 km of the tank: the message plays (%s)" % [rec.subtitles]
	)
	check(ent.path == null and ent.world.distance_to(at) < 1.0, "the convoy waits while the SA-6 lives")
	rt.set_damage_level(rt.entities["0:%d" % sam], DM.EXPLODED)
	await fly(tv, 5.0)
	check(
		ent.path != null and ent.world.distance_to(at) > 20.0, "the SA-6 destroyed: the convoy drives (%s)" % ent.world
	)
	settings().mission_files_override = []
	_clean()


func tank_name(ed, id: int) -> String:
	return String(ed.entity(id).get("0x2bc", ""))
