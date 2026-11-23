## Modern IAF's one-way attack drones of the Shahed-136 class (docs/ai.md §16), each salvo flown by the Rust salvo
## (IafSalvo, crates/iaf-ai/src/drone.rs). A dev / test hook: no mission launches one yet. Each drone is a mission
## entity ("drone:N", class 3: a fixed-wing mover) with its stand-in shape of ours and the type's radar cross-section,
## so the player's radar, data link, AIFF and weapons take it as any air contact and the existing damage path brings it
## down. It does not shoot. At its end point it explodes and is removed (no damage done there yet).
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const BaseFurniture := preload("res://shared/terrain/base_furniture.gd")
const DamageModel := preload("res://shared/mission/damage_model.gd")
const Gltf := preload("res://shared/util/gltf.gd")

## Strength: one 20 mm hit (100) brings it down (our damage scale, modern-iaf/docs/data-formats.md §6; inferred).
const STRENGTH := 100.0
## The span and length (m): Wikipedia's 2.5 and 3.5 (docs/ai.md §16).
const SPAN := 2.5
const LENGTH := 3.5
const GREY := Color(0.55, 0.56, 0.54)
const PROP := Color(0.2, 0.2, 0.2)
## The propeller disc's radius (m, inferred).
const PROP_R := 0.4

var host: Node  # terrain_view.gd
## Each salvo: {salvo (IafSalvo), ents [the drones' entities, null before launch], side}.
var salvos: Array = []
var _n := 0
## The CPU time of its frames (µs, modern-iaf/docs/ai-plan.md X5, K12); a test resets it.
var cost_us := 0
var _last := -1.0


## The drones of the flight `h` (terrain_view.gd), made on first use.
static func of(h: Node) -> Node:
	var n: Node = h.ai.get_node_or_null("Drones")
	if n == null:
		n = load("res://shared/ai/drones.gd").new()
		n.name = "Drones"
		n.host = h
		h.ai.add_child(n)
	return n


## A salvo of `count` drones along `route` (world points; the last is the end point on the ground; a point's height
## stands for the ground where the terrain is not loaded), `agl` m above the terrain (0: the type's), launched
## `interval` s apart (< 0: the type's); {} for a route of fewer than two points.
## `side` −1: the player's enemy.
func spawn(route: Array, count := 1, agl := 0.0, interval := -1.0, side := -1) -> Dictionary:
	var salvo = IafSalvo.create(route, count, agl, interval)
	if salvo == null:
		return {}
	if side < 0:
		side = 1 if int(host.runtime.player_entity().get("side", 2)) == 2 else 2
	var s := {"salvo": salvo, "ents": [], "side": side}
	s.ents.resize(count)
	salvos.append(s)
	return s


## A child of ai_flights.gd: it runs after every jet's step of the frame, on the runtime's clock (as air_defence.gd).
func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	cost_us += Time.get_ticks_usec() - t0


func _step(_delta: float) -> void:
	var now: float = host.runtime.now
	var dt := now - _last if _last >= 0.0 else 0.0
	_last = now
	if host.frozen or host.waiting_for_ground:
		return
	for s in salvos:
		for i in s.ents.size():
			var e = s.ents[i]
			if e != null and int(e.state) >= 3 and e.has("drone"):
				e.erase("drone")  # hit fatally: the runtime's destruction motion takes it
				s.salvo.down(i)
		var out: Array = s.salvo.step(dt, host.mission_ground)
		for i in out.size():
			var d: Dictionary = out[i]
			if d.phase == "wait" or d.phase == "down":
				continue
			if s.ents[i] == null:
				s.ents[i] = _entity(s, d)
			var e: Dictionary = s.ents[i]
			if not e.has("drone"):
				continue
			e.world = d.pos
			e.vel = d.vel
			e.heading = d.heading
			host.mission_entity_moved(e)
			e.node.rotation = Vector3(deg_to_rad(d.pitch), -deg_to_rad(d.heading), 0.0)
			if d.phase == "impact":
				_impact(e)


func _entity(s: Dictionary, d: Dictionary) -> Dictionary:
	_n += 1
	var e := {"0x1e": -_n, "0x2bc": "SHAHED-136", "0x2e4": d.pos.x, "0x2ee": d.pos.y, "0x2f8": d.pos.z}
	e.merge({"0x2d0": s.side, "0x302": d.heading})
	var ent := MissionRuntime.entity(e, "drone:%d" % _n, -1, false)
	MissionRuntime._init_damage(ent, {"0x5aa": 3, "0x56e": STRENGTH, "0x564": SPAN, "0x58c": 1})
	ent.airborne_class = true  # mission_entity_moved keeps it off the ground
	ent.half_span = SPAN / 2.0  # the gun's hit test (gun_rounds.gd half_span_of)
	ent.rcs = IafSalvo.rcs()  # the player's radar (radar.gd _feed)
	ent.drone = true
	ent.node = _shape()
	host.add_child(ent.node)
	host.runtime.entities[ent.key] = ent
	return ent


## At its end point: the explosion there, and it leaves the world (gone for whoever still holds it).
func _impact(e: Dictionary) -> void:
	e.erase("drone")
	host.mission_entity_impact(e)
	e.state = DamageModel.EXPLODED
	host.runtime._set_visible(e, false)
	host.runtime.entities.erase(e.key)
	e.node.queue_free()
	e.node = null


## The drone's model (Gltf.UNITS, docs/ai.md §16), else its stand-in shape (ours): the fuselage, the cranked delta
## wing, the fins at its tips and the pusher propeller's disc, in vertex colours as the bases' furniture, the nose
## along −Z.
func _shape() -> Node3D:
	var model = Gltf.model(Gltf.UNITS.get("SHAHED-136", ""))
	if model != null:
		return Gltf.instance(model)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LENGTH / 2.0
	BaseFurniture._box(st, Vector3(0, 0, 0), Vector3(0.4, 0.4, LENGTH - 0.2), GREY)
	# The delta: from the nose's root back to the tips, both faces.
	var nose := Vector3(0, 0, -half + 0.6)
	var tip_l := Vector3(-SPAN / 2.0, 0, half - 0.3)
	var tip_r := Vector3(SPAN / 2.0, 0, half - 0.3)
	var root := Vector3(0, 0, half - 0.1)
	for side in [[nose, tip_r, root], [nose, root, tip_l]]:
		BaseFurniture._tri(st, side[0], side[2], side[1], Vector3.UP, GREY)
		BaseFurniture._tri(st, side[0], side[1], side[2], Vector3.DOWN, GREY)
	for x in [-SPAN / 2.0, SPAN / 2.0]:
		BaseFurniture._box(st, Vector3(x, 0.2, half - 0.45), Vector3(0.03, 0.4, 0.5), GREY)
	# The propeller's disc behind the fuselage, both faces.
	var c := Vector3(0, 0, half + 0.02)
	var n := 16
	for k in n:
		var a := TAU * k / n
		var b := TAU * (k + 1) / n
		var p := c + Vector3(cos(a), sin(a), 0) * PROP_R
		var q := c + Vector3(cos(b), sin(b), 0) * PROP_R
		BaseFurniture._tri(st, c, p, q, Vector3.BACK, PROP)
		BaseFurniture._tri(st, c, q, p, Vector3.FORWARD, PROP)
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = BaseFurniture._material()
	var node := Node3D.new()
	node.add_child(m)
	return node
