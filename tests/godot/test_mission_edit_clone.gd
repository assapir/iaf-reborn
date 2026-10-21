# The mission editor's sanity check, Duplicate, Copy / Paste, the year's map and Remove for an enemy flight
# (game/editor/mission_editor.gd, docs/mission-editor.md §14, §15, §12), on a New 1998 mission:
# - Duplicate writes a copy and keeps you on yours;
# - three SA-6s copied (Ctrl+C) and pasted (Ctrl+V, a click) keep their layout, headings and roles, with new ids at
#   the ground's height;
# - Alpha sent to Inshas and back gets a fuel warning;
# - 1973 moves the mission onto 121's map and bases, kept by Save / Open; 1966 onto 111's, with a warning for
#   Refidim's blue base mission;
# - an enemy flight from Damascus is removed with its jets.
# Writes only under user://missions_test_clone.
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_test_clone"
const LAND := Vector2(350000, 600000)  # inland, 212 m


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
	ed.open_original(512)
	check(ed._ui.duplicate.disabled, "an original has no Duplicate (Fork)")
	ed.new_mission("Clone A", 1998.0, "Ramat David", 1, true)
	check(not ed._ui.duplicate.disabled, "your own mission has Duplicate")
	# Duplicate: a copy on disk, you stay on yours.
	ed._ask_name("duplicate", ed.suggest_name())
	check(ed._ui.name_edit.text == "Clone A 2", "Duplicate offers a free name (%s)" % ed._ui.name_edit.text)
	ed._ui.name_dlg.hide()
	ed.duplicate_mission("Clone A 2")
	var copy: Dictionary = settings().load_json(DIR.path_join("clone_a_2.json"))
	check(copy.get("name") == "Clone A 2" and int(copy.get("source", 0)) == 231, "Duplicate writes clone_a_2.json")
	check(ed.file == DIR.path_join("clone_a.json") and ed.mission_name == "Clone A", "and you go on editing Clone A")

	# Copy / Paste three SA-6s: their layout, headings and roles; new ids; the ground's height.
	var a: int = ed.add_unit(6, LAND.x, LAND.y, 2, 1)
	var b: int = ed.add_unit(6, LAND.x + 2000, LAND.y, 2, 0)
	var c: int = ed.add_unit(6, LAND.x, LAND.y + 1500, 2, 2)
	ed.sel_id = b
	ed.set_field("0x302", 135.0)
	ed._ui.units.deselect_all()
	for i in ed._ui.units.item_count:
		if int(ed._ui.units.get_item_metadata(i)) in [a, b, c]:
			ed._ui.units.select(i, false)
	var ctrl := func(k: Key):
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.ctrl_pressed = true
		ev.pressed = true
		ed._unhandled_key_input(ev)
	ctrl.call(KEY_C)
	check(ed.clipboard.size() == 3, "Ctrl+C copies the 3 selected units (%d)" % ed.clipboard.size())
	ctrl.call(KEY_V)
	check(ed.mode == "paste", "Ctrl+V waits for a click on the map")
	var to := LAND + Vector2(30000, -20000)
	var count: int = ed.data.entities.items.size()
	ed._on_map_clicked(_map_pos(ed, to))
	var pasted: Array = Array(ed._ui.units.get_selected_items()).map(
		func(i): return int(ed._ui.units.get_item_metadata(i))
	)
	check(pasted.size() == 3 and ed.data.entities.items.size() == count + 3, "3 new units pasted (%s)" % [pasted])
	var src: Array = [ed.entity(a), ed.entity(b), ed.entity(c)]
	var new: Array = pasted.map(func(i): return ed.entity(i))
	new.sort_custom(func(x, y): return int(x["0x1e"]) < int(y["0x1e"]))
	var shift := Vector2(
		float(new[0]["0x2e4"]) - float(src[0]["0x2e4"]), float(new[0]["0x2ee"]) - float(src[0]["0x2ee"])
	)
	var same := true
	for k in 3:
		var d := Vector2(
			float(new[k]["0x2e4"]) - float(src[k]["0x2e4"]), float(new[k]["0x2ee"]) - float(src[k]["0x2ee"])
		)
		same = same and d.distance_to(shift) < 2.0
		same = same and new[k]["0x302"] == src[k]["0x302"] and new[k]["0x32a"] == src[k]["0x32a"]
		var g = ed.api.ground_height(float(new[k]["0x2e4"]), float(new[k]["0x2ee"]))
		same = same and g != null and absf(float(new[k]["0x2f8"]) - roundf(g)) < 1.0
		same = same and not int(new[k]["0x1e"]) in [a, b, c]
	check(same, "the layout, headings and roles kept, at the ground's height (moved %s)" % shift)
	check(shift.distance_to(to - LAND - Vector2(2000, 1500) / 3) < 300.0, "centred on the click (%s)" % shift)

	# The sanity check: Alpha sent to Inshas and back (about 900 km).
	var d: Dictionary = ed.data.duplicate(true)
	for f in d.formations.items:
		if int(f.get("0x3f2", 0)) == 1 and int(f.get("0x14", 0)) == 0:
			f.points = [[1, 0.0, 360000.0, 3000.0, 0.0, 3]]
	ed._edit(d)
	var fuel: Array = ed.issues.filter(func(it): return String(it.text).contains("% of its fuel for this route"))
	check(fuel.size() == 1 and fuel[0].level == "warning", "a fuel warning (%s)" % [fuel])
	check(ed.tsd.issues.get("0:%d" % int(fuel[0].id) if not fuel.is_empty() else "", "") == "warning", "its ring")
	ed.undo_last()

	# 1973: the mission moves onto 121's map and bases; Ramat David (Alpha's) stays; Save / Open keep it.
	ed.set_year(1973.0, false)
	var names := func(): return ed.base_files.map(func(f): return String(f.name))
	check(ed.source == 121 and ed.tsd.map_name == "73", "1973: 121's map (%d, %s)" % [ed.source, ed.tsd.map_name])
	check(
		"bmisrfdim" in names.call() and "bmisrdvd" in names.call() and ed.entity(a).size() > 0,
		"121's bases, Ramat David kept, the units kept (%s)" % [names.call()]
	)
	ed.save()
	ed.open_file(DIR.path_join("clone_a.json"))
	check(ed.source == 121 and is_equal_approx(ed.year, 1973.0) and ed.tsd.map_name == "73", "Save / Open keep it")
	# 1966: 111's map; Refidim is Egyptian, its base mission blue: a warning.
	ed.set_year(1966.0, false)
	check(ed.source == 111 and ed.tsd.map_name == "67", "1966: 111's map")
	check(
		ed.issues.any(func(it): return String(it.text) == "Refidim: red holds it in 1966, but its base is blue"),
		"Refidim's blue base mission in 1966 warns"
	)
	ed.set_year(1998.0, false)
	check(ed.source == 231 and not "bmisrfdim" in names.call(), "1998: 231 again, Refidim gone (%s)" % [names.call()])

	# Remove an enemy flight from the Flights tab.
	ed.add_enemy_flight("bmisdmsk", 8, 2)
	var key := -1
	for n in ed.tsd.flights:
		if n > 4:
			key = n
	var fo: int = ed._formation_of(key)
	var jets: Array = ed.data.formations.items[fo].members.map(func(m): return int(m["0x41a"]))
	ed.tsd.sel_flight = key
	ed._refresh_ui()
	check(not ed._ui.red_remove.disabled, "Remove is on for the enemy flight")
	ed.remove_enemy_flight()
	check(not ed.data.formations.items.any(func(f): return int(f.get("0x3f2", 0)) == 8), "the enemy flight is gone")
	check(jets.all(func(i): return ed.entity(i).is_empty()), "and its jets")
	ed.queue_free()
	await frames(2)
	_clean()


## The TSD map position of world point `w` (the editor's clicks arrive as map positions).
func _map_pos(ed, w: Vector2) -> Vector2:
	return ed.tsd.world_to_map(w.x, w.y)
