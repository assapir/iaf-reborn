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
	await frames(240)
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
