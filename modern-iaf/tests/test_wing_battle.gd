# Modern IAF's wingmen in a fight (docs/ai.md §8.9, modern-iaf/docs/ai-plan.md F5, F13, K4), headless: mission
# ramon_four_ship with the player's four-ship put in the air by the dev hook ai_flights.gd `flight_in_air` (no mission
# starts so), against a MiG-29A pair spawned 50 km ahead by `spawn` and flown by `enemy_flight` (no network). Our jets
# are shielded (a MiG's missile cannot end the test); the MiGs are not.
#   - "engage my target" to the flight on the lead MiG: Kidon 1-2 and 1-3 acknowledge and fight it (IafAi "foe" 1),
#     Kidon 1-4 stays on 1-3;
#   - "cover me" to Kidon 1-4 through the radio menu: acknowledged;
#   - a wingman's missile launched through combat.gd and its "Fox" call said with its subtitle;
#   - both MiGs shot down (the second engaged once the first is down); a kill by a wingman's weapons called "splash";
#   - the flight's rejoin through the radio menu: Kidon 1-2 and 1-3 back "in position";
#   - at least 30 m between any two of our jets all along; the AI's CPU per jet per frame at time scale 1.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_wing_battle.gd --log-file <temp>
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
	await _battle(tv)
	process_frame.disconnect(_watch)
	Engine.time_scale = 1.0
	s.invulnerable = false
	check(_min_air > 30.0, "at least 30 m between any two of our jets in the air (%.1f m)" % _min_air)


func _battle(tv: Node) -> void:
	var ai = tv.ai
	var fa = ai.flight_ai
	await fly(tv, 20.0)
	var j: Vector3 = tv.player_world()
	var migs: Array = []
	for x in [0.0, 1500.0]:
		var m: Dictionary = ai.spawn("mig29a", Vector3(j.x + x, j.y + 50000, ALT), 180.0, [])
		if not m.is_empty():
			migs.append(m)
	check(migs.size() == 2, "two MiG-29As in the air")
	if migs.size() != 2:
		return
	var f = ai.enemy_flight(migs, Vector3(j.x, j.y + 50000, ALT), {})
	check(f != null, "flown as an enemy pair")
	var t0: float = tv.runtime.now
	check(ai.engage(0, migs[0]), "engage my target taken")
	var took := func():
		return int(fa.state(2).get("foe", 0)) == 1 and int(fa.state(3).get("foe", 0)) == 1 and _said(2, "ack", t0)
	check(await _until(tv, took, 5.0), "Kidon 1-2 and 1-3 acknowledge and fight the target (%s)" % _calls())
	check(int(fa.state(4).get("foe", 0)) == 0 and int(fa.state(4).leader) == 3, "Kidon 1-4 stays on Kidon 1-3")
	check(_menu(tv, ["to:4", "cover"]), "cover me in the radio menu")
	await fly(tv, 3.0)
	check(_said(4, "ack", t0) and fa.state(4).get("covering", false), "Kidon 1-4 covers (%s)" % _calls())
	# The CPU per AI jet per frame at time scale 1 (X5), 10 s into the intercept.
	ai.cost_us = 0
	ai.cost_frames = 0
	await fly(tv, 10.0)
	var ms: float = ai.cost_us / 1000.0 / maxi(ai.cost_frames, 1) / maxi(ai.pilots.size(), 1)
	print("X5: %.3f ms per AI jet per frame (CPU; %d jets, %d frames)" % [ms, ai.pilots.size(), ai.cost_frames])
	Engine.time_scale = TIME_SCALE
	var fox := func():
		for n in [2, 3, 4]:
			for id in ["fox_1", "fox_2", "fox_3"]:
				if _said(n, id, t0):
					return true
		return false
	var launched := func():
		return tv.weapons.missiles.any(func(m): return _wing.any(func(e): return is_same(m.get_meta("owner", {}), e)))
	# A Sufa jams once a MiG's radar locks it (K9); the MiGs fly at its strobe (home on jam) to the burn-through.
	check(await _until(tv, func(): return fox.call() and launched.call(), 120.0), "a wingman's shot (%s)" % _calls())
	var heard := func(p): return String(p.template) == "WNG_CALL" and String(p.text).contains("fox")
	check(tv.radio.said.any(heard), "the Fox call said with its subtitle")
	# The first down, the lead's next target the other (each answers "unable" when it has nothing left).
	var one := func(): return migs.any(func(m): return int(m.state) >= 3)
	check(await _until(tv, one, 600.0), "a MiG shot down (%s)" % _calls())
	var left: Array = migs.filter(func(m): return int(m.state) < 3)
	if not left.is_empty():
		ai.engage(0, left[0])
	var down := func(): return migs.all(func(m): return int(m.state) >= 3)
	var ok := await _until(tv, down, 600.0)
	var phases: Array = [2, 3, 4].map(func(n): return String(fa.state(n).get("phase", "")))
	check(ok, "both MiGs shot down (%s; phases %s)" % [_calls(), phases])
	await fly(tv, 3.0)
	check([2, 3, 4].any(func(n): return _said(n, "splash", t0)), "a wingman's kill called splash (%s)" % _calls())
	t0 = tv.runtime.now
	check(_menu(tv, ["to:0", "rejoin"]), "rejoin in the radio menu")
	var back := func(): return _said(2, "in_position", t0) and _said(3, "in_position", t0)
	var st := func(n):
		return "#%d %s %.0f m %.0f kg" % [n, fa.state(n).stage, fa.state(n).slot_error, fa.state(n).fuel_kg]
	check(await _until(tv, back, 600.0), "Kidon 1-2 and 1-3 rejoin (%s; %s, %s)" % [_calls(), st.call(2), st.call(3)])
	check([2, 3, 4].all(func(n): return int(fa.state(n).get("foe", 0)) == 0), "no foe left")


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
