# Pilot records (docs/front-end.md §13): the game starts on screen 0 with the default pilot; New_Pilot, the
# Dossier edit boxes and their checks (msgs 0x1c / 0x1a / 0x1b), Login; recording attempts (§13.7) with the
# score, best attempt and rank (§13.8); the Future fronts' locks (§13.11); the debrief recording; the list and
# history surviving a reload; Remove_Pilot (msg 0x1d). Runs in a temporary directory (IAF_DEFAULT_SETTINGS=1).
extends "res://../tests/godot/base.gd"

var fe: Control


func type_text(rec, s: String) -> void:
	for ch in s:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		rec._unhandled_input(e)


func click(p: Vector2, double := false) -> void:
	var at: Vector2 = fe._to_screen(p)
	fe.records._gui_input(mouse_button(at, true, double))
	fe.records._gui_input(mouse_button(at, false))


func ok_box() -> bool:
	var had: bool = fe.msgbox != null
	if had:
		var r: Rect2 = fe.msgbox.rects()[0]
		fe.msgbox._gui_input(mouse_button(r.get_center(), true))
		fe.msgbox._gui_input(mouse_button(r.get_center(), false))
	return had


func run() -> void:
	var Pilots = load("res://menu/pilots.gd")
	check(not Pilots.dir().begins_with("user://"), "tests keep the records in a temporary directory")
	fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
	check(fe.screen == "log" and fe.records != null, "the game starts on the Pilot Records screen")
	var rec = fe.records
	check(rec.data.pilots.size() == 1 and rec.data.pilots[0].name == "Gal" and rec.data.pilots[0].callsign == "default" \
		and rec.data.pilots[0].id == 14, "no records: the default pilot Gal / default, id 14")

	# New_Pilot: a blank record, id 15, selected; Login refuses the empty name.
	rec.new_pilot()
	check(rec.data.pilots.size() == 2 and rec.data.selected == 1 and rec.data.current().id == 15, "New_Pilot: blank pilot id 15 selected")
	check(not rec.login() and ok_box(), "Login with an empty name -> msg box")
	var page: Vector2 = rec.CONTENT + rec.PAGE
	click(page + rec.NAME_BOX.get_center())
	type_text(rec, "Ace!Pilot#1234567")
	check(rec.edit[0] == "AcePilot12", "name: only space . 0-9 a-z A-Z, at most 10 characters (%s)" % rec.edit[0])
	click(page + rec.CALL_BOX.get_center())
	check(rec.focus == 1 and rec.data.current().name == "AcePilot12", "focus to the callsign box writes the name")
	type_text(rec, "default")
	check(not rec.login() and ok_box(), "a callsign another pilot has -> msg 0x1b")
	for i in 7:
		var bs := InputEventKey.new()
		bs.pressed = true
		bs.keycode = KEY_BACKSPACE
		rec._unhandled_input(bs)
	type_text(rec, "viper")
	click(page + rec.PHOTO.get_center())
	check(rec.photo == 1, "a click on the photo shows the next one")
	check(rec.login() and Settings().pilot_id == 15 and Settings().pilot_name == "AcePilot12" \
		and Settings().pilot_callsign == "viper" and Settings().pilot_rank == "Second Lieutenant", "Login sets the pilot and rank")

	# Recording and scoring.
	check(Pilots.mission_bonus(311) == 500 and Pilots.mission_bonus(217) == 5000, "MissBonus from scores.ibx")
	# MiG-21 (cat 5, 500) and a tank (cat 16, 100) destroyed, own F-16 (cat 1, 800) lost, bonus 500.
	Pilots.record(15, 311, {"result": 1, "bonus": 500, "kills": [[150, 28], [250, 5]], "losses": [[100, 28]]}, 1.0)
	var h: Array = Pilots.history(15)
	var t: Dictionary = Pilots.totals(h)
	check(t.score == 300 and t.completed == 1 and t.k == [500, 100, 0] and t.l == [800, 0, 0], "attempt score 500 + 100 - 800 + 500 = 300 (%s)" % t)
	check(t.kill_groups[0] == 1 and t.kill_groups[5] == 1 and t.loss_groups[1] == 1, "Fighter, Tank kills; Adv Fighter loss")
	Pilots.record(15, 311, {"result": 0, "bonus": -250, "kills": [], "losses": []}, 1.0)
	check(Pilots.totals(Pilots.history(15)).score == 300, "a worse attempt does not lower the best")
	# Score multiplier 0.5: kills halved, bonus too; no scoring (0): nothing but a negative bonus.
	var a := {"result": 1, "mult": 0.5, "bonus": 1000, "kills": [], "losses": []}
	a.kills.resize(37)
	a.kills.fill(0)
	a.losses.resize(37)
	a.losses.fill(0)
	a.kills[32] = 1
	a.losses[16] = 1
	check(Pilots.attempt_score(a).score == 1500 + 500 - 100, "mult 0.5: trunc(3000·0.5) - 100 + 1000·0.5")
	a.mult = 0.0
	check(Pilots.attempt_score(a).score == 0, "mult 0 (no scoring): no kill, loss or bonus points")
	a.bonus = -500
	check(Pilots.attempt_score(a).score == -500, "a failed mission's negative bonus is not multiplied")
	check(Pilots.rank(4999) == "Second Lieutenant" and Pilots.rank(5000) == "Lieutenant" and Pilots.rank(99999) == "Colonel" \
		and Pilots.rank(100000) == "General", "rank table")
	check(Pilots.category(999, 2) == 15 and Pilots.category(999, 0xc) == 31 and Pilots.category(999, 4) == 37, "class fallback categories")

	# Future fronts: Mission 2 locked until Mission 1 is passed; an attempt out of order counts -1.
	fe.screen = "fut1mis"
	fe._enter_screen()
	check(fe._button_enabled("Mission 1") and not fe._button_enabled("Mission 2"), "Syrian front: Mission 2 locked")
	Pilots.record(15, 212, {"result": 1, "bonus": 1000, "kills": [], "losses": []}, 1.0)
	check(int(Pilots.attempts(Pilots.history(15), 212)[0].result) == -1, "212 before 211 is passed: result -1")
	Pilots.record(15, 211, {"result": 1, "bonus": 1000, "kills": [], "losses": []}, 1.0)
	fe._enter_screen()
	check(fe._button_enabled("Mission 2") and not fe._button_enabled("Mission 3"), "211 passed: Mission 2 open, 3 still locked")
	fe.screen = "his1mis"
	fe._enter_screen()
	check(fe._button_enabled("Mission 7"), "historical wars are open")

	# The debrief records the flight for the logged-in pilot.
	fe.queue_free()
	await frames(2)
	Settings().mission_id = 311
	Settings().debrief = {"passed": true, "headline": "", "notes": "", "result": 1, "bonus": 500, "kills": [[400, 12]], "losses": []}
	fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	check(fe.screen == "deb" and Pilots.attempts(Pilots.history(15), 311).size() == 3, "the debrief records the attempt")
	check(Pilots.totals(Pilots.history(15)).score == 200 + 500 + 1000 + 1000, "best 311 attempt (building 200 + bonus) counts (%d)" % Pilots.totals(Pilots.history(15)).score)
	Settings().debrief = {}

	# The list survives a reload with the selection; the new pilot's records are there.
	fe.screen = "log"
	fe._enter_screen()
	await frames(2)
	rec = fe.records
	check(rec.data.pilots.size() == 2 and rec.data.selected == 1 and rec.data.current().name == "AcePilot12" and rec.data.current().photo == 1,
		"pilot list and selection saved and read back")
	check(rec.totals.completed == 2, "Dossier: missions completed 311, 211")

	# A blank new pilot is dropped when the list is written.
	rec.new_pilot()
	fe.screen = "main"
	fe._enter_screen()
	await frames(2)
	var d = Pilots.new()
	d.load_list()
	check(d.pilots.size() == 2, "a blank selected pilot is not kept")

	# Remove_Pilot asks (msg 0x1d); Yes deletes the record and its history; the last pilot stays.
	fe.screen = "log"
	fe._enter_screen()
	await frames(2)
	rec = fe.records
	rec._select(1)
	rec.remove_pilot()
	check(fe.msgbox != null, "Remove_Pilot asks first")
	ok_box()
	check(rec.data.pilots.size() == 1 and rec.data.selected == 0 and Pilots.history(15).is_empty(), "Yes: pilot and history removed")
	rec.remove_pilot()
	check(rec.data.pilots.size() == 1 and fe.msgbox == null, "the last pilot cannot be removed")

	# A double-click on the selected pilot logs in and goes to Main.
	click(rec.LIST + rec.ITEMS.position + Vector2(10, 5), true)
	await frames(60)
	check(fe.screen == "main" and Settings().pilot_id == 14, "double-click logs in -> Main")
	Settings().pilot_id = -1
	fe.queue_free()
