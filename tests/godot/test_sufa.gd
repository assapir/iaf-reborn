# The Extras switch "F-16 version" on Sufa (docs/f16i.md): every F-16 (type 100), the player's and the AI's, flies the
# F-16I row (8,850 lb internal fuel) and gets the APG-68(V)9's ranges.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_sufa.gd
extends "res://../tests/godot/base.gd"

const SUFA_FUEL_KG := 8850.0 * 0.45359


func run() -> void:
	settings().f16_variant = "sufa"
	var real_weapons = load("res://weapons/real_weapons.gd")
	var combat = load("res://ai/combat.gd")
	check(absf(real_weapons.radar_nm(100) * 1854.0 - 104000.0) < 1.0, "Real F-16I (APG-68(V)9): 104 km")
	check(combat.sensor_nm(100) == 52.0, "AI F-16I sensor: 52 NM")
	check(combat.sensor_nm(110) == 40.0, "AI F-15 sensor unchanged: 40 NM")
	var tv = await start_mission(221)  # Back to the Wall: Alpha and Bravo, two F-16s each
	await frames(5)
	var fuel: float = tv.flight.state().internal_fuel_kg
	check(absf(fuel - SUFA_FUEL_KG) < 1.0, "player F-16I: internal fuel %.0f kg" % fuel)
	var lrs: Dictionary = tv.weapons.radar.modes.get(tv.weapons.radar.LRS, {})
	check(float(lrs.get("nm", 0.0)) == 58.0, "player radar LRS 58 NM: %s" % lrs)
	var ai_f16: Array = tv.ai.pilots.filter(func(p): return int(p.ent.type_code) == 100)
	check(not ai_f16.is_empty(), "an AI F-16 flies")
	for p in ai_f16:
		var f: float = p.flight.state().internal_fuel_kg
		check(absf(f - SUFA_FUEL_KG) < 1.0, "AI %s F-16I: internal fuel %.0f kg" % [p.ent.name, f])
	check(load("res://menu/tsd.gd").unit_label({"type": 100, "cls": 2, "name": ""}) == "F-16I", "TSD names it F-16I")
