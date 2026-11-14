# Dev helper (not run by tools/test.sh): the weapons in a real render, flown as a player (modern-iaf/docs/weapons.md
# §5).
# For each jet: the front end (the Hangar's jet, its take-off mission, two bombs hung on the Arming page, Fly), the
# start-up, the tower calls, the taxi and the take-off (test_mvp.gd's), a climb, then Shift+A, "[", Space: the bombs
# leave (chase view), fall and burst on the ground (the weapon's view), "]" and Space: a missile off the rail, Tab: the
# gun. The Sufa's flight also shows the HUD's CCIP cue and the notebook's WEAPONS tab in English and Hebrew.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> [SHOW_ONLY=f35i] -- --log-file <temp> \
#     --resolution 2560x1440 --path modern-iaf -s ../modern-iaf/tests/_weapons_shot.gd
extends "res://tests/test_mvp.gd"

## airframe id -> [unit, the bomb hung on a station and its mirror]
const ARM := {"f16i": ["f16i", 3, "mk-82"], "f16": ["f16d", 3, "mk-82"], "f35i": ["f35i", 4, "gbu-31"]}
## The climb's top above the field (m), and the level flight's pitch hold.
const TOP_M := 1400.0

var shots := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	shots = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-weapons-shots-%d" % OS.get_process_id())
	var s := settings()
	s.show_info = false
	load("res://tests/test_front_end.gd").fixture(s)
	s.pilot_name = "Noa Golan"
	var only := OS.get_environment("SHOW_ONLY")
	for id in JETS:
		if only == "" or only == id:
			await jet_flight(id)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var p := shots.path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _shift(tv: Node, k: Key, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = true
	e.pressed = down
	tv._unhandled_input(e)


func _key(tv: Node, k: Key, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	tv._unhandled_input(e)


## The front end as a player: the jet, its take-off mission's Arming page with the bombs, Fly; the flight scene.
func _from_front_end(id: String) -> Node:
	var s := settings()
	var unit: String = ARM[id][0]
	s.sim_jet = unit
	s.set_jet(id)
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	IafPilotLog.set_loadout(s.records_db(), s.pilot(), unit, IafBriefing.put(rec, "", ARM[id][1], ARM[id][2], true))
	change_scene_to_file("res://main.tscn")
	await frames(5)
	var fe: Control = current_scene
	fe.show_page("mission")
	await frames(3)
	var list: Array = fe.jet_missions(unit)
	fe._pick_mission(list.map(func(m): return str(m.id)).find(JETS[id][1] + "_takeoff"))
	fe.show_tab(2)
	await frames(10)
	await _shot("arming_%s" % unit)
	fe.find_child("Fly", true, false).pressed.emit()
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene if current_scene != null and current_scene.has_method("mission_ground") else null
	IafPilotLog.set_loadout(s.records_db(), s.pilot(), unit, "")
	tv.addon.out_dir = out
	return tv


func jet_flight(id: String) -> void:
	var unit: String = ARM[id][0]
	var tv := await _from_front_end(id)
	Engine.time_scale = TIME_SCALE
	await _call(tv, "startup")
	_press(tv, KEY_E, true)
	await _until(tv, func(): return tv.flight.state().engine_on and tv.flight.state().avionics, 180.0)
	await _call(tv, "taxi")
	var s: Dictionary = settings().load_ibx(settings().own_dir().path_join("iaf.ibx"))[JETS[id][2]]
	var path: Array = []
	for i in int(s.TaxiWayPtsFrom):
		path.append(Vector2(float(s["FromTaxiPtX%d" % i]), float(s["FromTaxiPtY%d" % i])))
	var hdg := float(s.RunwayNumber)
	tv.brakes = false
	tv.scripted_stick = Vector2.ZERO
	await _taxi(tv, path.slice(0, -1), hdg, false)
	await _call(tv, "lineup")
	await _taxi(tv, [path[-1]], hdg)
	await _call(tv, "takeoff")
	await _roll(tv, id, path[-1], hdg)
	print("%s take-off: %s" % [unit, tv.addon.result])
	# The climb to TOP_M above the field, then level on the runway heading.
	var field: float = tv.player_world().z
	while tv.player_world().z < field + TOP_M and not tv.crashed:
		_hold(tv, 10.0, hdg)
		await process_frame
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 8.0:
		_hold(tv, 0.0, hdg)
		await process_frame
	Engine.time_scale = 1.0
	tv.throttle = 0.85
	tv._throttle_event()
	var w = tv.weapons
	# The stores page: the bombs selected while safe, then armed.
	_key(tv, KEY_BRACKETLEFT)
	await _sms_shot(tv, "sms_safe_%s" % unit)
	_shift(tv, KEY_A)
	await _sms_shot(tv, "sms_armed_%s" % unit)
	# A shallow dive: the CCIP pipper comes up into the HUD.
	t0 = tv._sim_time
	while tv._sim_time - t0 < 4.0:
		_hold(tv, -20.0, hdg)
		await process_frame
	if unit == "f16i":
		tv.views.set_cockpit(tv.views.COCKPIT)
		tv.in_cockpit = true
		tv._apply_view()
		tv.views.snap = Vector2.ZERO
		await fly(tv, 0.5)
		await _shot("hud_ccip_%s" % unit)
	tv.views.snap = null
	# F9 the fly-by view (the camera beside the path ahead); the F-35I's bombs from the chase view, F10, close behind.
	tv._command([28, 6, 0] if tv.cockpit.pcd != null else [28, 19, 0])
	await fly(tv, 0.3)
	var t: int = w.stores.current_type()
	var n0: int = w.stores.total(t, w.stores.current_name())
	_key(tv, KEY_SPACE)
	t0 = tv._sim_time
	while w.stores.total(t, w.stores.current_name()) == n0 and tv._sim_time - t0 < 20.0:
		_hold(tv, -20.0, hdg)
		await process_frame
	_key(tv, KEY_SPACE, false)
	print("%s: one press released %d" % [unit, n0 - w.stores.total(t, w.stores.current_name())])
	# The F-35I's bombs leave its bays: taken while the doors are open and the bombs just below.
	await fly(tv, 0.3 if tv.cockpit.pcd != null else 1.0)
	print("%s: then %d released" % [unit, n0 - w.stores.total(t, w.stores.current_name())])
	await _shot("bombs_away_%s" % unit)
	tv._command([28, 6, 0])  # F10: the chase view
	await fly(tv, 0.6)
	await _shot("bombs_falling_%s" % unit)
	tv._command([28, 27, 0])  # F11: the view from the weapon
	var low := false
	while not (w.bombs.is_empty() and w.gps_bombs.is_empty()):
		_hold(tv, 5.0, hdg)
		var live: Array = w.bombs + w.gps_bombs
		if not low and not live.is_empty() and live[0].node != null:
			var g = tv.terrain.height_at(live[0].node.global_position)
			low = g != null and live[0].node.global_position.y - float(g) < 25.0
		await process_frame
	await fly(tv, 0.35)
	await _shot("hit_%s" % unit)
	await fly(tv, 1.5)
	await _shot("hit_after_%s" % unit)
	await _sms_shot(tv, "sms_released_%s" % unit)
	# A missile off the rail, from the chase view; the gun.
	tv._command([28, 6, 0])
	t0 = tv._sim_time
	while tv._sim_time - t0 < 3.0:
		_hold(tv, 3.0, hdg)
		await process_frame
	_key(tv, KEY_BRACKETRIGHT)
	var m0: int = w.missiles.size()
	_key(tv, KEY_SPACE)
	await frames(3)
	_key(tv, KEY_SPACE, false)
	await _until(tv, func(): return w.missiles.size() > m0, 3.0)
	await fly(tv, 0.5)
	await _shot("missile_%s" % unit)
	_key(tv, KEY_TAB)
	await fly(tv, 0.6)
	await _shot("gun_%s" % unit)
	_key(tv, KEY_TAB, false)
	if unit == "f16i":
		await _notebook(tv)
	print(
		(
			"%s: bombs %d -> %d, missiles fired %d, rounds %d"
			% [unit, n0, w.stores.total(t, w.stores.current_name()), w.missiles.size(), w.stores.displayed(9)]
		)
	)


## The cockpit view turned down to the stores page (the F-16s' right MFD, the F-35I's panoramic display), then back to
## the chase view.
func _sms_shot(tv: Node, name: String) -> void:
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = Vector2(0.0 if tv.cockpit.pcd != null else deg_to_rad(-16.0), deg_to_rad(-30.0))
	await fly(tv, 0.6)
	await _shot(name)
	tv.views.snap = null
	tv._command([28, 6, 0])


## Pitch `pitch` (deg) on heading `hdg` by the scripted stick (as test_mvp.gd's climb-out).
func _hold(tv: Node, pitch: float, hdg: float) -> void:
	var st: Dictionary = tv.flight.state()
	var herr := wrapf(hdg - float(st.heading), -180.0, 180.0)
	var pitch_cmd := clampf((pitch - float(st.pitch)) * 0.05, -0.4, 0.5)
	var roll_cmd := clampf((clampf(herr * 2.0, -15.0, 15.0) - float(st.roll)) * 0.03, -0.5, 0.5)
	tv.scripted_stick = Vector2(roll_cmd, pitch_cmd)


## The notebook raised (H) at its WEAPONS tab, English then Hebrew, from the cockpit.
func _notebook(tv: Node) -> void:
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = Vector2.ZERO
	var kb: Node = tv.addon.kneeboard
	for lang in ["en", "he"]:
		settings().language = lang
		if not kb.raised:
			kb.set_raised(true)
		kb.refresh()
		kb.board.open("weapons")
		await fly(tv, 0.6)
		await _shot("notebook_weapons_%s" % lang)
	settings().language = "en"
