# The player's aircraft per type (aircraft/player_aircraft.gd, docs/aircraft.md §5): the Jet list's F-4 2000
# (aircraft id 3 -> type 200) flies with its own model (f42000), flight-model section ([F-4]), cockpit
# (cockpits.ibx index 2 -> f4-2000, with its round fuel / vario gauges and second-engine needles), twin-engine
# damage rows and weapons; its Real flight data set applies (docs/real-aircraft.md §4); gear, flaps, speed brake,
# afterburner and drag chute work on its model and cockpit; without a pick the mission's jet (the F-16 in 311)
# flies as before.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var PlayerAircraft = load("res://aircraft/player_aircraft.gd")
	var p: Dictionary = PlayerAircraft.profile(200)
	check(p.plane == "f42000" and p.fm_section == "F-4" and p.cockpit_dir.ends_with("/f4-2000") and p.twin,
			"profile 200: %s" % p)
	check(PlayerAircraft.profile(120).type == 100, "an unflyable type (F-4E) falls back to the F-16")

	Settings().jet_id = 3
	var tv = await start_mission(311)
	check(tv.player.type == 200 and tv.aircraft != null and tv.aircraft.type_code == 200, "Jet list F-4 2000: type 200 flies")
	check(tv.cockpit.cockpit_dir.ends_with("/f4-2000") and tv.cockpit.layout.has("VARIOCLOCK") \
			and tv.cockpit.layout.has("FUELCLOCK") and tv.cockpit.twin_engines, "its cockpit: f4-2000, round gauges, twin engines")
	check(not tv.cockpit.mfds.is_empty() and tv.cockpit.mfds.all(func(m): return is_instance_valid(m) and m.get_parent() == tv.cockpit),
			"its MFDs (%d), the F-16's replaced" % tv.cockpit.mfds.size())
	check(tv.player_damage.twin and tv.weapons != null and tv.weapons.jet_type == 200, "twin-engine damage, F-4 2000 weapons")
	# 311 starts with the engine off: "1" starts it (idle); brakes off (B), military power (6): it rolls.
	key(tv, KEY_1)
	key(tv, KEY_B)
	key(tv, KEY_6)
	var v0: float = tv.flight.state().speed_kt
	await create_timer(6.0).timeout
	var st: Dictionary = tv.flight.state()
	check(st.speed_kt > v0 + 10.0 and st.on_ground and not st.crashed, "it accelerates on the runway (%.0f -> %.0f kt)" % [v0, st.speed_kt])
	check(float(st.internal_fuel_kg) > 0.0 and tv.cockpit.state.internal_fuel_kg == st.internal_fuel_kg, "the fuel gauge's capacity reaches the cockpit")

	# The cockpit state from the flight model (IafFlight.instruments, iaf_flight::instruments; its Rust tests hold
	# the formulas): the engine needles per engine with the damage flags, the fuel fill, the speeds.
	var flags := []
	flags.resize(25)
	flags.fill(false)
	flags[17] = true  # right engine on fire
	flags[22] = true  # left engine permanently damaged
	var ins: Dictionary = tv.flight.instruments(flags)
	var en: PackedFloat32Array = ins.engines
	var rpm: float = st.rpm
	check(en.size() == 6 and is_zero_approx(en[0]) and is_zero_approx(en[1]) and is_equal_approx(en[3], rpm)
			and is_equal_approx(en[5], 0.9), "engine needles with damage: %s at rpm %.2f" % [en, rpm])
	check(is_equal_approx(tv.cockpit.state.fuel_fill, ins.fuel_fill) and ins.fuel_fill > 0.9, "fuel fill %.2f in the cockpit" % ins.fuel_fill)
	var Hud = load("res://cockpit/hud.gd")
	check(Hud.speed_text({"tas_kt": 300.0, "ground_kt": 280.0, "ias_kt": 250.0}, 0, false) == " 280G"
			and Hud.speed_text({"tas_kt": 300.0, "ground_kt": 280.0, "ias_kt": 250.0}, 1, false) == " 250"
			and Hud.speed_text({"tas_kt": 300.0, "ground_kt": 280.0, "ias_kt": 250.0}, 5, true) == " 300T", "HUD speed per HUD mode")

	# Drag chute (Shift+B) on the ground: deployed at once, the model's Parach shown.
	key(tv, KEY_B, true)
	await frames(2)
	check(tv.drag_chute == 2 and tv.aircraft.part_node("Parach").visible, "Shift+B on the ground: the drag chute deploys")

	# Real flight data: the Real [F-4] row (internal fuel 12,060 lb against the original's 12,500).
	var fuel_orig: float = st.internal_fuel_kg / 0.45359
	Settings().flight_data = "real"
	Settings().weapon_data = "real"
	tv = await start_mission(311)
	var radar = tv.weapons.radar
	check(absf(float(radar.modes[radar.LRS].nm) - 44000.0 / 1854.0) < 0.05, "Real weapons: the APG-76's range (%.1f NM)" % radar.modes[radar.LRS].nm)
	var guns: Array = tv.weapons.stores.stations.values().filter(func(st): return int(st.w.type) == tv.weapons.stores.GUN)
	check(guns.size() == 1 and int(guns[0].count) == 639, "Real weapons: the F-4E airframe's 639 gun rounds (%s)" % [guns.map(func(st): return st.count)])
	Settings().weapon_data = "original"
	var fuel_real: float = tv.flight.state().internal_fuel_kg / 0.45359
	check(tv.real_data and absf(fuel_orig - 12500.0) < 5.0 and absf(fuel_real - 12060.0) < 5.0,
			"Real data: internal fuel %.0f lb (original %.0f lb)" % [fuel_real, fuel_orig])
	# Real data: the deployed chute brakes the roll (the original's is visual only). One roll: run up to ~90 kt,
	# idle, 2 s without the chute, then 2 s with it: the speed falls clearly faster.
	key(tv, KEY_1)
	key(tv, KEY_B)
	key(tv, KEY_8)
	var t0 := Time.get_ticks_msec()
	while tv.flight.state().speed_kt < 90.0 and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	key(tv, KEY_1)
	var lost := []
	for chute in [0, 2]:
		tv.drag_chute = chute
		var start_v: float = tv.flight.state().speed
		await create_timer(2.0).timeout
		lost.append(start_v - float(tv.flight.state().speed))
	check(lost[1] > lost[0] * 1.5 and lost[1] > lost[0] + 0.5,
			"Real data: the chute brakes the roll (2 s: %.2f m/s with it, %.2f without)" % [lost[1], lost[0]])
	Settings().flight_data = "original"

	# In the air (312 starts airborne, the autopilot holding level): gear, flaps, speed brake, afterburner.
	tv = await start_mission(312)
	var ac = tv.aircraft
	check(tv.player.type == 200 and not tv.gear_down and is_equal_approx(ac.ramps.gear, ac.GEAR_MAX), "312: the F-4 2000 in the air, gear up")
	var flap: Node3D = ac.part_node("FlapL")
	var flap0: Basis = flap.basis
	key(tv, KEY_G)
	check(not tv.gear_down, "G above the gear speed limit (%.0f kt): ignored" % tv.flight.state().speed_kt)
	key(tv, KEY_F)
	key(tv, KEY_B)
	key(tv, KEY_8)
	await create_timer(3.0).timeout
	check(tv.flaps > 0.0 and ac.ramps.flaps > 0.1 and not flap.basis.is_equal_approx(flap0), "F: the flaps go down (FlapL moves)")
	check(ac.ramps.speed_brake > 0.1 and tv.cockpit.indicators[5], "B: the speed brake opens, its light on")
	check(ac.flames.size() == 2 and ac.flame_lit(), "full AB: both engines' flames lit (%d)" % ac.flames.size())
	# Slow (the flight model restarted at 200 kt, same place and heading): the gear cycles.
	var p0: Vector3 = tv.flight.state().position
	var fwd: Vector3 = tv.flight.state().forward
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, p0, tv.flight.state().heading, 0.0, 0.0,
			fwd * 200.0 * 0.5144, true, true, false)
	key(tv, KEY_G)
	await create_timer(4.0).timeout
	check(tv.gear_down and ac.ramps.gear < 0.01 and tv.cockpit.gear_legs == [2, 2, 2],
			"G at 200 kt: the gear comes down (ramp %.3f, legs %s)" % [ac.ramps.gear, tv.cockpit.gear_legs])
	key(tv, KEY_G)
	await create_timer(4.0).timeout
	check(not tv.gear_down and absf(ac.ramps.gear - ac.GEAR_MAX) < 0.01 and tv.cockpit.gear_legs == [0, 0, 0], "G again: the gear goes up")

	# Two-seat ejection (E ×3 in the air): the F-4 2000 has pilot and pilotB, so two seats are thrown and two
	# parachuters follow (FUN_0053ee90: the second record only when the model has a pilotB).
	for i in 3:
		key(tv, KEY_E)
	# The mission ends after the ejection (the scene goes): count while it lasts.
	var n := 0
	var te := Time.get_ticks_msec()
	while is_instance_valid(tv) and n < 2 and Time.get_ticks_msec() - te < 8000:
		n = tv._parachuters.size()
		await process_frame
	check(n == 2, "two-seat ejection: %d parachuters" % n)

	Settings().jet_id = -1
	tv = await start_mission(311)
	check(tv.player.type == 100 and tv.cockpit.cockpit_dir.ends_with("/f16") and not tv.cockpit.twin_engines,
			"without a pick: the mission's F-16, its cockpit")

	# Every cockpit of cockpits.ibx loads and draws its round gauges: each active needle other than the altimeter
	# (which ignores it) has a FullClock > 0 (the MiG-29's altimeter has none).
	for t in PlayerAircraft.COCKPIT:
		var dir: String = "converted/cockpits/" + PlayerAircraft.cockpit_folder(t)
		tv.cockpit.load_cockpit(dir)
		tv.cockpit.queue_redraw()
		await frames(2)
		var bad := []
		for k in tv.cockpit.layout:
			var g = tv.cockpit.layout[k]
			if k.contains("CLOCK") and k != "ALTITUDELOCK" and g is Dictionary and g.get("Active", 0) == 1 \
					and not float(g.get("FullClock", 0.0)) > 0.0:
				bad.append(k)
		check(tv.cockpit.cockpit_dir == dir and bad.is_empty(), "type %d: %s draws (bad gauges %s)" % [t, dir, bad])
		# Attitude indicators (docs/cockpit.md "Attitude indicators"): the lens ball where [LENHORIZON] is active,
		# and on the OnMfd cockpits the MFD ADI page (9) draws.
		var lens_on: bool = int(tv.cockpit.layout.get("LENHORIZON", {}).get("Active", 0)) == 1
		var lens = tv.cockpit._lens
		check((lens != null and lens.visible and lens.size.x > 0.0) == lens_on, "%s: lens ADI %s" % [dir, "shown" if lens_on else "none"])
		if int(tv.cockpit.layout.get("HORIZON", {}).get("OnMfd", 0)) == 1:
			tv.cockpit.mfds[0].page = 9
			tv.cockpit.mfds[0].queue_redraw()
			await frames(2)
			check(tv.cockpit.mfds[0].page == 9, "%s: the MFD ADI page draws" % dir)
