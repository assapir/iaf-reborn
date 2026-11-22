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
const CLASS_AIRCRAFT := 0x1c
const CLASS_TRANSPORT := 3
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
## The target the flight engages (the radio menu's "engage my target", engage), {} none.
var engage_ent := {}
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
## player's enemy. Its entity, {} for a unit that does not fly.
func spawn(unit: String, at: Vector3, heading: float, route: Array, side := -1) -> Dictionary:
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
	return ent


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


## The tower's start-up clearance (sim_flight.gd): the flight's wingmen start their engines.
func flight_cleared_to_start() -> void:
	if flight_ai != null:
		flight_ai.start_up(runtime.now)


## IafAi's frame, after every jet's steps of the frame (its orders go to the next frame's ap_step): who is alive
## (the player while in the jet), the player's steerpoint (a promoted lead flies on from it), the orders, the calls.
func _step_flight_ai(now: float) -> void:
	if host.get("cockpit") != null and host.flight != null:
		host.flight.ap_set_waypoint_index(host.cockpit.current_waypoint)
	for m in _ai_members:
		var ent: Dictionary = m[1]
		flight_ai.set_alive(m[0], int(ent.state) < 3 and not (ent.player and host.ejected))
		var th := _threat_of(ent)
		flight_ai.set_threat(m[0], th[0], th[1])
	if not engage_ent.is_empty():
		# Gone: destroyed, or out of the world (a drone at its end point, a unit removed).
		var gone: bool = int(engage_ent.state) >= 3 or not runtime.entities.has(engage_ent.key)
		flight_ai.set_target(not gone, Vector3.ZERO if gone else host.world_to_scene(world_of(engage_ent)))
		if gone:
			engage_ent = {}
	for c in flight_ai.step(now):
		c["t"] = now
		flight_calls.append(c)
		if host.get("radio") != null:
			host.radio.flight_call(int(c.from), String(c.id), float(flight_ai.state(c.from).get("fuel_kg", 0.0)))
	# The engaging jets' weapons (combat.gd's air-to-air pick and launch: its envelope, cone and fire gate), one missile
	# of each jet in the air at the target at a time (shoot, look, shoot again; inferred).
	var w = host.get("weapons")
	for m in _ai_members:
		if engage_ent.is_empty() or m[1].player or not flight_ai.state(m[0]).get("engaging", false):
			continue
		var own := func(mis): return not mis.ended and is_same(mis.get_meta("owner", {}), m[1])
		if w != null and w.missiles.any(func(mis): return own.call(mis) and mis.target_key == engage_ent.key):
			continue
		var u = combat.units.get(m[1].key)
		if (
			u != null
			and (u.cur < 0 or int(u.stations[u.cur].count) <= 0 or not int(u.w.get("type", 0)) in Combat.AA_TYPES)
		):
			combat.combat(m[1], "330", {})
		combat.combat(m[1], "300", engage_ent)
	# The decoys the AI jets release (combat.gd's release path: their stores, the 4 s busy time, the decoy rule).
	for m in _ai_members:
		var d: int = flight_ai.decoy(m[0])
		if d > 0 and not m[1].player:
			combat.combat(m[1], "320" if d == 1 else "310", {})


## Ours (Modern IAF, the radio menu's "engage my target", modern-iaf/docs/ai-plan.md F5): the flight's jets `to` (0
## the flight, 5 the element, 2..4 one wingman) engage the radar's locked target. False: no flight AI or nobody to
## take it.
func engage_target(to: int) -> bool:
	return engage(to, host.radio._radar_target() if host.get("radio") != null else {})


## The flight's jets `to` engage `t`, an enemy aircraft alive; else each answers "unable".
func engage(to: int, t: Dictionary) -> bool:
	if flight_ai == null:
		return false
	var ok: bool = not t.is_empty() and host.enemy_of_player(t) and int(t.get("klass", 0)) in host.radio.AIRCRAFT
	ok = ok and int(t.state) < 3
	# Taken by nobody (each "unable"): a jet already engaging keeps its target.
	var r: int = flight_ai.engage(runtime.now, to, ok, host.world_to_scene(world_of(t)) if ok else Vector3.ZERO)
	if r > 0:
		engage_ent = t
	return r >= 0


## The threat jet `ent`'s RWR and MAW show IafAi: the nearest missile flying at it (3 radar, 4 infrared), else the
## nearest live hostile radar locked on it (1 from the air, 2 from the ground; combat.gd on_lock), else none; [kind,
## scene position]. A missile is infrared when the flares decoy it (player_weapons.gd DECOY_KINDS).
func _threat_of(ent: Dictionary) -> Array:
	var me := world_of(ent)
	var ir: Array = Combat.PlayerWeapons.DECOY_KINDS[Combat.Stores.FLARE]
	var best := [0, Vector3.ZERO]
	var d := INF
	var w = host.get("weapons")
	if w != null:
		for mis in w.missiles:
			if String(mis.target_key) != String(ent.key) or mis.ended:
				continue
			var p: Vector3 = mis.position(runtime.now)
			if p.distance_to(me) < d:
				d = p.distance_to(me)
				best = [4 if int(mis.weapon.get("type", 0)) in ir else 3, p]
	if best[0] == 0:
		for o in ent.get("locked_by", {}).values():
			# (A friendly radar's lock, the player's included, is no threat; a dead unit never sends its unlock.)
			if not host.enemy_of_player(o) or int(o.get("state", 0)) >= 3:
				continue
			var p := world_of(o)
			if p.distance_to(me) < d:
				d = p.distance_to(me)
				best = [1 if o.get("airborne_class", false) else 2, p]
	if best[0] != 0:
		best[1] = host.world_to_scene(best[1])
	return best


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
	flight.ap_set_ground(
		func(pos: Vector3):
			var g = host.scene_ground(pos)
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
	for p in pilots:
		var ent: Dictionary = p.ent
		if ent.control != 1 or int(ent.state) >= 3:
			continue  # fatally hit: the destruction motion drives it (mission_runtime.gd)
		var scene_pos: Vector3 = p._state.position
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
	# After every jet's step (the player's came first, TerrainView's frame): the flight reads them all at one instant.
	if flight_ai != null:
		_step_flight_ai(now)


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
