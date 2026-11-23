# Low level (docs/ai.md §20, modern-iaf/docs/ai-plan.md K17), headless: mission ramon_four_ship with MK-82s on the
# Arming load (the four-ship carries the lead's), the flight put in the air by the dev hook ai_flights.gd
# `flight_in_air`.
#   - The lead's order (sim_flight.gd flight_command): "Low level" from the radio menu to the flight, each wingman
#     acknowledges and flies low; record 257 (Ctrl + \, command 108 p1 8) gives back to altitude, then low again.
#   Then low at 200 ft by the dev hook `flight_low`.
#   - "Engage my target" on an enemy 64N6E2 (air_defence.gd `spawn_net`) 25 km ahead, to Kidon 1-2: its run comes
#     down to the terrain following (profile "pop"), runs in low over the Negev, pops up, dives, releases ("alpha"),
#     egresses and reports "done"; never under the ground collision avoidance's floor.
#   - A site's march on the roads (K5): an S-300 battery placed on the road nearest a point 20 km ahead, its alternate
#     position on the road nearest a point 10 km further (the convoy's ends in test_convoy.gd, joined by roads); the
#     march order (IafSite `relocate`, a dev hook): the route keeps to the roads (when setup made the road layer), and
#     the battery drives it to the alternate position.
#   Our jets are shielded.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_low_level.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
const ALT := 2500.0
const SPEED := 230.0
## 200 ft; flight.rs FLOOR_M.
const AGL := 61.0
const FLOOR_M := 30.0

var _tv: Node


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
	var wing: Dictionary = {}
	for m in ai._ai_members:
		if not m[1].player:
			m[1].shield = true
			if int(m[0]) == 2:
				wing = m[1]
	s.invulnerable = true
	await _order(tv)
	check(ai.flight_low(AGL), "the flight low at 200 ft (dev hook)")
	Engine.time_scale = TIME_SCALE
	await fly(tv, 3.0)
	await _attack(tv, wing)
	Engine.time_scale = 1.0
	s.invulnerable = false
	_site_march(tv)


func _order(tv: Node) -> void:
	var fa = tv.ai.flight_ai
	var t0: float = tv.runtime.now
	check(_menu(tv, ["to:0", "low"]), "Low level from the radio menu, to the flight")
	var acked := func(): return _said(2, "ack", t0) and _said(3, "ack", t0) and _said(4, "ack", t0)
	check(await _until(tv, acked, 10.0), "each wingman acknowledges (%s)" % _calls())
	check(await _until(tv, func(): return fa.state(2).low and fa.state(4).low, 5.0), "the flight flies low")
	tv._command([108, 8, 0])  # record 257, Ctrl + \: the flight flies low, so back to altitude
	check(await _until(tv, func(): return not fa.state(2).low, 10.0), "the key: back to altitude")
	tv._command([108, 8, 0])
	check(await _until(tv, func(): return fa.state(2).low, 10.0), "the key again: low level")


func _attack(tv: Node, wing: Dictionary) -> void:
	var ai = tv.ai
	var fa = ai.flight_ai
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	var ents: Array = ad.spawn_net(Vector3(j.x, j.y + 25000, 0), Vector3(j.x + 3000, j.y + 28000, 0), [])
	var radar: Dictionary = ents[0]
	tv.weapons.radar.designated = true
	tv.weapons.radar.desig = radar.world
	var t0: float = tv.runtime.now
	check(_menu(tv, ["to:2", "engage"]), "engage my target, to Kidon 1-2")
	tv.weapons.radar.designated = false
	check(await _until(tv, func(): return _said(2, "in", t0), 10.0), "Kidon 1-2 runs in (%s)" % _calls())
	check(String(fa.state(2).profile) == "pop", "the pop-up for its MK-82s from low: %s" % fa.state(2))
	# Its height over the terrain each frame until "done": the run-in band (from 15 to 9 km out), the least, the apex.
	var band := [INF, 0.0]
	var least := INF
	var apex := 0.0
	var t1: float = tv._sim_time
	while not _said(2, "done", t0) and tv._sim_time - t1 < 400.0:
		await process_frame
		var g = tv.scene_ground(tv.world_to_scene(wing.world))
		if g == null:
			continue
		var agl: float = wing.world.z - float(g)
		var d := Vector2(wing.world.x - radar.world.x, wing.world.y - radar.world.y).length()
		if String(fa.state(2).strike) == "run" and d < 15000.0 and d > 9000.0:
			band = [minf(band[0], agl), maxf(band[1], agl)]
		if d < 7400.0:
			apex = maxf(apex, agl)
		least = minf(least, agl)
	print("Kidon 1-2: run-in %.0f..%.0f m, apex %.0f m, least %.0f m" % [band[0], band[1], apex, least])
	check(band[1] > 0.0 and band[0] > FLOOR_M and band[1] < 200.0, "the run-in low on the terrain following")
	check(apex > 1000.0, "the pop-up (%.0f m)" % apex)
	check(_said(2, "alpha", t0), "Kidon 1-2 releases: alpha (%s)" % _calls())
	check(_said(2, "done", t0), "and reports done (%s)" % _calls())
	check(least > FLOOR_M, "never under the floor (%.0f m)" % least)


func _site_march(tv: Node) -> void:
	var j: Vector3 = tv.player_world()
	var ends := [Vector3(j.x, j.y + 20000, 0), Vector3(j.x, j.y + 30000, 0)]
	var ground_roads: GDScript = load("res://shared/terrain/ground_roads.gd")
	var roads: bool = ground_roads.available() and IafRoads.open(ground_roads.dir())
	if roads:
		for i in 2:
			var n: Dictionary = IafRoads.nearest(Vector2(ends[i].x, ends[i].y), 4)
			if not n.is_empty():
				ends[i] = Vector3(n.point.x, n.point.y, 0)
	var site = IafSite.create("s300", ends[0], 0.0, [ends[1]])
	site.relocate(0.0)
	var now := 0.0
	var out: Dictionary = site.tick(now, [], [], tv.mission_ground)
	var st: Dictionary = site.state(now)
	check(String(out.phase) == "march" and int(st.at) == 1, "the march order (dev hook): %s" % st.phase)
	var route: Dictionary = st.route
	var on_road: int = route.road.count(true)
	print(
		(
			"march route: %d points, %d of %d segments road, %.0f m"
			% [route.points.size(), on_road, route.road.size(), route.length]
		)
	)
	if roads:
		check(on_road > 0, "the march keeps to the roads")
	# Ticked every 0.5 s: each position on the route until it sets up at the alternate position.
	var pts: PackedVector2Array = route.points
	var off := 0.0
	while now < 20000.0 and String(site.state(now).phase) in ["march", "move"]:
		now += 0.5
		site.tick(now, [], [], tv.mission_ground)
		var p: Vector3 = site.state(now).pos
		off = maxf(off, _off_route(Vector2(p.x, p.y), pts))
	var end: Vector3 = site.state(now).pos
	print("arrived after %.0f s, %.1f m off its route at the most" % [now, off])
	check(off < 1.0, "every position on its route")
	check(Vector2(end.x - ends[1].x, end.y - ends[1].y).length() < 1.0, "at the alternate position")


## The distance from `p` to the polyline `pts`.
static func _off_route(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


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
