# The stores' release limits, jettisons and the F-35I's bay doors in the sim (finish list W17, W18, W22;
# docs/real-weapons.md §1.11, modern-iaf/docs/weapons.md §5.1). Each jet's take-off mission set up as the front end's
# Fly does, put in the air 1,500 m above the ground, hands off.
# - W17, the Sufa: a Mk 82 release is allowed level at 200 m/s there and refused at 360 m/s (over the 600 KCAS of
#   T.O. 1-1M-34; the dive limit: release.rs real_release_limits, as the 6-DoF starts level).
# - W18, the Sufa with a TER-9/A of three Mk 82 on 3 / 7, the default 370 US gal tanks on 4 / 6 and AIM-9Ms: the SMS's
#   S-J and Space (selective jettison) drop the six bombs with their racks: the 6-DoF's mass falls by the bombs' and
#   racks' kg, the drag index by theirs, the tanks and missiles stay, the bombs fall unarmed (no burst). Then Shift+C
#   (emergency jettison) drops the tanks in one press: the mass falls by their empty 201 kg each plus the fuel above
#   the internal, the fuel is the internal, the drag index loses the tanks', the four AIM-9M stay.
# - W22, the F-35I with a GBU-31 in each bay: Shift+C opens the doors; the bombs leave once they are open (0.47 s),
#   the open doors add their drag index (50) to the 6-DoF's, the doors are shut again within 2 s of the press.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_jettison.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func _press(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true


## The mission `mission` flown by `unit` with loadout `lo` (IafBriefing JSON), in the air at `speed` m/s, armed.
func _fly(mission: String, unit: String, lo: String, speed := 200.0) -> Node:
	var s := settings()
	var db: String = s.records_db()
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var list: Dictionary = s.load_json(s.converted(s.missions_folder().path_join("missionlist.json")))
	var id := -1
	for k in list:
		if str(list[k][0]) == mission:
			id = int(k)
	check(load("res://flight/fly.gd").prepare(id), "%s prepared as the front end's Fly" % mission)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.result = {"pass": true}  # the training run checks no more (sim_flight.gd _finish)
	_restart(tv, speed)
	tv.gear_down = false
	tv.throttle = 0.8
	tv.brakes = false
	tv.flight.set_switch("parking_brake", 0)  # a ground start is held by it
	await frames(10)
	tv.weapons._push_stores()  # the restart dropped the stores the mission's start gave the flight model
	_press(tv, KEY_A, true, true)  # master arm
	await frames(3)
	return tv


## The jet restarted level 1,500 m above the ground at `speed` m/s (the 6-DoF starts level, SixDof::start).
func _restart(tv: Node, speed: float) -> void:
	var s := settings()
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 1500.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	var vel: Vector3 = (st0.forward * Vector3(1, 0, 1)).normalized() * speed
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), vel, airborne_flags())
	tv.flight.set_fuel_capacity(tv.weapons.stores.tank_fuel)  # the start's tank fuel (player_weapons.gd setup)


func _record(id: String) -> Dictionary:
	return settings().load_json(ProjectSettings.globalize_path("res://data/db/weapons/%s.json" % id))


func run() -> void:
	await require_data()
	await sufa()
	await adir()


func sufa() -> void:
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	var tv: Node = await _fly("ramon_takeoff", "f16i", IafBriefing.put(rec, "", 3, "mk-82", true))
	var w = tv.weapons
	var bombs := range(9).filter(func(i): return w.stores.type_of(i) == 500 and w.stores.displayed(i) > 0)
	var tanks := range(9).filter(func(i): return "LB" in w.stores.name_of(i) and w.stores.displayed(i) > 0)
	var aam := range(9).filter(func(i): return w.stores.type_of(i) in w.AA_TYPES and w.stores.displayed(i) > 0)
	check(
		bombs.size() == 2 and tanks.size() == 2 and aam.size() == 4,
		"the Sufa: Mk 82 on %s, tanks on %s, AIM-9M on %s" % [bombs, tanks, aam]
	)
	# W17: the release limits (release.rs real_release_allowed), through the flight model's state.
	_press(tv, KEY_BRACKETLEFT)
	await frames(3)
	check(w.release_allowed(500), "W17: level at 200 m/s, 1,500 m: a Mk 82 may leave")
	_restart(tv, 360.0)
	await frames(3)
	var st: Dictionary = tv.flight.state()
	check(
		not w.release_allowed(500),
		"W17: %.0f m/s at %.0f ft (over 600 KCAS): refused" % [float(st.speed), float(st.alt_ft)]
	)
	_restart(tv, 200.0)
	await frames(10)
	w._push_stores()
	await frames(2)
	# W18, selective jettison: S-J on the SMS (player_weapons.gd mfd_event -2), then Space.
	var mk82 := _record("mk-82")
	var rack_kg: float = w.stores.station(bombs[0]).rack_kg
	var rack_drag: float = w.stores.station(bombs[0]).rack_drag
	check(absf(rack_kg - 47.6) < 0.01, "the TER-9/A weighs %.1f kg (47.6, Marvin Engineering)" % rack_kg)
	var m0: float = tv.flight.state().mass_kg
	var di0: float = w.stores.fm_di_left + w.stores.fm_di_right
	var n0: int = w.bombs.size()
	w.mfd_event(-2)
	check(w.sel_jett, "S-J: the selective jettison page up")
	_press(tv, KEY_SPACE)
	await frames(3)
	_press(tv, KEY_SPACE, false)
	var m1: float = tv.flight.state().mass_kg
	var di1: float = w.stores.fm_di_left + w.stores.fm_di_right
	var dm: float = m0 - m1
	var want_m: float = 6 * float(mk82.kg) + 2 * rack_kg
	check(
		bombs.all(func(i): return w.stores.displayed(i) == 0) and absf(dm - want_m) < 2.0,
		"W18 S-J: six Mk 82 and two TER-9/A leave: mass −%.1f kg (want %.1f)" % [dm, want_m]
	)
	var want_di: float = (6 * float(mk82.drag) + 2 * rack_drag) * 1e-4
	check(
		absf(di0 - di1 - want_di) < 1e-6, "W18 S-J: drag index −%.1f (want %.1f)" % [(di0 - di1) * 1e4, want_di * 1e4]
	)
	var dropped: Array = w.bombs.slice(n0)
	check(dropped.size() == 6 and dropped.all(func(b): return b.get("safe", false)), "W18: the six fall unarmed")
	check(
		tanks.all(func(i): return w.stores.displayed(i) == 1) and aam.all(func(i): return w.stores.displayed(i) == 1),
		"W18 S-J: the tanks and the missiles stay"
	)
	w.mfd_event(-2)
	check(not w.sel_jett, "S-J again: the page down")
	# W18, emergency jettison (Shift+C): the tanks in one press, their fuel with them.
	var tank := _record("tank-370")
	var st1: Dictionary = tv.flight.state()
	var fuel0: float = float(st1.fuel_lbs) * 0.45359
	var internal: float = float(st1.internal_fuel_kg)
	check(fuel0 > internal + 500.0, "the tanks hold fuel: %.0f kg against %.0f internal" % [fuel0, internal])
	m1 = float(st1.mass_kg)
	di1 = w.stores.fm_di_left + w.stores.fm_di_right
	_press(tv, KEY_C, true, true)
	await frames(3)
	var st2: Dictionary = tv.flight.state()
	var fuel1: float = float(st2.fuel_lbs) * 0.45359
	var want: float = 2 * float(tank.empty_kg) + fuel0 - fuel1
	check(
		tanks.all(func(i): return w.stores.displayed(i) == 0) and absf(fuel1 - internal) < 5.0,
		"W18 EMER: both tanks leave in one press, fuel %.0f → %.0f kg (internal %.0f)" % [fuel0, fuel1, internal]
	)
	check(
		absf(m1 - float(st2.mass_kg) - want) < 5.0,
		"W18 EMER: mass −%.0f kg (two empty tanks 2 × 201 + the fuel: %.0f)" % [m1 - float(st2.mass_kg), want]
	)
	var di2: float = w.stores.fm_di_left + w.stores.fm_di_right
	check(
		absf(di1 - di2 - 2 * float(tank.drag) * 1e-4) < 1e-6,
		"W18 EMER: drag index −%.1f (two tanks: %.1f)" % [(di1 - di2) * 1e4, 2 * float(tank.drag)]
	)
	check(aam.all(func(i): return w.stores.displayed(i) == 1), "W18 EMER: the four AIM-9M stay")


func adir() -> void:
	var rec := ProjectSettings.globalize_path("res://data/db/units/f35i.json")
	var tv: Node = await _fly("nevatim_takeoff", "f35i", IafBriefing.put(rec, "", 4, "gbu-31", true))
	var w = tv.weapons
	var bays := range(9).filter(func(i): return w._internal(i) and w.stores.type_of(i) == 650)
	bays = bays.filter(func(i): return w.stores.displayed(i) > 0)
	check(bays.size() == 2, "the F-35I: a GBU-31 in each bay (%s)" % [bays])
	check(w._bay_pushed == 0.0 and tv.aircraft.bay_fraction() == 0.0, "W22: the doors shut, no door drag")
	var t0: float = tv._sim_time
	_press(tv, KEY_C, true, true)
	await _until(tv, func(): return tv.aircraft.bay_fraction() > 0.3, 1.0)
	check(
		bays.all(func(i): return w.stores.displayed(i) == 1) and w._bay_pushed > 0.0,
		(
			"W22: the doors opening (%.2f), the bombs still in, door drag %.1f"
			% [w._bay_pushed, w._bay_pushed * w.BAY_DRAG]
		)
	)
	await _until(tv, func(): return bays.all(func(i): return w.stores.displayed(i) == 0), 2.0)
	var t_out: float = tv._sim_time - t0
	check(
		bays.all(func(i): return w.stores.displayed(i) == 0) and absf(t_out - 0.47) < 0.15,
		"W22: the bombs leave %.2f s after the press (the doors' 0.47 s)" % t_out
	)
	check(is_equal_approx(w._bay_pushed, 1.0), "W22: the doors open, their drag index %.0f (50)" % (w._bay_pushed * 50))
	await _until(tv, func(): return tv.aircraft.bay_fraction() == 0.0, 3.0)
	var t_shut: float = tv._sim_time - t0
	await frames(2)
	check(
		t_shut < 2.0 and w._bay_pushed == 0.0,
		"W22: the doors shut %.2f s after the press (under 2 s), the door drag gone" % t_shut
	)
