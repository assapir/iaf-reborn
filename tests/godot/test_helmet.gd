# Helmet sight DASH (docs/weapons.md §5.4, docs/cockpit.md "HUD dash repeater"): in the free-look / padlock views the
# IR seeker can take a target within 6° of the camera axis when that axis is within the missile generation's cone of
# the nose (FUN_00461f10); the helmet display (FUN_00530b70) shows in cockpits with `[HUD] Dash` 1 once the head is
# turned ≥ 250 px aside / ≥ 200 px down, with the DASH attitude symbol (FUN_00539ac0).
extends "res://../tests/godot/base.gd"


func run() -> void:
	var Seeker = load("res://weapons/ir_seeker.gd")
	var Hud = load("res://cockpit/hud.gd")
	var sk = Seeker.new()
	# Own jet heading north (world X east, Y north, Z up); the head turned 50° right; a target on that axis, 4° up, 3 km.
	var view := Vector3(sin(deg_to_rad(50.0)), cos(deg_to_rad(50.0)), 0.0)
	var up4 := (view * cos(deg_to_rad(4.0)) + Vector3(0, 0, sin(deg_to_rad(4.0)))).normalized()
	var own := {"pos": Vector3.ZERO, "fwd": Vector3(0, 1, 0), "up": Vector3(0, 0, 1), "right": Vector3(1, 0, 0),
		"helmet": true, "view_fwd": view}
	var u := {"pos": up4 * 3000.0}
	for g in [[4, true], [3, false], [2, false], [1, false]]:
		sk.set_generation(g[0])
		check(sk.in_view(own, u) == g[1], "gen %d, head 50° off the nose: %s" % [g[0], "lock possible" if g[1] else "outside the cone"])
	sk.set_generation(4)
	var off := {"pos": (view * cos(deg_to_rad(8.0)) + Vector3(0, 0, sin(deg_to_rad(8.0)))).normalized() * 3000.0}
	check(not sk.in_view(own, off), "gen 4: a target 8° off the head axis is outside the 6° sight")
	own.helmet = false
	check(not sk.in_view(own, u), "not in free look / padlock: only 6° of the nose")
	own.helmet = true
	own.view_fwd = Vector3(0, 1, 0)
	check(sk.in_view(own, {"pos": Vector3(0, 3000, 100)}), "head forward: the nose case")

	# The DASH symbol: the attitude bar moves 1.5 px per degree of pitch, held at ±40°; blinking leaves the aircraft only.
	var bar_y = func(lines: Array) -> float: return lines[3][2].y
	check(is_equal_approx(bar_y.call(Hud.dash_symbol(10.0, 0.0, true)), 15.0), "DASH bar 1.5 px/deg (10° -> 15 px)")
	check(is_equal_approx(bar_y.call(Hud.dash_symbol(60.0, 0.0, true)), 60.0), "DASH bar held at 40°")
	check(Hud.dash_symbol(60.0, 0.0, false).size() == 3, "blink phase: the aircraft symbol only")

	# The helmet display needs `[HUD] Dash` 1: the F-16 has it, the Mirage not (docs/cockpit.md table).
	var dash_of = func(dir: String) -> int:
		return int(Settings().load_json(Settings().assets_dir().path_join("converted/cockpits").path_join(dir).path_join("cockpit.json")).get("HUD", {}).get("Dash", 0))
	check(dash_of.call("f16") == 1 and dash_of.call("mirage") == 0 and dash_of.call("cfir") == 0, "Dash: F-16 1, Mirage 0, Kfir 0")
