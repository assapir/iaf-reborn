# Every Jet list jet's panel gauges (docs/cockpit.md "Gauges") move with the flight: in 312 (airborne) idle with the
# gear up, then military with the gear down and a climb — each active needle section of the cockpit's layout is drawn
# (`needle_angles`) and turns; military reads RPM 100 % with no afterburner, AB 1 lights it. The Real HUD alternates
# on / off (the panel does not depend on it).
# Better cockpit (docs/cockpit.md "Better cockpit"): with the switch on, the RPM needle reads the FM's RPM, the TEMP
# needle the temperature model (hotter at military, hotter still in AB, cooling at idle), the throttle needle the AB
# stage above military, the fuel needle the fill with the tanks (and the F-15's counter), the Lavi / Mirage clock
# the time of day; with it off every needle is the original's.
extends "res://../tests/godot/base.gd"

## Jet list index (-1 = the F-35I through the Lavi's button) → name.
const JETS := {0: "F-15", 1: "F-16", 2: "F-4E", 3: "Kurnass 2000", 4: "Lavi", 5: "Kfir", 6: "Mirage", -1: "F-35I"}


func run() -> void:
	var hands: Array = load("res://cockpit/gauges.gd").clock_hands(15.0 * 3600.0 + 15.0 * 60.0)
	check(is_equal_approx(hands[0], 3.25 / 12.0 * TAU) and is_equal_approx(hands[1], PI / 2.0),
			"the panel clock reads 15:15 as 3:15 (%s)" % [hands])
	for id in JETS:
		Settings().jet_id = 4 if id == -1 else id
		Settings().f35i_slot = 4 if id == -1 else -1
		Settings().hud_style = "real" if absi(id) % 2 == 1 else "original"
		await _jet(JETS[id])
	Settings().jet_id = -1
	Settings().f35i_slot = -1
	Settings().hud_style = "original"


func _jet(name: String) -> void:
	var tv = await start_mission(312)
	var c = tv.cockpit
	var lay: Dictionary = c.layout
	var active := lay.keys().filter(func(k): return String(k).contains("CLOCK") and lay[k] is Dictionary and int(lay[k].get("Active", 0)) == 1)
	key(tv, KEY_1)
	await create_timer(4.0).timeout
	var a: Dictionary = c.needle_angles()
	var t_idle: float = c.state.engine_temp_c[0]
	check(active.all(func(k): return a.has(k)), "%s: every active needle is drawn (%s)" % [name, active])
	# Military, gear down, climbing.
	var st: Dictionary = tv.flight.state()
	tv.flight.start(Settings().assets_dir().path_join("install"), tv.player.fm_section, st.position,
			Vector3(0.0, 0.0, st.heading), st.forward * 200.0 * 0.5144 + Vector3(0, 0, 25),
			{"airborne": true, "engine_on": true, "real_data": false})
	key(tv, KEY_6)
	key(tv, KEY_G)
	await create_timer(0.5).timeout
	var climbing: float = c.needle_angles().get("VARIOCLOCK", NAN)  # the vario rests at 0 once it sinks again
	await create_timer(3.5).timeout
	var b: Dictionary = c.needle_angles()
	if b.has("VARIOCLOCK"):
		b["VARIOCLOCK"] = climbing
	var still := a.keys().filter(func(k): return is_equal_approx(a[k], b.get(k, a[k])))
	check(still.is_empty(), "%s: every needle turns from idle to military / climbing (still: %s)" % [name, still])
	st = tv.flight.state()
	var en: PackedFloat32Array = c.state.engines
	check(is_equal_approx(en[0], 1.0) and int(st.get("afterburner", 0)) == 0,
			"%s: military reads RPM 100 %% with no afterburner (%.2f, AB %d)" % [name, en[0], int(st.get("afterburner", 0))])
	check(c.gear_handle_down, "%s: the gear lights follow the handle" % name)
	var t_mil: float = c.state.engine_temp_c[0]
	await _better(c, name, active, "military")
	key(tv, KEY_7)
	await create_timer(1.0).timeout
	check(int(tv.flight.state().get("afterburner", 0)) > 0 or not _has_ab(tv),
			"%s: AB 1 lights the afterburner" % name)
	var t_ab: float = c.state.engine_temp_c[0]
	await _better(c, name, active, "AB 1")
	check(t_idle < t_mil and t_mil < t_ab, "%s: Better: the temperature rises idle %.0f -> military %.0f -> AB %.0f C"
			% [name, t_idle, t_mil, t_ab])
	key(tv, KEY_1)
	await create_timer(1.0).timeout
	check(c.state.engine_temp_c[0] < t_ab and c.state.engine_temp_c[0] > t_idle,
			"%s: Better: it cools at idle (%.0f C)" % [name, c.state.engine_temp_c[0]])
	# Drop tanks (half the internal fuel): the original fill stays at 1 while the tank fuel burns; the Better fill is
	# the fuel over the load with the tanks.
	var internal: float = tv.flight.state().internal_fuel_kg
	tv.flight.set_fuel_capacity(internal * 0.5)
	key(tv, KEY_6)
	await create_timer(3.0).timeout
	var kg: float = tv.flight.state().fuel_lbs * 0.45359
	check(is_equal_approx(c.state.fuel_fill, 1.0) and c.state.fuel_fill_total < 0.9999 and absf(c.state.fuel_fill_total - kg / (internal * 1.5)) < 0.01,
			"%s: tank fuel burning: original fill 1, Better %.4f = %.0f / %.0f kg" % [name, c.state.fuel_fill_total, kg, internal * 1.5])
	await _better(c, name, active, "tanks")


## Better cockpit on (then off again): each active engine / fuel needle reads its Better value; off, the original.
func _better(c, name: String, active: Array, phase: String) -> void:
	var lay: Dictionary = c.layout
	var en: PackedFloat32Array = c.state.engines
	var off: Dictionary = c.needle_angles()
	var orig := {"FUELCLOCK": c.state.fuel_fill}
	for e in 2:
		var sfx := "SECONDARY" if e == 1 else ""
		orig["THROTTLECLOCK" + sfx] = en[3 * e]
		orig["RPMCLOCK" + sfx] = en[3 * e + 1]
		orig["TEMPCLOCK" + sfx] = en[3 * e + 2]
	var bad := orig.keys().filter(func(k): return active.has(k) and not is_equal_approx(off[k], c.needle_angle(k, orig[k])))
	check(bad.is_empty(), "%s (%s): Better cockpit off, every needle is the original's (off: %s)" % [name, phase, bad])
	Settings().better_cockpit = true
	var on: Dictionary = c.needle_angles()
	var st: Dictionary = c.state
	var ab: int = int(st.get("afterburner", 0))
	var want := {"FUELCLOCK": [st.fuel_fill_total, 0.0]}
	for e in 2:
		var sfx := "SECONDARY" if e == 1 else ""
		var thr_full := maxf(float(lay.get("THROTTLECLOCK" + sfx, {}).get("FullClock", 1.0)), 1.25)
		want["THROTTLECLOCK" + sfx] = [st.rpm + 0.1 * ab, thr_full]
		want["RPMCLOCK" + sfx] = [st.rpm, 0.0]
		want["TEMPCLOCK" + sfx] = [st.engine_temp_c[e] / 1000.0, 0.0]
	bad = want.keys().filter(func(k): return active.has(k) and absf(on[k] - c.needle_angle(k, want[k][0], want[k][1])) > 0.02)
	check(bad.is_empty(), "%s (%s): Better cockpit on, each needle follows its input (rpm %.2f, AB %d, %.0f C; off: %s)"
			% [name, phase, st.rpm, ab, st.engine_temp_c[0], bad])
	# The F-15's painted fuel counter and the Lavi / Mirage clock are drawn (no script error in the panel draw).
	c.queue_redraw()
	await process_frame
	Settings().better_cockpit = false


func _has_ab(tv) -> bool:
	return tv.aircraft != null and not tv.aircraft.flames.is_empty()
