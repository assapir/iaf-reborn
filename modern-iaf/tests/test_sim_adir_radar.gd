# The F-35I Adir's radar, sensors and helmet (avionics-plan.md §4 A2-A7, E5, H6-H8, N9, P5; slice 7 part B) on its
# range mission (nevatim_range) set up as the front end's Fly does, headless:
# - SRCH: airborne the radar searches by itself (radar.auto) on the real FCR's controls (airframe radar.fcr): CRM RWS
#   finds Drone 1 12 km ahead, the portal's SRCH draws it with the cursor; the cursor and TMS up (/) bug it (SAM), TMS
#   up again locks it (STT), the helmet's lock carries its combat ID; TMS down (Shift + /) drops it; TMS right (;)
#   TWS keeps its file; Q ACM acquires it 3 km ahead;
# - combat ID (aiff.rs combat_id): the data link on from the start names the drones hostile (the AWACS's picture);
#   with the link off a drone with its radar off is unknown, SRCH draws a yellow square; a drone of Drones 4 (radars
#   on) stays hostile, heard on the TWD;
# - TWD: Drones 4's radars show as "35"; the DAS's MAW warns of an infrared missile (no launch circle) with its class
#   and seconds ("AAM 9") on the TWD and the helmet;
# - TSD: the data link's tracks;
# - ASR: R gives GM with its SAR picture (grey) and the hulks as tracks; Ctrl + ; steps EXP, DBS1, DBS2; Q GMT; the
#   helmet's break X in a 45° dive 2,000 ft over the ground (the F-16's GAAF rule, f35.rs).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_adir_radar.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


## A missile flying at the jet, as the RWR's list keeps it (test_sim_ews.gd's).
class FakeMissile:
	extends RefCounted
	var p0: Vector3
	var v: Vector3
	var t0: float

	func position(now: float) -> Vector3:
		return p0 + v * (now - t0)

	func velocity(_now: float) -> Vector3:
		return v


var tv: Node
var w
var c
var pcd


func _tap(k: Key, shift := false, ctrl := false, alt := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		e.alt_pressed = alt
		e.pressed = down
		tv._unhandled_input(e)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


## `dist` m behind the drone at its speed and heading, `up` m above it.
func _behind(d, dist: float, up := 0.0) -> void:
	var st: Dictionary = d.state()
	_put(st.position - st.velocity.normalized() * dist + Vector3(0, up, 0), st.velocity, float(st.heading))


func _contact(d) -> Dictionary:
	for ct in w.radar.contacts:
		if String(ct.key) == String(d.ent.key):
			return ct
	return {}


func _drone(name: String):
	return tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with(name))[0]


func _target(name: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == name:
			return e
	return {}


## Portal 0 shows format `f`; the frames that draw it.
func _show(f: String) -> void:
	pcd._show(0, f)
	await frames(3)


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-adir", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	pcd = c.pcd
	check(pcd != null, "the F-35I's PCD")
	check(not w.radar.real.is_empty(), "the radar has the real FCR's controls (airframe radar.fcr)")
	check(
		w.ews != null and w.ews.combat_id and w.ews.maw and w.ews.link_on(),
		"the EW set: combat ID, the DAS's MAW, the data link on"
	)
	if pcd == null or w.ews == null:
		return
	await _search()
	await _identity()
	await _twd()
	await _tsd()
	await _asr()
	await _gcas()
	tv.queue_free()
	await frames(5)


func _search() -> void:
	var d1 = _drone("Drone 1")
	_behind(d1, 12000.0)
	await fly(tv, 2.0)
	if int(w.radar.mode) < 2:
		_tap(KEY_Q)
	# Behind Drone 1 again each 3 s (its racetrack's turns take it out of the scan) until a frame lists it.
	for i in 4:
		_behind(d1, 12000.0)
		await fly(tv, 3.0)
		if not _contact(d1).is_empty():
			break
	check(
		int(w.radar.mode) == w.radar.LRS and not _contact(d1).is_empty(),
		(
			"airborne: CRM finds Drone 1 12 km ahead (mode %d, %s, contacts %s)"
			% [w.radar.mode, w.radar.real.get("volume"), w.radar.contacts.map(func(x): return [x.key, x.dist])]
		)
	)
	await _show("SRCH")
	var sh: Dictionary = pcd.fmt.shown.get("srch", {})
	check(
		(
			String(sh.get("mode", "")).begins_with("CRM")
			and sh.get("cursor", false)
			and not sh.get("kinds", []).is_empty()
		),
		"SRCH: CRM with the cursor and the track (%s)" % [sh]
	)
	var ct := _contact(d1)
	if ct.is_empty():
		return
	w.radar_event(w.RADAR_CURSOR, ct.scope)
	_tap(KEY_SLASH)
	await fly(tv, 0.5)
	check(w.radar.real.sam.has(String(d1.ent.key)), "/ bugs Drone 1 (SAM)")
	w.radar_event(w.RADAR_CURSOR, Vector2(_contact(d1).scope))
	_tap(KEY_SLASH)
	await fly(tv, 0.5)
	check(int(w.radar.mode) == w.radar.STT, "/ again: STT (%d)" % w.radar.mode)
	c.hud.real_hud()
	var t: Dictionary = c.hud._real_in.get("target", {})
	check(t.get("ident") == "hostile", "the helmet's lock carries its combat ID (%s)" % [t.get("ident")])
	await _show("SRCH")
	check(String(pcd.fmt.shown.srch.mode).ends_with("STT"), "SRCH reads the lock (%s)" % pcd.fmt.shown.srch.mode)
	_tap(KEY_SLASH, true)
	await fly(tv, 0.5)
	check(int(w.radar.mode) == w.radar.LRS, "Shift + /: the lock dropped")
	_behind(d1, 15000.0)
	_tap(KEY_SEMICOLON)
	await fly(tv, 4.0)
	check(int(w.radar.mode) == w.radar.TWS and not _contact(d1).is_empty(), "; TWS keeps Drone 1's file")
	_behind(d1, 30000.0, 8000.0)  # 8 km above the range: no drone inside ACM's pattern
	_tap(KEY_Q)
	await fly(tv, 0.2)
	check(int(w.radar.mode) == w.radar.ACM, "Q after TWS: ACM (%d)" % w.radar.mode)
	_behind(d1, 3000.0)
	await fly(tv, 1.2)
	check(int(w.radar.mode) == w.radar.STT, "ACM acquires Drone 1 3 km ahead (%d)" % w.radar.mode)
	_tap(KEY_SLASH, true)
	_tap(KEY_Q)
	await fly(tv, 0.3)


func _identity() -> void:
	var d1 = _drone("Drone 1")
	_behind(d1, 12000.0)
	await fly(tv, 4.5)
	var key := String(d1.ent.key)
	check(c.ews.ident.get(key) == "hostile", "the AWACS's track names Drone 1 hostile (%s)" % c.ews.ident.get(key))
	w.ews.link_power(false)
	await fly(tv, 0.5)
	check(c.ews.ident.get(key) == "unknown", "link off, its radar off: Drone 1 unknown (%s)" % c.ews.ident.get(key))
	await _show("SRCH")
	check("unknown" in pcd.fmt.shown.srch.get("kinds", []), "SRCH: a yellow square (%s)" % [pcd.fmt.shown.srch])


func _twd() -> void:
	# Ahead of Drones 4 (radars on), facing them, the link still off: heard, so hostile.
	var drones: Array = tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with("Drones 4"))
	var st: Dictionary = drones[0].state()
	var fwd: Vector3 = st.velocity.normalized()
	_put(st.position + fwd * 15000.0, -st.velocity, float(st.heading) + 180.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not c.ews.get("symbols", []).any(func(x): return x.label == "35"):
		await fly(tv, 0.5)
	var key := String(drones[0].ent.key)
	check(c.ews.ident.get(key) == "hostile", "Drones 4 heard on the TWD: hostile (%s)" % c.ews.ident.get(key))
	await _show("TWD")
	check("35" in pcd.fmt.shown.twd.labels, "TWD: the drones' radars as '35' (%s)" % [pcd.fmt.shown.twd])
	# The DAS's MAW: an infrared missile (an AIM-9X's kind) 8 km ahead closing at 700 m/s: off the TWD's radar symbols,
	# on its MAW as "AAM" with the seconds (ews.md §2, §3).
	var o: Dictionary = w.own()
	var m := FakeMissile.new()
	m.p0 = o.pos + o.fwd * 8000.0
	m.v = -o.fwd * 700.0
	m.t0 = w.now
	w.rwr.launch(key, {"id": 9101, "pos": m.p0, "decoy": false, "m": m, "weapon": 570})
	await fly(tv, 0.3)
	var wn: Array = c.ews.get("maw", [])
	check(wn.size() == 1 and absf(float(wn[0].bearing)) < 0.3, "MAW: the missile ahead (%s)" % [wn])
	await _show("TWD")
	var tm: Array = pcd.fmt.shown.twd.maw
	check(
		tm.size() == 1 and String(tm[0]).begins_with("AAM "), "TWD: the MAW's M with its class and seconds (%s)" % [tm]
	)
	check(not c.ews.symbols.any(func(x): return x.launch), "TWD: no launch circle for an infrared missile")
	c.hud.real_hud()
	check(c.hud._real_in.get("maw", []).size() == 1, "the helmet has the MAW's warning")
	w.rwr.missile_end(key, {"id": 9101, "m": m})
	w.ews.link_power(true)


func _tsd() -> void:
	await fly(tv, 4.5)
	await _show("TSD-1")
	var sh: Dictionary = pcd.fmt.shown.get("tsd", {})
	check(int(sh.get("link", 0)) > 0, "TSD: the data link's tracks (%s)" % [sh])


func _asr() -> void:
	var t1 := _target("Target 1")
	check(not t1.is_empty(), "Target 1 on the range")
	if t1.is_empty():
		return
	# The hulks about 30° left, 42 km out (test_sim_fcr_ag.gd's place), flying north 3,000 m up.
	var at := Vector2(t1.world.x + 22000.0, t1.world.y - 35700.0)
	var g = tv.mission_ground(Vector3(at.x, at.y, 0.0))
	_put(tv.world_to_scene(Vector3(at.x, at.y, float(g if g != null else 0.0) + 3000.0)), Vector3(0, 0, -220), 0.0)
	await fly(tv, 1.0)
	_tap(KEY_R)
	await fly(tv, 3.0)
	await _show("SRCH")
	var sh: Dictionary = pcd.fmt.shown.get("asr", {})
	check(
		sh.get("name") == "GM" and sh.get("picture", false) and sh.get("kinds", []).size() >= 4,
		"R: the ASR's GM with its SAR picture and the hulks as tracks (%s)" % [sh]
	)
	w.radar_event(w.RADAR_GROUND, t1.world)
	var fovs := []
	for i in 3:
		_tap(KEY_SEMICOLON, false, true)
		await fly(tv, 2.2)
		await _show("SRCH")
		fovs.append(pcd.fmt.shown.asr.get("fov"))
	check(fovs == ["EXP", "DBS1", "DBS2"], "Ctrl + ; steps the patch: %s" % [fovs])
	check(pcd.fmt.shown.asr.picture, "DBS2: the SAR patch drawn")
	_tap(KEY_Q)
	await fly(tv, 3.0)
	await _show("SRCH")
	check(pcd.fmt.shown.asr.get("name") == "GMT", "Q: GMT (%s)" % [pcd.fmt.shown.asr])


func _gcas() -> void:
	# A steep dive from 6,000 ft over the ground: the helmet's break X once the GAAF advisory comes (f35.rs: the
	# F-16's rule), held by the scripted stick at 45° nose down, until 600 ft.
	var o: Dictionary = w.own()
	var g = tv.mission_ground(o.pos)
	var pos: Vector3 = tv.world_to_scene(Vector3(o.pos.x, o.pos.y, float(g if g != null else 0.0) + 1830.0))
	_put(pos, Vector3(0, 0, -215), 0.0)
	tv.throttle = 0.6
	var lines := 0
	var low := 1e9
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 40.0:
		var st: Dictionary = tv.flight.state()
		tv.scripted_stick = Vector2(0.0, clampf((-45.0 - float(st.pitch)) * 0.05, -0.4, 0.5))
		await process_frame
		var fr: Dictionary = c.hud.real_hud()
		var agl = c.hud._real_in.get("agl_ft")
		if agl != null:
			low = minf(low, float(agl))
			if float(agl) < 600.0:
				break
		for p in fr.get("outer", []):
			if p.get("k", "") == "line":
				var a: Vector2 = p.a
				var b: Vector2 = p.b
				if absf(a.x - b.x) > 40.0 and absf(a.y - b.y) > 40.0:
					lines += 1
		if lines >= 2:
			break
	tv.scripted_stick = null
	check(
		lines >= 2,
		"a 45° dive toward the ground: the helmet's break X (%d long diagonals, down to %.0f ft)" % [lines, low]
	)
