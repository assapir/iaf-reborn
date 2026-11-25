# Scramble's enemy and its AWACS task in flight (הזנקה, the front end's Scramble, modern-iaf/docs/front-end.md §2.1;
# docs/ai.md §23): a child of sim_flight.gd on a Scramble start (category fly_now). Once the ground under the jet is
# loaded it draws the enemy (IafFreeCombat.roll from Settings.free_combat's seed at the pilot's enemy skill) and places
# it where IafFreeCombat.plan lays it out round the fight's base, through the AI's hooks: the sites and the network
# (air_defence.gd), the MiG-29A pairs on CAP and parked at the fight's base (ai_flights.gd `spawn`, `enemy_flight`,
# `enemy_base`: the sim has no enemy base, so that base stands in), the convoy (convoys.gd, on the roads nearest its
# ends), the drones (drones.gd). Then the AWACS gives the task the roll was built round (IafFreeCombat.task_call:
# "Kidon 1, attack the convoy, bearing 040, 25 miles, free to engage") once the player's jet is in the air, and again
# while its target is alive (IafFreeCombat.task_due). On the air start the flight's own calls wait for the first task
# call (radio.gd hold_calls), so the AWACS speaks first.
extends Node

const AirDefence := preload("res://shared/ai/air_defence.gd")
const Convoys := preload("res://shared/ai/convoys.gd")
const Drones := preload("res://shared/ai/drones.gd")
const Eitam := preload("res://shared/ai/eitam.gd")
const GroundRoads := preload("res://shared/terrain/ground_roads.gd")
const Fly := preload("fly.gd")
const MIG := "mig29a"
const CONVOY := ["target_t72", "target_ural", "target_ural", "target_t72"]

var host: Node  # terrain_view.gd
## The player's base: the Scramble start's (its iaf.ibx section).
var home := ""
## What was placed (tests): {sites [site records], net {} or the network, flights [the enemy pairs' IafAi], convoy {},
## salvo {}, setup (the roll), task (its name), targets [the task's entities; a drone's null before its launch]}; {}
## before.
var placed := {}
## The task call's clock (the runtime's): when the player's jet first left the ground, the last call (-INF: none).
var _airborne_at := -1.0
var _said_at := -INF


func _init(h: Node, home_base: String) -> void:
	host = h
	home = home_base
	name = "FreeCombat"


func _process(_delta: float) -> void:
	if placed.is_empty() and host.get("flight") != null and not host.waiting_for_ground and host.get("ai") != null:
		var fc: Dictionary = Settings.free_combat
		place(fc, IafFreeCombat.roll(int(fc.get("seed", 0)), int(Settings.enemy_skill())))
	elif not placed.is_empty():
		_task()


## Places `setup` (IafFreeCombat.roll's: the enemy and its task) round the area of `fc` (Settings.free_combat's
## shape: the front end drew it, Fly.free_area), facing `home`; placed's record. An area that is no other base of the
## theatre places nothing. A runway start takes off in pairs (ai_flights.gd flight_pairs), as it is lined up.
func place(fc: Dictionary, setup: Dictionary) -> Dictionary:
	var ibx: Dictionary = Fly._ibx()
	var area := String(fc.get("area", ""))
	placed = {
		"sites": [], "net": {}, "flights": [], "convoy": {}, "salvo": {}, "setup": setup, "task": "", "targets": []
	}
	if area == home or not ibx.has(home) or not ibx.has(area):
		push_warning("scramble: nothing placed (%s -> %s)" % [home, area])
		return placed
	placed.task = String(setup.get("task", ""))
	if host.get("radio") != null:
		host.radio.awacs_task = task_target  # the AWACS's vector to the target (docs/ai.md §24.2)
	if fc.get("start", "air") == "air" and host.get("radio") != null:
		host.radio.hold_calls(true)
	if fc.get("start", "air") == "runway":
		host.ai.flight_pairs(true)
	# The Eitam on its station behind the flight's way to the fight (docs/ai.md §24.3).
	Eitam.of(host).place(Fly._lineup(ibx, area), Fly._lineup(ibx, home), host.player_world())
	var ad: Node = AirDefence.of(host)
	var plan: Array = IafFreeCombat.plan(setup, Fly._lineup(ibx, home), Fly._lineup(ibx, area))
	for s in plan:
		match String(s.kind):
			"site":
				var ents: Array = ad.spawn(s.site, s.pos, s.heading)
				if not ents.is_empty():
					placed.sites.append(ad.site_of(ents[0]))
					if s.site == "s300" and placed.task == "sam":
						placed.targets += ents
			"net":
				placed.net = ad.net_of(ad.spawn_net(s.radar, s.post, placed.sites, s.heading)[0])
			"cap":
				var jets: Array = s.jets.map(func(p): return host.ai.spawn(MIG, p, s.heading, []))
				jets = jets.filter(func(e): return not e.is_empty())
				var f = host.ai.enemy_flight(jets, s.station, placed.net) if not jets.is_empty() else null
				if f != null:
					placed.flights.append(f)
				if placed.task == "cap":
					placed.targets += jets
			"based":
				var f = host.ai.enemy_base(MIG, area, 2, s.station, placed.net, -1, int(s.first))
				if f != null:
					placed.flights.append(f)
			"convoy":
				placed.convoy = Convoys.of(host).spawn(CONVOY, _road(s.from), _road(s.to))
				if placed.task == "convoy":
					placed.targets = placed.convoy.get("ents", [])
			"drones":
				placed.salvo = Drones.of(host).spawn(s.route, int(s.count), 0.0, float(s.interval))
				if placed.task == "drones":
					placed.targets = placed.salvo.get("ents", [])  # the salvo's own list: filled at each launch
	print(
		(
			"scramble: %d sites, %d enemy pairs at %s, task %s"
			% [placed.sites.size(), placed.flights.size(), area, placed.task]
		)
	)
	return placed


## The AWACS's task call (IafFreeCombat.task_due, task_call) to the player about the task's target nearest the jet,
## said and subtitled by the radio (radio.gd `say`); none once every target is down. Returns the call [template,
## particles], [] when none was said.
func _task() -> Array:
	var rt = host.get("runtime")
	if rt == null or host.radio == null or host.flight == null:
		return []
	var now: float = rt.now
	if _airborne_at < 0.0:
		if not bool(host.flight.state().get("on_ground", true)):
			_airborne_at = now
		return []
	if not IafFreeCombat.task_due(now - _airborne_at, now - _said_at):
		return []
	var me: Vector3 = host.player_world()
	var best = task_target()
	var call: Array = []
	if best != null:
		call = IafFreeCombat.task_call(placed.task, host.radio.formation_name(rt.player_entity()), me, best)
	if not call.is_empty():
		_said_at = now
		host.radio.say(call[0], Array(call[1]))
	host.radio.hold_calls(false)  # the flight's calls after the task (none due: at once)
	return call


## The task's target alive nearest the player's jet (world), null when none is left.
func task_target() -> Variant:
	var me: Vector3 = host.player_world()
	var best = null
	for e in placed.get("targets", []):
		if e is Dictionary and not int(e.get("state", 0)) in [4, 5]:
			var w: Vector3 = host.ai.world_of(e)
			if best == null or me.distance_to(w) < me.distance_to(best):
				best = w
	return best


## The road point nearest `p` (the road layer, when setup made it), else `p`.
static func _road(p: Vector3) -> Vector3:
	if GroundRoads.available() and IafRoads.open(GroundRoads.dir()):
		var n: Dictionary = IafRoads.nearest(Vector2(p.x, p.y), 4)
		if not n.is_empty():
			return Vector3(n.point.x, n.point.y, 0)
	return p
