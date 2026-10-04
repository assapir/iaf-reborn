## Ground units' weapons (docs/ai.md §14): every ground unit with a brain and a weapon (brain or mission controlled:
## a mission-controlled unit's brain runs too, docs/ai.md §2) gets its bdb brain
## (game/ai/brain.gd, the ai_flights.gd host), the target sensor, start / stop combat (550 / 560), the fire
## tick, the AAA rounds (565: the player's gun round motion, gun_rounds.gd) and the SAM launches (class 0x18: the
## homing motion through player_weapons.gd launch_homing) and the rockets (560: the player's rocket motion).
extends Node

const Brain := preload("res://ai/brain.gd")
const GunRounds := preload("res://weapons/gun_rounds.gd")
const Missile := preload("res://weapons/missile.gd")
const WeaponDb := preload("res://weapons/weapon_db.gd")
const Stores := preload("res://weapons/stores.gd")
const Gltf := preload("res://util/gltf.gd")

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
## The global truce after every ground shot: 0.1 + rand·0.9 s (DAT_008321d0..d8).
const TRUCE_MIN := 0.1
const TRUCE_RAND := 0.9
## The homing weapons (class 0x18) a ground unit launches.
const HOMING := [570, 580, 590, 600, 610, 620, 630, 635]
## Launch offset in the launch attitude (FUN_004ab7b0: (0, 4, 1) = 4 m ahead, 1 m up).
const LAUNCH_OFFSET := Vector3(0, 4, 1)

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


func setup(h: Node, flights: Node, bdb: Dictionary) -> void:
	host = h
	ai = flights
	var rt: Node = ai.runtime
	var db = WeaponDb.create(bdb, Settings.real_weapons())
	var objects: Dictionary = rt.bdb_objects(bdb)
	var models := {}
	for ent in rt.entities.values():
		# Every armed unit other than the aircraft has a weapon handler (FUN_004b7ad6): script op 2 fires it; only the
		# sensor classes target and fire by their brain (FUN_0043eef0; helicopters, class 2, have no sensor).
		if ent.player or ent.klass == 0x1c:
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
			u.rounds.configure(m)
			u.rounds.units = _units_of
			u.rounds.ground = host.mission_ground
			u.rounds.detonate = _detonate.bind(u)
			u.limit_vel = float(m.get("_limitVel", 1200.0))
			u.range_m = float(m.get("_limitDist", 4500.0)) * (0.5 if int(w.type) == 565 else 1.0)  # 565: half _limitDist (2250 m)
			var path := String(w.model_path)
			if path != "" and not models.has(path):
				models[path] = Gltf.open(Settings.assets_dir().path_join("converted/objects").path_join(path))
			if models.get(path) != null:
				for i in u.rounds.pool.size():
					var n: Node3D = Gltf.instance(models[path])
					n.visible = false
					add_child(n)
					u.nodes.append(n)
		var rules: Array = ai.brain_rules(int(ent.brain)) if ent.brain >= 0 else []
		if ent.control in [1, 2] and ent.klass in SENSOR_CLASSES and not rules.is_empty():
			var p := GroundPilot.new()
			p.ent = ent
			p.rt = rt
			u.brain = Brain.new()
			u.brain.setup(ai, ent, p, rules, false)
			u.brain.reset(rt.now)
		u.next_scan = rt.now
		units[ent.key] = u
	print("Ground units armed: %d" % units.size())


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
				u.next_scan = now + SCAN_PERIOD
				_scan(u)
			u.brain.update(now)
			while now >= u.fire_next:
				u.fire_next += u.interval
				_fire_tick(u, now)
		if u.rounds != null:
			u.rounds.update(now)
			for k in u.nodes.size():
				var r: Dictionary = u.rounds.pool[k]
				var n: Node3D = u.nodes[k]
				n.visible = r.flying
				if r.flying:
					n.position = host.world_to_scene(u.rounds.position(r, now))
					var d := Vector3(r.u.x, r.u.z, -r.u.y)
					n.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT).scaled(Vector3.ONE * float(u.w.scale))


## The sensor scan (FUN_004af300): hostile units in range with terrain line of sight, score 100 / dist, the
## best 5. The player only within 0.7 R with its radar OFF / STBY. Both modes' classes are kept; the selector
## filters (UNCERTAIN: the original scans one mode). ECM is not built.
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
		if e.player and host.weapons != null and host.weapons.radar.mode <= 1:
			r *= QUIET_FACTOR
		if d > r or not line_of_sight(me, p):
			continue
		list.append({"ent": e, "score": 100.0 / maxf(d, 1.0)})
	list.sort_custom(func(a, b): return a.score > b.score)
	u.contacts = list.slice(0, SLOTS)


func line_of_sight(a: Vector3, b: Vector3) -> bool:
	a.z += LOS_RAISE
	b.z += LOS_RAISE
	var d := b - a
	var n := int(d.length() / 100.0)
	for i in range(1, n):
		var p := a + d * (float(i) / n)
		var g = host.mission_ground(p)
		if g != null and p.z < float(g):
			return false
	return true


## Brain combat actions for a ground unit (ai_flights.gd combat_hook). Targets: 400 / 440 air mode, 410 ground
## mode, 420 the best of either (selectors not traced: the best-scored contact, UNCERTAIN).
func combat(ent: Dictionary, what: String, target: Dictionary) -> void:
	var u: Unit = units.get(ent.key)
	if u == null:
		return
	match what:
		"400", "440", "410", "420":
			var classes: Array = AIR if what in ["400", "440"] else (GROUND if what == "410" else AIR + GROUND)
			u.brain.target = {}
			for c in u.contacts:
				if c.ent.klass in classes and int(c.ent.state) < 4:
					u.brain.target = c.ent
					break
		"start":
			# FUN_004aa900(0) → FUN_004ac120(1): first shot after _reactionTime, then every _fireReleaseInterval;
			# the target's RWR gets the lock.
			u.fire_next = ai.runtime.now + u.reaction
			if target.get("player", false) and host.weapons != null:
				host.weapons.rwr.lock(ent.key)
		"stop", "safe":
			u.fire_next = INF


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
	if u.rounds != null:
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
## initial value (taken as set until start combat); the script's mode flag (0x852 → FUN_004ab810(…, 2 / 0)) has no
## traced effect.
func script_fire(ent: Dictionary, target: Dictionary) -> void:
	var u: Unit = units.get(ent.key)
	if u == null or target.is_empty() or int(u.ent.state) >= 3:
		return
	_release(u, target, ai.runtime._world_of(target), ai.runtime.now, u.fire_next != INF)


## The release (FUN_004ab810): the global truce (taken even when the shot is skipped next; skipped in SAFE mode), a
## busy pool object, the terrain line of sight, then the round at `aim` or the missile at `t`.
func _release(u: Unit, t: Dictionary, aim: Vector3, now: float, truce: bool) -> void:
	var rt: Node = ai.runtime
	var p: Vector3 = rt._world_of(u.ent)
	var tp: Vector3 = rt._world_of(t)
	var dist := tp.distance_to(p)
	var h := deg_to_rad(float(u.ent.heading))
	var nose := Vector3(sin(h), cos(h), 0)
	if truce:
		if now < _truce_until:
			return  # "Entities in truce"
		_truce_until = now + TRUCE_MIN + randf() * TRUCE_RAND
	if u.rounds == null and (not int(u.w.type) in HOMING or host.weapons == null):
		return
	var busy: bool = u.missile != null and u.missile in host.weapons.missiles if u.rounds == null else not u.rounds.next_free()
	if busy or not line_of_sight(p, tp):
		return
	if u.rounds != null:
		var muzzle := p + Vector3(0, 0, LOS_RAISE)
		u.rounds.fire(now, muzzle, muzzle, Vector3.ZERO, aim, "", u.ent.key, Settings.easy_aiming, [t.key])
		if host.get("sounds") != null:
			var s = host.sounds.play("SFX_ENTITY_FIRED_WEAPON", "OST_GUNBULLET")
			if s is Node3D and is_instance_valid(s):
				s.top_level = true
				s.global_position = host.world_to_scene(muzzle)
		return
	# The launch attitude: SAM launchers (types 290–340) turn to the target (heading and pitch), others keep their
	# heading level.
	var tc := int(u.ent.type_code)
	if tc >= 290 and tc <= 340 and dist > 0.0:
		nose = (tp - p) / dist
	var right := nose.cross(Vector3(0, 0, 1))
	right = right.normalized() if right.length() > 1e-4 else Vector3(1, 0, 0)
	var up := right.cross(nose)
	var at := p + right * LAUNCH_OFFSET.x + nose * LAUNCH_OFFSET.y + up * LAUNCH_OFFSET.z
	u.missile = host.weapons.launch_homing(u.w, at, {"vel": Vector3.ZERO, "fwd": nose, "up": up, "right": right}, String(t.key), 1.0, u.ent)


func _velocity_of(ent: Dictionary) -> Vector3:
	if ent.player and host.flight != null:
		var v: Vector3 = host.flight.state().velocity
		return Vector3(v.x, -v.z, v.y)
	return ent.vel


## FUN_004d6130 for a ground round: a sphere hit blasts the target, the end of flight (an air burst) or a
## ground hit every unit around. The look as the player's: a gun round's impact on a hit or the ground, a rocket's
## burst always.
func _detonate(_r: Dictionary, pos: Vector3, cands, hit: Dictionary, u: Unit) -> void:
	var rocket := int(u.w.type) == 560
	ai.runtime.area_damage(pos, float(u.w.power), float(u.w.radius), u.ent, "rocket" if rocket else "gun", cands)
	if host.weapons == null:
		return
	if rocket:
		host.weapons.rocket_effect(pos)
	elif not hit.is_empty():
		host.weapons.gun_hit_effect(hit.pos if hit.has("pos") else pos)
