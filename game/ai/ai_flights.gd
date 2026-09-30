## AI aircraft (docs/ai.md): every brain-controlled mission aircraft with a flight model type flies the
## original flight model (one IafFlight each, crates/iaf-flight) under its autopilot (control loops, Rust
## `autopilot.rs`), steered by its bdb brain (game/ai/brain.gd). Drawn with game/aircraft/aircraft_model.gd at
## the Present scale. `contacts()` lists them for radar / RWR.
extends Node

const Brain := preload("res://ai/brain.gd")
const AircraftModel := preload("res://aircraft/aircraft_model.gd")
const CLASS_AIRCRAFT := 0x1c
## FUN_004a9100: the FM start velocity (200, 200, 0) → 282.84 m/s along the heading.
const START_SPEED := 282.842712

var host: Node  # terrain_view.gd
var runtime: Node  # mission_runtime.gd
var pilots: Array = []  # Pilot
var _brains := {}  # bdb brain id -> rules
var _actions := {}  # bdb action id -> item
var _formations: Array = []  # [{id, kind, members: [entity], targets: [entity], route: [[x, y, alt, T, action]]}]


class Pilot:
	var ent: Dictionary
	var flight  # IafFlight
	var node: Node3D
	var brain  # brain.gd
	var formation: Dictionary = {}
	var landed := false
	var mode := 0
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


func setup(h: Node, rt: Node, bdb: Dictionary, files: Array) -> void:
	host = h
	runtime = rt
	for b in bdb.get("brains", {}).get("items", []):
		_brains[int(b["0x1e"])] = Brain.rules_of(b)
	for a in bdb.get("actions", {}).get("items", []):
		_actions[int(a["0x1e"])] = a
	var objects: Dictionary = MissionRuntime().bdb_objects(bdb)
	var present := {}
	for p in bdb.get("present", {}).get("items", []):
		present[int(p["0x1e"])] = p
	_load_formations(files)
	var planes: Dictionary = AircraftModel.index()
	var install := Settings.assets_dir().path_join("install")
	for ent in runtime.entities.values():
		if ent.player or ent.control != 1 or ent.klass != CLASS_AIRCRAFT:
			continue
		var obj: Dictionary = objects.get(ent.type, {})
		var pr: Dictionary = present.get(int(obj.get("0x53c", -1)), {})
		var plane := _plane_of(planes, String(pr.get("0x64a", "")))
		if plane == "":
			continue
		var p := Pilot.new()
		p._host = self
		p.ent = ent
		p.formation = _formation_of(ent)
		if not _start(p, install, plane):
			continue
		var model := AircraftModel.create(plane, ent.type_code, bool(p._state.on_ground_start))
		if model != null:
			model.scale = Vector3.ONE * float(pr.get("0x65e", 10.0))
			host.add_child(model)
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
	print("AI aircraft: %d flying" % pilots.size())


static func MissionRuntime():
	return preload("res://mission/mission_runtime.gd")


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
	var box := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return (box.size.x + box.size.y + box.size.z) * model.scale.x


func _load_formations(files: Array) -> void:
	if files.is_empty():
		return
	for f in files[0].get("formations", {}).get("items", []):
		var members := []
		var targets := []
		for m in f.get("members", []):
			members.append(runtime.entities.get("0:%d" % int(m.get("0x41a", -1)), {}))
			targets.append(runtime.entities.get("0:%d" % int(m.get("0x424", -1)), {}))
		var route := []
		for q in f.get("points", []):
			route.append([float(q[1]), float(q[2]), float(q[3]), float(q[4]), int(q[5])])
		_formations.append({"id": int(f["0x1e"]), "kind": int(f.get("0x3f2", 0)), "members": members, "targets": targets, "route": route})


func _formation_of(ent: Dictionary) -> Dictionary:
	for f in _formations:
		for m in f.members:
			if m == ent:
				return f
	return {}


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
	var err: String = flight.start(install, plane, pos, float(p.ent.heading), 0.0, 0.0, vel if airborne else Vector3.ZERO,
			airborne, engine_on, host.real_data)
	if err != "":
		push_warning("AI %s: %s" % [p.ent.name, err])
		return false
	flight.set_ai(host.enemy_of_player(p.ent), int(host.mission_pref("ai_level")))
	flight.ap_setup(install, host.terrain.world_origin.x, host.terrain.world_origin.y)
	flight.ap_set_ground(func(pos: Vector3):
		var g = host.terrain.height_at(pos)
		return float(g) if g != null else -1.0e9)
	var pts := PackedFloat64Array()
	for q in p.route():
		pts.append_array(q)
	flight.ap_set_route(pts)
	p.flight = flight
	p._state = flight.state()
	p._state["on_ground_start"] = not airborne
	p._state["position_world"] = w
	return true


func _process(delta: float) -> void:
	if host.frozen or host.waiting_for_ground:
		return
	var now: float = runtime.now
	for p in pilots:
		var ent: Dictionary = p.ent
		if ent.control != 1 or int(ent.state) >= 3:
			continue  # fatally hit: the destruction motion drives it (mission_runtime.gd)
		var scene_pos: Vector3 = p._state.position
		var g = host.terrain.height_at(scene_pos)
		p.flight.set_ground_height(g if g != null else -1.0e9)
		p.flight.set_ai_damage(float(ent.damage) <= 0.1)
		_feed_leader(p)
		p.flight.ap_step(now)
		p.flight.step(delta)
		p._state = p.flight.state()
		p._state["position_world"] = host.scene_to_world(p._state.position)
		ent.world = p._state.position_world
		ent.alt = ent.world.z
		ent.heading = float(p._state.heading)
		ent.vel = Vector3(p._state.velocity.x, -p._state.velocity.z, p._state.velocity.y)
		if p._state.crashed:
			runtime.set_damage_level(ent, 5)
			continue
		if p.flight.ap_landed() and not p.landed:
			p.landed = true
			landed_handler(ent)
		_place(p)
		p.brain.update(now)


func _place(p: Pilot) -> void:
	if p.node == null:
		return
	var st: Dictionary = p._state
	p.node.position = st.position
	p.node.basis = Basis(st.right, st.up, -st.forward).scaled(p.node.scale) if st.has("right") else p.node.basis
	var parts := {}
	for k in ["stick_x", "stick_y", "rudder", "flaps", "gear_down", "brakes", "gear", "on_ground", "afterburner", "rpm"]:
		if st.has(k):
			parts[k] = st[k]
	p.node.update(parts, get_process_delta_time())


## The formation leader (route member 0, FUN_00587450) for the formation / taxi / take-off loops.
func _feed_leader(p: Pilot) -> void:
	var ref: Dictionary = p.formation.members[0] if not p.formation.is_empty() else {}
	if ref.is_empty() or ref == p.ent:
		p.flight.ap_set_leader(false, false, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0, 0.0)
		return
	var active := not (int(ref.state) in [4, 5]) and int(ref.control) != 0
	var st: Dictionary
	if ref.player:
		st = host.flight.state()
	elif ref.has("pilot"):
		st = ref.pilot.state()
	else:
		var w: Vector3 = world_of(ref)
		st = {"position": host.world_to_scene(w), "velocity": Vector3.ZERO, "pitch": 0.0, "roll": 0.0, "heading": float(ref.heading)}
	p.flight.ap_set_leader(true, active, st.position, st.velocity, st.pitch, st.roll, st.heading)


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
	var f := _formation_of(ent)
	if f.is_empty() or f.members[0] != ent or f.members.size() < 2:
		return
	var w = f.members[1].get("pilot")
	if w != null and not f.route.is_empty():
		w.set_waypoint_index(f.route.size() - 1)


## Weapons, targets, radar, flares / chaff, combat on / off: the combat job (docs/ai.md §5).
func combat_hook(_ent: Dictionary, _what: String, _target: Dictionary) -> void:
	pass


## Trigger ops 21 / 22 (FUN_00440830 / FUN_004407e0).
func set_combat(ent: Dictionary, on: bool) -> void:
	var p = ent.get("pilot")
	if p == null:
		return
	if on:
		p.brain.enable_combat(runtime.now)
	else:
		p.brain.disable_combat()


## Every AI aircraft for radar / RWR: entity, world position (X east, Y north, alt m), world velocity, side.
func contacts() -> Array:
	var out := []
	for p in pilots:
		if int(p.ent.state) < 4:
			out.append({"entity": p.ent, "position": p.ent.world, "velocity": p.ent.vel, "side": p.ent.side})
	return out
