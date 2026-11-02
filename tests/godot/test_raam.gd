# The Extras switch "F-15 version" on Ra'am (docs/f15i.md): every F-15 (type 110), the player's and the AI's, flies the
# F-15I row (22,665 lb internal fuel), gets the APG-70I's 104 km and the F-15E's 500 rounds, and its Arming lists the
# Python 5, the GBU-31(V)3 and the SPICE 1000 whatever Extras "Weapons" says; the TSD, the info line and the Reference
# name it; its Real HUD is the F-15E's. A SPICE 1000 released in PRE 45 km from its target, 9,000 m up, glides to it
# and destroys the unit there.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_raam.gd
extends "res://../tests/godot/base.gd"

const RAAM_FUEL_KG := 22665.0 * 0.45359
const SPICE := 1009


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
	check(settings().airframe(110).get("hud", "") == "f15e", "the Real HUD is the F-15E's")
	check(
		ClassDB.class_call_static("IafRealHud", "real_view_px_per_deg", "f15e", Rect2(-98, -60, 196, 130)) < 6.0,
		"the Real view fits the F-15E's 28° × 21° field"
	)
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
		check(
			(
				names.has("PYTH-5")
				and names.has("BLU109")
				and names.has("GBU-28")
				and names.has("GBU-39")
				and names.has("SPICE1")
			),
			"F-15I lists PYTH-5, BLU109, GBU-28, GBU-39 and SPICE1: %s" % [names]
		)
		check(
			names.has("GBU-31") and not names.has("AIM-9X") and not names.has("GBU-38"),
			"the GBU-31; no AIM-9X / GBU-38 (open for the F-15I)"
		)
		for w in mw.weapons:
			if w.name == "BLU109" or w.name == "GBU-31":
				check(w.max == [0, 1, 1, 1, 1, 1, 1, 1, 0], "%s on B, C, D, E, F, G, H: %s" % [w.name, w.max])
			elif w.name == "GBU-28":
				check(w.max == [0, 1, 0, 0, 1, 0, 0, 1, 0], "GBU-28 on B, E, H: %s" % [w.max])
			elif w.name == "GBU-39":
				check(w.max == [0, 4, 0, 4, 4, 4, 0, 4, 0], "GBU-39 four on B, D, E, F, H: %s" % [w.max])
			elif w.name == "SPICE1":
				check(w.max == [0, 1, 0, 0, 0, 0, 0, 1, 0], "SPICE1 on B and H: %s" % [w.max])
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
	check(tv.cockpit.real_hud_key() == "f15e", "the cockpit's Real HUD key: %s" % tv.cockpit.real_hud_key())
	var g_limit := float(tv.flight.state().get("g_limit", 0.0))
	check(absf(g_limit - 8.1) < 0.01, "the F-15E HUD's allowable g is the row's +8.1: %.2f" % g_limit)
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
	_spice(tv)
	settings().f15_variant = "baz"
	check(settings().airframe(110).get("hud", "") == "", "Baz: the F-15A/C Real HUD (its cockpit's)")


## PRE, the briefing's target 45 km ahead, 9,000 m up at 250 m/s: in the SPICE's LAR (a JDAM's is far short); the
## bomb glides to the point, its TTI the flight's time, and destroys the unit there (docs/weapons.md §13.2).
func _spice(tv) -> void:
	var site := _ground_unit(tv)
	var n: int = tv.player_flight_number
	if site.is_empty():
		check(false, "a ground unit")
		return
	settings().gps_targets[n] = {1: [site.world.x, site.world.y, "SPICE"]}
	var w = airborne_case(tv, [0, 0, SPICE, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, SPICE, 1, 0, 0, 25, 235, 33, 120, 34, 60])
	var p: Vector3 = w._on_ground(Vector2(site.world.x, site.world.y))
	site.world = p
	site.alt = p.z
	tv.mission_entity_moved(site)
	var vel: Vector3 = tv.world_to_scene(Vector3(0, 250, 0)) - tv.world_to_scene(Vector3.ZERO)
	start_over(tv, w, p - Vector3(0, 45000, 0), vel, tv.player.fm_section, 9000.0)
	var t := 40.0
	w.update(t)
	w.nav_key(0)
	w.stores.cur = 1
	w.select_ag()
	t += 0.05
	w.update(t)
	var gps: Dictionary = w.ag.get("gps", {})
	check(
		gps.get("pre", false) and gps.get("aim", Vector3.INF).distance_to(p) < 1.0,
		"SPICE selected: the aim is the briefing's point (%s)" % gps.get("aim")
	)
	check(gps.get("in_range", false), "45 km out from 9,000 m: in the SPICE's range (%s)" % gps.get("lar"))
	var o: Dictionary = w.own()
	var jdam = load("res://weapons/modern_weapons.gd").JDAM
	check(not ClassDB.class_call_static("IafGpsBomb", "in_range", jdam, o.pos, o.vel, p), "a JDAM's is far short")
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
	check(w.gps_bombs.size() == 1 and w.gps_bombs[0].g.aim().distance_to(p) < 1.0, "the SPICE flies to the point")
	var t_rel := t
	t += 0.02
	w.update(t)
	var tti0 = tv.cockpit.weapons.get("gps_tti")
	for i in 4000:
		t += 0.2
		w.update(t)
		if w.gps_bombs.is_empty():
			break
	var flown := t - t_rel - 0.02
	check(tti0 != null and absf(float(tti0) - flown) < 1.0, "TTI at the release %s, flown %.1f s" % [tti0, flown])
	check(
		w.gps_bombs.is_empty() and int(site.state) != 1,
		"the SPICE glided %.0f s and destroyed the unit (state %d)" % [flown, int(site.state)]
	)
