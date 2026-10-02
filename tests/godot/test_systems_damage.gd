# The player's systems damage acting on the flying (docs/damage.md §5.3): the flight model reads the flags
# (fuel leak → fuel flow, engine fire → no RPM on a single engine, hydraulics → a quarter of the stick,
# total flight control → no stick), the extinguisher (X, GEV 0x49) puts the fire out once, the air
# brakes key is refused with brakes damage, the gear overspeed damage (> 450 kt, gear down and locked),
# and the afterburner flame of a damaged side stays out.
extends "res://../tests/godot/base.gd"


func seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame


func run() -> void:
	Settings().invulnerable = false
	var tv = await start_mission(324)  # airborne at 2000 m
	var pd = tv.player_damage
	var fl = tv.flight
	tv.throttle = 0.74
	tv._throttle_event()
	await seconds(1.5)
	var ff0: float = fl.fuel_flow()
	pd.system_damage(10)
	await seconds(1.5)
	var ff1: float = fl.fuel_flow()
	check(ff1 > ff0 * 1.2, "fuel leak (10): more fuel flow (%.3f -> %.3f kg/s)" % [ff0, ff1])

	# Hydraulics (18): the flight model takes a quarter of the stick; total flight control (24): none.
	tv.scripted_stick = Vector2(0.8, 0.0)
	await frames(3)
	check(is_equal_approx(fl.state().stick_x, 0.8), "stick before the damage (%.2f)" % fl.state().stick_x)
	pd.system_damage(18)
	tv.scripted_stick = Vector2(0.6, 0.0)
	await frames(3)
	check(is_equal_approx(fl.state().stick_x, 0.15), "hydraulics: a quarter of the stick (%.3f)" % fl.state().stick_x)
	pd.flags[24] = true
	tv.scripted_stick = Vector2(0.7, 0.4)
	await frames(3)
	check(fl.state().stick_x == 0.0 and fl.state().stick_y == 0.0, "total flight control: no stick")
	pd.flags[24] = false
	pd.flags[18] = false
	tv.scripted_stick = Vector2.ZERO

	# Engine fire (16): the fire light; a single engine stops (RPM ramps to 0), a twin keeps running.
	var rpm0: float = fl.state().rpm
	pd.system_damage(16)
	check(tv.cockpit.indicators[1], "engine fire light on")
	await seconds(3.0)
	var rpm1: float = fl.state().rpm
	if pd.twin:
		check(rpm1 > 0.5, "twin: one engine on fire, RPM stays (%.2f)" % rpm1)
	else:
		check(rpm1 < rpm0 - 0.3, "single engine on fire: RPM falls (%.2f -> %.2f)" % [rpm0, rpm1])
	# X: the extinguisher clears the fire (and the cut-out flags), the lights go out; one charge only.
	tv._command([73, 0, 0])
	check(not pd.flags[16] and not tv.cockpit.indicators[1] and not pd.extinguisher, "extinguisher: fire out, charge used")
	check(pd.flags[8], "the afterburner damage the fire set stays")
	pd.system_damage(16)
	tv._command([73, 0, 0])
	check(pd.flags[16], "no second charge")
	pd.flags[16] = false
	tv.throttle = 1.0
	tv._throttle_event()
	await seconds(3.0)
	var st: Dictionary = fl.state()
	if not pd.twin:
		check(st.afterburner == 0, "single engine with AB damage (8): full throttle, no afterburner (stage %d)" % st.afterburner)

	# Air brakes damage (5): the B key is refused.
	var b: bool = tv.brakes
	pd.system_damage(5)
	tv._command([17, 0, 0])
	check(tv.brakes == b, "air brakes damaged: the key is refused")

	# Gear overspeed (@449082): > 450 kt with the handle down and leg 1 locked, unless Invulnerable.
	pd.flags[7] = false
	pd.gear_overspeed(240.0, true, 2, true)
	check(not pd.flags[7], "invulnerable: no gear overspeed damage")
	pd.gear_overspeed(230.0, true, 2, false)
	check(not pd.flags[7], "447 kt: no damage")
	pd.gear_overspeed(240.0, true, 1, false)
	check(not pd.flags[7], "leg in transit: no damage")
	pd.gear_overspeed(240.0, true, 2, false)
	check(pd.flags[7], "466 kt with the gear down and locked: gear damage")

	# The afterburner flame of a side with AB damage (8 left / 9 right) stays out (FUN_005abc90 / 5abdc0).
	var ac = tv.aircraft
	if ac.flames.size() > 0:
		ac.update({"afterburner": 2, "rpm": 1.0, "ab_damage": [true, false]}, 0.016)
		var lit := {}
		for f in ac.flames:
			lit[str(f.name)] = f.lit()
		check(lit.get("Afterburner_left", false) == false, "left AB damaged: no left flame (%s)" % str(lit))
		if lit.has("Afterburner_right"):
			check(lit.Afterburner_right, "right flame still lit")

	# Radar damage (15): the radar switches off for good (FUN_004adb20).
	if tv.weapons != null:
		pd.system_damage(15)
		await frames(3)
		check(tv.weapons.radar.damaged and tv.weapons.radar.off, "radar damage: radar off")
