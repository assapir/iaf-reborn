# Modern IAF's front end (iaf-2026/docs/front-end.md), headless, in English and Hebrew: Home → Pick a plane → Training →
# Pick a mission → (the flight skipped) → the Debrief of a stored record → Home; the texts each screen shows, the
# mirrored layout in Hebrew, the plane pick (Settings.sim_jet, the F-16 switch), the Preferences' controls and the
# live language switch both ways, the Pilot log (a row opens its debrief), a failed record's reasons and
# Attributions. Then a `--mission` run on a profile without a picked plane: the mission flies at once, the start
# command, the scoring, Esc's pause menu over the flight, its Preferences and back, End the flight, that flight's
# debrief, and Esc to Home with the mission's jet picked (the real run of front-end.md "Checks", also in a real render
# through tools/godot_window.sh; SHOT_DIR=<dir> saves the pause menu and the debrief in both languages). The records
# go to the isolated records folder (Settings.records_dir, a temporary folder): the fixture writes the JSON records
# from before the database there, and the store's first open imports them.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_front_end.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const STAMP := "20261102-080000"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/iaf-2026/missions/missionlist.json")):
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
	check(fe.page == "home", "a first start opens Home")
	check(fe.find_child("Fly", true, false) == null, "first start: no Fly before a plane")
	check(fe.find_child("change_plane", true, false) == null, "first start: no Change plane before a plane")
	var choose: Button = fe.find_child("ChoosePlane", true, false)
	check(choose != null and choose.text == "Choose a plane", "first start: Home's one action is Choose a plane")
	choose.pressed.emit()
	await frames(2)
	check(fe.page == "plane" and fe.find_child("Continue", true, false).disabled, "Choose a plane opens the picker")
	(fe.find_child("sufa", true, false) as Button).pressed.emit()
	await frames(2)
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "home" and fe.find_child("Fly", true, false) != null, "back to Home with the jet: Fly is there")
	s.sim_jet = ""
	for lang in ["en", "he"]:
		s.language = lang
		await walk(fe, ids, lang)
	s.language = "en"
	await crumbs(fe)
	await prefs(fe)
	await overlay_fits()
	await fly_once(fe)


## The breadcrumbs open their screens and keep the picks; the current one is no button.
func crumbs(fe: Control) -> void:
	var s := settings()
	s.sim_jet = "f16i"
	fe.mission_i = 1
	fe.show_page("mission")
	await frames(2)
	check(fe.find_child("Crumb_mission", true, false) == null, "crumbs: the current screen is no button")
	var home: Button = fe.find_child("Crumb_home", true, false)
	check(home != null and home.focus_mode != Control.FOCUS_NONE, "crumbs: Home is a button the keys reach")
	home.pressed.emit()
	await frames(2)
	check(fe.page == "home", "crumbs: Home from the mission screen opens Home")
	fe.show_page("mission")
	await frames(2)
	check(fe.mission_i == 1 and s.sim_jet == "f16i", "crumbs: the plane and the picked mission kept")
	(fe.find_child("Crumb_training", true, false) as Button).pressed.emit()
	await frames(2)
	check(fe.page == "training", "crumbs: the jet's crumb opens its Training")


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
	check(pause.page == "prefs", "fly: Esc from Graphics back to the sections")
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
	check(back.page == "home" and _has(back, "Sufa"), "fly: Esc from the debrief opens Home with the Sufa")


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
	fe.show_page("plane")
	await frames(2)
	check(
		fe.layout_direction == (Control.LAYOUT_DIRECTION_RTL if he else Control.LAYOUT_DIRECTION_LTR),
		"%s: layout direction" % lang
	)
	check(fe.is_layout_rtl() == he, "%s: mirrored layout flag" % lang)
	check(_has(fe, "הזרוע הארוכה" if he else "Modern IAF"), "%s: the sim's name in the header" % lang)
	check(_has(fe, "בחירת מטוס" if he else "Pick a plane"), "%s: plane: the title" % lang)
	for t in (
		["סופה", "ברק", "אדיר", "כנף 25 · רמון", "כנף 1 · רמת דוד", "כנף 28 · נבטים"]
		if he
		else ["Sufa", "Barak", "Adir", "Wing 28 · Nevatim"]
	):
		check(_has(fe, t), "%s: plane: %s" % [lang, t])
	var cards := fe.find_children("*", "Button", true, false).filter(func(b): return b.theme_type_variation == "Card")
	check(cards.size() == 3, "%s: three plane cards" % lang)
	# The cards run from the inline start: the Sufa's at the right in Hebrew.
	var sufa: Control = fe.find_child("sufa", true, false)
	var adir: Control = fe.find_child("adir", true, false)
	check((sufa.global_position.x > adir.global_position.x) == he, "%s: the cards' order mirrors" % lang)
	sufa.pressed.emit()
	await frames(2)
	check(s.sim_jet == "f16i" and s.f16_variant == "sufa", "%s: the Sufa picked (sim_jet, the F-16 switch)" % lang)
	fe.find_child("barak", true, false).pressed.emit()
	await frames(2)
	check(s.sim_jet == "f16d" and s.f16_variant == "barak", "%s: the Barak picked" % lang)
	fe.find_child("sufa", true, false).pressed.emit()
	await frames(2)
	fe.find_child("Continue", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "training", "%s: Continue opens Training" % lang)
	check(_has(fe, "לטוס בסופה" if he else "Fly the Sufa"), "%s: training: the title" % lang)
	check(_has(fe, "1 · התנעה ברמון" if he else "1 · Start-up at Ramon"), "%s: training: mission 1" % lang)
	check(_has(fe, "2 מתוך 2 עברו" if he else "2 of 2 passed"), "%s: training: the progress" % lang)
	fe.find_child("Open", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "mission" and fe.missions.size() == 2, "%s: Open lists the two missions" % lang)
	fe.find_child("Mission2", true, false).pressed.emit()
	await frames(2)
	check(_has(fe, "המראה מרמון" if he else "Take-off from Ramon"), "%s: mission: the take-off picked" % lang)
	check(_has_part(fe, "25R"), "%s: mission: the runway" % lang)
	check(_has(fe, "15 דקות" if he else "15 min"), "%s: mission: the time allowed" % lang)
	var list: Control = fe.find_child("Mission1", true, false)
	var pane: Control = fe.find_child("Briefing", true, false)
	check((list.global_position.x > pane.global_position.x) == he, "%s: the list and the briefing mirror" % lang)
	# The flight is skipped: the stored record comes back as the flight's.
	s.flown_sortie = ids.pass
	fe.show_page("home")
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
			"כנף 25 · רמון, מסלול 25R",
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
			"Wing 25 · Ramon, runway 25R",
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
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "home", "%s: Esc from the debrief: Home" % lang)
	check(
		_has(fe, "לטוס" if he else "Fly") and _has(fe, "יומן טיסות" if he else "Pilot log"),
		"%s: home: Fly and the log" % lang
	)
	check(
		_has(fe, "קרדיט" if he else "Attributions") and _has(fe, "יציאה" if he else "Quit"), "%s: home: the menu" % lang
	)
	check(_labels_of(fe, "Stat").has("3"), "%s: home: three flights" % lang)
	var fly: Control = fe.find_child("Fly", true, false)
	check((fly.global_position.x > 960) == he, "%s: home: the column on the inline start" % lang)
	fe.show_page("log")
	await frames(2)
	check(_has(fe, "המראה מרמון" if he else "Take-off from Ramon"), "%s: log: the take-off" % lang)
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
	check(fe.find_child("Pref_shadows", true, false) == null, "prefs: the list holds no rows")
	# Each section on its own screen, Esc back to the list.
	var rows := {}
	for g in sections:
		(fe.find_child("Section_" + g, true, false) as Button).pressed.emit()
		await frames(2)
		check(fe.page == "prefs_section" and fe.pref_group == g, "prefs: %s opens its own screen" % g)
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
		key(fe, KEY_ESCAPE)
		await frames(2)
		check(fe.page == "prefs", "prefs: Esc from %s back to the list" % g)
	check(s.rejected.size() == refused, "prefs: the screens read none of the original's data (%s)" % [s.rejected])
	for k in ["antialiasing", "upscaling", "shadows", "terrain_detail", "clouds", "scenery", "fullscreen", "vsync"]:
		check(rows.get(k) == "graphics", "prefs: Graphics has %s" % k)
	for k in ["engine_volume", "sfx_volume", "speech_volume", "mute"]:
		check(rows.get(k) == "sound", "prefs: Sound has %s" % k)
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


func _labels_of(root: Node, kind: String) -> Array:
	var labels := root.find_children("*", "Label", true, false)
	return labels.filter(func(n): return n.theme_type_variation == kind).map(func(n): return n.text)


func _has(root: Node, t: String) -> bool:
	return t in _labels(root)


func _has_part(root: Node, t: String) -> bool:
	return _labels(root).any(func(x): return t in x)


func _key_event(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	return e
