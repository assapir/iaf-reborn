# The Real HUD (ours, Extras > HUD; docs/cockpit.md "Real HUD", iaf_avionics::real_hud): off by default (the original
# HUD); switched on, the HUD draws the F-16 style symbology: the KCAS and altitude boxes, the scales, the heading scale,
# the data windows (mode, Mach, g, max g), the conformal ladder and the flight path marker in the field.
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
	Settings().hud_style = "original"
	await frames(2)
	check(hud.real_hud().is_empty(), "back to the original HUD")
