# The F-16s' real fire-control radar (the Sufa's, then the Barak's: base.gd sim_f16s) against the weapons range's drones
# (avionics-plan.md §6 slice 2, G1 and G5-G8; docs/radar.md §9), headless, on each jet's range mission set up as the
# front end's Fly does:
# - power and weight on wheels: the avionics key on the parking spot brings the FCR up in STBY; Q there picks CRM, which
#   does not radiate on the ground;
# - RWS: airborne, the search finds Drone 1 12 km ahead and not Drone 2 below the four bars; the antenna held down
#   (Alt + Down) finds Drone 2;
# - SAM and STT by the keys: the cursor on Drone 1, TMS up (/) bugs it while the search goes on, TMS up again locks it;
#   the lock holds through Drone 3's weave and break;
# - TWS (;): no bug by itself, the track file kept while the scan looks away, flashing;
# - VSR (' after TWS): only closing targets;
# - ACM: the 30 x 20 acquires a drone ahead; a drone 30° above is outside it until TMS right (10 x 60); TMS down
#   from that lock goes back to the 30 x 20; the HUD's ACM cues (10 x 60 lines, SLEW and BORE crosses);
# - NO RAD on the ground and in OVRD; the CNTL page (OSB 5) steps TGT HIS, whose earlier frames show; EXP (Ctrl + ;)
#   puts the SAM bug mid-scope and draws the scope 4:1 about it (the cursor beside the bug 4 times farther); the bug
#   centres the scan.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_fcr.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var w


func _press(k: Key, shift := false, alt := false, ctrl := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.alt_pressed = alt
	e.ctrl_pressed = ctrl
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false, ctrl := false) -> void:
	_press(k, shift, false, ctrl)
	_press(k, shift, false, ctrl, false)


## The jet restarted airborne at scene `pos` with scene velocity `vel`, heading `hdg`.
func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


## `dist` m behind the drone at its speed and heading, `up` m above it.
func _behind(d, dist: float, up := 0.0) -> void:
	var st: Dictionary = d.state()
	_put(st.position - st.velocity.normalized() * dist + Vector3(0, up, 0), st.velocity, float(st.heading))


func _seen(d) -> bool:
	return w.radar.contacts.any(func(c): return String(c.key) == String(d.ent.key))


func _contact(d) -> Dictionary:
	for c in w.radar.contacts:
		if String(c.key) == String(d.ent.key):
			return c
	return {}


## The drone's azimuth and elevation about the jet's axes (deg).
func _body(d) -> Vector2:
	var o: Dictionary = w.own()
	var r: Vector3 = d.ent.world - o.pos
	var fw: Vector3 = o.fwd
	var up: Vector3 = o.up
	var x := r.dot(fw.cross(up))
	var y := r.dot(fw)
	return Vector2(rad_to_deg(atan2(x, y)), rad_to_deg(atan2(r.dot(up), Vector2(x, y).length()))).round()


func _drone(name: String):
	return tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with(name))[0]


func run() -> void:
	await require_data()
	for unit in sim_f16s():
		print("-- %s" % unit)
		await _jet(unit, sim_f16s()[unit])


func _jet(unit: String, base: String) -> void:
	var s := settings()
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-fcr", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	check(not w.radar.real.is_empty(), "the radar is the real FCR (airframe radar.fcr)")
	# The Barak's radar against the Sufa's (avionics-plan.md B1): Weapon data Real's search range, the APG-68's 80 km
	# (43 NM), the (V)9's 104 km (56 NM);
	# SAM keeps one bug on the APG-68, four on the (V)9 (radar.rs keeps the newest sam_tracks).
	var want: Array = {"f16i": [56, 4], "f16d": [43, 1]}[unit]
	var nm := roundi(float(w.radar.modes[w.radar.LRS].nm))
	var sam := int(s.airframe(100).radar.fcr.sam_tracks)
	check([nm, sam] == want, "%s: CRM RWS to %d NM, SAM keeps %d bugs (%s)" % [unit, nm, sam, want])
	# Power and weight on wheels: the engine started (the developer shortcut), then the avionics key.
	tv._command([200, 0, 0])
	for i in 120:
		if int(tv.cockpit.power) == 2:
			break
		await fly(tv, 1.0)
	tv._command([213, 0, 0])
	await fly(tv, 4.0)
	check(
		tv.cockpit.up("fcr") and int(w.radar.mode) == w.radar.STBY, "on the ground, powered: STBY (%d)" % w.radar.mode
	)
	_tap(KEY_Q)
	await fly(tv, 3.0)
	check(int(w.radar.mode) == w.radar.LRS, "Q on the ground: CRM (%d)" % w.radar.mode)
	check(not w.radar.emit and w.radar.contacts.is_empty(), "weight on wheels: no radiating, no contacts")
	check(not bool(tv.cockpit.radar.emit) and not tv.cockpit.radar.real.is_empty(), "the FCR reads NO RAD (emit off)")
	# RWS: Drone 1 ahead at its height, Drone 2 low.
	var d1 = _drone("Drone 1")
	var d2 = _drone("Drone 2")
	_behind(d1, 12000.0)
	await fly(tv, 1.0)
	check(w.radar.emit and _seen(d1), "airborne: the search finds Drone 1 12 km ahead")
	_tap(KEY_SLASH, false, true)
	await fly(tv, 0.3)
	check(not w.radar.emit and w.radar.contacts.is_empty(), "Ctrl + / OVRD: NO RAD, no contacts")
	_tap(KEY_SLASH, false, true)
	await fly(tv, 1.0)
	check(w.radar.emit, "Ctrl + / again: radiating")
	# The CNTL page (OSB 5): OSB 18 steps TGT HIS 3 -> 4; three earlier frames show; OSB 5 closes it.
	var fmt = tv.cockpit.radar_mfd().real_fmt
	fmt._own("FCR", 5)
	check(fmt.fcr_cntl, "OSB 5: the CNTL page")
	fmt._own("FCR", 18)
	check(int(w.radar.real.cntl[6]) == 3, "CNTL OSB 18: TGT HIS 4 (%s)" % w.radar.real.cntl)
	fmt._own("FCR", 5)
	check(not fmt.fcr_cntl, "OSB 5 again: back to the FCR")
	_behind(d1, 12000.0)
	await fly(tv, 34.0)
	var back := 0
	for q: Vector3 in w.radar.real.history:
		back = maxi(back, int(q.z))
	check(back == 3, "TGT HIS 4: returns from three frames back show (%d)" % back)
	var names: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "fcr_mode", int(w.radar.mode))
	var sub: String = ClassDB.class_call_static("IafF16Mfd", "fcr_real_submode", int(w.radar.mode), false, 0)
	check(names[0] == "CRM" and sub == "RWS", "the FCR reads CRM RWS")
	_behind(d2, 15000.0, 3700.0)
	await fly(tv, 9.0)
	check(not _seen(d2), "Drone 2 3.7 km below, 15 km out: under the four bars")
	_press(KEY_DOWN, false, true)
	await fly(tv, 1.6)
	_press(KEY_DOWN, false, true, false, false)
	_behind(d2, 15000.0, 3700.0)
	await fly(tv, 9.0)
	check(float(w.radar.real.elevation) < -12.0, "Alt + Down: the antenna down (%.1f°)" % w.radar.real.elevation)
	check(_seen(d2), "the antenna down finds Drone 2 (look-down)")
	_press(KEY_UP, false, true)
	await fly(tv, 1.6)
	_press(KEY_UP, false, true, false, false)
	# SAM, then STT, by the cursor and the TMS.
	_behind(d1, 12000.0)
	await fly(tv, 9.0)
	var c := _contact(d1)
	check(not c.is_empty(), "Drone 1 listed again")
	if c.is_empty():
		return
	w.radar_event(w.RADAR_CURSOR, c.scope)
	_tap(KEY_SLASH)
	await fly(tv, 0.5)
	check(
		w.radar.real.sam.has(String(d1.ent.key)) and int(w.radar.mode) == w.radar.LRS, "/ bugs Drone 1: SAM, searching"
	)
	check(String(w.radar.locked().get("key", "")) == String(d1.ent.key), "SAM's bug is the weapons' target")
	# A1 (Shift + ' twice): the narrow scan about the bug, not the cursor.
	w.radar_event(w.RADAR_CURSOR, Vector2(0.1, 0.5))
	_tap(KEY_APOSTROPHE, true)
	_tap(KEY_APOSTROPHE, true)
	await fly(tv, 0.3)
	var vol: Vector4 = w.radar.real.volume
	c = _contact(d1)
	check(
		absf((vol.x + vol.y) / 2.0 - rad_to_deg(float(c.az))) < 1.0,
		(
			"A1, the cursor aside: the bug centres the scan (%.1f° / %.1f°)"
			% [(vol.x + vol.y) / 2.0, rad_to_deg(float(c.az))]
		)
	)
	_tap(KEY_APOSTROPHE, true)
	# EXP draws the scope 4:1 about the bug: the cursor 0.025 of the scope beside the bug is drawn 0.1 beside it.
	w.radar_event(w.RADAR_CURSOR, Vector2(c.scope) + Vector2(0.025, 0.0))
	await fly(tv, 0.1)
	var norm_gap := Vector2(w.radar.real.cursor).distance_to(Vector2(_contact(d1).scope))
	_tap(KEY_SEMICOLON, false, true)
	await fly(tv, 0.3)
	c = _contact(d1)
	check(
		w.radar.real.exp and Vector2(c.scope).distance_to(Vector2(0.5, 0.5)) < 0.02,
		"Ctrl + ; EXP: the bug mid-scope (%s)" % c.scope
	)
	var exp_gap := Vector2(w.radar.real.cursor).distance_to(Vector2(c.scope))
	check(
		absf(exp_gap / maxf(norm_gap, 1e-6) - 4.0) < 0.2,
		"EXP: the scope drawn 4:1 (cursor to bug %.3f, NORM %.3f)" % [exp_gap, norm_gap]
	)
	_tap(KEY_SEMICOLON, false, true)
	await fly(tv, 0.3)
	check(not w.radar.real.exp, "Ctrl + ; again: NORM")
	w.radar_event(w.RADAR_CURSOR, Vector2(_contact(d1).scope))  # the cursor back on the bug: TMS up below locks it
	_tap(KEY_SLASH)
	await fly(tv, 0.5)
	check(int(w.radar.mode) == w.radar.STT, "/ again: STT (%d)" % w.radar.mode)
	tv.cockpit.hud.real_hud()
	check(tv.cockpit.hud._real_in.get("target") != null, "the Real HUD has the lock's target (its TD box)")
	_tap(KEY_SLASH, true)
	await fly(tv, 0.5)
	check(int(w.radar.mode) == w.radar.LRS, "Shift + /: the lock dropped, back to the search")
	# The lock holds through Drone 3's weave and break.
	var d3 = _drone("Drone 3")
	_behind(d3, 7000.0)
	await fly(tv, 0.2)
	w.radar.scan(w.now)
	c = _contact(d3)
	check(not c.is_empty(), "Drone 3 found 7 km ahead")
	if not c.is_empty():
		w.radar.lock_key(String(d3.ent.key))
		w.radar.lock_key(String(d3.ent.key))
		await fly(tv, 0.2)
		var held := 0
		var h0: float = float(d3.state().heading)
		var turned := 0.0
		for i in 40:
			await fly(tv, 0.25)
			turned = maxf(turned, absf(wrapf(float(d3.state().heading) - h0, -180.0, 180.0)))
			if String(w.radar.locked().get("key", "")) == String(d3.ent.key) and int(w.radar.mode) == w.radar.STT:
				held += 1
		check(held == 40, "the STT lock holds 10 s while Drone 3 turns %.0f° (%d / 40)" % [turned, held])
	_tap(KEY_SLASH, true)
	await fly(tv, 0.3)
	# TWS: files kept while the scan looks away.
	_behind(d1, 15000.0)
	_tap(KEY_SEMICOLON)
	await fly(tv, 0.3)
	check(int(w.radar.mode) == w.radar.TWS, "; (TMS right): TWS (%d)" % w.radar.mode)
	await fly(tv, 4.0)
	check(_seen(d1) and String(w.radar.locked().get("key", "")) == "", "TWS keeps Drone 1's file, unbugged")
	var st: Dictionary = d1.state()
	var fw: Vector3 = st.velocity.normalized()
	var side := fw.cross(Vector3.UP).normalized()
	_put(st.position - fw * 15000.0 * cos(1.0) + side * 15000.0 * sin(1.0), st.velocity, float(st.heading))
	await fly(tv, 5.0)
	c = _contact(d1)
	check(not c.is_empty() and float(c.age) > 2.0, "57° off the scan, the file stays (age %.1f s)" % c.get("age", 0.0))
	await fly(tv, 10.0)
	check(not _seen(d1), "dropped 13 s after its last return")
	# VSR: closing targets only.
	_tap(KEY_APOSTROPHE)
	await fly(tv, 0.3)
	check(int(w.radar.mode) == w.radar.LRS and w.radar.real.vsr, "' after TWS: VSR")
	# Behind Drone 1 again every 6 s (the racetrack's turns take it out of the scan), until a frame lists it.
	for i in 24:
		if i % 12 == 0:
			st = d1.state()
			_put(st.position - st.velocity.normalized() * 20000.0, st.velocity * 1.6, float(st.heading))
		await fly(tv, 0.5)
		if _seen(d1):
			break
	check(_seen(d1) and float(_contact(d1).closure) > 0.0, "VSR: Drone 1 ahead, the jet faster: closing")
	st = d1.state()
	_put(st.position - st.velocity.normalized() * 20000.0, st.velocity * 0.6, float(st.heading))
	await fly(tv, 9.0)
	# Shown only if it closes by now (its racetrack may turn it back towards the jet within the 9 s).
	check(
		not _seen(d1) or float(_contact(d1).closure) > 0.0,
		"VSR: Drone 1 pulling away: not shown (%s)" % [_contact(d1).get("closure", "-")]
	)
	_tap(KEY_APOSTROPHE)
	# ACM: Q from RWS → TWS → ACM.
	_tap(KEY_Q)
	_tap(KEY_Q)
	await fly(tv, 0.2)
	check(int(w.radar.mode) == w.radar.ACM, "Q, Q: ACM (%d)" % w.radar.mode)
	# Each placement just before its wait (one ACM frame, 1 s): the drones turn.
	_behind(d1, 2500.0, -2500.0 * tan(deg_to_rad(30.0)))  # the jet below: Drone 1 30° up
	await fly(tv, 1.2)
	check(int(w.radar.mode) == w.radar.ACM and not _seen(d1), "ACM 30 x 20: Drone 1 30° above, outside")
	_behind(d1, 2500.0, -2500.0 * tan(deg_to_rad(30.0)))
	_tap(KEY_SEMICOLON)
	await fly(tv, 1.2)
	check(
		int(w.radar.mode) == w.radar.STT,
		"TMS right: the 10 x 60 acquires it (mode %d, Drone 1 at %s° off the jet's axes)" % [w.radar.mode, _body(d1)]
	)
	_tap(KEY_SLASH, true)
	await fly(tv, 0.2)
	check(
		int(w.radar.mode) == w.radar.ACM and int(w.radar.real.acm) == 0,
		"Shift + / on ACM's lock: back to the 30 x 20, no re-lock (%d)" % w.radar.mode
	)
	# The HUD's ACM cues, with nothing in reach (high above the drones): the 10 x 60's lines, SLEW's and BORE's crosses.
	_behind(d1, 30000.0, 8000.0)  # 8 km above the range: no drone inside any pattern
	var cues := []
	for k in [[KEY_SEMICOLON, false], [KEY_SEMICOLON, true], [KEY_SLASH, false]]:
		_tap(k[0], k[1])
		await fly(tv, 0.3)
		tv.cockpit.hud.real_hud()
		cues.append(int(tv.cockpit.hud._real_in.get("acm", -1)))
	check(cues == [1, 2, 3], "the HUD's ACM cue: 10 x 60, SLEW, BORE (%s)" % [cues])
	_tap(KEY_SLASH, true)
	await fly(tv, 0.2)
	_behind(d1, 3000.0)
	await fly(tv, 1.2)
	check(
		int(w.radar.mode) == w.radar.STT,
		"ACM 30 x 20 acquires Drone 1 ahead (mode %d, Drone 1 at %s°)" % [w.radar.mode, _body(d1)]
	)
	tv.queue_free()
	await frames(5)
