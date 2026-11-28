# The training range a mission names (`range`, modern-iaf/docs/data-formats.md §5.2; training-plan.md §1): a child of
# sim_flight.gd. Once the ground under the jet has loaded it stands the range's hulks on the ground (the bull at the
# circle's centre and the strafe row, convoys.gd `vehicle`) and, when the mission asks for its threats
# (`range_threats`), its SAM sites (air_defence.gd `spawn`). The positions are the compiled range's (sim.range: UTM
# 36N, the mission frame).
extends Node

const AirDefence := preload("res://shared/ai/air_defence.gd")
const Convoys := preload("res://shared/ai/convoys.gd")
## The range's entity ids: below the convoys' and the sites' counters' reach.
const FIRST_ID := -10000

var host: Node  # terrain_view.gd
var spec := {}
var threats := false
## What was placed (tests): {targets [entities], sites [site records]}; {} before.
var placed := {}
var _next_ground := 0.0


func _init(h: Node, range_spec: Dictionary, with_threats: bool) -> void:
	host = h
	spec = range_spec
	threats = with_threats
	name = "Range"


func _process(_delta: float) -> void:
	if placed.is_empty() and host.get("flight") != null and not host.waiting_for_ground and host.get("ai") != null:
		place()
	elif not placed.is_empty() and float(host.runtime.now) >= _next_ground:
		# ponytail: the far ground's finer heights load as the jet nears; every 5 s re-stands the few hulks on them.
		_next_ground = float(host.runtime.now) + 5.0
		for ent in placed.targets:
			var g = host.mission_ground(ent.world)
			if int(ent.state) < 3 and g != null:  # no ground loaded there: the last height stands
				ent.world.z = float(g)
				host.mission_entity_moved(ent)


## Stands the range's targets and (with `threats`) its sites; placed's record.
func place() -> Dictionary:
	placed = {"targets": [], "sites": []}
	var side := 1 if int(host.runtime.player_entity().get("side", 2)) == 2 else 2
	var targets: Array = spec.get("targets", [])
	for i in targets.size():
		var t: Dictionary = targets[i]
		var at := _ground(t.at)
		var key := "range:%d" % (i + 1)
		var ent: Dictionary = Convoys.vehicle(host, String(t.unit), key, FIRST_ID - i, at, float(t.heading), side)
		ent.name = String(t.name)
		placed.targets.append(ent)
	if threats:
		var ad: Node = AirDefence.of(host)
		for s in spec.get("sites", []):
			var ents: Array = ad.spawn(String(s.kind), Vector3(s.at[0], s.at[1], 0.0), float(s.heading))
			if not ents.is_empty():
				placed.sites.append(ad.site_of(ents[0]))
	print("range %s: %d targets, %d sites" % [spec.get("id", ""), placed.targets.size(), placed.sites.size()])
	return placed


## The point [x, y] on the ground (world).
func _ground(p: Array) -> Vector3:
	var g = host.mission_ground(Vector3(p[0], p[1], 0.0))
	return Vector3(p[0], p[1], float(g) if g != null else 0.0)
