# The EO / HARM MFD pages (docs/mfd.md "FLIR (6), TV (5)", "HARM (10)"): the pure EO camera rules (start, slew
# rate 0.09·x / zoom °/s, the gimbal limits per store class, zoom 1..8, WIDE / SPOT, the lock on release), the
# HARM list from RWR emitters, then mission 231 (F-16) with a FLIR pod, a POPEYE and a HARM on the pylons: I opens
# the FLIR page, Ctrl+Right slews it, the release locks; the POPEYE selects the TV page (weapon limits, RDY); the
# HARM page lists a synthetic emitter ahead; and every page draws on the F-16 and the Lavi cockpits.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var Eo = load("res://weapons/eo_sensor.gd")
	var Harm = load("res://weapons/harm_sensor.gd")
	var Mfd = load("res://cockpit/mfd.gd")
	# --- pure: the EO camera -----------------------------------------------------------------------
	var e = Eo.new()
	var base := Vector2.ZERO
	var eye := Vector3(0, 0, 3000)
	e.start(Eo.FLIR, true, null, 0.0)
	var ae: Vector2 = e.angles(0.0, base, eye)
	check(e.camera and e.zoom == 1.0 and is_equal_approx(ae.x, 0.0) and is_equal_approx(ae.y, deg_to_rad(-5.0)), "start: az 0, el −5°, zoom 1")
	e.pan(100, 0, 0.0, base, eye, null)
	ae = e.angles(1.0, base, eye)
	check(absf(rad_to_deg(ae.x) - 9.0) < 1e-3, "Pan right: 9°/s at zoom 1 (%.3f°)" % rad_to_deg(ae.x))
	ae = e.angles(10.0, base, eye)
	check(absf(rad_to_deg(ae.x) - 45.0) < 1e-3, "pod: az limit 45°")
	e.pan(0, -100, 10.0, base, eye, Vector3(0, 5000, 0))
	check(e.track == Eo.FREE, "a changed key pair slews (no lock while a key is held)")
	ae = e.angles(30.0, base, eye)
	check(absf(rad_to_deg(ae.y) + 80.0) < 1e-3 and absf(rad_to_deg(ae.x) - 45.0) < 1e-3, "pod: el limit −80°, az stays at its clamp")
	e.pan(0, 100, 30.0, base, eye, null)
	ae = e.angles(100.0, base, eye)
	check(absf(rad_to_deg(ae.y) - 30.0) < 1e-3, "pod: el limit +30°")
	e.zoom_step(true)
	check(e.zoom == 2.0 and absf(rad_to_deg(e.rate.y) - 4.5) < 1e-3, "zoom in: ×2, the slew rate halves")
	e.wide_spot()
	check(e.spot and e.zoom == 8.0, "SPOT: three steps in, at most 8")
	e.wide_spot()
	check(not e.spot and e.zoom == 1.0, "WIDE: three steps out, at least 1")
	e.pan(0, 0, 100.0, base, eye, Vector3(1000, 1000, 3000 - 1000 * sqrt(2.0)))
	ae = e.angles(100.0, base, eye)
	check(e.track == Eo.TRACK and absf(rad_to_deg(ae.x) - 45.0) < 1e-3 and absf(rad_to_deg(ae.y) + 45.0) < 1e-3, "FLIR: releasing the keys locks the centre point (tracked: 45° right, 45° down)")
	ae = e.angles(100.0, Vector2(deg_to_rad(10.0), 0.0), eye)
	check(absf(rad_to_deg(ae.x) - 35.0) < 1e-3, "tracking follows the jet's turn (heading 10°: az 35°)")
	e.pan(-100, 0, 100.0, Vector2(deg_to_rad(10.0), 0.0), eye, null)
	check(e.track == Eo.FREE and e.frozen != null, "a slew from tracking: free, the base frozen")
	var f: Dictionary = e.flir_page(Vector2(deg_to_rad(45.0), deg_to_rad(-5.0)), 40000.0)
	check(absf(f.u - 1.0) < 1e-4 and absf(f.v) < 1e-4 and f.range == "XXX.X", "FLIR page: 45° = u 1 (56 px), −5° = v 0; 40 km (≥ 20 NM) = XXX.X")
	check(e.flir_page(Vector2.ZERO, 1853.0 * 12.34).range == "12.3", "range %3.1f NM")
	e.laser_key(false)
	check(not e.laser, "laser: needs the pod")
	e.laser_key(true)
	check(e.laser, "laser on with the pod")
	var tvs = Eo.new()
	tvs.start(Eo.TV, false, null, 0.0)
	tvs.pan(100, 100, 0.0, base, eye, null)
	ae = tvs.angles(100.0, base, eye)
	check(absf(rad_to_deg(ae.x) - 30.0) < 1e-3 and absf(rad_to_deg(ae.y) - 15.0) < 1e-3, "weapon: az ±30°, el +15°")
	tvs.pan(0, 0, 100.0, base, eye, Vector3.ZERO)
	check(tvs.track == Eo.FREE and tvs.angles(200.0, base, eye) == ae, "TV before launch: releasing stops the slew (no lock)")
	var tp: Dictionary = tvs.tv_page(Vector2(deg_to_rad(30.0), 0.0), 1)
	check(absf(tp.u - 1.0) < 1e-4, "TV page: 30° = u 1 (56 px)")

	# --- pure: the HARM list ---------------------------------------------------------------------------
	var h = Harm.new()
	h.active = true
	var slots := [
		{"unit": "sam", "type": 300, "pos": Vector3(1000, 20000, 0), "active": true},
		{"unit": "off", "type": 290, "pos": Vector3(20000, 20000, 0), "active": true},
		{"unit": "", "type": 0, "pos": Vector3.ZERO, "active": false},
	]
	h.capture(slots, Vector3(0, 0, 3000), Vector2.ZERO)
	var pg: Dictionary = h.page(Vector2.ZERO, 2)
	check(pg.list.size() == 1 and pg.list[0].key == "sam" and pg.list[0].selected, "HARM: the emitter inside ±15° is listed and preselected, the one at 45° not")
	var sy: Array = Mfd.harm_symbols(pg)
	var want := Vector2(66 + int(atan2(1000.0, 20000.0) * 112.0 / deg_to_rad(30.0)), 66 + int(-atan2(-3000.0, Vector2(1000, 20000).length()) * 112.0 / deg_to_rad(30.0)))
	check(sy.size() == 1 and sy[0].pos == want, "HARM symbol at %s (%s)" % [want, sy[0].pos if not sy.is_empty() else null])
	check(not pg.no_source and not pg.in_range, "rounds left: a source; no DLZ: not in range")
	var pg2: Dictionary = h.page(Vector2(deg_to_rad(5.0), 0.0), 2)
	check(Mfd.harm_symbols(pg2)[0].pos.x < sy[0].pos.x - 10, "turning right moves the symbol left until the next capture")
	check(h.page(Vector2.ZERO, 0).no_source, "no round left: no source")

	# --- mission 231 (F-16): FLIR pod, POPEYE, HARM ------------------------------------------------------
	Settings().arm_loadouts = {1: [[11, 1], [0, 0], [55, 1], [30, 1], [0, 0], [0, 0], [20, 1], [0, 0], [11, 1]]}
	Settings().player_flight = 1
	var tv = await start_mission(231)
	Settings().arm_loadouts = {}
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.rig.position.y += 1500.0
	var w = tv.weapons
	var cp = tv.cockpit
	var t := 1.0
	w.update(t)
	check(w.flir_pod, "the FLIR pod on station 3 makes the FLIR available")
	tv._command([90, 6, 0])
	w.update(t)
	var flir_mfd = cp.mfds.filter(func(m): return m.page == 6)
	check(flir_mfd.size() == 1 and w.eo.mode == Eo.FLIR, "I: the FLIR page and EO mode 2")
	await frames(2)
	check(cp.eo.flir.zoom == 1 and cp.eo.flir.range != "", "FLIR page data published (zoom %d, range %s)" % [cp.eo.flir.zoom, cp.eo.flir.range])
	check(tv.eo_viewport != null and cp.eo_texture != null, "the EO picture: a SubViewport camera")
	var right_rec := 50
	tv._apply_held(right_rec, [139, 100, 0])
	t += 2.0
	w.update(t)
	check(absf(rad_to_deg(w.eo_ae.x) - 18.0) < 0.01, "Ctrl+Right held 2 s: 18° right (%.2f°)" % rad_to_deg(w.eo_ae.x))
	await frames(1)
	var fwd: Vector3 = -tv.eo_camera.global_basis.z
	var jet_fwd: Vector3 = -tv.rig.global_basis.z
	var turn := rad_to_deg(Vector2(jet_fwd.x, jet_fwd.z).angle_to(Vector2(fwd.x, fwd.z)))
	check(absf(absf(turn) - 18.0) < 1.0, "the EO camera turned 18° from the nose (%.1f°)" % turn)
	check(absf(tv.eo_camera.fov - 50.0) < 1e-3 and tv.eo_camera.keep_aspect == Camera3D.KEEP_WIDTH, "50° across at zoom 1")
	flir_mfd[0].press(0xb)
	w.update(t)
	check(w.eo.zoom == 2.0 and cp.eo.flir.zoom == 2, "OSB 0xb: zoom 2")
	tv._release_command([20, 0, 0])
	check(w.eo.zoom == 4.0, "the zoom key's release zooms the EO camera")
	flir_mfd[0].press(5)
	check(w.eo.spot and w.eo.zoom == 8.0, "OSB 5: SPOT")
	flir_mfd[0].press(3)
	w.update(t)
	check(w.eo.laser and cp.eo.flir.laser, "OSB 3: LASER ON")
	tv._apply_held(right_rec, [139, 0, 0])
	w.update(t)
	check(w.eo.track == Eo.TRACK, "releasing Ctrl+Right locks the FLIR on the centre point")
	await frames(2)
	# The TV page: the POPEYE (station 7).
	w.select_station(6)
	w.update(t)
	check(w.master == 6 and w.eo.mode == Eo.TV and w.eo.limits == Eo.WEAPON_LIMITS, "POPEYE: master 6, EO mode 1, weapon limits")
	check(cp.mfds.any(func(m): return m.page == 5) and cp.eo.tv.status == 1, "the TV page, RDY")
	check(not cp.mfds.any(func(m): return m.page == 6), "page 5 took the FLIR page's place")
	await frames(2)
	# The HARM page with a synthetic emitter 20 km ahead.
	w.select_station(3)
	var o: Dictionary = w.own()
	w.rwr.slots[0] = {"unit": "synthetic", "type": 300, "pos": o.pos + Vector3(o.fwd.x, o.fwd.y, 0).normalized() * 20000.0 - Vector3(0, 0, 1000),
		"launch": false, "missiles": 0, "drop": false, "active": true}
	w._harm_capture()
	t += 0.1
	w.update(t)
	var harm_mfd = cp.mfds.filter(func(m): return m.page == 10)
	check(w.master == 4 and harm_mfd.size() == 1 and w.eo.mode == Eo.NONE, "HARM: master 4, page 10, the EO mode off")
	check(cp.harm.list.size() == 1 and not cp.harm.no_source, "HARM page lists the synthetic emitter (%d)" % cp.harm.get("list", []).size())
	var hs: Array = Mfd.harm_symbols(cp.harm)
	check(hs.size() == 1 and absf(hs[0].pos.x - 66) <= 2, "ahead: near the centre column (%s)" % [hs[0].pos if not hs.is_empty() else null])
	await frames(2)
	# Every page draws on the F-16 and the Lavi (3 MFDs, ADI page).
	for dir in ["converted/cockpits/f16", "converted/cockpits/lavi"]:
		if dir != "converted/cockpits/f16":
			cp.load_cockpit(dir)
		for pgn in range(11):
			for m in cp.mfds:
				m.page = pgn
			await frames(2)
		check(true, "%s: pages 0..10 drawn" % dir.get_file())
