# The mission editor (game/editor/mission_editor.gd, docs/mission-editor.md): the start choices, New from scratch
# by year (the year's bases and jets, a red flight from a red base, a flipped Refidim before June 1967, the year kept
# by Save / Open);
# then on 512 Wild West: Fork offers a free
# name, a Hebrew name and an original title are refused; a drag on the map moves Alpha's leader; an added SA-6 stands
# at the terrain's height and Undo removes it; an SA-6 in the sea is an error (a red ring, Fly off); Save and Open
# give the same mission back; the list and the map share one selection, Esc clears it, hovering names a unit, Add
# checks the ground under the mouse and places at the click, Esc stops it; the original mission file stays
# byte-identical. Writes only under user://missions_test.
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
	await require_data()
	# New: from scratch on 1998's original (231), only Alpha left; the map zoomed in on it.
	ed.new_mission("Scratch 1", 1998.0, "Ramat David", 1, true)
	var real: Array = ed.data.entities.items.filter(func(e): return int(e["0x14"]) == 0)
	check(
		not ed._ui.start.visible and ed.tsd != null and ed.tsd.zoom > 1.0,
		"New: the map, zoomed in, in place of the start choices"
	)
	check(real.size() == 2 and ed.fly_flight() == 1, "New: Alpha's 2 jets only, Alpha flyable (%d units)" % real.size())
	check(FileAccess.file_exists(DIR.path_join("scratch_1.json")) and ed.source == 231, "New saves scratch_1.json")
	# The side panel keeps its width on every tab, so the map does not move.
	var tabs: TabContainer = ed.find_children("*", "TabContainer", true, false)[0]
	var widths := []
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await frames(2)
		widths.append(ed.host.size.x)
	check(
		widths.all(func(w): return is_equal_approx(w, widths[0])), "the map keeps its width on every tab %s" % [widths]
	)
	# The map fills its pane (any window size, 4K full screen too); the mouse pans and zooms it.
	var mh: Control = ed.host
	var mt: Control = ed.tsd
	check((mt.area.size * mh._scale()).distance_to(mh.size) < 1.0, "the map's client fills the pane")
	var sc0: Vector2 = mt.scroll
	mh._gui_input(_mouse(InputEventMouseButton.new(), mh.size / 2, MOUSE_BUTTON_MIDDLE, true))
	mh._gui_input(_mouse(InputEventMouseMotion.new(), Vector2(-40, -30)))
	mh._gui_input(_mouse(InputEventMouseButton.new(), mh.size / 2, MOUSE_BUTTON_MIDDLE, false))
	check(
		mt.scroll.x > sc0.x and mt.scroll.y > sc0.y, "a middle-button drag pans the map (%s -> %s)" % [sc0, mt.scroll]
	)
	var cur: Vector2 = mh.size * 0.3
	var under: Vector2 = mt.scroll + (mh._to_menu(cur) - mt.area.position) / mt.zoom
	var z0: float = mt.zoom
	mh._gui_input(_mouse(InputEventMouseButton.new(), cur, MOUSE_BUTTON_WHEEL_UP, true))
	var after: Vector2 = mt.scroll + (mh._to_menu(cur) - mt.area.position) / mt.zoom
	check(mt.zoom > z0 and after.distance_to(under) < 0.5, "the wheel zooms about the point under the cursor")
	# A flight's jet and start: Bravo, F-15s from Tel Nof's runway, its route taking off.
	var row: Dictionary = ed._ui.flight_rows[1]
	for i in row.type.item_count:
		if row.type.get_item_metadata(i) == 40:
			row.type.select(i)
	for i in row.start.item_count:
		if row.start.get_item_text(i) == "Tel Nof":
			row.start.select(i)
	ed.apply_flight(2)
	var bravo: Dictionary = ed.entity(ed._key_id(ed.tsd.units[ed.tsd.flights[2].leader].key))
	var fo: Dictionary = ed.data.formations.items[ed._formation_of(2)]
	check(
		(
			int(bravo["0x2c6"]) == 40
			and Vector2(bravo["0x2e4"], bravo["0x2ee"]).distance_to(Vector2(312984, 500459)) < 1.0
			and int(fo.points[0][5]) == 2
		),
		"Bravo: F-15s on Tel Nof's runway, the route taking off"
	)
	# 1973 from Refidim (Sinai), a lone Mirage: Refidim's base mission comes with it and is kept by Save / Open.
	ed.new_mission("Scratch 2", 1973.0, "Refidim", 47, false)
	real = ed.data.entities.items.filter(func(e): return int(e["0x14"]) == 0)
	check(real.size() == 1 and int(real[0]["0x2c6"]) == 47, "New: a lone Mirage, no wingman (%d units)" % real.size())
	var lead: Dictionary = real[0]
	check(
		Vector2(lead["0x2e4"], lead["0x2ee"]).distance_to(Vector2(153765, 373720)) < 1.0 and ed.source == 121,
		"New: on Refidim's start, on 1973's original"
	)
	ed.open_file(DIR.path_join("scratch_2.json"))
	check("bmisrfdim" in ed.base_files.map(func(f): return f.name), "Refidim's base mission is saved and read back")
	check(is_equal_approx(ed.year, 1973.0) and ed._ui.m_year.value == 1973, "1973 kept")
	# An enemy flight from Damascus (MiG-21): its base mission comes, Save / Open keep it and the year.
	ed.add_enemy_flight("bmisdmsk", 8, 2)
	var reds: Array = ed.data.formations.items.filter(func(f): return int(f.get("0x3f2", 0)) == 8)
	check(reds.size() == 1 and int(reds[0].points[0][5]) == 2, "a red flight (number 8) taking off")
	ed.save()
	ed.open_file(DIR.path_join("scratch_2.json"))
	check(
		"bmisdmsk" in ed.base_files.map(func(f): return f.name) and is_equal_approx(ed.year, 1973.0),
		"Save / Open keep Damascus and 1973"
	)
	# New's pickers by year: 1967 (the Six-Day War, from the pre-war lines) no Sinai base for blue, the Mirage only;
	# 1973 has Refidim.
	ed._ask_name("new", "x")
	var names := func(o): return range(o.item_count).map(func(i): return o.get_item_text(i))
	ed._ui.new_year.value = 1967
	var bases: Array = names.call(ed._ui.new_base)
	check(bases == ["Tel Nof", "Ramat David"], "1967: no Sinai home base (%s)" % [bases])
	check(names.call(ed._ui.new_jet) == ["Mirage"], "1967: the Mirage (%s)" % [names.call(ed._ui.new_jet)])
	ed._ui.new_year.value = 1973
	check("Refidim" in names.call(ed._ui.new_base), "1973: Refidim (%s)" % [names.call(ed._ui.new_base)])
	check(not "Lavi" in names.call(ed._ui.new_jet), "no Lavi without what-if")
	ed._ui.name_dlg.hide()
	# In 1967 (the war's start) Refidim is Egyptian: a red flight from it brings a flipped copy of its base mission.
	ed.new_mission("Scratch 3", 1967.0, "Tel Nof", 47, true)
	check(ed.source == 111, "1967: on 111's map")
	ed.add_enemy_flight("bmisrfdim", 8, 2)
	ed.save()
	ed.open_file(DIR.path_join("scratch_3.json"))
	var flip: Array = ed.base_files.filter(func(f): return f.name == "bmisrfdim_flipped")
	check(
		flip.size() == 1 and ed._base_side(flip[0].data) == 2 and is_equal_approx(ed.year, 1967.0),
		"a red Refidim (flipped) is saved and read back"
	)
	check(
		not ed.issues.any(func(it): return String(it.text).contains("starts at")),
		"no base warning (%s)" % [ed.issues.map(func(it): return it.text)]
	)
	ed.set_year(1990.0, false)
	check(
		ed.issues.any(func(it): return String(it.text).contains("Refidim in 1990: no fighter base")),
		"in 1990 Refidim is no fighter base: a warning"
	)
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
	var from: Vector2 = host._to_screen(tsd.area.position + tsd._to_client(tsd.units[i].pos))
	var to := from + Vector2(60, 40)
	i = tsd.unit_at(host._to_menu(from) - tsd.area.position)
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
	check(not ed._ui.fly.disabled and not tsd.issues.values().has("error"), "Undo clears the error")

	# Selection: a pick in the Units list selects the unit on the map; a click on the map makes it the list's only
	# pick; Esc clears it.
	var ul: ItemList = ed._ui.units
	ul.deselect_all()
	for k in ul.item_count:
		if int(ul.get_item_metadata(k)) in [1, 9]:
			ul.select(k, false)
	ed._on_unit_listed()
	check(tsd.selected >= 0 and tsd.units[tsd.selected].key == "0:9", "a list pick selects that unit on the map")
	var ring_at: Vector2 = host.map_px(tsd.units[tsd.selected].pos)
	check(Rect2(Vector2.ZERO, host.size).has_point(ring_at), "and the map centres on it")
	check(
		ed._ui.sel_head.text.begins_with("Selected: ") and ed._ui.sel_head.text.contains("Boat_1"), "the panel names it"
	)
	for k in tsd.units.size():
		if tsd.units[k].key == "0:1":
			i = k
	from = host.map_px(tsd.units[i].pos)
	tsd._gui_input(mouse_button(from, true))
	tsd._gui_input(mouse_button(from, false))
	var picks: Array = Array(ul.get_selected_items()).map(func(k): return int(ul.get_item_metadata(k)))
	check(ed.sel_id == 1 and picks == [1], "a click on the map makes it the list's only pick (%s)" % [picks])
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ed._unhandled_key_input(esc)
	check(ed.sel_id == -1 and tsd.selected == -1 and ul.get_selected_items().is_empty(), "Esc clears the selection")
	check(
		not ed._ui.p_name.get_parent().visible and not ed._ui.p_delete.visible,
		"with nothing selected the panel shows no unit's fields"
	)
	# A row of the Units list under the mouse rings its unit on the map.
	ed.find_children("*", "TabContainer", true, false)[0].current_tab = 0
	await frames(2)
	var row_mv := InputEventMouseMotion.new()
	row_mv.position = ul.get_item_rect(0).get_center()
	ed._on_units_hover(row_mv)
	check(ed.list_hover == int(ul.get_item_metadata(0)), "hovering a list row marks its unit (%d)" % ed.list_hover)
	ed._on_units_hover(null)
	# A label goes around its icon clear of what is taken, else farther out with a leader line.
	var at: Vector2 = host.size / 2
	var sz := Vector2(60, 20)
	var taken := [Rect2(at + Vector2(10, -10), sz)]
	var lab: Array = ed._place(at, sz, 10.0, taken)
	check(
		not lab[1] and not lab[0].intersects(taken[0]) and lab[0].end.x <= at.x, "a label taken on the right goes left"
	)
	var all := [Rect2(at - Vector2(40, 25), Vector2(80, 50))]
	lab = ed._place(at, sz, 20.0, all)
	check(lab[1] and not lab[0].intersects(all[0]), "boxed in, it goes farther out with a leader line")
	# Hover: the unit under the mouse is named on the status line.
	ed.hover_at(host._to_menu(from) - tsd.area.position)
	check(ed.hover == i and ed.hint_text().contains("F4_1"), "hovering a unit names it: %s" % ed.hint_text())
	# Place: Add's ghost checks the ground under the mouse before the click; the click places at that point.
	ed.add_object = 6
	ed._set_mode("add")
	tsd.centre_on(tsd.world_to_map(SEA.x, SEA.y))
	ed.hover_at(tsd._to_client(tsd.world_to_map(SEA.x, SEA.y)))
	check(
		ed.place_check.any(func(it): return it.level == "error") and ed.hint_text().contains("on the sea"),
		"Add over the sea: the error shows before the click (%s)" % ed.hint_text()
	)
	tsd.centre_on(tsd.world_to_map(LAND.x, LAND.y))
	var land_px: Vector2 = host.map_px(tsd.world_to_map(LAND.x, LAND.y))
	ed.hover_at(host._to_menu(land_px) - tsd.area.position)
	check(ed.place_check.is_empty(), "inland the ghost is clear (%s)" % [ed.place_check])
	count = ed.data.entities.items.size()
	tsd._gui_input(mouse_button(land_px, true))
	tsd._gui_input(mouse_button(land_px, false))
	var placed: Dictionary = ed.entity(ed.sel_id)
	check(
		(
			ed.data.entities.items.size() == count + 1
			and int(placed.get("0x2c6", -1)) == 6
			and Vector2(placed["0x2e4"], placed["0x2ee"]).distance_to(LAND) < 2500
		),
		"the click places the SA-6 there (%s, %s)" % [placed.get("0x2e4"), placed.get("0x2ee")]
	)
	check(ed.mode == "add", "Add stays on for the next one")
	ed._unhandled_key_input(esc)
	check(ed.mode == "" and not ed._ui.add_mode.button_pressed, "Esc stops placing")
	ed.undo_last()

	# Weather (ours, misc `weather`): a fork of an original has none (Default, the Graphics Rain level); Heavy rain.
	check(ed._ui.m_weather.selected == 0 and not ed.data.misc.items[0].has("weather"), "a fork: Weather Default")
	ed._ui.m_weather.select(3)
	ed._ui.m_weather.item_selected.emit(3)
	check(ed.data.misc.items[0].get("weather") == "heavy", "Weather Heavy rain: misc weather heavy")
	# Save, reopen: the same mission.
	ed.briefing.en = "Edited briefing."
	ed.save()
	var saved := JSON.stringify(ed.data, "", true, true)
	var path: String = ed.file
	ed.open_original(512)
	ed.open_file(path)
	check(JSON.stringify(ed.data, "", true, true) == saved, "Save then Open gives the same mission")
	check(ed.briefing.en == "Edited briefing." and ed.source == 512, "and its briefing and source")
	check(ed._ui.m_weather.selected == 3, "and its weather (Heavy rain)")
	check(FileAccess.get_md5(orig) == md5, "the original wild_west.json is unchanged")
	# Delete: your own mission's file goes, the editor closes it; an original cannot be deleted.
	ed.delete_mission()
	check(not FileAccess.file_exists(path) and ed._ui.start.visible, "Delete removes your mission and closes it")
	ed.open_original(512)
	check(ed._ui.delete.disabled, "an original has no Delete")
	ed.delete_mission()
	check(FileAccess.get_md5(orig) == md5, "and Delete leaves the original alone")
	ed.queue_free()
	await frames(2)
	_clean()


func _mouse(ev: InputEvent, pos: Vector2, button := MOUSE_BUTTON_NONE, pressed := false) -> InputEvent:
	if ev is InputEventMouseButton:
		ev.position = pos
		ev.button_index = button
		ev.pressed = pressed
	else:
		ev.relative = pos
		ev.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	return ev
