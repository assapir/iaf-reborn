## Modern IAF's Eitam in the sky (docs/ai.md §24.3): the IAF's G550 CAEW flown by the Rust Eitam (IafAwacs,
## crates/iaf-ai/src/eitam.rs: its 6-DoF under the autopilot's steer loop) on its standoff orbit, as a mission entity
## ("eitam", class 3: a fixed-wing mover) of the player's side with its model and radar cross-section, so the enemy's
## radars, sites and fighters see and attack it as any of ours and the existing damage path brings it down. Its call
## for help is said by the radio, and the group it names goes to the flight AI as a contact call does. Shot down, the
## controller's service ends (IafAwacs.eitam_down). Placed by Scramble (modern-iaf/flight/free_combat.gd) and the tests.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const Gltf := preload("res://shared/util/gltf.gd")

## Strength: our damage scale's fighter (300): one missile brings it down (modern-iaf/docs/data-formats.md §6;
## inferred: an unarmoured airliner is no stronger).
const STRENGTH := 300.0
## The span (m): Wikipedia's 28.50 (docs/ai.md §24.3).
const SPAN := 28.5

var host: Node  # terrain_view.gd
## Its entity, {} before it is placed.
var ent := {}
var _last := -1.0
var _down := false


## The Eitam of the flight `h` (terrain_view.gd), made on first use.
static func of(h: Node) -> Node:
	var n: Node = h.ai.get_node_or_null("Eitam")
	if n == null:
		n = load("res://shared/ai/eitam.gd").new()
		n.name = "Eitam"
		n.host = h
		h.ai.add_child(n)
	return n


## The Eitam on its station for a fight at `area` flown from `home` (the flight's base) and `start` (its start
## point), all world points (IafAwacs.place_eitam); its entity.
func place(area: Vector3, home: Vector3, start: Vector3) -> Dictionary:
	var aw = host.radio.awacs
	if aw == null:
		return {}
	if not aw.place_eitam(area, home, start, Settings.own_dir()):
		return {}
	var d: Dictionary = aw.eitam()
	var side := int(host.runtime.player_entity().get("side", 2))
	var e := {"0x1e": -9000, "0x2bc": "EITAM", "0x2e4": d.pos.x, "0x2ee": d.pos.y, "0x2f8": d.pos.z}
	e.merge({"0x2d0": side, "0x302": d.heading})
	ent = MissionRuntime.entity(e, "eitam", -1, false)
	MissionRuntime._init_damage(ent, {"0x5aa": 3, "0x56e": STRENGTH, "0x564": SPAN, "0x58c": 1, "0x514": "eitam"})
	ent.airborne_class = true  # mission_entity_moved keeps it off the ground
	ent.half_span = SPAN / 2.0  # the gun's hit test (gun_rounds.gd half_span_of)
	ent.rcs = IafAwacs.eitam_rcs()  # the radars (radar.gd _feed, air_defence.gd jets)
	ent.eitam = true
	ent.node = Gltf.instance(Gltf.model(Gltf.UNITS["EITAM"]))
	host.add_child(ent.node)
	host.runtime.entities[ent.key] = ent
	_move(d)
	return ent


## A child of ai_flights.gd: it runs after every jet's step of the frame, on the runtime's clock.
func _process(_delta: float) -> void:
	if ent.is_empty() or _down:
		return
	var now: float = host.runtime.now
	var dt := now - _last if _last >= 0.0 else 0.0
	_last = now
	if host.frozen or host.waiting_for_ground:
		return
	var r: Node = host.radio
	if int(ent.state) >= 3:
		_down = true
		r.awacs.eitam_down()  # the runtime's destruction motion takes it; the service ends
		print("eitam: down")
		return
	var calls: Array = r.awacs.step(now, dt, r.awacs_contacts(), r.formation_name(r._player_ent()), r._pos())
	_move(r.awacs.eitam())
	var ai = host.get("ai")
	var fa = ai.get("flight_ai") if ai != null else null
	for c in calls:
		r.say(c.template, Array(c.args))
		if fa != null:
			fa.awacs(now, c.bearing, c.miles, c.hostile)


func _move(d: Dictionary) -> void:
	var h := deg_to_rad(float(d.heading))
	ent.world = d.pos
	ent.vel = Vector3(sin(h), cos(h), 0.0) * float(d.speed)
	ent.heading = float(d.heading)
	host.mission_entity_moved(ent)
	# Its attitude from the flight model (the model's nose along -Z: + pitch nose up about X, + bank right wing down).
	ent.node.rotation = Vector3(deg_to_rad(float(d.pitch)), -h, -deg_to_rad(float(d.roll)))
