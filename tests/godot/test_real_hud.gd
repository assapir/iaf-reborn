# The Real HUD (ours, Extras > HUD; docs/cockpit.md "Real HUD", iaf_avionics::real_hud): off by default (the original
# HUD); switched on, the HUD draws the F-16 style symbology: the KCAS and altitude boxes, the scales, the heading scale,
# the data windows (mode, Mach, g, max g), the conformal ladder and the flight path marker in the field; the phase 2
# weapon cues through the bridge (the DLZ scale with the closure, the target range "F", the CCIP fall line, bingo).
extends "res://../tests/godot/base.gd"


func _texts(prims: Array) -> Array:
	return prims.filter(func(p): return p.k == "text").map(func(p): return String(p.text))


func run() -> void:
	var tv = await start_mission(-1)
	await frames(5)
	var hud = tv.cockpit.hud
	check(Settings().hud_style == "original" and hud.real_hud().is_empty(), "original HUD by default")
	Settings().hud_style = "real"
	await frames(3)
	var st: Dictionary = tv.cockpit.state
	var r: Dictionary = hud.real_hud()
	check(not r.is_empty() and r.outer.size() > 20 and r.field.size() > 10, "Real HUD: %d outer, %d field primitives"
		% [r.get("outer", []).size(), r.get("field", []).size()])
	var t := _texts(r.get("outer", []))
	check(t.has(str(int(round(float(st.ias_kt))))), "the KCAS box (%d kt in %s)" % [int(round(float(st.ias_kt))), str(t)])
	check(t.has("NAV"), "the master mode window: NAV")
	check(t.any(func(x): return x.begins_with(".") or x.begins_with("1.")), "the Mach window")
	check(r.field.any(func(p): return p.k == "circle"), "the flight path marker")
	await _save("real_hud.png")
	# Phase 2 cues: a target 15 NM away closing at 200 m/s inside an 18 / 2 NM DLZ, a CCIP pipper, 1000 lb of fuel.
	var rh = ClassDB.instantiate("IafRealHud")
	var cues: Dictionary = rh.frame(Rect2(-80, -70, 160, 140), {"kcas": 400.0, "alt_ft": 5000.0, "fpm": Vector2(0, 10),
		"horizon": Vector2(0, 10), "px_per_deg": 6.0, "master": "MRM", "target": {"range_m": 15.0 * 1852.0, "closure": 200.0},
		"dlz": [18.0 * 1852.0, 2.0 * 1852.0], "ccip": Vector2(5, 40), "fuel_lbs": 1000.0})
	var ct := _texts(cues.outer)
	check(ct.has("F 15.0") and ct.has("389") and ct.has("20"), "DLZ scale 20 NM, closure 389 kt, F 15.0 (%s)" % str(ct))
	check(ct.has("FUEL"), "bingo: FUEL below 1500 lb")
	check(cues.field.any(func(p): return p.k == "line" and p.b == Vector2(5, 40)), "the CCIP fall line to the pipper")
	Settings().hud_style = "original"
	await frames(2)
	check(hud.real_hud().is_empty(), "back to the original HUD")
