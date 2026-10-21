# The MiG-23 / MiG-29 Better cockpit (docs/mig-cockpits.md, docs/cockpit.md "Better cockpit"): a Mission Creator
# mission (0x29a) puts the player in each MiG, airborne. Original: every active needle record is drawn where the
# original draws it, no dial needle, the altimeter in ft. Better (smooth_needles off, so each needle is at its value):
# dials_by_label takes the misplaced records off their faces and draws each labelled dial from its value (MiG-23:
# Mach, EGT, litres, VVI; MiG-29: both tachometers); radar_alt / uua drive the MiG-29's radar altimeter (its flag
# covered while valid) and AoA / g meter; metric_gauges reads the altimeter in m and the MiG-23's VVI in m/s;
# turning_compass turns the MiG-23's HSI card with the heading; rsbn_counter shows the waypoint distance in km;
# spo15 lights the SPO-15's lamps from the RWR; pnp_bars moves the ПНП's bars with the ILS; hyd_gauge shows the
# hydraulic pressure (0 with damage 18); the UUA's max-g needle; radar_alt's danger lamp and Betty "altitude".
extends "res://../tests/godot/base.gd"

## Per cockpit folder: the Mission Creator's type index, each dial's label -> its centre (panel px).
const JETS := {
	"mig23":
	{
		"type": 7,
		"dials":
		{
			"M": Vector2(735, 275),
			"× 100 °C": Vector2(1183, 226),
			"× 1000 Л": Vector2(1175, 280),
			"VVI": Vector2(1098, 270),
			"HYD 1": Vector2(1030, 311.5),
			"HYD 2": Vector2(1055.5, 337)
		}
	},
	"mig29":
	{
		"type": 8,
		"dials":
		{
			"RPM L": Vector2(1009, 253),
			"RPM R": Vector2(1062, 253),
			"RADALT": Vector2(904, 168),
			"α": Vector2(1116, 55),
			"nᵧ": Vector2(1116, 55),
			"nᵧ max": Vector2(1116, 55)
		}
	},
}

var gauges: GDScript
var instruments: GDScript


func run() -> void:
	gauges = load("res://cockpit/gauges.gd")
	instruments = load("res://cockpit/instruments.gd")
	for folder in JETS:
		await _jet(folder)
	settings().better_cockpit = false


func _jet(folder: String) -> void:
	var m: Dictionary = ClassDB.class_call_static("IafMcr", "blank")
	m.count[0] = 1
	m.type[0] = JETS[folder].type
	m.alt = 2
	settings().mc = m
	settings().mc_files = load("res://menu/mission_creator.gd").build(m)
	settings().better_cockpit = false
	var tv: Node = await start_mission(0x29a)
	var c = tv.cockpit
	check(String(c.cockpit_dir).ends_with(folder), "%s: the player flies the %s cockpit" % [folder, folder])
	await seconds(1.0)

	# Original: every active record drawn at the original's value; no dial needle; the altimeter in ft.
	var lay: Dictionary = c.layout
	var active := lay.keys().filter(
		func(k): return String(k).contains("CLOCK") and lay[k] is Dictionary and int(lay[k].get("Active", 0)) == 1
	)
	var a: Dictionary = c.needle_angles()
	check(
		active.all(func(k): return a.has(k)) and gauges.dial_needles(c).is_empty() and gauges.replaced(c).is_empty(),
		"%s: Original draws every active record (%s), no dial needle" % [folder, active]
	)
	check(
		is_equal_approx(a.ALTITUDELOCK, c.needle_angle("ALTITUDELOCK", c.state.alt_ft, 1000.0)),
		"%s: Original altimeter in ft" % folder
	)

	# Better, every item on (smooth_needles off).
	settings().better_cockpit = true
	settings().cockpit_items["smooth_needles"] = false
	_dials(c, folder, JETS[folder].dials.keys())
	a = c.needle_angles()
	check(
		absf(a.ALTITUDELOCK - c.needle_angle("ALTITUDELOCK", c.state.alt_ft / 3.28084, 1000.0)) < 1e-4,
		"%s: metric_gauges: the altimeter in m (%.0f m)" % [folder, c.state.alt_ft / 3.28084]
	)
	if folder == "mig23":
		var nav: Dictionary = load("res://cockpit/hud.gd").nav_cues(c.state, c.waypoints, c.current_waypoint)
		check(
			c.waypoints.size() > 0 and gauges.rsbn_km(c) == mini(int(nav.dist_nm * 1.852), 999),
			"mig23: rsbn_counter: the drum reads the waypoint distance (%03d km)" % gauges.rsbn_km(c)
		)
		await frames(2)
		var comp: Array = c.compasses
		check(
			comp.size() == 1 and comp[0].visible and is_equal_approx(comp[0].angle, deg_to_rad(float(c.state.heading))),
			"mig23: turning_compass: the HSI card turns with the heading (%.0f°)" % float(c.state.heading)
		)
		await _mig23_extras(tv, c)
	else:
		# 3333 m above the base: off the radar altimeter's face, so its flag shows (not covered); valid, covered.
		var b: Dictionary = c.state.better
		check(
			not b.radalt_valid and gauges.covered_flags(c).is_empty(),
			"mig29: radar_alt: above 1500 m the flag shows (%.0f m)" % b.radalt_m
		)
		c.state.better = b.duplicate()
		c.state.better.radalt_valid = true
		check(gauges.covered_flags(c).size() == 1, "mig29: radar_alt: valid, the flag is covered")
		c.state.better = b
		# dials_by_label alone: the tachometers; the misplaced records off; the radar altimeter / UUA faces empty.
		settings().cockpit_items["radar_alt"] = false
		settings().cockpit_items["uua"] = false
		_dials(c, folder, ["RPM L", "RPM R"])
		# The two items alone: their needles and records, the tachometers keep the original's records.
		settings().cockpit_items["radar_alt"] = true
		settings().cockpit_items["uua"] = true
		settings().cockpit_items["dials_by_label"] = false
		_dials(c, folder, ["RADALT", "α", "nᵧ", "nᵧ max"])
		check(
			gauges.replaced(c) == ["SPEEDCLOCK", "VARIOCLOCK", "VARIOCLOCK"] and c.needle_angles().has("THROTTLECLOCK"),
			"mig29: without dials_by_label only the items' records leave (%s)" % [gauges.replaced(c)]
		)
		settings().cockpit_items["dials_by_label"] = true
		check(
			float(c.state.better.g_max) >= float(c.state.g) - 1e-4,
			"mig29: uua: the max-g needle holds the highest g (%.2f ≥ %.2f)" % [c.state.better.g_max, c.state.g]
		)
		await _radalt_warning(tv, c)
	c.queue_redraw()
	await frames(2)  # the panel draw with every item (no script error)
	settings().cockpit_items["smooth_needles"] = true
	settings().better_cockpit = false
	await frames(2)
	check(
		c.compasses.all(func(n): return not n.visible) and gauges.dial_needles(c).is_empty(),
		"%s: Better off again: the original panel" % folder
	)


## The dial needles `want` are drawn, each on its dial's centre at its value from the cockpit state; the records
## replaced are not drawn.
func _dials(c, folder: String, want: Array) -> void:
	var st: Dictionary = c.state
	var b: Dictionary = st.better
	var eb: PackedFloat32Array = st.engines_better
	var values := {
		"M": st.mach,
		"× 100 °C": eb[2],
		"× 1000 Л": float(st.fuel_lbs) * 0.45359 / 0.78 / 1000.0,  # fuel_total on: all the fuel
		"VVI": float(st.vs_fpm) / 196.85 / 10.0,  # metric_gauges on: × 10 m/s
		"RPM L": eb[1],
		"RPM R": eb[4],
		"RADALT": float(st.agl_ft) / 3.281,
		"α": st.aoa,
		"nᵧ": st.g,
		"nᵧ max": float(b.g_max),
		"HYD 1": float(b.hyd),
		"HYD 2": float(b.hyd),
	}
	var specs := {}
	for d in gauges.DIALS[folder].dials:
		specs[d.dial] = d
	var drawn := {}
	for d in gauges.dial_needles(c):
		drawn[d.dial] = d
	var bad := []
	for k in want:
		if (
			not drawn.has(k)
			or drawn[k].centre.distance_to(JETS[folder].dials[k]) > 0.6
			or absf(drawn[k].angle - deg_to_rad(instruments.dial_angle(specs[k].scale, values[k]))) > 0.01
		):
			bad.append(k)
	check(
		bad.is_empty() and drawn.size() == want.size(),
		(
			"%s: each dial needle is on its dial at its value (%s; drawn %s; off %s; values %s)"
			% [folder, want, drawn.keys(), bad, want.map(func(k): return snappedf(float(values[k]), 0.01))]
		)
	)
	var gone: Array = gauges.replaced(c)
	var a: Dictionary = c.needle_angles()
	check(
		not gone.is_empty() and gone.all(func(k): return not a.has(k)),
		"%s: the records taken off are not drawn (%s)" % [folder, gone]
	)


## The MiG-23's SPO-15 (synthetic RWR entries), ПНП bars and hydraulic gauge.
func _mig23_extras(tv: Node, c) -> void:
	var own: Vector2 = c.state.world
	var hdg := deg_to_rad(float(c.state.heading))
	var ahead := Vector2(sin(hdg), cos(hdg))
	var right := Vector2(cos(hdg), -sin(hdg))
	# An SA-6 90° right at half the RWR range; a MiG-29 ahead that launched; an inactive SA-2.
	c.rwr = [
		{"type": 320, "pos": own + right * 18540.0, "launch": false, "active": true},
		{"type": 180, "pos": own + ahead * 30000.0, "launch": true, "active": true},
		{"type": 290, "pos": own + right * 100.0, "launch": false, "active": false},
	]
	var sp: Dictionary = gauges.spo15(c)
	check(
		sp.sectors == (1 << 7 | 1 << 0 | 1 << 4) and sp.power == 8 and sp.types == 0b101 and sp.lock and sp.launch,
		"mig23: spo15: the right 90° and both 10° lamps, 8 of 15 power lamps, П and Х, the centre flashing (%s)" % sp
	)
	settings().cockpit_items["spo15"] = false
	check(gauges.spo15(c).is_empty(), "mig23: spo15 off: the art as painted")
	settings().cockpit_items["spo15"] = true
	# The ПНП: live only while the HUD shows its ILS (NAV, gear handle down); the bars follow the deviation.
	var gear: bool = c.gear_handle_down
	c.gear_handle_down = false
	var off: bool = gauges.pnp_live(c)
	c.gear_handle_down = true
	c.weapons["hud_mode"] = 0
	var ils: Vector2 = c.state.ils
	var bars: Vector2 = c.state.better.pnp_bars
	var want := Vector2(clampf(ils.x / 2.5, -1, 1), clampf(ils.y / 0.7, -1, 1))
	check(
		not off and gauges.pnp_live(c) and bars.distance_to(want) < 1e-3,
		"mig23: pnp_bars: live with the gear down only; the bars %s at the ILS %s" % [bars, ils]
	)
	c.queue_redraw()
	await frames(2)  # the SPO-15 and ПНП drawn (no script error)
	c.gear_handle_down = gear
	# The hydraulic gauge: the normal pressure, 0 with the hydraulics damage (18).
	check(is_equal_approx(float(c.state.better.hyd), 210.0), "mig23: hyd_gauge: %.0f kgf/cm²" % c.state.better.hyd)
	tv.player_damage.flags[18] = true
	await frames(3)
	check(float(c.state.better.hyd) == 0.0, "mig23: hyd_gauge: 0 with the hydraulics damage")
	tv.player_damage.flags[18] = false
	await frames(2)


## The MiG-29's radar altimeter warning: moved to 40 m above the ground (gear up), below the 70 m index: the lamp
## lights and Betty "altitude" plays (the original's rule alone waits for 100 ft).
func _radalt_warning(tv: Node, c) -> void:
	var st: Dictionary = tv.flight.state()
	var pos: Vector3 = st.position
	pos.y -= float(c.state.agl_ft) / 3.281 - 40.0
	tv.flight.start(
		settings().assets_dir().path_join("install"),
		tv.player.fm_section,
		pos,
		Vector3(0.0, 0.0, st.heading),
		st.forward * 300.0 * 0.5144,
		{"airborne": true, "engine_on": true, "real_data": false}
	)
	tv.sounds.played.clear()
	await seconds(0.5)
	check(
		c.state.better.radalt_danger and gauges.radalt_danger(c) == true and not tv.gear_down,
		"mig29: radar_alt: below the danger height the lamp lights (%.0f m)" % c.state.better.radalt_m
	)
	check(tv.sounds.played.has("VOC_BBETTY/BTY_ALT"), "mig29: radar_alt: Betty altitude (%s)" % [tv.sounds.played])
	settings().cockpit_items["radar_alt"] = false
	check(gauges.radalt_danger(c) == null, "mig29: radar_alt off: no warning of its own")
	settings().cockpit_items["radar_alt"] = true
