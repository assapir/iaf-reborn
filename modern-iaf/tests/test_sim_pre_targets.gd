# The GPS bombs' PRE targets picked on the briefing (A61; modern-iaf/docs/front-end.md §10.2, docs/weapons.md §13.2),
# headless. First the F-16s' GBU-31 and GBU-38 rack rows and a bomb's pick through the same rule; then on the F-35I's
# Nevatim weapons range with four GBU-39s on station 4 and a GBU-31 on station 8:
# - the briefing: the map's PRE targets chip shows the panel in the text card's place; station 4 takes Target 2 (a
#   click on its row, then on the target), its bomb 4-3 a point of the map, station 8 Target 3, cleared by a right
#   click, then steerpoint 1; each pick is kept in the pilot's loadout (`pre`) and shown on its row; a rack's bombs
#   take their station's; the panel in Hebrew;
# - the flight (Fly as the front end flies it): each bomb, released in PRE in turn 8 km short of its target, takes its
#   own pick: 4-1, 4-2 and 4-4 Target 2, 4-3 the point, station 8 the steerpoint.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_pre_targets.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const LOAD := '{"4": {"id": "gbu-39", "count": 4}, "8": {"id": "gbu-31", "count": 1}, "5": "aim-120", "7": "aim-120"}'

var fe: Control


func run() -> void:
	await require_data()
	var s := settings()
	IafPilotLog.set_loadout(s.records_db(), s.pilot(), "f35i", LOAD)
	s.sim_jet = "f35i"
	change_scene_to_file("res://main.tscn")
	await frames(3)
	fe = current_scene
	# The F-16s' GPS stores take picks the same way: a GBU-31 and a BRU-57/A's two GBU-38s (a row each and a bomb's).
	for unit in ["f16i", "f16d"]:
		var lo := '{"3": "gbu-31", "7": {"id": "gbu-38", "count": 2}, "1": "aim-9m"}'
		var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
		var mis := ProjectSettings.globalize_path("res://data/missions/ramon_range.json")
		var wdir := ProjectSettings.globalize_path("res://data/db/weapons")
		var rows: Array = JSON.parse_string(IafBriefing.pre(rec, wdir, lo, mis)).get("rows", [])
		check(rows.size() == 4, "%s: the GPS stations' rows (%d)" % [unit, rows.size()])
		var picked: String = IafBriefing.pre_set(rec, wdir, lo, mis, 7, 1, '{"target": 3}')
		check(JSON.parse_string(picked).get("pre", {}).has("7-2"), "%s: bomb 7-2 takes Target 3" % unit)
	var want := await _briefing()
	s.language = "he"
	await _hebrew()
	s.language = "en"
	await _flight(want)
	IafPilotLog.set_loadout(s.records_db(), s.pilot(), "f35i", "")


func _lo() -> Dictionary:
	var s := settings()
	var t: String = IafPilotLog.loadout(s.records_db(), s.pilot(), "f35i")
	var v = JSON.parse_string(t) if t != "" else {}
	return v if v is Dictionary else {}


func _open() -> void:
	fe.section = "training"
	fe.show_page("section")
	await frames(2)
	var i: int = fe.missions.map(func(m): return str(m.id)).find("nevatim_range")
	fe.open_mission(i)
	await frames(3)


func _row(name: String) -> Button:
	return fe.find_child(name, true, false) as Button


func _target(name: String) -> String:
	var b := _row(name)
	return (b.find_child("Target", true, false) as Label).text if b != null else ""


## A click on the map at the px of `world` (an aim's {x, y}) plus `off`.
func _click_map(map: Control, world: Dictionary, off := Vector2.ZERO) -> Vector2:
	var e: Array = map.data.extent
	var px: Vector2 = map.to_px(Vector2(float(world.x) - float(e[0]), float(e[3]) - float(world.y))) + off
	map._gui_input(mouse_button(px, true))
	map._gui_input(mouse_button(px, false))
	await frames(2)
	return px


## The picks on the briefing; returns the expected aim of each bomb: {Vector2i(pylon, bomb): world Vector2}.
func _briefing() -> Dictionary:
	await _open()
	var chip := fe.find_child("MapPre", true, false) as Button
	check(chip != null, "briefing: the PRE targets chip shows with GPS stores aboard")
	if chip == null:
		return {}
	chip.button_pressed = true
	await frames(2)
	var panel: Control = fe.find_child("PreTargets", true, false)
	var text: Control = fe.find_child("Text", true, false)
	check(panel.visible and not text.visible, "briefing: the panel takes the text card's place")
	check(_row("PreRow_4") != null and _row("PreRow_8") != null, "briefing: a row per GPS station")
	check(_row("PreRow_5") == null, "briefing: no row for a missile")
	check(_target("PreRow_4").ends_with("· default"), "briefing: without a pick the default (%s)" % _target("PreRow_4"))
	var map: Control = fe.find_child("PageMap", true, false)
	var pre: Dictionary = JSON.parse_string(
		IafBriefing.pre(
			fe._unit_file(fe.missions[fe.mission_i]),
			ProjectSettings.globalize_path("res://data/db/weapons"),
			LOAD,
			fe.mission_file(fe.missions[fe.mission_i])
		)
	)
	var aims: Array = pre.aims
	var t2: Dictionary = aims[1]
	var t3: Dictionary = aims[2]
	var s1: Dictionary = aims.filter(func(a): return a.kind == "steer")[0]
	# Station 4 (the rack, all four bombs) on Target 2: the row opens the rack's bombs.
	_row("PreRow_4").pressed.emit()
	await frames(2)
	check(_row("PreRow_4_3") != null, "briefing: the rack's row opens its four bombs")
	check(_target("PreRow_4") == "click the map…", "briefing: the armed row asks for the map")
	await _click_map(map, t2)
	check(
		_lo().get("pre", {}).get("4") == {"target": 2.0}, "briefing: station 4 keeps Target 2 (%s)" % [_lo().get("pre")]
	)
	check(_target("PreRow_4") == "Target 2", "briefing: the row shows Target 2 (%s)" % _target("PreRow_4"))
	check(_target("PreRow_4_1") == "Target 2 · as station", "briefing: a bomb takes its station's")
	# Bomb 4-3 on a point of the map 200 px below Target 2.
	_row("PreRow_4_3").pressed.emit()
	await frames(2)
	var px := await _click_map(map, t2, Vector2(0, 200))
	var pt: Variant = _lo().get("pre", {}).get("4-3")
	check(
		pt is Dictionary and pt.has("lat") and pt.mission == "nevatim_range",
		"briefing: bomb 4-3 keeps the point (%s)" % [pt]
	)
	check(_target("PreRow_4_3").begins_with("Point "), "briefing: the bomb's row shows the point")
	var e: Array = map.data.extent
	var at: Vector2 = map.to_map(px)
	var point := Vector2(float(e[0]) + at.x, float(e[3]) - at.y)
	# Station 8 on Target 3, cleared by a right click, then steerpoint 1.
	_row("PreRow_8").pressed.emit()
	await frames(2)
	await _click_map(map, t3)
	check(_lo().get("pre", {}).get("8") == {"target": 3.0}, "briefing: station 8 keeps Target 3")
	var right := mouse_button(Vector2.ZERO, true)
	right.button_index = MOUSE_BUTTON_RIGHT
	_row("PreRow_8").gui_input.emit(right)
	await frames(2)
	check(not _lo().get("pre", {}).has("8"), "briefing: a right click clears the row")
	_row("PreRow_8").pressed.emit()
	await frames(2)
	await _click_map(map, s1)
	check(
		_lo().get("pre", {}).get("8") == {"steer": 1.0},
		"briefing: station 8 keeps steerpoint 1 (%s)" % [_lo().get("pre")]
	)
	check(_target("PreRow_8") == "Steerpoint 1", "briefing: the row shows steerpoint 1")
	check(map.pre_marks.any(func(mk): return mk.tags == "4-1 4-2 4-4"), "briefing: the map tags Target 2's bombs")
	# Hiding the panel gives the text back and the map its clicks.
	chip.button_pressed = false
	await frames(2)
	check(text.visible and not panel.visible and not map.pre_click.is_valid(), "briefing: the chip off: the text again")
	var tw := Vector2(float(t2.x), float(t2.y))
	var sw := Vector2(float(s1.x), float(s1.y))
	return {Vector2i(2, 0): tw, Vector2i(2, 1): tw, Vector2i(2, 2): point, Vector2i(2, 3): tw, Vector2i(6, 0): sw}


func _hebrew() -> void:
	await _open()
	var chip := fe.find_child("MapPre", true, false) as Button
	check(chip != null and chip.text == "מטרות PRE", "Hebrew: the chip")
	if chip == null:
		return
	chip.button_pressed = true
	await frames(2)
	check(_target("PreRow_4") == "מטרה 2", "Hebrew: station 4's target (%s)" % _target("PreRow_4"))
	check(_target("PreRow_8") == "נקודת ציון 1", "Hebrew: the steerpoint")
	check(_target("PreRow_4_3").begins_with("מקום "), "Hebrew: the point")
	check(fe.is_layout_rtl(), "Hebrew: right to left")


## The flight: each bomb released in PRE in turn takes its own pick.
func _flight(want: Dictionary) -> void:
	var s := settings()
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	var tv := await start_mission(id)
	s.mission_files_override = []
	var n: int = tv.player_flight_number
	var g: Dictionary = s.gps_targets.get(n, {})
	check(g.has(2) and g.has(Vector2i(2, 2)) and g.has(6), "flight: the picks reach the flight (%s)" % [g])
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	var w = tv.weapons
	w.bay_doors_manual = true
	w.master_arm = true
	w.safety_off = true
	w.release_pairs = false
	w._ripple.set_values(1, 10)  # SGL, one pulse a press
	var time: float = tv._sim_time
	# The stores pages' lines: each bomb's target by its pick's name (WPN-S), the next bomb's PP and name (the SMS).
	w.stores.cur = 2
	if not w.hud_mode in [5, 6]:
		w.select_ag()
	var labels: Array = w.gps_bomb_rows().map(func(r): return r.label)
	check(labels == ["TGT 2", "TGT 2", "PT", "TGT 2"], "flight: the WPN-S names each bomb's target (%s)" % [labels])
	var info: Dictionary = w.gps_pre_info()
	check(
		info.get("label") == "TGT 2" and int(info.get("pp", 0)) == 1 and info.get("next", {}).get("bomb") == 1,
		"flight: the SMS line: PP 1, TGT 2, next bomb 4-2 (%s)" % [info]
	)
	for k in [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(6, 0)]:
		var aim: Vector2 = want[k]
		start_over(
			tv,
			w,
			Vector3(aim.x, aim.y - 8000.0, 0.0),
			tv.world_to_scene(Vector3(0, 250, 0)) - tv.world_to_scene(Vector3.ZERO),
			tv.player.fm_section,
			3000.0
		)
		w.stores.cur = k.x
		if not w.hud_mode in [5, 6]:
			w.select_ag()
		# The jet's power up (a cold start's): the stores' power with it (cockpit.gd up).
		tv.cockpit.power = 2
		tv.cockpit.systems = {}
		var before: int = w.gps_bombs.size()
		w.fire_selected()  # WPN REL held until the bomb leaves (the bay doors open first: their animation's frames)
		for i in 120:
			time += 0.05
			w.update(time)
			await process_frame
			if w.gps_bombs.size() > before:
				break
		w.release_selected()
		var ok: bool = w.gps_bombs.size() > before
		var got: Vector3 = w.gps_bombs[-1].g.aim() if ok else Vector3.INF
		check(
			ok and Vector2(got.x, got.y).distance_to(aim) < 25.0,
			"flight: bomb %d-%d flies to its pick (%s, want %s)" % [[4, 8][int(k.x == 6)], k.y + 1, got, aim]
		)
