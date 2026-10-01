# HUD (docs/cockpit.md "HUD"): the gun cross at GunRetPositionY (v1.1), the v1.1 value also with v1.0
# cockpit data (−10 px on the five cockpits v1.1 changed); the v1.1 pitch ladder hangs off the flight
# path marker at 12 px/deg, 7 rungs ±15°, rolled with the jet.
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


	# The original 3D projection (docs/cockpit.md "3D view"): 50° across 640 px, centred on the
	# viewport above the panel (F-16: rows 0..296, centre 42 px above the panel top), 5.5° below the nose.
	check(absf(cp.focal_length() - 686.2414 * s) < 0.01 * s, "focal length 320 / tan 25° = 686.2 px (×s)")
	check(cp._view_bottom == 296.0, "F-16 viewport bottom 296 (D 104 + MainOffsetY 190 + 7, & ~7) (%.0f)" % cp._view_bottom)
	var c: Vector2 = cp.projection_centre()
	check(absf(c.y - (cp.panel_top() - 42.0 * s)) < 0.01, "projection centre 296/2 − 190 = 42 px above the panel top")
	tv.in_cockpit = true
	tv._apply_view()
	var cam: Camera3D = tv.camera
	var axis := cam.unproject_position(cam.global_position - cam.global_basis.z * 1000.0)
	check(axis.distance_to(c) < 0.5, "the camera axis projects on the projection centre (%s vs %s)" % [axis, c])
	var nose := cam.unproject_position(cam.global_position - tv.rig.global_basis.z * 1000.0)
	check(absf(nose.y - (c.y - cp.focal_length() * tan(deg_to_rad(5.5)))) < 0.5, "the nose 5.5° above the centre")
	var up := cam.unproject_position(cam.global_position + (-cam.global_basis.z + cam.global_basis.y * tan(deg_to_rad(10.0))) * 1000.0)
	check(absf((c.y - up.y) - cp.focal_length() * tan(deg_to_rad(10.0))) < 0.5, "10° above the axis: f·tan 10° (square pixels)")
	# Level flight and 10° nose up: the v1.1 ladder's horizon rung on the world's horizon (the rungs are
	# linear, 12 px/deg, so rungs far from the centre differ from the perspective by a few pixels, as in the original).
	for pitch in [0.0, 10.0]:
		tv.rig.global_basis = Basis.from_euler(Vector3(deg_to_rad(pitch), 0, 0))
		hud.velocity_dir = -tv.rig.global_basis.z
		var fpm2: Vector2 = hud._fpm_position() + hud.position
		var r := {}
		for rr in hud.ladder_rungs(fpm2, pitch, 0.0, s):
			r[rr[0]] = rr[1]
		var horizon := cam.unproject_position(cam.global_position + Vector3(0, 0, -1) * 100000.0)
		check(absf(r[0].y - horizon.y) < 0.5 * s, "pitch %d°: the horizon rung on the world's horizon (%.2f vs %.2f)" % [pitch, r[0].y, horizon.y])
		check(r[int(pitch)].distance_to(fpm2) < 0.01, "pitch %d°: the %d° rung through the marker" % [pitch, pitch])
	# Our conformal ladder (Extras): at 20° nose up the horizon rung is exactly on the world's horizon,
	# where the linear v1.1 rung is a few pixels off.
	tv.rig.global_basis = Basis.from_euler(Vector3(deg_to_rad(20.0), 0, 0))
	var hz := cam.unproject_position(cam.global_position + Vector3(0, 0, -1) * 100000.0)
	var conf := {}
	for rr in hud.conformal_rungs(0.0):
		conf[rr[0]] = rr[1] + hud.position
	check(absf(conf[0].y - hz.y) < 0.5, "conformal: the horizon rung on the world's horizon at 20° (%.2f vs %.2f)" % [conf[0].y, hz.y])
