# The big fight (modern-iaf/docs/ai-plan.md K12, X5; docs/ai.md §22): one scenario with everything at once, put
# together from the dev hooks; no mission places it. Used by test_big_fight.gd (headless) and _big_fight_movie.gd (the
# real render). Mission ramon_four_ship, MK-82s on the Arming load (the four-ship carries the lead's), the flight put
# in the air over Ramon heading north (ai_flights.gd `flight_in_air`); the player's jet flies on ALT HOLD and HDG SEL,
# invulnerable; the wingmen are not shielded. The enemy, at the pilot's skill (Medium by default):
#   - a convoy of two T-72s and two Ural-4320s on the roads 25 to 35 km north (convoys.gd), a Tor-M1 and a ZSU-23-4
#     beside it (air_defence.gd `spawn`);
#   - an S-300PMU-2 battery 65 km north (its 96L6E, 30N6E2 and four launchers) under an 83M6E2 network (64N6E2 and
#     54K6E2, `spawn_net`) that the Tor and the ZSU join too;
#   - a MiG-29A pair on CAP 85 km north (ai_flights.gd `spawn`, `enemy_flight`) and a pair parked at Nevatim that
#     scrambles on the network's vector (`enemy_base`; the sim has no enemy base, so Nevatim stands in), both
#     vectored by the network;
#   - a salvo of four Shahed-136s from the north at Ramon (drones.gd).
# The lead's orders, as the radio menu gives them (sim_flight.gd flight_command): "low level" to the flight at once;
# "sort" once a MiG is within SORT_M; "weapons free" to the element round the MiGs; then "engage my target" to Kidon
# 1-2 with the radar's point on the convoy's first vehicle alive (the ground attack, its run in low and popping up).
extends RefCounted

const ALT := 6000.0
const SPEED := 230.0
## A MiG this near the lead (m): the sort.
const SORT_M := 60000.0
## After the sort (s): weapons free to the element, then the ground attack.
const FREE_AFTER := 8.0
const ATTACK_AFTER := 12.0

var tv: Node
var ai
## The lead's start (world): the scenario's origin.
var origin := Vector3.ZERO
var wing: Array = []
var cap: Array = []
var based: Array = []
var cap_flight
var based_flight
var convoy: Dictionary = {}
var salvo: Dictionary = {}
## The air-defence parts' entities: the S-300's, the network's, the Tor's, the ZSU's.
var sites: Array = []
var orders: Array = []
var _sorted_at := -1.0
## `spawn` done.
var spawned := false


## Starts the mission and puts our flight in the air; false (a check failed or no data) ends the run. `t` is the test.
func start(t) -> bool:
	var s: Node = t.settings()
	var id: int = t.sim_mission("ramon_four_ship")
	if id < 0:
		print("NEEDS DATA: the big fight reads the sim's compiled missions (./modern-iaf-setup)")
		return false
	s.language = "en"
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", IafBriefing.put(rec, "", 3, "mk-82", true))
	load("res://flight/fly.gd").start(id)
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await t.process_frame
		tv = t.current_scene
	IafPilotLog.set_loadout(db, s.pilot(), "f16i", "")
	await t.frames(2)
	tv.addon.rules = {}  # unscored
	ai = tv.ai
	if ai.flight_ai == null:
		t.check(false, "IafAi flies the four-ship")
		return false
	origin = tv.player_world()
	var pos: Vector3 = tv.world_to_scene(Vector3(origin.x, origin.y, ALT))
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(SPEED, 0, 0), t.airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.6
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])  # ROLL: HDG SEL
	await t.frames(2)
	tv.flight.set_ap_panel(false, false, false, 0.0, -1.0)
	t.check(ai.flight_in_air(0.0), "the flight in the air (dev hook)")
	s.invulnerable = true  # the lead flies on its autopilot: only the AI fights
	wing = ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	t.check(wing.size() == 3, "three wingmen (%d)" % wing.size())
	t.check(s.enemy_skill() == 1, "the enemy at Medium skill (%d)" % s.enemy_skill())
	return true


## The enemy put in place (after `start`); false when a part of it could not be.
func spawn(t) -> bool:
	var o := origin
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	# The convoy's ends on the roads nearest two points 25 and 35 km north (the road layer), else those points.
	var ends := [Vector3(o.x, o.y + 25000, 0), Vector3(o.x, o.y + 35000, 0)]
	var ground_roads: GDScript = load("res://shared/terrain/ground_roads.gd")
	if ground_roads.available() and IafRoads.open(ground_roads.dir()):
		for i in 2:
			var n: Dictionary = IafRoads.nearest(Vector2(ends[i].x, ends[i].y), 4)
			if not n.is_empty():
				ends[i] = Vector3(n.point.x, n.point.y, 0)
	convoy = load("res://shared/ai/convoys.gd").of(tv).spawn(
		["target_t72", "target_ural", "target_ural", "target_t72"], ends[0], ends[1]
	)
	t.check(convoy.get("ents", []).size() == 4, "a convoy of four on the road")
	var mid: Vector3 = (ends[0] + ends[1]) / 2.0
	var s300: Array = ad.spawn("s300", Vector3(o.x + 10000, o.y + 65000, 0), 180.0)
	var tor: Array = ad.spawn("tor", mid + Vector3(1500, 1000, 0), 180.0)
	var zsu: Array = ad.spawn("zsu", mid + Vector3(-800, -500, 0), 180.0)
	var members: Array = [s300, tor, zsu].filter(func(a): return not a.is_empty()).map(func(a): return ad.site_of(a[0]))
	t.check(members.size() == 3, "an S-300 battery, a Tor and a ZSU")
	var net_ents: Array = ad.spawn_net(
		Vector3(o.x + 15000, o.y + 70000, 0), Vector3(o.x + 16000, o.y + 69000, 0), members
	)
	var net: Dictionary = ad.net_of(net_ents[0])
	sites = s300 + net_ents + tor + zsu
	for x in [5000.0, 6500.0]:
		var m: Dictionary = ai.spawn("mig29a", Vector3(o.x + x, o.y + 85000, ALT + 1000), 180.0, [])
		if not m.is_empty():
			cap.append(m)
	cap_flight = ai.enemy_flight(cap, Vector3(o.x + 5000, o.y + 85000, ALT + 1000), net) if cap.size() == 2 else null
	t.check(cap_flight != null, "a MiG-29A pair on CAP")
	var ibx: Dictionary = Settings.load_ibx(Settings.own_dir().path_join("iaf.ibx"))
	var nb: Dictionary = ibx.get("Nevatim", {})
	var station := Vector3(float(nb.get("LineupLocX", 0)), float(nb.get("LineupLocY", 0)), ALT)
	based_flight = ai.enemy_base("mig29a", "Nevatim", 2, station, net)
	if based_flight != null:
		based = ai.enemy_flights[-1].members.map(func(m): return m[1])
	t.check(based.size() == 2, "a MiG-29A pair parked at Nevatim")
	var route := [Vector3(o.x - 15000, o.y + 70000, o.z), Vector3(o.x - 3000, o.y + 5000, o.z), o]
	salvo = load("res://shared/ai/drones.gd").of(tv).spawn(route, 4, 0.0, 10.0)
	t.check(not salvo.is_empty(), "four Shahed-136s launched")
	spawned = true
	return not (convoy.is_empty() or cap_flight == null or based_flight == null or salvo.is_empty())


## Every AI jet of the fight (ours and theirs).
func jets() -> Array:
	return wing + cap + based


## The lead's orders, each frame: "low level" at once, the sort once a MiG is near, then weapons free and the attack.
func step() -> void:
	var now: float = tv.runtime.now
	var me: Vector3 = tv.player_world()
	if not "low" in orders:
		_order(0, "low", null)
		return
	var alive: Array = (cap + based).filter(
		func(m): return int(m.state) < 3 and not m.pilot._state.get("on_ground", false)
	)
	if not "sort" in orders:
		if alive.any(func(m): return Vector3(m.world).distance_to(me) < SORT_M):
			_order(0, "sort", null)
			_sorted_at = now
		return
	if not "free" in orders and now - _sorted_at > FREE_AFTER:
		# Round the MiGs alive in the air, else round the lead itself.
		var mid := me
		if not alive.is_empty():
			mid = Vector3.ZERO
			for m in alive:
				mid += Vector3(m.world) / alive.size()
		_order(5, "free", me + (mid - me).limit_length(30000.0))
	var head: Array = convoy.ents.filter(func(e): return int(e.state) < 3)
	if not "engage" in orders and now - _sorted_at > ATTACK_AFTER and not head.is_empty():
		_order(2, "engage", Vector3(head[0].world))


## Order `id` to `to` through the radio menu's path (sim_flight.gd flight_command), with the radar's point at `spi`.
func _order(to: int, id: String, spi) -> void:
	var r = tv.weapons.radar
	if spi != null:
		r.designated = true
		r.desig = spi
	tv.addon.flight_command(to, id)
	r.designated = false
	orders.append(id)
