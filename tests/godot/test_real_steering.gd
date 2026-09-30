# Real data set: geometric nose-wheel steering from the rudder pedals (fast turn at taxi speed);
# the stick does not steer.
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().flight_data = "real"
	var tv = await start_mission(311)
	key(tv, KEY_1)
	key(tv, KEY_B)
	for i in 2:
		key(tv, KEY_0)
	# The brakes release over 1.7 s (docs/flight-model.md §15.6.4); taxi at >= 5 kt.
	var t0 := Time.get_ticks_msec()
	while tv.flight.state().speed_kt < 5.0 and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var st: Dictionary = tv.flight.state()
	var hdg0: float = st.heading
	tv.scripted_stick = Vector2(-1, 0)
	tv.scripted_rudder = 0.0
	await frames(90)
	var by_stick: float = absf(tv.flight.state().heading - hdg0)
	check(by_stick < 1.0, "stick does not steer with real data (%.1f deg)" % by_stick)
	hdg0 = tv.flight.state().heading
	tv.scripted_rudder = -1.0
	await frames(120)
	var turned: float = hdg0 - tv.flight.state().heading
	check(turned > 20.0, "left pedal turns left fast at taxi speed (%.1f deg in 2 s, %.0f kt)" % [turned, tv.flight.state().speed_kt])
	# Takeoff roll with steering corrections: no early lift-off (the original's x4 quirk is off).
	tv.scripted_stick = Vector2.ZERO
	key(tv, KEY_8)
	var early := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		var roll: Dictionary = tv.flight.state()
		tv.scripted_rudder = sin(Time.get_ticks_msec() * 0.003) * 0.5
		tv.scripted_stick = Vector2(sin(Time.get_ticks_msec() * 0.002) * 0.4, 0.0)
		if not roll.on_ground and roll.speed_kt < 140.0:
			early = true
		if roll.speed_kt > 145.0:
			break
	check(not early, "no lift-off below 140 kt while steering")
