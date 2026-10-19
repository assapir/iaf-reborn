## The armed units' weapon handlers (docs/ai.md §13, §14). Ground units: the bdb brain (game/ai/brain.gd, the
## ai_flights.gd host; a mission-controlled unit's brain runs too), the target sensor, start / stop combat (550 / 560),
## the fire tick, the AAA rounds (565: the player's gun round motion, gun_rounds.gd), the SAM launches (class 0x18:
## the homing motion through player_weapons.gd launch_homing), the rockets (560) and script op 2. AI aircraft (their
## brain is the pilot's, ai_flights.gd): the sensor, the stations and the weapon actions 300–380, the decoys' count,
## the combat conditions and the gun bursts.
extends Node

const Brain := preload("res://ai/brain.gd")
const GunRounds := preload("res://weapons/gun_rounds.gd")
const Missile := preload("res://weapons/missile.gd")
const WeaponDb := preload("res://weapons/weapon_db.gd")
const Stores := preload("res://weapons/stores.gd")
const Gltf := preload("res://util/gltf.gd")
const Terrain := preload("res://terrain/terrain.gd")
const Bombs := preload("res://weapons/bombs.gd")
const PlayerWeapons := preload("res://weapons/player_weapons.gd")
const AircraftModel := preload("res://aircraft/aircraft_model.gd")

const NM := 1854.0
## Sensor classes (FUN_004ac5f0): units of other classes (6, 11 ground radar, 15 boat) never target or fire.
const SENSOR_CLASSES := [5, 8, 9, 10, 0x10]
## Sensor scan period (kind 2, classes 10 / 0x10: 6 s; UNCERTAIN for kinds 1 / 3) and slots kept.
const SCAN_PERIOD := 6.0
const SLOTS := 5
## Air mode (400 / 440, FUN_004ac820) and ground mode (410, FUN_004ac900) classes.
const AIR := [0x1c, 3, 2, 1]
const GROUND := [10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10]
## The player is seen only within 0.7 R while its radar is OFF / STBY.
const QUIET_FACTOR := 0.7
## Terrain line of sight: both ends 1.5 m up (FUN_004020d0).
const LOS_RAISE := 1.5
const RELEASE_LOS_RAISE := 3.0
## The global truce after every ground shot: 0.1 + rand·0.9 s (DAT_008321d0..d8).
const TRUCE_MIN := 0.1
const TRUCE_RAND := 0.9
## The homing weapons (class 0x18) a ground unit launches.
const HOMING := [570, 580, 590, 600, 610, 620, 630, 635]
## Launch offset in the launch attitude (FUN_004ab7b0: (0, 4, 1) = 4 m ahead, 1 m up).
const LAUNCH_OFFSET := Vector3(0, 4, 1)
## Aircraft sensors (kind 4, FUN_0043eef0): 10 slots, a scan every 2 s.
const SCAN_PERIOD_AIR := 2.0
const SLOTS_AIR := 10
## Launch (300, FUN_004440d0): the cone 30° (gun 5°), ×0.5 Rookie / ×1.5 Expert against the player's side; a 580
## only within 60° of relative bearing.
const CONE := 30.0
const CONE_GUN := 5.0
const CONE_SKILL := [0.5, 1.0, 1.5]
const LIMITED_BEARING := 60.0
## The gun envelope (FUN_00561700): max = _limitDist × 3.281 (a feet factor on metres: original bug), min 328.1 m.
const GUN_MAX_K := 3.281
const GUN_MIN := 328.1
## The gun's shot timer (DAT_0082f4e8, as the player's). An AI burst (FUN_004579f0) is the weapon-change action's
## quantity W+0xe8 (clamped by FUN_004562f0) of ticks: one round at once, then one per tick (FUN_0045a540 →
## FUN_00456d40, W+0xe4 − 1 on every tick, also when no round is free); at 0 it ends (FUN_00457b40, W+0xac = 0).
const GUN_PERIOD := 0.2
## The decoy actions' busy time (310 / 320: 4.0 s, 0x600920).
const DECOY_BUSY := 4.0
## Weapon-change wants (FUN_00452710): 350 radar AAM, 360 IR AAM (580 too, v1.1), 380 bombs.
const WANTS := {350: [600], 360: [570, 580], 380: [500]}
## The AA missile types (330 / 340 cycle the AA (1) or AG (2) stations, FUN_00452690). UNCERTAIN: the AG class.
const AA_TYPES := [570, 580, 600, 610]
const AG_TYPES := [500, 510, 560, 590, 635, 640, 650]

var host: Node  # terrain_view.gd
var ai: Node  # ai_flights.gd: the brain host
var units := {}  # entity key -> Unit
var _truce_until := -INF


class GroundPilot:
	## The brain's pilot for a unit without an autopilot: no manoeuvres, no route.
	var ent: Dictionary
	var rt: Node
	var landed := false

	func set_mode(_m: int, _arg = null) -> void:
		pass

	func state() -> Dictionary:
		var v: Vector3 = ent.vel
		return {"position_world": rt._world_of(ent), "heading": float(ent.heading), "speed": v.length(), "g": 1.0}

	func waypoint_action() -> int:
		return 0

	func waypoint_index() -> int:
		return 0

	func set_waypoint_index(_i: int) -> void:
		pass

	func fuel_ratio() -> float:
		return 100.0


class Unit:
	var ent: Dictionary
	var brain
	var w: Dictionary  # weapon record of the first valid station
	var rounds  # gun_rounds.gd, class 0x17 only
	var reaction := 10.0
	var interval := 0.5
	var range_m := 0.0
	var limit_vel := 1200.0  # the round's _limitVel (the lead time)
	var sensor_r := 0.0
	var contacts: Array = []  # [{ent, score}] best first
	var next_scan := 0.0
	var fire_next := INF
	var nodes: Array = []
	var prev_v := Vector3.ZERO
	var prev_t := -INF
	var prev_key := ""
	var missile: RefCounted = null  # the one SAM in the air (_maxNumInAir 1)
	# AI aircraft.
	var air := false
	var pilot  # ai_flights.gd Pilot
	var stations: Array = []  # 0..8 pylons, 9 gun, 10 chaff, 11 flares: {w (record or {}), count}
	var cur := -1  # the selected station
	var db
	var gate_next := 0.0  # the fire gate B+0x98 (FUN_004d4100)
	var gate_last := -INF
	var gate_interval := 1.0
	var gun_left := 0  # the burst's ticks left (W+0xe4)
	var gun_next := INF
	var decoy_until := -INF
	var round_scale := 1.0  # the round model's Present scale
	var stores  # stores.gd of an AI jet: the weight / drag on its flight model and the pylon models
	var store_nodes := {}  # station -> [Node3D per slot] (player_weapons.gd attach_stores)
	## The AI ripple (W+0xe4 left, W+0xe8 quantity, W+0xec interval, W+0xf0 period; iaf_avionics Ripple): set by the
	## actions 350 / 360 / 380; before one, 1 bomb (UNCERTAIN: W+0xe8 is not set by the handler's constructor).
	var ripple = ClassDB.instantiate("IafRipple")
	var ripple_left := 0
	var ripple_next := INF
	var ripple_target: Dictionary = {}
	var ripple_line: Array = []
	var fire_sound: Node = null  # the looping SFX_ENTITY_FIRED_WEAPON while the unit keeps firing
	var fire_sound_until := -INF


func setup(h: Node, flights: Node, bdb: Dictionary) -> void:
	host = h
	ai = flights
	var rt: Node = ai.runtime
	var db = WeaponDb.create(bdb, Settings.real_weapons())
	var objects: Dictionary = rt.bdb_objects(bdb)
	_db = db
	_objects = objects
	for ent in rt.entities.values():
		# Every armed unit other than the aircraft has a weapon handler (FUN_004b7ad6): script op 2 fires it; only the
		# sensor classes target and fire by their brain (FUN_0043eef0; helicopters, class 2, have no sensor).
		if ent.player:
			continue
		if ent.klass == 0x1c:
			if ent.has("pilot"):
				_setup_aircraft(ent, objects.get(ent.type, {}), db, rt.now)
			continue
		var w := _weapon(ent, objects.get(ent.type, {}), db)
		if w.is_empty():
			continue  # "Entity with no weapon handler" (FUN_00444b20)
		var u := Unit.new()
		u.ent = ent
		u.w = w
		u.sensor_r = sensor_nm(int(ent.type_code)) * NM
		var m: Dictionary = db.motion_for(int(w.type), int(w.generation))
		u.reaction = float(m.get("_reactionTime", 10.0))
		u.interval = float(m.get("_fireReleaseInterval", 0.5))
		if int(w.type) in [560, 565]:
			u.rounds = GunRounds.new()
			if int(w.type) == 560:
				m = {"_spiralAccel": 0.0}  # as the player's rockets: no hit sphere, they burst on the ground
				m.merge(db.motion_for(560, int(w.generation)), true)
			u.rounds.configure(m, int(w.type))
			u.rounds.units = _units_of
			u.rounds.ground = host.mission_ground
			u.rounds.detonate = _detonate.bind(String(ent.key))  # the key, not u: u holds the rounds (a cycle never freed)
			u.limit_vel = float(m.get("_limitVel", 1200.0))
			u.range_m = float(m.get("_limitDist", 4500.0)) * (0.5 if int(w.type) == 565 else 1.0)  # 565: half _limitDist (2250 m)
			_round_nodes(u, w)
		var rules: Array = ai.brain_rules(int(ent.brain)) if ent.brain >= 0 else []
		if ent.control in [1, 2] and ent.klass in SENSOR_CLASSES and not rules.is_empty():
			var p := GroundPilot.new()
			p.ent = ent
			p.rt = rt
			u.brain = Brain.new()
			u.brain.setup(ai, ent, p, rules, false)
			u.brain.reset(rt.now)
		u.next_scan = rt.now + randf() * SCAN_PERIOD  # staggered: not every unit's scan in one frame
		units[ent.key] = u
	print("Ground units armed: %d" % units.size())


## The weapon database and the bdb objects by id (for the jets handed over in flight).
var _db
var _objects := {}


## The player's old jet joins the AI (the FlyTSD's Fly): its handler with the stores it had left (`load`).
func adopt(ent: Dictionary, load: Array) -> void:
	_setup_aircraft(ent, _objects.get(ent.type, {}), _db, ai.runtime.now, load)


## A jet the player takes over leaves the AI: its handler goes; returns its stations' stores left,
## [[weapon id, count] × 12].
func hand_over(ent: Dictionary) -> Array:
	var u: Unit = units.get(ent.key)
	if u == null:
		return []
	units.erase(ent.key)
	for n in u.nodes:
		n.queue_free()
	if u.fire_sound != null and is_instance_valid(u.fire_sound):
		u.fire_sound.queue_free()
	return u.stations.map(func(s): return [int(s.w.get("id", 0)) if not s.w.is_empty() else 0, int(s.count)])


## An AI jet's handler: the pilot's brain, the sensor (kind 4), its stations (the mission's or the object's load, or
## `given`: a jet handed over in flight) and the gun's rounds. The first station selected: the first loaded pylon,
## else the gun (UNCERTAIN).
func _setup_aircraft(ent: Dictionary, obj: Dictionary, db, now: float, given: Array = []) -> void:
	var u := Unit.new()
	u.ent = ent
	u.air = true
	u.pilot = ent.pilot
	u.brain = ent.pilot.brain
	u.db = db
	u.sensor_r = sensor_nm(int(ent.type_code)) * NM
	u.next_scan = now + randf() * SCAN_PERIOD_AIR  # staggered
	var load := given if not given.is_empty() else _armed(ent, Stores.loadout(ent, obj))
	for s in load:
		var w: Dictionary = db.by_id(int(s[0])) if int(s[1]) != 0 else {}
		u.stations.append({"w": w, "count": int(s[1]) if not w.is_empty() else 0})
	u.ripple.set_values(1, 10)
	# The stores on the jet (FUN_0053b580; the Arming loads: FUN_004541d0 + FUN_00459410 redo the weight / drag).
	u.stores = Stores.new()
	u.stores.player = false
	u.stores.setup(load, db, AircraftModel.load_descriptor(String(ent.pilot.plane)), PlayerWeapons._pilon_of,
		int(ent.type_code))
	_push_stores(u)
	if ent.get("node") is Node3D:
		u.store_nodes = PlayerWeapons.attach_stores(u.stores, ent.node).nodes
	for i in 10:
		if i < u.stations.size() and int(u.stations[i].count) > 0 and (i < 9 or u.cur < 0):
			u.cur = i
			break
	_select(u, u.cur)
	var gw: Dictionary = u.stations[9].w if u.stations.size() > 9 else {}
	if not gw.is_empty():
		var m: Dictionary = db.motion_for(565, int(gw.generation))
		u.rounds = GunRounds.new()
		u.rounds.configure(m, 565)
		u.rounds.units = _units_of
		u.rounds.ground = host.mission_ground
		u.rounds.detonate = _detonate.bind(String(ent.key))  # the key, not u: u holds the rounds (a cycle never freed)
		u.limit_vel = float(m.get("_limitVel", 1200.0))
		u.range_m = float(m.get("_limitDist", 4500.0))
		_round_nodes(u, gw)
	units[ent.key] = u


func _round_nodes(u: Unit, w: Dictionary) -> void:
	u.round_scale = float(w.get("scale", 1.0))
	var path := String(w.model_path)
	var model = Gltf.object(path) if path != "" else null
	if model != null:
		for i in u.rounds.pool.size():
			var n: Node3D = Gltf.instance(model)
			n.visible = false
			add_child(n)
			u.nodes.append(n)


## The Arming screen's loads go on both members of the flight (FUN_004f0140 on FUN_004f0330 the leader and
## FUN_004f0380 the second member; docs/front-end.md §15): pylons 0..8 of the formation's two member slots.
func _armed(ent: Dictionary, load: Array) -> Array:
	var f: Dictionary = ent.pilot.formation if ent.get("pilot") != null else {}
	var n := int(f.get("kind", 0))
	if f.is_empty() or not Settings.arm_loadouts.has(n) or not f.members.slice(0, 2).has(ent):
		return load
	var arm: Array = Settings.arm_loadouts[n]
	for i in mini(9, arm.size()):
		load[i] = [int(arm[i][0]), int(arm[i][1])]
	return load


## The stores' weight and drag on the AI jet's flight model (S+0x424 / 0x42c / 0x428, as the player's).
func _push_stores(u: Unit) -> void:
	if u.stores != null and u.pilot != null and u.pilot.get("flight") != null:
		u.pilot.flight.set_stores(u.stores.fm_mass, u.stores.fm_di_left, u.stores.fm_di_right)


## A store (or a gun round) left station i: the count, the weight / drag (FUN_0053bf10 -> FUN_0053c8b0).
func _spent(u: Unit, i: int) -> void:
	u.stations[i].count = int(u.stations[i].count) - 1
	if u.stores == null or u.stores.station(i).is_empty():
		return
	if i == 9:
		u.stores.consume(i)
	else:
		u.stores.fired(i)
		_push_stores(u)


## The pylon models (FUN_0053e430): `count` stores per station with EXTERNAL STORES on, within 9000 m of the camera.
func _show_stores(u: Unit) -> void:
	if u.store_nodes.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var node = u.ent.get("node")
	var near: bool = cam == null or (node is Node3D and is_instance_valid(node)
		and cam.global_position.distance_to(node.global_position) < PlayerWeapons.STORES_DRAW_DIST)
	for i in u.store_nodes:
		var n := int(u.stores.station(i).get("count", 0))
		for k in u.store_nodes[i].size():
			var sn = u.store_nodes[i][k]
			if is_instance_valid(sn):
				sn.visible = Settings.external_stores and near and k < n


func _select(u: Unit, i: int) -> void:
	u.cur = i
	u.w = u.stations[i].w if i >= 0 and i < u.stations.size() else {}


## The unit's weapon: the first of its first 2 valid stations (FUN_004b7ea3; the second is not used).
static func _weapon(ent: Dictionary, obj: Dictionary, db) -> Dictionary:
	for s in Stores.loadout(ent, obj):
		if int(s[1]) == 0 or db.by_id(int(s[0])).is_empty():
			continue
		return db.by_id(int(s[0]))
	return {}


## Sensor range in nm by type code (FUN_004acae0, × 1854 m).
static func sensor_nm(type: int) -> float:
	if type >= 250 and type <= 280:
		return 3.0
	if type in [290, 310, 330, 340]:
		return 20.0
	if type in [300, 320] or (type >= 370 and type <= 390):
		return 10.0
	if type in [350, 360]:
		return 5.0
	return 40.0


## The units a round can hit ({key, pos}): the player and every drawn unit (the round's candidates are its target).
func _units_of() -> Array:
	var out := []
	for ent in ai.runtime.entities.values():
		if int(ent.state) < 5 and (ent.player or ent.node != null):
			out.append({"key": ent.key, "pos": ai.runtime._world_of(ent)})
	return out


func _process(_delta: float) -> void:
	if not (host.frozen or host.waiting_for_ground):
		update(ai.runtime.now)


func update(now: float) -> void:
	for u in units.values():
		if int(u.ent.state) >= 3:
			u.fire_next = INF
		elif u.brain != null:
			if now >= u.next_scan:
				u.next_scan = now + (SCAN_PERIOD_AIR if u.air else SCAN_PERIOD)
				_scan(u)
			if not u.air:
				u.brain.update(now)  # an aircraft's brain runs with its pilot (ai_flights.gd)
			while u.ripple_left > 0 and now >= u.ripple_next:
				u.ripple_next += float(u.ripple.period())
				_ripple_tick(u)
			while u.gun_left > 0 and now >= u.gun_next:
				u.gun_next += GUN_PERIOD
				u.gun_left -= 1
				_gun_round(u, u.gun_next - GUN_PERIOD)
			while now >= u.fire_next:
				u.fire_next += u.interval
				_fire_tick(u, now)
		if u.air:
			_show_stores(u)
		if u.fire_sound != null and (now > u.fire_sound_until or int(u.ent.state) >= 3):
			host.sounds.stop(u.fire_sound)
			u.fire_sound = null
		if u.rounds != null:
			u.rounds.update(now)
			for k in u.nodes.size():
				var r: Dictionary = u.rounds.pool[k]
				var n: Node3D = u.nodes[k]
				n.visible = r.flying
				if r.flying:
					n.position = host.world_to_scene(u.rounds.position(r, now))
					var d := Terrain.dir_to_scene(r.u)
					n.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT).scaled(Vector3.ONE * u.round_scale)


## The sensor scan (FUN_004af300): hostile units in range with terrain line of sight, score 100 / dist, the
## best 5. The player only within 0.7 R with its radar OFF / STBY; a target jamming (ctl+0x1b8: only the player has
## a controller, so only it jams) is seen at any range. The owner's own jamming (0.8 R / 0.5 R) needs a controller:
## never an AI unit. Both modes' classes are kept; the selector filters (UNCERTAIN: the original scans one mode).
func _scan(u: Unit) -> void:
	var rt: Node = ai.runtime
	var me: Vector3 = rt._world_of(u.ent)
	var list := []
	for e in rt.entities.values():
		if e == u.ent or int(e.state) >= 4 or e.side == u.ent.side or not (e.klass in AIR or e.klass in GROUND):
			continue
		if not e.player and e.node == null:
			continue
		var p: Vector3 = rt._world_of(e)
		var d := p.distance_to(me)
		var r := u.sensor_r
		if e.player and host.weapons != null and host.weapons.radar.mode <= 1 and d > r * QUIET_FACTOR:
			continue
		if not (e.player and _jamming()) and d > r:
			continue
		if not line_of_sight(me, p):
			continue
		list.append({"ent": e, "score": 100.0 / maxf(d, 1.0)})
	list.sort_custom(func(a, b): return a.score > b.score)
	u.contacts = list.slice(0, SLOTS_AIR if u.air else SLOTS)


## Terrain line of sight (FUN_004020d0, its sampling UNCERTAIN), both ends raised: the radar's (IafRadar, stepped by
## the clearance, at least every 20 m near the ground; radar.rs `line_of_sight`).
func line_of_sight(a: Vector3, b: Vector3, raise := LOS_RAISE) -> bool:
	return IafRadar.line_of_sight(a + Vector3(0, 0, raise), b + Vector3(0, 0, raise), host.mission_ground)


## Brain combat actions (ai_flights.gd combat_hook). Targets: 400 / 440 the best of the air mode scan, 410 of the
## ground mode scan, 420 the primary target.
func combat(ent: Dictionary, what: String, target: Dictionary) -> Variant:
	var u: Unit = units.get(ent.key)
	if u == null:
		return null
	if u.air and what in ["300", "310", "320", "330", "340", "350", "360", "370", "380"]:
		return _air_action(u, int(what), target)
	match what:
		"420":
			# FUN_004ac9e0: the primary target (brain+0x74, the formation slot's target) unless it is me; else none.
			var pt: Dictionary = u.brain.primary
			_pick(u, pt if not pt.is_empty() and not is_same(pt, ent) else {})
		"400", "440", "410":
			# FUN_004ac820 / FUN_004ac900: the best of the air / ground mode scan (a dead pick rescans).
			var classes: Array = AIR if what in ["400", "440"] else GROUND
			var pick: Dictionary = {}
			for c in u.contacts:
				if c.ent.klass in classes and int(c.ent.state) < 4:
					pick = c.ent
					break
			_pick(u, pick)
		"430":
			# FUN_00444a60: target = my nearest RWR emitter with a controller (FUN_00451f70), else brain+0x7c: an AI
			# unit has no controller. B+0x70 is written directly (no on-lock).
			u.brain.target = u.brain.attacker
		"start":
			# FUN_004aa900(0) → FUN_004ac120(1): first shot after _reactionTime, then every _fireReleaseInterval (the RWR
			# lock comes with the selector's pick, _pick).
			u.fire_next = ai.runtime.now + u.reaction
		"stop", "safe":
			u.fire_next = INF
	return null


# --- AI aircraft (docs/ai.md §13) -------------------------------------------------------------------

## The jet's pose now (world): {pos, vel, fwd, up, right}.
func _pose(u: Unit) -> Dictionary:
	var st: Dictionary = u.pilot.state()
	return {"pos": ai.runtime._world_of(u.ent), "vel": u.ent.vel, "fwd": Terrain.dir_to_world(st.get("forward", Vector3.FORWARD)),
		"up": Terrain.dir_to_world(st.get("up", Vector3.UP)), "right": Terrain.dir_to_world(st.get("right", Vector3.RIGHT))}


## The fire gate B+0x98 (FUN_004d4100): passes when now < last or now > next, then next = now + interval.
func _gate(u: Unit, now: float) -> bool:
	if not (now < u.gate_last or now > u.gate_next):
		return false
	u.gate_last = now
	u.gate_next = now + u.gate_interval
	return true


## A weapon action of an AI jet; returns whether it happened (the brain marks the action type then).
func _air_action(u: Unit, code: int, t: Dictionary) -> bool:
	var now: float = ai.runtime.now
	var act: Dictionary = {}
	match code:
		300:
			return _launch(u, t, now)
		310, 320:
			# One flare (station 11) / chaff (station 10) when not busy (FUN_00444640 / 4446d0): busy for 4 s first, then
			# the player's release path (its pool, flight, look and decoy rule, player_weapons.release_decoy); the count
			# drops only when a decoy left. UNCERTAIN: the AI's station point (the jet's position here).
			var i := 11 if code == 310 else 10
			if now < u.decoy_until:
				return false
			u.decoy_until = now + DECOY_BUSY
			if i >= u.stations.size() or int(u.stations[i].count) <= 0 or host.weapons == null:
				return true
			var o := _pose(u)
			var st: Dictionary = u.pilot.state()
			if host.weapons.release_decoy(550 if code == 310 else 540, o.pos, o, u.ent.key, int(st.get("afterburner", 0)) > 0,
					float(st.get("g", 1.0))):
				_spent(u, i)
			return true
		330, 340:
			# FUN_00452690: refused while releasing (W+0xac); the action's quantity / interval become the AI ripple's
			# (and the gun burst's); one cycle step to the next AA (330) / AG (340) station with rounds (FUN_0053b8b0).
			if _releasing(u):
				return false
			var a0 := _action(code)
			u.ripple.set_values(int(a0.get("0x82", 1)), int(a0.get("0x96", 10)))
			var kinds: Array = AA_TYPES if code == 330 else AG_TYPES
			for k in range(1, 10):
				var i := (u.cur + k) % 9 if u.cur >= 0 and u.cur < 9 else k - 1
				if int(u.stations[i].count) > 0 and int(u.stations[i].w.get("type", 0)) in kinds:
					_select(u, i)
					_gate_interval(u, code)
					return true
			return false
		350, 360, 380:
			# FUN_00452710: refused while releasing (W+0xac); the action's quantity / interval (bdb 0x82 / 0x96,
			# FUN_004562f0) become the AI ripple's; then up to 10 steps to the wanted type with rounds.
			if _releasing(u):
				return false
			var a := _action(code)
			u.ripple.set_values(int(a.get("0x82", 1)), int(a.get("0x96", 10)))
			for i in 9:
				if int(u.stations[i].count) > 0 and int(u.stations[i].w.get("type", 0)) in WANTS[code]:
					_select(u, i)
					_gate_interval(u, code)
					return true
			return false
		370:
			# FUN_004448e0 → FUN_00452710(0x172, …): as 350, to the gun (station 9).
			if _releasing(u):
				return false
			var a1 := _action(code)
			u.ripple.set_values(int(a1.get("0x82", 1)), int(a1.get("0x96", 10)))
			if u.stations.size() > 9 and int(u.stations[9].count) > 0:
				_select(u, 9)
				_gate_interval(u, code)
				return true
			return false
	return false


## W+0xac: an AI ripple or gun burst runs (FUN_00454270 sets it; the weapon-change actions are refused).
func _releasing(u: Unit) -> bool:
	return u.ripple_left > 0 or u.gun_left > 0


## The weapon-change action's fire gate interval: its bdb action +0x8c; 370 (FUN_004448e0) a fixed 5.0 s.
func _gate_interval(u: Unit, code: int) -> void:
	if code == 370:
		u.gate_interval = 5.0
		return
	var a := _action(code)
	if a.has("0x8c"):
		u.gate_interval = float(a["0x8c"])


## The bdb action record of a code ({} when the bdb has none).
func _action(code: int) -> Dictionary:
	for id in ai._actions:
		var a: Dictionary = ai._actions[id]
		if int(a.get("0xbe", -1)) == code:
			return a
	return {}


## The envelope [max, min] of the selected weapon against `t` (motion vt+0x74): the chase class's DLZ; the gun's
## _limitDist × 3.281 / 328.1 m. [0, 0] = none.
func _envelope(u: Unit, t: Dictionary) -> Array:
	var type := int(u.w.get("type", 0))
	if type == 565:
		return [u.range_m * GUN_MAX_K, GUN_MIN]
	if type in AA_TYPES and host.weapons != null:
		var o := _pose(u)
		return Missile.dlz(host.weapons._motion(u.w), {"pos": o.pos, "fwd": o.fwd, "vel": o.vel},
			{"pos": ai.runtime._world_of(t), "vel": _velocity_of(t)})
	return [0.0, 0.0]


## 300 Launch (FUN_004440d0): the selected weapon at the target inside its envelope, within the cone (30°, gun 5°;
## ×0.5 Rookie / ×1.5 Expert when hostile to the player), a 580 within 60° of relative bearing, the fire gate open;
## then FUN_00454270(T, 1): a missile through the homing release, q 1.0 (UNCERTAIN: the AI's q), or a gun burst.
func _launch(u: Unit, t: Dictionary, now: float) -> bool:
	if t.is_empty() or u.cur < 0 or int(u.stations[u.cur].count) <= 0 or u.gun_left > 0:
		return false
	var o := _pose(u)
	var tp: Vector3 = ai.runtime._world_of(t)
	var d: Vector3 = tp - o.pos
	var dist := d.length()
	var env := _envelope(u, t)
	if dist <= 0.0 or dist < float(env[1]) or dist > float(env[0]):
		return false
	var type := int(u.w.type)
	var cone := CONE_GUN if type == 565 else CONE
	if host.enemy_of_player(u.ent):
		cone *= CONE_SKILL[clampi(int(host.mission_pref("ai_level")), 0, 2)]
	if rad_to_deg(acos(clampf(o.fwd.dot(d / dist), -1.0, 1.0))) > cone:
		return false
	if type == 580 and absf(_relative_bearing(u, t)) > LIMITED_BEARING:
		return false
	if not _gate(u, now):
		return false
	if type == 565:
		u.gun_left = u.ripple.qty()
		u.gun_next = now
		return true
	if host.weapons == null:
		return false
	_spent(u, u.cur)
	# FUN_00454b70 (an AI shooter, 570..610): q 1.0, less against a jamming target (the player with its ECM on).
	var roll = float(randi() & 0x7fff) / 32767.0 if t.get("player", false) and _jamming() else null
	host.weapons.launch_homing(u.w, o.pos, o, String(t.key), IafRelease.ai_launch_q(roll), u.ent)
	return true


## A bombing manoeuvre's release (440440: the fire gate, then the selected weapon as 300's FUN_00454270): bombs
## (500 / 510) start the AI ripple (W+0xe4 = W+0xe8, a timer every W+0xf0 s; none while one runs, W+0xac), a missile
## or a gun burst as Launch does. Rockets (560) and laser bombs (650) ripple too (their FUN_00454270 case).
func release(ent: Dictionary) -> void:
	var u: Unit = units.get(ent.key)
	var now: float = ai.runtime.now
	if u == null or not u.air or u.cur < 0 or int(u.stations[u.cur].count) <= 0 or _releasing(u) or not _gate(u, now):
		return
	var t: Dictionary = u.brain.target
	if t.is_empty() or host.weapons == null:
		return
	var o := _pose(u)
	var type := int(u.w.type)
	if type in [500, 510, 560, 650]:
		u.ripple_left = u.ripple.qty()
		u.ripple_next = now  # the first store on the next tick
		u.ripple_target = t
	elif type == 565:
		u.gun_left = u.ripple.qty()
		u.gun_next = now
	elif type in AA_TYPES or type in HOMING:
		_spent(u, u.cur)
		host.weapons.launch_homing(u.w, o.pos, o, String(t.key), 1.0, u.ent)


## One store of the AI ripple (the timer callback FUN_004545e0 with p4 = 1: no release permission, no delayed
## release): the selected station, else another with the same weapon; the aim (FUN_00454b70, AI): the target led by
## its velocity over t = |T − own| / own speed, spread on the ripple line frozen at the first store (FUN_00457c20,
## W+0xec m along the heading); W+0xe4 − 1, at 0 the ripple ends. No rounds → it ends.
func _ripple_tick(u: Unit) -> void:
	if int(u.stations[u.cur].count) <= 0:
		var id = u.w.get("id")
		for i in 9:
			if int(u.stations[i].count) > 0 and u.stations[i].w.get("id") == id:
				_select(u, i)
				break
	if int(u.stations[u.cur].count) <= 0 or host.weapons == null:
		u.ripple_left = 0
		return
	var o := _pose(u)
	var t := u.ripple_target
	var qty: int = u.ripple.qty()
	if u.ripple_left == qty or u.ripple_line.size() != qty:
		var p: Vector3 = ai.runtime._world_of(t) if not t.is_empty() else o.pos
		var spd: float = o.vel.length()
		# 650 (FUN_00454b70 case 0x28a, AI): the target where it is now, no lead.
		if not t.is_empty() and spd > 1.0 and int(u.w.type) != 650:
			p += _velocity_of(t) * (p.distance_to(o.pos) / spd)
		u.ripple_line = Bombs.ripple_line(p, qty, float(u.ripple.interval()), deg_to_rad(float(u.ent.heading)),
			host.mission_ground)
	var aim: Vector3 = u.ripple_line[u.ripple.index(u.ripple_left)]
	_spent(u, u.cur)
	host.weapons.release_store(u.w, o.pos, o.vel, aim, u.ent)
	u.ripple_left -= 1


## One AI gun round (FUN_00456d40 for the AI: the shot line is the nose, no 1° elevation), at the target as the
## locked unit; a round per 0.2 s tick (UNCERTAIN: the AI's count per tick).
func _gun_round(u: Unit, now: float) -> void:
	if u.stations.size() <= 9 or int(u.stations[9].count) <= 0:
		u.gun_left = 0  # no rounds left: the burst ends (FUN_00456d40 → FUN_00457b40)
		return
	if u.rounds == null or not u.rounds.next_free():
		return
	var o := _pose(u)
	var a: Vector3 = u.rounds.aim_point(o.pos, o.vel, o.fwd, false)
	u.rounds.fire(now, o.pos, o.pos + o.fwd * 10.0, o.vel, a, String(u.brain.target.get("key", "")), u.ent.key,
		Settings.easy_aiming)
	_spent(u, 9)


## Condition 10: the target's bearing relative to my heading (degrees, FUN_0044e770).
func _relative_bearing(u: Unit, t: Dictionary) -> float:
	var d: Vector3 = ai.runtime._world_of(t) - ai.runtime._world_of(u.ent)
	return wrapf(rad_to_deg(atan2(d.x, d.y)) - float(u.ent.heading), -180.0, 180.0)


## The combat conditions of an AI jet's brain (docs/ai.md §13.2); null = invalid.
func measure(ent: Dictionary, code: int, t: Dictionary) -> Variant:
	var u: Unit = units.get(ent.key)
	if u == null:
		return null
	var rt: Node = ai.runtime
	match code:
		8:
			# No external tanks attached (FUN_004593e0).
			for i in 9:
				if int(u.stations[i].count) > 0 and int(u.stations[i].w.get("type", 0)) == 660:
					return 0
			return 1
		10:
			return null if t.is_empty() else _relative_bearing(u, t)
		12:
			return null if t.is_empty() else _velocity_of(t).length() * 1.9427955
		14:
			if t.is_empty():
				return null
			var d: Vector3 = rt._world_of(t) - rt._world_of(ent)
			return d.normalized().dot(_velocity_of(ent) - _velocity_of(t)) if d.length() > 0.0 else 0.0
		17:
			if t.is_empty():
				return null
			if t.get("player", false) and host.flight != null:
				return float(host.flight.state().g)
			return float(t.pilot.state().get("g", 1.0)) if t.has("pilot") else 1.0
		20:
			# Gun: within _limitDist and Dogchase with the nose on (NoseOnTargetAng); else the envelope has a max.
			if t.is_empty() or u.cur < 0:
				return 0
			if int(u.w.get("type", 0)) == 565:
				var near: bool = rt._world_of(t).distance_to(rt._world_of(ent)) <= u.range_m
				return int(near and u.pilot.mode == 0x11 and u.pilot.flight.ap_nose_on())
			return int(float(_envelope(u, t)[0]) != 0.0)
		21:
			return int(u.stations[u.cur].count) if u.cur >= 0 else 0
		26:
			# FUN_005c1530: the target's brain+0x7c is set (a sensor locked it, on_lock), or it has a controller (the
			# player) whose RWR lists something (FUN_00452110: RWR+0x174).
			if t.is_empty():
				return null
			if t.get("player", false):
				return int(host.weapons != null and host.weapons.rwr.count != 0)
			var tb = brain_of(t)
			return int(tb != null and not tb.attacker.is_empty())
		27:
			return null  # the leader locked: needs the leader's controller (UNCERTAIN)
		37:
			var ld: Dictionary = u.brain.leader
			if ld.is_empty() or not ld.has("pilot"):
				return null
			var lt: Dictionary = ld.pilot.brain.target
			return null if lt.is_empty() else int(is_same(lt, t))
	return null


## A selector's pick: the old target is unlocked, the new one locked: the AI sensor's override (FUN_004aca80 /
## FUN_004aca60) passes only aircraft (class 0x1c) to the on-unlock / on-lock.
func _pick(u: Unit, t: Dictionary) -> void:
	var old: Dictionary = u.brain.target
	if not is_same(old, t):
		if int(old.get("klass", 0)) == 0x1c:
			on_lock(u.ent, old, false)
		if int(t.get("klass", 0)) == 0x1c:
			on_lock(u.ent, t, true)
	u.brain.target = t


## On-lock / on-unlock of `owner`'s sensor or radar (FUN_004b0510 / FUN_004b04d0): a target with a controller (the
## player) hears it on its RWR (FUN_0044deb0 / FUN_0044e030); another target's brain+0x7c = the target itself when
## free (original bug: not the owner, so condition 38 never holds; Physics "fix_lock_threat": the owner), cleared on
## the unlock while it still holds that.
func on_lock(owner: Dictionary, t: Dictionary, on: bool) -> void:
	if t.is_empty() or host.weapons == null:
		return
	if t.get("player", false):
		if on:
			host.weapons.rwr.lock(owner.key)
		else:
			host.weapons.rwr.unlock(owner.key)
		if host.has_method("blackbox_event"):
			host.blackbox_event({"event": "lock" if on else "unlock", "key": String(owner.key)})
		return
	var b = brain_of(t)
	if b == null:
		return
	var who: Dictionary = owner if host.weapons.lock_threat_fix else t
	if on:
		if b.attacker.is_empty():
			b.attacker = who
	elif is_same(b.attacker, who):
		b.attacker = {}


## A unit's brain: an AI aircraft's (its pilot's) or an armed ground unit's; null without one.
func brain_of(ent: Dictionary):
	var p = ent.get("pilot")
	if p != null and p.get("brain") != null:
		return p.brain
	var u: Unit = units.get(ent.get("key", ""))
	return u.brain if u != null else null


## The player's jammer on (ctl+0x1b8, the ECM light).
func _jamming() -> bool:
	return host.weapons != null and host.weapons.ecm_on()


## Trigger ops 21 / 22.
func set_combat(ent: Dictionary, on: bool) -> void:
	var u: Unit = units.get(ent.key)
	if u == null or u.brain == null:
		return
	if on:
		u.brain.enable_combat(ai.runtime.now)
	else:
		u.brain.disable_combat()


## The fire tick (FUN_004ab110): the target dead → the timer stops. Class 0x17 (565): out of range (_limitDist ×0.5)
## → no shot; aim at the lead point T + V·t + ½A·t² (t = |T − P| / _limitVel). Class 0x18: only with the target
## inside the missile's DLZ from the unit's pose (FUN_005624f0: its heading is the nose, so a site never fires at a
## target 90° or more off its heading; original quirk), q 1.0. Then the release (FUN_004ab810): the global truce
## (taken even when the shot is skipped next), a busy pool object, the terrain line of sight. The ring's 3–4 steps
## per gun shot (pool quirk) are not reproduced.
func _fire_tick(u: Unit, now: float) -> void:
	var t: Dictionary = u.brain.target
	if t.is_empty() or int(t.state) >= 4:
		u.fire_next = INF
		return
	var rt: Node = ai.runtime
	var p: Vector3 = rt._world_of(u.ent)
	var tp: Vector3 = rt._world_of(t)
	var tv: Vector3 = _velocity_of(t)
	var acc := Vector3.ZERO
	if u.prev_key == t.key and now > u.prev_t:
		acc = (tv - u.prev_v) / (now - u.prev_t)
	u.prev_key = t.key
	u.prev_v = tv
	u.prev_t = now
	var dist := tp.distance_to(p)
	var h := deg_to_rad(float(u.ent.heading))
	var nose := Vector3(sin(h), cos(h), 0)
	var aim := tp
	if _fixed(u):
		if dist > u.range_m:
			return
		var ft: float = dist / u.limit_vel
		aim = tp + tv * ft + 0.5 * acc * ft * ft
	elif int(u.w.type) in HOMING and host.weapons != null:
		var env: Array = Missile.dlz(host.weapons._motion(u.w), {"pos": p, "fwd": nose, "vel": Vector3.ZERO}, {"pos": tp, "vel": tv})
		if dist < float(env[1]) or dist > float(env[0]):
			return
	else:
		return
	_release(u, t, aim, now, true)


## Script trigger op 2 Launch at target (FUN_005c42f0 → FUN_004aae40, target = entity 0x8ac): the unit's weapon at
## the target's position now (no lead, no range, no DLZ), q 1.0, through the release. A unit not in combat (the
## handler's SAFE flag +0x28 set: "Fired a weapon by the Scenario") skips the truce. UNCERTAIN: the SAFE flag's
## initial value (taken as set until start combat). `kill`: the entry's 0x852 (script +0x3c) ≠ 0, release flag 2
## (the blast, then the target explodes); 0 is the editor's "Miss …" shot, flag 0: it flies and bursts, hurting nothing
## (FUN_004d6130 @4d6597 / @4d673a).
func script_fire(ent: Dictionary, target: Dictionary, kill := false) -> void:
	var u: Unit = units.get(ent.key)
	if u == null or target.is_empty() or int(u.ent.state) >= 3:
		return
	_release(u, target, ai.runtime._world_of(target), ai.runtime.now, u.fire_next != INF, 2 if kill else 0)


## Script trigger op 1 Launch at location (FUN_005c4160 → FUN_004aad10): the unit's weapon at the point `at` (no target,
## the pose's angles 0), through the release, the truce skipped out of combat as op 2.
func script_fire_at(ent: Dictionary, at: Vector3) -> void:
	var u: Unit = units.get(ent.key)
	if u == null or int(u.ent.state) >= 3:
		return
	_release(u, {}, at, ai.runtime.now, u.fire_next != INF)


## The release (FUN_004ab810): the global truce (taken even when the shot is skipped next; skipped in SAFE mode), a
## busy pool object, the terrain line of sight, then the round at `aim` or the missile at `t`.
## `flag` (the weapon's +0x100, FUN_004d5d10): 1 a normal shot (the fire tick, op 1); op 2 passes 2 for a kill shot
## (0x852 ≠ 0) or 0 for a miss for show; FUN_004d6130 applies the blast only with a flag, and with 2 then explodes the
## target.
func _release(u: Unit, t: Dictionary, aim: Vector3, now: float, truce: bool, flag := 1) -> void:
	var rt: Node = ai.runtime
	var p: Vector3 = rt._world_of(u.ent)
	var tp: Vector3 = rt._world_of(t) if not t.is_empty() else aim  # {} = at a point (script op 1)
	var dist := tp.distance_to(p)
	var h := deg_to_rad(float(u.ent.heading))
	var nose := Vector3(sin(h), cos(h), 0)
	if not u.air:
		# A release hides the unit's Missile part (part record +8 = 0, FUN_004ab810 @4aba06), before the truce:
		# also when the shot is then skipped.
		if not u.ent.has("parts"):
			u.ent["parts"] = {}
		if not u.ent.parts.get("missile_gone", false):
			u.ent.parts["missile_gone"] = true
			host.mission_entity_parts(u.ent)
	if truce:
		if now < _truce_until:
			return  # "Entities in truce"
		_truce_until = now + TRUCE_MIN + randf() * TRUCE_RAND
	if not _fixed(u) and (not int(u.w.type) in HOMING or host.weapons == null):
		return
	var busy: bool = u.missile != null and u.missile in host.weapons.missiles if not _fixed(u) else not u.rounds.next_free()
	# The release's line of sight raises both ends by 3 m (−1.5 subtracted twice, 0x6031e0 @4abd14), not the
	# sensor's 1.5 m.
	if busy or not line_of_sight(p, tp, RELEASE_LOS_RAISE):
		return
	# The launch attitude (FUN_004ab810): the part angles, which only script motion op 11 turns to a target (the
	# release reads them, it does not turn them): tanks (type 250) the turret's heading, level; SAM launchers
	# (types 290–340) the launcher's heading, pitched toward the target; others the hull's heading, level. The round or
	# missile starts at (0, 4, 1) in it (FUN_004ab7b0). Part angles are +θ to the left of the hull (vehicle_parts.gd).
	# UNCERTAIN: the tank's heading taken as hull + turret (Ghidra's stack aliasing hides the hull term).
	var tc := int(u.ent.type_code)
	var parts: Dictionary = u.ent.get("parts", {})
	if tc == 250:
		var b := h - deg_to_rad(float(parts.get("turret", 0.0)))
		nose = Vector3(sin(b), cos(b), 0)
	elif tc >= 290 and tc <= 340:
		var b := h - deg_to_rad(float(parts.get("launcher", 0.0)))
		var pitch := asin(clampf((tp.z - p.z) / dist, -1.0, 1.0)) if dist > 0.0 else 0.0
		nose = Vector3(sin(b) * cos(pitch), cos(b) * cos(pitch), sin(pitch))
	var right := nose.cross(Vector3(0, 0, 1))
	right = right.normalized() if right.length() > 1e-4 else Vector3(1, 0, 0)
	var up := right.cross(nose)
	var at := p + right * LAUNCH_OFFSET.x + nose * LAUNCH_OFFSET.y + up * LAUNCH_OFFSET.z
	if _fixed(u):
		# Its speed adds the launcher's (FUN_004d5d10 takes the mover's velocity, vt+0x38).
		var slot: int = u.rounds.fire(now, at, at, u.ent.get("vel", Vector3.ZERO), aim, "", u.ent.key, Settings.easy_aiming, [t.key] if not t.is_empty() else [])
		if slot >= 0:
			u.rounds.pool[slot].flag = flag
			u.rounds.pool[slot].target = t
		# The row is a loop (cyclic): one per unit, kept while it fires again within two intervals (UNCERTAIN: the
		# original's stop), else every shot left a loop playing for good.
		u.fire_sound_until = now + 2.0 * u.interval
		if host.get("sounds") != null and not is_instance_valid(u.fire_sound):
			u.fire_sound = host.sounds.play("SFX_ENTITY_FIRED_WEAPON", "OST_GUNBULLET")
			if u.fire_sound is Node3D:
				u.fire_sound.top_level = true
				u.fire_sound.global_position = host.world_to_scene(at)
		return
	u.missile = host.weapons.launch_homing(u.w, at, {"vel": Vector3.ZERO, "fwd": nose, "up": up, "right": right},
		String(t.get("key", "")), 1.0, u.ent, null if not t.is_empty() else aim)
	u.missile.set_meta("flag", flag)


## The selected weapon flies the fixed motion (class 0x17: 560 rockets, 565 gun): rounds, not a missile.
func _fixed(u: Unit) -> bool:
	return u.rounds != null and int(u.w.get("type", 0)) in [560, 565]


func _velocity_of(ent: Dictionary) -> Vector3:
	if ent.player and host.flight != null:
		return Terrain.dir_to_world(host.flight.state().velocity)
	return ent.vel


## FUN_004d6130 for a ground round: a sphere hit blasts the target, the end of flight (an air burst) or a
## ground hit every unit around. The look as the player's: a gun round's impact on a hit or the ground, a rocket's
## burst always.
func _detonate(r: Dictionary, pos: Vector3, cands, hit: Dictionary, key: String) -> void:
	var u: Unit = units.get(key)
	if u == null:
		return
	var rocket := int(u.w.type) == 560
	var flag: int = r.get("flag", 1)
	if flag != 0:
		ai.runtime.area_damage(pos, float(u.w.power), float(u.w.radius), u.ent, "rocket" if rocket else "gun", cands)
	if flag == 2:
		ai.runtime.scripted_kill(r.get("target", {}), u.ent)
	if host.weapons == null:
		return
	if rocket:
		host.weapons.rocket_effect(pos)
	elif not hit.is_empty():
		host.weapons.gun_hit_effect(hit.pos if hit.has("pos") else pos)
