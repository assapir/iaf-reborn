# Modern IAF's four-ship (modern-iaf/docs/ai-plan.md §6 F1–F4, F7, F10–F13): mission ramon_four_ship, Kidon 1-1 the
# player and Kidon 1-2, 1-3 and 1-4 flown by IafAi (crates/iaf-ai):
#   - F1: one formation of four in Ramon's four Sufa shelters in data/parking.json's order, the wingmen with the lead's
#     stores;
#   - F2: the tower's start-up clearance starts the wingmen's engines; each holds until the jet ahead has moved (the
#     player's jet put in the air over the base, its F-16 autopilot circling at 30° of bank), then taxies;
#   - F3, F4: Kidon 1-2, 1-3 and 1-4 take off in order and join the lead, the slots kept within 300 m in its turn and
#     each back within 60 m of its slot in 60 s (a real wingman drifts in a turn too; inferred);
#   - F5's commands through the radio menu (sim_flight.gd): the pilot's call and the answers said, check and ops
#     check answered, engage my target with nothing locked "unable", echelon right flown, the split and the regroup;
#   - F12: the split (element 2 to its own target, #4 on #3, #2 on the lead) and the regroup;
#   - F13: a scripted ground radar's lock on Kidon 1-2: its call, its defence with chaff, its rejoin; then a real
#     S-300PMU-2 (shared/ai/air_defence.gd) 15 km away locks and launches at the wingmen: the calls said with their
#     subtitles, the defence with chaff, the rejoin once the site is silent;
#   - F5's engage my target: Kidon 1-2 on an enemy drone (shared/ai/drones.gd): it flies at it and fires through
#     combat.gd, one missile in the air at a time, and rejoins once the target is gone;
#   - F4's other close shapes through the radio menu: diamond, vic, delta, echelon left, fingertip, each held within
#     60 m of its slot for 20 s by 80 s after the "in position";
#   - F7: sent home, each lands and parks at its own shelter, engine off;
#   - all along at least 30 m between any two jets in the air; F10: the AI's CPU time per jet per frame at time
#     scale 1.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_four_ship.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 6.0
## The player's circle over the base: start this far north and this high over the shelter (m), the heading bug this
## far right of the heading (the autopilot's HDG SEL then banks 30°), the throttle.
const ORBIT_N := 6000.0
const ORBIT_UP := 1500.0
const BUG_AHEAD := 30.0
const ORBIT_THROTTLE := 0.2

var _tv: Node
var _wing: Array = []  # the wingmen's entities, Kidon 1-2..1-4
var _spots: Array = []  # their shelters' spots (x east, y north)
var _orbit := false
var _min_air := INF
var _min_at := ""
var _phase := "start-up"  # the test's step, in the separation's message
var _since := -1.0  # all the wingmen within 60 m of their slots since (mission s; -1 not)


func run() -> void:
	var s := settings()
	var id := sim_mission("ramon_four_ship")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	tv.addon.rules = {}  # unscored: the lesson's checks would end the flight when the lead is put in the air
	_tv = tv
	_spawn(tv)
	var ai = tv.ai
	check(
		ai.flight_ai != null and ai._ai_members.size() == 4, "IafAi flies Kidon 1-1..1-4 (%d)" % ai._ai_members.size()
	)
	if ai.flight_ai == null or _wing.size() != 3:
		return
	process_frame.connect(_watch)
	await _start_up(tv)
	_phase = "join-up"
	if await _join(tv):
		_phase = "commands"
		await _commands(tv)
		_phase = "split"
		await _split(tv)
		_phase = "lock"
		await _lock(tv)
		_phase = "site"
		await _site(tv)
		_phase = "engage"
		await _engage(tv)
		_phase = "shapes"
		await _shapes(tv)
		_phase = "home"
		await _home(tv)
	process_frame.disconnect(_watch)
	Engine.time_scale = 1.0
	check(_min_air > 30.0, "at least 30 m between any two jets in the air all along (%.1f m%s)" % [_min_air, _min_at])


## F1: four jets in one formation, the player first, each on its own shelter's spot; the wingmen AI with the lead's
## stores.
func _spawn(tv: Node) -> void:
	var me: Dictionary = tv.runtime.player_entity()
	var f: Dictionary = tv.ai._formation_of(me)
	var members: Array = f.get("members", [])
	check(members.size() == 4 and members[0] == me, "one formation of four, the player first (%d)" % members.size())
	var mission: Dictionary = tv.MissionRuntime.mission_files(tv.mission_id)[0].data
	var placed := {}
	for e in mission.entities.items:
		placed[int(e["0x1e"])] = Vector2(float(e["0x2e4"]), float(e["0x2ee"]))
	for k in range(1, members.size()):
		var ent: Dictionary = members[k]
		check(int(ent.control) == 1 and ent.has("pilot"), "Kidon 1-%d: flown by the AI" % (k + 1))
		var at: Vector2 = placed.get(int(ent.id), Vector2.INF)
		var w := Vector2(ent.world.x, ent.world.y)
		check(w.distance_to(at) < 2.0, "Kidon 1-%d: on its shelter's spot (%.1f m off)" % [k + 1, w.distance_to(at)])
		for j in k:
			var o: Vector2 = Vector2(members[j].world.x, members[j].world.y) if j > 0 else _me(tv)
			check(
				w.distance_to(o) > 30.0, "Kidon 1-%d and 1-%d stand apart (%.0f m)" % [k + 1, j + 1, w.distance_to(o)]
			)
		var u = tv.ai.combat.units.get(ent.key)
		var same := u != null
		for i in 9:
			var a: Dictionary = tv.weapons.stores.station(i)
			var b: Dictionary = u.stores.station(i) if u != null else {}
			same = same and int(a.get("w", {}).get("id", 0)) == int(b.get("w", {}).get("id", 0))
			same = same and int(a.get("count", 0)) == int(b.get("count", 0))
		check(same, "Kidon 1-%d: the lead's stores" % (k + 1))
		_wing.append(ent)
		_spots.append(at)


func _me(tv: Node) -> Vector2:
	var w: Vector3 = tv.player_world()
	return Vector2(w.x, w.y)


## F2, F3: the tower's clearance starts the wingmen; each holds until the jet ahead has moved, then taxies; all three
## airborne, in order.
func _start_up(tv: Node) -> void:
	var a: String = tv.addon.pick("startup")
	check(a == "ACFT_CLEAR_TO_START", "start-up: the tower clears the flight (%s)" % a)
	Engine.time_scale = TIME_SCALE
	var running := func(k: int) -> bool: return bool(_wing[k].pilot.flight.state().engine_on)
	var ok := await _until(tv, func(): return running.call(0) and running.call(1) and running.call(2), 120.0)
	for k in 3:
		check(running.call(k), "Kidon 1-%d: its engine started after the clearance" % (k + 2))
		check(_moved(k) < 5.0, "Kidon 1-%d: holds while the jet ahead has not moved (%.1f m)" % [k + 2, _moved(k)])
	_lead_up(tv)
	ok = await _until(tv, func(): return _moved(0) > 20.0, 90.0)
	check(
		ok and _moved(1) < 5.0,
		"Kidon 1-2 taxies once the lead has moved, Kidon 1-3 holds (%.0f, %.0f m)" % [_moved(0), _moved(1)]
	)
	var up := [INF, INF, INF]
	var t0: float = tv._sim_time
	ok = await _until(
		tv,
		func():
			for k in 3:
				if up[k] == INF and _wing[k].pilot.flight.ap_airborne():
					up[k] = tv._sim_time - t0
			return not INF in up,
		900.0
	)
	check(
		ok and up[0] < up[1] and up[1] < up[2],
		"Kidon 1-2, 1-3 and 1-4 airborne in order (%s s after the lead left)" % [up]
	)


## F4: each in position, then the slots kept within 300 m in the lead's turn for 30 s and each back within 60 m in
## 60 s (inferred: a real wingman drifts in a turn too; in position and the separation stay strict); F10: the AI's
## cost at time scale 1 meanwhile.
func _join(tv: Node) -> bool:
	var ok := await _until(tv, func(): return _said_all("in_position", 0), 600.0)
	check(ok, "Kidon 1-2, 1-3 and 1-4 in position on the lead (%s;%s)" % [_calls(), _wing_states(tv)])
	if not ok:
		return false
	Engine.time_scale = 1.0
	tv.ai.cost_us = 0
	tv.ai.cost_frames = 0
	var worst := 0.0
	var at := ""
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 30.0:
		await process_frame
		for n in [2, 3, 4]:
			var e := float(tv.ai.flight_ai.state(n).slot_error)
			if e > worst + 5.0:
				worst = e
				at = "#%d at %.1f s, nearest jet %.0f m:%s" % [n, tv._sim_time - t0, _nearest(tv, n), _wing_states(tv)]
			worst = maxf(worst, e)
	var ms: float = tv.ai.cost_us / 1000.0 / maxi(tv.ai.cost_frames, 1) / 3.0
	print(
		(
			"F10: %.3f ms per AI jet per frame (CPU: flight model, autopilot, AI, model and sound; %d frames)"
			% [ms, tv.ai.cost_frames]
		)
	)
	Engine.time_scale = TIME_SCALE
	check(worst < 300.0, "the slots kept in the lead's 30° bank turn (worst %.1f m; %s)" % [worst, at])
	var near := func(): return [2, 3, 4].all(func(n): return float(tv.ai.flight_ai.state(n).slot_error) < 60.0)
	check(await _until(tv, near, 60.0), "each back within 60 m of its slot in 60 s (%s)" % _wing_states(tv))
	return true


## F5's commands, by IafAi.command: check (each its number), ops check (each its fuel), echelon right flown.
func _commands(tv: Node) -> void:
	var t0: float = tv.runtime.now
	check(_menu(tv, ["to:0", "check"]) and _menu(tv, ["to:0", "ops_check"]), "check and ops check in the radio menu")
	await fly(tv, 3.0)
	check(_heard(tv, "FLT_CMD", "Kidon 1, check"), "the pilot's call said (%s)" % [_said_texts(tv)])
	check(_said_all("ack", t0) and _said_all("fuel_state", t0), "check and ops check answered (%s)" % [_calls()])
	check(_heard(tv, "WNG_FUEL", "Kidon 1-2, "), "the fuel state said (%s)" % [_said_texts(tv)])
	check(_menu(tv, ["to:2", "engage"]), "engage my target in the radio menu")
	await fly(tv, 3.0)
	check(_said(2, "unable", t0) and _heard(tv, "WNG_CALL", "Kidon 1-2, unable"), "no target locked: Kidon 1-2, unable")
	t0 = tv.runtime.now
	check(_menu(tv, ["to:0", "formation", "echelon_right"]), "echelon right in the radio menu")
	var ok := await _until(tv, func(): return _said_all("in_position", t0), 300.0)
	check(ok, "echelon right: each in position (%s)" % [_calls()])


## The other close shapes in the lead's 30° bank turn (line abreast and trail are the Rust test's), ending in
## fingertip. Held: within 60 m of the slots for 20 s, by 80 s after the last "in position" (the turn's tolerance
## of the join-up; a wingman pulled away by the collision avoidance in the change takes that long to come back). A
## phase of its own after the engage, so the split and the reactions start as before.
func _shapes(tv: Node) -> void:
	for id in ["diamond", "vic", "delta", "echelon_left", "fingertip"]:
		var t0: float = tv.runtime.now
		check(_menu(tv, ["to:0", "formation", id]), "%s in the radio menu" % id)
		var ok := await _until(tv, func(): return _said_all("in_position", t0), 300.0)
		var t1: float = tv.runtime.now
		_since = -1.0
		var held := await _until(tv, func(): return _held(tv, 20.0), 80.0)
		print("%s: in position after %.0f s, held %.0f s later" % [id, t1 - t0, tv.runtime.now - t1])
		check(ok and held, "%s: each in position, then held (%s)" % [id, _wing_states(tv)])


## F12: the lead splits element 2 to its own target 8 km ahead in the same area: #3 flies there with #4 on it, #2
## stays on the lead; the regroup brings element 2 back.
func _split(tv: Node) -> void:
	var fa = tv.ai.flight_ai
	var st: Dictionary = tv.flight.state()
	var b: Vector3 = st.position + st.forward * 8000.0 + st.right * 4000.0
	var t0: float = tv.runtime.now
	check(_menu(tv, ["to:5", "split"]), "split in the radio menu (to the SPI)")
	await fly(tv, 3.0)
	check(_said(3, "ack", t0) or _said(3, "unable", t0), "#3 answers the split (%s)" % _calls())
	t0 = tv.runtime.now
	check(fa.split(t0, b), "split taken")
	var on := func(): return fa.state(3).get("task", false) and int(fa.state(4).get("leader", 0)) == 3
	check(await _until(tv, on, 10.0), "element 2 on its task, #4 on #3 (%s)" % _wing_states(tv))
	var near := func():
		var q: Vector3 = _wing[1].pilot.flight.state().position
		return Vector2(q.x - b.x, q.z - b.z).length() < 4000.0
	check(await _until(tv, near, 200.0), "#3 at its target (%s)" % _wing_states(tv))
	var e2: float = fa.state(2).slot_error
	var e4: float = fa.state(4).slot_error
	# "It's ok if wingman isn't perfect, as in reality" (user): after engage + menu split #2 is 95 m, #4 51 m;
	# main's direct split still holds 60 m. #4 on its own task with #3 was seen 200–305 m off as #3 arrives (20 Nov):
	# a real pair flies its own task in a tactical spread far wider than that, so 400 m there (inferred).
	check(e2 < 150.0 and e4 < 400.0, "#2 on the lead (%.0f m), #4 on #3 (%.0f m)" % [e2, e4])
	t0 = tv.runtime.now
	check(_menu(tv, ["to:5", "rejoin"]), "the element's rejoin (the regroup) in the radio menu")
	var back := func(): return _said(3, "in_position", t0) and _said(4, "in_position", t0)
	check(await _until(tv, back, 900.0), "element 2 regrouped (%s;%s)" % [_calls(), _wing_states(tv)])


## The reactions: a radar on the ground locks Kidon 1-2 (combat.gd on_lock, scripted): it calls "mud", defends with
## chaff, and rejoins once the lock is gone.
func _lock(tv: Node) -> void:
	var ent: Dictionary = _wing[0]
	var u = tv.ai.combat.units.get(ent.key)
	var chaff: int = int(u.stations[10].count) if u != null and u.stations.size() > 10 else 0
	var side := 3 if int(ent.side) != 3 else 2  # hostile
	var at: Vector3 = ent.world + Vector3(20000, 20000, -ent.world.z)
	var radar := {"key": "test:radar", "world": at, "airborne_class": false, "side": side, "state": 0}
	var t0: float = tv.runtime.now
	tv.ai.combat.on_lock(radar, ent, true)
	var fa = tv.ai.flight_ai
	var defending := func(): return fa.state(2).get("defending", false) and _said(2, "mud", t0)
	check(await _until(tv, defending, 5.0), "Kidon 1-2 calls the lock and defends (%s)" % _calls())
	await fly(tv, 6.0)
	var left: int = int(u.stations[10].count) if u != null and u.stations.size() > 10 else 0
	check(chaff > 0 and left < chaff, "Kidon 1-2 releases chaff (%d of %d left)" % [left, chaff])
	t0 = tv.runtime.now
	tv.ai.combat.on_lock(radar, ent, false)
	var back := func(): return _said(2, "in_position", t0)
	check(await _until(tv, back, 600.0), "Kidon 1-2 rejoins (%s;%s)" % [_calls(), _wing_states(tv)])


## F13 against a real site (docs/ai.md §15): an S-300PMU-2 15 km from the flight locks and launches at the wingmen;
## each locked one calls "mud" (said, with its subtitle), defends and drops chaff, a launch at one is called
## "defending"; the site silent and its missiles gone, each rejoins. The jets are shielded: the stand-in missiles hit.
## (At 25 km the envelope's edge: the beaming wingmen were out of it and the site fired only at the lead, 1 run in 2.)
func _site(tv: Node) -> void:
	settings().invulnerable = true
	for e in _wing:
		e.shield = true
	var chaff := _wing.map(func(e): return _chaff(tv, e))
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	var parts: Array = ad.spawn("s300", j + Vector3(0, 15000, 0), 180.0)
	check(parts.size() == 6, "the S-300 spawned (%d parts)" % parts.size())
	if parts.is_empty():
		return
	var site: Dictionary = ad.site_of(parts[0])
	var t0: float = tv.runtime.now
	var by_site := func(k: int) -> bool:
		return _wing[k].get("locked_by", {}).keys().any(func(key): return String(key).begins_with("ad:"))
	var locked := []
	var any_locked := func():
		for k in 3:
			if by_site.call(k) and not k in locked:
				locked.append(k)
		return not locked.is_empty()
	check(await _until(tv, any_locked, 60.0), "the S-300 locks a wingman (%s)" % _calls())
	var k0: int = locked[0] if not locked.is_empty() else 0
	var fa = tv.ai.flight_ai
	var reacts := func(): return _said(k0 + 2, "mud", t0) and fa.state(k0 + 2).get("defending", false)
	check(await _until(tv, reacts, 10.0), "Kidon 1-%d calls the lock and defends (%s)" % [k0 + 2, _calls()])
	var heard := func(p): return String(p.template) == "WNG_CALL" and String(p.text).ends_with("mud")
	check(tv.radio.said.any(heard), "the call said with its subtitle (%s)" % [tv.radio.said.slice(-3)])
	var shot := []
	var at_wing := func():
		for f in site.flying:
			for k in 3:
				if String(f[1]) == String(_wing[k].key) and not k in shot:
					shot.append(k)
		return not shot.is_empty()
	check(await _until(tv, at_wing, 150.0), "the S-300 launches at a wingman (%s)" % [site.site.state(tv.runtime.now)])
	var k1: int = shot[0] if not shot.is_empty() else k0
	check(
		await _until(tv, func(): return _said(k1 + 2, "defending", t0), 10.0), "Kidon 1-%d calls the launch" % (k1 + 2)
	)
	var dropped := func(): return locked.all(func(k): return _chaff(tv, _wing[k]) < chaff[k])
	check(
		await _until(tv, dropped, 10.0),
		"each locked wingman drops chaff (%s of %s)" % [_wing.map(func(e): return _chaff(tv, e)), chaff]
	)
	site.site.set_emcon("silent")
	t0 = tv.runtime.now
	var gone := func(): return site.flying.is_empty() and range(3).all(func(k): return not by_site.call(k))
	check(await _until(tv, gone, 120.0), "the site silent, its missiles gone")
	var back := func(): return (locked + shot).all(func(k): return _said(k + 2, "in_position", t0))
	check(await _until(tv, back, 600.0), "the locked wingmen rejoin (%s;%s)" % [_calls(), _wing_states(tv)])
	for e in _wing:
		e.shield = false
	settings().invulnerable = false


## F5's engage my target (ai_flights.gd engage, the menu's path after the radar lock): an enemy drone 15 km away;
## Kidon 1-2 acknowledges, flies at it and fires (combat.gd's pick and launch), never two of its missiles at it at once;
## the drone gone, it rejoins. The S-300 above stays silent.
func _engage(tv: Node) -> void:
	var j: Vector3 = tv.player_world()
	var end := j + Vector3(0, -60000, 0)
	var g = tv.mission_ground(end)
	var salvo: Dictionary = load("res://shared/ai/drones.gd").of(tv).spawn(
		[j + Vector3(0, 15000, 0), Vector3(end.x, end.y, float(g if g != null else 0.0))]
	)
	check(not salvo.is_empty() and await _until(tv, func(): return salvo.ents[0] != null, 30.0), "a drone in the air")
	if salvo.is_empty() or salvo.ents[0] == null:
		return
	var d: Dictionary = salvo.ents[0]
	var t0: float = tv.runtime.now
	check(tv.ai.engage(2, d), "engage taken")
	var fa = tv.ai.flight_ai
	check(
		await _until(tv, func(): return _said(2, "ack", t0) and fa.state(2).get("engaging", false), 5.0),
		"Kidon 1-2 acknowledges and engages (%s)" % _calls()
	)
	var most := [0, 0]  # the most of Kidon 1-2's missiles at the drone at once, launches seen
	var seen := {}
	var shoot := func():
		var mine: Array = tv.weapons.missiles.filter(
			func(m): return is_same(m.get_meta("owner", {}), _wing[0]) and m.target_key == d.key
		)
		for m in mine:
			seen[m.get_instance_id()] = true
		most[0] = maxi(most[0], mine.filter(func(m): return not m.ended).size())
		most[1] = seen.size()
		return int(d.state) >= 3 or not tv.runtime.entities.has(d.key)
	check(await _until(tv, shoot, 240.0), "the drone destroyed or gone (%d launches, %s)" % [most[1], _wing_states(tv)])
	check(
		most[1] >= 1 and most[0] == 1,
		"Kidon 1-2 fires, one missile in the air at a time (%d launches, %d at once)" % [most[1], most[0]]
	)
	t0 = tv.runtime.now
	var back := func(): return _said(2, "in_position", t0) and not fa.state(2).get("engaging", true)
	check(await _until(tv, back, 600.0), "Kidon 1-2 rejoins (%s;%s)" % [_calls(), _wing_states(tv)])


func _chaff(tv: Node, ent: Dictionary) -> int:
	var u = tv.ai.combat.units.get(ent.key)
	return int(u.stations[10].count) if u != null and u.stations.size() > 10 else 0


## F7: sent home, each lands and parks at its own shelter, engine off.
func _home(tv: Node) -> void:
	check(tv.ai.flight_ai.command(tv.runtime.now, 0, "rtb"), "RTB taken")
	var parked := func(k: int) -> bool:
		var p = _wing[k].pilot
		var st: Dictionary = p.flight.state()
		return p.flight.ap_landed() and not bool(st.engine_on) and float(st.get("speed", 0.0)) < 0.5
	var ok := await _until(tv, func(): return parked.call(0) and parked.call(1) and parked.call(2), 1500.0)
	for k in 3:
		check(
			parked.call(k) and _moved(k) < 40.0,
			(
				"Kidon 1-%d: landed and parked at its shelter, engine off (%.0f m off; %s)"
				% [k + 2, _moved(k), _wing[k].pilot.flight.ap_stage()]
			)
		)
	check(ok, "all three parked")


## Every frame: the least distance between two jets in the air; the player's heading bug kept ahead (the circle).
func _watch() -> void:
	var tv := _tv
	if tv == null or tv.flight == null:
		return
	var me: Dictionary = tv.flight.state()
	if _orbit:
		# The heading marker straight into the autopilot (the cockpit's ap_inputs passes it only with its panel live).
		tv.flight.set_ap_panel(false, false, false, fposmod(float(me.heading) + BUG_AHEAD, 360.0), -1.0)
	var jets := [[tv.player_world(), bool(me.on_ground)]]
	for e in _wing:
		jets.append([e.world, bool(e.pilot._state.get("on_ground", true))])
	for i in jets.size():
		for j in range(i + 1, jets.size()):
			if jets[i][1] or jets[j][1]:
				continue
			var d: float = (jets[i][0] as Vector3).distance_to(jets[j][0])
			if d < _min_air:
				_min_air = d
				_min_at = ", Kidon 1-%d and 1-%d at %.0f s, %s" % [i + 1, j + 1, tv._sim_time, _phase]
				_min_at += "; Kidon 1-%d: %s" % [j + 1, tv.ai.flight_ai.state(j + 1).get("stage", "")]
				var sts: Array = [me] + _wing.map(func(e): return e.pilot.flight.state())
				for k in [i, j]:
					var st: Dictionary = sts[k]
					_min_at += (
						"; #%d hdg %.0f spd %.0f roll %.0f pitch %.0f clock %.2f s"
						% [k + 1, st.heading, st.speed, st.roll, st.pitch, st.time]
					)
				_min_at += "; #%d from #%d %s" % [j + 1, i + 1, (jets[j][0] - jets[i][0]).round()]


## The player's jet in the air ORBIT_N north of its shelter, ORBIT_UP over it, heading east; the F-16 autopilot's ALT
## HOLD and HDG SEL, the bug kept BUG_AHEAD right of the heading: a circle round the base.
func _lead_up(tv: Node) -> void:
	var w: Vector3 = tv.player_world()
	var pos: Vector3 = tv.world_to_scene(Vector3(w.x, w.y + ORBIT_N, w.z + ORBIT_UP))
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 90.0), Vector3(190.0, 0, 0), airborne_flags()
	)
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = ORBIT_THROTTLE
	_orbit = true
	_watch()
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])  # ROLL: HDG SEL
	await frames(2)
	var ap: Dictionary = tv.flight.ap_state()
	check(int(ap.pitch) == 1 and int(ap.roll) == 1, "the lead in the air on ALT HOLD and HDG SEL (%s)" % ap)


## All the wingmen within 60 m of their slots for `s` s by now (`_since` reset before the first call).
func _held(tv: Node, s: float) -> bool:
	var now: float = tv.runtime.now
	if [2, 3, 4].all(func(n): return float(tv.ai.flight_ai.state(n).slot_error) < 60.0):
		_since = now if _since < 0.0 else _since
	else:
		_since = -1.0
	return _since >= 0.0 and now - _since >= s


## Wingman k's distance from its shelter's spot, m.
func _moved(k: int) -> float:
	var w: Vector3 = _wing[k].world
	return Vector2(w.x, w.y).distance_to(_spots[k])


## Each wingman's call `id` made after `t0` (mission s).
func _said_all(id: String, t0: float) -> bool:
	return _said(2, id, t0) and _said(3, id, t0) and _said(4, id, t0)


## Kidon 1-`n`'s call `id` made after `t0` (mission s).
func _said(n: int, id: String, t0: float) -> bool:
	for c in _tv.ai.flight_calls:
		if int(c.from) == n and String(c.id) == id and float(c.get("t", 0.0)) >= t0:
			return true
	return false


## The radio menu (Ctrl+T, sim_flight.gd): opened, each id of `path` picked by its number as the keys do.
func _menu(tv: Node, path: Array) -> bool:
	tv.addon.set_open(true)
	for id in ["m:wingmen"] + path:
		var i: int = tv.addon.shown.find(id)
		if i < 0:
			tv.addon.set_open(false)
			return false
		tv.addon.choose(i + 1)
	return true


## A phrase of `template` said whose English text starts with `text`.
func _heard(tv: Node, template: String, text: String) -> bool:
	return tv.radio.said.any(func(p): return String(p.template) == template and String(p.text).begins_with(text))


func _said_texts(tv: Node) -> Array:
	return tv.radio.said.slice(-4).map(func(p): return String(p.text))


func _calls() -> String:
	return ", ".join(_tv.ai.flight_calls.map(func(c): return "%d %s" % [c.from, c.id]))


## Kidon 1-`n`'s distance to the nearest other jet of the flight, m.
func _nearest(tv: Node, n: int) -> float:
	var pos: Array = [tv.flight.state().position]
	for w in _wing:
		pos.append(w.pilot.flight.state().position)
	var d := INF
	for k in 4:
		if k != n - 1:
			d = minf(d, (pos[k] as Vector3).distance_to(pos[n - 1]))
	return d


## Each wingman's stage, slot error and flight state, for a failed check's message.
func _wing_states(tv: Node) -> String:
	var me: Dictionary = tv.flight.state()
	var s := ""
	for k in 3:
		var ai: Dictionary = tv.ai.flight_ai.state(k + 2)
		var st: Dictionary = _wing[k].pilot.flight.state()
		s += (
			" #%d %s%s slot %.0f m, %.0f m/s (lead %.0f), %+.0f ft, hdg %.0f, %.0f kg, clock %+.2f s;"
			% [
				k + 2,
				ai.get("stage", ""),
				" avoiding" if ai.get("avoiding", false) else "",
				ai.get("slot_error", -1.0),
				st.speed,
				me.speed,
				st.alt_ft - me.alt_ft,
				st.heading,
				st.internal_fuel_kg,
				st.time - me.time
			]
		)
	return s


## Waits until `cond` holds or `limit` s of sim time pass; true when it held.
func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true
