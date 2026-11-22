# The AI jets' air-to-ground attack (docs/ai.md §8.10, modern-iaf/docs/ai-plan.md F15, K15), headless: mission
# ramon_four_ship with MK-82s on the Arming load (the four-ship carries the lead's), the flight put in the air by the
# dev hook ai_flights.gd `flight_in_air`.
#   - Our four-ship: an enemy 64N6E2 radar (air_defence.gd `spawn_net`, the network's stand-in shapes) 20 km ahead,
#     designated on the radar (the SPI); "engage my target" to the flight through the radio menu: Kidon 1-2, 1-3 and
#     1-4 acknowledge and attack it one after the other: "in" with its subtitle, the release through combat.gd's AI
#     ripple ("alpha"), the radar destroyed, "done", each back on the slot.
#   - A MiG-29A pair (spawned by `spawn` with two MK-83s each standing in for its FAB-500s, flown by `enemy_flight`)
#     on its lead's own order (`enemy_strike`) against a 64N6E2 of our side: the lead releases on it, it is destroyed
#     (the target gone ends the wingman's turn), the lead goes back to its CAP.
#   Our jets are shielded.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_ground_attack.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
const ALT := 4000.0
const SPEED := 230.0

var _tv: Node
var _wing: Array = []


func run() -> void:
	var s := settings()
	var id := sim_mission("ramon_four_ship")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", IafBriefing.put(rec, "", 3, "mk-82", true))
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	await frames(2)
	tv.addon.rules = {}  # unscored
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
	var u = ai.combat.units.get(_wing[0].key) if not _wing.is_empty() else null
	check(u != null and int(ai._ag_of(u)[1]) == 1, "the wingmen carry the MK-82s")
	Engine.time_scale = TIME_SCALE
	await fly(tv, 5.0)
	await _ours(tv)
	await _migs(tv)
	Engine.time_scale = 1.0
	s.invulnerable = false


func _ours(tv: Node) -> void:
	var ai = tv.ai
	var fa = ai.flight_ai
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	var ents: Array = ad.spawn_net(Vector3(j.x, j.y + 20000, 0), Vector3(j.x + 3000, j.y + 23000, 0), [])
	var radar: Dictionary = ents[0]
	check(tv.enemy_of_player(radar), "an enemy 64N6E2 20 km ahead")
	# Designated on the radar: the SPI on it (the radar's designated point).
	tv.weapons.radar.designated = true
	tv.weapons.radar.desig = radar.world
	var t0: float = tv.runtime.now
	check(_menu(tv, ["to:0", "engage"]), "engage my target in the radio menu")
	tv.weapons.radar.designated = false
	check(is_same(ai.attack_ent, radar), "the ground target taken: the 64N6E2 nearest the SPI")
	var acks := func(): return [2, 3, 4].all(func(n): return _said(n, "ack", t0))
	check(await _until(tv, acks, 5.0), "Kidon 1-2, 1-3 and 1-4 acknowledge (%s)" % _calls())
	check(String(fa.state(2).strike) in ["wait", "run"], "Kidon 1-2 attacks: %s" % fa.state(2))
	check(await _until(tv, func(): return _said(2, "in", t0), 10.0), "Kidon 1-2 runs in (%s)" % _calls())
	check(String(fa.state(2).profile) == "dive", "a dive for its MK-82s")
	var heard := func(p):
		return String(p.template) == "WNG_CALL" and String(p.text).strip_edges().trim_suffix(".").ends_with(", in")
	check(tv.radio.said.any(heard), "the run-in call said with its subtitle")
	var alpha := func(): return _said(2, "alpha", t0)
	check(await _until(tv, alpha, 240.0), "Kidon 1-2 releases: alpha (%s; %s)" % [_calls(), fa.state(2)])
	var dropped := func(): return tv.weapons.bombs.any(func(b): return is_same(b.owner, _wing[0]))
	check(dropped.call() or int(radar.state) >= 3, "its MK-82s fall")
	var down := func(): return int(radar.state) >= 3
	check(await _until(tv, down, 300.0), "the 64N6E2 destroyed (%s)" % _calls())
	var done := func(): return [2, 3, 4].any(func(n): return _said(n, "done", t0))
	check(await _until(tv, done, 120.0), "an attacker reports done (%s)" % _calls())
	var over := func(): return [2, 3, 4].all(func(n): return String(fa.state(n).strike) == "")
	check(await _until(tv, over, 120.0), "every attack over, the target gone: back to the slots")
	check(ai.attack_ent.is_empty(), "no ground target left")


func _migs(tv: Node) -> void:
	var ai = tv.ai
	var ad: Node = tv.ai.get_node("AirDefence")  # made by _ours
	var j: Vector3 = tv.player_world()
	var mine := int(tv.runtime.player_entity().get("side", 2))
	var ours: Array = ad.spawn_net(Vector3(j.x + 60000, j.y, 0), Vector3(j.x + 63000, j.y, 0), [], 0.0, mine)
	var radar: Dictionary = ours[0]
	check(not tv.enemy_of_player(radar), "a 64N6E2 of our side 60 km east")
	var arm := {1: ["MK-83", 1], 2: ["MK-83", 1], 6: ["MK-83", 1], 7: ["MK-83", 1]}
	var migs: Array = []
	for x in [0.0, 1500.0]:
		var at := Vector3(j.x + 60000 + x, j.y - 30000, 5000.0)
		var m: Dictionary = ai.spawn("mig29a", at, 0.0, [], -1, arm)
		if not m.is_empty():
			migs.append(m)
	check(migs.size() == 2, "two MiG-29As with bombs")
	if migs.size() != 2:
		return
	var u = ai.combat.units.get(migs[0].key)
	check(int(ai._ag_of(u)[1]) == 1, "MK-83s on its pylons")
	var f = ai.enemy_flight(migs, migs[0].world, {})
	check(ai.enemy_strike(f, radar), "its lead's own attack order")
	var t0: float = tv.runtime.now
	var empty := func(m): return int(ai._ag_of(ai.combat.units.get(m.key))[1]) == 0
	var one := func(): return migs.any(empty)
	check(await _until(tv, one, 400.0), "a MiG releases (%s, %s)" % [f.state(1), f.state(2)])
	var down := func(): return int(radar.state) >= 3
	check(await _until(tv, down, 120.0), "our 64N6E2 destroyed")
	print("MiGs emptied: lead %s, wingman %s" % [empty.call(migs[0]), empty.call(migs[1])])
	var cap := func(): return String(f.state(1).phase) == "cap" and String(f.state(1).strike) == ""
	check(await _until(tv, cap, 200.0), "the lead back on its CAP (%s)" % f.state(1))
	print("MiG strike over after %.0f s" % (tv.runtime.now - t0))


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
