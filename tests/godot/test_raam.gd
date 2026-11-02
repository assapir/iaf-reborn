# The Extras switch "F-15 version" on Ra'am (docs/f15i.md): every F-15 (type 110), the player's and the AI's, flies the
# F-15I row (22,665 lb internal fuel), gets the APG-70I's 104 km and the F-15E's 500 rounds, and its Arming lists the
# Python 5 and the GBU-31(V)3 whatever Extras "Weapons" says; the TSD, the info line and the Reference name it.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_raam.gd
extends "res://../tests/godot/base.gd"

const RAAM_FUEL_KG := 22665.0 * 0.45359


func run() -> void:
	await require_data()
	settings().f15_variant = "raam"
	settings().weapon_data = "real"
	var real_weapons = load("res://weapons/real_weapons.gd")
	var mission_weapons = load("res://weapons/mission_weapons.gd")
	var combat = load("res://ai/combat.gd")
	check(absf(real_weapons.radar_nm(110) * 1854.0 - 104000.0) < 1.0, "Real F-15I (APG-70I): 104 km")
	check(real_weapons.gun_rounds(110) == 500, "Real F-15I gun: 500 rounds (F-15E)")
	check(combat.sensor_nm(110) == 30.8, "AI F-15I sensor: 30.8 NM")
	check(combat.sensor_nm(100) == 40.0, "AI F-16 sensor unchanged: 40 NM")
	check(load("res://menu/tsd.gd").unit_label({"type": 110, "cls": 2, "name": ""}) == "F-15I", "TSD names it F-15I")
	# The Arming list: the Ra'am's own modern weapons with Extras "Weapons" on Original, on its stations.
	settings().modern_weapons = false
	var mw = mission_weapons.create(231)
	var found := false
	for n in mw.flights:
		if int(mw.flights[n].type) != 110:
			continue
		found = true
		mw.reset(n)
		var names := []
		for t in [0, 1]:
			names.append_array(mw.tab_list(t).map(func(x): return x.name))
		check(names.has("PYTH-5") and names.has("GBU-31V3"), "F-15I lists PYTH-5 and GBU-31V3: %s" % [names])
		check(not names.has("AIM-9X") and not names.has("GBU-31"), "no AIM-9X / GBU-31 (no F-15I source)")
		for w in mw.weapons:
			if w.name == "GBU-31V3":
				check(w.max == [0, 1, 1, 1, 0, 1, 1, 1, 0], "GBU-31V3 on B, C, D, F, G, H: %s" % [w.max])
			elif w.name == "PYTH-5":
				check(w.max == [2, 0, 0, 0, 0, 0, 0, 0, 2], "PYTH-5 two on A and I: %s" % [w.max])
		break
	check(found, "mission 231 has an F-15 flight")
	var jet: Dictionary = mission_weapons.jet(110)
	check(
		jet.art == "x_f15i" and jet.title == "F-15I" and jet.base == 59734.0 and jet.max == 81000.0,
		"its own Arming art and weights: %s" % jet
	)
	settings().jet_id = 0
	var tv = await start_mission(231)
	await frames(5)
	check(tv.player.type == 110, "the F-15 flies mission 231")
	var fuel: float = tv.flight.state().internal_fuel_kg
	check(absf(fuel - RAAM_FUEL_KG) < 1.0, "player F-15I: internal fuel %.0f kg" % fuel)
	check(tv._modes_text().contains("RAAM"), "info line: %s" % tv._modes_text())
	for p in tv.ai.pilots.filter(func(p): return int(p.ent.type_code) == 110):
		var f: float = p.flight.state().internal_fuel_kg
		check(absf(f - RAAM_FUEL_KG) < 1.0, "AI %s F-15I: internal fuel %.0f kg" % [p.ent.name, f])
	# In the air 3,000 m up at 250 m/s, full afterburner: 30 s of the game's flight.
	var st0: Dictionary = tv.flight.state()
	var flags := {"airborne": true, "engine_on": true, "real_data": false, "f15_variant": "raam"}
	tv.flight.start(
		settings().assets_dir().path_join("install"),
		tv.player.fm_section,
		st0.position + Vector3(0.0, 3000.0, 0.0),
		Vector3(0.0, 0.0, st0.heading),
		st0.forward * 250.0,
		flags
	)
	tv.gear_down = false
	tv.throttle = 1.0
	tv._throttle_event()
	var s0: Dictionary = tv.flight.state()
	await fly(tv, 30.0)
	var s: Dictionary = tv.flight.state()
	check(
		not bool(s.crashed) and float(s.speed) > 150.0 and absf(float(s.alt_ft - s0.alt_ft)) < 2000.0,
		"the Ra'am flies 30 s: %.0f m/s, %.0f ft height change" % [s.speed, s.alt_ft - s0.alt_ft]
	)
	var burn := float(s0.fuel_lbs - s.fuel_lbs) * 0.45359
	check(burn > 300.0, "it burns the -229s' afterburner fuel: %.0f kg in 30 s" % burn)
	settings().f15_variant = "baz"
