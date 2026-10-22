# Mission Creator (docs/front-end.md §19, docs/formats/mcr.md): Main → MISSION CREATOR opens screen 0x14 with the
# zeroed state; the combos open, list and pick (BASE copied into the formation records); the name and notes boxes
# take the edit class's characters; FLY's checks (msgs 44, 47, 48); RANDOM; SAVE (msg 49 without a name, msg 46
# before replacing) and LOAD round trip in a temporary folder (IAF_DEFAULT_SETTINGS=1); FLY generates mission 0x29a
# (units, routes, base, target as chosen) and the TSD opens on it.
extends "res://../tests/godot/base.gd"

var fe: Control
var mcv: Control


## Mission 0x29a's files for the current state (the screen's FLY build).
func mc_build() -> Array:
	return load("res://menu/mission_creator.gd").build(settings().mc)


func type_text(s: String) -> void:
	for ch in s:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		mcv._unhandled_input(e)


func mc_click(q: Vector2) -> void:
	var at: Vector2 = fe._to_screen(mcv.CONTENT + q)
	mcv._gui_input(mouse_button(at, true))
	mcv._gui_input(mouse_button(at, false))


## Opens combo c and picks item i by clicking its row.
func pick(c: int, i: int) -> void:
	mc_click(mcv.combos[c][3].get_center())
	var lr: Rect2 = mcv.list_rect()
	mc_click(Vector2(lr.get_center().x, lr.position.y + mcv.ROW_H * (i + 0.5)))


func box_msg() -> int:
	if fe.msgbox == null:
		return -1
	var lines: PackedStringArray = settings().msgs()
	for i in lines.size():
		if lines[i].strip_edges() == fe.msgbox.text:
			return i
	return -2


func answer(art: String) -> void:
	fe.msgbox.chosen.emit(art)


func run() -> void:
	fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("MissionCreator"))
	while fe.busy:
		await process_frame
	check(fe.screen == "mc" and fe.mc_view != null, "Main -> MissionCreator opens the MC screen")
	mcv = fe.mc_view
	# A click on the frame's RANDOM button through the viewport reaches the front end (the content over the whole
	# screen passes presses that hit none of its controls).
	var before: Dictionary = settings().mc.duplicate(true)
	var rb: Dictionary = fe._button(fe._key_for_label("Random"))
	var at: Vector2 = fe._to_screen(Vector2(rb.rect[0] + rb.rect[2] / 2.0, rb.rect[1] + rb.rect[3] / 2.0))
	root.push_input(mouse_button(at, true))
	root.push_input(mouse_button(at, false))
	await frames(2)
	while fe.busy:
		await process_frame
	check(str(settings().mc) != str(before), "a real click on RANDOM reaches the button (the content passes it)")
	settings().mc = before
	var mc: Dictionary = settings().mc
	check(mc.name == "" and int(mc.count[0]) == 0 and int(mc.base) == 0, "the state starts zeroed (FUN_004f64a0)")

	# FLY on the zeroed state: msg 44 (no controllable blue jet).
	mcv.button("fly")
	check(box_msg() == 44, "FLY without a blue jet -> msg 44")
	answer("ok")

	# Combos: open, pick.
	pick(0, 2)
	check(int(settings().mc.count[0]) == 2 and mcv.open == -1, "Alpha No: 2, the list closes")
	pick(4, 8)
	check(int(settings().mc.type[0]) == 8 and mcv.shown_text(4) == "MiG-29", "Alpha TYPE: MiG-29 (Alpha lists 9 types)")
	check(mcv.LISTS[mcv.COMBOS[5][2]].size() == 16, "Bravo TYPE lists all 16 types")
	check(mcv.LISTS[mcv.COMBOS[10][2]].size() == 2, "the Red AI lists hold Aggressors / Defenders")
	pick(12, 2)
	check(
		int(settings().mc.base) == 2 and settings().mc.fbase.all(func(b): return int(b) == 2),
		"BASE Ramon, copied into every formation record"
	)
	mcv.button("fly")
	check(box_msg() == 48, "By Kills without a red jet -> msg 48")
	answer("ok")
	pick(19, 1)
	mcv.button("fly")
	check(box_msg() == 47, "By Target with No Target -> msg 47")
	answer("ok")
	check(mcv.opens_up(18) and not mcv.opens_up(19), "WEAPONS opens up, VICTORY down (FUN_004f5570)")
	mc_click(mcv.COMBOS[13][3].get_center())
	check(mcv.open == 13, "a click on the box opens its list, the release keeps it open")
	mc_click(Vector2(300, 20))
	check(mcv.open == -1 and int(settings().mc.time) == 0, "a click outside closes it unchanged")
	pick(15, 3)
	check(mcv.shown_text(15) == "Radar Station", "TARGET Radar Station")

	# Name / notes.
	mc_click(mcv.NAME_BOX.get_center())
	type_text("Test 1!")
	check(settings().mc.name == "Test 1", "the name box takes letters, digits, space, '.' only")
	type_text("שם")
	check(settings().mc.name == "Test 1", "Hebrew letters are refused (the edit class's WM_CHAR table, both languages)")
	var cr: Rect2 = mcv.caret_rect(0, 130, mcv.NAME_BOX.end.y)
	check(cr.size.y == 13 and cr.position.y == mcv.NAME_BOX.position.y, "the name caret clipped to the 13 px box")
	check(mcv.caret_rect(1, 300, 271).size.y == 16, "the notes caret: all 16 px")
	mc_click(mcv.NOTES_BOX.get_center())
	type_text("abc")
	check(settings().mc.notes == "abc", "the notes box")

	# SAVE / LOAD.
	var folder: String = mcv.folder()
	check(not folder.begins_with(ProjectSettings.globalize_path("user://")), "tests save in a temporary folder")
	mcv.button("save")
	check(FileAccess.file_exists(folder.path_join("Test 1")), "SAVE writes MCR/<name>")
	check(FileAccess.get_file_as_bytes(folder.path_join("Test 1")).size() == 0x5ac, "the file is 0x5ac bytes")
	mcv.button("save")
	check(box_msg() == 46, "SAVE over an existing file asks msg 46")
	answer("yes")
	var saved: Dictionary = settings().mc.duplicate(true)
	mcv.button("random")
	check(settings().mc.name == "Random" and int(settings().mc.weapons) == 1, "RANDOM: name Random, Multipurpose")
	check(mcv.read(folder.path_join("Test 1")) and settings().mc == saved, "LOAD restores the saved state")
	settings().mc.name = ""
	mcv.button("save")
	check(box_msg() == 49, "SAVE without a name -> msg 49")
	answer("ok")

	# Mission Creator: Better off (the default): the original's 20 combos, no wind in the state, the template's wind.
	settings().mc = saved.duplicate(true)
	var misc0: Dictionary = mc_build()[0].data.misc.items[0]
	check(mcv.combos.size() == 20 and not saved.has("wind_kt"), "switch off: the original's 20 combos, no wind")
	check(int(misc0["0x46a"]) == 10 and int(misc0["0x474"]) == 270, "switch off: the template's 10 kt from 270")
	# On: WIND / FROM after the 20, the template's wind to start, picked like any combo.
	settings().better_mc = true
	mcv.setup(fe)
	check(mcv.combos.size() == 22 and mcv.shown_text(20) == "10 kt" and mcv.shown_text(21) == "W", "on: WIND 10 kt W")
	check(mcv.items(20).size() == 4 and mcv.items(21).size() == 8, "WIND: Calm / 10 / 15 / 20 kt; FROM: 8 points")
	settings().mc = saved.duplicate(true)
	mcv._set_state(settings().mc)
	pick(20, 3)
	pick(21, 3)
	check(int(settings().mc.wind_kt) == 20 and int(settings().mc.wind_from) == 135, "picked 20 kt from SE")
	pick(20, 0)
	check(
		mcv.combo_off(21) and not mcv.press(mcv.combos[21][3].get_center()) and mcv.open < 0,
		"Calm: FROM greyed, it does not open"
	)
	pick(20, 3)
	misc0 = mc_build()[0].data.misc.items[0]
	check(int(misc0["0x46a"]) == 20 and int(misc0["0x474"]) == 135, "FLY writes misc 0x46a = 20, 0x474 = 135")
	var wpath := folder.path_join("Wind")
	check(mcv.write(wpath) and FileAccess.get_file_as_bytes(wpath).size() == 0x5ac + 12, "SAVE adds the wind trailer")
	check(
		FileAccess.get_file_as_bytes(wpath).slice(0, 0x5ac) == FileAccess.get_file_as_bytes(folder.path_join("Test 1")),
		"the first 0x5ac bytes are the original record"
	)
	var windy: Dictionary = settings().mc.duplicate(true)
	check(
		mcv.read(folder.path_join("Test 1")) and int(settings().mc.wind_kt) == 10, "an original file: the default wind"
	)
	check(mcv.read(wpath) and settings().mc == windy, "LOAD restores the wind")
	mcv.button("random")
	check(
		int(settings().mc.wind_kt) in [0, 10, 15, 20] and int(settings().mc.wind_from) % 45 == 0,
		"RANDOM draws a wind (%s)" % [[settings().mc.wind_kt, settings().mc.wind_from]]
	)
	# Off again: the wind file loads without its wind, FLY keeps the template's.
	settings().better_mc = false
	mcv.setup(fe)
	check(mcv.read(wpath) and not settings().mc.has("wind_kt"), "switch off: LOAD drops the trailer's wind")
	misc0 = mc_build()[0].data.misc.items[0]
	check(int(misc0["0x46a"]) == 10 and int(misc0["0x474"]) == 270, "switch off: FLY keeps the template's wind")

	# FLY: Alpha 2 MiG-29 Aggressors from Ramon at 10000ft, Charlie 1 MiG-21 Bombers, Radar Station, By Target.
	settings().mc = saved
	var m: Dictionary = settings().mc
	m.count[0] = 2
	m.type[0] = 8
	m.count[2] = 1
	m.type[2] = 11
	m.ai[2] = 2
	m.alt = 2
	m.sams = 1
	m.victory = 1
	m.weapons = 1
	mcv.button("fly")
	check(fe.msgbox == null and settings().mission_id == 0x29a, "FLY: mission 0x29a")
	var files: Array = settings().mc_files
	check(
		files.map(func(f): return f.name) == ["mission", "bmisrmon", "ramon4", "bmisamman"],
		"the files: mission, Ramon's base, the Radar Station set, BMISAMMAN"
	)
	var main: Dictionary = files[0].data
	var ents := {}
	for e in main.entities.items:
		ents[String(e["0x2bc"])] = e
	check(
		(
			int(ents.Player1["0x2c6"]) == 2
			and ents.has("Player11")
			and not ents.has("Player2")
			and not ents.has("Player33")
		),
		"Alpha: 2 MiG-29; Bravo and Charlie's wingman dropped"
	)
	check(float(ents.Player1["0x2f8"]) == 580.0 + 3333.0, "10000ft: base altitude + 3333 m")
	while fe.busy or fe.loading:
		await process_frame
	check(fe.screen == "tsd" and fe.tsd != null, "the TSD opens on the built mission")
	check(fe._selected_flight() == "alpha" and fe.tsd.flight_enabled(1), "Alpha (MiG-29) selected and flyable")
	check(fe._button_enabled("Arm"), "Arm on (Multipurpose)")
	settings().mc.weapons = 0
	check(not fe._button_enabled("Arm"), "Guns Only disables Arm (FUN_00505c10)")
	settings().mc.weapons = 1
	fe.queue_free()
	await frames(2)

	# The flight: the player in the MiG-29 with its cockpit (FUN_00447e70: type 180 -> cockpit 7, mig29).
	var tv: Node = await start_mission(0x29a)
	check(int(tv.player.type) == 180, "the player flies the MiG-29 (type 180)")
	check(String(tv.player.cockpit_dir).ends_with("mig29"), "with the mig29 cockpit")
	check(tv.ai != null and tv.runtime.entities.size() > 10, "the mission's units are up")
	await seconds(2.0)
	var rt = tv.runtime
	# By Target (FUN_0059a480): the mission's passed flag picks the side.
	check(rt.debrief_text(0x29a).headline == "Too bad, red team won.\n\n\n\n", "By Target, not passed: red won")
	rt.passed = true
	var d: Dictionary = rt.debrief_text(0x29a)
	check(d.headline == "Congratulations, blue team won.\n\n\n\n" and d.result == 1, "By Target passed: blue won")
	rt.passed = false

	# By Kills (FUN_004a8420): every aircraft that explodes scores for the other side; Charlie's MiG-21 down.
	settings().mc.victory = 0
	settings().mc_files = mc_build()
	tv = await start_mission(0x29a)
	rt = tv.runtime
	var red: Dictionary = rt.entities["0:5"]
	check(red.name == "Player3" and red.role == 1, "By Kills: the red leader is a target (role 1)")
	check(rt.debrief_text(0x29a).headline == "Red team/Blue team draw.\n\n\n\n", "no losses: a draw")
	rt.set_damage_level(red, 5)
	check(rt.mc_score == [1, -1], "a red jet down: blue +1, red -1 (%s)" % [rt.mc_score])
	check(rt.passed, "every red jet down: the mission passes")
	d = rt.debrief_text(0x29a)
	check(d.headline == "Congratulations, blue team won.\n\n\n\n" and d.result == 1, "blue won (%s)" % d.headline)
	# The reverse: both blue jets down (the player's wingman, then a second blue loss counted on the leader).
	rt.set_damage_level(rt.entities["0:2"], 5)
	check(rt.mc_score == [0, 0], "a blue jet down evens it")
	rt.set_damage_level(rt.player_entity(), 5)
	d = rt.debrief_text(0x29a)
	check(d.headline == "Too bad, red team won.\n\n\n\n" and d.result == 0, "red won (%s)" % d.headline)
	settings().mc.victory = 1

	# WEAPONS (FUN_0058c9c0): the weapon table keeps only the allowed types, so no jet carries another store, even
	# when its stores come from the type's default.
	settings().mc.victory = 1
	for w in [[0, "Guns Only: guns, chaff, flares"], [2, "Air To Air: guns, AAMs, chaff, flares"]]:
		settings().mc.weapons = w[0]
		settings().mc_files = mc_build()
		tv = await start_mission(0x29a)
		var kept: Array = settings().mc_files[0].data.weapon_types
		var types := []
		for st in tv.weapons.loadout():
			if int(st[0]) > 0:
				types.append(int(tv.weapons.db.by_id(int(st[0])).type))
		check(not types.is_empty() and types.all(func(t): return float(t) in kept), "%s (%s)" % [w[1], types])
		check(
			tv.ai.combat._db.weapons.values().all(func(r): return float(r.type) in kept),
			"the AI jets' weapon table holds only the kept types"
		)
		if w[0] == 0:
			tv.weapons.select_aa()
			check(tv.weapons.hud_mode != 1, "Guns Only: no SRM (IR) mode")
	settings().mc.weapons = 1
