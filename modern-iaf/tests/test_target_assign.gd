# Modern IAF's lead assigns targets (docs/ai.md §8.11, modern-iaf/docs/ai-plan.md F5), headless: mission
# ramon_four_ship with the player's four-ship put in the air by the dev hook ai_flights.gd `flight_in_air`, against two
# MiG-29A pairs spawned 60 km ahead, 20 km apart side by side, each flown by `enemy_flight` (no network). Our jets
# are shielded (a MiG's missile cannot end the test); the MiGs are not.
#   - no order: the wingmen keep their slots and call each MiG "contact" once;
#   - each enemy pair, committed, takes two of our jets, not one (the same sort rule);
#   - engage bandit X: Kidon 1-2 on one west MiG, then the element on an east MiG (Kidon 1-4 on Kidon 1-3's wing);
#   - sort through the radio menu, then again by its key (Alt + W, command 108 p1 4): Kidon 1-3 "targeted" on the
#     east pair, Kidon 1-4 on the other east MiG, Kidon 1-2 on a west MiG, the wingmen holding their fire;
#   - weapons free by its key (Alt + \, command 108 p1 7) round the SPI on the east pair: the jets hunt there;
#   - the flight's rejoin through the radio menu: no foe left, the order over;
#   - weapons free with no SPI (nothing designated, no route): the jets hunt round the lead; the rejoin again;
#   - at least 30 m between any two of our jets all along.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_target_assign.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
const ALT := 6000.0
const SPEED := 230.0

var _tv: Node
var _wing: Array = []
var _min_air := INF


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
	var ai = tv.ai
	if ai.flight_ai == null:
		check(false, "IafAi flies the four-ship")
		return
	# The lead in the air at ALT heading north on ALT HOLD and HDG SEL; the wingmen behind it (the dev hook).
	var w: Vector3 = tv.player_world()
	var pos: Vector3 = tv.world_to_scene(Vector3(w.x, w.y, ALT))
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 0), Vector3(SPEED, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.6
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])  # ROLL: HDG SEL
	await frames(2)
	tv.flight.set_ap_panel(false, false, false, 0.0, -1.0)
	check(ai.flight_in_air(0.0), "the flight in the air (dev hook)")
	for m in ai._ai_members:
		if not m[1].player:
			_wing.append(m[1])
			m[1].shield = true
	s.invulnerable = true
	check(_wing.size() == 3, "three wingmen (%d)" % _wing.size())
	process_frame.connect(_watch)
	await _orders(tv)
	process_frame.disconnect(_watch)
	Engine.time_scale = 1.0
	s.invulnerable = false
	check(_min_air > 30.0, "at least 30 m between any two of our jets in the air (%.1f m)" % _min_air)


func _orders(tv: Node) -> void:
	var ai = tv.ai
	var fa = ai.flight_ai
	await fly(tv, 20.0)
	var j: Vector3 = tv.player_world()
	var migs: Array = []
	for x in [-10000.0, -11500.0, 10000.0, 11500.0]:
		var m: Dictionary = ai.spawn("mig29a", Vector3(j.x + x, j.y + 60000, ALT), 180.0, [])
		if not m.is_empty():
			migs.append(m)
	check(migs.size() == 4, "four MiG-29As in the air")
	if migs.size() != 4:
		return
	var pairs: Array = []
	for k in [0, 2]:
		pairs.append(ai.enemy_flight([migs[k], migs[k + 1]], Vector3(migs[k].world.x, j.y + 60000, ALT), {}))
	check(pairs.all(func(f): return f != null), "flown as two enemy pairs")
	var west: Array = [ai._bandit_id(migs[0]), ai._bandit_id(migs[1])]
	var east: Array = [ai._bandit_id(migs[2]), ai._bandit_id(migs[3])]
	var foe := func(n): return int(fa.state(n).get("foe", 0))
	# No order: the slots kept, each MiG called once.
	var t0: float = tv.runtime.now
	await fly(tv, 4.0)
	var contacts: int = ai.flight_calls.filter(func(c): return String(c.id) == "contact").size()
	check(contacts == 4, "each MiG called contact once (%s)" % _calls())
	check([2, 3, 4].all(func(n): return foe.call(n) == 0), "no order: no foe (%s)" % _states())
	# Each enemy pair, committed, on two of our jets.
	var sorted := func():
		return pairs.all(
			func(f):
				return f.state(1).get("committed", false) and f.state(1).foe != f.state(2).foe and f.state(2).foe > 0
		)
	check(await _until(tv, sorted, 20.0), "each enemy pair takes two of our jets (%s)" % _pairs(pairs))
	# Engage bandit X: Kidon 1-2 on a west MiG, then the element on an east one.
	t0 = tv.runtime.now
	check(ai.engage(2, migs[0]) and ai.engage(5, migs[2]), "engage taken")
	var named := func():
		return foe.call(2) == west[0] and foe.call(3) == east[0] and foe.call(4) == 0 and _said(3, "ack", t0)
	check(await _until(tv, named, 5.0), "each on its named bandit, Kidon 1-4 on Kidon 1-3 (%s)" % _states())
	check(int(fa.state(4).leader) == 3, "Kidon 1-4 flies on Kidon 1-3")
	# The sort, through the radio menu, then by its key.
	for how in ["menu", "key"]:
		t0 = tv.runtime.now
		if how == "menu":
			check(_menu(tv, ["to:0", "sort"]), "sort in the radio menu")
		else:
			check(tv._command([108, 4, 0]), "sort by its key (command 108 p1 4)")
		# At once: a threat on it (a MiG's lock in this fight) clears the hold in the next frames, as it should.
		check(fa.state(2).get("holding", false), "Kidon 1-2 holds its fire until the lead shoots (%s)" % how)
		var shared := func():
			var ok: bool = foe.call(3) in east and foe.call(4) in east and foe.call(3) != foe.call(4)
			return ok and foe.call(2) in west and _said(3, "targeted", t0) and _said(2, "ack", t0)
		check(
			await _until(tv, shared, 5.0),
			"sorted (%s): element 2 the east pair, Kidon 1-2 the west (%s)" % [how, _states()]
		)
	# Weapons free by its key round the SPI (the radar's designated point) on the east pair.
	tv.weapons.radar.designated = true
	# The point toward the east pair, at most 30 km out (the order's area must be within 40 km of the lead).
	var mid: Vector3 = (migs[2].world + migs[3].world) / 2.0
	var me: Vector3 = tv.player_world()
	tv.weapons.radar.desig = me + (mid - me).limit_length(30000.0)
	t0 = tv.runtime.now
	check(tv._command([108, 7, 0]), "weapons free by its key (command 108 p1 7)")
	var hunting := func():
		var ok: bool = [2, 3, 4].all(func(n): return String(fa.state(n).get("tactic", "")) == "free")
		return ok and _said(2, "ack", t0) and foe.call(3) in east
	check(await _until(tv, hunting, 5.0), "weapons free: the jets hunt the east pair (%s)" % _states())
	tv.weapons.radar.designated = false
	Engine.time_scale = TIME_SCALE
	await fly(tv, 60.0)
	# The rejoin ends the order.
	t0 = tv.runtime.now
	check(_menu(tv, ["to:0", "rejoin"]), "rejoin in the radio menu")
	await fly(tv, 3.0)
	# (A wingman a MiG attacks fights it on: its own defence needs no order.)
	check(
		[2, 3, 4].all(func(n): return String(fa.state(n).get("tactic", "")) == ""),
		"rejoined: the order over (%s)" % _states()
	)
	# Weapons free with no SPI (nothing designated, no route): the hunt is round the lead itself.
	var route: Array = tv.cockpit.waypoints
	tv.cockpit.waypoints = []
	check(tv.weapons.spi() == null, "no designation, no route: no SPI")
	t0 = tv.runtime.now
	check(tv._command([108, 7, 0]), "weapons free with no SPI")
	var alive: bool = migs.any(func(m): return int(m.state) < 3)
	var round_lead := func():
		var ok: bool = [2, 3, 4].all(func(n): return String(fa.state(n).get("tactic", "")) == "free")
		return ok and _said(2, "ack", t0) and (not alive or [2, 3, 4].any(func(n): return foe.call(n) > 0))
	check(await _until(tv, round_lead, 5.0), "no SPI: the jets hunt round the lead (%s)" % _states())
	tv.cockpit.waypoints = route
	check(_menu(tv, ["to:0", "rejoin"]), "rejoin in the radio menu (again)")


func _states() -> String:
	var fa = _tv.ai.flight_ai
	var out := []
	for n in [2, 3, 4]:
		var st: Dictionary = fa.state(n)
		var hold := " holding" if st.get("holding", false) else ""
		out.append("#%d %s foe %d%s" % [n, st.get("tactic", ""), int(st.get("foe", 0)), hold])
	return ", ".join(out)


func _pairs(pairs: Array) -> String:
	return ", ".join(
		pairs.map(func(f): return "%s %d %d" % [f.state(1).get("committed", false), f.state(1).foe, f.state(2).foe])
	)


## Every frame: the least distance between two of our jets in the air.
func _watch() -> void:
	var tv := _tv
	if tv == null or tv.flight == null:
		return
	var jets: Array = [tv.player_world()] + _wing.map(func(e): return e.world)
	for i in jets.size():
		for k in range(i + 1, jets.size()):
			_min_air = minf(_min_air, (jets[i] as Vector3).distance_to(jets[k]))


## Kidon 1-`n`'s call `id` made after `t0` (mission s).
func _said(n: int, id: String, t0: float) -> bool:
	for c in _tv.ai.flight_calls:
		if int(c.from) == n and String(c.id) == id and float(c.get("t", 0.0)) >= t0:
			return true
	return false


func _calls() -> String:
	return ", ".join(_tv.ai.flight_calls.map(func(c): return "%d %s" % [c.from, c.id]))


## The radio menu (Ctrl+T, sim_flight.gd): opened, each id of `path` picked by its number as the keys do.
func _menu(tv: Node, path: Array) -> bool:
	tv.addon.set_open(true)
	for id in ["m:wingmen"] + path:
		if not id in tv.addon.shown and "m:more" in tv.addon.shown:
			tv.addon.choose(tv.addon.shown.find("m:more") + 1)  # the page's lines after its first eight
		var i: int = tv.addon.shown.find(id)
		if i < 0:
			tv.addon.set_open(false)
			return false
		tv.addon.choose(i + 1)
	return true


## Waits until `cond` holds or `limit` s of sim time pass; true when it held.
func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true
