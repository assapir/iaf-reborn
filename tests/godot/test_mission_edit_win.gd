# The mission editor's win and lose (docs/mission-editor.md §12): New has no target, so it can never pass (an error,
# Fly off, the summary line red); an SA-6 marked Target and a Merkava marked Must survive give the summary and let it
# fly. Flown through the runtime (Settings.mission_files_override, as Fly does): destroying the SA-6 passes the mission
# with New's headline; in a second flight losing the Merkava first fails it, and the SA-6 then no longer passes it.
# Writes only under user://missions_test_win.
extends "res://../tests/godot/base.gd"

const DM := preload("res://mission/damage_model.gd")
const DIR := "user://missions_test_win"
const LAND := Vector2(350000, 600000)  # inland, 212 m


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func run() -> void:
	await require_data()
	_clean()
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.size = Vector2i(1600, 1000)
	root.add_child(ed)
	await frames(3)
	ed.new_mission("Win 1", 1998.0, "Ramat David", 1, true)
	check(
		ed.issues.any(func(it): return it.level == "error" and "never pass" in String(it.text)) and ed._ui.fly.disabled,
		"New: no target, it can never pass (an error, Fly off)"
	)
	check(ed._ui.cond_line.modulate == Color.RED, "the summary line is red: %s" % ed._ui.cond_line.text)
	var sam: int = ed.add_unit(6, LAND.x, LAND.y, 2, 2)
	var tank: int = ed.add_unit(10, LAND.x + 300.0, LAND.y, 1, 2)
	for i in ed._ui.units.item_count:
		ed._ui.units.deselect(i)
	for i in ed._ui.units.item_count:
		if int(ed._ui.units.get_item_metadata(i)) == sam:
			ed._ui.units.select(i, false)
	ed.mark_selected(1)
	ed.sel_id = tank
	for i in ed._ui.units.item_count:
		ed._ui.units.deselect(i)
	ed.mark_selected(0)
	var tank_name := String(ed.entity(tank)["0x2bc"])
	var want := (
		"Pass: destroy 1 target (1 SA 6) · Keep alive: %s · Fail: a keep-alive unit is lost, or the flight " % tank_name
	)
	check(ed.conditions.summary == want + "ends first", "summary: %s" % ed.conditions.summary)
	check(ed._ui.cond_line.text == ed.conditions.summary and not ed._ui.fly.disabled, "the line by Fly; Fly on")
	check(ed.conditions.passed_text == "Mission - successful.", "New's passed headline")
	ed.save()
	var files: Array = ed.files()
	var id: int = ed.source
	ed.queue_free()
	await frames(2)

	# Flight 1: the SA-6 destroyed -> passed.
	settings().mission_files_override = files
	var tv = await start_mission(id)
	var rt = tv.runtime
	check(rt.targets_left == 1, "one target (%d)" % rt.targets_left)
	rt.set_damage_level(rt.entities["0:%d" % sam], DM.EXPLODED)
	var d: Dictionary = rt.debrief_text()
	check(rt.passed and not rt.failed and d.headline == "Mission - successful.", "the SA-6 destroyed: passed")

	# Flight 2: the Merkava lost first -> failed; the SA-6 then does not pass it.
	tv = await start_mission(id)
	rt = tv.runtime
	rt.set_damage_level(rt.entities["0:%d" % tank], DM.EXPLODED)
	rt.set_damage_level(rt.entities["0:%d" % sam], DM.EXPLODED)
	d = rt.debrief_text()
	check(rt.failed and not rt.passed and d.headline == "Mission - failed.", "the Merkava lost: failed (%s)" % d)
	settings().mission_files_override = []
	_clean()
