# The weapons in the sim's own flights (modern-iaf/docs/weapons.md §5), headless, for each jet: its take-off mission
# set up as the front end's Fly does (fly.gd prepare) with the pilot's loadout from the Arming page (bombs on their
# stations), then the jet put in the air 1,500 m above the ground at 200 m/s, the flight model flying:
# - the stores page (the F-16s' SMS, the F-35I's SMS portal) shows the Arming page's bombs on their stations;
# - "[" selects the bombs (the CCIP HUD mode, the SMS's A-G page with the same weapon), safe: no RDY; Shift+A arms
#   (RDY, ARM), ST STA is up once the avionics are;
# - Space held releases: the bomb exists, falls over a kilometre and is gone at the terrain (its burst); the SMS's
#   counts go down; Shift+C jettisons the rest (the F-16s' tanks first) and the stations empty;
# - "]" selects the missiles; Space launches one: it leaves the jet and flies away from it;
# - Tab fires the gun: the rounds count down.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_weapons_flight.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Mission, jet, the bomb hung on a station and its mirror on the Arming page, how many that makes (a TER holds three).
const JETS := [
	["ramon_takeoff", "f16i", 3, "mk-82", 6],
	["ramat_david_takeoff", "f16d", 3, "mk-82", 6],
	["nevatim_takeoff", "f35i", 4, "gbu-31", 2],
]

var fly_gd
var out := ""


func _press(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = DirAccess.create_temp("modern-iaf-weapons", false).get_current_dir()
	for j in JETS:
		await jet(j[0], j[1], j[2], j[3], j[4])


func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true


func jet(mission: String, unit: String, station: int, bomb: String, count: int) -> void:
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	IafPilotLog.set_loadout(db, s.pilot(), unit, IafBriefing.put(rec, "", station, bomb, true))
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == mission:
			id = int(k)
	check(fly_gd.prepare(id), "%s: mission %d prepared as the front end's Fly" % [unit, id])
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = out
	# As after the take-off's pass: the training run checks no more and the flight goes on (sim_flight.gd _finish).
	tv.addon.result = {"pass": true}
	var w = tv.weapons
	var bombs := 0
	for i in 9:
		if w.stores.type_of(i) == 500 or w.stores.type_of(i) == 650:
			bombs += w.stores.displayed(i)
	check(bombs == count, "%s: the Arming page's %d %s are on the jet (%d)" % [unit, count, bomb, bombs])
	# In the air, the engine and the avionics up (an airborne start), gear up.
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 1500.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 200.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.9
	tv.brakes = false
	await frames(10)
	var wp: Dictionary = tv.cockpit.weapons
	var name := bomb.to_upper()
	check(
		_on(wp, 2) == [name, int(count * 0.5)] and _on(wp, 6) == [name, int(count * 0.5)],
		"%s: the stores page's stations 2 / 6 hold %s (%s, %s)" % [unit, name, _on(wp, 2), _on(wp, 6)]
	)
	check(not w.master_arm and not bool(wp.armed), "%s: the master arm starts safe" % unit)
	_press(tv, KEY_BRACKETLEFT)
	await frames(3)
	var t: int = w.stores.current_type()
	wp = tv.cockpit.weapons
	check(
		t in [500, 650] and w.hud_mode in [5, 6] and String(wp.name) == w.stores.current_name(),
		"%s: '[' selects %s, CCIP (HUD mode %d), the same weapon on the SMS" % [unit, wp.name, w.hud_mode]
	)
	check(_sms_shown(tv), "%s: the stores page is up" % unit)
	check(_status(tv) == "", "%s: safe: the SMS shows no RDY (%s)" % [unit, _status(tv)])
	_press(tv, KEY_A, true, true)
	await frames(3)
	check(w.master_arm and bool(tv.cockpit.weapons.armed), "%s: Shift+A arms, the SMS shows it" % unit)
	check(w._up("st_sta") and bool(tv.cockpit.weapons.stores_power), "%s: ST STA up with the avionics" % unit)
	check(_status(tv) == "RDY", "%s: armed: RDY (%s)" % [unit, _status(tv)])
	var before: int = w.stores.total(t, w.stores.current_name())
	_press(tv, KEY_SPACE)
	var left := await _until(tv, func(): return w.stores.total(t, w.stores.current_name()) < before, 30.0)
	_press(tv, KEY_SPACE, false)
	check(left, "%s: Space releases a %s (%d left)" % [unit, bomb, w.stores.total(t, w.stores.current_name())])
	await frames(2)
	wp = tv.cockpit.weapons
	check(
		int(wp.total) == w.stores.total(t, w.stores.current_name()) and _on(wp, 2)[1] + _on(wp, 6)[1] == int(wp.total),
		"%s: the SMS counts the release (%d left: %s, %s)" % [unit, wp.total, _on(wp, 2), _on(wp, 6)]
	)
	var falling: Array = w.bombs + w.gps_bombs
	check(falling.size() >= 1 and falling[0].node != null, "%s: the bomb exists and is drawn" % unit)
	# Its last place before it is gone: the burst (player_weapons.gd _bomb_detonate at IafBomb.check's ground hit).
	var y0: float = falling[0].node.global_position.y if not falling.is_empty() else 0.0
	var last := Vector3.ZERO
	var t0: float = tv._sim_time
	while not (w.bombs.is_empty() and w.gps_bombs.is_empty()) and tv._sim_time - t0 < 60.0:
		var live: Array = w.bombs + w.gps_bombs
		if not live.is_empty() and live[0].node != null:
			last = live[0].node.global_position
		await process_frame
	check(w.bombs.is_empty() and w.gps_bombs.is_empty(), "%s: the bomb fell and burst" % unit)
	var ground = tv.terrain.height_at(last)
	check(
		ground != null and last.y - float(ground) < 60.0 and y0 - last.y > 1000.0,
		(
			"%s: it fell %.0f m and burst at the terrain (%.0f m above it at the last frame)"
			% [unit, y0 - last.y, last.y - float(ground)]
		)
	)
	# Shift+C: the F-16s' tanks first, then the bombs left; the stations empty on the page.
	var tanks := range(9).filter(func(i): return w.stores.type_of(i) == 660 and w.stores.displayed(i) > 0)
	for k in 2:
		_press(tv, KEY_C, true, true)
		await frames(3)
	wp = tv.cockpit.weapons
	check(
		_on(wp, 2)[1] == 0 and _on(wp, 6)[1] == 0 and tanks.all(func(i): return int(wp.stations[i].count) == 0),
		"%s: jettison empties the bomb stations and the tanks %s on the SMS" % [unit, tanks]
	)
	# A missile off the rail.
	_press(tv, KEY_BRACKETRIGHT)
	var mt: int = w.stores.current_type()
	check(mt in [570, 580, 590, 600, 610], "%s: ']' selects %s" % [unit, w.stores.current_name()])
	var n0: int = w.missiles.size()
	var m0: int = w.stores.total(mt, w.stores.current_name())
	_press(tv, KEY_SPACE)
	await frames(3)
	_press(tv, KEY_SPACE, false)
	# A missile in a bay waits for the doors (player_weapons.gd _bay_wait), then leaves by itself.
	await _until(tv, func(): return w.missiles.size() > n0, 3.0)
	check(
		w.missiles.size() > n0 and w.stores.total(mt, w.stores.current_name()) == m0 - 1,
		"%s: Space launches a %s (HUD mode %d)" % [unit, w.stores.current_name(), w.hud_mode]
	)
	var mis = w.last_launched
	var away := func(): return mis != null and mis.position(w.now).distance_to(w.own().pos) > 100.0
	check(await _until(tv, away, 4.0), "%s: the missile flies away from the jet" % unit)
	# The gun.
	var r0: int = w.stores.displayed(9)
	_press(tv, KEY_TAB)
	await _until(tv, func(): return w.stores.displayed(9) < r0, 2.0)
	_press(tv, KEY_TAB, false)
	check(w.stores.displayed(9) < r0, "%s: Tab fires the gun (%d → %d rounds)" % [unit, r0, w.stores.displayed(9)])


## Station `i` on the stores page: [store name, count] ("" and 0 when empty).
func _on(wp: Dictionary, i: int) -> Array:
	var st: Dictionary = wp.stations[i]
	return [String(st.name) if int(st.count) > 0 else "", int(st.count)]


## The stores page is up: an F-16 MFD showing its SMS format, the F-35I's panoramic display holding its SMS portal.
func _sms_shown(tv: Node) -> bool:
	var c: Node = tv.cockpit
	if c.pcd != null:
		return "SMS" in c.pcd.main
	return c.mfds.any(func(m): return m.real != null and String(m.real.state().shown) == "SMS")


## The weapon's status the stores page shows: the F-16 SMS's RDY / MAL / blank (f16_mfd.gd), the F-35I's ARM / SAFE
## line over the weapon with its RDY colour, from the state pcd_formats.gd sms draws them from (armed, ready).
func _status(tv: Node) -> String:
	var c: Node = tv.cockpit
	var wp: Dictionary = c.weapons
	if c.pcd != null:
		return "RDY" if bool(wp.get("armed", false)) and bool(wp.get("ready", true)) else ""
	for m in c.mfds:
		if m.real != null and m.real_fmt != null:
			return String(m.real_fmt._status(wp))
	return "?"
