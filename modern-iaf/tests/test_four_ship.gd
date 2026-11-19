# Modern IAF's four-ship (modern-iaf/docs/ai-plan.md §6 F1–F4, F7, F10, F11): mission ramon_four_ship, Alpha 1 the
# player and Alpha 2, 3 and 4 flown by IafAi (crates/iaf-ai):
#   - F1: one formation of four in Ramon's four Sufa shelters in data/parking.json's order, the wingmen with the lead's
#     stores;
#   - F2: the tower's start-up clearance starts the wingmen's engines; each holds until the jet ahead has moved (the
#     player's jet put in the air over the base, its F-16 autopilot circling at 30° of bank), then taxies;
#   - F3, F4: Alpha 2, 3 and 4 take off in order and join the lead, the slots kept within 300 m in its turn and
#     each back within 60 m of its slot in 60 s (a real wingman drifts in a turn too; inferred);
#   - F5's commands through IafAi.command: check and ops check answered, echelon right flown;
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
var _wing: Array = []  # the wingmen's entities, Alpha 2..4
var _spots: Array = []  # their shelters' spots (x east, y north)
var _orbit := false
var _min_air := INF
var _min_at := ""
var _phase := "start-up"  # the test's step, in the separation's message


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
	check(ai.flight_ai != null and ai._ai_members.size() == 4, "IafAi flies Alpha 1-4 (%d)" % ai._ai_members.size())
	if ai.flight_ai == null or _wing.size() != 3:
		return
	process_frame.connect(_watch)
	await _start_up(tv)
	_phase = "join-up"
	if await _join(tv):
		_phase = "commands"
		await _commands(tv)
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
		check(int(ent.control) == 1 and ent.has("pilot"), "Alpha %d: flown by the AI" % (k + 1))
		var at: Vector2 = placed.get(int(ent.id), Vector2.INF)
		var w := Vector2(ent.world.x, ent.world.y)
		check(w.distance_to(at) < 2.0, "Alpha %d: on its shelter's spot (%.1f m off)" % [k + 1, w.distance_to(at)])
		for j in k:
			var o: Vector2 = Vector2(members[j].world.x, members[j].world.y) if j > 0 else _me(tv)
			check(w.distance_to(o) > 30.0, "Alpha %d and %d stand apart (%.0f m)" % [k + 1, j + 1, w.distance_to(o)])
		var u = tv.ai.combat.units.get(ent.key)
		var same := u != null
		for i in 9:
			var a: Dictionary = tv.weapons.stores.station(i)
			var b: Dictionary = u.stores.station(i) if u != null else {}
			same = same and int(a.get("w", {}).get("id", 0)) == int(b.get("w", {}).get("id", 0))
			same = same and int(a.get("count", 0)) == int(b.get("count", 0))
		check(same, "Alpha %d: the lead's stores" % (k + 1))
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
		check(running.call(k), "Alpha %d: its engine started after the clearance" % (k + 2))
		check(_moved(k) < 5.0, "Alpha %d: holds while the jet ahead has not moved (%.1f m)" % [k + 2, _moved(k)])
	_lead_up(tv)
	ok = await _until(tv, func(): return _moved(0) > 20.0, 90.0)
	check(
		ok and _moved(1) < 5.0,
		"Alpha 2 taxies once the lead has moved, Alpha 3 holds (%.0f, %.0f m)" % [_moved(0), _moved(1)]
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
		ok and up[0] < up[1] and up[1] < up[2], "Alpha 2, 3 and 4 airborne in order (%s s after the lead left)" % [up]
	)


## F4: each in position, then the slots kept within 300 m in the lead's turn for 30 s and each back within 60 m in
## 60 s (inferred: a real wingman drifts in a turn too; in position and the separation stay strict); F10: the AI's
## cost at time scale 1 meanwhile.
func _join(tv: Node) -> bool:
	var ok := await _until(tv, func(): return _said_all("in_position", 0), 600.0)
	check(ok, "Alpha 2, 3 and 4 in position on the lead (%s;%s)" % [_calls(), _wing_states(tv)])
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
	var fa = tv.ai.flight_ai
	var t0: float = tv.runtime.now
	check(fa.command(t0, 0, "check") and fa.command(t0, 0, "ops_check"), "check and ops check taken")
	await fly(tv, 3.0)
	check(_said_all("ack", t0) and _said_all("fuel_state", t0), "check and ops check answered (%s)" % [_calls()])
	t0 = tv.runtime.now
	check(fa.command(t0, 0, "echelon_right"), "echelon right taken")
	var ok := await _until(tv, func(): return _said_all("in_position", t0), 300.0)
	check(ok, "echelon right: each in position (%s)" % [_calls()])


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
				"Alpha %d: landed and parked at its shelter, engine off (%.0f m off; %s)"
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
				_min_at = ", Alpha %d and %d at %.0f s, %s" % [i + 1, j + 1, tv._sim_time, _phase]
				_min_at += "; Alpha %d: %s" % [j + 1, tv.ai.flight_ai.state(j + 1).get("stage", "")]
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


## Wingman k's distance from its shelter's spot, m.
func _moved(k: int) -> float:
	var w: Vector3 = _wing[k].world
	return Vector2(w.x, w.y).distance_to(_spots[k])


## Each wingman's call `id` made after `t0` (mission s).
func _said_all(id: String, t0: float) -> bool:
	for n in [2, 3, 4]:
		var said := false
		for c in _tv.ai.flight_calls:
			said = said or (int(c.from) == n and String(c.id) == id and float(c.get("t", 0.0)) >= t0)
		if not said:
			return false
	return true


func _calls() -> String:
	return ", ".join(_tv.ai.flight_calls.map(func(c): return "%d %s" % [c.from, c.id]))


## Alpha `n`'s distance to the nearest other jet of the flight, m.
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
