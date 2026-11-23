# The big fight (modern-iaf/docs/ai-plan.md K12, X5; docs/ai.md §22), headless: the scenario of big_fight.gd (our
# four-ship against two MiG-29A pairs, one on CAP and one scrambling from a base, the S-300 network with a Tor and a
# ZSU, a convoy on the road and four Shahed-136s), flown FIGHT_S s of sim time.
#   - the lead's orders taken: low level, sort, weapons free to the element, the ground attack by Kidon 1-2;
#   - shots both ways: a missile of ours, a missile of theirs (a MiG's or a site's);
#   - kills: at least one enemy unit down;
#   - no AI jet flies into the ground (its flight model's crash while alive), none stuck (alive in the air and slower
#     than STUCK_MPS for STUCK_S), the based pair takes off;
#   - the CPU per frame at time scale 1 once the sort is given (X5, K12): the AI jets', the sites', the drones', the
#     convoy's, and the frame's process time, with our flight alone first.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_big_fight.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
const FIGHT_S := 420.0
const COST_S := 20.0
const STUCK_MPS := 60.0
const STUCK_S := 20.0

var sc
## Missiles seen in flight, by side: {instance id: true}.
var _shots := {1: {}, 2: {}}
## Missiles by the shooter's and the target's names: {"shooter>target": count}.
var _by := {}
var _ground_hits: Array = []
var _slow := {}
var _stuck: Array = []
var _alone := 0.0


func run() -> void:
	sc = load("res://../modern-iaf/tests/big_fight.gd").new()
	if not await sc.start(self):
		return
	var tv: Node = sc.tv
	# The frame's process time with our flight alone, then everything spawned.
	await fly(tv, 3.0)
	_alone = await _process_ms(tv, COST_S)
	if not sc.spawn(self):
		return
	process_frame.connect(_watch)
	var t0: float = tv._sim_time
	while not "sort" in sc.orders and tv._sim_time - t0 < 120.0:
		sc.step()
		await process_frame
	check("sort" in sc.orders, "a MiG near: the sort given (%s)" % _calls())
	await _cost(tv)
	Engine.time_scale = TIME_SCALE
	while tv._sim_time - t0 < FIGHT_S:
		sc.step()
		await process_frame
	Engine.time_scale = 1.0
	process_frame.disconnect(_watch)
	settings().invulnerable = false
	_outcomes(tv)
	sc = null


## The frame's mean process time (ms) over `secs` s at time scale 1, the lead's orders going on.
func _process_ms(tv: Node, secs: float) -> float:
	var sum := 0.0
	var n := 0
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < secs:
		if sc.spawned:
			sc.step()
		await process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	return sum / maxi(n, 1)


## The CPU per frame for COST_S s at time scale 1.
func _cost(tv: Node) -> void:
	var ai = tv.ai
	var nodes: Array = ["AirDefence", "Drones", "Convoys"].map(func(n): return ai.get_node(n))
	for n in nodes:
		n.cost_us = 0
	ai.cost_us = 0
	ai.cost_frames = 0
	var whole := await _process_ms(tv, COST_S)
	var f := float(maxi(ai.cost_frames, 1))
	var n_jets: int = ai.pilots.filter(func(p): return int(p.ent.state) < 3).size()
	var ad = nodes[0]
	print(
		(
			(
				"K12 CPU: AI jets %.3f ms a frame (%d jets, %.3f ms each); sites %.3f ms (%d sites, %d networks, %.3f ms "
				+ "each); drones %.3f ms; convoy %.3f ms; the frame's process %.2f ms (our flight alone: %.2f ms)"
			)
			% [
				ai.cost_us / 1000.0 / f,
				n_jets,
				ai.cost_us / 1000.0 / f / maxi(n_jets, 1),
				ad.cost_us / 1000.0 / f,
				ad.sites.size(),
				ad.nets.size(),
				ad.cost_us / 1000.0 / f / maxi(ad.sites.size() + ad.nets.size(), 1),
				nodes[1].cost_us / 1000.0 / f,
				nodes[2].cost_us / 1000.0 / f,
				whole,
				_alone
			]
		)
	)


func _outcomes(tv: Node) -> void:
	for id in ["low", "sort", "free", "engage"]:
		check(id in sc.orders, "the lead's order %s given" % id)
	var mine := int(tv.runtime.player_entity().side)
	var theirs := 3 - mine
	print("shots: ours %d, theirs %d (%s)" % [_shots[mine].size(), _shots[theirs].size(), _by])
	check(not _shots[mine].is_empty(), "a missile of ours")
	check(not _shots[theirs].is_empty(), "a missile of theirs")
	var down := func(a: Array): return a.filter(func(e): return e != null and int(e.state) >= 3).size()
	var enemy := {
		"MiG-29A": down.call(sc.cap + sc.based),
		"sites": down.call(sc.sites),
		"convoy": down.call(sc.convoy.ents),
		"drones": down.call(sc.salvo.ents),
	}
	print("down: ours %d of 3 wingmen; theirs %s" % [down.call(sc.wing), enemy])
	print("calls: %s" % _calls())
	check(enemy.values().reduce(func(a, b): return a + b, 0) > 0, "kills happen")
	check(_ground_hits.is_empty(), "no AI jet flew into the ground (%s)" % [_ground_hits])
	check(_stuck.is_empty(), "no AI jet stuck (%s)" % [_stuck])
	check(sc.based.all(func(e): return e.pilot.airborne or int(e.state) >= 3), "the based pair took off")


## Every frame: the missiles in flight by side, a jet's crash into the ground, a jet stuck.
func _watch() -> void:
	var tv: Node = sc.tv
	if tv == null or tv.get("weapons") == null:
		return
	for m in tv.weapons.missiles:
		var o = m.get_meta("owner", {})
		if o is Dictionary and o.has("side") and _shots.has(int(o.side)):
			if not _shots[int(o.side)].has(m.get_instance_id()):
				var at: Dictionary = sc.tv.runtime.entities.get(m.target_key, {})
				var k := "%s>%s" % [o.name, at.get("name", "?")]
				_by[k] = int(_by.get(k, 0)) + 1
			_shots[int(o.side)][m.get_instance_id()] = true
	var now: float = tv._sim_time
	for e in sc.jets():
		var p = e.get("pilot")
		if p == null:
			continue
		var st: Dictionary = p._state
		if int(e.state) >= 3:
			if st.get("crashed", false) and not _ground_hits.has(e.name):
				_ground_hits.append(e.name)
			continue
		var slow: bool = p.airborne and not st.get("on_ground", false) and Vector3(e.vel).length() < STUCK_MPS
		if not slow:
			_slow.erase(e.name)
		elif now - float(_slow.get(e.name, now)) > STUCK_S:
			if not _stuck.has(e.name):
				_stuck.append(e.name)
		else:
			_slow[e.name] = _slow.get(e.name, now)


func _calls() -> String:
	return ", ".join(sc.tv.ai.flight_calls.map(func(c): return "%d %s" % [c.from, c.id]))
