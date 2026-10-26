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
	check(settings().hud_style == "original" and hud.real_hud().is_empty(), "original HUD by default")
	settings().hud_style = "real"
	await frames(3)
	var st: Dictionary = tv.cockpit.state
	var r: Dictionary = hud.real_hud()
	# Directions in / behind the camera plane (head turned 90°+): far off-screen on their side, no engine error.
	var cam: Camera3D = hud.camera
	var side: Vector2 = hud._project(cam.global_basis.x)
	var back: Vector2 = hud._project(cam.global_basis.z)
	check(
		side.x > hud.size.x * 2.0 and back.is_finite() and not Rect2(Vector2.ZERO, hud.size).has_point(back),
		"the camera plane / behind project off-screen (%s, %s)" % [side, back]
	)
	check(
		not r.is_empty() and not r.sight and r.outer.size() > 20 and r.field.size() >= 8,
		"F-16 Real HUD: %d outer, %d field primitives" % [r.get("outer", []).size(), r.get("field", []).size()]
	)
	var t := _texts(r.get("outer", []))
	check(t.has(str(int(round(float(st.ias_kt))))) and t.has("C"), "the KCAS box and its C (%s)" % str(t))
	check(t.has("NAV") and t.has("%.2f" % float(st.mach)), "the mode and Mach windows")
	check(r.field.any(func(p): return p.k == "circle"), "the flight path marker")
	await frames(30)
	check(
		hud.cut.clip_contents and absf(hud.cut.size.y - tv.cockpit.panel_top()) < 1.0,
		"the Real HUD is cut at the panel's top edge (%.1f / %.1f)" % [hud.cut.size.y, tv.cockpit.panel_top()]
	)
	# Looking aside (the DASH): the layer is not cut.
	tv.cockpit.head = Vector2(1.0, 0.0)  # the view sets it every frame: checked within this one
	hud._process(0.0)
	check(
		tv.cockpit.dash() and not hud.cut.clip_contents,
		(
			"looking aside: the DASH layer is not cut (dash %s, pan %s, clip %s)"
			% [tv.cockpit.dash(), tv.cockpit.head_pan(), hud.cut.clip_contents]
		)
	)
	# … and the Real DASH (docs/real-hud.md "DASH helmet"): the helmet set in the DASH's green, not the original symbol.
	hud._real_frame = -1
	var d: Dictionary = hud.real_hud()
	check(
		not d.is_empty() and d.colour != null and _texts(d.outer).has(str(int(round(float(st.ias_kt))))),
		"looking aside: the F-16's Real DASH (%s)" % str(_texts(d.get("outer", [])))
	)
	# The symbols drawn over the Real HUD (ILS, weapons, BORE cross) take the frame's colour, not the HUD's (H).
	check(
		d.colour != null and hud._hc() == d.colour and hud._hc() != tv.cockpit.hud_colour(),
		"the helmet's own symbols in its green (%s, HUD %s)" % [hud._hc(), tv.cockpit.hud_colour()]
	)
	check(
		hud.real_dash("converted/cockpits/f15") and not hud.real_dash("converted/cockpits/lavi"),
		"the DASH: F-16 and F-15 only"
	)
	check(
		(
			hud.real_ils("converted/cockpits/f15")
			and hud.real_ils("converted/cockpits/lavi")
			and not hud.real_ils("converted/cockpits/f16")
		),
		"own ILS on the F-15 / Lavi Real HUD; the original's lines elsewhere"
	)
	tv.cockpit.head = Vector2.ZERO
	hud._process(0.0)
	# No ILS reading yet (a flight's first frame): the Real HUD gets none, not a made-up zero that reads as on the
	# glide slope (the F-15's capture latched on it).
	var gear: bool = tv.cockpit.gear_handle_down
	var ils = tv.cockpit.state.get("ils")
	tv.cockpit.gear_handle_down = true
	tv.cockpit.state.erase("ils")
	hud._real_frame = -1
	hud.real_hud()
	var none_first: bool = hud._real_in.get("ils", 0) == null
	tv.cockpit.state["ils"] = Vector2(0.5, -1.0)
	hud._real_frame = -1
	hud.real_hud()
	check(
		none_first and hud._real_in.ils != null,
		"no ILS reading: none for the Real HUD, then the bars (mode %d, %s)" % [hud._mode(), str(hud._real_in.ils)]
	)
	tv.cockpit.gear_handle_down = gear
	if ils != null:
		tv.cockpit.state["ils"] = ils
	hud._real_frame = -1
	await _save("real_hud.png")
	settings().hud_style = "original"
	await frames(2)
	check(hud.real_hud().is_empty(), "back to the original HUD")
	check(not hud.cut.clip_contents, "the original HUD draws over the panel")

	# Every jet's display through the bridge.
	var base := {
		"kcas": 400.0,
		"ground_kt": 420.0,
		"tas_ms": 220.0,
		"alt_ft": 5000.0,
		"agl_ft": 4800.0,
		"vs_fpm": -1125.0,
		"heading": 270.0,
		"mach": 0.74,
		"g": 1.8,
		"fuel_lbs": 1000.0,
		"bingo_lbs": 1500.0,
		"fpm": Vector2(0, 10),
		"horizon": Vector2(0, 10),
		"boresight": Vector2(0, -20),
		"gun_cross": Vector2(0, -30),
		"px_per_deg": 12.0,
		"steerpoint": {"number": 1, "bearing": 280.0, "dist_m": 5.0 * 1852.0, "eta_s": 35.0, "at": Vector2(20, 30)},
		"target": {"range_m": 15.0 * 1852.0, "closure": 200.0, "at": Vector2(5, -5)},
		"dlz": [18.0 * 1852.0, 2.0 * 1852.0],
		"weapons": {"hud_mode": 2, "mrm": 4, "srm": 2, "circle": 4.0}
	}
	var field := Rect2(-80, -70, 160, 140)
	var rh = ClassDB.instantiate("IafRealHud")
	var f16: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f16"}))
	var ft := _texts(f16.outer)
	check(
		ft.has("4 MRM") and ft.has("ARM") and ft.has("F15.0") and ft.has("390>") and ft.has("FUEL"),
		"F-16 MRM: 4 MRM, ARM, F15.0, the DLZ closure, FUEL (%s)" % str(ft)
	)
	var kfir: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/cfir"}))
	var kt := _texts(kfir.outer)
	check(
		kt.has("MSL") and kt.has("D5.0") and kt.has("WP1") and not kt.has("FUEL") and not kt.has("ARM"),
		"the Kfir draws its own HUD (MSL, D5.0, WP1; no F-16 windows): %s" % str(kt)
	)
	var lavi: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/lavi"}))
	var lt := _texts(lavi.outer)
	check(
		lt.has("MRM 4") and lt.has("WP 1") and lt.has("5.0 NM") and not lt.has("4 MRM"),
		"the Lavi draws its own HUD, not the F-16's (%s)" % str(lt)
	)
	var k2: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f4-2000"}))
	var tk := _texts(k2.outer)
	check(tk.has("MRM") and not tk.has("4 MRM") and tk.has("FUEL"), "the Kurnass 2000 draws its own HUD (%s)" % str(tk))
	var f15: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/f15"}))
	var t15 := _texts(f15.outer)
	check(
		t15.has("1   NAV") and t15.has("N 5.0") and t15.has("1.8G") and t15.has("IN RNG") and t15.has("400"),
		"F-15: the NAV window, 1.8G, IN RNG, full-value airspeed labels (%s)" % str(t15)
	)
	var f35: Dictionary = rh.frame(field, base.merged({"cockpit": "res://extra/planes/f35i/cockpit"}))
	var t35 := _texts(f35.outer)
	check(
		t35.has("GS 420") and t35.has("AA1") and t35.has("4 AIM-A") and t35.has("-1125") and f35.colour != null,
		"F-35 helmet: GS, AA1, 4 AIM-A, the vertical velocity, green (%s)" % str(t35)
	)
	var off: Dictionary = rh.frame(
		field,
		base.merged({"cockpit": "res://extra/planes/f35i/cockpit", "off_boresight": true, "head_heading": 90.0}, true)
	)
	var to := _texts(off.outer)
	check(
		to.has("400") and to.has("090") and not to.has("GS 420"),
		"F-35 looking off the nose: the head set only (%s)" % str(to)
	)
	for c in [["phantom", "F-4E ASG-26"], ["mirage", "Mirage CSF"]]:
		var s: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/" + c[0]}))
		check(
			s.sight and s.outer.is_empty() and _texts(s.field).is_empty() and s.colour != null,
			"%s: a reticle only, no HUD text, its lamp colour" % c[1]
		)
	var gun: Dictionary = rh.frame(
		field,
		base.merged(
			{
				"cockpit": "converted/cockpits/f16",
				"weapons": {"hud_mode": 3},
				"target": {"range_m": 600.0, "closure": 100.0, "at": Vector2(5, -5)}
			},
			true
		)
	)
	check(
		_texts(gun.outer).has("EEGS") and gun.field.filter(func(p): return p.k == "line").size() > 30,
		"F-16 A-A gun: EEGS and the funnel"
	)
	var ccip: Dictionary = rh.frame(
		field,
		base.merged(
			{"cockpit": "converted/cockpits/f16", "target": {}, "weapons": {"hud_mode": 5, "pipper": Vector2(5, 40)}},
			true
		)
	)
	check(ccip.field.any(func(p): return p.k == "line" and p.b == Vector2(5, 40)), "F-16 CCIP: the bomb fall line")

	# The MiGs (docs/mig-cockpits.md §5–6): the MiG-23's АСП-17МЛ sight (no flight numbers; the range scale in km) and
	# the MiG-29's ИЛС-31 (km/h, m, the heading in tens, ДВБ with the range scale in km), Cyrillic in the HUD's font.
	var m23: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/mig23"}))
	var t23 := _texts(m23.outer)
	check(
		not m23.sight and t23.has("45") and t23.has("28") and not t23.has("400") and not t23.has("ARM"),
		"MiG-23: the sight's km range scale, no airspeed, no F-16 windows (%s)" % str(t23)
	)
	var m29: Dictionary = rh.frame(field, base.merged({"cockpit": "converted/cockpits/mig29"}))
	var t29 := _texts(m29.outer)
	check(
		t29.has("741") and t29.has("1520") and t29.has("27") and t29.has("ДВБ") and t29.has("50") and t29.has("28"),
		"MiG-29: 741 km/h, 1520 m, heading 27, ДВБ, the 50 km scale with the target at 28 km (%s)" % str(t29)
	)
	var m29h: Dictionary = rh.frame(
		field, base.merged({"cockpit": "converted/cockpits/mig29", "off_boresight": true, "head_rel": Vector2(-30, 5)})
	)
	check(
		_texts(m29h.outer).has("ШЛЕМ") and hud.real_dash("converted/cockpits/mig29"),
		"MiG-29 looking aside: the Щель-3УМ helmet sight (%s)" % str(_texts(m29h.outer))
	)
	var font: SystemFont = hud.Img.arial()
	var legends := "ДВБПРОТВШЛЕМНОПКГМРШЗЯФ"
	var missing := Array(legends.split("")).filter(func(c): return not font.has_char(c.unicode_at(0)))
	check(missing.is_empty(), "the HUD font has the Cyrillic legends' glyphs (missing %s)" % str(missing))
