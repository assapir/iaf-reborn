# Mission 311 "Engines ON": ground start at 0 kt, gear down, engine off; "1" starts the engine,
# brakes off + throttle rolls the jet, the stick steers the nose wheel, the gear can't be raised
# on the ground.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(311)
	var st: Dictionary = tv.flight.state()
	check(st.speed_kt < 1.0, "starts at rest (%.2f kt)" % st.speed_kt)
	check(tv.gear_down and tv.brakes, "gear down, brakes on")
	check(not st.engine_on, "engine off at a ground start")
	key(tv, KEY_G)
	check(tv.gear_down, "gear can't be raised on the ground")
	key(tv, KEY_1)
	check(tv.flight.state().engine_on, "1 starts the engine")
	key(tv, KEY_B)
	for i in 3:
		key(tv, KEY_0)
	check(is_equal_approx(tv.flight.state().throttle, 0.2775), "three 5 %% steps in one frame add up (%.4f)" % tv.flight.state().throttle)
	# The brakes release over 1.7 s (ramp 0.855 at 0.5/s, docs/flight-model.md §15.6.4).
	var t0 := Time.get_ticks_msec()
	while tv.flight.state().speed_kt < 5.0 and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	st = tv.flight.state()
	check(st.speed_kt > 5.0, "rolling after throttle up (%.1f kt)" % st.speed_kt)
	var hdg0: float = st.heading
	tv.scripted_stick = Vector2(-1, 0)
	await frames(240)
	var turned: float = hdg0 - tv.flight.state().heading
	# The original's rate is small at taxi speed: stick · V · 20°/s / 74.53 m/s.
	check(turned > 1.5, "stick left turns left on the ground (%.1f deg)" % turned)
