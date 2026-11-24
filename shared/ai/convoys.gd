## Modern IAF's moving ground vehicles (docs/ai.md §19): each convoy a column of T-72s and Ural-4320s driven by the
## Rust convoy (IafConvoy, crates/iaf-ai/src/convoy.rs) on the roads and across country; it scatters off the road when
## a blast (runtime `blast`: a bomb, a missile, a rocket or gun round, a hit) falls near it and drives on after the
## quiet. A dev / test hook: no mission places one yet. Each vehicle is a mission entity ("convoy:N", class 6, a
## vehicle) with its unit record's model, strength and size (modern-iaf/data/db/units), so the player's sensors and
## weapons and the AI jets' attack take it as any ground unit. Its models have no wheel or track nodes: the hull only
## moves and pitches with the ground.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const GroundRoads := preload("res://shared/terrain/ground_roads.gd")
const Gltf := preload("res://shared/util/gltf.gd")
## A vehicle record's class (modern-iaf/data-formats: "vehicle").
const VEHICLE := 6

var host: Node  # terrain_view.gd
## Each convoy: {convoy (IafConvoy), ents [its vehicles' entities, head first]}.
var convoys: Array = []
var _n := 0
## The CPU time of its frames (µs, modern-iaf/docs/ai-plan.md X5, K12); a test resets it.
var cost_us := 0
var _last := -1.0


## The convoys of the flight `h` (terrain_view.gd), made on first use.
static func of(h: Node) -> Node:
	var n: Node = h.ai.get_node_or_null("Convoys")
	if n == null:
		n = load("res://shared/ai/convoys.gd").new()
		n.name = "Convoys"
		n.host = h
		h.ai.add_child(n)
	return n


## A convoy of the unit records `ids` (head first: "target_t72", "target_ural") from `from` to `to` (world), its tail
## at `from`; on the roads where they serve (the road layer, when setup made it), else across country. `side` −1: the
## player's enemy. {} without a known vehicle.
func spawn(ids: Array, from: Vector3, to: Vector3, side := -1) -> Dictionary:
	if GroundRoads.available():
		IafRoads.open(GroundRoads.dir())
	var c = IafConvoy.create(PackedStringArray(ids), from, to)
	if c == null:
		return {}
	var rt: Node = host.runtime
	if not rt.blast.is_connected(_blast):
		rt.blast.connect(_blast)
	if side < 0:
		side = 1 if int(rt.player_entity().get("side", 2)) == 2 else 2
	var cv := {"convoy": c, "ents": []}
	for d in c.step(rt.now, 0.0, host.mission_ground):
		cv.ents.append(_entity(d, side))
	convoys.append(cv)
	return cv


## A child of ai_flights.gd, on the runtime's clock (as drones.gd); after ai_flights.gd set the AI jets' height nodes,
## each convoy's first vehicle alive joins them (terrain.gd `extra_heights`): its ground is there far from the
## player.
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
	for cv in convoys:
		for i in cv.ents.size():
			var e: Dictionary = cv.ents[i]
			if int(e.state) >= 3 and e.has("convoy"):
				e.erase("convoy")  # hit fatally: the runtime's destruction takes it; the column goes on without it
				e.vel = Vector3.ZERO
				cv.convoy.down(i)
		var out: Array = cv.convoy.step(now, dt, host.mission_ground)
		for i in out.size():
			_place(cv.ents[i], out[i])
		var head: Array = cv.ents.filter(func(e): return e.has("convoy"))
		if Settings.new_ai() and host.get("terrain") != null and not head.is_empty():
			host.terrain.extra_heights.append(host.world_to_scene(head[0].world))


func _place(e: Dictionary, d: Dictionary) -> void:
	if not e.has("convoy"):
		return
	e.world = d.pos
	e.vel = d.vel
	e.heading = d.heading
	host.mission_entity_moved(e)
	e.node.rotation = Vector3(deg_to_rad(d.pitch), -deg_to_rad(d.heading), 0.0)


## A blast at the world point `p`: each convoy near it scatters.
func _blast(p: Vector3, _kind: String) -> void:
	for cv in convoys:
		cv.convoy.alarm(host.runtime.now, p)


func _entity(d: Dictionary, side: int) -> Dictionary:
	var rec: Dictionary = Settings.load_json("res://data/db/units/%s.json" % d.id)
	_n += 1
	var e := {"0x1e": -_n, "0x2bc": String(rec.get("label", d.id)), "0x2e4": d.pos.x, "0x2ee": d.pos.y}
	e.merge({"0x2f8": d.pos.z, "0x2d0": side, "0x302": d.heading})
	var ent := MissionRuntime.entity(e, "convoy:%d" % _n, -1, false)
	var obj := {"0x5aa": VEHICLE, "0x56e": float(rec.get("strength", 600)), "0x564": float(rec.get("radius_m", 3.5))}
	obj["0x514"] = String(d.id)  # the record's id: the combat logbook's type
	obj["0x58c"] = 1
	MissionRuntime._init_damage(ent, obj)
	ent.convoy = true
	var model = Gltf.model(Gltf.objects_path(String(rec.get("model", ""))))
	ent.node = Gltf.instance(model) if model != null else Node3D.new()
	host.add_child(ent.node)
	host.runtime.entities[ent.key] = ent
	_place(ent, d)
	return ent
