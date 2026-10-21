# Debrief buttons (docs/front-end.md §13, FUN_004ff440 / FUN_004ff540, v1.1): Replay and Next Mission on
# a training mission open the Jet list (311–319 -> screen 9 under Basic, 321–329 -> screen 10 under
# Combat) so a plane is picked before each training flight; campaign missions reload (-> TSD); New
# Mission goes to the mission's list; Next is disabled when there is no next mission. The message box
# reads msgs.trx line 56 (v1.1's version-mismatch text) and any line past the file is empty.
extends "res://../tests/godot/base.gd"

var fe: Control


func debrief(id: int, passed := true) -> void:
	settings().mission_id = id
	settings().debrief = {"passed": passed, "headline": "", "notes": ""}
	fe.screen = "deb"
	fe.busy = false
	fe._enter_screen()
	await frames(2)


func run() -> void:
	fe = load("res://menu/front_end.tscn").instantiate()
	settings().debrief = {"passed": true, "headline": "", "notes": ""}
	root.add_child(fe)
	await frames(2)
	var fe_script = fe.get_script()

	await debrief(311)
	fe._debrief_button("replaymission")
	await frames(90)
	check(
		fe.screen == "jet" and fe.jet_parent == "basic" and settings().mission_id == 311,
		"Replay 311 -> Jet list (screen 9, under Basic)"
	)
	check(settings().debrief.is_empty(), "debrief consumed")

	await debrief(311)
	check(fe._button_enabled("Next_Mission"), "311 has a next mission")
	fe._debrief_button("nextmission")
	await frames(90)
	check(fe.screen == "jet" and settings().mission_id == 312, "Next after 311 -> 312 on the Jet list")

	await debrief(315)
	fe._debrief_button("nextmission")
	await frames(90)
	check(
		fe.screen == "jet" and fe.jet_parent == "combat" and settings().mission_id == 321,
		"Next after 315 -> 321, Jet list under Combat (screen 10)"
	)

	await debrief(326)
	check(not fe._button_enabled("Next_Mission"), "326: no next mission, Next disabled")

	await debrief(322)
	fe._debrief_button("newmission")
	await frames(90)
	check(fe.screen == "combat", "New Mission after 322 -> Combat list")

	check(fe_script.next_mission(137, false) == 211, "137 -> 211")
	check(
		fe_script.next_mission(211, false) == 0 and fe_script.next_mission(211, true) == 212,
		"a Future front's next needs this one passed"
	)
	check(fe_script.next_mission(217, true) == 0, "217 is the front's last")
	check(
		(
			fe_script.new_mission_screen(124) == "his2mis"
			and fe_script.new_mission_screen(233) == "fut3mis"
			and fe_script.new_mission_screen(401) == "main"
		),
		"New Mission lists"
	)

	await debrief(111)
	fe._debrief_button("replaymission")
	await frames(120)
	check(
		fe.screen == "tsd" and fe.tsd_return == "his1mis",
		"Replay of a campaign mission reloads it -> TSD (BACK to its list)"
	)

	await _pages()

	var box = load("res://mission/mission_box.gd").new()
	box.setup(56, ["ok"])
	var lines: int = (
		String(settings().load_json(settings().assets_dir().path_join("converted/menu/strings.json")).get("msgs", ""))
		. split("\n")
		. size()
	)
	check(
		("version" in box.text) if lines >= 57 else box.text == "",
		"msgs.trx line 56: v1.1 version text, empty with v1.0 data (%d lines)" % lines
	)
	box.setup(400, ["ok"])
	check(box.text == "", "a line past the file is empty")
	box.free()


## The Debrief's tabs and pages (FUN_004ff1f0, FUN_00517130): this flight's kills / losses per category with
## their names and counts, and the score column.
func _pages() -> void:
	settings().mission_id = 113
	settings().debrief = {
		"passed": false,
		"headline": "Mission - failed.",
		"notes": "A note.",
		"result": 0,
		"bonus": -750,
		"kills": [[150, 3], [150, 3], [290, 8], [400, 12], [450, 12]],
		"losses": [[120, 28]]
	}
	fe.screen = "deb"
	if fe.debrief_view != null:
		fe.debrief_view.free()
		fe.debrief_view = null
	fe._enter_screen()
	await frames(2)
	var dv = fe.debrief_view
	check(dv != null and dv.tab == 0, "the Debrief opens on DEBRIEFING")
	var p0: Array = dv.items(0)
	check(
		p0[0].text == "Mission - failed.\n A note." and p0[0].at == Vector2(10, 10) and p0[0].key,
		"headline and notes in key.fnt at (10,10)"
	)
	# MiG21 ×2 500, SA-2 300, building 200 + runway 2000; the F-4E lost 700; bonus −750.
	check(
		(
			_line(p0, 58) == ["300", Color8(0, 255, 0)]
			and _line(p0, 128) == ["300", Color8(0, 255, 0)]
			and _line(p0, 184) == ["2200", Color8(0, 255, 0)]
		),
		"DEBRIEFING rows: kills − losses per class"
	)
	check(_line(p0, 204) == ["-750", Color8(255, 0, 0)], "MISSION BONUS −750 in red")
	check(
		_line(p0, 219) == ["3500", Color8(0, 255, 0)] and _line(p0, 234) == ["-700", Color8(255, 0, 0)],
		"KILL TALLY 3500, LOSSES −700"
	)
	check(
		_line(p0, 250) == ["2050", Color8(0, 255, 0)] and _line(p0, 269)[0] == "2050",
		"MISSION CREDITS 2050, PILOT SCORE"
	)
	check(dv.press(Vector2(150, 50)) and dv.tab == 1, "KILL TALLY tab")
	check(not dv.press(Vector2(150, 50)), "the current tab is not hit")
	var p1: Array = dv.items(1)
	check(
		_text_at(p1, Vector2(88, 24)) == "MiG21X2" and _icon_at(p1, Vector2(75, 7)) == 0,
		"one MiG21 icon, MiG21X2 under it"
	)
	check(
		_text_at(p1, Vector2(88, 122)) == "SA-2" and _icon_at(p1, Vector2(75, 105)) == 3,
		"SA-2 in the ground row, SAM cell"
	)
	check(
		(
			_text_at(p1, Vector2(88, 207)) == "Building"
			and _text_at(p1, Vector2(178, 207)) == "Runway"
			and _icon_at(p1, Vector2(165, 190)) == 5
		),
		"structures: Building, Runway"
	)
	check(
		_line(p1, 58) == ["1000", Color8(0, 255, 0)] and _line(p1, 184) == ["2200", Color8(0, 255, 0)],
		"kill points per class"
	)
	check(dv.press(Vector2(200, 50)) and dv.tab == 2, "LOSSES tab")
	var p2: Array = dv.items(2)
	check(
		(
			_text_at(p2, Vector2(88, 24)) == "F-4E"
			and _line(p2, 58) == ["-700", Color8(255, 0, 0)]
			and _line(p2, 128).is_empty()
		),
		"losses: F-4E, −700 red, empty rows not drawn"
	)
	# The Mission Creator's mission: "N/A" in green but the pilot's score; empty rows still not drawn.
	settings().mission_id = 0x29a
	p2 = dv.items(2)
	check(
		(
			_line(p2, 58) == ["N/A", Color8(0, 255, 0)]
			and _line(p2, 128).is_empty()
			and _line(p2, 234) == ["N/A", Color8(0, 255, 0)]
			and _line(p2, 269)[0] == str(int(dv.stats.pilot_score))
		),
		"mission 0x29a: N/A, green, the pilot's score a number"
	)
	settings().mission_id = 113
	# The structure row's bound reads the ground row's slot (< 4 ground icons placed).
	settings().debrief = {
		"passed": false,
		"headline": "",
		"notes": "",
		"result": 0,
		"bonus": 0,
		"kills": [[250, 5], [260, 6], [270, 5], [280, 6], [400, 12]],
		"losses": []
	}
	dv.setup(fe)
	check(
		_text_at(dv.items(1), Vector2(88, 207)) == "" and _line(dv.items(1), 184)[0] == "200",
		"4 ground icons: no structure icon, its points still shown"
	)
	settings().debrief = {"passed": true, "headline": "", "notes": ""}
	dv.free()
	fe.debrief_view = null


func _line(items: Array, y: int) -> Array:
	for it in items:
		if it.get("at") == Vector2(378, y) and it.has("text"):
			return [it.text, it.color]
	return []


func _text_at(items: Array, at: Vector2) -> String:
	for it in items:
		if it.get("at") == at and it.has("text"):
			return it.text
	return ""


func _icon_at(items: Array, at: Vector2) -> int:
	for it in items:
		if it.get("at") == at and it.has("icon"):
			return it.icon
	return -1
