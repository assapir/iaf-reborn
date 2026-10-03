# Player weapons (docs/weapons.md): the data layer (weapon database, stores weight / drag, Real
# weapon data), the gun round trajectory and hit sphere, and in mission 231 the gun hitting a unit,
# an IR missile locking, launching, guiding and hitting, the stores leaving the pylons and the flight
# model's mass changing. The flight model is frozen; the weapons run on a scripted sim time.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var MR = load("res://mission/mission_runtime.gd")
	var bdb: Dictionary = MR.load_bdb(MR.mission_files(231)[0].data)
	var objs: Dictionary = MR.bdb_objects(bdb)
	var f16: Dictionary = objs[1]
	var desc: Dictionary = load("res://aircraft/aircraft_model.gd").load_descriptor("f16")
	var Db = load("res://weapons/weapon_db.gd")
	var Stores = load("res://weapons/stores.gd")

	# --- data ---------------------------------------------------------------------------------
	var db = Db.create(bdb, false)
	check(db.by_id(11).name == "AIM-9L" and db.by_id(11).generation == 3, "bdb weapon 11 = AIM-9L, generation 3")
	check(db.motion_for(570, 3).get("_absAcceleration") == 100.0 and db.motion_for(565, 0).get("_spiralAccel") == 50.0,
		"weapons.ibx: AIM-9L acceleration 100, gun hit distance 50")
	var st = Stores.new()
	st.setup(Stores.loadout({}, f16), db, desc, Callable(), 100)
	check(st.displayed(9) == 940, "F-16 gun: 235 x 4 = 940 rounds shown")
	check(is_equal_approx(st.fm_mass, 192 + 192 + 346 + 346 + 1040 + 1040 + 2020 + 2020), "original stores weight: one store per pylon, pounds in the kg field")
	check(is_equal_approx(st.fm_di_left, 0.0108) and is_equal_approx(st.fm_di_right, 0.0108), "stores drag index per side")
	var fix = Stores.new()
	fix.weight_fix = true
	fix.setup(Stores.loadout({}, f16), db, desc, Callable(), 100)
	check(is_equal_approx(fix.fm_mass, (192 * 2 + 346 * 2 + 1040 * 6 + 2020 * 2) * 0.45359), "Stores weight fix: every store, in kg")
	st.cycle(1)
	check(st.current_name() == "AMRAAM", "']' from AIM-9L: next AA weapon AMRAAM")
	st.cycle(1)
	st.cycle(1)
	check(st.cur == 9, "the gun is in the AA cycle")
	var tank = Stores.new()
	tank.setup([[11, 1], [0, 0], [0, 0], [0, 0], [28, 1], [0, 0], [0, 0], [0, 0], [11, 1], [25, 235], [33, 90], [34, 60]], db, desc, Callable(), 100)
	check(tank.has_tank and is_equal_approx(tank.tank_fuel, 2700.0) and is_equal_approx(tank.fm_mass, 384.0), "tank: its 2700 goes to the fuel (lb as kg), not the stores weight")
	var real = Db.create(bdb, true)
	check(absf(real.by_id(11).weight_lb * 0.45359 - 86.0) < 0.01, "Weapon data Real: AIM-9L 86 kg")
	var m9: Dictionary = real.by_id(11).motion
	check(absf(100.0 / m9._spiralAccelBeta - 2.5 * 340.3) < 0.1 and absf((m9.burn + 6.0) * 2.5 * 340.3 - 35400.0) < 1.0,
		"Real AIM-9L chase: top speed Mach 2.5, range 35.4 km")
	var by_name := {}
	for id in real.weapons:
		by_name[real.weapons[id].name] = real.weapons[id]
	check(by_name.has("AIM-9D") and by_name["AIM-9D"].get("real_rear", false) and by_name["AIM-9D"].get("real_max_g", 0.0) == 12.0
		and by_name["PYTH-4"].get("real_cone_deg", 0.0) == 60.0, "Real flags: AIM-9D rear-aspect 12 g, Python 4 cone 60°")
	var sk = load("res://weapons/ir_seeker.gd").new()
	sk.set_weapon(by_name["AIM-9D"])
	var me := {"pos": Vector3.ZERO, "yaw": 0.0}
	check(sk.can_track(me, {"pos": Vector3(0, 2000, 0), "vel": Vector3(0, 200, 0)}, 570)
		and not sk.can_track(me, {"pos": Vector3(0, 2000, 0), "vel": Vector3(0, -200, 0)}, 570), "Real AIM-9D: tail chase only")
	sk.set_weapon(db.by_id(11))
	check(not sk.rear_only and sk.can_track(me, {"pos": Vector3(0, 2000, 0), "vel": Vector3(0, -200, 0)}, 570), "original: all aspects")
	var mi = load("res://weapons/missile.gd").new()
	mi.launch(by_name["AIM-9D"], {"_absAcceleration": 300.0, "_spiralAccel": 0.0, "_timeConstOrientation": 0.0, "burn": 10.0}, 0.0, Vector3(0, 0, 1000), Vector3(0, 300, 0), Vector3(0, 1, 0), "x", Vector3.ZERO, 1.0, func(_i, d): return d)
	mi.update(0.0, Vector3(3000, 0, 1000), Vector3.ZERO, Callable())
	mi.update(0.1, Vector3(3000, 0, 1000), Vector3.ZERO, Callable())
	var lat: Vector3 = mi.acc - mi.v0.normalized() * mi.acc.dot(mi.v0.normalized())
	check(absf(lat.length() - 12.0 * 9.80665) < 0.01, "Real AIM-9D: turn limited to 12 g (%.1f m/s²)" % lat.length())
	var rst = Stores.new()
	rst.setup(Stores.loadout({}, f16), real, desc, Callable(), 100)
	check(rst.displayed(9) == 511, "Weapon data Real: F-16 gun 511 rounds")
	rst.consume(9)
	check(rst.displayed(9) == 491, "Real: one 0.2 s shot tick of the M61A1 = 20 rounds")

	# --- gun rounds (pure) ----------------------------------------------------------------------
	var G = load("res://weapons/gun_rounds.gd")
	var g = G.new()
	g.configure(db.motion_for(565, 0))
	var unit := {"key": "u", "pos": Vector3(0, 1000, 100)}
	g.units = func(): return [unit]
	g.ground = func(_p): return 0.0
	var det := []
	g.detonate = func(_r, p, c, h): det.append([p, c, h])
	var d := Vector3(0, 1, 0)
	g.fire(0.0, Vector3(0, 0, 100), Vector3(0, 0, 100), Vector3(0, 200, 0), g.aim_point(Vector3(0, 0, 100), Vector3.ZERO, d, false), "", "me", false)
	var r: Dictionary = g.pool[0]
	check(is_equal_approx(r.hit_r, 25.0), "gun hit sphere 25 m (Easy aiming off)")
	check(absf(r.t_end - (1400.0 - sqrt(1400.0 * 1400.0 - 20.0 * 2781.0)) / 10.0) < 1e-4, "round flight time to the 2781 m aim point")
	g.update(2.0)
	check(det.size() == 1 and det[0][2].get("key", "") == "u", "round hits the unit on the line")
	g.fire(3.0, Vector3(0, 0, 100), Vector3(0, 0, 100), Vector3(0, 200, 0), Vector3(0, 2781, 100), "", "me", true)
	check(is_equal_approx(g.pool[1].hit_r, 50.0), "Easy aiming: hit sphere 50 m")

	# --- in flight: mission 231 ---------------------------------------------------------------
	var tv = await start_mission(231)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true  # the rig stays where the test puts it
	tv.gear_down = false
	tv.rig.position.y += 1000.0  # in the air above the base
	var w = tv.weapons
	check(w != null and not w.stores.stations.is_empty(), "the player's stores are set up")
	var o: Dictionary = w.own()
	var mig: Dictionary = tv.runtime.entities.values().filter(func(e): return e.name == "mig23_0")[0]
	var dline: Vector3 = G.shot_dir(o.fwd, o.up)
	var tpos: Vector3 = o.pos + dline * 600.0
	mig.world = tpos
	tv.mission_entity_moved(mig)
	var t := 1.0
	w.update(t)
	w.gun_key()
	check(w.firing, "Tab: the gun fires")
	for i in 20:
		t += 0.1
		w.update(t)
	w.gun_stop()
	check(w.stores.displayed(9) < 940, "rounds used: %d left" % w.stores.displayed(9))
	check(mig.damage > 0.0 or mig.state != 1, "gun rounds damage the unit ahead (damage %.2f, state %d)" % [mig.damage, mig.state])

	# AA gun mode (']' onto the gun): the LCOS pipper settles near the gun cross in steady flight.
	w.stores.cur = 9
	w._master_from_type(true)
	for i in 40:
		t += 0.05
		w.update(t)
	check(w.hud_mode == 3 and tv.cockpit.weapons.pipper != null and tv.cockpit.weapons.pipper.length() < 20.0,
		"AA gun: LCOS pipper %s px from the gun cross" % str(tv.cockpit.weapons.pipper))
	# IR missile: select the AIM-9, the seeker locks a unit 3 km ahead, launch, it hits.
	var mig2: Dictionary = tv.runtime.entities.values().filter(func(e): return e.name == "mig23_1")[0]
	mig2.world = o.pos + o.fwd * 3000.0 + Vector3(0, 0, 30)
	tv.mission_entity_moved(mig2)
	# Only the target in front (the seeker takes any unit near the boresight, friendlies too).
	for e in tv.runtime.entities.values():
		if e != mig2 and not e.player:
			e.visible = false
	var before_mass: float = tv.flight.state().mass_kg
	var aim_station := -1
	for i in 9:
		if w.stores.type_of(i) in [570, 580]:
			aim_station = i
	check(aim_station >= 0, "an IR missile is loaded")
	w.nav_key(0)  # N: NAV (from NAV, ']' enters the selected AA missile without cycling)
	w.stores.cur = aim_station
	w.select_aa()
	check(w.hud_mode == 1, "']' with an IR missile: SRM HUD mode")
	for i in 20:
		t += 0.05
		w.update(t)
	print("seeker: ", w.seeker.target_key, " ", w.seeker.lock, " mig2 visible ", mig2.visible, " node ", mig2.node != null, " units ", w._units().map(func(u): return u.key).has(mig2.key), " gen R ", w.seeker.lock_range)
	check(w.seeker.target_key == mig2.key and w.seeker.lock, "the seeker locks the unit ahead")
	var n0: int = w.stores.total(w.stores.current_type(), w.stores.current_name())
	var drawn0 := _drawn(w)
	w.fire_selected()
	w.release_selected()
	check(w.missiles.size() == 1, "Space: missile launched")
	check(w.stores.total(w.stores.current_type(), w.stores.current_name()) == n0 - 1, "missile count -1")
	check(_drawn(w) == drawn0 - 1, "the store left its pylon")
	# The fired station is empty: in IR mode on it (FUN_0053bcd0 checks the selected station, not the weapon's
	# total) the seek tone only chirps on entry (FUN_00461b00) and the next update stops it (FUN_00461bf0).
	if float(w.stores.station(aim_station).count) == 0.0:
		var keep_t := t
		w._set_hud_mode(0)
		w.stores.cur = aim_station
		w._set_hud_mode(1)
		for i in 3:
			keep_t += 0.05
			w.seeker.update(keep_t, w.own(), w._units(), 570, w._station_has_rounds())
		check(w._seek_sound == null and w._lock_sound == null and not w.seeker.lock, "empty station: no seeker tone (chirp stopped)")
		w._set_hud_mode(0)
		w.select_aa()
	check(tv.flight.state().mass_kg < before_mass, "flight model mass dropped (%.0f -> %.0f kg)" % [before_mass, tv.flight.state().mass_kg])
	var m0 = w.missiles[0]
	for i in 300:
		t += 0.05
		w.update(t)
		if i % 10 == 0 and not w.missiles.is_empty():
			print("t %.2f pos %s v %.0f dist %.0f" % [t - 1.0, m0.position(t), m0.velocity(t).length(), m0.position(t).distance_to(tv.runtime._world_of(mig2))])
		if w.missiles.is_empty():
			print("end at ", m0.last_pos, " target ", tv.runtime._world_of(mig2), " hitground ", m0.hit_ground)
			break
	check(w.missiles.is_empty(), "the missile ended")
	check(mig2.damage > 0.0 or mig2.state != 1, "the missile hit (damage %.2f, state %d)" % [mig2.damage, mig2.state])
	# External fuel tank (docs/weapons.md "Fuel tanks"): the original adds the tank's bdb weight
	# (2700 "LB", as kg) to the fuel; the Stores weight fix adds it in kg. The external part burns
	# first; the jettison drops the tank and the fuel above FuelWeight.
	var tank_load := {"armament": {"hardpoints": [11, 1, 0, 0, 0, 0, 0, 0, 28, 1, 0, 0, 0, 0, 0, 0, 11, 1, 25, 235, 33, 90, 34, 60]}}
	var internal: float = tv.flight.state().internal_fuel_kg
	for fixed in [false, true]:
		Settings().better["fix_stores_weight"] = fixed
		var w2 = load("res://weapons/player_weapons.gd").new()
		tv.add_child(w2)
		w2.setup(tv, tank_load, f16, bdb, desc)
		var want: float = internal + (2700.0 * 0.45359 if fixed else 2700.0)
		var fuel0: float = tv.flight.state().fuel_lbs * 0.45359
		check(absf(fuel0 - want) < 1.0, "%s: fuel with a 2700LB tank %.0f kg (internal %.0f)" % ["fix" if fixed else "original", fuel0, internal])
		if fixed:
			tv.flight.set_engine_on(true)
			tv.flight.set_controls(0, 0, 0, 1.0, 0, false, false)
			for k in 20:
				tv.flight.step(0.25)
			var fuel1: float = tv.flight.state().fuel_lbs * 0.45359
			check(fuel1 < fuel0 and fuel1 > internal, "burn drains the tank first (%.0f kg)" % fuel1)
			var di0: float = w2.stores.fm_di_right
			w2.jettison()
			check(absf(tv.flight.state().fuel_lbs * 0.45359 - internal) < 1.0, "jettison: the tank's fuel is gone")
			check(w2.stores.fm_di_right < di0 and w2.stores.displayed(4) == 0, "jettison: the tank left station E, drag dropped")
		w2.queue_free()
	Settings().better["fix_stores_weight"] = false
	# Chaff / flares (Insert / Delete, events 0x44 / 0x45): one decoy per press from stations 10 / 11,
	# behind the jet, gone 4 s later; refused with the gear handle down.
	var ch0: int = w.stores.displayed(10)
	var fl0: int = w.stores.displayed(11)
	check(ch0 == 90 and fl0 == 60, "F-16: 90 chaff, 60 flares")
	check(w.dispense(550) and w.dispense(540), "flare and chaff released")
	check(w.stores.displayed(11) == fl0 - 1 and w.stores.displayed(10) == ch0 - 1, "counts -1")
	var own0: Dictionary = w.own()
	t += 1.0
	w.update(t)
	check(tv.cockpit.weapons.get("flares", -1) == fl0 - 1, "panel counter fed")
	var fl: Dictionary = w.decoys.filter(func(d): return d.type == 550)[0]
	var behind: float = (w.decoy_position(fl) - own0.pos).dot(own0.fwd)
	# The test jet is held still: the flare leaves at |V| + 10 m/s toward the point 200 m aft.
	check(behind < -5.0, "the flare goes aft (%.0f m along the nose)" % behind)
	# The look (decoy_fx.gd): the flare sprite at the decoy, chaff bursts along the decoy path.
	var fx = w.decoy_fx
	var ch: Dictionary = w.decoys.filter(func(d): return d.type == 540)[0]
	check(fx.counts(t).flares == 1 and fx.counts(t).chaff > 0, "a flare sprite and chaff pieces drawn (%s)" % fx.counts(t))
	check(fx._flares[fl].node.position.distance_to(w.to_scene(w.decoy_position(fl))) < 0.01, "the flare sprite is at the decoy")
	var on_path := true
	for b in fx.bursts:
		on_path = on_path and b[1].distance_to(w.to_scene(w._decoy_motion[540].position(ch.r, b[0]))) < 0.01
	check(fx.bursts.size() >= 30 and on_path, "chaff bursts at 30 Hz along the decoy path (%d)" % fx.bursts.size())
	# The jet is still: |V| + 10 m/s decelerating to 5 m/s never reaches A within 4 s -> ends at 4 s.
	check(is_equal_approx(fl.end, fl.r.t0 + 4.0), "end = min(time to A, 4 s)")
	t += 3.5
	w.update(t)
	check(w.decoys.is_empty(), "decoys end after 4 s")
	check(fx.counts(t).flares == 0 and fx.counts(t).chaff > 0, "flare gone, the chaff still falls")
	t += 3.3
	w.update(t)
	check(fx.counts(t).chaff == 0, "the last chaff pieces end 3 s (+ delay) after the decoy")
	tv.gear_down = true
	check(not w.dispense(550), "no flares with the gear handle down")
	tv.gear_down = false
	# M cycles the master modes: AA -> AG -> NAV.
	w.master_key()
	w.master_key()
	check(w.hud_mode == 0 and w.master == 0 or w.m_cycle == 2, "M cycles the master modes")
	await frames(3)


func _drawn(w) -> int:
	var n := 0
	for i in w._store_nodes:
		for node in w._store_nodes[i]:
			if node.visible:
				n += 1
	return n
