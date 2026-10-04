# The Real HUD (ours, Extras > HUD; docs/real-hud.md, iaf_avionics::real_hud): off by default (the original HUD);
# switched on, the F-16 draws its dash-34 symbology (boxed airspeed with "C", the altitude box, the heading box, the
# data windows, the ladder and the marker). Through the bridge, every jet's own display: the F-15's tapes and NAV
# window, the F-35's helmet blocks, the F-4E's and the Mirage's gunsight reticles (sight only, in their colours), and
# the weapon cues (DLZ with closure, target range, EEGS funnel, CCIP fall line, bingo), the F-35's off-boresight set.
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
	check(not r.is_empty() and not r.sight and r.outer.size() > 20 and r.field.size() >= 8,
		"F-16 Real HUD: %d outer, %d field primitives" % [r.get("outer", []).size(), r.get("field", []).size()])
	var t := _texts(r.get("outer", []))
	check(t.has(str(int(round(float(st.ias_kt))))) and t.has("C"), "the KCAS box and its C (%s)" % str(t))
	check(t.has("NAV") and t.has("%.2f" % float(st.mach)), "the mode and Mach windows")
	check(r.field.any(func(p): return p.k == "circle"), "the flight path marker")
	await _save("real_hud.png")
	Settings().hud_style = "original"
	await frames(2)
	check(hud.real_hud().is_empty(), "back to the original HUD")

	# Every jet's display through the bridge.
	var base := {"kcas": 400.0, "ground_kt": 420.0, "tas_ms": 220.0, "alt_ft": 5000.0, "agl_ft": 4800.0, "vs_fpm": -1125.0,
		"heading": 270.0, "mach": 0.74, "g": 1.8, "fuel_lbs": 1000.0, "fpm": Vector2(0, 10), "horizon": Vector2(0, 10),
		"boresight": Vector2(0, -20), "gun_cross": Vector2(0, -30), "px_per_deg": 12.0,
		"steerpoint": {"number": 1, "bearing": 280.0, "dist_m": 5.0 * 1852.0, "eta_s": 35.0, "at": Vector2(20, 30)},
		"target": {"range_m": 15.0 * 1852.0, "closure": 200.0, "at": Vector2(5, -5)},
		"dlz": [18.0 * 1852.0, 2.0 * 1852.0], "weapons": {"hud_mode": 2, "mrm": 4, "srm": 2, "circle": 4.0}}
	var field := Rect2(-80, -70, 160, 140)
	var rh = ClassDB.instantiate("IafRealHud")
	var f16: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f16"}))
	var ft := _texts(f16.outer)
	check(ft.has("4 MRM") and ft.has("ARM") and ft.has("F15.0") and ft.has("390>") and ft.has("FUEL"),
		"F-16 MRM: 4 MRM, ARM, F15.0, the DLZ closure, FUEL (%s)" % str(ft))
	var lavi: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/lavi"}))
	check(_texts(lavi.outer).has("4 MRM"), "the Lavi draws the F-16's HUD")
	var f15: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f15"}))
	var t15 := _texts(f15.outer)
	check(t15.has("1   NAV") and t15.has("N 5.0") and t15.has("1.8G") and t15.has("IN RNG") and t15.has("400"),
		"F-15: the NAV window, 1.8G, IN RNG, full-value airspeed labels (%s)" % str(t15))
	var f35: Dictionary = rh.frame(field, base.merged({"cockpit": "res://extra/planes/f35i/cockpit"}))
	var t35 := _texts(f35.outer)
	check(t35.has("GS 420") and t35.has("AA1") and t35.has("4 AIM-A") and t35.has("-1125") and f35.colour != null,
		"F-35 helmet: GS, AA1, 4 AIM-A, the vertical velocity, green (%s)" % str(t35))
	var off: Dictionary = rh.frame(field, base.merged({"cockpit": "res://extra/planes/f35i/cockpit", "off_boresight": true,
		"head_heading": 90.0}, true))
	var to := _texts(off.outer)
	check(to.has("400") and to.has("090") and not to.has("GS 420"), "F-35 looking off the nose: the head set only (%s)" % str(to))
	for c in [["phantom", "F-4E ASG-26"], ["mirage", "Mirage CSF"]]:
		var s: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/" + c[0]}))
		check(s.sight and s.outer.is_empty() and _texts(s.field).is_empty() and s.colour != null,
			"%s: a reticle only, no HUD text, its lamp colour" % c[1])
	var gun: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f16",
		"weapons": {"hud_mode": 3}, "target": {"range_m": 600.0, "closure": 100.0, "at": Vector2(5, -5)}}, true))
	check(_texts(gun.outer).has("EEGS") and gun.field.filter(func(p): return p.k == "line").size() > 30,
		"F-16 A-A gun: EEGS and the funnel")
	var ccip: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f16", "target": {},
		"weapons": {"hud_mode": 5, "pipper": Vector2(5, 40)}}, true))
	check(ccip.field.any(func(p): return p.k == "line" and p.b == Vector2(5, 40)), "F-16 CCIP: the bomb fall line")
