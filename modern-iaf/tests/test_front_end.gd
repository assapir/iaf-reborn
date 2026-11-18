# Modern IAF's front end (modern-iaf/docs/front-end.md), headless, in English and Hebrew: the Hangar → Missions →
# Training → the briefing → (the flight skipped) → the Debrief of a stored record (Back to missions, Fly again, Next
# mission) → the section's list; each jet's own missions only (numbered after the filter, its own progress);
# the texts each screen shows, the mirrored layout in Hebrew, the plane pick (Settings.sim_jet, the F-16 switch), the
# Preferences' controls and the live language switch both ways, the Pilot log (a row opens its debrief), a failed
# record's reasons and Attributions. Then a `--mission` run on a profile without a picked plane: the mission flies at
# once, the start command, the scoring, Esc's pause menu over the flight, its Preferences and back, End the flight,
# that flight's debrief, and Esc to the Training list in the mission's jet (the real run of front-end.md "Checks", also
# in a real render through tools/godot_window.sh; SHOT_DIR=<dir>
# saves the pause menu and the debrief in both languages). The records go to the isolated records folder
# (Settings.records_dir, a temporary folder): the fixture writes the JSON records from before the database there, and
# the store's first open imports them.
# IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf
# \     -s ../modern-iaf/tests/test_front_end.gd --log-file <temp>
extends "res://tests/test_mvp.gd"

const STAMP := "20261102-080000"
## The sample recording of the take-off (tests/data/sample_flight.py).
const SAMPLE_FLIGHT := "res://tests/data/ramon_takeoff_flight.jsonl"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	# The sim has no aids (the user, 2026-11-08): every switch of the original's Gameplay page off.
	for k in [
		"no_wind",
		"no_blackouts",
		"no_spins",
		"no_stalls",
		"easy_landing",
		"easy_aiming",
		"no_malfunctions",
		"invulnerable",
		"no_crashes",
		"unlimited_ammo",
		"unlimited_fuel"
	]:
		check(s.get(k) == false, "settings: no aid on (%s = %s)" % [k, s.get(k)])
		check(not s.has_setting(k), "settings: the logs name no aid (%s)" % k)
	# The start-up log's dump (settings.gd _log_startup) names only the sim's settings.
	var dump: Dictionary = s.changed_settings()
	check(dump.keys().all(func(k): return s.has_setting(k)), "settings: the log dump is the sim's own (%s)" % [dump])
	for k in ["airbases", "language", "shadows", "cockpit_3d"]:
		check(s.has_setting(k), "settings: the sim has %s" % k)
	var ids := fixture(s)
	fly_gd = load("res://flight/fly.gd")
	s.sim_jet = ""
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	await first_start(fe)
	check(fe.page == "hangar" and fe.find_child("JetCard", true, false) != null, "first start: then the Hangar")
	check(fe.find_child("change_plane", true, false) == null, "the Hangar: no Change plane")
	s.sim_jet = ""
	for lang in ["en", "he"]:
		s.language = lang
		await walk(fe, ids, lang)
	s.language = "en"
	await crumbs(fe)
	for lang in ["en", "he"]:
		s.language = lang
		await two_flights(fe, lang)
	s.language = "en"
	await jet_missions(fe)
	await prefs(fe)
	for lang in ["en", "he"]:
		s.language = lang
		await pilot(fe, lang)
	s.language = "en"
	await overlay_fits()
	await fly_once(fe)


## The first start (no profile stored): the Pilot screen makes one before the Hangar, Save only with a name, Esc stays;
## no pilot in the top bar yet; the empty picture a head and shoulders, then the initials as the name is typed; Up /
## Down between Name and Nickname; Save stores the name on the active pilot (its imported sorties kept) and opens the
## Hangar.
func first_start(fe: Control) -> void:
	var s := settings()
	check(fe.page == "pilot" and fe.first_start(), "a first start opens the Pilot screen to make the profile")
	check(_has(fe, "Create your pilot") and fe.find_child("JetCard", true, false) == null, "first start: no Hangar yet")
	var save: Button = fe.find_child("Save", true, false)
	check(save != null and save.disabled, "first start: Save waits for a name")
	check(
		fe.find_child("Back", true, false) == null and fe.find_child("ResetLog", true, false) == null,
		"first start: Save only"
	)
	key(fe, KEY_ESCAPE)
	await frames(1)
	check(fe.page == "pilot", "first start: Esc stays")
	check(fe.find_child("PilotName", true, false) == null, "first start: no pilot in the top bar yet")
	var ini: Label = fe.find_child("Initials", true, false)
	var empty: Control = fe.find_child("Placeholder", true, false)
	check(ini != null and ini.text == "" and empty.visible, "first start: the empty picture a head and shoulders")
	var e: LineEdit = fe.find_child("Field_name", true, false)
	await type_into(e, "Noa Golan")
	check(not save.disabled and e.text == "Noa Golan", "first start: typed, Save on (%s)" % e.text)
	check(ini.text == "NG" and not empty.visible, "first start: the initials as typed (%s)" % ini.text)
	var vp := fe.get_viewport()
	vp.push_input(_key_event(KEY_DOWN), true)
	await frames(1)
	check(vp.gui_get_focus_owner().name == "Field_nickname", "first start: Down from Name: Nickname")
	vp.push_input(_key_event(KEY_DOWN), true)
	await frames(1)
	check(vp.gui_get_focus_owner().name == "ChoosePicture", "first start: Down from Nickname: Choose a picture")
	vp.gui_get_focus_owner().release_focus()
	fe.find_child("Field_nickname", true, false).grab_focus()
	vp.push_input(_key_event(KEY_UP), true)
	await frames(1)
	check(vp.gui_get_focus_owner() == e, "first start: Up from Nickname: Name")
	e.grab_focus()
	save.pressed.emit()
	await frames(2)
	var p = JSON.parse_string(IafPilotLog.pilot(s.records_db(), s.pilot()))
	check(fe.page == "hangar" and p.name == "Noa Golan", "first start: Save stores the name and opens the Hangar")
	check(s.pilot() == IafPilotLog.default_pilot(), "first start: the profile on the active pilot")
	fe.show_page("hangar")
	await frames(1)
	check(fe.page == "hangar", "with a profile: the Hangar")


## Clicks LineEdit `e` and types `t` through the viewport, as a player does.
func type_into(e: LineEdit, t: String) -> void:
	var vp := e.get_viewport()
	for down in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = down
		m.position = e.get_global_rect().get_center()
		vp.push_input(m, true)
	await frames(1)
	check(e.has_focus(), "%s: a click focuses it" % e.name)
	e.select_all()
	for ch in t:
		for down in [true, false]:
			var k := InputEventKey.new()
			k.unicode = ch.unicode_at(0)
			k.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
			k.pressed = down
			vp.push_input(k, true)
	await frames(1)


## The Pilot screen from the pilot's name in the Hangar: the nickname typed, Back's discard prompt, Save to the Hangar
## with the nickname and the name in its top bar; the picture (the frame's click opens the picker) shown at once and
## copied beside the records on Save; the logbook per plane; Change pilot: a new pilot made and active, a sortie of its
## own reset after the warning and the second confirm, then the first pilot picked back.
func pilot(fe: Control, lang: String) -> void:
	var he := lang == "he"
	var s := settings()
	var db: String = s.records_db()
	fe.show_page("hangar")
	await frames(2)
	var link: Button = fe.find_child("PilotBlock", true, false)
	check(
		(
			link != null
			and link.focus_mode == Control.FOCUS_ALL
			and link.find_child("PilotName", true, false) != null
			and link.find_child("PilotName", true, false).mouse_filter == Control.MOUSE_FILTER_IGNORE
		),
		"%s: the Hangar: the pilot block is one button" % lang
	)
	check(fe.find_child("nickname_note", true, false) == null, "%s: no note under the fields" % lang)
	link.pressed.emit()
	await frames(2)
	check(fe.page == "pilot" and fe.is_layout_rtl() == (lang == "he"), "%s: the block opens the Pilot screen" % lang)
	check(not _has_part(fe, "בראש כל מסך" if he else "every screen"), "%s: Pilot: no note on where it shows" % lang)
	var nick: LineEdit = fe.find_child("Field_nickname", true, false)
	check(
		nick.text == "" and nick.placeholder_text != fe.pilot_name(),
		"%s: the nickname field: a hint, not the name" % lang
	)
	await type_into(nick, "Viper")
	check(nick.text == "Viper", "%s: the nickname is typed in (%s)" % [lang, nick.text])
	# The logbook: the Sufa's three imported sorties (their plane from the missions), the take-off's pass and fail.
	var book: Control = fe.find_child("Logbook", true, false)
	check(book != null and book.find_child("Plane_f16i", true, false) != null, "%s: the logbook's Sufa" % lang)
	check(
		(
			_has(book, "F-16I סופה" if he else "F-16I Sufa")
			and _has(book, "3 טיסות · 2 הצלחות · 1 כישלונות" if he else "3 flights · 2 passed · 1 failed")
		),
		"%s: the logbook's counts" % lang
	)
	check(
		_has(book, "המראה" if he else "Take-off") and _has(book, "כישלונות 1" if he else "Failed 1"),
		"%s: per mission" % lang
	)
	# Back with a change: the prompt; Keep editing keeps the draft.
	fe.back()
	await frames(1)
	check(fe.find_child("Modal", true, false) != null and fe.page == "pilot", "%s: Back asks before discarding" % lang)
	(fe.find_child("ModalCancel", true, false) as Button).pressed.emit()
	await frames(1)
	check(fe.find_child("Modal", true, false) == null and nick.text == "Viper", "%s: Keep editing keeps it" % lang)
	# The picture: a click on the frame opens the picker; a picture shows at once, stored on Save.
	var fr: Control = fe.find_child("Picture", true, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	fr.gui_input.emit(click)
	var dialog := fe.find_child("PictureDialog", true, false)
	check(dialog != null, "%s: a click on the picture opens the file picker" % lang)
	if dialog != null:
		dialog.free()
	var png := OS.get_temp_dir().path_join("iaf2026-test-pilot-%d.png" % OS.get_process_id())
	Image.create(30, 40, false, Image.FORMAT_RGB8).save_png(png)
	check(not fe.set_picture(db), "%s: a file that is no picture is refused" % lang)
	check(fe.set_picture(png), "%s: the picture is taken" % lang)
	await frames(2)
	fr = fe.find_child("Picture", true, false)
	check(
		fr != null and is_equal_approx(fr.size.x / fr.size.y, 0.75) and fr.find_child("*", true, false) is TextureRect,
		"%s: the picture in its 3:4 frame (%s)" % [lang, fr.size if fr != null else null]
	)
	check(JSON.parse_string(IafPilotLog.pilot(db, s.pilot())).picture == "", "%s: not stored before Save" % lang)
	(fe.find_child("Save", true, false) as Button).pressed.emit()
	await frames(2)
	var p = JSON.parse_string(IafPilotLog.pilot(db, s.pilot()))
	check(fe.page == "hangar" and p.nickname == "Viper", "%s: Save stores and opens the Hangar: %s" % [lang, p])
	check(FileAccess.file_exists(str(p.picture)) and p.picture != png, "%s: copied beside the records" % lang)
	check(fe.find_child("PilotName", true, false).text == "Viper", "%s: the Hangar: the nickname" % lang)
	var full: Label = fe.find_child("PilotFullName", true, false)
	check(full != null and full.text == "Noa Golan", "%s: the Hangar: the name under it" % lang)
	fe.show_page("log")
	await frames(2)
	check(_has(fe, "Viper"), "%s: the Pilot log's top bar shows the nickname" % lang)
	await switch_and_reset(fe, lang)
	IafPilotLog.set_pilot(db, s.pilot(), "Noa Golan", "")
	IafPilotLog.set_picture(db, s.pilot(), "")
	DirAccess.remove_absolute(png)


## Change pilot → New pilot → a second pilot made and active; a sortie of its own, Reset after two confirms; the
## pilot list picks the first one back.
func switch_and_reset(fe: Control, lang: String) -> void:
	var he := lang == "he"
	var s := settings()
	var db: String = s.records_db()
	var first: int = s.pilot()
	fe.show_page("pilot")
	await frames(2)
	(fe.find_child("OtherPilots", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "pilots" and fe.find_child("Pilot_%d" % first, true, false) != null, "%s: the pilot list" % lang)
	check(_has(fe, "בשימוש" if he else "Current"), "%s: the list marks the active pilot" % lang)
	(fe.find_child("NewPilot", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "pilot" and fe.creating and _has(fe, "פרופיל חדש" if he else "New pilot"), "%s: New pilot" % lang)
	check((fe.find_child("Field_name", true, false) as LineEdit).text == "", "%s: New pilot: empty" % lang)
	await type_into(fe.find_child("Field_name", true, false), "Dana")
	(fe.find_child("Save", true, false) as Button).pressed.emit()
	await frames(2)
	var second: int = s.pilot()
	check(fe.page == "hangar" and second != first and fe.pilot_name() == "Dana", "%s: the new pilot active" % lang)
	check(JSON.parse_string(IafPilotLog.sorties(db, second)).is_empty(), "%s: the new pilot's log is empty" % lang)
	IafPilotLog.log_sortie(
		db,
		second,
		2011,
		JSON.stringify(
			{
				"mission": "ramon_startup",
				"pass": true,
				"date": "2026-11-10T09:00:00",
				"elapsed_s": 60.0,
				"plane": "f16i"
			}
		)
	)
	fe.show_page("pilot")
	await frames(2)
	var reset: Button = fe.find_child("ResetLog", true, false)
	check(reset != null and not reset.disabled, "%s: Reset with a flight" % lang)
	reset.pressed.emit()
	await frames(1)
	check(_has(fe, "לאפס את יומן הטיסות?" if he else "Reset the pilot log?"), "%s: the reset's warning" % lang)
	var ok: Button = fe.find_child("ModalOk", true, false)
	check(ok.text == ("לאפס" if he else "Reset"), "%s: the modal's Reset" % lang)
	ok.pressed.emit()
	await frames(1)
	check(_has(fe, "לאפס סופית?" if he else "Reset for good?"), "%s: the second confirm" % lang)
	check(JSON.parse_string(IafPilotLog.sorties(db, second)).size() == 1, "%s: nothing deleted before it" % lang)
	(fe.find_child("ModalOk", true, false) as Button).pressed.emit()
	await frames(2)
	check(JSON.parse_string(IafPilotLog.sorties(db, second)).is_empty(), "%s: Reset empties the log" % lang)
	check(not JSON.parse_string(IafPilotLog.sorties(db, first)).is_empty(), "%s: the other pilot's log stays" % lang)
	check(fe.find_child("Modal", true, false) == null and fe.page == "pilot", "%s: back on the Pilot screen" % lang)
	# Delete profile: the warning, the second confirm, then the pilot list without the pilot.
	IafPilotLog.log_sortie(db, second, 2011, JSON.stringify({"mission": "ramon_startup", "pass": true}))
	(fe.find_child("DeleteProfile", true, false) as Button).pressed.emit()
	await frames(1)
	check(_has(fe, "למחוק את הפרופיל?" if he else "Delete the profile?"), "%s: the delete's warning" % lang)
	(fe.find_child("ModalOk", true, false) as Button).pressed.emit()
	await frames(1)
	check(_has(fe, "למחוק סופית?" if he else "Delete for good?"), "%s: the delete's second confirm" % lang)
	check(JSON.parse_string(IafPilotLog.pilot(db, second)).name == "Dana", "%s: nothing deleted before it" % lang)
	(fe.find_child("ModalOk", true, false) as Button).pressed.emit()
	await frames(2)
	check(
		(
			fe.page == "pilots"
			and fe.find_child("Pilot_%d" % second, true, false) == null
			and fe.find_child("Pilot_%d" % first, true, false) != null
		),
		"%s: Delete opens the pilot list without the pilot" % lang
	)
	check(JSON.parse_string(IafPilotLog.sorties(db, second)).is_empty(), "%s: its flights deleted" % lang)
	(fe.find_child("Pilot_%d" % first, true, false) as Button).pressed.emit()
	await frames(2)
	check(
		fe.page == "hangar" and s.pilot() == first and fe.pilot_name() == "Viper",
		"%s: the first pilot picked back" % lang
	)


## The breadcrumbs open their screens and keep the picks; the current one is no button.
func crumbs(fe: Control) -> void:
	var s := settings()
	s.sim_jet = "f16i"
	fe.section = "training"
	fe.mission_i = 1
	fe.show_page("mission")
	await frames(2)
	check(
		not _has_button(fe, fe.title_of(fe.missions[1])) and _has_button(fe, fe.s("sec_training")),
		"crumbs: the current screen (the mission) is no button, Training before it is"
	)
	var home: Button = fe.find_child("Crumb_hangar", true, false)
	check(home != null and home.focus_mode != Control.FOCUS_NONE, "crumbs: the Hangar is a button the keys reach")
	home.pressed.emit()
	await frames(2)
	check(fe.page == "hangar", "crumbs: the Hangar crumb from the mission screen opens the Hangar")
	fe.show_page("mission")
	await frames(2)
	check(fe.mission_i == 1 and s.sim_jet == "f16i", "crumbs: the plane and the picked mission kept")
	(fe.find_child("Crumb_section", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "section", "crumbs: the section's crumb opens its list")
	(fe.find_child("Crumb_missions", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "missions", "crumbs: the jet's crumb opens the Missions screen")
	(fe.find_child("Crumb_jet", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "hangar", "crumbs: on the Missions screen the jet's crumb opens the Hangar")
	fe.open_debrief(int(fe.sorties()[-1].id))
	await frames(2)
	(fe.find_child("Crumb_section", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "section", "crumbs: the debrief's Training crumb opens the section's list")


## A mission of two flights (N1; the sample modern-iaf/tests/data/two_flights.json, test data, not a shipped mission):
## FLIGHTS tabs Alpha (the player's, picked) and Bravo over a line for the picked flight (its jets, task, stores),
## Bravo's route on the map, picked by its tab; up from Edit the tabs.
func two_flights(fe: Control, lang: String) -> void:
	var m: Dictionary = settings().load_json("res://tests/data/two_flights.json")
	m["_file"] = "res://tests/data/two_flights.json"
	fe.section = "training"
	fe.missions = [m]
	fe.open_mission(0)
	await frames(2)
	var tabs: Control = fe.find_child("FlightTabs", true, false)
	check(tabs != null and tabs.get_child_count() == 2, "%s: flights: two tabs" % lang)
	if tabs == null:
		return
	var a: Button = tabs.find_child("Flight_Alpha", false, false)
	var b: Button = tabs.find_child("Flight_Bravo", false, false)
	check(a != null and b != null and a.button_pressed and not b.button_pressed, "%s: flights: Alpha picked" % lang)
	var detail: Label = fe.find_child("FlightDetail", true, false)
	check(
		detail.text.begins_with(fe.s("your_flight")) and detail.text.contains("F-16I"),
		"%s: flights: the player's line (%s)" % [lang, detail.text]
	)
	var map: Control = fe.find_child("PageMap", true, false)
	await frames(2)
	var others: Array = map.data.get("flights", [])
	check(others.size() == 1 and others[0].callsign == "Bravo", "%s: map: Bravo's route" % lang)
	check(map.selected == "Alpha", "%s: map: the player's flight picked" % lang)
	b.button_pressed = true
	await frames(1)
	check(
		map.selected == "Bravo" and detail.text.contains("2 × ") and detail.text.contains("F-15C"),
		"%s: flights: Bravo's line and route picked (%s)" % [lang, detail.text]
	)
	check(detail.text.contains(fe.s("task_cap")), "%s: flights: Bravo's task" % lang)
	var xf: Transform2D = map._xf()
	var bravo: Array = others[0].pts
	var room: Rect2 = map._room().grow(40)
	check(
		room.has_point(xf * Vector2(float(bravo[0]), float(bravo[1]))),
		"%s: map: Bravo picked, its route in view" % lang
	)
	var edit: Button = fe.find_child("ArmEdit", true, false)
	check(edit.get_node(edit.focus_neighbor_top) == a, "%s: flights: up from Edit the tabs" % lang)
	check(a.get_node(a.focus_neighbor_bottom) == edit, "%s: flights: down from the tabs Edit" % lang)
	fe.show_page("section")
	await frames(2)


## Each jet's own missions (the user, 15 Nov: "show only the same plane missions"): the list holds the Hangar jet's
## missions only, numbered 1, 2 … after the filter, with that jet's progress, Next and side panel; a mission flies in
## its own jet (no other unit in the player's slot).
func jet_missions(fe: Control) -> void:
	var s := settings()
	var want := {"f16i": [2011, 2012, 2013], "f16d": [2021, 2022, 2023], "f35i": [2031, 2032, 2033]}
	for unit in want:
		s.sim_jet = unit
		fe.section = "training"
		fe.show_page("section")
		await frames(2)
		var ids: Array = fe.missions.map(func(m): return int(m.menu_id))
		check(ids == want[unit], "jets: the %s lists its own missions (%s)" % [unit, ids])
		var rows: Array = fe.find_child("List", true, false).get_children()
		check(
			rows.size() == 3 and _has(rows[0], "1") and _has(rows[2], "3") and rows[2].name == "Mission3",
			"jets: the %s's list numbered 1, 2, 3" % unit
		)
	# The Barak: nothing flown on it (the fixture's flights are the Sufa's): 0 of 3, its first one Next.
	s.sim_jet = "f16d"
	fe.section = "training"
	fe.show_page("section")
	await frames(2)
	check(_has_part(fe, "0 of 3 passed"), "jets: the Barak's own progress")
	var rows: Array = fe.find_child("List", true, false).get_children()
	check(rows[0].find_child("NextUp", true, false) != null and rows[0].has_focus(), "jets: the Barak's first is Next")
	var side: Control = fe.find_child("Side", true, false)
	check(
		_has(side, "Start-up") and _has(side, "Ramat David") and _has(side, "Not flown yet") and _has(side, "—"),
		"jets: the side panel: the Barak's start-up, not flown, no best time"
	)
	fe.show_page("hangar")
	await frames(2)
	check(_has(fe.find_child("JetCard", true, false), "0 of 3 passed"), "jets: the Hangar card: the Barak's progress")
	# A mission flies in its own jet: the compiled data as it is, its unit picked.
	check(fly_gd.prepare(2012), "jets: Ramon's take-off prepared")
	check(s.sim_jet == "f16i" and not s.mission_files_override[0].data.has("readable"), "jets: flown in the Sufa")
	# Next mission follows the mission's own jet, whatever the Hangar picked.
	s.sim_jet = "f16d"
	check(fe.next_of(fe.mission_by_id(2011)) == 2012, "jets: next_of the Sufa's start-up is its take-off")
	s.mission_files_override = []
	s.sim_jet = "f16i"


## The pause menu over a flight in viewports of several sizes, both languages: on its first frame the panel lies
## inside the viewport with its labels (the Mac's 2026-11-08 Hebrew pause menu sat off the right edge).
func overlay_fits() -> void:
	var s := settings()
	for lang in ["en", "he"]:
		s.language = lang
		for vs in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1280, 800)]:
			var vp := SubViewport.new()
			vp.size = vs
			get_root().add_child(vp)
			var layer := CanvasLayer.new()
			vp.add_child(layer)
			var o: Control = load("res://menu/front_end.gd").new()
			o.flight = Node.new()
			o.screen = "flytsd"
			layer.add_child(o)
			await frames(1)
			var panel: Control = o.find_child("Pause", true, false)
			var r := panel.get_global_rect() if panel != null else Rect2()
			var view := Rect2(Vector2.ZERO, Vector2(vs))
			var dim: Control = o.get_child(0)
			check(
				r.size.x > 0 and view.encloses(r) and absf(r.get_center().x - vs.x / 2.0) < 2.0,
				"overlay %s %s: the pause menu centred inside the view (%s)" % [lang, vs, r]
			)
			check(view.is_equal_approx(dim.get_global_rect()), "overlay %s %s: the dim covers the view" % [lang, vs])
			var resume: Button = o.find_child("Resume", true, false)
			check(resume != null and resume.text != "", "overlay %s %s: the buttons are labelled" % [lang, vs])
			o.flight.free()
			vp.queue_free()
			await frames(1)
	s.language = "en"


func fly_once(fe: Control) -> void:
	var s := settings()
	s.sim_jet = ""
	check(fe.start_args(PackedStringArray(["--mission", "2011"])), "fly: --mission 2011 starts")
	check(s.sim_jet == "f16i", "fly: the mission's jet is picked (%s)" % s.sim_jet)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	check(tv.mission_id == 2011, "fly: Ramon's start-up loads")
	for k in [KEY_F1, KEY_F2, KEY_F3, KEY_F4]:
		var f := _key_event(k)
		tv._unhandled_input(f)
		f = f.duplicate()
		f.pressed = false
		tv._unhandled_input(f)
	await frames(2)
	check(tv.fe_overlay == null, "fly: F1–F4 only switch views (no pause menu)")
	tv._unhandled_input(_key_event(KEY_F1))
	check(tv.in_cockpit, "fly: F1 is the cockpit")
	Engine.time_scale = 6.0
	# The tower's start-up clearance first (training.md §3.3).
	check(tv.addon.pick("startup") == "ACFT_CLEAR_TO_START", "fly: the tower clears the start-up")
	# The lesson's items of the checklist card (training.md §12), by test_mvp's helper: the start-up steps by their keys.
	await _fly_card(tv, func(it): return it.id in tv.addon.checklist, true)
	var t0 := Time.get_ticks_msec()
	while tv.addon.result.is_empty() and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	Engine.time_scale = 1.0
	check(bool(tv.addon.result.get("pass", false)), "fly: the start-up scored a pass")
	var shot := OS.get_environment("SHOT_DIR")
	# The pass pauses the flight under the accomplished panel (training.md §9), once the radio's speech is said.
	t0 = Time.get_ticks_msec()
	while tv.fe_overlay == null and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	var done: Node = tv.fe_overlay
	check(
		done != null and done.page == "accomplished" and paused and _has(done, "Mission accomplished"),
		"fly: the pass pauses the flight under Mission accomplished"
	)
	check(
		done != null and done.get_viewport().gui_get_focus_owner() == done.find_child("Continue", true, false),
		"fly: Continue focused"
	)
	if shot != "" and done != null:
		await _shots(done, shot, "accomplished")
	key(done, KEY_ESCAPE)  # Esc = Continue: never the flight's end by accident
	await frames(2)
	check(tv.fe_overlay == null and not paused, "fly: Esc on the panel continues the flight")
	var sim_t: float = tv._sim_time
	await frames(30)
	check(tv.fe_overlay == null and tv._sim_time > sim_t, "fly: the flight goes on, the panel not back")
	tv._esc_key()
	await frames(3)
	var pause: Node = tv.fe_overlay
	check(pause != null and pause.page == "pause" and _has(pause, "Paused"), "fly: Esc opens the pause menu")
	var flying: Label = pause.find_child("Flying", true, false)
	var want: String = "%s · %s" % [pause.mission_title(int(tv.mission_id)), pause.full_name(pause.jet())]
	check(flying != null and flying.text == want and want.length() > 5, "fly: the pause menu names the mission and jet")
	pause.find_child("PausePrefs", true, false).pressed.emit()
	await frames(2)
	check(
		pause.page == "prefs" and pause.find_child("Section_graphics", true, false) != null, "fly: pause, Preferences"
	)
	# The front end's bars over the flight: the crumb back to the pause menu and the footer's Back.
	check(pause.find_child("Crumb_pause", true, false) != null, "fly: Settings over the flight, crumb Paused")
	check(pause.find_child("Back", true, false) != null, "fly: Settings over the flight, the footer's Back")
	var pane: Control = pause.find_child("SectionPane", true, false)
	var last: Control = pause.find_child("Pref_vsync", true, false)
	check(
		pane != null and last != null and last.get_global_rect().end.y <= pane.get_global_rect().end.y + 1,
		"fly: Settings over the flight, Graphics whole (VSync not cut)"
	)
	(pause.find_child("Section_graphics", true, false) as Button).pressed.emit()
	await frames(2)
	check(pause.find_child("Pref_shadows", true, false) != null, "fly: pause, Preferences, Graphics")
	key(pause, KEY_ESCAPE)
	await frames(2)
	check(pause.page == "pause" and tv.fe_overlay == pause, "fly: Esc from Preferences back to the pause menu")
	if shot != "":
		await _shots(pause, shot, "pause")
	pause.find_child("QuitDesktop", true, false).pressed.emit()
	await frames(2)
	check(pause.find_child("ModalOk", true, false) != null, "fly: Quit to desktop asks before it quits")
	pause.close_modal()
	await frames(2)
	pause.find_child("EndFlight", true, false).pressed.emit()
	var back: Node = null
	while back == null or back.get("page") == null:
		await process_frame
		back = current_scene
	await frames(3)
	check(
		back.page == "debrief" and str(back.record.get("mission", "")) == "ramon_startup",
		"fly: the flight's end opens its debrief"
	)
	check(not _has(back, "Time to idle"), "fly: the start-up's debrief shows no numbers (no goals)")
	check(_has(back, "The engine at idle with the avionics up. Nothing failed."), "fly: the start-up's pass remark")
	var exp: Button = back.find_child("ExportFlight", true, false)
	check(
		exp != null and not exp.disabled and FileAccess.file_exists(str(back.record.get("flight", ""))),
		"fly: the debrief's Export flight data offers the flight's recording"
	)
	if shot != "":
		await _shots(back, shot, "flown_debrief")
	key(back, KEY_ESCAPE)
	await frames(2)
	check(
		back.page == "section" and settings().sim_jet == "f16i" and _has(back, "F-16I Sufa"),
		"fly: Esc from the debrief opens the Training list in the jet flown (%s, %s)" % [back.page, settings().sim_jet]
	)


## Saves the screen in English and Hebrew as <name>_<lang>.png (the page rebuilt in each language).
func _shots(fe: Node, dir: String, name: String) -> void:
	for lang in ["en", "he"]:
		settings().language = lang
		fe.show_page(fe.page)
		await frames(8)
		get_root().get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [name, lang]))
	settings().language = "en"
	fe.show_page(fe.page)


func walk(fe: Control, ids: Dictionary, lang: String) -> void:
	var he := lang == "he"
	var s := settings()
	s.sim_jet = "f16i"
	fe.show_page("hangar")
	await frames(2)
	check(
		fe.layout_direction == (Control.LAYOUT_DIRECTION_RTL if he else Control.LAYOUT_DIRECTION_LTR),
		"%s: layout direction" % lang
	)
	check(fe.is_layout_rtl() == he, "%s: mirrored layout flag" % lang)
	check(_has(fe, "הזרוע הארוכה" if he else "Modern IAF"), "%s: the sim's name in the header" % lang)
	# Each jet's card: its squadron and base (no wing: the wing is the base).
	var subs := (
		[["201 האחת", "רמון"], ["101 הקרב הראשונה", "רמת דוד"], ["116 אריות הדרום", "נבטים"]]
		if he
		else [["201 The One", "Ramon"], ["101 First Fighter", "Ramat David"], ["116 Lions of the South", "Nevatim"]]
	)
	for i in 3:
		(fe.find_child(["sufa", "barak", "adir"][i], true, false) as Button).pressed.emit()
		await frames(2)
		var card: Control = fe.find_child("JetCard", true, false)
		check(_has(card, subs[i][0]) and _has(card, subs[i][1]), "%s: hangar: %s" % [lang, subs[i]])
		check(not _has_part(fe, "כנף" if he else "Wing"), "%s: hangar: no wing" % lang)
	# The Ra'am and the Baz: listed with their squadron and base, disabled (no pick, no focus, dimmed), no text on why.
	for t in ["טייסת 69 · חצרים", "טייסת 133 · תל נוף"] if he else ["69 Squadron · Hatzerim", "133 Squadron · Tel Nof"]:
		check(_has(fe, t), "%s: hangar: %s" % [lang, t])
	for n in ["raam", "baz"]:
		var off: Button = fe.find_child(n, true, false)
		check(
			off.disabled and off.focus_mode == Control.FOCUS_NONE and off.modulate.a < 1.0 and not off.button_pressed,
			"%s: the %s row greyed and not pickable" % [lang, n]
		)
	var picked: String = s.sim_jet
	fe.find_child("raam", true, false).pressed.emit()  # no handler: a press picks nothing
	await frames(2)
	check(s.sim_jet == picked, "%s: the Ra'am row picks nothing" % lang)
	fe.find_child("barak", true, false).pressed.emit()
	await frames(2)
	check(s.sim_jet == "f16d" and s.f16_variant == "barak", "%s: the Barak picked" % lang)
	fe.find_child("sufa", true, false).pressed.emit()
	await frames(2)
	check(s.sim_jet == "f16i" and s.f16_variant == "sufa", "%s: the Sufa picked (sim_jet, the F-16 switch)" % lang)
	check(fe.find_child("Campaign", true, false) == null, "%s: hangar: no campaign button (Missions has it)" % lang)
	check(_has(fe, "2 מתוך 3 עברו" if he else "2 of 3 passed"), "%s: hangar: the Sufa's own progress" % lang)
	fe.find_child("Fly", true, false).pressed.emit()
	await frames(2)
	await _missions_checks(fe, lang)
	fe.find_child("Mission2", true, false).pressed.emit()
	await frames(2)
	check(_has(fe, "המראה" if he else "Take-off"), "%s: mission: the take-off picked" % lang)
	check(_has_part(fe, "25R"), "%s: mission: the runway" % lang)
	check(_has(fe, "15") and _has(fe, "דקות" if he else "min"), "%s: mission: the time allowed" % lang)
	await _briefing_checks(fe, lang)
	# The flight is skipped: the stored record comes back as the flight's.
	s.flown_sortie = ids.pass
	fe.show_page("hangar")
	fe._ready()
	await frames(2)
	check(fe.page == "debrief", "%s: a flight's end opens its debrief" % lang)
	await _debrief_checks(fe, lang, ids)
	# After the take-off the Sufa's weapons range: Next mission, focused.
	var nm: Button = fe.find_child("NextMission", true, false)
	check(nm != null and nm.has_focus(), "%s: debrief: Next mission (the range) focused" % lang)
	var order := ["BackMissions", "FlyAgain", "NextMission"]
	var foot: Array = fe.find_child("Footer", true, false).get_children().filter(func(c): return c.name in order)
	check(foot.map(func(c): return str(c.name)) == order, "%s: debrief: the buttons' order" % lang)
	fe.find_child("BackMissions", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "section" and fe.section == "training", "%s: Back to missions: the Training list" % lang)
	fe.open_debrief(ids.pass)
	await frames(2)
	fe.find_child("FlyAgain", true, false).pressed.emit()
	await frames(2)
	check(
		fe.page == "mission" and fe.mission_i == 1,
		"%s: Fly again opens the flown take-off's briefing, not the flight" % lang
	)
	check(_has_button(fe, "אימונים" if he else "Training"), "%s: Fly again: the Training breadcrumb" % lang)
	var fly_btn: Control = fe.find_child("Fly", true, false)
	check(fly_btn != null and fly_btn.has_focus(), "%s: Fly again: the briefing's Fly focused" % lang)
	# The start-up's debrief: Next mission is the Sufa's take-off.
	fe.open_debrief(ids.startup)
	await frames(2)
	var next: Button = fe.find_child("NextMission", true, false)
	check(
		next != null and next.text == ("המשימה הבאה" if he else "Next mission") and next.has_focus(),
		"%s: debrief: Next mission, focused" % lang
	)
	next.pressed.emit()
	await frames(2)
	check(
		fe.page == "mission" and fe.mission_i == 1 and fe.missions[1].id == "ramon_takeoff",
		"%s: Next mission: the jet's next one's briefing (Ramon's take-off)" % lang
	)
	var last: Dictionary = fe.missions[-1]
	check(fe.next_of(last) == 0 and fe.next_of(fe.missions[0]) == int(fe.missions[1].menu_id), "%s: next_of" % lang)
	fe.open_debrief(ids.pass)
	await frames(2)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "section", "%s: Esc from the debrief: the section's list" % lang)
	fe.show_page("hangar")
	await frames(2)
	check(fe.find_child("pilot_log", true, false) == null, "%s: hangar: no Pilot log entry (the pilot block's)" % lang)
	check(fe.find_child("credits", true, false) is Button, "%s: hangar: Attributions" % lang)
	var mn: Button = fe.find_child("manuals", true, false)
	check(mn != null and mn.text == ("מדריכים" if he else "Manuals"), "%s: hangar: Manuals" % lang)
	fe.show_page("manuals")
	await frames(2)
	var pdfs: Array = fe.manuals()
	check(pdfs.size() == 4, "%s: manuals: four listed" % lang)
	for m in pdfs:
		var row: Button = fe.find_child("Manual_" + str(m[0]), true, false)
		check(FileAccess.file_exists(m[1]), "%s: manuals: %s is on the disk" % [lang, m[1].get_file()])
		check(row != null and not row.disabled, "%s: manuals: a row opens %s" % [lang, m[0]])
		if m[0] == "game":
			var pdf := "game-manual-he.pdf" if he else "game-manual.pdf"
			check(m[1].get_file() == pdf, "%s: manuals: the game manual in the game's language (%s)" % [lang, pdf])
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "hangar", "%s: Esc from the manuals: the Hangar" % lang)
	check(_labels_of(fe, "Stat").is_empty(), "%s: hangar: no flight counts" % lang)
	check(not _has(fe, "בחירה" if he else "Select"), "%s: hangar: no key hints" % lang)
	fe.show_page("pilot")
	await frames(2)
	(fe.find_child("pilot_log", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "log", "%s: the Pilot screen's Pilot log opens the Pilot log" % lang)
	check(_has(fe, "המראה" if he else "Take-off"), "%s: log: the take-off" % lang)
	check(_has(fe, "2 בנובמבר 2026 · 08:14" if he else "2 Nov 2026 · 08:14"), "%s: log: the date localised" % lang)
	check(fe.find_child("Back", true, false) != null, "%s: log: the footer's Back" % lang)
	var all_rows: int = fe.find_child("Log", true, false).find_children("Sortie_*", "Button", true, false).size()
	var by_mission: OptionButton = fe.find_child("FilterMission", true, false)
	var take_off := -1
	for i in by_mission.item_count:
		if by_mission.get_item_text(i) == ("המראה" if he else "Take-off"):
			take_off = i
	by_mission.select(take_off)
	by_mission.item_selected.emit(take_off)
	await frames(2)
	check(
		fe.get_viewport().gui_get_focus_owner().name == "FilterMission", "%s: log: the filter used keeps focus" % lang
	)
	var shown: Array = fe.find_child("Log", true, false).find_children("Sortie_*", "Button", true, false)
	check(
		take_off > 0 and shown.size() > 0 and shown.size() < all_rows and not _has(fe, "התנעה" if he else "Start-up"),
		"%s: log: the mission filter (%d of %d)" % [lang, shown.size(), all_rows]
	)
	var by_jet: OptionButton = fe.find_child("FilterJet", true, false)
	check(by_jet != null and by_jet.get_item_text(0) == ("כל המטוסים" if he else "All jets"), "%s: log: jets" % lang)
	# A filter this pilot's log never flew falls back to every flight (a filter kept from another pilot).
	fe.log_mission = 99999
	fe.show_page("log")
	await frames(2)
	check(
		fe.log_mission == -1 and fe.find_child("Sortie_*", true, false) != null,
		"%s: log: a stale filter falls back to All" % lang
	)
	var rows: Array = fe.find_child("Log", true, false).find_children("Sortie_*", "Button", true, false)
	rows[0].pressed.emit()
	await frames(2)
	check(
		fe.page == "debrief" and fe.record.get("mission") == "ramon_takeoff", "%s: a log row opens its debrief" % lang
	)
	fe.open_debrief(ids.fail)
	await frames(2)
	check(
		_has(fe, "נכשל" if he else "FAIL") and _has(fe, "כן הנסע לא נאסף." if he else "The gear was never raised."),
		"%s: a failed record shows FAIL and its reason" % lang
	)
	fe.show_page("credits")
	await frames(2)
	check(
		_has(fe, "Copernicus DEM GLO-30") and not _has_part(fe, "Major Ofer"),
		"%s: attributions: the wizard's list, no jet photos" % lang
	)
	var cs: ScrollContainer = fe.find_child("Credits", true, false)
	check(cs.has_focus() and fe.find_child("Back", true, false) != null, "%s: attributions: focused, a Back" % lang)
	var ring: StyleBox = cs.get_theme_stylebox("focus")
	check(
		cs.draw_focus_border and ring is StyleBoxFlat and ring.border_width_top > 0,
		"%s: attributions: the focus ring shows" % lang
	)
	cs.gui_input.emit(_key_event(KEY_PAGEDOWN))
	await frames(1)
	check(cs.scroll_vertical > 0, "%s: attributions: Page Down scrolls (%d)" % [lang, cs.scroll_vertical])


func prefs(fe: Control) -> void:
	var s := settings()
	var refused: int = s.rejected.size()
	fe.show_page("prefs")
	await frames(2)
	var sections := ["graphics", "language", "sound", "devices"]
	for g in sections:
		check(fe.find_child("Section_" + g, true, false) != null, "prefs: the %s section on the list" % g)
	check(fe.find_child("Section_physics", true, false) == null, "prefs: no Physics section (no aids)")
	# Each section opens beside the list on the same screen, its rows only, no line under an option.
	var rows := {}
	for g in sections:
		(fe.find_child("Section_" + g, true, false) as Button).pressed.emit()
		await frames(2)
		var tab: Button = fe.find_child("Section_" + g, true, false)
		check(
			fe.page == "prefs" and fe.pref_group == g and tab.button_pressed, "prefs: %s opens beside the sections" % g
		)
		var pane: ScrollContainer = fe.find_child("SectionPane", true, false)
		var after: bool = pane != null and pane.global_position.x > tab.global_position.x
		check(
			pane != null and pane.size.y > 700 and after == (not fe.is_layout_rtl()),
			"prefs: %s's pane beside the list, %d px high" % [g, pane.size.y if pane != null else 0]
		)
		for k in fe.find_children("Pref_*", "", true, false):
			var notes: Array = k.find_children("*", "Label", true, false).filter(
				func(l): return l.theme_type_variation == "Small"
			)
			check(notes.is_empty() or k.modulate.a < 1.0, "prefs: no line under %s but a greyed row's why" % k.name)
		for c in fe.find_children("Pref_*", "", true, false):
			rows[String(c.name).trim_prefix("Pref_")] = g
		if g == "graphics":
			var aa: Button = fe.find_child("Pref_antialiasing", true, false).find_child("Choice_msaa4", true, false)
			check(
				aa != null and aa.button_pressed and aa.text.begins_with("MSAA 4×"),
				"prefs: antialiasing as segmented buttons at MSAA 4×"
			)
			await settings_screen(fe)
			var sh: CheckButton = fe.find_child("Pref_shadows", true, false).find_child("Control", true, false)
			sh.button_pressed = false
			check(s.shadows == false, "prefs: the shadows switch sets the setting")
			sh.button_pressed = true
			var sc: Control = fe.find_child("Pref_scenery", true, false)
			var radios := sc.find_children("Choice_*", "Button", true, false)
			var have: bool = load("res://shared/terrain/scenery.gd").available()
			check(
				radios.size() == 3 and radios.all(func(r): return r.disabled != have),
				"prefs: Scenery Off / On / Detailed, greyed only without setup's scenery (%s)" % have
			)
			if not have:
				var left: Dictionary = s.load_json(s.converted("modern-iaf/setup.json"))
				var why: String = (
					fe.s("scenery_left_out") if "sim-scenery" in left.get("excluded", []) else fe.s("scenery_missing")
				)
				var shown := sc.find_children("*", "Label", true, false).map(func(l): return l.text)
				check(why in shown, "prefs: greyed Scenery says why: %s" % why)
	check(s.rejected.size() == refused, "prefs: the screens read none of the original's data (%s)" % [s.rejected])
	for k in ["antialiasing", "upscaling", "shadows", "terrain_detail", "clouds", "scenery", "fullscreen", "vsync"]:
		check(rows.get(k) == "graphics", "prefs: Graphics has %s" % k)
	check(not rows.has("town_labels"), "prefs: no Town labels row")
	for k in ["engine_volume", "sfx_volume", "speech_volume", "mute"]:
		check(rows.get(k) == "sound", "prefs: Sound has %s" % k)
	# The sim's clips are Ogg: each slider's sample plays (an AudioStreamWAV-typed slot raised a SCRIPT ERROR).
	for k in ["engine_volume", "sfx_volume", "speech_volume"]:
		fe.play_sample(k)
		check(fe._sample.stream is AudioStreamOggVorbis, "prefs: the %s sample plays its Ogg clip" % k)
	fe._sample.stop()
	for k in ["flight_controls", "rudder", "throttle", "stick_response"]:
		check(rows.get(k) == "devices", "prefs: Devices has %s" % k)
	await devices_no_joystick(fe)
	check(rows.get("language") == "language", "prefs: Language has the language")
	for k in [
		"flight_data", "unlimited_fuel", "invulnerable", "no_crashes", "no_blackouts", "rain", "water", "ground_roads"
	]:
		check(not rows.has(k), "prefs: no %s row (no realism switch, no aid, nothing the profile fixes)" % k)
	(fe.find_child("Section_language", true, false) as Button).pressed.emit()
	await frames(2)
	(fe.find_child("Pref_language", true, false).find_child("Choice_he", true, false) as Button).pressed.emit()
	await frames(2)
	check(s.language == "he" and fe.is_layout_rtl() and _has(fe, "שפה"), "prefs: Hebrew switches every string at once")
	(fe.find_child("Pref_language", true, false).find_child("Choice_en", true, false) as Button).pressed.emit()
	await frames(2)
	check(s.language == "en" and not fe.is_layout_rtl() and _has(fe, "Language"), "prefs: and back to English")
	# The settings file (FileExport): Export / Import in the footer; an import restores the file's values and keeps
	# the pilot flying.
	check(
		(
			fe.find_child("ExportSettings", true, false) is Button
			and fe.find_child("ImportSettings", true, false) is Button
		),
		"prefs: Export and Import settings file in the footer"
	)
	var cfg_path := OS.get_temp_dir().path_join("modern_iaf_settings_test_%d.cfg" % OS.get_process_id())
	var shadows0: bool = s.shadows
	var pilot0: int = s.pilot_id
	s.write_config().save(cfg_path)
	s.shadows = not shadows0
	s.pilot_id = pilot0 + 7
	fe.import_settings(cfg_path)
	await frames(2)
	check(s.shadows == shadows0 and s.pilot_id == pilot0 + 7, "prefs: a settings file imported, the pilot kept")
	s.pilot_id = pilot0
	DirAccess.remove_absolute(cfg_path)
	key(fe, KEY_ESCAPE)
	await frames(2)


## The debrief of the sample flight (the fixture's passed take-off): the sheet's fields, the goals with their target,
## flown figure and mark, Remarks with Next time, the whole flight on the map with its pins and legend, the graphs,
## The r3 Settings on Graphics (front-end.md §14): the Preset row (a preset sets its settings, a change lands on
## Custom), a cost chip per row, the pane on the hovered setting (its picture, text and the frame time), the sections'
## counts, the search across the sections in either language, Defaults, the footer.
func settings_screen(fe: Control) -> void:
	var s := settings()
	var pc = load("res://shared/util/pref_choices.gd")
	var counts := {"graphics": 9, "language": 1, "sound": 4, "devices": 7}
	for g in counts:
		var n: Label = fe.find_child("Section_" + g, true, false).find_child("Count", true, false)
		check(n.text == str(counts[g]), "settings: %s counts %d (%s)" % [g, counts[g], n.text])
	var preset: Control = fe.find_child("Pref_preset", true, false)
	check(preset != null and preset.get_index() == 0, "settings: Graphics opens with the Preset row")
	for name in ["laptop", "balanced", "high", "everything", "custom"]:
		check(preset.find_child("Choice_" + name, true, false) is Button, "settings: preset %s" % name)
	(preset.find_child("Choice_laptop", true, false) as Button).pressed.emit()
	await frames(2)
	var want: Dictionary = pc.preset("laptop")
	check(want.keys().all(func(k): return pc._same(s.get(k), want[k])), "settings: Laptop sets its settings")
	check(pc.preset_of(pc.preset_values()) == "laptop", "settings: the settings match Laptop")
	var laptop: Button = fe.find_child("Pref_preset", true, false).find_child("Choice_laptop", true, false)
	check(laptop.button_pressed, "settings: Laptop lit")
	var sh: CheckButton = fe.find_child("Pref_shadows", true, false).find_child("Control", true, false)
	sh.button_pressed = not sh.button_pressed
	var custom: Button = fe.find_child("Pref_preset", true, false).find_child("Choice_custom", true, false)
	check(custom.button_pressed and not laptop.button_pressed, "settings: a change by hand lands on Custom")
	for k in ["antialiasing", "upscaling", "shadows", "shadow_reach", "terrain_detail", "clouds", "scenery", "vsync"]:
		var chip: Label = fe.find_child("Pref_" + k, true, false).find_child("Cost", true, false)
		check(chip != null and chip.text != "", "settings: %s has a cost chip (%s)" % [k, chip.text if chip else ""])
	check(fe.cost_band(-1.0) == "saves" and fe.cost_band(5.0) == "high", "settings: the cost bands")
	check(fe.chip_cost("upscaling", "balanced") < -0.3, "settings: Upscaling Balanced saves frame time on the Iris Xe")
	check(fe.chip_cost("clouds", "volumetric") > 0.3, "settings: volumetric clouds cost frame time on the Iris Xe")
	check(
		fe.is_plain("clouds", "original") and not fe.is_plain("clouds", "volumetric") and fe.cost_under().contains("."),
		"settings: a cost inside the noise reads as under it (%s)" % fe.cost_under()
	)
	# The pane: the hovered row's name, text and its Off / On picture; the frame time for a graphics setting.
	fe.find_child("Pref_scenery", true, false).mouse_entered.emit()
	var about: Control = fe.find_child("About", true, false)
	var title: Label = about.find_child("AboutTitle", true, false)
	check(title != null and title.text == fe.s("scenery"), "settings: the pane tells about the hovered row")
	check(about.find_child("Preview", true, false) != null, "settings: the pane's Off / On picture")
	check(about.find_child("FrameHead", true, false) != null, "settings: the pane's frame time")
	s.frame_measured = {"ms": 24.0, "size": [2560, 1440], "settings": pc.preset_values()}
	fe._about_key = ""
	fe._about("scenery")
	var ms: Label = about.find_child("FrameMs", true, false)
	check(ms != null and ms.text.begins_with("24 ms"), "settings: the measured frame time shown")
	s.frame_measured = {}
	# The search: across the sections, in either language; the counts are the matches.
	var search: LineEdit = fe.find_child("Search", true, false)
	search.text = "joystick"
	search.text_changed.emit(search.text)
	await frames(2)
	check(fe.find_child("Pref_flight_controls", true, false) != null, "settings: a search finds Devices' rows")
	check(fe.find_child("Pref_shadows", true, false) == null, "settings: and only the matches")
	var dev: Label = fe.find_child("Section_devices", true, false).find_child("Count", true, false)
	check(int(dev.text) > 0 and int(dev.text) < 7, "settings: the count is the matches (%s)" % dev.text)
	search.text = "צללים"
	search.text_changed.emit(search.text)
	await frames(2)
	check(fe.find_child("Pref_shadows", true, false) != null, "settings: a Hebrew search in English")
	search.text = "ג'ויסטיק"
	search.text_changed.emit(search.text)
	await frames(2)
	check(fe.find_child("Pref_flight_controls", true, false) != null, "settings: a Hebrew search typed with '")
	search.text = "zzzz"
	search.text_changed.emit(search.text)
	await frames(2)
	check(fe.find_child("Pref_shadows", true, false) == null, "settings: no match, no row")
	search.text = ""
	search.text_changed.emit("")
	await frames(2)
	# Defaults: the section back to its defaults, the language kept.
	s.shadows = not s.default_value("shadows")
	fe.find_child("Defaults", true, false).pressed.emit()
	await frames(2)
	check(s.shadows == s.default_value("shadows") and s.language == "en", "settings: Defaults")
	var back: Button = fe.find_child("Back", true, false)
	check(back != null and back.text == fe.s("back_hangar"), "settings: the footer's Back to the hangar")


## Devices with no joystick connected: Keyboard picked on the joystick's rows (the device's choice greyed); the
## Joystick screen without its axis rows.
func devices_no_joystick(fe: Control) -> void:
	if root.get_node("Joystick").device() >= 0:
		return
	var was: int = settings().flight_controls
	settings().flight_controls = 1
	fe.pref_group = "devices"
	fe.show_page("prefs")
	await frames(2)
	var row: Control = fe.find_child("Pref_flight_controls", true, false)
	var kb: Button = row.find_child("Choice_0", true, false)
	var joy: Button = row.find_child("Choice_1", true, false)
	check(kb.button_pressed and joy.disabled, "devices: Keyboard with no joystick connected")
	settings().flight_controls = was
	fe.show_page("joystick")
	await frames(2)
	check(fe.find_child("Tab_joy_axes", true, false) == null, "devices: no axis rows with no joystick")
	fe.show_page("prefs")
	await frames(2)


## Export flight data offered; then the failed record from before the goals: its numbers and the empty right column.
func _debrief_checks(fe: Control, lang: String, ids: Dictionary) -> void:
	var he := lang == "he"
	var want := (
		["מטוס", "תוצאה", "יעדים", "הערות", "F-16I סופה", "רמון, מסלול 25R", "המראה ממסלול 25R", "160 קשר", "147 קשר"]
		if he
		else (
			["Plane flown", "Result", "GOALS", "REMARKS", "F-16I Sufa", "Ramon, runway 25R", "Take off from runway 25R"]
			+ ["160 kt", "147 kt", "PASS"]
		)
	)
	for t in want:
		check(_has(fe, t), "%s: debrief: %s" % [lang, t])
	check(_has_part(fe, "2 בנובמבר 2026" if he else "2 Nov 2026"), "%s: debrief: the date, the month named" % lang)
	check(_has_part(fe, "08:00–08:13"), "%s: debrief: the mission clock" % lang)
	var goals: Node = fe.find_child("Goals", true, false)
	var marks: Array = goals.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(marks.count("✓") == 5 and marks.count("!") == 1, "%s: debrief: five goals met, the lift-off marked" % lang)
	var next_time: RichTextLabel = fe.find_child("NextTime", true, false)
	check(
		(
			next_time != null
			and next_time.get_parsed_text().begins_with("בפעם הבאה:" if he else "Next time:")
			and next_time.get_parsed_text().contains("13 קשר מעל" if he else "13 kt above the reference speed")
		),
		"%s: debrief: Next time from the scorer" % lang
	)
	var map: Control = fe.find_child("DebriefMap", true, false)
	check(
		map != null and map.track.size() > 100 and map.track_pins.size() == 3, "%s: debrief: the track and pins" % lang
	)
	check(
		map != null and str(map.track_pins[1][1]) == ("ניתוק · 08:10:17" if he else "Lift-off · 08:10:17"),
		"%s: debrief: the lift-off pin's time" % lang
	)
	check(fe.find_child("Inset", true, false) != null, "%s: debrief: the base inset" % lang)
	var legend: Node = fe.find_child("Legend", true, false)
	check(
		(
			legend != null
			and _has(legend, "הסעה" if he else "Taxi")
			and _has(legend, "המסלול המתוכנן" if he else "Planned route")
		),
		"%s: debrief: the legend" % lang
	)
	var graphs: Control = fe.find_child("Graphs", true, false)
	check(graphs != null and graphs.size.y > 200 and graphs.flight.marks.size() == 4, "%s: debrief: the graphs" % lang)
	check(fe.find_child("NoRecording", true, false) == null, "%s: debrief: no empty state" % lang)
	var exp: Button = fe.find_child("ExportFlight", true, false)
	check(exp != null and not exp.disabled, "%s: debrief: Export flight data offers the recording" % lang)
	var order := ["PilotLog", "ExportFlight", "BackMissions", "FlyAgain"]
	var foot: Array = fe.find_child("Footer", true, false).get_children().filter(func(c): return c.name in order)
	check(foot.map(func(c): return str(c.name)) == order, "%s: debrief: the buttons' order" % lang)
	check(
		map.focus_next != NodePath() and exp.focus_neighbor_top == exp.get_path_to(map), "%s: debrief: the focus" % lang
	)
	# The failed record from before the goals and the recording.
	fe.open_debrief(ids.fail)
	await frames(2)
	check(
		_has(fe, "3.1 מ'" if he else "3.1 m") and _has(fe, "172 קשר" if he else "172 kt"),
		"%s: an old record's numbers" % lang
	)
	check(fe.find_children("NoRecording", "", true, false).size() == 2, "%s: an old record: the empty state" % lang)
	var gone: Button = fe.find_child("ExportFlight", true, false)
	check(
		gone.disabled and gone.focus_mode == Control.FOCUS_NONE,
		"%s: debrief: Export flight data greyed and unfocusable without the recording" % lang
	)
	fe.open_debrief(ids.pass)
	await frames(2)


## Writes the JSON records from before the database (storage.md §5): a pilot log with the start-up's pass, a failed
## take-off and a passed one, with their debrief records (the scorer's shape, training.md §4), in a new records
## folder; the store imports them on its first open. The take-off's sortie ids: {pass, fail}.
static func fixture(s: Node) -> Dictionary:
	var root: String = s.records_dir()
	var dir := root.path_join("debriefs")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(s.records_db())
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var items := [
		["taxi_time", 312, "s"],
		["lineup_heading_error", 1.2, "deg"],
		["roll_start_from_runway_start", 104, "m"],
		["roll_length", 1140, "m"],
		["runway_left", 1860, "m"],
		["rotation_speed", 160, "kt"],
		["liftoff_speed", 172, "kt"],
		["gross_weight", 13420, "kg"],
		["reference_speed", 159, "kt"],
		["gear_up_height", 15, "m"],
		["gear_up_time", 4.6, "s"],
		["roll_heading_deviation", 1.4, "deg"],
		["max_centreline_offset", 3.1, "m"],
		["tower_calls", 3, ""],
	]
	var names := {
		"en":
		{
			"pass": "Pass",
			"takeoff": "Take-off",
			"taxi_time": "Taxi time",
			"lineup_heading_error": "Lineup heading error",
			"roll_start_from_runway_start": "Roll start from the runway start",
			"roll_length": "Take-off roll",
			"runway_left": "Runway left at lift-off",
			"rotation_speed": "Rotation speed",
			"liftoff_speed": "Lift-off speed",
			"gross_weight": "Gross weight at lift-off",
			"reference_speed": "Reference take-off speed at this weight",
			"gear_up_height": "Gear-up height",
			"gear_up_time": "Gear-up time after lift-off",
			"roll_heading_deviation": "Heading deviation during the roll",
			"max_centreline_offset": "Max offset from the centreline",
			"tower_calls": "Tower calls",
			"runway": "Runway"
		},
		"he":
		{
			"pass": "עבר",
			"takeoff": "המראה",
			"taxi_time": "זמן הסעה",
			"lineup_heading_error": "סטיית כיוון בהתייצבות",
			"roll_start_from_runway_start": "תחילת ריצת ההמראה מתחילת המסלול",
			"roll_length": "אורך ריצת ההמראה",
			"runway_left": "מסלול שנותר בניתוק",
			"rotation_speed": "מהירות הרמת האף",
			"liftoff_speed": "מהירות ניתוק",
			"gross_weight": "משקל כולל בניתוק",
			"reference_speed": "מהירות המראה מומלצת במשקל זה",
			"gear_up_height": "גובה איסוף כן הנסע",
			"gear_up_time": "זמן איסוף כן הנסע מהניתוק",
			"roll_heading_deviation": "סטיית כיוון בזמן ריצת ההמראה",
			"max_centreline_offset": "סטייה מרבית מקו המרכז",
			"tower_calls": "קריאות למגדל",
			"runway": "מסלול"
		},
	}
	var rec := {
		"mission": "ramon_takeoff",
		"kind": "takeoff",
		"pass": true,
		"reasons": [],
		"items":
		(
			[{"id": "runway", "value": null, "text": "25R", "unit": ""}]
			+ items.map(func(i): return {"id": i[0], "value": i[1], "unit": i[2]})
		),
		"goals": ["runway", "liftoff_speed", "reference_speed", "max_centreline_offset", "tower_calls"],
		"strings": names,
		"date": "2026-11-02T08:11:00",
		"elapsed_s": 660.0,
	}
	var file := dir.path_join("debrief-%s-ramon_takeoff.json" % STAMP)
	var start := dir.path_join("debrief-20261102-075000-ramon_startup.json")
	# The passed take-off: the scorer's record of the sample flight (tests/data/sample_flight.py), with its recording.
	var flight := ProjectSettings.globalize_path(SAMPLE_FLIGHT)
	var scored = JSON.parse_string(
		IafTraining.new().score(
			flight,
			ProjectSettings.globalize_path("res://data/missions/ramon_takeoff.json"),
			ProjectSettings.globalize_path("res://data/airbases")
		)
	)
	scored.merge({"flight": flight, "date": "2026-11-02T08:14:00", "elapsed_s": 832.0}, true)
	FileAccess.open(file, FileAccess.WRITE).store_string(JSON.stringify(scored))
	# The failed one: a record from before the goals and the recording (its numbers, no flight).
	var fail := rec.duplicate(true)
	fail["pass"] = false
	fail["date"] = "2026-11-02T08:05:00"
	fail["reasons"] = ["gear_down"]
	fail["strings"]["en"]["gear_down"] = "The gear was never raised."
	fail["strings"]["he"]["gear_down"] = "כן הנסע לא נאסף."
	var failed := dir.path_join("debrief-20261102-075500-ramon_takeoff.json")
	FileAccess.open(failed, FileAccess.WRITE).store_string(JSON.stringify(fail))
	FileAccess.open(start, FileAccess.WRITE).store_string(
		JSON.stringify(
			{"mission": "ramon_startup", "pass": true, "items": [], "elapsed_s": 112.0, "date": "2026-11-02T07:52:00"}
		)
	)
	var log := {
		"missions":
		[
			{
				"id": 2012,
				"attempts":
				[
					{"result": 0, "debrief": failed, "date": "2026-11-02T08:05:00"},
					{"result": 1, "debrief": file, "date": "2026-11-02T08:14:00"},
				]
			},
			{"id": 2011, "attempts": [{"result": 1, "debrief": start, "date": "2026-11-02T07:52:00"}]},
		]
	}
	var path := root.path_join("pilots/14.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(log))
	var ids := {}
	for a in JSON.parse_string(IafPilotLog.sorties(s.records_db(), s.pilot())):
		if a.mission == "ramon_takeoff":
			ids["pass" if int(a.result) == 1 else "fail"] = int(a.id)
		elif a.mission == "ramon_startup":
			ids["startup"] = int(a.id)
	return ids


func _labels(root: Node) -> Array:
	return (
		root
		. find_children("*", "", true, false)
		. filter(func(n): return n is Label or n is Button)
		. map(func(n): return n.text)
	)


## The Loadout screen (front-end.md §10) of the Sufa's take-off: the crumb, the jet from beneath with a callout per
## station and its line, the take-off weight panel, the stores; the editor: a refused drop changes nothing, a drop
## changes that station only, with Mirror on its mirror station too, a store dragged back to the stores takes its pair
## off, the keyboard path (Enter on a callout, Enter on a store, Esc), racks, the balance, the loadout stored per pilot
## per jet and handed to the flight (fly.gd arm) and to the Hangar's jet, the maximum (a lowered one: the weight red,
## Fly off), saved loadouts (save, pick, delete), Reset.
func _loadout_checks(fe: Control, lang: String) -> void:
	var he := lang == "he"
	var s := settings()
	var db: String = s.records_db()
	var stored := func() -> String: return IafPilotLog.loadout(db, s.pilot(), "f16i")
	var scr := func() -> Control: return fe.find_child("Loadout", true, false)
	var slot := func(st: String) -> Control: return scr.call().callouts.get(st)
	var held := func(st: String) -> String:
		return str(slot.call(st).store[0]) if not slot.call(st).store.is_empty() else ""
	for e in JSON.parse_string(IafPilotLog.saved_loadouts(db, s.pilot(), "f16i")):
		IafPilotLog.delete_saved_loadout(db, s.pilot(), int(e.id))
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	load("res://menu/loadout_screen.gd").mirror = false  # the game's start: Mirror off
	fe.show_page("arming")
	await frames(3)
	check(fe.page == "arming" and scr.call() != null, "%s: loadout: the Arming tab opens the Loadout screen" % lang)
	check(
		_has(fe, "חימוש" if he else "Arming") and fe.find_child("Crumb_mission", true, false) != null,
		"%s: loadout: the crumb ends at the mission, then Arming" % lang
	)
	check(
		fe.find_child("ToBriefing", true, false).text == ("תדריך" if he else "Briefing"),
		"%s: loadout: the footer's Briefing named" % lang
	)
	var c: Dictionary = scr.call().callouts
	# Every station, 5 (5R) the chin's Litening (avionics slice 4), 10 (5L) the navigation pod's (pods part 1).
	check(
		c.size() == 10 and c.has("5") and c.has("10"),
		"%s: loadout: a callout per station that takes a store (%s)" % [lang, c.keys()]
	)
	check(
		c["4"].head == ("4 · פנימית" if he else "4 · INBOARD") and c["4"].sub == "1,321 " + ("ק\"ג" if he else "kg"),
		"%s: loadout: the callout's number, place and weight (%s, %s)" % [lang, c["4"].head, c["4"].sub]
	)
	check(c["1"].store[1] == "AIM-9M" and c["1"].tooltip_text == "AIM-9M", "%s: loadout: 1 an AIM-9M" % lang)
	var stage: Control = fe.find_child("Stage", true, false)
	check(stage.layout_direction == Control.LAYOUT_DIRECTION_LTR, "%s: loadout: the jet never mirrors" % lang)
	if scr.call().tt != null:
		var pts: Dictionary = scr.call().points()
		check(pts.size() == 10, "%s: loadout: each station's place on the model (%d)" % [lang, pts.size()])
		check(
			pts["1"].x > pts["9"].x and c["1"].position.x > c["9"].position.x,
			"%s: loadout: from beneath the left wing (1) on the right" % lang
		)
		check(
			scr.call().tt.below and scr.call().tt.focus_mode == Control.FOCUS_NONE,
			"%s: loadout: the jet from beneath, still" % lang
		)
	var mission_row: Button = fe.find_child("LoadoutMission", true, false)
	check(mission_row.button_pressed and _has_part(mission_row, "AIM-9M"), "%s: loadout: the mission's own, on" % lang)
	check(_has(mission_row, "המשימה" if he else "Mission"), "%s: loadout: the Mission badge" % lang)
	check(
		mission_row.get_theme_stylebox("pressed").border_width_left <= 1, "%s: loadout: no bold bar at the side" % lang
	)
	var weight: Control = fe.find_child("Weight", true, false)
	var rows: Control = fe.find_child("Loadouts", true, false)
	check((rows.global_position.x > weight.global_position.x) == he, "%s: loadout: the columns mirror" % lang)
	check(_has(weight, "16,471") and _has_part(weight, "23,582"), "%s: loadout: the take-off weight and maximum" % lang)
	check(_has_part(weight, "70 %") or _has_part(weight, "70%"), "%s: loadout: the share of the maximum" % lang)
	check(_has(weight, "הכנפיים מאוזנות" if he else "Wings balanced"), "%s: loadout: the wings balanced" % lang)
	check(
		_has_part(weight, "6,254") and _has(weight, "511") and _has(weight, "60 / 60"),
		"%s: loadout: fuel, rounds, chaff / flares" % lang
	)
	check(fe.find_child("Itemdelilah", true, false) == null, "%s: loadout: the Delilah is not offered" % lang)
	check(
		fe.find_child("Itemmk-84", true, false).find_child("Count", false, false) == null,
		"%s: loadout: no count without the record's" % lang
	)
	stage.dropped({"store": "tank-370", "from": ""}, "2")
	await frames(3)
	check(stored.call() == "", "%s: loadout: a tank on station 2 is refused" % lang)
	var fly_b: Control = fe.find_child("Fly", true, false)
	var brief_b: Control = fe.find_child("ToBriefing", true, false)
	check(
		fly_b.size.is_equal_approx(brief_b.size) and fly_b.theme_type_variation == "Primary",
		"%s: loadout: Fly the size of its neighbours (%s, %s)" % [lang, fly_b.size, brief_b.size]
	)
	var mir: CheckButton = fe.find_child("Mirror", true, false)
	check(
		(
			mir != null
			and not mir.button_pressed
			and mir.text == ("שיקוף לכנף הנגדית" if he else "Mirror to the other wing")
		),
		"%s: loadout: Mirror to the other wing, off" % lang
	)
	stage.dropped({"store": "mk-84", "from": ""}, "3")
	await frames(3)
	check(
		held.call("3") == "mk-84" and held.call("7") == "aim-9m" and stored.call().contains("aim-9m"),
		"%s: loadout: an MK-84 on 3 changes 3 only" % lang
	)
	check(
		(
			_has(fe.find_child("Weight", true, false), "17,310")
			and _has_part(fe.find_child("Weight", true, false), "כבדה" if he else "heavier")
		),
		"%s: loadout: one MK-84, the uneven wings shown" % lang
	)
	(fe.find_child("Mirror", true, false) as CheckButton).button_pressed = true
	fe.find_child("Stage", true, false).dropped({"store": "mk-84", "from": ""}, "3")
	await frames(3)
	stage = fe.find_child("Stage", true, false)
	check(
		held.call("3") == "mk-84" and held.call("7") == "mk-84" and held.call("2") == "aim-9m",
		"%s: loadout: with Mirror on, an MK-84 on 3 fills 7 too" % lang
	)
	check((fe.find_child("Mirror", true, false) as CheckButton).button_pressed, "%s: loadout: Mirror stays on" % lang)
	check(_has(fe.find_child("Weight", true, false), "18,149"), "%s: loadout: the weight with two MK-84s" % lang)
	check(not fe.find_child("LoadoutMission", true, false).button_pressed, "%s: loadout: edited, Mission off" % lang)
	check(fe.jet_stores(fe.jet()).get(2, {}).get("path", "") != "", "%s: loadout: the Hangar's jet carries it" % lang)
	# A callout's store dropped on a store in the grid goes back through the column.
	var on_item: Control = fe.find_child("Itemmk-84", true, false)
	check(
		on_item._can_drop_data(Vector2.ZERO, {"store": "tank-370", "from": "4"}), "%s: loadout: drop on a store" % lang
	)
	on_item._drop_data(Vector2.ZERO, {"store": "tank-370", "from": "4"})
	await frames(3)
	check(
		held.call("4") == "" and held.call("6") == "" and _has_part(fe.find_child("Weight", true, false), "4,014"),
		"%s: loadout: the tanks back, their fuel off" % lang
	)
	check(
		slot.call("4").store.is_empty() and slot.call("4").empty_text == ("ריק" if he else "Empty"),
		"%s: loadout: an empty station's callout" % lang
	)
	# The keyboard: Enter on 4 picks it, the focus on what it takes; Enter on the tank hangs both; Esc leaves a pick.
	scr.call().pick_station("4")
	await frames(2)
	var fo := fe.get_viewport().gui_get_focus_owner()
	check(
		fo != null and fo.name == "Itemmk-82", "%s: loadout: Enter on a callout, the focus on a store (%s)" % [lang, fo]
	)
	scr.call().choose_store("tank-370")
	await frames(4)
	fo = fe.get_viewport().gui_get_focus_owner()
	check(held.call("4") == "tank-370" and held.call("6") == "tank-370", "%s: loadout: Enter hangs both tanks" % lang)
	check(fo != null and fo.name == "Slot4", "%s: loadout: the focus back on the callout" % lang)
	scr.call().pick_station("2")
	await frames(1)
	fe._unhandled_input(_key_event(KEY_ESCAPE))
	await frames(1)
	check(fe.page == "arming" and scr.call().pick == "", "%s: loadout: Esc leaves the pick, the screen stays" % lang)
	var lo_keep: String = stored.call()
	# A TER: three Mk 82 on 4 and 6; the badge cycles the pair to two each.
	fe.find_child("Stage", true, false).dropped({"store": "mk-82", "from": ""}, "4")
	await frames(3)
	check(slot.call("4").store[2] == 3 and slot.call("6").store[2] == 3, "%s: loadout: three Mk 82 on 4 and 6" % lang)
	if scr.call().tt != null:
		# Every bomb drawn: three Mk 82 apart on each TER-9/A of 4 and 6 (the jet's model; Stores.place).
		var kids: Array = scr.call().tt._model.get_node("StoresMount").get_children()
		var bombs := kids.filter(func(k): return k.get_meta("store_of", -1) in [3, 5] and k.visible)
		var racks := kids.filter(func(k): return k.get_meta("station", -1) in [3, 5])
		var spots := {}
		for b in bombs:
			spots[(b.position * 100.0).round()] = true
		check(
			bombs.size() == 6 and spots.size() == 6 and racks.size() == 2,
			"%s: loadout: six Mk 82 drawn on two TERs (%d, %d, %d)" % [lang, bombs.size(), spots.size(), racks.size()]
		)
	scr.call().cycle("4")
	await frames(3)
	check(
		slot.call("4").store[2] == 2 and slot.call("6").store[2] == 2 and slot.call("4").badge_rect.has_area(),
		"%s: loadout: the badge cycles the rack, the pair along" % lang
	)
	# One-sided past the limit: the balance amber, Fly still on.
	IafPilotLog.set_loadout(
		db, s.pilot(), "f16i", JSON.stringify({"3": {"id": "mk-84", "count": 1}, "4": {"id": "tank-370", "count": 1}})
	)
	fe.show_page("arming")
	await frames(3)
	var bal: Label = fe.find_child("BalanceText", true, false)
	check(
		bal.get_theme_color("font_color") == Color("ffb547") and not fe.find_child("Fly", true, false).disabled,
		"%s: loadout: the wings out of balance, a warning, Fly on (%s)" % [lang, bal.text]
	)
	# A laser bomb with no targeting pod (modern-iaf/docs/weapons.md §7.1): the line saying what to add, Fly off; the
	# briefing's Arming summary the same line, its Fly off.
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", JSON.stringify({"3": "gbu-12", "7": "gbu-12"}))
	# The nodes of the page shown, not of one being freed.
	var live := func(n: String) -> Node:
		for x in fe.find_children(n, "", true, false):
			if not x.is_queued_for_deletion():
				return x
		return null
	fe.show_page("arming")
	await frames(3)
	var need: Label = live.call("NeedLine")
	var want := need.text if need != null else "-"
	check(
		(
			need != null
			and live.call("Fly").disabled
			and want.contains("לייטנינג" if he else "Litening")
			and want.contains("פוד" if he else "pod")
			and want.length() < 40
		),  # one short line (the user, 17 Nov: "too long and big")
		"%s: loadout: a GBU-12 without the pod: the line, Fly off (%s)" % [lang, want]
	)
	fe.show_page("mission")
	await frames(5)
	var need2: Label = live.call("ArmingNeed")
	check(
		need2 != null and need2.text == want and live.call("Fly").disabled,
		"%s: briefing: the Arming summary's line, Fly off (%s)" % [lang, need2.text if need2 != null else "none"]
	)
	# Such a load is not saved as a preset (the user, 17 Nov): Save off, and save_named stores nothing.
	fe.show_page("arming")
	await frames(3)
	var saves := func() -> int:
		var v = JSON.parse_string(IafPilotLog.saved_loadouts(db, s.pilot(), "f16i"))
		return v.size() if v is Array else -1
	var n_saved: int = saves.call()
	scr.call().find_child("LoadoutName", true, false).text = "no pod"
	scr.call().save_named()
	await frames(3)
	check(
		live.call("SaveLoadout").disabled and saves.call() == n_saved,
		"%s: loadout: a laser bomb with no pod is not saved as a preset" % lang
	)
	# A preset stored before the rule: picked, its stores kept, the line shown, Fly and Save off.
	var old: int = IafPilotLog.save_loadout(
		db,
		s.pilot(),
		"f16i",
		"old",
		JSON.stringify({"3": {"id": "gbu-12", "count": 1}, "7": {"id": "gbu-12", "count": 1}})
	)
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	fe.show_page("arming")
	await frames(3)
	live.call("LoadoutSaved%d" % old).emit_signal("pressed")
	await frames(3)
	check(
		(
			stored.call().contains("gbu-12")
			and live.call("NeedLine") != null
			and live.call("Fly").disabled
			and live.call("SaveLoadout").disabled
		),
		"%s: loadout: an old preset without the pod: kept, the line, Fly and Save off (%s)" % [lang, stored.call()]
	)
	IafPilotLog.delete_saved_loadout(db, s.pilot(), old)
	IafPilotLog.set_loadout(
		db, s.pilot(), "f16i", JSON.stringify({"3": "gbu-12", "7": "gbu-12", "5": "litening", "10": "lantirn-nav"})
	)
	fe.show_page("arming")
	await frames(3)
	check(
		live.call("NeedLine") == null and not live.call("Fly").disabled and not live.call("SaveLoadout").disabled,
		"%s: loadout: the pod loaded: no line, Fly and Save on" % lang
	)
	# The two chin stations by their real names, the navigation pod on 5L drawn on its own pylon.
	var head5: String = live.call("Slot5").head
	var head10: String = live.call("Slot10").head
	check(
		head5.begins_with("5R") and head10.begins_with("5L"), "%s: loadout: 5R and 5L (%s, %s)" % [lang, head5, head10]
	)
	if scr.call().tt != null:
		var jet: Node3D = scr.call().tt._model
		var pods: Array = jet.get_node("StoresMount").get_children().filter(
			func(k): return k.get_meta("store_of", -1) == 12 and k.visible
		)
		var pl: Node3D = jet.find_child("PylonChinL", true, false)
		check(
			pods.size() == 1 and pods[0].position.x < -0.5 and pl != null and pl.visible,
			(
				"%s: loadout: the navigation pod under the left chin pylon (%s)"
				% [lang, pods.map(func(p): return p.position)]
			)
		)
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", lo_keep)
	fe.show_page("arming")
	await frames(3)
	fe.find_child("Stage", true, false).dropped({"store": "tank-370", "from": ""}, "4")
	await frames(3)
	# Handed to the flight: the MK-84 (record number 2) on pylons C and G, the AIM-9M (1) on A.
	var mission := "ramon_takeoff"
	var m: Dictionary = s.load_json(s.converted(s.missions_folder()).path_join(mission + ".json"))
	if not m.is_empty():
		fly_gd.arm(m, s.load_json("res://data/missions/%s.json" % mission))
		var pylons: Array = s.arm_loadouts.values()[0] if s.arm_loadouts.size() == 1 else []
		check(
			(
				pylons.size() == 13
				and pylons[2] == [2.0, 1.0, 0.0, 0.0, 0.0]
				and pylons[6] == [2.0, 1.0, 0.0, 0.0, 0.0]
				and pylons[0] == [1.0, 1.0, 0.0, 0.0, 0.0]
			),
			"%s: loadout: the flight's pylons (%s)" % [lang, pylons]
		)
		s.arm_loadouts = {}
	# Saved loadouts: named, on the list with its badge and on; the mission's picked back; the saved one again; delete.
	scr.call().open_name()
	await frames(1)
	var field: LineEdit = fe.find_child("LoadoutName", true, false)
	check(
		field.visible and field.text != "" and field.has_focus(),
		"%s: loadout: Save offers a name (%s)" % [lang, field.text]
	)
	field.text = "Strike"
	scr.call().save_named()
	await frames(3)
	var saved: Array = JSON.parse_string(IafPilotLog.saved_loadouts(db, s.pilot(), "f16i"))
	var row: Button = fe.find_child("LoadoutSaved%d" % int(saved[0].id), true, false) if saved.size() == 1 else null
	check(
		row != null and row.button_pressed and _has(row, "Strike") and _has(row, "שמורה" if he else "Saved"),
		"%s: loadout: saved, listed, on" % lang
	)
	fe.find_child("LoadoutMission", true, false).pressed.emit()
	await frames(3)
	check(stored.call() == "" and held.call("3") == "aim-9m", "%s: loadout: the mission's own picked back" % lang)
	fe.find_child("LoadoutSaved%d" % int(saved[0].id), true, false).pressed.emit()
	await frames(3)
	check(
		held.call("3") == "mk-84" and fe.find_child("LoadoutSaved%d" % int(saved[0].id), true, false).button_pressed,
		"%s: loadout: the saved one picked" % lang
	)
	scr.call().ask_delete(int(saved[0].id), "Strike")
	await frames(1)
	fe.find_child("ModalOk", true, false).pressed.emit()
	await frames(3)
	check(
		(JSON.parse_string(IafPilotLog.saved_loadouts(db, s.pilot(), "f16i")).is_empty()) and held.call("3") == "mk-84",
		"%s: loadout: deleted; the jet keeps its stores" % lang
	)
	# Over a (lowered) maximum: the take-off weight red, Fly off.
	var dir := OS.get_temp_dir().path_join("modern-iaf-units-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var u: Dictionary = s.load_json("res://data/db/units/f16i.json")
	u["max_takeoff_kg"] = 17000
	FileAccess.open(dir.path_join("f16i.json"), FileAccess.WRITE).store_string(JSON.stringify(u))
	fe.units_dir = dir
	fe.show_page("arming")
	await frames(3)
	var fly: Button = fe.find_child("Fly", true, false)
	var tw: Control = fe.find_child("TakeoffWeight", true, false)
	check(
		fly.disabled and tw.get_child(0).get_theme_color("font_color") == Color("ff6b6b"),
		"%s: loadout: over the maximum, the weight red and Fly off" % lang
	)
	fe.units_dir = "res://data/db/units"
	DirAccess.remove_absolute(dir.path_join("f16i.json"))
	DirAccess.remove_absolute(dir)
	fe.find_child("ArmReset", true, false).pressed.emit()
	await frames(3)
	check(
		stored.call() == "" and held.call("3") == "aim-9m" and not fe.find_child("Fly", true, false).disabled,
		"%s: loadout: Reset, the mission's again" % lang
	)
	check(fe.find_child("ArmReset", true, false).disabled, "%s: loadout: Reset off on the mission's own" % lang)
	# A mission with its own load (the range lessons'): the mission's is that load, on the screen's jet too.
	var own := {"start": {"unit": "f16i"}, "loadout": {"3": {"id": "mk-82", "count": 3}}}
	var own_lo: String = fly_gd.own_loadout(own)
	check(
		(
			fe.arming(own).slots["3"].id == "mk-82"
			and fe.jet_stores({"unit": "f16i"}, own_lo).get(2, {}).get("count") == 3
		),
		"%s: loadout: a mission's own load is the mission's" % lang
	)
	# The Adir: its bays' callouts, two AIM-120 inside.
	var adir: Dictionary = fe.arming({"start": {"unit": "f35i"}})
	check(
		(
			float(adir.stores_kg) == 2.0 * 161.5
			and adir.internal == [4.0, 5.0, 7.0, 8.0]
			and adir.positions["5"] == "bay_inboard"
		),
		"%s: loadout: the Adir's bays, two AIM-120 inside" % lang
	)


## True when the briefing map's mission area lies in the room between the panels (its centre there, its box filling
## the room along one side).
func _area_in_room(map: Control) -> bool:
	var a: Rect2 = map._xf() * Rect2(Vector2.ZERO, map._size_m())
	return map.view.grow(2).encloses(a) and (a.size.x >= map.view.size.x * 0.3 or a.size.y >= map.view.size.y * 0.3)


## Every pin and its name's plate (drawn, toward the map's right) in the room between the cards, so no panel covers
## what the briefing points at.
func _pins_in_room(map: Control, what: String) -> void:
	var pins: Array = map.data.pins
	check(map.plates.size() == pins.size(), "%s: every pin's name shown (%d)" % [what, map.plates.size()])
	for p in pins:
		var at: Vector2 = map._xf() * Vector2(float(p.at[0]), float(p.at[1]))
		check(map.view.grow(2).has_point(at), "%s: pin %d in the room between the cards" % [what, p.first + 1])
	for r in map.plates:
		check(map.view.grow(2).encloses(r), "%s: a name's plate in the room (%s)" % [what, r])


## Waits (at most 10 s) until the briefing map's view settled: its tiles decoded.
func _map_settled(map: Control) -> void:
	for i in 600:
		await frames(1)
		if not map._view_dirty and map._want.is_empty() and map._jobs.is_empty():
			return


## A press of `button` at `at`, a move by `by` with the button held, the release, through the viewport `vp`.
func _push_drag(vp: Viewport, at: Vector2, button: MouseButton, by: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = at
	press.global_position = at
	vp.push_input(press)
	await frames(1)
	var move := InputEventMouseMotion.new()
	move.position = at + by
	move.global_position = at + by
	move.relative = by
	move.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	vp.push_input(move)
	await frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.position = at + by
	up.global_position = at + by
	vp.push_input(up)
	await frames(1)


func _labels_of(root: Node, kind: String) -> Array:
	var labels := root.find_children("*", "Label", true, false)
	return labels.filter(func(n): return n.theme_type_variation == kind).map(func(n): return n.text)


## The Missions screen and the Training list (front-end.md §2): the four sections, Training open and focused, the
## others greyed without focus or click; the list's six missions with their statuses, the next one to fly marked and
## focused; Esc back up.
func _missions_checks(fe: Control, lang: String) -> void:
	var he := lang == "he"
	check(fe.page == "missions", "%s: Fly opens the Missions screen" % lang)
	var names := (
		["אימונים", "מערכה", "משימות בודדות", "טיסה מיידית"]
		if he
		else ["Training", "Campaign", "Single missions", "Fly now"]
	)
	var ids := ["training", "campaign", "single", "fly_now"]
	for i in 4:
		var b: Button = fe.find_child("Section_" + ids[i], true, false)
		check(b != null and _has(b, names[i]), "%s: missions: the section %s" % [lang, names[i]])
		if i == 0:
			check(not b.disabled and b.has_focus(), "%s: missions: Training open and focused" % lang)
		else:
			check(
				(
					b.disabled
					and b.focus_mode == Control.FOCUS_NONE
					and b.modulate.a < 1.0
					and b.pressed.get_connections().is_empty()
				),
				"%s: missions: %s greyed, no focus, no click" % [lang, ids[i]]
			)
	var row_x := func(n: String) -> float:
		return fe.find_child("Section_" + n, true, false).get_global_rect().position.x
	check(
		(row_x.call("training") > row_x.call("fly_now")) == he,
		"%s: missions: the sections from the inline start" % lang
	)
	check(_has(fe, "2 מתוך 3 עברו" if he else "2 of 3 passed"), "%s: missions: Training's progress" % lang)
	# A card: its number, title and progress (or Coming later); no subtitle, no list of what it holds (2026-11-16).
	var tr: Control = fe.find_child("Section_training", true, false)
	var texts := func(c: Control) -> Array: return _labels(c).filter(func(x): return x != "")
	check(texts.call(tr).size() == 3, "%s: missions: Training: number, title, progress (%s)" % [lang, texts.call(tr)])
	var camp: Control = fe.find_child("Section_campaign", true, false)
	check(
		_has(camp, "יגיע בהמשך" if he else "Coming later") and texts.call(camp).size() == 3,
		"%s: missions: Campaign: number, title, Coming later (%s)" % [lang, texts.call(camp)]
	)
	var back: Button = fe.find_child("Back", true, false)
	check(
		back != null and back.focus_mode != Control.FOCUS_NONE and back.text == ("חזרה" if he else "Back"),
		"%s: missions: the footer's Back" % lang
	)
	check(
		tr.get_node(tr.focus_next) == back and back.get_node(back.focus_next) == tr, "%s: missions: Tab to Back" % lang
	)
	back.pressed.emit()
	await frames(2)
	check(fe.page == "hangar", "%s: missions: Back opens the Hangar" % lang)
	fe.show_page("missions")
	await frames(2)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "hangar", "%s: Esc on the Missions screen: the Hangar" % lang)
	fe.show_page("missions")
	await frames(2)
	(fe.find_child("Section_training", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "section" and fe.missions.size() == 3, "%s: Training lists the Sufa's three missions" % lang)
	var rows: Array = fe.find_child("List", true, false).get_children()
	var status := func(i: int) -> String: return str(rows[i].find_child("Status", true, false).text)
	check(status.call(0).begins_with("עבר" if he else "Pass"), "%s: list: the start-up passed" % lang)
	check(status.call(1).begins_with("עבר" if he else "Pass"), "%s: list: the take-off passed (its last flight)" % lang)
	# The two passed; the range not flown: it is Next, and focused.
	check(
		rows.slice(0, 2).all(func(r): return r.find_child("NextUp", true, false) == null),
		"%s: list: no Next on the passed ones" % lang
	)
	check(
		rows[2].find_child("NextUp", true, false) != null and rows[2].has_focus(),
		"%s: list: the range Next, focused" % lang
	)
	check(
		_has(
			rows[0],
			(
				"רמון · להתניע את המנוע ולהפעיל את האוויוניקה."
				if he
				else "Ramon · Start the engine and bring the avionics up."
			)
		),
		"%s: list: the base and what it trains" % lang
	)
	check(_has_button(fe, fe.full_name(fe.jet())), "%s: list: the jet's crumb" % lang)
	# The side panel follows the focus: the take-off's purpose, base, time allowed, last result and best time.
	rows[1].grab_focus()
	await frames(2)
	var side: Control = fe.find_child("Side", true, false)
	for t in (
		["משימה 2", "המראה", "רמון", "15 דקות", "עבר · 2 בנובמבר 2026", "13:52", "זמן מוקצב", "תוצאה אחרונה"]
		if he
		else ["Mission 2", "Take-off", "Ramon", "15 min", "Pass · 2 Nov 2026", "13:52", "Time allowed", "Last result"]
	):
		check(_has(side, t), "%s: list: the side panel: %s" % [lang, t])
	var purpose: RichTextLabel = side.find_child("SidePurpose", true, false)
	check(purpose != null and purpose.get_parsed_text().contains("25R"), "%s: list: the side panel's purpose" % lang)
	back = fe.find_child("Back", true, false)
	check(rows[2].get_node(rows[2].focus_next) == back, "%s: list: Tab to Back" % lang)
	back.pressed.emit()
	await frames(2)
	check(fe.page == "missions", "%s: list: Back opens the Missions screen" % lang)
	(fe.find_child("Section_training", true, false) as Button).pressed.emit()
	await frames(2)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "missions", "%s: Esc on the list: the Missions screen" % lang)
	(fe.find_child("Section_training", true, false) as Button).pressed.emit()
	await frames(2)


## The briefing, map first (front-end.md §10) of the take-off picked, then of the start-up: the mission card (the title
## as the kind, the time as military time, the wind as pilots read it, the objectives, the runway's heading, the Arming
## summary and its Edit, Arming beside Fly), the text card (what you will learn, the explanation's paragraphs with
## their keys as bound, scrolled by the keys), the map under them (it opens on the base and the route with the pins; the
## chips; it zooms around the pointer, scrolls, resets, follows the keys, its scale bar with the zoom), the focus order,
## the loadout screen Edit opens (the front view with a slot per station, the weights, the loadout editor).
func _briefing_checks(fe: Control, lang: String) -> void:
	var he := lang == "he"
	var pane: Control = fe.find_child("Briefing", true, false)
	var text: Control = fe.find_child("Text", true, false)
	check(
		(pane.get_global_rect().get_center().x > 960) == he and (text.get_global_rect().get_center().x < 960) == he,
		"%s: briefing: the card at the inline start, the text at the end" % lang
	)
	check(_has(pane, "המראה" if he else "Take-off"), "%s: briefing: the title is the kind" % lang)
	check(not _has_part(pane, "מרמון" if he else "from Ramon"), "%s: briefing: no base in the title" % lang)
	check(_has(pane, "0800"), "%s: briefing: the time as military time" % lang)
	check(
		_has(pane, "000° / 0") and _has(pane, "קשר" if he else "kt"), "%s: briefing: the wind as pilots read it" % lang
	)
	var fact_labels: Array = pane.find_child("Facts", true, false).find_children("*", "Label", true, false)
	var wind: Label = fact_labels.filter(func(l): return l.text == "000° / 0")[0]
	check(wind.text_direction == Control.TEXT_DIRECTION_LTR, "%s: wind: the figures left to right" % lang)
	check(fe.wind_text({"wind_from": 250, "wind_kt": 8}) == "250° / 8", "%s: wind" % lang)
	var objs: Control = pane.find_child("Objectives", true, false)
	check(objs.get_child_count() == 4 and _has_part(objs, "25R"), "%s: briefing: the take-off's objectives" % lang)
	check(_has_part(pane, "25R · 246°"), "%s: briefing: the runway with its heading" % lang)
	var sub: Label = pane.find_child("Subtitle", true, false)
	check(
		sub.text.contains("טייסת 201 האחת · רמון" if he else "201 Squadron The One · Ramon"),
		"%s: briefing: the subtitle once, under the title (%s)" % [lang, sub.text]
	)
	check(not sub.text.contains("846"), "%s: briefing: no tail in the card (the header has it)" % lang)
	# The text: what you will learn, then the explanation in paragraphs, the keys as bound in it; nothing clipped.
	var purpose: RichTextLabel = text.find_child("Purpose", true, false)
	check(_has(text, "מה לומדים" if he else "WHAT YOU WILL LEARN"), "%s: briefing: what you will learn" % lang)
	check(purpose.get_parsed_text().contains("\u206625R\u2069"), "%s: briefing: the purpose, its runway" % lang)
	var how: ScrollContainer = text.find_child("HowScroll", true, false)
	var paras: Array = how.get_child(0).get_children()
	check(paras.size() == 6, "%s: briefing: the take-off's six paragraphs (%d)" % [lang, paras.size()])
	var words := (
		"\n"
		. join(paras.map(func(r): return r.find_children("*", "RichTextLabel", true, false)[0].get_parsed_text()))
		. replace("\u00a0", " ")
	)
	check(not words.contains("{"), "%s: briefing: every placeholder filled" % lang)
	# The keys by the table, as the player's platform names them: Ctrl + T, "⌘ + T" on a Mac (key_table.gd cmd_is_ctrl);
	# each call to the tower with the menu's pick 1-4.
	var tower: String = fe.key_name(47)
	check(tower != "", "%s: briefing: the tower key named" % lang)
	var calls := 0
	for k in 4:
		calls += words.count("%s, %d" % [tower, k + 1])
	check(calls == 4, "%s: briefing: four tower calls, Ctrl + T, 1-4 (%d)" % [lang, calls])
	check(words.contains("אישור המראה" if he else "cleared for take-off"), "%s: briefing: the wait" % lang)
	check(
		text.get_global_rect().end.y <= text.get_viewport_rect().end.y - 39,
		(
			"%s: briefing: the text card on the screen (%s in %s)"
			% [lang, text.get_global_rect(), text.get_viewport_rect()]
		)
	)
	# The keys scroll the explanation with the focus; at its end the arrow is left to move the focus.
	how.grab_focus()
	await frames(2)
	var bar := how.get_v_scroll_bar()
	check(bar.max_value > bar.page, "%s: briefing: the explanation longer than its card scrolls" % lang)
	for n in 40:
		how.gui_input.emit(_key_event(KEY_DOWN))
	await frames(1)
	check(how.scroll_vertical > 0 and bar.value >= bar.max_value - bar.page - 1.0, "%s: text: Down scrolls" % lang)
	how.gui_input.emit(_key_event(KEY_PAGEUP))
	check(how.scroll_vertical < bar.max_value - bar.page - 1.0, "%s: text: Page Up scrolls" % lang)
	how.scroll_vertical = 0
	how.release_focus()
	var credit: Label = fe.find_child("Credit", true, false)
	check(credit != null and "OpenStreetMap" in credit.text, "%s: briefing: the map's credit" % lang)
	check(credit.is_layout_rtl() == he, "%s: map: the credit right to left" % lang)
	# The Arming summary: the stores on the jet, the take-off weight, Edit.
	var summ: Control = pane.find_child("ArmingSummary", true, false)
	check(
		_has_part(summ, "6 × AIM-9M") and _has_part(summ, "16,471") and _has(summ, "חימוש" if he else "ARMING"),
		"%s: briefing: the Arming summary" % lang
	)
	# The focus: on Fly; up to Edit, down from Edit to Fly. No mission tabs (the section's list has them).
	var edit: Button = fe.find_child("ArmEdit", true, false)
	var fly: Button = fe.find_child("Fly", true, false)
	check(
		(
			fe._focus == fly
			and fly.get_node(fly.focus_neighbor_top) == edit
			and edit.get_node(edit.focus_neighbor_bottom) == fly
		),
		"%s: focus: on Fly, up to Edit and back down" % lang
	)
	check(pane.find_child("Missions", true, false) == null, "%s: briefing: no mission tabs" % lang)
	check(pane.find_child("Flights", true, false) == null, "%s: briefing: one flight, no flight tabs" % lang)
	check(fe.find_child("PageMap", true, false).data.get("flights") == [], "%s: map: no other flight" % lang)
	var back: Button = pane.find_child("Back", true, false)
	back.pressed.emit()
	await frames(2)
	check(fe.page == "section", "%s: briefing: Back to the section's list" % lang)
	fe.open_mission(1)
	await frames(2)
	pane = fe.find_child("Briefing", true, false)
	how = fe.find_child("Text", true, false).find_child("HowScroll", true, false)
	edit = fe.find_child("ArmEdit", true, false)
	fly = fe.find_child("Fly", true, false)
	var arm: Button = fe.find_child("Arming", true, false)
	check(fly.get_node(fly.focus_next) is Button and not fly.disabled, "%s: focus: on from Fly to the chips" % lang)
	var back_b: Button = fe.find_child("Back", true, false)
	check(
		back_b.get_node(back_b.focus_next) == arm and arm.get_node(arm.focus_next) == fly,
		"%s: focus: Back, Arming, Fly" % lang
	)
	var end_side := "focus_neighbor_left" if he else "focus_neighbor_right"
	check(fly.get_node(fly.get(end_side)) == how, "%s: focus: across from Fly the text" % lang)
	check(
		(arm.get_global_rect().get_center().x < fly.get_global_rect().get_center().x) != he,
		"%s: Arming beside Fly, before it" % lang
	)
	check(arm.text == ("חימוש" if he else "Arming") and arm.shortcut == null, "%s: Arming: its word, no key" % lang)
	# The map: the whole screen under the cards, opened on the base and the route with the steps' pins.
	var map: Control = fe.find_child("PageMap", true, false)
	await frames(2)
	check(map.size.x >= 1900 and map.size.y >= 1000, "%s: map: the whole screen (%s)" % [lang, map.size])
	var d: Dictionary = map.data
	check(absf(float(d.size[0]) / float(d.size[1]) - map.size.x / map.size.y) < 0.02, "%s: map: the aspect" % lang)
	check(d.runways.size() >= 2 and d.route.size() == 4 and d.taxi.size() >= 4, "%s: map: runways, taxi, route" % lang)
	check(d.aprons.size() > 0 and d.taxiways.size() > 0 and d.parking.size() > 0, "%s: map: the airbase" % lang)
	check(map.base_label == ("רמון" if he else "Ramon"), "%s: map: the base" % lang)
	check(d.pins.map(func(p): return int(p.first)) == [0, 3, 4], "%s: map: pins 1, 4 and 5 (%s)" % [lang, d.pins])
	check(map.zoom > 2.0 and map.view.has_area(), "%s: map: opened on the base (%.1f)" % [lang, map.zoom])
	await frames(1)
	_pins_in_room(map, "%s: map" % lang)
	var hold_name := "עצירה לפני \u206625R\u2069" if he else "Stop short of \u206625R\u2069"
	check(map.pin_names.hold == hold_name, "%s: map: the holding point's pin named (%s)" % [lang, map.pin_names.hold])
	# The roads with setup's road layer (the optional scenery step); without it the map draws the ground alone.
	var roads: bool = load("res://shared/terrain/ground_roads.gd").available()
	check((d.roads.size() > 0) == roads, "%s: map: roads %s" % [lang, roads])
	# The ground: the view's tiles (IafBriefing.tiles) decoded on worker threads.
	await _map_settled(map)
	check(map._tiles.size() > 0 and map._tex.size() > 0, "%s: map: the ground's tiles (%d)" % [lang, map._tex.size()])
	var towns: Array = d.places.map(func(p): return p.he if he else p.en)
	check(("מצפה רמון" if he else "Mitspe Ramon") in towns, "%s: map: Mitzpe Ramon (%s)" % [lang, towns])
	# The text card wider: the map frames again in the narrower room between the cards.
	var text_card: Control = fe.find_child("Text", true, false)
	var room0: Rect2 = map.view
	text_card.offset_left -= 200  # toward the map in either layout (the anchors mirror in Hebrew)
	await frames(3)
	check(
		absf(map.view.size.x - (room0.size.x - 200.0)) < 1.0,
		"%s: map: the room follows the text card (%s)" % [lang, map.view]
	)
	_pins_in_room(map, "%s: map, the text card wider" % lang)
	text_card.offset_left += 200
	await frames(3)
	check(map.view == room0, "%s: map: the room back (%s)" % [lang, map.view])
	# The chips: the layers off and on, the zoom.
	check(fe.find_child("MapTaxi", true, false) == null, "%s: no Taxi route chip (the route always drawn)" % lang)
	for c in [["MapLabels", "show_labels"], ["MapPhoto", "show_photo"]]:
		var b: Button = fe.find_child(c[0], true, false)
		b.button_pressed = false
		check(not map.get(c[1]), "%s: chip %s off" % [lang, c[0]])
		b.button_pressed = true
	var z0: float = map.zoom
	fe.find_child("ZoomIn", true, false).pressed.emit()
	check(map.zoom > z0, "%s: chip: zoom in" % lang)
	fe.find_child("ZoomOut", true, false).pressed.emit()
	fe.find_child("ZoomOut", true, false).pressed.emit()
	check(map.zoom < z0, "%s: chip: zoom out" % lang)
	map.reset_view()
	check(_area_in_room(map), "%s: map: reset fits the mission's area into the room" % lang)
	await frames(1)
	_pins_in_room(map, "%s: map at the reset" % lang)
	check(map._area_shown(), "%s: map: the runway label at the reset" % lang)
	var zr: float = map.zoom
	# The wheel zooms around the pointer: the map point under it stays; the scale bar follows.
	var at: Vector2 = map.view.get_center()
	var under: Vector2 = map._xf().affine_inverse() * at
	var scale0: int = map.scale_metres()
	for n in 8:
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP
		w.pressed = true
		w.position = at
		map._gui_input(w)
	check(map.zoom > zr * 5.0, "%s: map: the wheel zooms in (%.2f)" % [lang, map.zoom])
	var still: Vector2 = map._xf() * under
	check(still.distance_to(at) < 1.0, "%s: map: zoomed around the pointer (%s)" % [lang, still - at])
	check(map.scale_metres() < scale0, "%s: map: the scale bar follows (%d m)" % [lang, map.scale_metres()])
	# A drag scrolls; a double click shows the whole map.
	var c0: Vector2 = map.center
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	map._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(60, -40)
	map._gui_input(drag)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	map._gui_input(up)
	check(map.center.x < c0.x and map.center.y > c0.y, "%s: map: a drag scrolls" % lang)
	press.double_click = true
	map._gui_input(press)
	check(is_equal_approx(map.zoom, zr) and _area_in_room(map), "%s: map: a double click shows the whole map" % lang)
	# Through the window, in the room between the cards (nothing over the map there takes the events): a left drag
	# and a middle drag move it, a trackpad's two-finger scroll (a pan gesture) moves it, a pinch zooms.
	var vp := map.get_viewport()
	var mid: Vector2 = vp.get_final_transform() * (map.get_global_transform() * map.view.get_center())
	vp.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)  # headless: the pointer never entered the window
	var probe := InputEventMouseMotion.new()
	probe.position = mid
	probe.global_position = mid
	vp.push_input(probe)
	await frames(1)
	check(vp.gui_get_hovered_control() == map, "%s: map: nothing over the map takes the pointer" % lang)
	for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		var c2: Vector2 = map.center
		var by := Vector2(80, 50) * (1.0 if b == MOUSE_BUTTON_LEFT else -1.0)
		await _push_drag(vp, mid, b, vp.get_final_transform().basis_xform(by))
		check(map.center.distance_to(c2) > 1.0, "%s: map: a %s drag moves the whole map" % [lang, b])
	var c3: Vector2 = map.center
	var pg := InputEventPanGesture.new()
	pg.position = mid
	pg.delta = Vector2(3, 2)
	vp.push_input(pg)
	await frames(1)
	check(map.center.distance_to(c3) > 1.0, "%s: map: a two-finger scroll moves it" % lang)
	var mg := InputEventMagnifyGesture.new()
	mg.position = mid
	mg.factor = 1.5
	var zp: float = map.zoom
	vp.push_input(mg)
	await frames(1)
	check(map.zoom > zp * 1.4, "%s: map: a pinch zooms (%.2f)" % [lang, map.zoom])
	map.reset_view()
	# The keys: + zooms, an arrow scrolls, 0 shows the whole map.
	map.grab_focus()
	map._gui_input(_key_event(KEY_EQUAL))
	map._gui_input(_key_event(KEY_EQUAL))
	var c1: Vector2 = map.center
	map._gui_input(_key_event(KEY_RIGHT))
	check(map.zoom > zr * 1.4 and map.center.x > c1.x, "%s: map: + zooms, an arrow scrolls" % lang)
	map._gui_input(_key_event(KEY_0))
	check(is_equal_approx(map.zoom, zr) and _area_in_room(map), "%s: map: 0 shows the whole map" % lang)
	# Out to the whole theatre: below the mission's area, the coarse tiles.
	for n in 40:
		map.zoom_at(1.0 / map.ZOOM_STEP, map.size / 2.0)
	await _map_settled(map)
	check(
		is_equal_approx(map.zoom, map._zoom_min()) and int(map._tiles[0]) >= 7,
		"%s: map: out to the theatre (%.2f)" % [lang, map.zoom]
	)
	# Far from the base (the theatre's middle, about 100 km north of Ramon), zoomed in: its ground and its towns load;
	# the decoded tiles stay within MAX_TILES.
	var towns0: Array = map.data.places.duplicate()
	map.center = map._bounds().get_center()
	map.zoom = 2.0
	map._clamp()
	await _map_settled(map)
	var far: Vector2 = map.center
	check(map._layers_box.has_point(far), "%s: map: the layers asked again there" % lang)
	check(map.data.places.size() > 0 and map.data.places != towns0, "%s: map: the towns there" % lang)
	var drawn: int = (
		range(0, map._tiles.size(), 7)
		. filter(
			func(t): return map._tex.has(Vector3i(int(map._tiles[t + 1]), int(map._tiles[t + 2]), int(map._tiles[t])))
		)
		. size()
	)
	check(drawn * 7 == map._tiles.size(), "%s: map: the ground there (%d tiles)" % [lang, drawn])
	check(map._tex.size() <= map.MAX_TILES, "%s: map: at most MAX_TILES kept (%d)" % [lang, map._tex.size()])
	map.reset_view()
	map.release_focus()
	# Edit: the loadout screen, its crumb back to the briefing.
	edit.pressed.emit()
	await frames(3)
	check(fe.page == "arming", "%s: Edit opens the loadout screen" % lang)
	check(fe.find_child("Crumb_mission", true, false) != null, "%s: arming: the mission's crumb" % lang)
	await _loadout_checks(fe, lang)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "mission", "%s: Esc from the loadout screen: the briefing" % lang)
	# Away and back (the Hangar, Settings, the Hangar, the mission screen): the mission kept, the map on the base.
	var mi: int = fe.mission_i
	for screen in ["hangar", "prefs", "hangar", "mission"]:
		fe.show_page(screen)
	await frames(3)
	map = fe.find_child("PageMap", true, false)
	check(fe.mission_i == mi and map.zoom > 2.0, "%s: entering again: the mission kept, the map on the base" % lang)
	# The start-up: the tower's call, then its checklist, one pin for all of it, each step's switch pictured.
	fe.open_mission(0)
	await frames(3)
	how = fe.find_child("HowScroll", true, false)
	paras = how.get_child(0).get_children()
	check(paras.size() == 6, "%s: briefing: the start-up's six paragraphs (%d)" % [lang, paras.size()])
	words = (
		"\n"
		. join(paras.map(func(r): return r.find_children("*", "RichTextLabel", true, false)[0].get_parsed_text()))
		. replace("\u00a0", " ")
	)
	for rec in [47, 119, 120, 7, 122, 123, 124]:
		var k: String = fe.key_name(rec)
		check(k != "" and words.contains(k), "%s: briefing: the key %d as bound (%s)" % [lang, rec, k])
	var first: String = paras[0].find_children("*", "RichTextLabel", true, false)[0].get_parsed_text()
	check(first.contains("tower") or first.contains("מגדל"), "%s: briefing: the tower's start-up call first" % lang)
	var pics: Array = how.find_children("Switch_*", "TextureRect", true, false)
	check(
		pics.size() == 5 and pics.all(func(p): return p.texture != null),
		(
			"%s: briefing: each step's switch pictured from the 3D cockpit, the canopy its key alone (%d)"
			% [lang, pics.size()]
		)
	)
	check(
		pics.size() > 0 and "MAIN PWR" in pics[0].tooltip_text, "%s: briefing: the switch named on its picture" % lang
	)
	check(words.contains("20") and words.contains("90"), "%s: briefing: the waits" % lang)
	var m: Control = fe.find_child("PageMap", true, false)
	check(m.runway_label == "", "%s: map: a start-up has no runway" % lang)
	check(m.data.pins.size() == 1 and int(m.data.pins[0].last) == 5, "%s: map: one pin, the whole text" % lang)
	check(fe.find_child("Fly", true, false) != null, "%s: briefing: Fly" % lang)
	fe.open_mission(1)
	await frames(2)

	# No key cap on a screen's footer (the user, 2026-11-16: "remove the back/esc hint").
	var was: String = fe.page
	# A key cap is a Label of the theme's "Key" kind: none on any screen but the Keys and Joystick screens' own
	# bound keys and buttons.
	var pages := ["hangar", "missions", "section", "mission", "arming", "log", "credits", "prefs", "keys", "joystick"]
	for p in pages + ["pilot", "pilots"]:
		fe.show_page(p)
		await frames(1)
		var foot: Node = fe.find_child("Footer", true, false)
		var caps: Array = [] if p in ["keys", "joystick"] else _labels_of(fe, "Key")
		check(
			caps.is_empty() and (foot == null or _labels(foot).all(func(x): return x != "Esc")),
			"%s: %s: no key cap %s" % [lang, p, caps]
		)
	fe.show_page(was)
	await frames(1)


func _has(root: Node, t: String) -> bool:
	return t in _labels(root).map(func(x): return x.replace("\u200f", ""))


func _has_button(root: Node, t: String) -> bool:
	return root.find_children("*", "Button", true, false).any(func(b): return b.text == t)


func _has_part(root: Node, t: String) -> bool:
	return _labels(root).any(func(x): return t in x)


func _key_event(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	return e
