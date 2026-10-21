# The mission editor (game/editor/mission_editor.gd, docs/mission-editor.md): the start choices, New from scratch;
# then on 512 Wild West: Fork offers a free
# name, a Hebrew name and an original title are refused; a drag on the map moves Alpha's leader; an added SA-6 stands
# at the terrain's height and Undo removes it; an SA-6 in the sea is an error (a red ring, Fly off); Save and Open
# give the same mission back; the original mission file stays byte-identical. Writes only under user://missions_test.
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_test"
const LAND := Vector2(350000, 600000)  # inland, 212 m
const SEA := Vector2(330000, 626000)  # off Haifa, west of the satil boats of onyourmarks


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func run() -> void:
	_clean()
	var orig: String = settings().assets_dir().path_join("converted/missions/wild_west.json")
	var md5: String = FileAccess.get_md5(orig)
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.size = Vector2i(1600, 1000)  # headless starts at 64 × 64
	root.add_child(ed)
	await frames(3)
	check(ed._ui.start.visible and ed.tsd == null, "nothing open: the start choices, no map")
	# New: from scratch on the modern era's original (231), only Alpha left; the map zoomed in on it.
	ed.new_mission("Scratch 1", 0, "Ramat David", 1, true)
	var real: Array = ed.data.entities.items.filter(func(e): return int(e["0x14"]) == 0)
	check(
		not ed._ui.start.visible and ed.tsd != null and ed.tsd.zoom > 1.0,
		"New: the map, zoomed in, in place of the start choices"
	)
	check(real.size() == 2 and ed.fly_flight() == 1, "New: Alpha's 2 jets only, Alpha flyable (%d units)" % real.size())
	check(FileAccess.file_exists(DIR.path_join("scratch_1.json")) and ed.source == 231, "New saves scratch_1.json")
	# 1973 from Refidim (Sinai), a lone Mirage: Refidim's base mission comes with it and is kept by Save / Open.
	ed.new_mission("Scratch 2", 1, "Refidim", 47, false)
	real = ed.data.entities.items.filter(func(e): return int(e["0x14"]) == 0)
	check(real.size() == 1 and int(real[0]["0x2c6"]) == 47, "New: a lone Mirage, no wingman (%d units)" % real.size())
	var lead: Dictionary = real[0]
	check(
		Vector2(lead["0x2e4"], lead["0x2ee"]).distance_to(Vector2(153765, 373720)) < 1.0 and ed.source == 121,
		"New: on Refidim's start, on 1973's original"
	)
	ed.open_file(DIR.path_join("scratch_2.json"))
	check("bmisrfdim" in ed.base_files.map(func(f): return f.name), "Refidim's base mission is saved and read back")
	ed._ask_name("new", "x")
	ed._fill_new_choices(2)
	var bases := range(ed._ui.new_base.item_count).map(func(i): return ed._ui.new_base.get_item_text(i))
	check(not "Refidim" in bases, "1967: no Sinai home base (%s)" % [bases])
	ed._ui.name_dlg.hide()
	ed.open_original(512)
	await frames(3)
	check(ed.read_only and ed.mission_name == "Wild West", "512 opens read-only as Wild West")
	check(ed.suggest_name() == "Wild West 2", "Fork offers 'Wild West 2' (%s)" % ed.suggest_name())
	check(ed.name_error("משימה חדשה") != "", "a Hebrew name is refused: %s" % ed.name_error("משימה חדשה"))
	check(ed.name_error("wild WEST") != "", "an original's title is refused: %s" % ed.name_error("wild WEST"))
	ed.fork("Wild West 2")
	check(not ed.read_only and FileAccess.file_exists(DIR.path_join("wild_west_2.json")), "Fork saves wild_west_2.json")
	check(ed.data.misc.items[0]["0x44c"] == "Wild West 2", "the fork's title is its name")
	ed.fork("Wild West 3")
	check(ed.own_clash("wild west 2"), "your own name clashes (asks Replace)")
	check(not ed.own_clash("Wild West 3"), "the open mission's own name does not clash")

	# Move Alpha (the F4 under the cursor at its leader F4_1, id 1) by a drag on the map.
	var tsd = ed.tsd
	var host = ed.host
	var i := -1
	for k in tsd.units.size():
		if tsd.units[k].key == "0:1":
			i = k
	var from: Vector2 = host._to_screen(tsd.CLIENT.position + tsd._to_client(tsd.units[i].pos))
	var to := from + Vector2(60, 40)
	i = tsd.unit_at(host._to_menu(from) - tsd.CLIENT.position)
	var id: int = int(String(tsd.units[i].key).split(":")[1])
	var x0: float = ed.entity(id)["0x2e4"]
	tsd._gui_input(mouse_button(from, true))
	var mv := InputEventMouseMotion.new()
	mv.position = to
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	tsd._gui_input(mv)
	tsd._gui_input(mouse_button(to, false))
	var want: Vector2 = tsd.map_to_world(tsd.units[i].pos)
	var e: Dictionary = ed.entity(id)
	check(
		id in [1, 2] and float(e["0x2e4"]) != x0 and absf(float(e["0x2e4"]) - want.x) < 2,
		"Alpha's F4 %d moved by the drag to %s (%s, %s)" % [id, want, e["0x2e4"], e["0x2ee"]]
	)
	check(tsd.sel_flight == 1, "the drag selects Alpha")

	# Add an SA-6 launcher (bdb object 6) on land: the terrain's height; Undo removes it.
	var count: int = ed.data.entities.items.size()
	id = ed.add_unit(6, LAND.x, LAND.y, 2, 1)
	var g = ed.api.ground_height(LAND.x, LAND.y)
	check(id > 0 and int(ed.entity(id).get("0x2c6", -1)) == 6, "an SA-6 added (id %d)" % id)
	check(
		g != null and float(g) > 50 and float(ed.entity(id)["0x2f8"]) == roundf(g),
		"its altitude is the ground's (%s, %s)" % [ed.entity(id).get("0x2f8"), g]
	)
	check(not ed.issues.any(func(it): return int(it.id) == id), "on land it has no issue")
	check(ed.data.entities.items[-1].get("0x14") == 1, "the placeholder row stays last")
	ed.undo_last()
	check(ed.data.entities.items.size() == count and ed.entity(id).is_empty(), "Undo removes it")

	# An SA-6 in the sea: an error, a red ring on the map, Fly off.
	check(not ed._ui.fly.disabled, "Fly is on before")
	id = ed.add_unit(6, SEA.x, SEA.y, 2, 1)
	await frames(2)
	var err: Array = ed.issues.filter(func(it): return int(it.id) == id and it.level == "error")
	check(not err.is_empty(), "the SA-6 in the sea is an error: %s" % [err])
	check(tsd.issues.get("0:%d" % id, "") == "error", "its map ring is red")
	check(ed._ui.fly.disabled, "an error turns Fly off")
	ed.undo_last()
	check(not ed._ui.fly.disabled and tsd.issues.is_empty(), "Undo clears the error")

	# Save, reopen: the same mission.
	ed.briefing.en = "Edited briefing."
	ed.save()
	var saved := JSON.stringify(ed.data, "", true, true)
	var path: String = ed.file
	ed.open_original(512)
	ed.open_file(path)
	check(JSON.stringify(ed.data, "", true, true) == saved, "Save then Open gives the same mission")
	check(ed.briefing.en == "Edited briefing." and ed.source == 512, "and its briefing and source")
	check(FileAccess.get_md5(orig) == md5, "the original wild_west.json is unchanged")
	ed.queue_free()
	await frames(2)
	_clean()
