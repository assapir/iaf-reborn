# The reported glitch: a full stick pull on the runway at ~127 kt. Original (§14.7): g is limited by
# the envelope (~1.65), the jet keeps accelerating and stays on the ground; no reversal.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(311)
	key(tv, KEY_1)
	key(tv, KEY_B)
	key(tv, KEY_8)
	var t0 := Time.get_ticks_msec()
	while tv.flight.state().speed_kt < 127.0 and Time.get_ticks_msec() - t0 < 40000:
		await process_frame
	var hdg: float = tv.flight.state().heading
	var v0: float = tv.flight.state().speed_kt
	tv.scripted_stick = Vector2(0, 1)
	var min_speed := 999.0
	var max_hdg_change := 0.0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3000:
		await process_frame
		var st: Dictionary = tv.flight.state()
		min_speed = minf(min_speed, st.speed_kt)
		max_hdg_change = maxf(max_hdg_change, absf(angle_difference(deg_to_rad(st.heading), deg_to_rad(hdg))))
	check(min_speed > v0 - 5.0, "no hard deceleration (%.0f kt -> min %.0f kt)" % [v0, min_speed])
	check(rad_to_deg(max_hdg_change) < 5.0, "no heading flip (%.1f deg)" % rad_to_deg(max_hdg_change))
