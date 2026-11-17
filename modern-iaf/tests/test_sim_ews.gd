# The F-16s' EW and identification, the Sufa's then the Barak's (base.gd sim_f16s; avionics-plan.md §6 slice 5 part B;
# modern-iaf/docs/ews.md) on the weapons range, headless: each jet's range mission set up as the front end's Fly does,
# the jet put in the air ahead of Drones 4 (the F-35 pair with radars on), then
# - E1 the threat display: a drone's lock is heard (all round, not only from behind) and shows as "35" on the RWR
#   scope's symbols, a lock in its square and the top threat in the diamond; the threat warning keys: Alt + I OPEN,
#   Alt + O UNKNOWN, Alt + Y HANDOFF, Alt + J TGT SEP held, Ctrl + I SYS TEST's pattern;
# - E2 the MAW (the Sufa's; the Barak has none): a missile launched at the jet warns from its direction with a falling
#   time to impact;
# - E4 the CMDS: Shift + Y to MAN, P runs program 1 (a chaff and a flare counted off through the game's dispense);
#   SEMI asks "Counter" on a launch and Y gives consent; Ctrl + Y the next program; the panel's switches;
# - R15 the AIFF: O (SCAN) and TMS left in CRM: a friendly drone replies (a green circle), a hostile one does not;
# - N5 the data link: the DL switch on, the drones as hostile tracks;
# - the DED's pages (ufc.md, ews.md §8): LIST 7 EWS (its BINGO page sets the flares' BINGO, a program's BQ), the IFF
#   key's page, LIST ENTR DLNK, LIST RCL INTG (the last interrogation);
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_ews.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


## A missile flying at the jet, as the RWR's list keeps it (player_weapons.gd _rwr_missile's "m").
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


func _tap(k: Key, mods := "", down := true, up := true) -> void:
	for d in ([true] if down else []) + ([false] if up else []):
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = "s" in mods
		e.ctrl_pressed = "c" in mods
		e.alt_pressed = "a" in mods
		e.pressed = d
		tv._unhandled_input(e)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


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
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-ews", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	# The Barak's suite against the Sufa's (avionics-plan.md B4, B8): both have the AIFF, only the Sufa the MAW.
	var maw: bool = {"f16i": true, "f16d": false}[unit]
	check(
		w.ews != null and w.ews.aiff and w.ews.maw == maw,
		"%s: the EW suite, the AIFF, the MAW %s" % [unit, "on" if maw else "off"]
	)
	if w.ews == null:
		return
	var drones: Array = tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with("Drones 4"))
	check(drones.size() == 2, "Drones 4: the radar pair")
	# 15 km ahead of the pair, head on: the drones' radars see the jet and lock it.
	var st: Dictionary = drones[0].state()
	var fwd: Vector3 = st.velocity.normalized()
	_put(st.position + fwd * 15000.0, -st.velocity, float(st.heading) + 180.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not c.ews.get("symbols", []).any(func(x): return x.label == "35"):
		await fly(tv, 0.5)
	await _threats()
	await _maw(drones[0].ent)
	await _cmds()
	await _aiff(drones[0].ent)
	await _link()
	await _ded()
	await _awacs()


func _threats() -> void:
	var sy: Array = c.ews.get("symbols", [])
	check(
		w.rwr.display().any(func(e): return int(e.type) == 1000 and e.active),
		"E1: a drone's lock is on the RWR, active from ahead (%s)" % [w.rwr.display()]
	)
	check(sy.any(func(x): return x.label == "35" and x.kind == "air" and x.lethal), "E1: '35' locking: %s" % [sy])
	check(sy.size() > 0 and sy[0].diamond, "E1: the top threat in the diamond")
	# Each symbol on the ring of its lethality (ews.rs RING_*), the symbols apart (SEP), none on the ownship.
	var rings := sy.all(func(x): return absf(x.at.length() - (0.3 if x.launch else (0.58 if x.lethal else 0.9))) < 1e-3)
	check(rings, "E1: each symbol on its ring (%s)" % [sy.map(func(x): return [x.at, x.lethal])])
	var apart := true
	for i in sy.size():
		for j in range(i + 1, sy.size()):
			apart = apart and (sy[i].at as Vector2).distance_to(sy[j].at) >= 0.45 - 1e-3
	check(apart, "E1: the symbols apart (%s)" % [sy.map(func(x): return x.at)])
	var scope = tv.cockpit_3d.displays.get("RWR_scope") if tv.get("cockpit_3d") != null else null
	if scope != null:
		scope.queue_redraw()
		await frames(2)
		check("35" in scope.shown.get("labels", []), "E1: the 3D RWR scope draws '35' (%s)" % [scope.shown])
	_tap(KEY_I, "a")
	check(bool(w.ews.twd_state().open), "Alt + I: OPEN")
	_tap(KEY_O, "a")
	check(bool(w.ews.twd_state().unknowns), "Alt + O: UNKNOWN on")
	_tap(KEY_J, "a", true, false)
	check(bool(w.ews.twd_state().sep), "Alt + J held: TGT SEP")
	_tap(KEY_J, "a", false, true)
	check(not bool(w.ews.twd_state().sep), "Alt + J let go")
	if sy.size() >= 2:
		var top: int = sy[0].id
		_tap(KEY_Y, "a")
		await fly(tv, 0.2)
		var now: Array = c.ews.symbols
		check(now.any(func(x): return x.diamond and x.id != top), "Alt + Y: HANDOFF moves the diamond")
	_tap(KEY_I, "c")
	await fly(tv, 0.2)
	check(c.ews.twd.testing and c.ews.symbols.size() == 4, "Ctrl + I: SYS TEST's pattern")
	await fly(tv, 3.5)
	check(not c.ews.twd.testing, "SYS TEST ends")


func _launch(from: Dictionary, id: int, dist: float) -> FakeMissile:
	var o: Dictionary = w.own()
	var m := FakeMissile.new()
	var d: Vector3 = o.fwd
	m.p0 = o.pos + d * dist
	m.v = -d * 700.0
	m.t0 = w.now
	w.rwr.launch(String(from.key), {"id": id, "pos": m.p0, "decoy": false, "m": m})
	return m


func _maw(drone: Dictionary) -> void:
	var m := _launch(drone, 9001, 8000.0)
	await fly(tv, 0.3)
	var wn: Array = c.ews.get("maw", [])
	if not w.ews.maw:
		check(wn.is_empty(), "E2: no MAW on the Barak: a launch gives no warning (%s)" % [wn])
		w.rwr.missile_end(String(drone.key), {"id": 9001, "m": m})
		return
	check(wn.size() == 1 and absf(float(wn[0].bearing)) < 0.3, "E2: the MAW warns from ahead: %s" % [wn])
	var t1: float = wn[0].tti if wn.size() > 0 else 0.0
	check(t1 > 0.0 and t1 < 12.0, "E2: a time to impact (%.1f s)" % t1)
	await fly(tv, 1.0)
	wn = c.ews.get("maw", [])
	check(wn.size() == 1 and float(wn[0].tti) < t1, "E2: the time falls")
	w.rwr.missile_end(String(drone.key), {"id": 9001, "m": m})
	await fly(tv, 0.2)
	check(c.ews.get("maw", []).is_empty(), "E2: the missile gone, no warning")


func _counts() -> Vector2i:
	return Vector2i(w.stores.displayed(10), w.stores.displayed(11))


func _cmds() -> void:
	var e = w.ews
	check(String(e.cmds_state().mode_name) == "STBY", "E4: the CMDS starts in STBY")
	_tap(KEY_Y, "s")
	check(String(e.cmds_state().mode_name) == "MAN", "E4: Shift + Y: MAN")
	var n0 := _counts()
	_tap(KEY_P)
	await fly(tv, 1.5)
	check(_counts() == n0 - Vector2i(1, 1), "E4: P runs program 1: a chaff and a flare (%s -> %s)" % [n0, _counts()])
	_tap(KEY_Y, "s")
	check(String(e.cmds_state().mode_name) == "SEMI", "E4: Shift + Y: SEMI")
	var played: Array = tv.sounds.played
	var p0 := played.size()
	var drone: Dictionary = tv.ai.pilots[0].ent
	var m := _launch(drone, 9002, 9000.0)
	await fly(tv, 0.3)
	check(bool(e.cmds_state().pending), "E4: SEMI waits for consent on a launch")
	check(played.slice(p0).has("VOC_BBETTY/BTY_COUNTER"), "E4: 'Counter' said: %s" % [played.slice(p0)])
	n0 = _counts()
	_tap(KEY_Y)
	await fly(tv, 1.5)
	check(_counts() == n0 - Vector2i(1, 1), "E4: Y consents: the program runs")
	w.rwr.missile_end(String(drone.key), {"id": 9002, "m": m})
	_tap(KEY_Y, "c")
	check(int(e.cmds_state().program) == 2, "E4: Ctrl + Y: program 2")
	_tap(KEY_P, "s")
	e.cmds_switch("ch", false)
	check(not bool(e.cmds_state().ch), "E4: CH off")
	e.cmds_switch("ch", true)


func _aiff(drone: Dictionary) -> void:
	var side: int = drone.side
	drone.side = tv.runtime.player_entity().side  # this one a friend for the check
	_tap(KEY_O)
	await fly(tv, 0.2)
	var r: Array = c.ews.get("aiff", [])
	check(r.any(func(x): return x.key == drone.key and x.friend), "R15: O: the friend replies (%s)" % [r])
	check(r.all(func(x): return x.friend), "R15: the hostile drones do not")
	check(bool(c.ews.blank), "R15: SCAN blanks the FCR's targets")
	await fly(tv, 3.5)
	check(c.ews.get("aiff", []).is_empty(), "R15: the replies go after 3 s")
	# TMS left in CRM interrogates too.
	_tap(KEY_Q)
	await fly(tv, 0.5)
	_tap(KEY_SEMICOLON, "s")
	await fly(tv, 0.2)
	check(not c.ews.get("aiff", []).is_empty(), "R15: TMS left in CRM: SCAN")
	# The reply's circle on the FCR sits on its contact (both by slant range; f16_mfd.gd fcr_place).
	await fly(tv, 1.2)
	var mfd = load("res://shared/cockpit/f16_mfd.gd")
	var rd: Dictionary = c.radar
	var nm: float = [5, 10, 20, 40, 80, 160][clampi(int(rd.get("idx", 1)), 1, 6) - 1]
	var h := deg_to_rad(float(c.state.heading))
	var rp: Array = c.ews.get("aiff", []).filter(func(x): return x.key == drone.key)
	var ct: Array = rd.get("contacts", []).filter(func(x): return x.get("key") == drone.key)
	if rp.is_empty() or ct.is_empty():
		check(false, "R15: the friend replies and is a contact (%s, %s)" % [rp, ct])
	else:
		var at: Vector2 = mfd.fcr_place(rp[0].pos, c.ews.own, h, nm)
		var want: Vector2 = mfd.bscope(rd, ct[0], nm)
		check(at.distance_to(want) < 1.5, "R15: the AIFF circle on its contact (%s, %s)" % [at, want])
	drone.side = side


func _link() -> void:
	check(not w.ews.link_on(), "N5: DL off at the start")
	tv._press([265, 0, 0])
	await fly(tv, 0.5)
	var t: Array = c.ews.get("link", [])
	check(t.any(func(x): return x.kind == "hostile"), "N5: the drones as hostile tracks (%d)" % t.size())


func _lines() -> PackedStringArray:
	return c.ufc.lines(c.ufc_nav())


func _ded() -> void:
	if c.ufc == null:
		check(false, "DED: the Sufa has the UFC")
		return
	for b in [18, 12, 7]:
		c.ufc_press(b)
	var l := _lines()
	check("EWS CONTROLS" in l[0], "LIST 7: the EWS page: %s" % [l])
	for b in [19, 17, 5, 10]:  # SEQ to BINGO, DCS down to FLARE, 5, ENTR
		c.ufc_press(b)
	await frames(1)
	check(int(w.ews.cmds_state().bingo[1]) == 5, "EWS BINGO: the flares' set to 5 (%s)" % [w.ews.cmds_state().bingo])
	for b in [19, 3, 10]:  # SEQ to the chaff program 1, BQ 3, ENTR
		c.ufc_press(b)
	await frames(1)
	check(float(w.ews.cmds_state().programs[0][0]) == 3.0, "EWS PRGM: program 1's chaff BQ 3")
	c.ufc_press(15)
	check("XPDR" in _lines()[0] and "2000" in _lines()[3], "the IFF key: the transponder's page (%s)" % [_lines()])
	for b in [17, 17, 4, 7, 2, 1, 10]:  # DCS down twice to mode 3/A, 4721, ENTR
		c.ufc_press(b)
	check("4721" in _lines()[3], "IFF: mode 3/A's code 4721 (%s)" % [_lines()])
	c.ufc_press(19)
	check("AIFF" in _lines()[0], "IFF SEQ: the AIFF's page (%s)" % [_lines()])
	_tap(KEY_K, "a")
	# The DED's five lines on its screen: the texture stretched over the screen's UVs (cockpit3d.gd _attach_display).
	var c3d = tv.get("cockpit_3d")
	if c3d != null and c3d.displays.has("DED_screen"):
		var mat: StandardMaterial3D = c3d._ded_mat
		check(absf(mat.uv1_scale.y - 1.0 / 0.673) < 0.01, "DED: its texture over the screen (%s)" % mat.uv1_scale)
	c.ufc_press(18)
	check(_lines()[4].begins_with("M1 3 C I"), "Alt + K: IDENT on the CNI page (%s)" % [_lines()])
	for b in [12, 10]:
		c.ufc_press(b)
	check("DLNK" in _lines()[0] and "ON" in _lines()[1], "LIST ENTR: DLNK, the link on (%s)" % [_lines()])
	for b in [12, 11]:
		c.ufc_press(b)
	check("INTG" in _lines()[0] and "SCAN" in _lines()[1], "LIST RCL: INTG, the last SCAN (%s)" % [_lines()])
	c.ufc_press(18)


## N6: the AWACS's contact call on the range (radio.gd _awacs, from 60 s into the flight), said in its voice.
func _awacs() -> void:
	var r: Node = tv.radio
	var call := func(p): return String(p.template).begins_with("ACFT_FCTRL")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not r.said.any(call):
		await fly(tv, 1.0)
	var calls: Array = r.said.filter(call)
	check(not calls.is_empty(), "N6: an AWACS contact call on the range")
	var played: Array = tv.sounds.played.map(func(x): return str(x))
	check(played.any(func(x): return "awx_" in x), "N6: the call heard in the AWACS's voice (%s)" % [calls.slice(0, 1)])
