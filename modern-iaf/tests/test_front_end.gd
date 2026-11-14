# Modern IAF's front end (modern-iaf/docs/front-end.md), headless, in English and Hebrew: the Hangar → Pick a mission →
# (the flight skipped) → the Debrief of a stored record → the Hangar; the texts each screen shows, the mirrored layout
# in Hebrew, the plane pick (Settings.sim_jet, the F-16 switch), the Preferences' controls and the live language switch
# both ways, the Pilot log (a row opens its debrief), a failed record's reasons and Attributions. Then a `--mission` run
# on a profile without a picked plane: the mission flies at once, the start command, the scoring, Esc's pause menu over
# the flight, its Preferences and back, End the flight, that flight's debrief, and Esc to the Hangar with the mission's
# jet picked (the real run of front-end.md "Checks", also in a real render through tools/godot_window.sh; SHOT_DIR=<dir>
# saves the pause menu and the debrief in both languages). The records go to the isolated records folder
# (Settings.records_dir, a temporary folder): the fixture writes the JSON records from before the database there, and
# the store's first open imports them.
# IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf
# \     -s ../modern-iaf/tests/test_front_end.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const STAMP := "20261102-080000"


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
	await prefs(fe)
	for lang in ["en", "he"]:
		s.language = lang
		await pilot(fe, lang)
	s.language = "en"
	await overlay_fits()
	await fly_once(fe)


## The first start (no profile stored): the Pilot screen makes one before the Hangar, Save only with a name, Esc stays;
## Save stores the name on the active pilot (its imported sorties kept) and opens the Hangar.
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
	var e: LineEdit = fe.find_child("Field_name", true, false)
	await type_into(e, "Noa Golan")
	check(not save.disabled and e.text == "Noa Golan", "first start: typed, Save on (%s)" % e.text)
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
	fe.mission_i = 1
	fe.show_page("mission")
	await frames(2)
	check(not _has_button(fe, fe.s("training")), "crumbs: the current screen is no button")
	var home: Button = fe.find_child("Crumb_hangar", true, false)
	check(home != null and home.focus_mode != Control.FOCUS_NONE, "crumbs: the Hangar is a button the keys reach")
	home.pressed.emit()
	await frames(2)
	check(fe.page == "hangar", "crumbs: the Hangar crumb from the mission screen opens the Hangar")
	fe.show_page("mission")
	await frames(2)
	check(fe.mission_i == 1 and s.sim_jet == "f16i", "crumbs: the plane and the picked mission kept")
	(fe.find_child("Crumb_jet", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "hangar", "crumbs: the jet's crumb opens the Hangar")
	fe.open_debrief(int(fe.sorties()[-1].id))
	await frames(2)
	(fe.find_child("Crumb_mission", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "mission", "crumbs: the debrief's Training crumb opens the missions")


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
	# The start-up checklist by its keys (training.md §7.1), each at its moment.
	var t0 := Time.get_ticks_msec()
	for step in [1, 2, 3, 4, 5, 6]:
		var rpm := {3: 0.2, 4: 0.55}.get(step, 0.0) as float
		while float(tv.flight.state().rpm) < rpm and Time.get_ticks_msec() - t0 < 60000:
			await process_frame
		tv._command([209 + step, 0, 0])
	while tv.addon.result.is_empty() and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	Engine.time_scale = 1.0
	check(bool(tv.addon.result.get("pass", false)), "fly: the start-up scored a pass")
	tv._esc_key()
	await frames(3)
	var pause: Node = tv.fe_overlay
	check(pause != null and pause.page == "pause" and _has(pause, "Paused"), "fly: Esc opens the pause menu")
	pause.find_child("PausePrefs", true, false).pressed.emit()
	await frames(2)
	check(
		pause.page == "prefs" and pause.find_child("Section_graphics", true, false) != null, "fly: pause, Preferences"
	)
	(pause.find_child("Section_graphics", true, false) as Button).pressed.emit()
	await frames(2)
	check(pause.find_child("Pref_shadows", true, false) != null, "fly: pause, Preferences, Graphics")
	key(pause, KEY_ESCAPE)
	await frames(2)
	check(pause.page == "pause" and tv.fe_overlay == pause, "fly: Esc from Preferences back to the pause menu")
	var shot := OS.get_environment("SHOT_DIR")
	if shot != "":
		await _shots(pause, shot, "pause")
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
	if shot != "":
		await _shots(back, shot, "flown_debrief")
	key(back, KEY_ESCAPE)
	await frames(2)
	check(
		back.page == "hangar" and settings().sim_jet == "f16i" and _has(back, "F-16I Sufa"),
		"fly: Esc from the debrief opens the Hangar on the mission's jet (%s, %s)" % [back.page, settings().sim_jet]
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
	var camp: Button = fe.find_child("Campaign", true, false)
	check(camp != null and camp.disabled and camp.tooltip_text == "", "%s: hangar: Missions and campaign greyed" % lang)
	check(_has(fe, "2 מתוך 2 עברו" if he else "2 of 2 passed"), "%s: hangar: the progress" % lang)
	fe.find_child("Fly", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "mission" and fe.missions.size() == 2, "%s: Fly lists the two missions" % lang)
	fe.find_child("Mission2", true, false).pressed.emit()
	await frames(2)
	check(_has(fe, "המראה" if he else "Take-off"), "%s: mission: the take-off picked" % lang)
	check(_has_part(fe, "25R"), "%s: mission: the runway" % lang)
	check(_has(fe, "15") and _has(fe, "דקות" if he else "min"), "%s: mission: the time allowed" % lang)
	var list: Control = fe.find_child("Mission1", true, false)
	var pane: Control = fe.find_child("Briefing", true, false)
	check((list.global_position.x > pane.global_position.x) == he, "%s: the list and the briefing mirror" % lang)
	await _briefing_checks(fe, lang)
	# The flight is skipped: the stored record comes back as the flight's.
	s.flown_sortie = ids.pass
	fe.show_page("hangar")
	fe._ready()
	await frames(2)
	check(fe.page == "debrief", "%s: a flight's end opens its debrief" % lang)
	for t in (
		[
			"מטוס",
			"מבסיס",
			"זמן",
			"משימה",
			"תוצאה",
			"המספרים",
			"הערות",
			"F-16I סופה",
			"רמון, מסלול 25R",
			"מסלול",
			"25R",
			"3.1 מ׳",
			"172 קשר"
		]
		if he
		else [
			"Plane flown",
			"From",
			"Time",
			"Mission",
			"Result",
			"THE NUMBERS",
			"REMARKS",
			"F-16I Sufa",
			"Ramon, runway 25R",
			"Runway",
			"25R",
			"3.1 m",
			"172 kt",
			"PASS"
		]
	):
		check(_has(fe, t), "%s: debrief: %s" % [lang, t])
	check(_has(fe, "2.11.2026 · 08:00–08:11" if he else "2 Nov 2026 · 08:00–08:11"), "%s: debrief: the time" % lang)
	for t in (
		["הניתוק ב־13 קשר מעל המהירות המומלצת.", "המטוס באוויר עם כן נסע אסוף, בכיוון המסלול. לא נרשם כשל."]
		if he
		else [
			"Lift-off 13 kt above the reference speed.",
			"Airborne with the gear up on the runway heading. Nothing failed."
		]
	):
		check(_has(fe, t), "%s: debrief remark: %s" % [lang, t])
	# Only the goals: the other numbers stay in the record.
	for t in ["1,140 מ׳", "5:12 דק׳", "13,420 ק״ג"] if he else ["1,140 m", "5:12 min", "13,420 kg"]:
		check(not _has(fe, t), "%s: debrief: no %s (not a goal)" % [lang, t])
	fe.find_child("BackMissions", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "mission" and fe.mission_i == 1, "%s: Back to missions picks the flown take-off" % lang)
	fe.open_debrief(ids.pass)
	await frames(2)
	fe.find_child("FlyAgain", true, false).pressed.emit()
	await frames(2)
	check(
		fe.page == "mission" and fe.mission_i == 1 and fe.brief_tab == 0,
		"%s: Fly again opens the flown take-off's briefing, not the flight" % lang
	)
	check(_has(fe, "אימון" if he else "Training"), "%s: Fly again: the Training breadcrumb" % lang)
	var fly_btn: Control = fe.find_child("Fly", true, false)
	check(fly_btn != null and fly_btn.has_focus(), "%s: Fly again: the briefing's Fly focused" % lang)
	fe.open_debrief(ids.pass)
	await frames(2)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "hangar", "%s: Esc from the debrief: the Hangar" % lang)
	check(fe.find_child("pilot_log", true, false) == null, "%s: hangar: no Pilot log entry (the pilot block's)" % lang)
	check(fe.find_child("credits", true, false) is Button, "%s: hangar: Attributions" % lang)
	check(_labels_of(fe, "Stat").is_empty(), "%s: hangar: no flight counts" % lang)
	check(not _has(fe, "בחירה" if he else "Select"), "%s: hangar: no key hints" % lang)
	fe.show_page("pilot")
	await frames(2)
	(fe.find_child("pilot_log", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "log", "%s: the Pilot screen's Pilot log opens the Pilot log" % lang)
	check(_has(fe, "המראה" if he else "Take-off"), "%s: log: the take-off" % lang)
	var rows: Array = fe.find_child("Log", true, false).find_children("*", "Button", true, false)
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
		_has(fe, "Copernicus DEM GLO-30") and _has(fe, "Wikimedia Commons"),
		"%s: attributions: the wizard's list and the photos" % lang
	)


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
			var aa: OptionButton = fe.find_child("Pref_antialiasing", true, false).find_child("Control", true, false)
			check(aa.get_item_text(aa.selected).begins_with("MSAA 4×"), "prefs: antialiasing is a dropdown at MSAA 4×")
			var sh: CheckButton = fe.find_child("Pref_shadows", true, false).find_child("Control", true, false)
			sh.button_pressed = false
			check(s.shadows == false, "prefs: the shadows switch sets the setting")
			sh.button_pressed = true
			var sc: Control = fe.find_child("Pref_scenery", true, false)
			var radios := sc.find_children("*", "CheckBox", true, false)
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
	check(rows.get("language") == "language", "prefs: Language has the language")
	for k in [
		"flight_data", "unlimited_fuel", "invulnerable", "no_crashes", "no_blackouts", "rain", "water", "ground_roads"
	]:
		check(not rows.has(k), "prefs: no %s row (no realism switch, no aid, nothing the profile fixes)" % k)
	(fe.find_child("Section_language", true, false) as Button).pressed.emit()
	await frames(2)
	var lang: OptionButton = fe.find_child("Pref_language", true, false).find_child("Control", true, false)
	lang.select(1)
	lang.item_selected.emit(1)
	await frames(2)
	check(s.language == "he" and fe.is_layout_rtl() and _has(fe, "שפה"), "prefs: Hebrew switches every string at once")
	lang = fe.find_child("Pref_language", true, false).find_child("Control", true, false)
	lang.select(0)
	lang.item_selected.emit(0)
	await frames(2)
	check(s.language == "en" and not fe.is_layout_rtl() and _has(fe, "Language"), "prefs: and back to English")
	key(fe, KEY_ESCAPE)
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
	FileAccess.open(file, FileAccess.WRITE).store_string(JSON.stringify(rec))
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
					{"result": 1, "debrief": file, "date": "2026-11-02T08:11:00"},
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
	return ids


func _labels(root: Node) -> Array:
	return (
		root
		. find_children("*", "", true, false)
		. filter(func(n): return n is Label or n is Button)
		. map(func(n): return n.text)
	)


## The loadout editor (front-end.md §10) on the Sufa's take-off: a refused drop changes nothing, a drop fills the
## mirror station too, a store dragged back to the inventory takes its pair off, the keyboard path (Enter on a slot,
## Enter on an inventory entry), the figures with it, the loadout stored per pilot per jet and handed to the flight
## (fly.gd arm), the maximum (a lowered one: the take-off weight red, Fly off), Reset.
func _loadout_checks(fe: Control, lang: String) -> void:
	var s := settings()
	var db: String = s.records_db()
	var stored := func() -> String: return IafPilotLog.loadout(db, s.pilot(), "f16i")
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	var drawing: Control = fe.find_child("Drawing", true, false)
	drawing.dropped({"store": "tank-370", "from": ""}, "2")
	await frames(3)
	check(stored.call() == "", "%s: loadout: a tank on station 2 is refused" % lang)
	drawing.dropped({"store": "mk-84", "from": ""}, "3")
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	check(
		drawing.stores[3][0] == "mk-84" and drawing.stores[7][0] == "mk-84" and drawing.stores[2][0] == "aim-9m",
		"%s: loadout: an MK-84 on 3 fills 7 too" % lang
	)
	var count: Label = fe.find_child("Itemmk-84", true, false).find_child("Count", false, false)
	check(count == null, "%s: loadout: no count without the record's (the slots show what is on)" % lang)
	check(
		fe.find_child("Group_ground", true, false).get_child_count() >= 8,
		"%s: loadout: the long inventory, the air-to-ground group two to a row" % lang
	)
	var facts: Control = fe.find_child("ArmingFacts", true, false)
	check(_has(facts, "17,747"), "%s: loadout: the take-off weight with two MK-84s for two AIM-9Ms" % lang)
	# A slot's store dropped on an inventory entry (in its group's grid) goes back through the column.
	var on_item: Control = fe.find_child("Itemmk-84", true, false)
	check(
		on_item._can_drop_data(Vector2.ZERO, {"store": "tank-370", "from": "4"}), "%s: loadout: drop on an entry" % lang
	)
	on_item._drop_data(Vector2.ZERO, {"store": "tank-370", "from": "4"})
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	facts = fe.find_child("ArmingFacts", true, false)
	check(
		not drawing.stores.has(4) and not drawing.stores.has(6) and _has(facts, "4,014"),
		"%s: loadout: the tanks back to the inventory, their fuel off" % lang
	)
	# The keyboard: Enter on slot 4 picks it, the focus on the tank; Enter there hangs both tanks.
	fe._arm_pick("4")
	await frames(2)
	var fo := fe.get_viewport().gui_get_focus_owner()
	check(fo != null and fo.name == "Itemmk-82", "%s: loadout: Enter on a slot, the focus on what it takes" % lang)
	fe._arm_choose("tank-370")
	await frames(4)
	drawing = fe.find_child("Drawing", true, false)
	fo = fe.get_viewport().gui_get_focus_owner()
	check(
		drawing.stores.get(4, [""])[0] == "tank-370" and drawing.stores.get(6, [""])[0] == "tank-370",
		"%s: loadout: Enter on the tank hangs both" % lang
	)
	check(fo != null and fo.name == "Slot4", "%s: loadout: the focus back on the slot" % lang)
	var lo_keep: String = stored.call()
	# A TER: three Mk 82 on 4 and on 6, the slot's count.
	drawing.dropped({"store": "mk-82", "from": ""}, "4")
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	check(
		drawing.stores.get(4, [])[2] == 3 and drawing.stores.get(6, [])[2] == 3,
		"%s: loadout: three Mk 82 on a rack on 4 and 6" % lang
	)
	# The "×3" badge: a click cycles the pair to two each.
	fe._arm_cycle(fe.missions[fe.mission_i], "4")
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	check(
		drawing.stores[4][2] == 2 and drawing.stores[6][2] == 2 and drawing.slots["4"].badge_rect.has_area(),
		"%s: loadout: the badge cycles the rack 3 to 2, the pair along" % lang
	)
	# A store with no model of ours yet: greyed, not dragged, not focused.
	var dl: Control = fe.find_child("Itemdelilah", true, false)
	check(
		(
			dl != null
			and not dl.flyable
			and dl.focus_mode == Control.FOCUS_NONE
			and dl._get_drag_data(Vector2.ZERO) == null
		),
		"%s: loadout: the Delilah disabled for now" % lang
	)
	# One-sided: a tank on 4 and an MK-84 on 3 alone, past the limit: the imbalance amber, Fly still on.
	var one_sided := {"3": {"id": "mk-84", "count": 1}, "4": {"id": "tank-370", "count": 1}}
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", JSON.stringify(one_sided))
	fe._arm_redraw(fe.missions[fe.mission_i])
	await frames(3)
	var imb: Control = fe.find_child("Fact_imbalance", true, false)
	check(
		imb != null and not fe.find_child("Fly", true, false).disabled,
		"%s: loadout: the wings out of balance, a warning, Fly on" % lang
	)
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", lo_keep)
	fe._arm_redraw(fe.missions[fe.mission_i])
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	drawing.dropped({"store": "tank-370", "from": ""}, "4")
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	# Handed to the flight: the MK-84 (record number 2) on pylons C and G, the AIM-9M (1) on A.
	var mission := "ramon_takeoff"
	var m: Dictionary = s.load_json(s.converted(s.missions_folder()).path_join(mission + ".json"))
	if not m.is_empty():
		load("res://flight/fly.gd").arm(m, s.load_json("res://data/missions/%s.json" % mission))
		var pylons: Array = s.arm_loadouts.values()[0] if s.arm_loadouts.size() == 1 else []
		check(
			(
				pylons.size() == 9
				and pylons[2] == [2.0, 1.0, 0.0, 0.0]
				and pylons[6] == [2.0, 1.0, 0.0, 0.0]
				and pylons[0] == [1.0, 1.0, 0.0, 0.0]
			),
			"%s: loadout: the flight's pylons (%s)" % [lang, pylons]
		)
		s.arm_loadouts = {}
	# Over a (lowered) maximum: the take-off weight red, Fly off.
	var dir := OS.get_temp_dir().path_join("modern-iaf-units-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var u: Dictionary = s.load_json("res://data/db/units/f16i.json")
	u["max_takeoff_kg"] = 17000
	FileAccess.open(dir.path_join("f16i.json"), FileAccess.WRITE).store_string(JSON.stringify(u))
	fe.units_dir = dir
	fe._arm_redraw(fe.missions[fe.mission_i])
	await frames(3)
	var fly: Button = fe.find_child("Fly", true, false)
	var tw: Control = fe.find_child("Fact_takeoff_weight", true, false)
	check(
		(
			fly.disabled
			and tw.find_children("*", "Label", true, false)[1].get_theme_color("font_color") == Color("ff6b6b")
		),
		"%s: loadout: over the maximum, the weight red and Fly off" % lang
	)
	fe.units_dir = "res://data/db/units"
	DirAccess.remove_absolute(dir.path_join("f16i.json"))
	DirAccess.remove_absolute(dir)
	fe.find_child("ArmReset", true, false).pressed.emit()
	await frames(3)
	drawing = fe.find_child("Drawing", true, false)
	check(
		stored.call() == "" and drawing.stores[3][0] == "aim-9m" and not fe.find_child("Fly", true, false).disabled,
		"%s: loadout: Reset, the default again" % lang
	)


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


## The briefing (front-end.md §10) of the take-off picked, then of the start-up: the Briefing page (the title as the
## kind, the time as military time, the wind as pilots read it, the objectives, the runway's heading, how: the steps
## with their keys and a free fourth column), the Map page by its tab and by the arrow keys (one map that zooms around
## the pointer, scrolls, resets, follows the keys, its scale bar with the zoom), the Arming page (the front view with
## a slot per station with its store, the weights; the Map's credit), the subtitle, the steps with their
## switches and waits, each tower call its own step, Fly.
func _briefing_checks(fe: Control, lang: String) -> void:
	var he := lang == "he"
	fe.show_tab(0)
	await frames(2)
	var pane: Control = fe.find_child("Briefing", true, false)
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
	var steps: GridContainer = pane.find_child("Steps", true, false)
	check(steps.columns == 4 and steps.get_child_count() == 7 * 4, "%s: briefing: the take-off's seven steps" % lang)
	check(not _has_part(steps, "מדפים" if he else "Flaps"), "%s: briefing: no flaps step" % lang)
	# Each call to the tower its own step: start-up, taxi, line-up, take-off at the menu's picks 1-4, with the answer
	# to wait for.
	# The keys by the table, as the player's platform names them: Ctrl + T, "⌘ + T" on a Mac (key_table.gd cmd_is_ctrl).
	var tower: String = fe.key_name(47)
	check(tower != "", "%s: briefing: the tower key named" % lang)
	var calls := 0
	for k in 4:
		calls += _labels(steps).count("%s, %d" % [tower, k + 1])
	check(calls == 4, "%s: briefing: four tower calls, Ctrl + T, 1-4 (%d)" % [lang, calls])
	check(_has_part(steps, "בקשת כניסה למסלול" if he else "request line-up"), "%s: briefing: the line-up call" % lang)
	check(_has_part(steps, "אישור המראה" if he else "cleared for take-off"), "%s: briefing: the wait" % lang)
	check(
		_has(pane, "846 · טייסת 201 האחת · רמון" if he else "846 · 201 Squadron The One · Ramon"), "%s: subtitle" % lang
	)
	var credit: Label = fe.find_child("Credit", true, false)
	check(credit != null and credit.text.strip_edges() == "", "%s: no credit on the Briefing page" % lang)
	check(_has_part(steps, "מגדל" if he else "tower"), "%s: briefing: the tower step" % lang)
	var tabs: Array = ["Briefing", "Map", "Arming"].map(func(t): return pane.find_child("Tab" + t, true, false))
	check((tabs[0].global_position.x > tabs[2].global_position.x) == he, "%s: briefing: the tabs mirror" % lang)
	check(not pane.find_child("PageMap", true, false).visible, "%s: briefing: the Briefing page first" % lang)
	check(_has(pane, "חימוש" if he else "Arming"), "%s: arming: the tab's name" % lang)
	tabs[2].pressed.emit()
	await frames(3)
	check(pane.find_child("PageArming", true, false).visible, "%s: arming: its tab opens the Arming page" % lang)
	var drawing: Control = pane.find_child("Drawing", true, false)
	check(drawing != null and drawing.picture != null, "%s: arming: our own Sufa's front view" % lang)
	check(drawing.stations.size() == 8 and drawing.stores.size() == 8, "%s: arming: eight stations loaded" % lang)
	var title: Label = pane.find_child("ArmingJet", true, false)
	check(
		title.text == "%s · \u2066F-16I\u2069 · \u2066846\u2069" % ("סופה" if he else "Sufa"),
		"%s: arming: the jet's own name, the Latin and digits isolated (%s)" % [lang, title.text]
	)
	check(not _has_part(fe, "F-16C"), "%s: arming: no F-16C" % lang)
	check(
		(
			drawing.stores[1].slice(0, 3) == ["aim-9m", "AIM-9M", 1]
			and drawing.stores[4].slice(0, 3) == ["tank-370", "בידון 370" if he else "370 gal tank", 1]
		),
		"%s: arming: 1 an AIM-9M, 4 a drop tank" % lang
	)
	check(pane.find_child("Stores", true, false) == null, "%s: arming: the drawing, not the list" % lang)
	var facts: Control = pane.find_child("ArmingFacts", true, false)
	check(_has(facts, "511") and _has(facts, "60"), "%s: arming: the rounds, chaff and flares" % lang)
	check(
		_has(facts, "6,254") and _has(facts, "16,069") and _has(facts, "23,582"),
		"%s: arming: fuel, the take-off weight and the maximum, each its own field" % lang
	)
	check(facts.alignment == BoxContainer.ALIGNMENT_CENTER, "%s: arming: the figures centred" % lang)
	check(not _has_part(fe, "FlightGear"), "%s: arming: no credit for our own drawing" % lang)
	check(drawing.store_picture("tank-370") != null, "%s: arming: the drop tank's picture" % lang)
	await frames(2)
	# A slot per station, the wing row in station order 9 to 1 left to right, the tanks straight under 4 and 6.
	var sl: Dictionary = drawing.slots
	check(sl.size() == 8 and sl["1"].tooltip_text == "AIM-9M", "%s: arming: a slot per station, the tooltip" % lang)
	var xs: Array = ["9", "8", "7", "3", "2", "1"].map(func(n): return sl[n].position.x)
	var ordered := true
	for i in range(1, xs.size()):
		ordered = ordered and xs[i] >= xs[i - 1] + sl["1"].size.x
	check(ordered, "%s: arming: the wing slots in station order, apart (%s)" % [lang, xs])
	for n in ["4", "6"]:
		var lead: Array = drawing._leaders[n]
		check(
			absf(lead[0].x - lead[1].x) < 1.0 and sl[n].position.y > sl["1"].position.y,
			"%s: arming: station %s's tank in the second row, straight under it" % [lang, n]
		)
	check(not _has_part(fe, "OpenStreetMap"), "%s: arming: no map credit" % lang)
	var adir: Dictionary = fe.arming({"start": {"unit": "f35i"}})
	check(
		float(adir.stores_kg) == 2.0 * 161.5 and adir.internal == [4.0, 5.0, 7.0, 8.0] and fe.DRAWINGS.has("f35i"),
		"%s: arming: the Adir's own drawing, two AIM-120 in its bays" % lang
	)
	var inv: Control = pane.find_child("Inventory", true, false)
	check(
		inv != null and inv.find_child("Itemaim-120", true, false) != null and inv.find_child("Itemmk-84", true, false),
		"%s: arming: the Sufa's inventory column, each store one Control" % lang
	)
	var row: Control = pane.find_child("ArmingRow", true, false)
	check(
		(inv.global_position.x > drawing.global_position.x) == (lang == "en"),
		"%s: arming: the inventory on the block-end side" % lang
	)
	check(row != null and inv.size.x >= 150, "%s: arming: the column its width" % lang)
	await _loadout_checks(fe, lang)
	tabs[1].pressed.emit()
	await frames(3)
	check(not pane.find_child("PageBriefing", true, false).visible, "%s: map: its tab opens the Map page" % lang)
	var map: Control = pane.find_child("PageMap", true, false)
	check(map.size.x > 900 and map.size.y > 500, "%s: map: the full panel (%s)" % [lang, map.size])
	var d: Dictionary = map.data
	check(absf(float(d.size[0]) / float(d.size[1]) - map.size.x / map.size.y) < 0.02, "%s: map: the aspect" % lang)
	check(d.runways.size() >= 2 and d.route.size() == 4 and d.taxi.size() >= 4, "%s: map: runways, taxi, route" % lang)
	check(d.aprons.size() > 0 and d.taxiways.size() > 0 and d.parking.size() > 0, "%s: map: the airbase" % lang)
	check(map.base_label == ("רמון" if he else "Ramon"), "%s: map: the base" % lang)
	# The roads with setup's road layer (the optional scenery step); without it the map draws the ground alone.
	var roads: bool = load("res://shared/terrain/ground_roads.gd").available()
	check(
		d.get("texture") is Texture2D and (d.roads.size() > 0) == roads, "%s: map: the ground, roads %s" % [lang, roads]
	)
	var towns: Array = d.places.map(func(p): return p.he if he else p.en)
	check(("מצפה רמון" if he else "Mitspe Ramon") in towns, "%s: map: Mitzpe Ramon (%s)" % [lang, towns])
	check(fe.find_child("Footer", true, false) != null and _has_part(fe, "OpenStreetMap"), "%s: map: credit" % lang)
	var foot: Control = fe.find_child("Footer", true, false)
	check(foot.get_child(-1).name == "Credit", "%s: map: the credit at the footer's inline end" % lang)
	# The credit reads in the language's direction ("מפה:" with its colon at the word's end, on its left).
	var credit_label: Label = foot.get_child(-1)
	check(credit_label.is_layout_rtl() == he, "%s: map: the credit right to left" % lang)
	# The wheel zooms around the pointer: the map point under it stays; the scale bar follows.
	var at := map.size * Vector2(0.3, 0.6)
	var under: Vector2 = map._xf().affine_inverse() * at
	var scale0: int = map.scale_metres()
	for n in 8:
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP
		w.pressed = true
		w.position = at
		map._gui_input(w)
	check(map.zoom > 5.0, "%s: map: the wheel zooms in (%.2f)" % [lang, map.zoom])
	var still: Vector2 = map._xf() * under
	check(still.distance_to(at) < 1.0, "%s: map: zoomed around the pointer (%s)" % [lang, still - at])
	check(map.scale_metres() < scale0, "%s: map: the scale bar follows (%d m)" % [lang, map.scale_metres()])
	# A drag scrolls; a double click resets.
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
	check(is_equal_approx(map.zoom, 1.0), "%s: map: a double click resets" % lang)
	# At the whole map, through the window (nothing over the map takes the events): a left drag and a middle drag
	# move it, a trackpad's two-finger scroll (a pan gesture) moves it, a pinch (a magnify gesture) zooms.
	var vp := map.get_viewport()
	# A point of the map inside the window (the headless window is smaller than the front end's page).
	var seen := map.get_global_rect().intersection(vp.get_visible_rect())
	# In the window's pixels (the project's stretch scales the canvas into the window).
	var mid := vp.get_final_transform() * seen.get_center()
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
	vp.push_input(mg)
	await frames(1)
	check(map.zoom > 1.4, "%s: map: a pinch zooms (%.2f)" % [lang, map.zoom])
	map.reset_view()
	# The keys: + zooms, an arrow scrolls (the map has the focus: the arrows stay off the tabs), 0 resets.
	map.grab_focus()
	map._gui_input(_key_event(KEY_EQUAL))
	map._gui_input(_key_event(KEY_EQUAL))
	var c1: Vector2 = map.center
	map._gui_input(_key_event(KEY_RIGHT))
	fe._input(_key_event(KEY_RIGHT))
	check(map.zoom > 1.4 and map.center.x > c1.x, "%s: map: + zooms, an arrow scrolls" % lang)
	check(fe.brief_tab == 1, "%s: map: the arrows scroll the focused map, not the tabs" % lang)
	map._gui_input(_key_event(KEY_0))
	check(is_equal_approx(map.zoom, 1.0), "%s: map: 0 resets" % lang)
	map.release_focus()
	# The arrow key toward the inline start goes back to Briefing; toward the end to Map.
	fe._input(_key_event(KEY_RIGHT if he else KEY_LEFT))
	check(fe.brief_tab == 0 and pane.find_child("PageBriefing", true, false).visible, "%s: arrow: Briefing" % lang)
	fe._input(_key_event(KEY_LEFT if he else KEY_RIGHT))
	check(fe.brief_tab == 1, "%s: arrow: Map" % lang)
	fe.find_child("Mission1", true, false).pressed.emit()
	await frames(2)
	pane = fe.find_child("Briefing", true, false)
	check(pane.find_child("PageMap", true, false).visible, "%s: the page kept for the next mission" % lang)
	# Away and back (the Hangar, Preferences, the Hangar, the mission screen): the briefing opens on its first page, the
	# map whole.
	var mi: int = fe.mission_i
	for screen in ["hangar", "prefs", "hangar", "mission"]:
		fe.show_page(screen)
	await frames(2)
	pane = fe.find_child("Briefing", true, false)
	var mp: Control = pane.find_child("PageMap", true, false)
	check(
		(
			fe.brief_tab == 0
			and pane.find_child("PageBriefing", true, false).visible
			and is_equal_approx(mp.zoom, 1.0)
			and fe.mission_i == mi
		),
		"%s: entering the mission screen again opens Briefing, the map whole, the mission kept" % lang
	)
	fe.show_tab(1)
	fe.show_tab(0)
	steps = pane.find_child("Steps", true, false)
	check(steps.get_child_count() == 6 * 4, "%s: briefing: the start-up's six checklist steps" % lang)
	var check_key: String = fe.key_name(fe.SimFlight.CHECK_KEY)
	check(check_key != "" and _has(steps, check_key), "%s: briefing: the checklist's keys as bound" % lang)
	check(
		_has(steps, fe.key_name(fe.SimFlight.THROTTLE_IDLE_KEY)), "%s: briefing: the idle step's key, the card's" % lang
	)
	var pics: Array = steps.find_children("Switch*", "TextureRect", true, false)
	check(
		pics.size() == 6 and pics.all(func(p): return p.texture != null),
		"%s: briefing: each step's switch pictured from the 3D cockpit (%d)" % [lang, pics.size()]
	)
	check(
		pics.size() > 0 and "MAIN PWR" in pics[0].tooltip_text, "%s: briefing: the switch named on its picture" % lang
	)
	check(_has_part(steps, "20") and _has_part(steps, "90"), "%s: briefing: the waits" % lang)
	var m: Control = pane.find_child("PageMap", true, false)
	check(m.runway_label == "", "%s: map: a start-up has no runway" % lang)
	check(pane.find_child("Fly", true, false) != null, "%s: briefing: Fly" % lang)
	fe.find_child("Mission2", true, false).pressed.emit()
	await frames(2)


## The texts without the right-to-left mark that leads a Hebrew jet name (front_end.gd full_name).
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
