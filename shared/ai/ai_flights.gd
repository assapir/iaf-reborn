## AI aircraft (docs/ai.md): every brain-controlled mission aircraft with a flight model type flies the
## original flight model (one IafFlight each, crates/iaf-flight) under its autopilot (control loops, Rust
## `autopilot.rs`), steered by its bdb brain (shared/ai/brain.gd). Drawn with shared/aircraft/aircraft_model.gd at
## the Present scale. `contacts()` lists them for radar / RWR.
extends Node

const Brain := preload("res://shared/ai/brain.gd")
const Combat := preload("res://shared/ai/combat.gd")
const AircraftModel := preload("res://shared/aircraft/aircraft_model.gd")
const Gltf := preload("res://shared/util/gltf.gd")
const Terrain := preload("res://shared/terrain/terrain.gd")
const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const DamageModel := preload("res://shared/mission/damage_model.gd")
const PlayerAircraft := preload("res://shared/aircraft/player_aircraft.gd")
const FlightSounds := preload("res://shared/audio/flight_sounds.gd")
const AirDefence := preload("res://shared/ai/air_defence.gd")
const CLASS_AIRCRAFT := 0x1c
const CLASS_TRANSPORT := 3
## Ours: a fighter's gun burst in the dogfight, combat.gd ticks of 0.2 s (1 s; inferred).
const GUN_BURST := 5
## Ours: the launch call by the missile's guidance (brevity: Fox 1 semi-active radar, Fox 2 infrared, Fox 3 active
## radar; modern-iaf/docs/research/radio-terms.md), by combat.gd's weapon type.
const FOX := {570: "fox_2", 580: "fox_2", 600: "fox_3", 610: "fox_1"}
## FUN_004a9100: the FM start velocity (200, 200, 0) → 282.84 m/s along the heading.
const START_SPEED := 282.842712

var host: Node  # terrain_view.gd
var runtime: Node  # mission_runtime.gd
var pilots: Array = []  # Pilot
var combat: Node  # combat.gd: the armed units' weapon handlers, sensors and fire
var _brains := {}  # bdb brain id -> rules
var _actions := {}  # bdb action id -> item
var _formations: Array = []  # [{id, kind, members: [entity], targets: [entity], route: [[x, y, alt, T, action]]}]
## Modern IAF (Settings.new_ai): the player's flight under IafAi (crates/iaf-ai, modern-iaf/docs/ai-plan.md §6), its
## members [[number, entity]], and the calls its jets made so far [{from, id, t (mission s)}] (the radio says them).
var flight_ai: RefCounted
var _ai_members: Array = []
var flight_calls: Array = []
## The target the flight engages (the radio menu's "engage my target", engage), {} none; the hostile jet nearest the
## flight (IafAi's bogey: a wingman covering the lead or attacked fights it), {} none.
var engage_ent := {}
var flight_bogey := {}
## The ground target the flight attacks (the radio menu's "engage my target" on a ground target, attack; an entity or a
## point, `_point`), {} none.
var attack_ent := {}
## Our wingmen's radar locks on their foe {number: target key} (_radar_lock).
var _wing_locks := {}
## Modern IAF's enemy fighter flights (enemy_flight, docs/ai.md §18): {ai (IafAi), members [[number, entity]], net (its
## ground control: an air_defence.gd network, {} none), station (world), bogey (the entity it is set on), locks {number:
## target key}, strike (the ground target of its lead's attack order, enemy_strike; {} none)}.
var enemy_flights: Array = []
## The CPU time the AI jets took (this node's _process: flight model, autopilot, AI, model and sound), µs, over
## `cost_frames` frames (modern-iaf/docs/ai-plan.md X5); a test resets both.
var cost_us := 0
var cost_frames := 0
## The bdb's Objects and Present rows by id (setup), for `spawn`; the jets `spawn` made so far.
var _objects := {}
var _present := {}
var _spawned := 0


class Pilot:
	var ent: Dictionary
	var flight  # IafFlight
	var node: Node3D
	var brain  # brain.gd
	var formation: Dictionary = {}
	var landed := false
	var airborne := false  # TakeoffCL done: the AirborneReport was posted
	var mode := 0
	var plane := ""  # the converted plane folder (its flight model start)
	var airborne_start := true  # the jet's start was airborne (its controller's autopilot starts on, @4483d7)
	var by_ai := false  # flown by IafAi (flight_ai), not by its brain
	var ground = null  # Modern IAF: the last ground height fed (m), held where the terrain is not loaded (_feed_ground)
	## Systems damage flags 0..24 (controller +0x3d8 + 0xc + 4n, docs/damage.md §5), the cut-out pick (+0x70)
	## and the twin-engine test (controller +8 → +0x24: the player's table PlayerAircraft.TWIN, or the aircraft
	## definition's `engines`: `_twin`).
	var systems: Array = []
	var cut_out := false
	var twin := false
	var _state := {}
	var _host

	func set_mode(m: int, arg = null) -> void:
		if m == mode and m != 0:
			return  # a running manoeuvre is kept (5c8a70)
		mode = m
		flight.ap_set_mode(m, _host.runtime.now)
		if m == 1 or m == 3:
			_host.follow(self, arg)

	func state() -> Dictionary:
		return _state

	func route() -> Array:
		return formation.get("route", [])

	func waypoint_index() -> int:
		return flight.ap_waypoint_index()

	func set_waypoint_index(i: int) -> void:
		flight.ap_set_waypoint_index(i)

	## Condition 30: the action of the current waypoint (0 without a formation).
	func waypoint_action() -> int:
		var r := route()
		var i := waypoint_index()
		return int(r[i][4]) if i >= 0 and i < r.size() else 0

	## Condition 35 (FUN_00453540): endurance over the time to the last waypoint at 220 m/s, ×10; latched at
	## 1.0 once ≤ 1.1. UNCERTAIN: the flow is the current fuel flow.
	var _bingo := false

	func fuel_ratio() -> float:
		var r := route()
		if r.is_empty():
			return 100.0
		if _bingo:
			return 1.0
		var last: Array = r[r.size() - 1]
		var d: float = Vector3(last[0], last[1], last[2]).distance_to(_state.position_world) / 220.0
		var ff: float = flight.fuel_flow()
		var endurance: float = _state.fuel_lbs / (ff * 2.2046299) if ff > 0.0 else 1.0e9
		var ratio := endurance / d if d > 0.0 else 0.0
		if ratio <= 1.1:
			_bingo = true
		return ratio * 10.0


## Freed with the flight: a pilot holds its brain and its entity, both of which hold it back (reference counts that
## would outlive the flight, reported as leaked at exit); dropping them breaks the cycles.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for p in pilots:
			p.brain = null
			p.ent.erase("pilot")
			p.ent = {}
		pilots.clear()


func setup(h: Node, rt: Node, bdb: Dictionary, files: Array) -> void:
	host = h
	runtime = rt
	for b in bdb.get("brains", {}).get("items", []):
		_brains[int(b["0x1e"])] = Brain.rules_of(b)
	for a in bdb.get("actions", {}).get("items", []):
		_actions[int(a["0x1e"])] = a
	var objects: Dictionary = MissionRuntime.bdb_objects(bdb)
	var present := {}
	for p in bdb.get("present", {}).get("items", []):
		present[int(p["0x1e"])] = p
	_objects = objects
	_present = present
	_load_formations(files)
	var planes: Dictionary = AircraftModel.index()
	var install := Settings.own_dir()
	for ent in runtime.entities.values():
		# Activation (FUN_004a9100) gives every BRAIN-controlled unit the FM mover, by control mode, not class: the
		# transports (class 3: C-130, IL-76) fly as the jets do.
		if ent.player or ent.control != 1 or not ent.klass in [CLASS_AIRCRAFT, CLASS_TRANSPORT]:
			continue
		var obj: Dictionary = objects.get(ent.type, {})
		var pr: Dictionary = present.get(int(obj.get("0x53c", -1)), {})
		var plane := _plane_of(planes, String(pr.get("0x64a", "")))
		# A Modern IAF flyable unit (an Objects row with "airframe") has no Present model of its own: it is drawn from
		# its aircraft definition, so its AI jet (a four-ship's wingman) takes the plane of its type, as the player's.
		if plane == "" and obj.has("airframe"):
			plane = PlayerAircraft.plane_for(int(ent.type_code))
		if plane == "":
			continue
		_launch(ent, _formation_of(ent), plane, install, pr)
	if Settings.new_ai() and ClassDB.class_exists("IafAi"):
		_setup_flight_ai()
	if not pilots.is_empty() or Settings.has_setting("ai_level"):  # a game with AI (not IAF 2026's training)
		print("AI aircraft: %d flying" % pilots.size())
	combat = Combat.new()
	add_child(combat)
	combat.setup(host, self, bdb)


## A dev / test hook (no mission places one yet; modern-iaf/docs/ai-plan.md K2): an AI jet of the bdb unit `unit`
## (its Objects id, e.g. "mig29a") at world `at`, heading `heading` (deg), flying `route` ([[x, y, z, action] world
## points]) under its autopilot, as a mission's brain-less aircraft does: its plane, flight model and model from its
## unit's record and aircraft definition, on the ground at a base when `at` is there (the start rule). `side` −1: the
## player's enemy. `arm` {pylon index (0..8): [weapon record name, count]} replaces those pylons of its record's load
## (a strike load, docs/ai.md §8.10). Its entity, {} for a unit that does not fly.
func spawn(unit: String, at: Vector3, heading: float, route: Array, side := -1, arm := {}) -> Dictionary:
	var obj: Dictionary = {}
	for o in _objects.values():
		if String(o.get("0x514", "")) == unit:
			obj = o
	var pr: Dictionary = _present.get(int(obj.get("0x53c", -1)), {})
	var plane := _plane_of(AircraftModel.index(), String(pr.get("0x64a", "")))
	if plane == "":
		return {}
	_spawned += 1
	if side < 0:
		side = 1 if int(runtime.player_entity().get("side", 2)) == 2 else 2
	var e := {"0x1e": -1000 - _spawned, "0x2bc": "%s %d" % [unit, _spawned], "0x2c6": int(obj["0x1e"])}
	e.merge({"0x2e4": at.x, "0x2ee": at.y, "0x2f8": at.z, "0x2d0": side, "0x302": heading})
	var ent := MissionRuntime.entity(e, "jet:%d" % _spawned, -1, false)
	MissionRuntime._init_damage(ent, obj)
	var pts := []
	for q in route:
		pts.append([float(q[0]), float(q[1]), float(q[2]), 0.0, int(q[3])])
	var formation := {"id": ent.id, "kind": 0, "slot": 0, "members": [ent], "targets": [], "route": pts}
	runtime.entities[ent.key] = ent
	if not _launch(ent, formation, plane, Settings.own_dir(), pr):
		runtime.entities.erase(ent.key)
		return {}
	if combat != null:
		combat.adopt(ent, _arm(ent, obj, arm))  # its stores and weapons from its record, as a mission's jet
	return ent


## The load of a spawned jet `ent` (its record `obj`) with the pylons of `arm` replaced (spawn); [] for none.
func _arm(ent: Dictionary, obj: Dictionary, arm: Dictionary) -> Array:
	if arm.is_empty():
		return []
	var load: Array = Combat.Stores.loadout(ent, obj)
	for i in arm:
		for w in combat._db.weapons.values():
			if String(w.name) == String(arm[i][0]):
				load[int(i)] = [int(w.id), int(arm[i][1])]
	return load


## Ours (a dev / test hook, docs/ai.md §18; no mission places one yet): the AI jets `ents` (from `spawn`: in the air,
## or parked at a base, `enemy_base`) fly as an enemy pair under IafAi on station at `station` (world: a CAP orbit's
## centre at its height, or where they were spawned), vectored by the network `net` (an air_defence.gd network: its
## IafGci; {} none: its own radar only), at the pilot's enemy skill. The flight, null when fewer than one jet could
## join.
func enemy_flight(ents: Array, station: Vector3, net := {}) -> RefCounted:
	var ai = ClassDB.instantiate("IafAi")
	var members := []
	for k in ents.size():
		var p = ents[k].get("pilot")
		if p != null and ai.add_member(p.flight, k + 1, true):
			p.by_ai = true
			members.append([k + 1, ents[k]])
	if members.is_empty():
		return null
	ai.enemy(Settings.enemy_skill(), host.world_to_scene(station))
	enemy_flights.append(
		{"ai": ai, "members": members, "net": net, "station": station, "bogey": {}, "locks": {}, "strike": {}}
	)
	return ai


## Ours (a dev / test hook, docs/ai.md §8.10; no mission orders one): the enemy flight `ai` (enemy_flight's) attacks the
## ground target `t` on its lead's own order: an entity (a ground unit, a parked jet), or a world point (a base's
## runway or shelters) as a Vector3. Each jet with an air-to-ground weapon flies its run in turn (its lead first),
## releases through combat.gd's AI ripple, then goes back to its station (a based pair home). False: no such flight,
## or no jet could take it.
func enemy_strike(ai, t) -> bool:
	var tt: Dictionary = _point(t) if t is Vector3 else t
	for f in enemy_flights:
		if f.ai == ai and not tt.is_empty():
			for m in f.members:
				_ground_weapon(ai, m[0], m[1])
			var ok: bool = ai.strike(
				runtime.now, host.world_to_scene(world_of(tt)), Terrain.dir_to_scene(combat._velocity_of(tt))
			)
			if ok:
				f.strike = tt
			return ok
	return false


## A ground point as a target for the attack (combat.gd's AI ripple, the jets' runs): at world `p` on the ground.
func _point(p: Vector3) -> Dictionary:
	var g = host.mission_ground(p)
	var w := Vector3(p.x, p.y, float(g) if g != null else p.z)
	return {"key": "", "world": w, "vel": Vector3.ZERO, "heading": 0.0, "state": 0, "player": false, "klass": 0}


## Ours (a dev / test hook, docs/ai.md §18.3; no mission places one): up to `count` jets of the bdb unit `unit` parked
## in the shelters of `base` (its iaf.ibx section; the sim has no enemy base yet, so any base stands in), flown as an
## enemy pair by `enemy_flight` on station at `station` (world): they scramble on the network `net`'s vector, take off,
## intercept and land there after. Their route is the Rust ground run's: the take-off point 15 km along the runway,
## the landing waypoint 15 km out on the approach (action 7), both 1,500 m up. The flight, null when none could park.
func enemy_base(unit: String, base: String, count: int, station: Vector3, net := {}, side := -1) -> RefCounted:
	var b: Dictionary = Settings.load_ibx(Settings.own_dir().path_join("iaf.ibx")).get(base, {})
	var f := func(k: String) -> float: return float(b.get(k, "0"))
	var l := Vector3(f.call("LineupLocX"), f.call("LineupLocY"), f.call("LineupLocZ"))
	var h := deg_to_rad(f.call("RunwayNumber"))
	var route := []
	for q in [[15000.0, 2], [-15000.0, 7]]:
		var p: Vector3 = l + Vector3(sin(h), cos(h), 0) * q[0] + Vector3(0, 0, 1500)
		route.append([p.x, p.y, p.z, q[1]])
	var ents := []
	for i in mini(count, int(f.call("HangarsNum"))):
		var at := Vector3(f.call("HangarPtX%d" % i), f.call("HangarPtY%d" % i), l.z)
		var e := spawn(unit, at, f.call("HangarPtHdg%d" % i), route, side)
		if not e.is_empty():
			ents.append(e)
	return enemy_flight(ents, station, net) if not ents.is_empty() else null


## An AI jet's pilot for `ent` in `formation` on `plane`: its flight model started and its model attached (`pr`: its
## Present row); false when the flight model refuses it.
func _launch(ent: Dictionary, formation: Dictionary, plane: String, install: String, pr: Dictionary) -> bool:
	var p := Pilot.new()
	p._host = self
	p.ent = ent
	p.formation = formation
	p.plane = plane
	p.systems.resize(25)
	p.systems.fill(false)
	p.twin = _twin(int(ent.type_code))
	if not _start(p, install, plane):
		return false
	_attach(p, Settings.model_scale(float(pr.get("0x65e", 10.0))), bool(p._state.on_ground_start))
	return true


## A twin-engine jet for the damage model: its aircraft definition's `engines`, else the 1998 type-code table.
static func _twin(type_code: int) -> bool:
	var n = Settings.airframe(type_code).get("engines")
	return int(n) == 2 if n != null else type_code in PlayerAircraft.TWIN


## A pilot's jet in the world: its model at the Present scale `scale` (with its engine sound), its entity's links
## and its brain; then it flies.
func _attach(p: Pilot, scale: float, on_ground: bool) -> void:
	var ent := p.ent
	# Its tail number: the next of the flight's, kept on the entity (a jet the player leaves keeps the player's).
	var model := AircraftModel.create(p.plane, ent.type_code, on_ground, int(ent.get("tail", AircraftModel.NEXT)))
	if model != null:
		ent["tail"] = model.tail
		model.scale = Vector3.ONE * scale
		host.add_child(model)
		# As the player's jet: the model's `height` helper (how far the wheels reach below the
		# origin) at the Present scale.
		var hp := model.find_child("height", true, false) as Node3D
		p.flight.set_gear_clearance(-hp.position.y * model.scale.y if hp != null else 0.0)
		p.flight.set_true_gear_clearance(-hp.position.y if hp != null else 0.0)
		model.add_child(FlightSounds.create_engine(host, p.flight, ent))  # docs/sound.md §3
	p.node = model
	ent.node = model
	ent["pilot"] = p
	ent["airborne_class"] = true
	ent["coll_radius"] = 0.25 * _extent_sum(model)
	ent["max_extent"] = 10.0
	var rules: Array = _brains.get(int(ent.get("brain", -1)), [])
	p.brain = Brain.new()
	p.brain.setup(self, ent, p, rules, true)
	p.brain.reset(runtime.now)
	pilots.append(p)
	_place(p)


## FUN_004a8e70(1) on the player's old jet (the FlyTSD's Fly, docs/views.md §1): brain controlled, it flies on from
## its state with the player's flight model `flight`, its systems damage and the stores it had left (`load`,
## [[weapon id, count] × 12]); `airborne_start`: its start was airborne.
func adopt(
	ent: Dictionary, flight, plane: String, scale: float, systems: Array, load: Array, airborne_start: bool
) -> void:
	var p := Pilot.new()
	p._host = self
	p.ent = ent
	p.formation = _formation_of(ent)
	p.plane = plane
	p.systems = systems
	p.twin = _twin(int(ent.type_code))
	p.flight = flight
	p.airborne_start = airborne_start
	flight.set_ai(host.enemy_of_player(ent), int(host.mission_pref("ai_level")))
	var pts := PackedFloat64Array()
	for q in p.route():
		pts.append_array(q)
	flight.ap_set_route(pts)
	p._state = flight.state()
	p._state["position_world"] = host.scene_to_world(p._state.position)
	ent.world = p._state.position_world
	ent.heading = float(p._state.heading)
	_attach(p, scale, bool(p._state.on_ground))
	combat.adopt(ent, load)


## FUN_004a8e70(3) on a jet the player takes over: it leaves the AI (pilot, brain, model, engine sound and weapon
## handler). Returns the stores it had left, [[weapon id, count] × 12].
func release(ent: Dictionary) -> Array:
	var p: Pilot = ent.pilot
	pilots.erase(p)
	var load: Array = combat.hand_over(ent)
	if p.node != null:
		p.node.queue_free()
	p.brain = null
	p.ent = {}
	ent.erase("pilot")
	ent.node = null
	return load


## The converted plane folder of a Present model path (…\MIG29\MIG29_H.XFR → "mig29").
static func _plane_of(planes: Dictionary, path: String) -> String:
	var file := path.get_file().get_basename().to_lower()
	for k in planes:
		if String(planes[k].get("model", "")).get_file().get_basename().to_lower() == file:
			return k
	return ""


static func _extent_sum(model: Node3D) -> float:
	if model == null:
		return 0.0
	var box := Gltf.model_aabb(model, Gltf.MESH_SPACE)
	return (box.size.x + box.size.y + box.size.z) * model.scale.x


func _load_formations(files: Array) -> void:
	if files.is_empty():
		return
	var slots := MissionRuntime.flight_slots(files[0])
	for f in files[0].get("formations", {}).get("items", []):
		var members := []
		var targets := []
		for m in f.get("members", []):
			members.append(runtime.entities.get("0:%d" % int(m.get("0x41a", -1)), {}))
			# target_key: a Mission Creator target in another file (mission_creator.rs).
			targets.append(runtime.entities.get(m.get("target_key", "0:%d" % int(m.get("0x424", -1))), {}))
		var route := []
		for q in f.get("points", []):
			route.append([float(q[1]), float(q[2]), float(q[3]), float(q[4]), int(q[5])])
		_formations.append(
			{
				"id": int(f["0x1e"]),
				"kind": int(f.get("0x3f2", 0)),
				"slot": int(slots.get(int(f["0x1e"]), 0)),
				"members": members,
				"targets": targets,
				"route": route
			}
		)


func _formation_of(ent: Dictionary) -> Dictionary:
	for f in _formations:
		for m in f.members:
			if m == ent:
				return f
	return {}


## Modern IAF: the player's formation flies under IafAi, the player its number by the formation's slot (Kidon 1-1 the
## first), its AI jets the rest; none without an AI member.
func _setup_flight_ai() -> void:
	var me: Dictionary = runtime.player_entity()
	var f := _formation_of(me)
	if f.is_empty() or host.get("flight") == null:
		return
	var ai = ClassDB.instantiate("IafAi")
	for k in f.members.size():
		var ent: Dictionary = f.members[k]
		var p = ent.get("pilot")
		if ent == me:
			ai.add_member(host.flight, k + 1, false)
		elif p != null:
			p.by_ai = true
			ai.add_member(p.flight, k + 1, true)
		else:
			continue
		_ai_members.append([k + 1, ent])
	if _ai_members.size() > 1:
		flight_ai = ai


## Ours (a dev / test hook, docs/ai.md §8.9; no mission starts a flight in the air): the player's flight's AI jets put
## in the air behind the player's jet (put it in the air first), stepped back 150 m each and 150 m right or left,
## heading `heading` (deg), engines on; the flight's IafAi made again from them (they rejoin their slots). False: no
## flight.
func flight_in_air(heading: float) -> bool:
	if flight_ai == null:
		return false
	var me: Vector3 = world_of(runtime.player_entity())
	var h := deg_to_rad(heading)
	var fwd := Vector3(sin(h), cos(h), 0.0)
	var right := Vector3(cos(h), -sin(h), 0.0)
	for m in _ai_members:
		var ent: Dictionary = m[1]
		var p = ent.get("pilot")
		if ent.player or p == null:
			continue
		var n: int = m[0]
		ent.world = me - fwd * (150.0 * (n - 1)) + right * (150.0 if n % 2 == 1 else -150.0)
		ent.heading = heading
		if not _start(p, Settings.own_dir(), p.plane):
			return false
		p.airborne = true
		p.landed = false
	_ai_members = []
	flight_ai = null
	_setup_flight_ai()
	return flight_ai != null


## The tower's start-up clearance (sim_flight.gd): the flight's wingmen start their engines.
func flight_cleared_to_start() -> void:
	if flight_ai != null:
		flight_ai.start_up(runtime.now)


## Ours (Modern IAF, a dev hook: no mission sets it yet): the player's flight takes off in pairs (true) or in a stream
## (false, the default): Kidon 1-2 lines up beside the lead, 1-4 beside 1-3, each rolls with its lead
## (docs/ai.md §8.7). False: no flight AI.
func flight_pairs(on: bool) -> bool:
	if flight_ai == null:
		return false
	flight_ai.pairs(on)
	return true


## IafAi's frame, after every jet's steps of the frame (its orders go to the next frame's ap_step): who is alive
## (the player while in the jet), the player's steerpoint (a promoted lead flies on from it), the orders, the calls.
func _step_flight_ai(now: float) -> void:
	if host.get("cockpit") != null and host.flight != null:
		host.flight.ap_set_waypoint_index(host.cockpit.current_waypoint)
	for m in _ai_members:
		var ent: Dictionary = m[1]
		flight_ai.set_alive(m[0], int(ent.state) < 3 and not (ent.player and host.ejected))
		var th := _threat_of(ent)
		flight_ai.set_threat(m[0], th[0], th[1], th[2])
	if not engage_ent.is_empty():
		# Gone: destroyed, or out of the world (a drone at its end point, a unit removed).
		var gone: bool = int(engage_ent.state) >= 3 or not runtime.entities.has(engage_ent.key)
		if int(engage_ent.state) >= 3:
			flight_ai.splash(now, 1)
		var at: Vector3 = Vector3.ZERO if gone else host.world_to_scene(world_of(engage_ent))
		var vel: Vector3 = Vector3.ZERO if gone else Terrain.dir_to_scene(combat._velocity_of(engage_ent))
		flight_ai.set_target(not gone, at, vel, 0.0 if gone else _jam_of(engage_ent))
		if gone:
			engage_ent = {}
	attack_ent = _feed_strike(flight_ai, _ai_members, attack_ent)
	# The flight's bogey: the hostile jet nearest it (one shot down is the wingmen's splash when theirs).
	if not flight_bogey.is_empty() and int(flight_bogey.state) >= 3:
		flight_ai.splash(now, 2)
	var side := int(runtime.player_entity().side)
	flight_bogey = _nearest_hostile(_ai_members, side)
	var b := flight_bogey
	flight_ai.set_bogey_jam(_jam_of(b))
	var bw: Vector3 = world_of(b) if not b.is_empty() else Vector3.ZERO
	var bv: Vector3 = combat._velocity_of(b) if not b.is_empty() else Vector3.ZERO
	flight_ai.set_bogey(
		false, Vector3.ZERO, Vector3.ZERO, not b.is_empty(), host.world_to_scene(bw), Terrain.dir_to_scene(bv)
	)
	# Each AI jet's weapons against its foe (state "foe": 1 the target, 2 the bogey; the last frame's decision).
	for m in _ai_members:
		if not m[1].player:
			_weapons_of(flight_ai, m[0], m[1], _foe_of(m[0]))
	for c in flight_ai.step(now):
		_flight_say(c, now)
	# The wingmen's shots and bursts (the enemy fighters' host path, combat.gd), called "Fox" or "guns".
	for m in _ai_members:
		if m[1].player:
			continue
		var foe := _foe_of(m[0]) if int(m[1].state) < 3 else {}
		var said := _fire(flight_ai, m[0], m[1], foe)
		if said != "":
			_flight_say({"from": m[0], "id": said}, now)
		_release(flight_ai, m[0], m[1], attack_ent)
		_radar_lock(flight_ai, m[0], m[1], foe, _wing_locks)
	# The decoys the AI jets release (combat.gd's release path: their stores, the 4 s busy time, the decoy rule).
	for m in _ai_members:
		var d: int = flight_ai.decoy(m[0])
		if d > 0 and not m[1].player:
			combat.combat(m[1], "320" if d == 1 else "310", {})
		if not m[1].player:
			_set_jam(m[1], flight_ai.jams(m[0]))


## A call of the flight (IafAi.step's, or a wingman's launch call) said by the radio and recorded.
func _flight_say(c: Dictionary, now: float) -> void:
	c["t"] = now
	flight_calls.append(c)
	if host.get("radio") != null:
		var ent: Dictionary = {}
		for m in _ai_members:
			if int(m[0]) == int(c.from):
				ent = m[1]
		var at: Vector3 = world_of(ent) if not ent.is_empty() else Vector3.INF
		host.radio.flight_call(int(c.from), String(c.id), float(flight_ai.state(c.from).get("fuel_kg", 0.0)), at)


## The entity our wingman `n` fights (IafAi state "foe"): the engaged target, the flight's bogey, else {}.
func _foe_of(n: int) -> Dictionary:
	match int(flight_ai.state(n).get("foe", 0)):
		1:
			return engage_ent
		2:
			return flight_bogey
	return {}


## The hostile jet (AirDefence's jets not of `side`) nearest any live member of `members` [[number, entity]], {} none.
func _nearest_hostile(members: Array, side: int) -> Dictionary:
	var t := {}
	var near := INF
	var jets: Array = AirDefence.of(host).jets(side)
	for m in members:
		if int(m[1].state) >= 3:
			continue
		for j in jets:
			var d: float = j.pos.distance_to(world_of(m[1]))
			if d < near:
				near = d
				t = j.ent
	return t


## Jet `n` (entity `ent`) of the IafAi `ai`: its weapons against `t` ({} none; set_weapons): the missile picked and its
## envelope (_pick_aa), armed (a missile or the gun's rounds left), its own missile flying at `t`.
func _weapons_of(ai, n: int, ent: Dictionary, t: Dictionary) -> void:
	var u = combat.units.get(ent.key)
	var env: Array = _pick_aa(u, t) if u != null and not t.is_empty() else [0.0, 0.0, false]
	# Armed: an air-to-air missile left (with a target or not: a foe taken this decision is fed next frame), or the
	# gun's rounds (the dogfight, docs/ai.md §18.2).
	var armed: bool = u != null and u.stations.size() > 9 and int(u.stations[9].count) > 0
	if u != null and not armed:
		for i in mini(9, u.stations.size()):
			if int(u.stations[i].count) > 0 and int(u.stations[i].w.get("type", 0)) in Combat.AA_TYPES:
				armed = true
	var w = host.get("weapons")
	var mine := func(mis): return not mis.ended and is_same(mis.get_meta("owner", {}), ent)
	var flying: bool = (
		w != null
		and not t.is_empty()
		and w.missiles.any(func(mis): return mine.call(mis) and mis.target_key == t.get("key"))
	)
	ai.set_weapons(n, env[0], env[1], env[2] or armed, flying)


## Jet `n`'s shot or burst at `t` this frame (IafAi shoot / gun) through combat.gd: the missile (300), or the gun
## selected (370), a burst of GUN_BURST ticks and its launch through the fire gate (the gate's interval the missiles'
## again after it: 370 sets the gun's 5 s for good). The call it makes ("fox_1".."fox_3", "guns"), "" none.
func _fire(ai, n: int, ent: Dictionary, t: Dictionary) -> String:
	if t.is_empty():
		return ""
	if ai.shoot(n):
		var u = combat.units.get(ent.key)
		var type: int = int(u.w.get("type", 0)) if u != null and u.cur >= 0 else 0
		return FOX.get(type, "") if combat.combat(ent, "300", t) else ""
	if ai.gun(n):
		var gu = combat.units[ent.key]
		var gi: float = gu.gate_interval
		if combat.combat(ent, "370", {}):
			gu.ripple.set_values(GUN_BURST, 10)
			var fired = combat.combat(ent, "300", t)
			gu.gate_interval = gi
			return "guns" if fired else ""
	return ""


## Ours (Modern IAF, the radio menu's "engage my target", modern-iaf/docs/ai-plan.md F5, F15): the flight's jets `to`
## (0 the flight, 5 the element, 2..4 one wingman) engage the radar's locked aircraft, else attack the player's ground
## target (attack; IafAi.pick_ground among the hostile ground units: the radar's lock, else the one nearest the SPI,
## else the SPI itself). False: no flight AI or nobody to take it.
func engage_target(to: int) -> bool:
	var t: Dictionary = host.radio._radar_target() if host.get("radio") != null else {}
	if not t.is_empty() and int(t.get("klass", 0)) in host.radio.AIRCRAFT:
		return engage(to, t)
	if flight_ai == null or host.get("weapons") == null:
		return attack(to, {})
	# The hostile ground units alive and drawn (not aircraft).
	var units: Array = []
	var at := PackedVector3Array()
	for e in runtime.entities.values():
		var air: bool = int(e.get("klass", 0)) in host.radio.AIRCRAFT
		if e.player or int(e.state) >= 3 or air or e.get("node") == null or not host.enemy_of_player(e):
			continue
		units.append(e)
		at.append(e.world)
	var spi: Vector3 = host.weapons.spi()
	var i: int = flight_ai.pick_ground(units.find(t) if not t.is_empty() else -1, spi, at)
	return attack(to, units[i] if i >= 0 else _point(spi))


## The flight's jets `to` attack the ground target `t` (an entity or `_point`'s; {} none: each "unable"), each with an
## air-to-ground weapon in turn (IafAi.attack; docs/ai.md §8.10).
func attack(to: int, t: Dictionary) -> bool:
	if flight_ai == null:
		return false
	for m in _ai_members:
		if not m[1].player:
			_ground_weapon(flight_ai, m[0], m[1])
	var ok: bool = not t.is_empty() and int(t.state) < 3
	var at: Vector3 = host.world_to_scene(world_of(t)) if ok else Vector3.ZERO
	var vel: Vector3 = Terrain.dir_to_scene(combat._velocity_of(t)) if ok else Vector3.ZERO
	var r: int = flight_ai.attack(runtime.now, to, ok, at, vel)
	if r > 0:
		attack_ent = t
	return r >= 0


## The ground target `t` of the flight `ai` (members [[number, entity]]) this frame, and each AI jet's air-to-ground
## weapon; a target destroyed or gone from the world is {} (the jets end their attack). Returns the target kept.
func _feed_strike(ai, members: Array, t: Dictionary) -> Dictionary:
	var gone: bool = (
		not t.is_empty() and (int(t.state) >= 3 or (String(t.key) != "" and not runtime.entities.has(t.key)))
	)
	if gone:
		t = {}
	var at: Vector3 = host.world_to_scene(world_of(t)) if not t.is_empty() else Vector3.ZERO
	var vel: Vector3 = Terrain.dir_to_scene(combat._velocity_of(t)) if not t.is_empty() else Vector3.ZERO
	ai.set_ground_target(not t.is_empty(), at, vel)
	for m in members:
		if not m[1].player:
			_ground_weapon(ai, m[0], m[1])
	return t


## Jet `n`'s pylons for its air-to-ground weapon (IafAi.set_ground_pylons).
func _ground_weapon(ai, n: int, ent: Dictionary) -> void:
	var u = combat.units.get(ent.key)
	ai.set_ground_pylons(n, _pylons_of(u) if u != null else PackedInt64Array())


## The pylons 0..8 of combat.gd's unit `u` as IafAi takes them: the weapon's type, 1 when GPS-guided, the stores
## left, the weapon's id, for each.
static func _pylons_of(u) -> PackedInt64Array:
	var a := PackedInt64Array()
	for i in mini(9, u.stations.size()):
		var w: Dictionary = u.stations[i].w
		a.append_array([int(w.get("type", 0)), int(w.has("gps")), int(u.stations[i].count), int(w.get("id", -1))])
	return a


## Jet `n`'s release this frame (IafAi.release) on the ground target `t`: the pylon IafAi.ground_release names selected,
## its stores in one AI ripple (combat.gd release); IafAi told (released: "alpha").
func _release(ai, n: int, ent: Dictionary, t: Dictionary) -> void:
	var u = combat.units.get(ent.key)
	if t.is_empty() or u == null or not ai.release(n) or combat._releasing(u):
		return
	var r: Vector3i = ai.ground_release(_pylons_of(u))
	if r.x < 0:
		return
	combat._select(u, r.x)
	u.ripple.set_values(r.y, r.z)
	if combat.release(ent, t):
		ai.released(n, runtime.now)


## The flight's jets `to` engage `t`, an enemy aircraft alive; else each answers "unable".
func engage(to: int, t: Dictionary) -> bool:
	if flight_ai == null:
		return false
	var ok: bool = not t.is_empty() and host.enemy_of_player(t) and int(t.get("klass", 0)) in host.radio.AIRCRAFT
	ok = ok and int(t.state) < 3
	# Taken by nobody (each "unable"): a jet already engaging keeps its target.
	var at: Vector3 = host.world_to_scene(world_of(t)) if ok else Vector3.ZERO
	var vel: Vector3 = Terrain.dir_to_scene(combat._velocity_of(t)) if ok else Vector3.ZERO
	var r: int = flight_ai.engage(runtime.now, to, ok, at, vel)
	if r > 0:
		engage_ent = t
	return r >= 0


## The threat jet `ent`'s RWR and MAW show IafAi: the nearest missile flying at it (3 radar, 4 infrared), else the
## nearest live hostile radar locked on it (1 from the air, 2 from the ground; combat.gd on_lock), else none; [kind,
## scene position, the missile's scene velocity (zero for a lock)]. A missile is infrared when the flares decoy it
## (player_weapons.gd DECOY_KINDS).
func _threat_of(ent: Dictionary) -> Array:
	var me := world_of(ent)
	var ir: Array = Combat.PlayerWeapons.DECOY_KINDS[Combat.Stores.FLARE]
	var best := [0, Vector3.ZERO, Vector3.ZERO]
	var d := INF
	var w = host.get("weapons")
	if w != null:
		for mis in w.missiles:
			if String(mis.target_key) != String(ent.key) or mis.ended:
				continue
			var p: Vector3 = mis.position(runtime.now)
			if p.distance_to(me) < d:
				d = p.distance_to(me)
				best = [4 if int(mis.weapon.get("type", 0)) in ir else 3, p, mis.velocity(runtime.now)]
	if best[0] == 0:
		for o in ent.get("locked_by", {}).values():
			# (A friendly radar's lock, the player's included, is no threat; a dead unit never sends its unlock.)
			if int(o.get("side", -1)) == int(ent.side) or int(o.get("state", 0)) >= 3:
				continue
			var p := world_of(o)
			if p.distance_to(me) < d:
				d = p.distance_to(me)
				best = [1 if o.get("airborne_class", false) else 2, p, Vector3.ZERO]
	if best[0] != 0:
		best[1] = host.world_to_scene(best[1])
		best[2] = Terrain.dir_to_scene(best[2])
	return best


## An enemy flight's frame (docs/ai.md §18), after every jet's step: its bogey (the network's vector while its radar
## and post stand, else the nearest hostile jet, which only its own radar can find), each jet's threat and weapons,
## the orders; then its shots and decoys through combat.gd, and its radar's lock on the bogey while it holds it.
func _step_enemy(f: Dictionary, now: float) -> void:
	var lead: Dictionary = f.members[0][1]
	var side := int(lead.side)
	var gci := {}
	var n: Dictionary = f.net
	if not n.is_empty() and n.ents.all(func(e): return int(e.state) < 3):
		gci = n.gci.vector(now, f.station)
	var t: Dictionary = runtime.entities.get(gci.get("id", ""), {})
	if not t.is_empty() and int(t.state) >= 3:
		# Shot down: the network's track coasts on a while; neither it nor the jet is a bogey.
		t = {}
		gci = {}
	if gci.is_empty():
		t = _nearest_hostile(f.members, side)
	f.bogey = t
	f.ai.set_bogey_jam(_jam_of(t))
	var tw: Vector3 = world_of(t) if not t.is_empty() else Vector3.ZERO
	var tv: Vector3 = combat._velocity_of(t) if not t.is_empty() else Vector3.ZERO
	f.ai.set_bogey(
		not gci.is_empty(),
		host.world_to_scene(gci.get("pos", Vector3.ZERO)),
		Terrain.dir_to_scene(gci.get("vel", Vector3.ZERO)),
		not t.is_empty(),
		host.world_to_scene(tw),
		Terrain.dir_to_scene(tv)
	)
	for m in f.members:
		var ent: Dictionary = m[1]
		f.ai.set_alive(m[0], int(ent.state) < 3)
		var th := _threat_of(ent)
		f.ai.set_threat(m[0], th[0], th[1], th[2])
		_weapons_of(f.ai, m[0], ent, t)
	f.strike = _feed_strike(f.ai, f.members, f.strike)
	f.ai.step(now)  # (the enemy's radio calls are not heard)
	for m in f.members:
		var ent: Dictionary = m[1]
		var alive := int(ent.state) < 3
		if alive:
			_fire(f.ai, m[0], ent, t)
			_release(f.ai, m[0], ent, f.strike)
		var d: int = f.ai.decoy(m[0]) if alive else 0
		if d > 0:
			combat.combat(ent, "320" if d == 1 else "310", {})
		_set_jam(ent, alive and f.ai.jams(m[0]))
		_radar_lock(f.ai, m[0], ent, t if alive else {}, f.locks)


## Jet `n`'s radar lock on `t` (combat.gd on_lock: the target's RWR) while its radar holds it (IafAi state "contact")
## or tracks its jammer's angle beyond the burn-through ("strobe": home on jam, still a track on the target's RWR;
## inferred); `locks` {number: target key} the locks held.
func _radar_lock(ai, n: int, ent: Dictionary, t: Dictionary, locks: Dictionary) -> void:
	var st: Dictionary = ai.state(n) if not t.is_empty() else {}
	var key: String = String(t.key) if st.get("contact", false) or st.get("strobe", false) else ""
	var had: String = locks.get(n, "")
	if had != key:
		if had != "":
			combat.on_lock(ent, runtime.entities.get(had, {}), false)
		if key != "":
			combat.on_lock(ent, t, true)
		locks[n] = key


## Ours (Modern IAF, docs/ai.md §15.6): an AI jet's jammer on or off by its tree (IafAi.jams), when its definition has
## one (`jammer.burn_through`); the entity's `jam` is the share the radars read (air_defence.gd jets, radar.gd).
func _set_jam(ent: Dictionary, on: bool) -> void:
	var share := float(Settings.airframe(int(ent.get("type_code", -1))).get("jammer", {}).get("burn_through", 0.0))
	ent["jam"] = share if on and Settings.modern_ew() else 0.0


## The jammer share of a jet `t` ({} none): the player's from its jammer switch, an AI jet's from its entity.
func _jam_of(t: Dictionary) -> float:
	if t.is_empty():
		return 0.0
	return (
		host.weapons.jam_share() if t.get("player", false) and host.get("weapons") != null else float(t.get("jam", 0.0))
	)


## The air-to-air missile an enemy jet `u` shoots at `t` (combat.gd's stations and DLZ): of those it has left, the one
## with the shortest reach whose envelope holds the target (the infrared one close in), else the farthest reaching;
## selected. [max, min, a missile left].
func _pick_aa(u, t: Dictionary) -> Array:
	var o: Dictionary = combat._pose(u)
	var tgt := {"pos": world_of(t), "vel": combat._velocity_of(t)}
	var dist: float = o.pos.distance_to(tgt.pos)
	var best := [-1, 0.0, 0.0]
	var inside := false
	for i in mini(9, u.stations.size()):
		var st: Dictionary = u.stations[i]
		if int(st.count) <= 0 or not int(st.w.get("type", 0)) in Combat.AA_TYPES:
			continue
		var env: Array = Combat.Missile.dlz(host.weapons._motion(st.w), {"pos": o.pos, "fwd": o.fwd, "vel": o.vel}, tgt)
		var holds: bool = dist >= float(env[1]) and dist <= float(env[0])
		if (
			best[0] < 0
			or (holds and (not inside or env[0] < best[1]))
			or (not inside and not holds and env[0] > best[1])
		):
			best = [i, float(env[0]), float(env[1])]
			inside = holds
	if best[0] < 0:
		return [0.0, 0.0, false]
	if best[0] != u.cur and not combat._releasing(u):
		combat._select(u, best[0])
	return [best[1], best[2], true]


## The FM start (FUN_004a9100 → FUN_005a5820): the player's rules, 282.84 m/s along the heading.
func _start(p: Pilot, install: String, plane: String) -> bool:
	var flight = ClassDB.instantiate("IafFlight")
	var w: Vector3 = p.ent.world
	var pos: Vector3 = host.world_to_scene(w)
	var h := deg_to_rad(float(p.ent.heading))
	var vel := Vector3(sin(h), 0, -cos(h)) * START_SPEED
	var rule: Vector2i = flight.start_rule(install, w.x, w.y, w.z)
	var airborne: bool = flight.is_airborne_start(w.z, rule.x != 0)
	var engine_on := rule.y != 0
	var err: String = flight.start(
		install,
		plane,
		pos,
		Vector3(0.0, 0.0, float(p.ent.heading)),
		vel if airborne else Vector3.ZERO,
		{
			"airborne": airborne,
			"engine_on": engine_on,
			"real_data": host.real_data,
			"f16_variant": Settings.f16_variant,
			"f15_variant": Settings.f15_variant
		}
	)
	if err != "":
		push_warning("AI %s: %s" % [p.ent.name, err])
		return false
	flight.set_ai(host.enemy_of_player(p.ent), int(host.mission_pref("ai_level")))
	if host.has_method("ai_wind"):
		host.ai_wind(flight)
	flight.ap_setup(install, host.terrain.world_origin.x, host.terrain.world_origin.y)
	if Settings.new_ai() and not airborne:
		p.ground = w.z  # parked: its spawn's height until the terrain under it is loaded
	flight.ap_set_ground(
		func(pos: Vector3):
			var g = host.scene_ground(pos)
			if g == null and Settings.new_ai():
				g = p.ground
			return float(g) if g != null else -1.0e9
	)
	var pts := PackedFloat64Array()
	for q in p.route():
		pts.append_array(q)
	flight.ap_set_route(pts)
	p.flight = flight
	p.airborne_start = airborne
	p._state = flight.state()
	p._state["on_ground_start"] = not airborne
	p._state["position_world"] = w
	return true


func _process(delta: float) -> void:
	if host.frozen or host.waiting_for_ground:
		return
	var t0 := Time.get_ticks_usec()
	_fly(delta)
	cost_us += Time.get_ticks_usec() - t0
	cost_frames += 1


func _fly(delta: float) -> void:
	var now: float = runtime.now
	var want: Array[Vector3] = []
	for p in pilots:
		var ent: Dictionary = p.ent
		if ent.control != 1 or int(ent.state) >= 3:
			continue  # fatally hit: the destruction motion drives it (mission_runtime.gd)
		var scene_pos: Vector3 = p._state.position
		if Settings.new_ai():
			want.append(scene_pos)
			_feed_ground(p, scene_pos)
		else:
			host.feed_ground(p.flight, scene_pos)
		p.flight.set_ai_damage(float(ent.damage) <= 0.1)
		if not p.by_ai:
			_feed_leader(p)  # IafAi gives its jets their leader
		_feed_target(p)
		var wp: int = p.flight.ap_waypoint_index()
		var out: Dictionary = p.flight.ap_step(now)
		if out.get("release", false):
			combat.release(ent)  # a bombing manoeuvre's release (440440)
		# WayPtSet moving on (5d7450: index ≠ brain+0x88) posts the radio's WayptReport (docs/radio.md §4).
		if p.flight.ap_waypoint_index() != wp and host.get("radio") != null:
			host.radio.waypoint_passed(ent, p.flight.ap_waypoint_index())
		# The player's steps (TerrainView: time_factor equal steps, each capped at 0.25 s): the jets keep one clock.
		for i in host.time_factor:
			p.flight.step(delta / host.time_factor)
		p._state = p.flight.state()
		p._state["position_world"] = host.scene_to_world(p._state.position)
		ent.world = p._state.position_world
		ent.alt = ent.world.z
		ent.heading = float(p._state.heading)
		ent.vel = Terrain.dir_to_world(p._state.velocity)
		if p._state.crashed:
			runtime.set_damage_level(ent, 5)
			continue
		if p.flight.ap_landed() and not p.landed:
			p.landed = true
			landed_handler(ent)
			if host.get("radio") != null:
				host.radio.report_landed(ent)  # StopPlaneCL's LandedReport (5d44d0, docs/radio.md §4)
		if p.flight.ap_airborne() and not p.airborne:
			p.airborne = true
			if host.get("radio") != null:
				host.radio.report_airborne(ent)  # TakeoffCL's AirborneReport (5cdb5d)
		_place(p)
		if not p.by_ai:
			p.brain.update(now)
	if Settings.new_ai() and host.get("terrain") != null:
		host.terrain.extra_heights = want
	# After every jet's step (the player's came first, TerrainView's frame): the flight reads them all at one instant.
	if flight_ai != null:
		_step_flight_ai(now)
	for f in enemy_flights:
		_step_enemy(f, now)


## Ours, Modern IAF (docs/ai.md §18.4): an AI jet's ground. Terrain heights load only where the camera wants; each
## AI jet's own come too (terrain.gd `extra_heights`), and until they are there the jet keeps the last ground it had
## (a parked one its spawn's height): with none it fell through the ground landing far from the player.
func _feed_ground(p: Pilot, scene_pos: Vector3) -> void:
	var g = host.feed_ground(p.flight, scene_pos)
	if g != null:
		p.ground = g
	elif p.ground != null:
		p.flight.set_ground_height(float(p.ground))


func _place(p: Pilot) -> void:
	if p.node == null:
		return
	var st: Dictionary = p._state
	p.node.position = st.position
	p.node.basis = Basis(st.right, st.up, -st.forward).scaled(p.node.scale) if st.has("right") else p.node.basis
	var parts := {}
	for k in [
		"stick_x", "stick_y", "rudder", "flaps", "gear_down", "brakes", "gear", "on_ground", "afterburner", "rpm", "tef"
	]:
		if st.has(k):
			parts[k] = st[k]
	p.node.update(parts, get_process_delta_time())
	# Wingtip vortices of an AI jet (FUN_004da090 runs for every drawn aircraft with EndWing helpers); Detailed effects
	# draw their own condensation instead (vapour_fx.gd).
	var detailed: bool = host != null and host.get("effects") != null and host.effects.gpu != null
	if host != null and host.get("trails") != null and not detailed and bool(st.get("vortex", false)):
		var tips: Array = p.node.wingtips()
		for i in tips.size():
			host.trails.emit([p, i], tips[i], host.trails.WINGTIP)
	# Contrails (ours, Detailed effects).
	if host != null and host.get("effects") != null and host.effects.gpu != null:
		host.effects.gpu.contrail(p.node, st)


## The formation leader (route member 0, FUN_00587450) for the formation / taxi / take-off loops.
func _feed_leader(p: Pilot) -> void:
	var ref: Dictionary = p.formation.members[0] if not p.formation.is_empty() else {}
	if ref.is_empty() or ref == p.ent:
		p.flight.ap_set_leader(false, false, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		return
	var active := not (int(ref.state) in [4, 5]) and int(ref.control) != 0
	var st: Dictionary
	if ref.player:
		st = host.flight.state()
	elif ref.has("pilot"):
		st = ref.pilot.state()
	else:
		var w: Vector3 = world_of(ref)
		st = {
			"position": host.world_to_scene(w),
			"velocity": Vector3.ZERO,
			"pitch": 0.0,
			"roll": 0.0,
			"heading": float(ref.heading)
		}
	var att := Vector3(st.pitch, st.roll, st.heading)
	p.flight.ap_set_leader(true, active, st.position, st.velocity, att)


## The combat manoeuvres' target (brain +0x70), every frame (the original's loops read the entity live).
func _feed_target(p: Pilot) -> void:
	var t: Dictionary = p.brain.target if p.brain != null else {}
	if t.is_empty() or int(t.state) >= 4:
		p.flight.ap_set_target(false, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0, 0.0)
		return
	var st: Dictionary
	if t.player:
		st = host.flight.state()
	elif t.has("pilot"):
		st = t.pilot.state()
	else:
		var w: Vector3 = world_of(t)
		st = {
			"position": host.world_to_scene(w),
			"velocity": Terrain.dir_to_scene(t.vel),
			"pitch": 0.0,
			"roll": 0.0,
			"heading": float(t.heading)
		}
	p.flight.ap_set_target(true, st.position, st.velocity, st.pitch, st.roll, st.heading)


func follow(_p: Pilot, _leader) -> void:
	pass  # the leader is fed every frame (_feed_leader)


# --- brain host --------------------------------------------------------------------------------


## brain+0x44 (FUN_0043eef0): the wingman of my formation, else its leader unless that is me.
func partner_of(ent: Dictionary) -> Dictionary:
	var f := _formation_of(ent)
	if f.is_empty():
		return {}
	if f.members[0] == ent:
		return f.members[1] if f.members.size() > 1 else {}
	return f.members[0]


## brain+0x74: my formation slot's target (0x424).
func member_target(ent: Dictionary) -> Dictionary:
	var f := _formation_of(ent)
	for i in f.get("members", []).size():
		if f.members[i] == ent:
			return f.targets[i]
	return {}


func skill_period_factor(ent: Dictionary) -> float:
	if not host.enemy_of_player(ent):
		return 1.0
	return Brain.SKILL_PERIOD[clampi(int(host.mission_pref("ai_level")), 0, 2)]


func world_of(ent: Dictionary) -> Vector3:
	if ent.get("player", false):
		return host.player_world()
	return ent.world


func on_ground(ent: Dictionary) -> bool:
	if ent.get("player", false):
		return bool(host.flight.state().on_ground)
	var p = ent.get("pilot")
	return p != null and bool(p._state.get("on_ground", false))


func engaged(ent: Dictionary) -> bool:
	var p = ent.get("pilot")
	return p != null and p.brain.engaged


func action(id: int) -> Dictionary:
	return _actions.get(id, {})


func brain_rules(id: int) -> Array:
	return _brains.get(id, [])


## A fired rule's audio: the mission Audio record, now or after its delay (ActionTimer).
func play_audio(_ent: Dictionary, id: int, delay: float) -> void:
	if delay <= 0.0:
		runtime.play_message(id)
	else:
		get_tree().create_timer(delay).timeout.connect(func(): runtime.play_message(id))


## FUN_00440f90 (landed once): the wingman's waypoint := the route's last.
func landed_handler(ent: Dictionary) -> void:
	_wingman_to(ent, _formation_of(ent).get("route", []).size() - 1)


## FUN_004a86b0 → FUN_00440eb0 → FUN_00440ed0 (a unit with a brain at its final status): a dead leader's waypoint
## index (brain +0x88; the player's: its NAV selection, autopilot.gd set_waypoint) goes to its wingman.
func leader_died(ent: Dictionary) -> void:
	if ent.get("player", false):
		_wingman_to(ent, host.flight.ap_waypoint_index() if host.get("flight") != null else -1)
	elif ent.get("pilot") != null:
		_wingman_to(ent, ent.pilot.waypoint_index())


## FUN_00440e90 on the wingman of `ent` (getWingman FUN_005bcb90: only a formation's leader has one): its brain
## index +0x88 := i, and its controller's NAV selects waypoint i (FUN_00453450). With the player in the wingman's
## seat that is the player's NAV (inferred: the player's jet has the same brain object, S+0x2c).
func _wingman_to(ent: Dictionary, i: int) -> void:
	var f := _formation_of(ent)
	if i < 0 or f.is_empty() or f.members[0] != ent or f.members.size() < 2:
		return
	var w: Dictionary = f.members[1]
	if w.get("player", false):
		if host.get("autopilot") != null and i < host.route.size():
			host.autopilot.set_waypoint(i)
	elif w.get("pilot") != null:
		w.pilot.set_waypoint_index(i)


## Weapons, targets, radar, flares / chaff, combat on / off: the combat job (docs/ai.md §5).
## The armed units: combat.gd.
func combat_hook(ent: Dictionary, what: String, target: Dictionary) -> Variant:
	return combat.combat(ent, what, target)


## The combat conditions (docs/ai.md §13.2): combat.gd.
func combat_measure(ent: Dictionary, code: int, target: Dictionary) -> Variant:
	return combat.measure(ent, code, target)


## Trigger ops 21 / 22 (FUN_00440830 / FUN_004407e0).
func set_combat(ent: Dictionary, on: bool) -> void:
	var p = ent.get("pilot")
	if p == null:
		combat.set_combat(ent, on)
		return
	if on:
		p.brain.enable_combat(runtime.now)
	else:
		p.brain.disable_combat()


## Ours (the mission editor's "takes off" rule, docs/mission-editor.md §18.3): every jet of `ent`'s flight that waits
## on wp0's late planned time takes off now.
func take_off(ent: Dictionary) -> void:
	var f := _formation_of(ent)
	for m in f.get("members", [ent]):
		if m.get("pilot") != null:
			m.pilot.flight.ap_release_takeoff(runtime.now)


## Every AI aircraft for radar / RWR: entity, world position (X east, Y north, alt m), world velocity, side.
func contacts() -> Array:
	var out := []
	for p in pilots:
		if int(p.ent.state) < 4:
			out.append({"entity": p.ent, "position": p.ent.world, "velocity": p.ent.vel, "side": p.ent.side})
	return out


## FUN_004a9c60 → FUN_0044d590 on an AI jet's controller (entity +0x34, the same direct call as the player's): a hit
## that left it alive at 0 < damage < 1 may break a system (FUN_0045cd80; FUN_0045d020 refuses 2, 3, 5, 7 for an
## AI jet, and ECM damage 1 needs an ECM, which no AI jet carries yet). FUN_0044d760 sets the flag (and the flags
## it implies); the flight model reads them as the player's (engines, afterburner, fuel leak, hydraulics, total
## flight control: iaf_flight set_damage). The console text, lights and calls are the player's only.
func hit(ent: Dictionary) -> void:
	var p = ent.get("pilot")
	var d := float(ent.damage)
	if p == null or p.flight == null or d <= 0.0 or d >= 1.0:
		return
	var r: Array = DamageModel.pick_system(d, p.systems, p.twin, false, false, p.cut_out, _rand)
	p.cut_out = r[1]
	var n: int = r[0]
	if n == 0:
		return
	for f in DamageModel.SYSTEMS.get(n, {}).get("also", []):
		p.systems[f] = true
	p.systems[n] = true
	p.flight.set_damage(p.systems, p.twin)


## CRT rand(): 0..32767.
func _rand() -> int:
	return randi() & 0x7fff
