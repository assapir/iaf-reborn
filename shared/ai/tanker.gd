# Modern IAF's tanker (modern-iaf/docs/research/air-refuelling.md §8): a KC-46A Gideon or a 707 Re'em on its
# racetrack, its boom operator (IafTanker, crates/iaf-ai/src/tanker.rs) and its model (our own, tools/tanker/build.py)
# with the boom and the pilot director lights. A flight has one only when its mission or Scramble's draw puts one
# there (`place`); the player reaches it by the radio (modern-iaf/flight/sim_flight.gd's Tanker page: `request`), the
# AI wingmen by the lead's "refuel" (IafAi). Each frame (`frame`, from ai_flights.gd after every jet's step, before
# IafAi's): the tanker flies on, works its receivers (the player's jet and the AI wingmen it knows), gives the fuel,
# says its calls (radio.gd tanker_call), and hands each AI wingman its station (IafAi.set_refuel). It is a friendly
# aircraft on the radar (an entity of the mission runtime, drawn by this node).
extends Node3D

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const Gltf := preload("res://shared/util/gltf.gd")
const DamageModel := preload("res://shared/mission/damage_model.gd")
const ArDoor := preload("res://shared/aircraft/ar_door.gd")
const CLASS_AIRCRAFT := 0x1c
## Each kind's model and the callsign the radio uses (radio.gd TANKERS).
const MODELS := {
	"kc46": "res://shared/extra/models/tanker/kc46.glb",
	"reem": "res://shared/extra/models/tanker/reem.glb",
}
## The DISC lamp's time after a disconnect, s (T.O. 1F-16A-1 p. 1-80: RDY again after a 3 s delay).
const DISC_S := 3.0
## A receiver that has come within this of the tanker and then flies this far from it again leaves its queue (out of
## the refuelling; inferred: 20 NM), m; a receiver done leaves once this far (it has gone on its way), m. One still on
## its way from farther out stays in the queue.
const LEAVE_M := 37_000.0
const GONE_M := 5_000.0
## The pilot director lights: each row's five lamps, forward to aft (elevation U..D, telescope F..A), their size and
## spacing, m; the colours: the striped green centre, then amber, then red (the KC-10's, research §3), lit and dark.
const PDL_LAMP := Vector3(0.35, 0.08, 0.5)
const PDL_STEP := 0.6
const PDL_LIT := [
	Color(1.0, 0.1, 0.05), Color(1.0, 0.65, 0.1), Color(0.2, 1.0, 0.3), Color(1.0, 0.65, 0.1), Color(1.0, 0.1, 0.05)
]

var host: Node  # terrain_view.gd
var kind := ""
var tk: RefCounted  # IafTanker
## Its entity (the radar's): MissionRuntime.entity's shape, moved each frame.
var ent := {}
var model: Node3D
var _pivot: Node3D
var _inner: Node3D
var _inner_z := 0.0
var _pdl := [[], []]  # each row's lamps (MeshInstance3D), forward to aft
## The receiver in contact (0 none) and each receiver's DISC lamp until (the runtime's clock).
var contact_id := 0
var _disc_until := {}
## The AI wingmen sent to it (IafAi's "refuel") whose request it took; the calls said (for the tests: [name, id]).
var _asked := {}
var said: Array = []
var _now := 0.0
## The receivers that have come within LEAVE_M.
var _reached := {}
var _doors := {}  # the AI receivers' models with their doors open -> their aircraft definitions
## Tests: the player's jet held where a test puts it: a Callable(delta) giving {position, velocity, forward, right, up}
## (scene) at this frame's end; null: its flight model's state.
var test_player_state = null


## A tanker of `kind` (kc46, reem) on its track: the inbound leg from `anchor` (world, m) on `course` (deg); the node,
## added to `h` and set as its tanker, or null when the extension or the kind is missing.
static func place(h: Node, what: String, anchor: Vector3, course: float) -> Node:
	if not ClassDB.class_exists("IafTanker") or not MODELS.has(what):
		return null
	var t: RefCounted = ClassDB.class_call_static("IafTanker", "create", what, h.world_to_scene(anchor), course)
	if t == null:
		return null
	var n := new()
	n.name = "Tanker"
	n.host = h
	n.kind = what
	n.tk = t
	n._build()
	h.add_child(n)
	h.tanker = n
	n._place_model()
	print("tanker: %s, track from %s on %03d" % [what, anchor, roundi(course)])
	return n


func _build() -> void:
	var parsed = Gltf.open(MODELS[kind])
	model = Gltf.instance(parsed) if parsed != null else Node3D.new()
	add_child(model)
	_pivot = model.find_child("boom_pivot", true, false)
	_inner = model.find_child("boom_inner", true, false)
	_inner_z = _inner.position.z if _inner != null else 0.0
	for r in 2:
		var at := model.find_child(["pdl_l", "pdl_r"][r], true, false) as Node3D
		for i in 5:
			var m := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = PDL_LAMP
			m.mesh = box
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.15, 0.15, 0.15)
			m.material_override = mat
			m.position = Vector3(0, 0, (i - 2) * PDL_STEP)
			if at != null:
				at.add_child(m)
			_pdl[r].append(m)
	var e := {"0x1e": -900, "0x2bc": kind, "0x2c6": -1, "0x2d0": _player_side(), "0x2e4": 0.0, "0x2ee": 0.0}
	ent = MissionRuntime.entity(e, "tanker", -1, false)
	ent.merge({"klass": CLASS_AIRCRAFT, "type_code": -1, "coll_radius": 20.0, "max_extent": 30.0, "node": model}, true)
	ent.control = 2  # flown here, not by a brain (0 would leave it out of the AWACS picture: radio.gd awacs_contacts)
	ent["tanker"] = true  # the AWACS's "vector to tanker"
	if host.get("runtime") != null:
		host.runtime.entities[ent.key] = ent


func _player_side() -> int:
	return int(host.runtime.player_entity().get("side", 2)) if host.get("runtime") != null else 2


# --- the radio (the player's call; the wingmen's turn) ------------------------------------------------------------


## Receiver `id` (the flight's number: the player's, or an AI wingman's) asks to refuel: the tanker's answer said.
func request(id: int) -> void:
	_events([tk.request(id)])


## The boom latched in the player's receptacle (the F-16's AR/NWS lamp).
func in_contact() -> bool:
	return contact_id != 0 and contact_id == _player_id()


## The player's DISC lamp: lit for DISC_S after a disconnect.
func disc_lit() -> bool:
	return _now < float(_disc_until.get(_player_id(), -INF))


func _player_id() -> int:
	var n: int = int(host.get("player_flight_number")) if host.get("player_flight_number") != null else 0
	return n if n > 0 else 1


# --- the frame --------------------------------------------------------------------------------------------------


## One frame of `delta` s (ai_flights.gd, after every jet's step): the AI wingmen's requests, the receivers, the
## boom operator, the fuel, the calls, the AI's stations, the model.
func frame(delta: float) -> void:
	if int(ent.get("state", 1)) >= DamageModel.HIT:
		_shot_down()
		return
	_now = float(host.runtime.now) if host.get("runtime") != null else _now + delta
	var ai = host.get("ai")
	var fa = ai.get("flight_ai") if ai != null else null
	if fa != null:
		_ai_requests(ai, fa)
	var rx := _receivers(ai, delta)
	_ai_doors(ai, rx)
	var out: Dictionary = tk.step(delta, rx)
	var fuel: Array = out.get("fuel", [])
	if not fuel.is_empty():
		var f = _flight_of(int(fuel[0]), ai)
		if f != null:
			f.add_fuel(float(fuel[1]))
	_events(out.events, String(out.get("why", "")))
	host.ar_disconnect = false
	if fa != null:
		_ai_stations(ai, fa)
	_place_model()


## Fatally hit (DamageModel.HIT on): no more tanker. Its receivers' lamps go out and its wingmen rejoin; its model goes
## to the scene, where the runtime's fall moves it as any hit aircraft's (`ent.node`), and this node stops.
func _shot_down() -> void:
	var ai = host.get("ai")
	var fa = ai.get("flight_ai") if ai != null else null
	# Every AI jet sent to it, asked yet or not (a "Refuel" given this frame): no station, so it rejoins.
	if fa != null:
		for m in ai._ai_members:
			if not m[1].player and bool(fa.state(int(m[0])).get("refuelling", false)):
				fa.set_refuel(int(m[0]), {})
	_asked.clear()
	contact_id = 0
	host.tanker = null
	var xf := model.global_transform
	model.reparent(host)
	model.global_transform = xf
	print("tanker: shot down")
	queue_free()


## The AI wingmen IafAi sent to the tanker (state refuelling) ask in their number's order, once.
func _ai_requests(ai, fa) -> void:
	for m in ai._ai_members:
		var n := int(m[0])
		if m[1].player:
			continue
		var on: bool = int(m[1].state) < 3 and bool(fa.state(n).get("refuelling", false))
		if on and not _asked.has(n):
			_asked[n] = true
			request(n)
		elif not on and _asked.has(n):
			_asked.erase(n)
			_events(tk.leave(n))


## Every receiver the tanker knows as it is now; those too far away leave (a done one once on its way).
func _receivers(ai, delta: float) -> Array:
	var out := []
	var pose: Dictionary = tk.pose()
	var known: PackedInt64Array = tk.receivers()
	for id in known:
		var r := _receiver(int(id), ai, delta)
		if r.is_empty():
			continue
		var d: float = (r.receptacle as Vector3).distance_to(pose.position)
		var done: bool = tk.is_done(id) and not _asked.has(int(id))
		if d < LEAVE_M:
			_reached[int(id)] = true
		if (d > LEAVE_M and _reached.has(int(id))) or (done and d > GONE_M):
			_reached.erase(int(id))
			_events(tk.leave(id))
			continue
		out.append(r)
	return out


## Receiver `id` now: {id, receptacle, velocity (scene), door, room_kg, disconnect}; {} when it is not in the air.
func _receiver(id: int, ai, delta: float) -> Dictionary:
	if id == _player_id() and host.get("flight") != null and not (host.ejected or host.fatal_hit or host.crashed):
		var rc: Vector3 = host.receptacle()
		if rc == Vector3.INF:
			return {}
		var st: Dictionary = host.flight.state() if test_player_state == null else test_player_state.call(delta)
		var ready: bool = host.refuel_door and _door_ready()
		return _rx(id, st, rc, ready, host.flight.fuel_room(), host.ar_disconnect)
	var m = _member(id, ai)
	if m == null or int(m[1].state) >= 3 or m[1].get("pilot") == null:
		return {}
	var p = m[1].pilot
	var rc := _receptacle_of(m[1])
	if rc == Vector3.INF:
		return {}
	return _rx(id, p.state(), rc, true, p.flight.fuel_room(), false)  # an AI jet opens its door as it goes in


## The AI receivers' doors drawn open while the tanker knows them (an AI jet opens its door as it goes in: _receiver),
## shut once they leave.
func _ai_doors(ai, rx: Array) -> void:
	var open := {}
	for r in rx:
		var m = _member(int(r.id), ai)
		if m != null and m[1].get("node") is Node3D:
			open[m[1].node] = Settings.airframe(int(m[1].get("type_code", 0)))
	for n in _doors:
		if not open.has(n) and is_instance_valid(n):
			ArDoor.set_open(n, _doors[n], false)
	for n in open:
		ArDoor.set_open(n, open[n], true)
	_doors = open


func _rx(id: int, st: Dictionary, rc: Vector3, door: bool, room: float, disc: bool) -> Dictionary:
	var at: Vector3 = st.position + st.forward * rc.x + st.right * rc.y + st.up * rc.z
	return {"id": id, "receptacle": at, "velocity": st.velocity, "door": door, "room_kg": room, "disconnect": disc}


## The F-16's door opens on hydraulic system B (its RDY lamp, cockpit3d.gd): the 3D cockpit's lamp where it has one.
func _door_ready() -> bool:
	var c3 = host.get("cockpit_3d")
	return c3 == null or not c3.has_method("ar_hydraulics") or c3.ar_hydraulics()


func _member(id: int, ai) -> Variant:
	if ai == null:
		return null
	for m in ai._ai_members:
		if int(m[0]) == id and not m[1].player:
			return m
	return null


func _receptacle_of(e: Dictionary) -> Vector3:
	var r: Array = Settings.airframe(int(e.get("type_code", 0))).get("receptacle", [])
	return Vector3(float(r[0]), float(r[1]), float(r[2])) if r.size() == 3 else Vector3.INF


func _flight_of(id: int, ai) -> Variant:
	if id == _player_id():
		return host.get("flight")
	var m = _member(id, ai)
	return m[1].pilot.flight if m != null and m[1].get("pilot") != null else null


## The calls of `events` ([name, id, kg]) said; the contact and the DISC lamps; a wingman done is let go once every
## wingman sent is done.
func _events(events: Array, why := "") -> void:
	for e in events:
		var name := String(e[0])
		var id := int(e[1])
		said.append([name, id])
		match name:
			"contact":
				contact_id = id
			"disconnect", "breakaway":
				if contact_id == id or name == "disconnect":
					contact_id = 0
				_disc_until[id] = _now + DISC_S
				if why != "" and name == "disconnect":
					print("tanker: %d disconnected (%s)" % [id, why])
		if host.get("radio") != null and host.radio.has_method("tanker_call"):
			host.radio.tanker_call(kind, name, id)


## Each AI wingman sent to it: its station (IafAi.set_refuel); once every one sent is done (on the right wing), all
## are let go together and rejoin the flight.
func _ai_stations(ai, fa) -> void:
	var all_done := not _asked.is_empty() and _asked.keys().all(func(n): return tk.is_done(n))
	for n in _asked.keys():
		var m = _member(n, ai)
		if m == null:
			continue
		if all_done:
			fa.set_refuel(n, {})
			_events(tk.leave(n))
			_asked.erase(n)
		else:
			fa.set_refuel(n, tk.slot(n, _receptacle_of(m[1])))


# --- the model -----------------------------------------------------------------------------------------------------


func _place_model() -> void:
	var pose: Dictionary = tk.pose()
	position = pose.position
	basis = Basis(pose.right, pose.up, -pose.forward)
	var b: Dictionary = tk.boom()
	if _pivot != null:
		_pivot.basis = Basis(Vector3.UP, float(b.azimuth)) * Basis(Vector3.RIGHT, float(b.elevation))
	if _inner != null:
		_inner.position.z = _inner_z + float(b.extension)
	var pdl = b.get("pdl")
	for r in 2:
		var lit: int = -9 if pdl == null else (pdl.x if r == 0 else pdl.y) + 2
		for i in 5:
			var mat: StandardMaterial3D = _pdl[r][i].material_override
			mat.albedo_color = PDL_LIT[i] if i == lit else Color(0.15, 0.15, 0.15)
	if host.get("runtime") != null:
		ent.world = host.scene_to_world(pose.position)
		ent.alt = ent.world.z
		ent.vel = Vector3(pose.velocity.x, -pose.velocity.z, pose.velocity.y)
		ent.heading = rad_to_deg(atan2(ent.vel.x, ent.vel.y))
