# Original data set, v1.1 rudder handler (FUN_0059f5a0 → FUN_0059f3d0, docs/flight-model.md "The rudder handler"):
# on the ground a pedal change is a stick event (x = pedal, y = 0), so the pedals steer the nose wheel and move the
# rudder part; the next stick move takes over again.
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().flight_data = "original"
	var tv = await start_mission(311)
	key(tv, KEY_1)
	key(tv, KEY_B)
	for i in 2:
		key(tv, KEY_0)
	var t0 := Time.get_ticks_msec()
	while tv.flight.state().speed_kt < 8.0 and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	tv.scripted_stick = Vector2(0.0, 0.3)
	tv.scripted_rudder = 0.0
	await frames(5)
	check(is_equal_approx(tv.flight.state().stick_y, 0.3), "the stick's pull held (%.2f)" % tv.flight.state().stick_y)
	var hdg0: float = tv.flight.state().heading
	tv.scripted_rudder = 1.0
	await frames(5)
	var st: Dictionary = tv.flight.state()
	check(
		st.stick_x == 1.0 and st.stick_y == 0.0,
		"the pedal is the stick's x, the pull centred (%.2f, %.2f)" % [st.stick_x, st.stick_y]
	)
	check(tv.aircraft._targets.rudder < 0.0, "the rudder part follows the pedal (%.3f)" % tv.aircraft._targets.rudder)
	await fly(tv, 3.0)
	var turned: float = wrapf(tv.flight.state().heading - hdg0, -180.0, 180.0)
	check(turned > 1.0, "the right pedal turns right (%.1f deg, %.0f kt)" % [turned, tv.flight.state().speed_kt])
	tv.scripted_stick = Vector2(-0.5, 0.0)
	await frames(5)
	check(
		is_equal_approx(tv.flight.state().stick_x, -0.5), "a stick move takes over (%.2f)" % tv.flight.state().stick_x
	)
