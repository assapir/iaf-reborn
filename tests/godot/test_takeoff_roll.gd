# Full-afterburner takeoff roll with steering inputs: speed never drops back (the "jump to 0 kt"
# glitch), the jet accelerates through 145 kt and lifts off when pulled.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(311)
	key(tv, KEY_1)
	key(tv, KEY_B)
	key(tv, KEY_8)
	var last := 0.0
	var worst_drop := 0.0
	var t0 := Time.get_ticks_msec()
	var airborne := false
	while Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		var st: Dictionary = tv.flight.state()
		# Small steering corrections like a player keeping the centreline.
		tv.scripted_stick = Vector2(sin(Time.get_ticks_msec() * 0.002) * 0.3, 0.5 if st.speed_kt > 150.0 else 0.0)
		worst_drop = maxf(worst_drop, last - st.speed_kt)
		last = st.speed_kt
		if not st.on_ground and st.speed_kt > 120.0:
			airborne = true
			break
	check(worst_drop < 5.0, "speed never drops back during the roll (worst drop %.1f kt)" % worst_drop)
	check(airborne, "lifts off (at %.0f kt)" % last)
