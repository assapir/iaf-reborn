# Ours, Modern IAF's F-16s (modern-iaf/docs/avionics-plan.md E1, E2, E4, R15, N5; modern-iaf/docs/ews.md): the
# threat warning display, the MAW, the CMDS, the AIFF and the data link. The logic is IafEws
# (crates/iaf-godot/src/ews.rs over iaf_avionics::ews, cmds, aiff, datalink); this gathers the inputs from its owner
# (player_weapons.gd), plays the tones and the VMS calls, releases the CMDS's expendables through the game's own
# dispense, and keeps `state` for the cockpit (cockpit.gd ews: the RWR scope, the FCR and the HSD). The aircraft
# definition says what the jet has (airframe.json "ews": "aiff", "maw", "combat_id"); the threat display, the CMDS and
# the data link are every modern F-16's. Modern IAF's F-35I runs it too (its TWD, the DAS's MAW, the data link on the
# TSD, its combat ID: "combat_id"; modern-iaf/docs/avionics-plan.md A7, E5, N9, P5).
extends RefCounted

const AIRCRAFT := [2, 3, 0x1c]
## The FCR's azimuth across its scope (±60°): the cursor's place to its azimuth (radar.rs norm_xy).
const SCOPE_AZ := TAU / 3.0

var w: Object  # player_weapons.gd
var aiff := false
var maw := false
## The F-35I's combat ID (aiff.rs combat_id): every unit's identity in `state.ident`; its data link on from the start
## (MADL / Link 16 run by the mission systems, inferred: no DL switch on the jet).
var combat_id := false
## What the cockpit draws: {symbols, maw ([{id, bearing, tti, class ("AAM" / "SAM"), label ("AAM 12"), new}]), twd,
## cmds, aiff, blank, link, own (the jet's world position), ident ({key: "friend" / "unknown" / "hostile"}, the combat
## ID's; {} without one)}.
var state := {}
var _e = ClassDB.instantiate("IafEws")
var _launch_ids := {}


func _init(owner: Object, def: Dictionary) -> void:
	w = owner
	aiff = bool(def.get("aiff", false))
	maw = bool(def.get("maw", false))
	combat_id = bool(def.get("combat_id", false))
	w.rwr.new_guy_tone = false
	w.rwr.all_aspect = true
	w.rwr.radar_only = true
	if combat_id:
		_e.link_power(true)


func _play(code: String, sub: String, volume := 1.0) -> void:
	if w.host.get("sounds") != null:
		w.rwr.scaled(w.host.sounds.play(code, sub), volume)


# --- the panels' controls (terrain_view.gd _press, cockpit3d_controls.gd) --------------------------------------------


## The threat warning prime panel: 0 HANDOFF, 1 MODE (PRI / OPEN), 2 UNKNOWN, 3 TGT SEP (`on` held), 4 SYS TEST.
func twd_button(b: int, on := true) -> void:
	var st: Dictionary = _e.twd_state(w.now)
	match b:
		0:
			_e.handoff()
		1:
			_e.set_open(not st.open)
		2:
			_e.set_unknowns(not st.unknowns)
		3:
			_e.set_sep(on)
		4:
			_e.sys_test(w.now)


func twd_state() -> Dictionary:
	return _e.twd_state(w.now)


func set_open(on: bool) -> void:
	_e.set_open(on)


func set_unknowns(on: bool) -> void:
	_e.set_unknowns(on)


## The CMDS MODE knob (0 OFF … 5 BYP; -1 the next, round).
func cmds_mode(m := -1) -> void:
	_e.cmds_mode(m if m >= 0 else (int(_e.cmds_state().mode) + 1) % 6)


func cmds_switch(name: String, on: bool) -> void:
	_e.cmds_switch(name, on)


func cmds_next_program() -> void:
	_e.cmds_next_program()


func cmds_state() -> Dictionary:
	return _e.cmds_state()


## The CMS: 0 forward (the program), 1 aft (stop), 2 right (consent / AUTO).
func cms(dir: int) -> void:
	_e.cms(dir, w.now)


## The AIFF (the Sufa's; nothing on a jet without one): `los` a line-of-sight interrogation about the FCR's cursor,
## else SCAN. A friend replies, a hostile does not.
func interrogate(los: bool) -> void:
	if not aiff:
		return
	var o: Dictionary = w.own()
	var targets := []
	for u in w._units():
		if int(u.ent.get("klass", -1)) in AIRCRAFT:
			targets.append({"key": u.key, "pos": u.pos, "answer": 2 if u.hostile else 0})
	var cur: Vector2 = w.radar.real.get("cursor", Vector2(0.5, 0.5)) if not w.radar.real.is_empty() else Vector2(0.5, 0)
	var own := {"pos": o.pos, "heading": o.yaw, "pitch": asin(clampf(o.fwd.z, -1.0, 1.0))}
	_e.interrogate(los, own, (cur.x - 0.5) * SCOPE_AZ, targets, w.now)


## The DL switch.
func link_power(on: bool) -> void:
	if on != link_on():
		_e.link_power(on)


func link_on() -> bool:
	return _e.link_on()


# --- every frame ---------------------------------------------------------------------------------------------------


func update() -> void:
	var o: Dictionary = w.own()
	var own_xy := Vector2(o.pos.x, o.pos.y)
	var symbols: Array = _e.threats(w.rwr.display(), own_xy, o.yaw, w.now)
	if _e.take_new_guy() or _e.take_handoff():
		_play("SFX_WARNING", "WRN_NEW_GUY", w.rwr.threat_volume)
	# The missiles launched at the jet: the RWR's launch for the CMDS (a radar-guided one, heard), the MAW's warnings
	# (every one: it sees the motor and where it was launched from, the launcher's unit class).
	var list := []
	for e in w.rwr.missiles:
		var m = e.missile.get("m")
		var id = e.missile.id
		if e.get("heard", true) and not _launch_ids.has(id):
			_e.cmds_threat(true, w.now)
		if m != null:
			list.append(
				{
					"id": id,
					"pos": m.position(w.now),
					"vel": m.velocity(w.now),
					"launcher": e.missile.get("launcher", -1)
				}
			)
	_launch_ids = {}
	for e in w.rwr.missiles:
		_launch_ids[e.missile.id] = true
	var warnings: Array = _e.maw(list, o.pos, o.vel, o.yaw) if maw else []
	for wn in warnings:
		if wn.new:
			_e.cmds_threat(false, w.now)
	w.rwr.maw_warning = not warnings.is_empty()
	_cmds_step()
	link_update(o)
	state = {
		"symbols": symbols,
		"maw": warnings,
		"twd": _e.twd_state(w.now),
		"cmds": _e.cmds_state(),
		"aiff": _e.aiff_replies(w.now),
		"blank": _e.aiff_blanking(w.now),
		"link": _e.link_tracks(),
		"own": o.pos,
		"ident": _ident(o) if combat_id else {},
	}
	state.ded = _ded(state)


## The combat ID of every unit (aiff.rs combat_id): {key: "friend" / "unknown" / "hostile"}.
func _ident(o: Dictionary) -> Dictionary:
	var units := []
	for u in w._units():
		units.append({"key": u.key, "pos": u.pos, "hostile": u.hostile})
	return _e.combat_id(units, o.pos, w.rwr.heard())


## What the DED's EW pages show (IafUfc's nav.ews; modern-iaf/docs/ews.md §8).
func _ded(st: Dictionary) -> Dictionary:
	var c: Dictionary = st.cmds
	var friends := 0
	for r in st.aiff:
		friends += 1 if r.friend else 0
	var team := 0
	for t in st.link:
		team += 1 if t.kind == "team" else 0
	return {
		"programs": c.programs,
		"bingo": c.bingo,
		"opts": c.opts,
		"chaff": w.stores.displayed(10),
		"flares": w.stores.displayed(11),
		"mode": c.mode_name,
		"aiff": aiff,
		"intg": _e.aiff_last(),
		"friends": friends,
		"unknowns": st.aiff.size() - friends,
		"dl": link_on(),
		"team": team,
		"tracks": st.link.size()
	}


## An EWS page entry (IafUfc.press's effect, cockpit.gd ufc_press): a program, the BINGO quantities, the options.
func ded_edit(fx: Dictionary) -> void:
	match String(fx.kind):
		"cmds_program":
			_e.cmds_program(int(fx.index), bool(fx.flare), fx.d)
		"cmds_bingo":
			_e.cmds_bingo(int(fx.chaff), int(fx.flares))
		"cmds_opts":
			_e.cmds_opts(fx.opts)


## The CMDS's releases through the game's dispense (counted there; refused with the gear down, as Insert / Delete)
## and its VMS calls.
func _cmds_step() -> void:
	var s: Dictionary = _e.cmds_step(w.now, w.stores.displayed(10), w.stores.displayed(11))
	for t in s.release:
		w.dispense(t)
	for v in s.voice:
		_play("VOC_BBETTY", v)


## The data link's aircraft: the flight's other jets numbered from 2, every other aircraft for the AWACS's picture.
func link_update(o: Dictionary) -> void:
	if not link_on():
		return
	var ai = w.host.get("ai")
	var me: Dictionary = w._me()
	var mine: Dictionary = ai._formation_of(me) if ai != null and not me.is_empty() else {}
	var units := []
	var n := 1
	for u in w._units():
		if not int(u.ent.get("klass", -1)) in AIRCRAFT:
			continue
		var member := 0
		if not mine.is_empty() and is_same(ai._formation_of(u.ent), mine):
			n += 1
			member = n
		var g = w.host.mission_ground(u.pos)
		var v: Vector3 = u.vel
		units.append(
			{
				"key": u.key,
				"pos": u.pos,
				"ground": float(g) if g != null else 0.0,
				"heading": rad_to_deg(atan2(v.x, v.y)),
				"speed": Vector2(v.x, v.y).length(),
				"friend": not u.hostile,
				"member": member
			}
		)
	_e.link_update(w.now, o.pos, units)
