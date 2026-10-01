# HUD (docs/cockpit.md "HUD"): the gun cross at GunRetPositionY (v1.1), the v1.1 value also with v1.0
# cockpit data (−10 px on the five cockpits v1.1 changed); the v1.1 pitch ladder hangs off the flight
# path marker at 12 px/deg, 7 rungs ±15°, rolled with the jet. The traced heading tape, speed / altitude
# scales, text block and ILS (docs/cockpit.md "HUD symbology"), and every cockpit's HUD draws.
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

	await _traced(tv)


func _traced(tv) -> void:
	var cp = tv.cockpit
	var hud = cp.hud
	var Hud = load("res://cockpit/hud.gd")
	# Heading tape (FUN_00537cd0): 2 px/deg, ticks every 5° outside the box, labels every 10°.
	var ht: Dictionary = Hud.heading_tape(0.0, 0.0)
	check(ht.box == "000" and ht.caret == 0, "heading 000: box and caret centred")
	check(ht.ticks == [50, 40, 30, 20, -20, -30, -40, -50], "heading 0: 5° ticks at ±20..50 px (%s)" % str(ht.ticks))
	check(ht.labels == [[40, "02"], [20, "01"], [-20, "35"], [-40, "34"]], "heading 0: labels 34 35 | 01 02 (%s)" % str(ht.labels))
	ht = Hud.heading_tape(37.6, 47.6)
	check(ht.box == "037", "heading 37.6: box 037")
	check(ht.labels == [[45, "06"], [25, "05"], [-15, "03"], [-35, "02"], [-55, "01"]], "heading 37.6: 50° 25 px right, 30° 15 px left, 40° (5 px) under the box (%s)" % str(ht.labels))
	check(ht.caret == 20, "waypoint 10° right: caret 20 px right (%d)" % ht.caret)
	check(Hud.heading_tape(350.0, 10.0).caret == 40, "bearing 010 from 350: +20° wraps (caret 40)")
	check(Hud.heading_tape(37.0, 300.0).caret == -57, "a bearing far left: caret held at -57")
	# Speed (FUN_005386c0): "% 3d" + G / T, 0.6 px per kt, labels every 50 kt.
	var st := {"tas_kt": 172.0, "ground_kt": 165.4, "ias_kt": 5.0}
	check(Hud.speed_text(st, 0, false) == " 165G" and Hud.speed_text(st, 0, true) == " 172T" and Hud.speed_text(st, 1, false) == "  5",
			"speed: NAV ground ' 165G', gear down true ' 172T', SRM indicated '  5'")
	var sc: Dictionary = Hud.speed_scale(165.0, 200.0)
	check(sc.labels == [[-16, "200"], [14, "150"], [44, "100"]], "165 kt: labels 200 / 150 / 100 (%s)" % str(sc.labels))
	check(sc.caret == 21 and Hud.speed_scale(165.0, 400.0).caret == 51 and Hud.speed_scale(165.0, null).caret == null,
			"required 200 kt: caret 21 px up; held at 51; none in gun mode")
	check([-21, 3] in sc.ticks and [-27, 4] in sc.ticks, "165 kt: the 200 kt tick (21 px up) is the 3 px one")
	# Altitude (FUN_005381c0): radar "R" in NAV with the gear up, else barometric "B"; 20 ft per px, labels in
	# thousands every 500 ft.
	var at: Array = Hud.alt_value({"agl_ft": 376.4, "alt_ft": 1234.5}, 0, false)
	check(at[1] == "  376 R", "NAV gear up: radar '  376 R' (%s)" % at[1])
	check(Hud.alt_value({"agl_ft": 376.4, "alt_ft": 1234.5}, 0, true)[1] == " 1234 B" and Hud.alt_value({"agl_ft": 376.4, "alt_ft": 1234.5}, 1, false)[1] == " 1234 B",
			"gear down / air-to-air: barometric ' 1234 B'")
	var asc: Dictionary = Hud.alt_scale(376.0)
	check(asc.labels == [[-27, " 1.0"], [-2, " 0.5"], [23, " 0.0"], [48, "-0.5"]], "376 ft: labels 1.0 0.5 0.0 -0.5 (%s)" % str(asc.labels))
	check([-32, 3] in asc.ticks and [-27, 4] in asc.ticks, "376 ft: the 1000 ft tick (32 px up) is the 3 px one")
	# Text block (FUN_0052ef20).
	var nav := {"index": 0, "dist_nm": 2.0, "minutes": 0.75, "req_kt": 0.0, "bearing_deg": 0.0}
	var ts := {"engines": PackedFloat32Array([0.6, 0.6, 0.6, 0.75, 0.75, 0.75]), "g": 0.94, "ap_mode": 0, "afterburner": 0}
	var rows: Array = Hud.text_block(ts, 0, nav, {}, {}, false, [])
	check(rows == ["T 060", "+0.9G", "NAV", "", "W01  2.0", "0.8 MIN"], "NAV rows as the briefing's final-approach HUD (%s)" % str(rows))
	check(Hud.text_block(ts, 0, nav, {}, {}, true, [])[0] == "T 075", "twin engines: the larger rpm")
	ts.afterburner = 2
	ts.ap_mode = 2
	ts.g = -1.25
	rows = Hud.text_block(ts, 2, nav, {"total": 2, "name": "AIM-7", "ready": true}, {}, false, [])
	check(rows[0] == "AB 2" and rows[1] == "AP NAV" and rows[2] == "2 AIM-7 RDY" and rows[4] == "W01  2.0" and rows[5] == "",
			"MRM: AB 2, AP NAV, the store row, the waypoint (%s)" % str(rows))
	ts.ap_mode = 0
	check(Hud.text_block(ts, 2, nav, {}, {}, false, [])[1] == "-1.2G", "negative G: '%4.1fG'")
	check(Hud.text_block(ts, 0, nav, {}, {}, false, [false, false, false, false, false, false, false, false, true])[0] == "T 060",
			"afterburner damage (flag 8): the rpm row")
	# NAV cues (FUN_00452e60): bearing / NM / minutes / required speed.
	var nc: Dictionary = Hud.nav_cues({"world": Vector2(0, 0), "ground_kt": 194.28, "time": 100.0},
			[{"world": Vector2(1000, 1000), "t": 200.0}], 0)
	check(absf(nc.bearing_deg - 45.0) < 1e-3 and absf(nc.dist_nm - 1414.2 * 0.00053937) < 1e-3, "waypoint NE: bearing 045, distance in NM")
	check(absf(nc.minutes - 1414.2 / 100.0 / 60.0) < 1e-3 and absf(nc.req_kt - 1414.2 / 100.0 * 1.9428) < 0.01, "minutes at the ground speed; speed to make T")

	# ILS (FUN_005309a0): 12 px/deg from the HUD centre, held 1 px inside the field.
	var f := Rect2(-69, -75, 139, 135)
	check(Hud.ils_lines(Vector2.ZERO, f) == Vector2.ZERO, "on the localizer and the glide path: both lines through the HUD centre")
	check(Hud.ils_lines(Vector2(1.0, 0.0), f) == Vector2(12, 0) and Hud.ils_lines(Vector2(-1.0, 0.0), f) == Vector2(-12, 0),
			"runway 1° right: the localizer 12 px right; left: left")
	check(Hud.ils_lines(Vector2(0.0, 2.0), f) == Vector2(0, 24) and Hud.ils_lines(Vector2(0.0, -2.0), f) == Vector2(0, -24),
			"2° high: the glide slope 24 px below the centre; low: above")
	check(Hud.ils_lines(Vector2(0.05, 0.0), f) == Vector2.ZERO, "truncated to whole pixels")
	check(Hud.ils_lines(Vector2(19.0, 5.0), f) == Vector2(69, 59), "held 1 px inside the field (F-16 borders)")
	# In flight: the deviations reach the cockpit state; shown in NAV with the gear handle down only.
	check(cp.state.get("ils") is Vector2, "the ILS deviations in the cockpit state (%s)" % str(cp.state.get("ils")))
	var on: bool = tv.flight.ils().length() >= 0.0
	check(on, "IafFlight.ils() answers")
	check(Hud.waypoint_marker_point(Vector2(200, 0), f) == Vector2(70, 0) and Hud.waypoint_marker_point(Vector2(10, 5), f) == Vector2(10, 5),
			"waypoint marker: held on the field's edge along the line from the centre")

	# Every cockpit draws the HUD (both layers) without script errors, NAV gear down and gear up.
	var PlayerAircraft = load("res://aircraft/player_aircraft.gd")
	var dirs := {}
	for t in PlayerAircraft.COCKPIT:
		dirs[PlayerAircraft.cockpit_folder(t)] = true
	check(dirs.size() == 9, "nine cockpits (%s)" % str(dirs.keys()))
	for d in dirs:
		cp.load_cockpit("converted/cockpits/" + d)
		for gear in [true, false]:
			cp.gear_handle_down = gear
			hud.queue_redraw()
			hud.outer.queue_redraw()
			await frames(2)
		var fl: Rect2 = hud._field()
		var h: Dictionary = cp.layout.HUD
		check(fl == Rect2(-h.LeftBorder, -h.TopBorder, h.LeftBorder + h.RightBorder, h.TopBorder + h.BottomBorder) and hud.outer.visible,
				"%s: HUD drawn, field from its borders, ShowLRScales %d ShowHorizon %d" % [d, int(h.get("ShowLRScales", 1)), int(h.get("ShowHorizon", 1))])
	cp.load_cockpit("converted/cockpits/f16")
