# Modern IAF's front end (iaf-2026/docs/front-end.md), headless, in English and Hebrew: Home → Pick a plane → Training →
# Pick a mission → (the flight skipped) → the Debrief of a stored record → Home; the texts each screen shows, the
# mirrored layout in Hebrew, the plane pick (Settings.sim_jet, the F-16 switch), the Preferences' controls and the
# live language switch both ways, the Pilot log (a row opens its debrief), a failed record's reasons and
# Attributions. Then a `--mission` run on a profile without a picked plane: the mission flies at once, the start
# command, the scoring, Esc's pause menu over the flight, its Preferences and back, End the flight, that flight's
# debrief, and Esc to Home with the mission's jet picked (the real run of front-end.md "Checks", also in a real render
# through tools/godot_window.sh; SHOT_DIR=<dir> saves the pause menu and the debrief in both languages). The records
# go to the isolated folders (Settings.debriefs_dir, a temporary folder).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_front_end.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const STAMP := "20261102-080000"
const FAIL_STAMP := "20261102-090000"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/iaf-2026/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	var file := fixture(s)
	s.sim_jet = ""
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	check(fe.page == "plane", "a first start opens Pick a plane")
	check(fe.find_child("Continue", true, false).disabled, "first start: Continue waits for a pick")
	key(fe, KEY_ESCAPE)
	await frames(2)
	check(fe.page == "plane", "first start: Esc stays on Pick a plane")
	fe.show_page("home")
	check(fe.page == "plane", "first start: Home needs a plane, so Pick a plane opens")
	for lang in ["en", "he"]:
		s.language = lang
		await walk(fe, file, lang)
	s.language = "en"
	await prefs(fe)
	await fly_once(fe)


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
	Engine.time_scale = 6.0
	var e := InputEventKey.new()
	e.keycode = KEY_E
	e.physical_keycode = KEY_E
	e.ctrl_pressed = true
	e.pressed = true
	tv._unhandled_input(e)
	var t0 := Time.get_ticks_msec()
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
	check(pause.page == "prefs" and pause.find_child("Pref_shadows", true, false) != null, "fly: pause, Preferences")
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
	check(_has(back, "Time to idle"), "fly: the debrief lists the start-up's numbers")
	check(not _has_part(back, "none modelled"), "fly: no remark for a value the model lacks")
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


func walk(fe: Control, file: String, lang: String) -> void:
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
	s.flown_debrief = file
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
			"1,140 מ׳",
			"5:12 דק׳",
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
			"1,140 m",
			"5:12 min",
			"172 kt",
			"PASS"
		]
	):
		check(_has(fe, t), "%s: debrief: %s" % [lang, t])
	check(_has(fe, "2.11.2026 · 08:00–08:11" if he else "2 Nov 2026 · 08:00–08:11"), "%s: debrief: the time" % lang)
	for t in (
		["הניתוק ב־13 קשר מעל המהירות המומלצת ל־13,420 ק״ג.", "ריצת ההמראה נשמרה עד 3.1 מ׳ מקו המרכז."]
		if he
		else ["Lift-off 13 kt above the reference speed for 13,420 kg.", "The roll held the centreline within 3.1 m."]
	):
		check(_has(fe, t), "%s: debrief remark: %s" % [lang, t])
	fe.find_child("BackMissions", true, false).pressed.emit()
	await frames(2)
	check(fe.page == "mission" and fe.mission_i == 1, "%s: Back to missions picks the flown take-off" % lang)
	fe.open_debrief(file)
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
	check(_labels_of(fe, "Stat").has("2"), "%s: home: two flights" % lang)
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
	fe.open_debrief(file.replace(STAMP, FAIL_STAMP))
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
	fe.show_page("prefs")
	await frames(2)
	for k in [
		"antialiasing",
		"shadows",
		"terrain_detail",
		"clouds",
		"rain",
		"night_lights",
		"language",
		"flight_controls",
		"unlimited_fuel"
	]:
		check(fe.find_child("Pref_" + k, true, false) != null, "prefs: the %s row" % k)
	check(fe.find_child("Pref_flight_data", true, false) == null, "prefs: no realism switch (flight data)")
	var aa: OptionButton = fe.find_child("Pref_antialiasing", true, false).find_child("Control", true, false)
	check(aa.get_item_text(aa.selected).begins_with("MSAA 4×"), "prefs: antialiasing is a dropdown at MSAA 4×")
	var sh: CheckButton = fe.find_child("Pref_shadows", true, false).find_child("Control", true, false)
	sh.button_pressed = false
	check(s.shadows == false, "prefs: the shadows switch sets the setting")
	sh.button_pressed = true
	var lang: OptionButton = fe.find_child("Pref_language", true, false).find_child("Control", true, false)
	lang.select(1)
	lang.item_selected.emit(1)
	await frames(2)
	check(
		s.language == "he" and fe.is_layout_rtl() and _has(fe, "הגדרות"), "prefs: Hebrew switches every string at once"
	)
	lang = fe.find_child("Pref_language", true, false).find_child("Control", true, false)
	lang.select(0)
	lang.item_selected.emit(0)
	await frames(2)
	check(s.language == "en" and not fe.is_layout_rtl() and _has(fe, "Preferences"), "prefs: and back to English")


## Writes a pilot log with two passes and the take-off's debrief record (the scorer's shape, training.md §4).
static func fixture(s: Node) -> String:
	var dir: String = s.debriefs_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("debrief-"):
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
			"tower_calls": "Tower calls"
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
			"tower_calls": "קריאות למגדל"
		},
	}
	var rec := {
		"mission": "ramon_takeoff",
		"kind": "takeoff",
		"pass": true,
		"reasons": [],
		"items": items.map(func(i): return {"id": i[0], "value": i[1], "unit": i[2]}),
		"strings": names,
		"date": "2026-11-02T08:11:00",
		"elapsed_s": 660.0,
	}
	var file := dir.path_join("debrief-%s-ramon_takeoff.json" % STAMP)
	var start := dir.path_join("debrief-20261102-075000-ramon_startup.json")
	FileAccess.open(file, FileAccess.WRITE).store_string(JSON.stringify(rec))
	var fail := rec.duplicate(true)
	fail["pass"] = false
	fail["reasons"] = ["gear_down"]
	fail["strings"]["en"]["gear_down"] = "The gear was never raised."
	fail["strings"]["he"]["gear_down"] = "כן הנסע לא נאסף."
	FileAccess.open(file.replace(STAMP, FAIL_STAMP), FileAccess.WRITE).store_string(JSON.stringify(fail))
	FileAccess.open(start, FileAccess.WRITE).store_string(
		JSON.stringify(
			{"mission": "ramon_startup", "pass": true, "items": [], "elapsed_s": 112.0, "date": "2026-11-02T07:52:00"}
		)
	)
	var log := {
		"missions":
		[
			{"id": 2012, "attempts": [{"result": 1, "debrief": file, "date": "2026-11-02T08:11:00"}]},
			{"id": 2011, "attempts": [{"result": 1, "debrief": start, "date": "2026-11-02T07:52:00"}]},
		]
	}
	var path: String = s.pilot_log_file()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(log))
	return file


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
