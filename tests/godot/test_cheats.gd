# The retail cheats (docs/controls.md §4, FUN_00450780): Shift+D turns the console's messages off and on, Shift+S the
# weapons safety override, Shift+F refuels the internal tank only while the release permission fails (inverted), and
# Shift+R reloads the stores only behind its key combination (gear up, radar STBY, speed brakes out, HUD mode 4).
# Mission 231, airborne, the flight model frozen.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(231)
	await frames(3)
	var w = airborne_case(tv, [30, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 59, 1, 25, 235, 33, 90, 34, 60])
	await frames(2)
	# Shift+D: "off" is the last message the console takes; "on" the first after.
	key(tv, KEY_D, true)
	check(not tv.text_messages and _last(tv) == "Cheat: Text messages off", "Shift+D: text messages off")
	tv._on_subtitle("a mission message")
	check(_last(tv) == "Cheat: Text messages off", "messages off: the console skips them")
	key(tv, KEY_D, true)
	check(tv.text_messages and _last(tv) == "Cheat: Text messages on", "Shift+D again: on")
	# Shift+S: the safety override.
	key(tv, KEY_S, true)
	check(w.safety_off and _last(tv) == "Safety Off", "Shift+S: Safety Off")
	key(tv, KEY_S, true)
	check(not w.safety_off and _last(tv) == "Safety On", "Shift+S again: Safety On")
	# Shift+F: refused upright; inverted, the fuel and its maximum become the internal capacity.
	var st0: Dictionary = tv.flight.state()
	tv.flight.set_fuel(500.0)
	key(tv, KEY_F, true)
	check(absf(float(tv.flight.state().fuel_lbs) * 0.45359 - 500.0) < 1.0, "Shift+F upright: no refuel")
	tv.flight.start(
		Settings().assets_dir().path_join("install"),
		tv.player.fm_section,
		st0.position,
		Vector3(0.0, 180.0, st0.heading),
		st0.forward * 250.0,
		{"airborne": true, "engine_on": true, "real_data": false}
	)
	tv.flight.set_fuel(500.0)
	key(tv, KEY_F, true)
	var st: Dictionary = tv.flight.state()
	print("  inverted: roll %.0f fuel %.0f kg of %.0f" % [st.roll, st.fuel_lbs * 0.45359, st.internal_fuel_kg])
	check(
		(
			absf(float(st.fuel_lbs) * 0.45359 - float(st.internal_fuel_kg)) < 1.0
			and _last(tv) == "Cheat: Refuel internal tank"
		),
		"Shift+F inverted: internal tank full"
	)
	# Shift+R: refused without the combination; with it every station is back to its initial count.
	var n0: int = w.stores.displayed(0)
	w.stores.fired(0)
	check(w.stores.displayed(0) == n0 - 1, "one HARM gone")
	key(tv, KEY_R, true)
	check(w.stores.displayed(0) == n0 - 1, "Shift+R without the combination: refused")
	w.radar.standby()
	tv.brakes = true
	w.hud_mode = 4
	key(tv, KEY_R, true)
	print("  combination: radar %d brakes %s hud %d" % [w.radar.mode, tv.brakes, w.hud_mode])
	check(
		w.stores.displayed(0) == n0 and _last(tv) == "Cheat: Reload Weapons", "Shift+R with the combination: reloaded"
	)


func _last(tv) -> String:
	var lines: Array = tv.cockpit.subtitles
	return "" if lines.is_empty() else String(lines[-1])
