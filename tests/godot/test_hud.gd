# HUD (docs/cockpit.md "HUD"): the gun cross at GunRetPositionY (v1.1), the v1.1 value also with v1.0
# cockpit data (−10 px on the five cockpits v1.1 changed); the v1.1 pitch ladder hangs off the flight
# path marker at 12 px/deg, 7 rungs ±15°, rolled with the jet; the conformal ladder is our option.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(-1)
	await frames(5)
	var cp = tv.cockpit
	var hud = cp.hud
	var s: float = cp.ui_scale()
	var h: Dictionary = cp.layout.HUD
	check(cp.cockpit_dir.get_file() == "f16", "F-16 cockpit")
	var y: float = h.GunRetPositionY
	check(y == 140.0 or y == 150.0, "F-16 GunRetPositionY is the v1.1 (140) or v1.0 (150) value (%.0f)" % y)
	check(absf(hud.gun_cross().y - (cp.panel_top() - 140.0 * s)) < 0.01, "gun cross 140 px above the panel top (v1.1)")
	h.GunRetPositionY = 150.0
	check(absf(hud.gun_cross().y - (cp.panel_top() - 140.0 * s)) < 0.01, "v1.0 data (150): the cross still at the v1.1 140")
	h.GunRetPositionY = 133.0
	check(absf(hud.gun_cross().y - (cp.panel_top() - 133.0 * s)) < 0.01, "any other value is used as is")
	h.GunRetPositionY = y
	check(absf(hud.gun_cross().y - cp.boresight().y) > 0.1, "the gun cross is not the boresight")

	# v1.1 ladder: γ = 3°, wings level: the horizon 36 px (×s) below the marker, rung 5 24 px above,
	# 7 rungs from 15 down to -15.
	var fpm := Vector2(100, 100)
	var rungs: Array = hud.ladder_rungs(fpm, 3.0, 0.0, s)
	var angles := rungs.map(func(r): return r[0])
	check(angles == [15, 10, 5, 0, -5, -10, -15], "7 rungs 15..-15 (%s)" % str(angles))
	var at := {}
	for r in rungs:
		at[r[0]] = r[1]
	check(at[0].distance_to(fpm + Vector2(0, 36) * s) < 0.01, "horizon 3° × 12 px below the marker")
	check(at[5].distance_to(fpm + Vector2(0, -24) * s) < 0.01, "5° rung 2° × 12 px above the marker")
	# Rolled 90° right: the rungs line up to the side of the marker (up = screen left).
	rungs = hud.ladder_rungs(fpm, 0.0, 90.0, s)
	at = {}
	for r in rungs:
		at[r[0]] = r[1]
	check(at[10].distance_to(fpm + Vector2(-120, 0) * s) < 0.01, "rolled 90° right: the 10° rung 120 px to the left")
	# Past ±90°, no rungs.
	check(hud.ladder_rungs(fpm, 88.0, 0.0, s).all(func(r): return absi(r[0]) <= 90), "no rung beyond 90°")

	check(Settings().hud_ladder == "original", "the original (v1.1) ladder is the default")
	Settings().hud_ladder = "conformal"
	hud.queue_redraw()
	await frames(2)
	check(true, "conformal ladder draws")
	Settings().hud_ladder = "original"
