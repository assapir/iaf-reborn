# Modern IAF's moving ground vehicles (docs/ai.md §19, modern-iaf/docs/ai-plan.md K16), headless: mission
# ramon_four_ship with MK-82s on the Arming load (the four-ship carries the lead's), the flight put in the air by the
# dev hook ai_flights.gd `flight_in_air`, a convoy of two T-72s and two Ural-4320s spawned by the dev hook
# convoys.gd `spawn` on the roads 20 km ahead.
#   - The column drives: on the road where the route has one, the vehicles about SPACING_M apart, on the ground.
#   - "Engage my target" with the radar's point on its head: the wingmen attack the moving T-72 one after the other
#     (led by its velocity, strike.rs); the first bombs scatter the convoy off the road, every vehicle stops.
#   - After the attack, QUIET_S without a blast: the survivors drive back onto the route and on.
#   Our jets are shielded.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_convoy.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
const ALT := 4000.0
const SPEED := 230.0
## convoy.rs SPACING_M.
const SPACING_M := 100.0


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
	for m in ai._ai_members:
		if not m[1].player:
			m[1].shield = true
	s.invulnerable = true
	Engine.time_scale = TIME_SCALE
	await _convoy(tv)
	Engine.time_scale = 1.0
	s.invulnerable = false


func _convoy(tv: Node) -> void:
	var ai = tv.ai
	var j: Vector3 = tv.player_world()
	# Its ends on the roads nearest two points 20 and 30 km ahead (the road layer), else those points.
	var ends := [Vector3(j.x, j.y + 20000, 0), Vector3(j.x, j.y + 30000, 0)]
	var ground_roads: GDScript = load("res://shared/terrain/ground_roads.gd")
	if ground_roads.available() and IafRoads.open(ground_roads.dir()):
		for i in 2:
			var n: Dictionary = IafRoads.nearest(Vector2(ends[i].x, ends[i].y), 4)
			if not n.is_empty():
				ends[i] = Vector3(n.point.x, n.point.y, 0)
	var cs: Node = load("res://shared/ai/convoys.gd").of(tv)
	var cv: Dictionary = cs.spawn(["target_t72", "target_ural", "target_ural", "target_t72"], ends[0], ends[1])
	check(not cv.is_empty() and cv.ents.size() == 4, "a convoy of four (dev hook)")
	if cv.is_empty():
		return
	var route: Dictionary = cv.convoy.route()
	var on_road: int = route.road.count(true)
	print(
		(
			"route: %d points, %d of %d segments road, %.0f m"
			% [route.points.size(), on_road, route.road.size(), route.length]
		)
	)
	if ground_roads.available():
		check(on_road > 0, "the route keeps to the roads")
	var head: Dictionary = cv.ents[0]
	check(tv.enemy_of_player(head) and int(head.klass) == 6, "its vehicles are enemy ground units")
	var start: Vector3 = head.world
	await fly(tv, 20.0)
	check(String(cv.convoy.phase()) == "move" and head.vel.length() > 3.0, "the column drives (%s)" % head.vel)
	check(Vector2(head.world.x - start.x, head.world.y - start.y).length() > 100.0, "the head moved on")
	for i in 3:
		var gap: float = (cv.ents[i].world - cv.ents[i + 1].world).length()
		check(gap > SPACING_M * 0.5 and gap < SPACING_M * 1.05, "vehicle %d %.0f m behind the one ahead" % [i + 2, gap])
	var g = tv.terrain.height_at(tv.world_to_scene(head.world))
	check(g != null and absf(float(head.alt) - float(g)) < 0.5, "on the ground (%s, %s)" % [head.alt, g])
	# The wingmen at its head: the radar's point on it, "engage my target".
	tv.weapons.radar.designated = true
	tv.weapons.radar.desig = head.world
	check(_menu(tv, ["to:0", "engage"]), "engage my target in the radio menu")
	tv.weapons.radar.designated = false
	check(is_same(ai.attack_ent, head), "the ground target taken: the moving T-72")
	var scattered := func(): return String(cv.convoy.phase()) == "scatter"
	check(await _until(tv, scattered, 400.0), "the convoy scatters under the attack (%s)" % ai.flight_ai.state(2))
	var at_scatter: Array = cv.ents.map(func(e): return e.world)
	await fly(tv, 30.0)
	for i in 4:
		var e: Dictionary = cv.ents[i]
		if int(e.state) >= 3:
			print("vehicle %d destroyed" % (i + 1))
			continue
		var off: float = Vector2(e.world.x - at_scatter[i].x, e.world.y - at_scatter[i].y).length()
		check(off > 40.0 or String(cv.convoy.phase()) != "scatter", "vehicle %d off the road (%.0f m)" % [i + 1, off])
	var hurt := func(): return cv.ents.any(func(e): return float(e.damage) > 0.0 or int(e.state) >= 3)
	check(hurt.call(), "the bombs found the convoy")
	var over := func(): return [2, 3, 4].all(func(n): return String(ai.flight_ai.state(n).strike) == "")
	check(await _until(tv, over, 600.0), "every attack over")
	var alive: Array = cv.ents.filter(func(e): return int(e.state) < 3)
	if alive.is_empty():
		print("every vehicle destroyed: nothing to drive on")
		return
	var moving := func(): return String(cv.convoy.phase()) == "move" and alive[0].vel.length() > 3.0
	check(await _until(tv, moving, 200.0), "the survivors back on the route, driving on (%s)" % cv.convoy.phase())


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
