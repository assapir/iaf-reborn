# "Better cockpit" aoa_indexer, standby_instruments and warning_lamps (game/cockpit/instruments.gd, docs/cockpit.md
# "Better cockpit"): with Original nothing is drawn; with Better each item follows its input (the F-16's AoA
# indexer and FLCS / TO/LDG CONFIG lamps, the Mirage's VVI needle), and each item's own flag turns it off. The
# values come from IafFlight.better_instruments (iaf_flight::instruments).
extends "res://../tests/godot/base.gd"


func run() -> void:
	# F-16 (jet 1).
	Settings().jet_id = 1
	Settings().better_cockpit = false
	var tv = await start_mission(312)
	var c = tv.cockpit
	check(String(c.cockpit_dir).get_file() == "f16", "jet 1 flies the f16 cockpit")
	var b: Dictionary = tv.flight.better_instruments([])
	check(int(b.get("aoa_index", 0)) in [1, 2, 3] and not b.flcs, "bridge: the F-16 has an indexer (%s), FLCS off" % b)
	var flags := []
	flags.resize(25)
	flags.fill(false)
	flags[18] = true
	check(tv.flight.better_instruments(flags).flcs, "bridge: hydraulics damage (18) lights FLCS")
	# The flight scene stops writing the cockpit state, so the test sets the inputs.
	tv.set_process(false)
	tv.set_physics_process(false)
	c.state["better"] = {"aoa_index": 1, "flcs": true, "to_ldg_config": true}
	await frames(2)
	check(c.better_instruments == null or (c.better_instruments.indexer == 0 and c.better_instruments.lamps.is_empty()),
			"f16: Original = the static art (no indexer, no lamps)")
	Settings().better_cockpit = true
	await frames(1)
	check(c.better_instruments._unlit != null, "f16: the unlit copy of the indexer art")
	for i in [1, 2, 3, 0]:
		c.state["better"] = {"aoa_index": i}
		await frames(2)
		check(c.better_instruments.indexer == i, "f16: indexer symbol %d lit (%d)" % [i, c.better_instruments.indexer])
	for w in [[true, false], [false, true], [false, false]]:
		c.state["better"] = {"flcs": w[0], "to_ldg_config": w[1]}
		await frames(2)
		var l: Dictionary = c.better_instruments.lamps
		check(l.get("flcs") == w[0] and l.get("to_ldg_config") == w[1], "f16: lamps FLCS %s TO/LDG %s (%s)" % [w[0], w[1], l])
	Settings().cockpit_items["aoa_indexer"] = false
	Settings().cockpit_items["warning_lamps"] = false
	c.state["better"] = {"aoa_index": 2, "flcs": true}
	await frames(2)
	check(c.better_instruments.indexer == 0 and c.better_instruments.lamps.is_empty(), "f16: the items' own flags off = static")
	Settings().cockpit_items["aoa_indexer"] = true
	Settings().cockpit_items["warning_lamps"] = true

	# Mirage (jet 6): the VVI needle.
	Settings().jet_id = 6
	Settings().better_cockpit = false
	tv = await start_mission(312)
	c = tv.cockpit
	check(String(c.cockpit_dir).get_file() == "mirage", "jet 6 flies the mirage cockpit")
	tv.set_process(false)
	tv.set_physics_process(false)
	c.state["vs_fpm"] = 1000.0
	await frames(2)
	check(c.better_instruments == null or is_nan(c.better_instruments.needles[0]), "mirage: Original = no VVI needle")
	Settings().better_cockpit = true
	for v in [[0.0, -90.0], [1000.0, -24.0], [-1000.0, -156.0], [3000.0, 24.5], [9000.0, 90.0], [-9000.0, -270.0]]:
		c.state["vs_fpm"] = v[0]
		await frames(2)
		var a: float = c.better_instruments.needles[0]
		check(is_equal_approx(a, deg_to_rad(v[1])), "mirage: %d ft/min → needle %.1f° (%.1f°)" % [v[0], v[1], rad_to_deg(a)])
	Settings().cockpit_items["standby_instruments"] = false
	await frames(2)
	check(is_nan(c.better_instruments.needles[0]), "mirage: the item's own flag off = static")
	Settings().cockpit_items["standby_instruments"] = true
	Settings().jet_id = -1
	Settings().better_cockpit = false
