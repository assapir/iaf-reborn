# Debrief buttons (docs/front-end.md §13, FUN_004ff440 / FUN_004ff540, v1.1): Replay and Next Mission on
# a training mission open the Jet list (311–319 -> screen 9 under Basic, 321–329 -> screen 10 under
# Combat) so a plane is picked before each training flight; campaign missions reload (-> TSD); New
# Mission goes to the mission's list; Next is disabled when there is no next mission. The message box
# reads msgs.trx line 56 (v1.1's version-mismatch text) and any line past the file is empty.
extends "res://../tests/godot/base.gd"

var fe: Control


func debrief(id: int, passed := true) -> void:
	Settings().mission_id = id
	Settings().debrief = {"passed": passed, "headline": "", "notes": ""}
	fe.screen = "deb"
	fe.busy = false
	fe._enter_screen()
	await frames(2)


func run() -> void:
	fe = load("res://menu/front_end.tscn").instantiate()
	Settings().debrief = {"passed": true, "headline": "", "notes": ""}
	root.add_child(fe)
	await frames(2)
	var FE = fe.get_script()

	await debrief(311)
	fe._debrief_button("replaymission")
	await frames(90)
	check(fe.screen == "jet" and fe.jet_parent == "basic" and Settings().mission_id == 311, "Replay 311 -> Jet list (screen 9, under Basic)")
	check(Settings().debrief.is_empty(), "debrief consumed")

	await debrief(311)
	check(fe._button_enabled("Next_Mission"), "311 has a next mission")
	fe._debrief_button("nextmission")
	await frames(90)
	check(fe.screen == "jet" and Settings().mission_id == 312, "Next after 311 -> 312 on the Jet list")

	await debrief(315)
	fe._debrief_button("nextmission")
	await frames(90)
	check(fe.screen == "jet" and fe.jet_parent == "combat" and Settings().mission_id == 321, "Next after 315 -> 321, Jet list under Combat (screen 10)")

	await debrief(326)
	check(not fe._button_enabled("Next_Mission"), "326: no next mission, Next disabled")

	await debrief(322)
	fe._debrief_button("newmission")
	await frames(90)
	check(fe.screen == "combat", "New Mission after 322 -> Combat list")

	check(FE.next_mission(137, false) == 211, "137 -> 211")
	check(FE.next_mission(211, false) == 0 and FE.next_mission(211, true) == 212, "a Future front's next needs this one passed")
	check(FE.next_mission(217, true) == 0, "217 is the front's last")
	check(FE.new_mission_screen(124) == "his2mis" and FE.new_mission_screen(233) == "fut3mis" and FE.new_mission_screen(401) == "main", "New Mission lists")

	await debrief(111)
	fe._debrief_button("replaymission")
	await frames(120)
	check(fe.screen == "tsd" and fe.tsd_return == "his1mis", "Replay of a campaign mission reloads it -> TSD (BACK to its list)")

	var box = load("res://mission/mission_box.gd").new()
	box.setup(56, ["ok"])
	var lines: int = String(Settings().load_json(Settings().assets_dir().path_join("converted/menu/strings.json")).get("msgs", "")).split("\n").size()
	check(("version" in box.text) if lines >= 57 else box.text == "", "msgs.trx line 56: v1.1 version text, empty with v1.0 data (%d lines)" % lines)
	box.setup(400, ["ok"])
	check(box.text == "", "a line past the file is empty")
	box.free()
