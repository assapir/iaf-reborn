# The player's weapons (docs/weapons.md): the weapon system of the player controller (ctl+0xf0) with
# its stores (ctl+0xfc), the master modes and HUD modes, the weapon keys, the gun (trigger, 0.2 s shot
# timer, rounds, muzzle flash, sounds), the IR seeker and missiles, the stores drawn on the pylons and
# the stores weight / drag the flight model carries. Owned by the flight scene (terrain_view.gd, the
# `host`), which calls update() every frame and command() / release() for the key commands.
# Generic for every aircraft: stations from the descriptor, loadout from the mission / bdb.
extends Node

const WeaponDb := preload("res://weapons/weapon_db.gd")
const Stores := preload("res://weapons/stores.gd")
const GunRounds := preload("res://weapons/gun_rounds.gd")
const IrSeeker := preload("res://weapons/ir_seeker.gd")
const IrMissile := preload("res://weapons/ir_missile.gd")
const Radar := preload("res://weapons/radar.gd")
const Rwr := preload("res://weapons/rwr.gd")
const DamageEffects := preload("res://mission/damage_effects.gd")

## The gun's shot timer period (DAT_0082f4e8 = 0.2 s, sim time).
const GUN_PERIOD := 0.2
## Stores are drawn within 9000 m of the camera (0x638a08).
const STORES_DRAW_DIST := 9000.0
## Launch q without Easy aiming (v1.1: ×0.8, 0x600f64) and the q of an unlocked target (0x82f6ec).
const Q_NO_EASY := 0.8
const Q_UNLOCKED := 0.1
## Player's systems damage flags (docs/damage.md §5): 13 gun, 20 / 21 weapon systems.
const DMG_GUN := 13
const DMG_WEAPONS := [20, 21]
## Light 9 of the panel = the gear handle (FUN_0045b3c0(9)).

var host: Node
var db: RefCounted
var stores: RefCounted
var gun: RefCounted
var seeker: RefCounted
## The radar (ctl+0x84, docs/radar.md).
var radar: RefCounted
## The RWR (ctl+0x5b0, docs/rwr.md).
var rwr: RefCounted
## Physics "fix_lock_threat" (ours): a radar lock makes the player the AI target's threat (brain+0x7c).
var lock_threat_fix := false
var missiles: Array = []  # IrMissile with .node, .sound
var now := 0.0

## ctl+0x78 master mode, +0x80 the previous one, +0x7c the M key cycle, +0x5c the HUD mode.
var master := 0
var master_prev := 0
var m_cycle := 0
var hud_mode := 0
## ctl+0x970: Safety off (the cheat; firing with the gear handle down).
var safety_off := false
## W+0xac release in progress (Space held), W+0xb0 gun firing (also the muzzle flash).
var releasing := false
var firing := false
var _gun_next := INF
var _gun_sound: Node
var _seek_sound: Node
var _lock_sound: Node
## The jet's bdb type code and the stores / gun attach points (descriptor, glTF metres).
var jet_type := 100
var descriptor := {}
var easy_aiming := false

## Visuals.
var _round_nodes: Array = []
## The round model's Present-record scale (gunsh: ×2), as every mission model.
var _round_scale := 1.0
var _flash: Node3D
var _store_nodes := {}  # station -> [Node3D per slot]
var _models := {}  # model path -> util/gltf.gd open() result or null
## The AA gun LCOS pipper (FUN_0045f410) state.
var lcos := {"x": 0.0, "y": 0.0, "w28": 0.0, "w2c": 0.0, "prev0": 0.0, "prev2": 0.0, "next": 0.0}


## Sets up the stores of the player's jet: `entity` = its mission entity ({} in free flight),
## `object` = its bdb object, `bdb` = the object database.
func setup(host_node: Node, entity: Dictionary, object: Dictionary, bdb: Dictionary, desc: Dictionary) -> void:
	host = host_node
	descriptor = desc
	jet_type = int(object.get("0x5b4", 100))
	db = WeaponDb.create(bdb, Settings.real_weapons())
	stores = Stores.new()
	stores.player = true
	stores.weight_fix = bool(Settings.better.get("fix_stores_weight", false))
	stores.unlimited = Settings.unlimited_ammo
	stores.setup(_arm(Stores.loadout(entity, object), entity), db, desc, _pilon_of, jet_type)
	easy_aiming = Settings.easy_aiming
	gun = GunRounds.new()
	var gm: Dictionary = db.motion_for(Stores.GUN, 0).duplicate()
	var gw: Dictionary = stores.station(9).get("w", {})
	gm.merge(gw.get("motion", {}), true)
	gun.configure(gm)
	gun.units = _units
	gun.ground = _ground
	gun.detonate = _gun_detonate
	seeker = IrSeeker.new()
	seeker.tone = _tone
	radar = Radar.new()
	radar.units = _units
	radar.ground = _ground
	radar.own = own
	radar.on_lock = _radar_lock
	radar.setup(jet_type, preload("res://weapons/real_weapons.gd").radar_nm(jet_type) if Settings.real_weapons() else 0.0)
	rwr = Rwr.new()
	rwr.unit = _rwr_unit
	rwr.own = own
	rwr.now = func(): return now
	rwr.compact = Settings.real_data()
	rwr.betty = jet_type in preload("res://audio/flight_sounds.gd").BETTY_TYPES
	if host.get("sounds") != null:
		rwr.play = host.sounds.play
		rwr.stop = host.sounds.stop
	_push_stores()
	# The tanks' fuel (FUN_005a8980 before the start fills the fuel to FuelWeight + tanks).
	if host.flight != null:
		host.flight.set_fuel_capacity(stores.tank_fuel)
	_build_visuals()


## The Arming screen's pylon loads of the player's flight replace pylons 0..8 (FUN_004f00f0 ->
## FUN_004f0140 writes them to the flight's aircraft; docs/front-end.md §15). Only for the mission's
## own jet (`entity` set): a jet flown in place of another keeps its type's load.
func _arm(load: Array, entity: Dictionary) -> Array:
	var n = host.get("player_flight_number") if host != null else null
	if entity.is_empty() or n == null or not Settings.arm_loadouts.has(int(n)):
		return load
	var arm: Array = Settings.arm_loadouts[int(n)]
	for i in mini(9, arm.size()):
		load[i] = [int(arm[i][0]), int(arm[i][1])]
	return load


## The flight model carries the stores (S+0x424, S+0x42c, S+0x428).
func _push_stores() -> void:
	if host != null and host.flight != null:
		host.flight.set_stores(stores.fm_mass, stores.fm_di_left, stores.fm_di_right)


# --- world <-> scene --------------------------------------------------------------------------------

func _origin() -> Vector2:
	return host.terrain.world_origin


func to_scene(w: Vector3) -> Vector3:
	var o := _origin()
	return Vector3(w.x - o.x, w.z, -(w.y - o.y))


func to_world(p: Vector3) -> Vector3:
	var o := _origin()
	return Vector3(o.x + p.x, o.y - p.z, p.y)


static func dir_world(d: Vector3) -> Vector3:
	return Vector3(d.x, -d.z, d.y)


## The own jet in the world frame: {pos, vel, fwd, up, right, yaw}.
func own() -> Dictionary:
	var b: Basis = host.rig.global_basis
	var vel := Vector3.ZERO
	if host.flight != null:
		vel = dir_world(host.flight.state().velocity)
	var fwd := dir_world(-b.z)
	return {"pos": to_world(host.rig.global_position), "vel": vel, "fwd": fwd, "up": dir_world(b.y),
		"right": dir_world(b.x), "yaw": atan2(fwd.x, fwd.y)}


## A body point of the jet (descriptor glTF metres) in the world.
func body_to_world(p: Vector3) -> Vector3:
	return to_world(host.rig.global_transform * p)


## The mission's units the weapons see: every placed unit with a model other than the player, not
## exploded (UNCERTAIN: the original's spatial query also holds objects without a model, e.g.
## sensors). {key, pos (world), vel, afterburner, ent}. AI jets have no afterburner state yet.
func _units() -> Array:
	var out := []
	var rt = host.runtime
	if rt == null:
		return out
	for ent in rt.entities.values():
		if ent.player or ent.node == null or not ent.visible or ent.state == 5:
			continue
		out.append({"key": ent.key, "pos": rt._world_of(ent), "vel": ent.vel, "afterburner": false, "ent": ent,
			"hostile": rt._enemy_of_player(ent)})
	return out


func _ground(w: Vector3) -> Variant:
	return host.mission_ground(w)


func _me() -> Dictionary:
	return host.runtime.player_entity() if host.runtime != null else {}


# --- master and HUD modes (FUN_0044ec80, FUN_00449810, FUN_0044a220) ---------------------------------

static func is_aa_missile(type: int) -> bool:
	return type in [570, 580, 600, 610]


## FUN_0044ec80: the master mode and HUD mode of the selected store; `aa_key` = reached by ']'.
func _master_from_type(aa_key: bool) -> void:
	var t: int = stores.current_type()
	var m := -1
	var h := -1
	match t:
		500, 510, 560:
			m = 1; h = 5
		565:
			m = 3 if aa_key else 2
			h = 3 if aa_key else 4
		570, 580:
			m = 4; h = 1
		600, 610:
			m = 4; h = 2
		590:
			m = 4; h = 8
		650:
			m = 5; h = 5  # 6 with a FLIR pod (not built)
		635, 640:
			m = 6; h = 7
	if m < 0:
		return  # type 660 / nothing: the mode stays
	if m != master:
		master_prev = master
	master = m
	_set_hud_mode(h)


func _set_hud_mode(h: int) -> void:
	if hud_mode == 1 and h != 1:
		seeker.exit()
	var entering_ir := h == 1 and hud_mode != 1
	hud_mode = h
	if entering_ir:
		seeker.set_weapon(stores.station(stores.cur).get("w", {}))
		# FUN_00461b00: the seek tone starts only when the store is empty (the next update stops it).
		if stores.total(stores.current_type(), stores.current_name()) == 0:
			_tone("seek")


## FUN_00449810: the MFD page of the master mode (NAV 0; bombs / AG gun stores; AA gun radar; the
## IR missiles leave the pages; radar missiles radar).
func _mfd_page() -> void:
	var page := -1
	match master:
		0: page = 0
		1, 2: page = 1
		3: page = 2
		4:
			match stores.current_type():
				600, 610: page = 2
				590: page = 10
		5: page = 1
		6: page = 5
	# Placed like event 0x5a (FUN_00449f90 / FUN_00449f20; UNCERTAIN: same rule).
	if page >= 0 and host.cockpit != null:
		host.cockpit.show_mfd_page(page)


## ']' (event 0x3e): next AA store unless an AA missile is already selected in NAV.
func select_aa() -> void:
	var t: int = stores.current_type()
	var a := is_aa_missile(t)
	if t == Stores.GUN and master_prev == 2:
		a = false
	if master != 0 or not a or t == Stores.SHELL:
		_next(1)
	_master_from_type(true)
	_mfd_page()


## '[' (event 0x3c): next AG store unless a non-AA store is already selected in NAV.
func select_ag() -> void:
	var t: int = stores.current_type()
	var a := not is_aa_missile(t)
	if t != 0 and master_prev == 3:
		a = false
	if master != 0 or not a or t == Stores.SHELL:
		_next(2)
	_master_from_type(false)
	_mfd_page()


## FUN_00454210 / FUN_00454240: not while releasing or firing.
func _next(kind: int) -> void:
	if releasing or firing:
		return
	stores.cycle(kind, true)


## M (event 0x63): NAV -> AA -> AG -> NAV; blocked while releasing.
func master_key() -> void:
	if releasing:
		return
	m_cycle = (m_cycle + 1) % 3
	match m_cycle:
		1:
			select_aa()
		2:
			select_ag()
		0:
			master_prev = master
			master = 0
			_set_hud_mode(0)
			_mfd_page()
	host.sounds.play("SFX_BUTTON")


## N (event 0x62, p = 0): the master mode p (NAV).
func nav_key(p: int) -> void:
	master_prev = master
	master = p
	if p == 0:
		_set_hud_mode(0)
	_mfd_page()


## MFD stores page station button (event 0x4c): select that station.
func select_station(i: int) -> void:
	if stores.select_station(i):
		_master_from_type(Stores.category(stores.current_type()) == 1)
		_mfd_page()
		host.sounds.play("SFX_BUTTON")


# --- release (Space) --------------------------------------------------------------------------------

func _flag(i: int) -> bool:
	var f: Array = host.player_damage.flags
	return i < f.size() and bool(f[i])


func _weapons_down() -> bool:
	return DMG_WEAPONS.any(func(i): return _flag(i))


## Space (event 0x40): HUD mode 1..8; the gear handle down only with Safety off and the gun; not
## with weapon systems damage (flag 20).
func fire_selected() -> void:
	if hud_mode < 1 or hud_mode > 8:
		return
	if host.gear_down and not (safety_off and stores.current_type() == Stores.GUN):
		return
	if _flag(20):
		return
	# FUN_00454270
	if _weapons_down() or releasing or stores.total(stores.current_type(), stores.current_name()) == 0:
		return
	releasing = true
	match stores.current_type():
		Stores.GUN:
			gun_trigger()
		570, 580:
			_release_missile()


## Space up (event 0x41, FUN_00456100).
func release_selected() -> void:
	releasing = false
	if stores.current_type() == Stores.GUN:
		gun_stop()


# --- jettison (Shift+C, event 0x48) ----------------------------------------------------------------

## W+0xb8 tanks jettisoned, W+0xbc bombs jettisoned.
var tanks_jettisoned := false
var bombs_jettisoned := false


## Event 0x48: nothing with the gear handle down; the first press drops the tanks (FUN_00458760), the
## next ones the bombs (FUN_00458d10: not built yet, no bombs).
func jettison() -> void:
	if host.gear_down:
		return
	if tanks_jettisoned:
		return  # bombs jettison: with the bombs (docs/weapons.md)
	_jettison_tanks()


## FUN_00458760: every pylon whose store name contains "LB" releases one store (count −1 even with
## Unlimited ammo, drag updated, no weight update); then, when the fuel is at or above FuelWeight, the
## fuel and its maximum become FuelWeight (motion 0x18): the tanks' remaining fuel is gone.
func _jettison_tanks() -> void:
	var was: bool = stores.unlimited
	stores.set_unlimited(false)
	for i in 9:
		if stores.stations.has(i) and "LB" in stores.name_of(i) and stores.displayed(i) > 0:
			stores.jettisoned(i)
	stores.set_unlimited(was)
	if host.flight != null:
		var st: Dictionary = host.flight.state()
		if float(st.fuel_lbs) >= float(st.internal_fuel_kg) * 2.2046:
			host.flight.set_fuel(float(st.internal_fuel_kg))
	tanks_jettisoned = true
	_push_stores()
	_update_store_nodes()


# --- the gun ----------------------------------------------------------------------------------------

## Tab (event 0x42): the gear handle down needs Safety off.
func gun_key() -> void:
	if host.gear_down and not safety_off:
		return
	gun_trigger()


## FUN_004579f0: the first round at once, then the 0.2 s timer and the gun sound loop.
func gun_trigger() -> bool:
	if _weapons_down() or _flag(DMG_GUN) or firing:
		return false
	firing = true
	if stores.station(9).is_empty():
		return false
	if not _gun_shot():
		return false  # quirk: firing stays set without a timer until the release
	_gun_next = now + GUN_PERIOD
	if _gun_sound == null:
		var code := "SFX_AIRCRAFT_FIRED_WEAPON" if "20 MM" in stores.name_of(9) else "SFX_ENTITY_FIRED_WEAPON"
		_gun_sound = host.sounds.play(code, "OST_GUNBULLET")
		_place_sound(_gun_sound, body_to_world(_gun_offset()))
	return true


## FUN_00457b40.
func gun_stop() -> void:
	_gun_next = INF
	if _gun_sound != null:
		host.sounds.stop(_gun_sound)
		_gun_sound = null
	firing = false


## FUN_00456d40: one round (out of rounds: the gun stops, silently).
func _gun_shot() -> bool:
	if stores.displayed(9) == 0:
		gun_stop()
		return false
	if gun.next_round().is_empty():
		return false
	var o := own()
	var d: Vector3 = GunRounds.shot_dir(o.fwd, o.up)
	var a: Vector3 = gun.aim_point(o.pos, o.vel, d, hud_mode == 4)
	var me := _me()
	gun.fire(now, o.pos, body_to_world(_gun_offset()), o.vel, a, String(radar.locked().get("key", "")), String(me.get("key", "")), easy_aiming)
	stores.consume(9)
	return true


func _gun_offset() -> Vector3:
	var g = descriptor.get("stations", {}).get("StationGun", descriptor.get("gun"))
	var k: float = host.aircraft.scale.x if host.aircraft != null else 1.0  # the model's Present scale
	return Vector3(g[0], g[1], g[2]) * k if g is Array else Vector3.ZERO


## FUN_004d6130 for a round: a sphere hit blasts the round's candidate list, a ground / end-of-flight
## detonation every unit around; the impact effect (small fireball, SFX_WEAPON_EXPLODED/OST_GUNBULLET)
## only on a hit (at the unit) or on the ground.
func _gun_detonate(_r: Dictionary, pos: Vector3, cands, hit: Dictionary) -> void:
	var w: Dictionary = stores.station(9).get("w", {"power": 100.0, "radius": 50.0})
	var me := _me()
	if host.runtime != null and not me.is_empty():
		host.runtime.area_damage(pos, float(w.power), float(w.radius), me, "gun", cands)
	if hit.is_empty():
		return
	var at: Vector3 = hit.pos if hit.has("pos") else pos
	var sp := to_scene(at)
	var water := false
	if host.terrain.has_method("surface_at"):
		water = (host.terrain.surface_at(sp) & host.terrain.SURFACE_WATER) != 0
	var g = host.terrain.height_at(sp)
	if water and (g == null or sp.y < g + 10.5):
		host.effects.smoke_puff(sp, true)  # splash (look UNCERTAIN)
		_place_sound(host.sounds.play("SFX_SPLASH"), at)
		return
	host.effects.explosion(sp, DamageEffects.F_SMALL_FIRE, 1.5, 1.2, g if g != null else sp.y)
	_place_sound(host.sounds.play("SFX_WEAPON_EXPLODED", "OST_GUNBULLET"), at)


# --- IR missiles ------------------------------------------------------------------------------------

## FUN_004545e0 -> FUN_00454b70 (570 / 580): HUD mode 1, 2 or 8; the target and q of FUN_00457f70.
func _release_missile() -> void:
	if not hud_mode in [1, 2, 8]:
		return
	var i: int = stores.fire_station()
	if i < 0 or stores.displayed(i) <= 0:
		return
	var st: Dictionary = stores.station(i)
	var w: Dictionary = st.w
	var o := own()
	var units := _units()
	var q := 1.0
	var target := {}
	if not easy_aiming:
		target = seeker.target_in_circle(o, units)
		if not target.is_empty():
			q = (1.0 if seeker.lock else Q_UNLOCKED) * Q_NO_EASY
	else:
		target = seeker.current(units)
	if not target.is_empty():
		q = maxf(q, 0.1)
	# Release point: the store's slot (the last drawn) or the pylon, through the attitude.
	var slots: Array = st.slots
	var n := int(st.count)
	var at: Vector3 = slots[n - 1] if n >= 1 and n <= slots.size() else st.attach
	var m: Dictionary = db.motion_for(int(w.type), int(w.generation)).duplicate()
	m.merge(w.get("motion", {}), true)
	var mis := IrMissile.new()
	var fe := Vector3(m.get("_fireEndVecX", 0.0), m.get("_fireEndVecY", 10000.0), m.get("_fireEndVecZ", 0.0))
	# _fireEndVec in body axes (x right, y forward, z up).
	var point: Vector3 = o.pos + o.right * fe.x + o.fwd * fe.y + o.up * fe.z
	mis.launch(w, m, now, body_to_world(at), o.vel, o.fwd, String(target.get("key", "")), point, q, db.debug_param)
	missiles.append(mis)
	_missile_visual(mis)
	var ost := "OST_HEATMISSILE" if int(w.type) == 570 else "OST_LIMITEDHEATMISSILE"
	_place_sound(host.sounds.play("SFX_AIRCRAFT_FIRED_WEAPON", ost), mis.p0)
	stores.fired(i)
	_push_stores()
	_update_store_nodes()


func _missile_visual(mis: RefCounted) -> void:
	var node := _instance(String(mis.weapon.get("model_path", "")))
	if node != null:
		host.add_child(node)
		node.position = to_scene(mis.p0)
	mis.set_meta("node", node)
	# Flight loop (UNCERTAIN: code 0x8337e4, probably SFX_OBJECT_SPECIFIC / OST_HEATMISSILE).
	var ost := "OST_HEATMISSILE" if int(mis.weapon.type) == 570 else "OST_LIMITEDHEATMISSILE"
	var s = host.sounds.play("SFX_OBJECT_SPECIFIC", ost)
	mis.set_meta("sound", s)


func _update_missiles() -> void:
	var units := {}
	for u in _units():
		units[u.key] = u
	for mis in missiles.duplicate():
		var gone := false
		while not gone and mis.next_update <= now:
			var t: Dictionary = units.get(mis.target_key, {})
			var tp: Vector3 = t.get("pos", mis.last_pos)
			if mis.has_target and t.is_empty():
				tp = Vector3.ZERO  # target gone: FUN_0045a180's static default (UNCERTAIN: origin)
			gone = mis.update(mis.next_update, tp, t.get("vel", Vector3.ZERO), _ground)
		var node: Node3D = mis.get_meta("node")
		var p: Vector3 = mis.last_pos if gone else mis.position(now)
		var v: Vector3 = mis.velocity(now)
		if node != null:
			node.position = to_scene(p)
			var dv := Vector3(v.x, v.z, -v.y)
			if dv.length() > 1.0:
				node.basis = Basis.looking_at(dv.normalized(), Vector3.UP if absf(dv.normalized().y) < 0.99 else Vector3.RIGHT)
		_place_sound(mis.get_meta("sound"), p)
		if gone:
			_missile_detonate(mis)


## FUN_004d6130 for a player's missile: every unit around (the blast decides), explosion and sound
## (UNCERTAIN look: a fireball of the weapon explosion), the flight loop stops.
func _missile_detonate(mis: RefCounted) -> void:
	missiles.erase(mis)
	var p: Vector3 = mis.last_pos
	var me := _me()
	var hit := []
	if host.runtime != null and not me.is_empty():
		hit = host.runtime.area_damage(p, float(mis.weapon.power), float(mis.weapon.radius), me, "missile")
	var sp := to_scene(p)
	var g = host.terrain.height_at(sp)
	host.effects.explosion(sp, DamageEffects.F_FIREBALL | DamageEffects.F_PUFF, 1.0, 5.0, g if g != null else sp.y)
	var ost := "OST_HEATMISSILE" if int(mis.weapon.type) == 570 else "OST_LIMITEDHEATMISSILE"
	_place_sound(host.sounds.play("SFX_WEAPON_EXPLODED", ost), p)
	if not hit.is_empty():
		_place_sound(host.sounds.play("SFX_WEAPON_HIT_TARGET"), p)
	var node: Node3D = mis.get_meta("node")
	if node != null:
		node.queue_free()
	if mis.get_meta("sound") != null:
		host.sounds.stop(mis.get_meta("sound"))


func _tone(kind: String) -> void:
	for pair in [["seek", "_seek_sound", "SFX_IR_SEEK"], ["lock", "_lock_sound", "SFX_IR_LOCK"]]:
		var cur = get(pair[1])
		if kind == pair[0]:
			if cur == null:
				set(pair[1], host.sounds.play(pair[2]))
		elif cur != null:
			host.sounds.stop(cur)
			set(pair[1], null)


# --- radar (docs/radar.md) ---------------------------------------------------------------------------

## Radar key events (FUN_0044a240): 0x21 / 0x22 range, 0x24 Q modes, 0x2b R A-A / A-G, 0x2c S standby,
## 0x2d / 0x2e boresight down / up, 0x26 / 0x27 next / previous target, 0x31 deselect, 0x2a lock (key).
func radar_event(ev: int, arg = null) -> void:
	match ev:
		0x21: radar.step_range(1, now)
		0x22: radar.step_range(-1, now)
		0x24: radar.cycle_mode(now)
		0x2b: radar.toggle_aa_ag(now)
		0x2c: radar.standby()
		0x2d: radar.boresight(true)
		0x2e: radar.boresight(false)
		0x26: radar.next_target(true, now)
		0x27: radar.next_target(false, now)
		0x31: radar.deselect(now)
		0x2a: radar.lock_key(String(arg))
		0x2f:
			var g = _ground(Vector3(arg.x, arg.y, 0.0))
			radar.designate(arg.x, arg.y, float(g) if g != null else 0.0, now)
		0x30: radar.toggle_exp()


## On-lock / on-unlock (FUN_004b0510 / FUN_004b04d0): a target with a controller hears it on its RWR;
## an AI aircraft (no controller) gets brain+0x7c = the target itself when free (original bug: not the
## radar's owner, so its "my target is my threat" condition 38 never holds) and loses it on the unlock
## (docs/rwr.md §2). Physics "fix_lock_threat" (ours): brain+0x7c = the player, the radar's owner.
func _radar_lock(key: String, on: bool) -> void:
	var ent: Dictionary = host.runtime.entities.get(key, {}) if host.runtime != null else {}
	var p = ent.get("pilot")
	if p == null or p.get("brain") == null:
		return
	var who: Dictionary = ent
	if lock_threat_fix and host.runtime.has_method("player_entity"):
		who = host.runtime.player_entity()
	if on:
		if p.brain.attacker.is_empty():
			p.brain.attacker = who
	elif is_same(p.brain.attacker, who):
		p.brain.attacker = {}


## An emitter for the RWR: {pos, klass, type, state} of a mission unit, {} when gone.
func _rwr_unit(key: String) -> Dictionary:
	var rt = host.runtime if host != null else null
	if rt == null or not rt.entities.has(key):
		return {}
	var ent: Dictionary = rt.entities[key]
	return {"pos": rt._world_of(ent), "klass": int(ent.get("klass", -1)), "type": int(ent.get("type_code", 0)),
		"state": int(ent.get("state", 1))}


## The cockpit's radar snapshot (FUN_00445f10 → state+0x640.., +0xa00..): mode, range index (1..6),
## scope width, heading shift, antenna carets, the contacts and the lock.
func radar_snapshot() -> Dictionary:
	var lk: Dictionary = radar.locked()
	var o := own()
	var closure := 0.0
	if not lk.is_empty():
		var d: Vector3 = (lk.pos - o.pos).normalized()
		closure = (o.vel - (lk.unit.vel as Vector3)).dot(d)
	return {"mode": radar.mode, "idx": radar.range_index(), "width": radar.scope_width(),
		"shift": radar.heading_shift, "antenna": radar.antenna, "contacts": radar.contacts,
		"lock": lk, "closure": closure, "has_lock": not lk.is_empty(),
		"exp": radar.exp, "designated": radar.designated}


# --- chaff and flares (events 0x44 / 0x45, docs/weapons.md §10) ------------------------------------

## A decoy lives 4.0 s after its release (FUN_004d7690: the end time of types 0x21c / 0x226 is capped
## at 4.0, _DAT_00605120); its pool object is busy until then.
const DECOY_LIFE := 4.0
## Decoys in the air: {type, r (round record of the decoy motion), end, node}.
var decoys: Array = []
## Per type: the fixed-weapon motion (gun_rounds.gd configured with weapons.ibx 540 / 550) and the
## ring pool of `_maxNumInAir` (15) end times.
var _decoy_motion := {}
var _decoy_pool := {}
var _decoy_next := {}


## Insert / Delete (events 0x44 chaff / 0x45 flare, FUN_0044a240): refused with the gear handle down
## (no Safety override) or weapon systems damage (flag 20); then one decoy (FUN_004545e0(0x21c / 0x226,
## 0, 0)). No repeat, no program, no busy timer: only the pool limits the rate.
func dispense(type: int) -> bool:
	if host.gear_down or _flag(20):
		return false
	var i := 10 if type == Stores.CHAFF else 11
	if not stores.stations.has(i) or stores.displayed(i) == 0:
		return false  # no message, no sound
	var st: Dictionary = stores.station(i)
	var w: Dictionary = st.w
	if not _decoy_motion.has(type):
		var m: Dictionary = db.motion_for(type, 0).duplicate()
		m.merge(w.get("motion", {}), true)
		var g := GunRounds.new()
		g.configure(m)
		_decoy_motion[type] = g
		_decoy_pool[type] = []
		for k in maxi(int(m.get("_maxNumInAir", 15)), 1):
			_decoy_pool[type].append(-INF)
		_decoy_next[type] = 0
	var g: RefCounted = _decoy_motion[type]
	var k: int = _decoy_next[type]
	if now < float(_decoy_pool[type][k]):
		return false  # that pool object is still alive (w+0x48)
	_decoy_next[type] = (k + 1) % _decoy_pool[type].size()
	_decoy_pool[type][k] = now + DECOY_LIFE
	# Release point: the station (StationCha / StationFla) through the attitude; aim point: the
	# _fireEndVec in body axes (0, -200, -10: 200 m aft, 10 m below; composition UNCERTAIN).
	var o := own()
	var p0 := body_to_world(st.attach)
	var m2: Dictionary = db.motion_for(type, 0)
	var fe := Vector3(m2.get("_fireEndVecX", 0.0), m2.get("_fireEndVecY", -200.0), m2.get("_fireEndVecZ", -10.0))
	var a: Vector3 = p0 + o.right * fe.x + o.fwd * fe.y + o.up * fe.z
	# The fixed-weapon flight (FUN_005605c0 -> FUN_0047a1e2, as a gun round): |V| + velocityJump along
	# the line to A, decelerating at 50 m/s², then at A. No hit sphere (_spiralAccel 0): no damage.
	var s: float = o.vel.length() + g.velocity_jump
	var d := a - p0
	var dist := d.length()
	var r := {"p0": p0, "u": d / dist if dist > 0.0 else -o.fwd, "s": s, "t0": now, "A": a,
		"t_end": now + g._flight_time(s, dist)}
	var node := _decoy_visual(type)
	decoys.append({"type": type, "r": r, "end": now + DECOY_LIFE, "node": node})
	stores.consume(i)
	var ost := "OST_CHAFF" if type == Stores.CHAFF else "OST_FLARE"
	_place_sound(host.sounds.play("SFX_AIRCRAFT_FIRED_WEAPON", ost), p0)
	_decoy_effect(type)
	return true


## The decoy rule (FUN_00454b70, cases 0x21c / 0x226) acts on the missiles launched at the jet (its
## RWR missile list): none exist until the enemies fire (docs/weapons.md §10).
func _decoy_effect(_type: int) -> void:
	pass


## The decoy's look is UNCERTAIN (bdb model 0): ours draws a flare as a small bright glow, chaff
## not at all.
func _decoy_visual(type: int) -> Node3D:
	if type != Stores.FLARE:
		return null
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3, 3)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	return mi


func _update_decoys() -> void:
	for dc in decoys.duplicate():
		var node: Node3D = dc.node
		if now >= dc.end:
			decoys.erase(dc)
			if node != null:
				node.queue_free()
			continue
		if node != null:
			node.position = to_scene(decoy_position(dc))


## A decoy's world position now (at A after its flight; UNCERTAIN what it does until the 4 s end).
func decoy_position(dc: Dictionary) -> Vector3:
	return _decoy_motion[dc.type].position(dc.r, now)


# --- every frame ------------------------------------------------------------------------------------

## Advances the weapons to sim time `t`.
func update(t: float) -> void:
	now = t
	while firing and _gun_next <= now:
		_gun_shot()  # catch-up shots share the timestamp
		_gun_next += GUN_PERIOD
	gun.update(now)
	_update_missiles()
	_update_decoys()
	radar.update(now)
	rwr.damaged = _flag(14)
	rwr.update(now)
	# FUN_00461680: an A-A radar lock slaves the IR seeker (any lock clears the seeker's own target).
	seeker.radar_key = String(radar.locked().get("key", ""))
	seeker.radar_aa = radar.aa
	if hud_mode == 1:
		var st: Dictionary = stores.station(stores.cur)
		seeker.update(now, own(), _units(), int(st.get("w", {}).get("type", 0)), stores.total(stores.current_type(), stores.current_name()) > 0)
	if hud_mode == 3:
		_lcos(now)
	else:
		lcos.fresh = true
	_update_visuals()
	_publish()


## The AA gun LCOS pipper (FUN_0045f3b0 -> FUN_0045f410, feet): every 0.05 s, integrated with dt 0.15
## (quirk kept). Without a radar lock the range is 450 m.
func _lcos(t: float) -> void:
	if t < lcos.next:
		return
	lcos.next = t + 0.05
	var st: Dictionary = host.flight.state() if host.flight != null else {}
	if st.is_empty():
		return
	const DT := 0.15
	if lcos.get("fresh", true):
		# Ours: the rate filters start from the current attitude (the original's first values are
		# untraced; from 0 the first heading step would throw the pipper off for ~1 s).
		lcos.prev0 = deg_to_rad(float(st.pitch)) / PI
		lcos.prev2 = deg_to_rad(float(st.heading)) / PI
		lcos.fresh = false
	var a0 := deg_to_rad(float(st.pitch))
	var a1 := deg_to_rad(float(st.roll))
	var a2 := deg_to_rad(float(st.heading))
	var v := float(st.velocity.length()) * 3.2808
	var g0 := float(st.g)
	var alpha := float(st.alpha)
	# R (ft): the locked range ×3.28084 (0x601478), else 1476.378; at most 3148.8.
	var lk: Dictionary = radar.locked()
	var r := minf(float(lk.dist) * 3.28084 if not lk.is_empty() else 1476.378, 3148.8)
	var e0: float = a0 / PI - lcos.prev0
	lcos.prev0 = a0 / PI
	var e2: float = a2 / PI - lcos.prev2
	lcos.prev2 = a2 / PI
	lcos.w28 += 4.0 * (_int16(e0) / 65536.0 - DT * lcos.w28)
	lcos.w2c += 4.0 * (_int16(e2) / 65536.0 - DT * lcos.w2c)
	var pp: float = PI * (cos(a1) * lcos.w28 + cos(a0) * sin(a1) * lcos.w2c)
	var qq: float = PI * (cos(a0) * cos(a1) * lcos.w2c - sin(a1) * lcos.w28)
	var tf := r / (3300.0 - (v + 1650.0) * r * 0.00024667423)
	var gd := PI * tf * tf * 16.087 / r
	var dd := 0.2 + 1.35 * tf
	var xs: float = gd * cos(a0) * sin(a1) - tf * qq
	var ys: float = tf * pp + (g0 - 1.0) * gd - ((3300.0 * tf - r) * v * alpha / r) / (v + 3300.0) + 5.0617 / r
	lcos.x += DT * (xs - lcos.x) / dd
	lcos.y += DT * (ys - lcos.y) / dd


static func _int16(e: float) -> int:
	var n := int(e * 65536.0)
	return ((n + 32768) & 0xffff) - 32768


## The cockpit snapshot (FUN_00456520 -> FUN_00445bb0) for the HUD and the stores MFD page.
func _publish() -> void:
	var c: Control = host.cockpit
	if c == null:
		return
	var list := []
	for i in 12:
		list.append({"type": stores.type_of(i), "count": stores.displayed(i), "name": stores.name_of(i)})
	var t: int = stores.current_type()
	var mal := _weapons_down() or (_flag(DMG_GUN) and t == Stores.GUN)
	var srm := 0
	var mrm := 0
	for i in 12:
		if stores.type_of(i) in [570, 580]:
			srm += stores.displayed(i)
		elif stores.type_of(i) in [600, 610]:
			mrm += stores.displayed(i)
	var o := own()
	var pip = null
	if hud_mode == 3:
		pip = Vector2(lcos.x, lcos.y) * rad_to_deg(1.0) * 12.0  # px from the gun cross
	elif hud_mode == 4:
		var d: Vector3 = GunRounds.shot_dir(o.fwd, o.up)
		pip = gun.aim_point(o.pos, o.vel, d, true)  # world point, projected by the HUD
	c.radar = radar_snapshot()
	c.rwr = rwr.display()
	c.indicators[Rwr.LAMP_AI] = rwr.lamps[Rwr.LAMP_AI]
	c.indicators[Rwr.LAMP_SAM] = rwr.lamps[Rwr.LAMP_SAM]
	c.weapons = {
		"hud_mode": hud_mode, "master": master, "stations": list, "selected": stores.cur,
		"name": stores.current_name(), "type": t, "total": stores.total(t, stores.current_name()),
		"ready": not mal, "srm": srm, "mrm": mrm, "gun": stores.displayed(9),
		"chaff": stores.displayed(10), "flares": stores.displayed(11),
		"quantity": 1, "interval": 10, "seeker": seeker.symbol, "lock": seeker.lock,
		"have_missiles": stores.total(t, stores.current_name()) > 0, "circle": 5.0,
		"pipper": pip, "pipper_world": hud_mode == 4, "firing": firing,
	}


# --- visuals ----------------------------------------------------------------------------------------

func _instance(path: String) -> Node3D:
	if path == "":
		return null
	if not _models.has(path):
		_models[path] = preload("res://util/gltf.gd").open(Settings.assets_dir().path_join("converted/objects").path_join(path))
	if _models[path] == null:
		return null
	return preload("res://util/gltf.gd").instance(_models[path])


## The store model's `pilon` helper (glTF, the sum of its and its parents' translations), or null.
static func _pilon_of(path: String) -> Variant:
	var d := Settings.load_json(Settings.assets_dir().path_join("converted/objects").path_join(path))
	var nodes: Array = d.get("nodes", [])
	var parent := {}
	for i in nodes.size():
		for c in nodes[i].get("children", []):
			parent[int(c)] = i
	for i in nodes.size():
		if String(nodes[i].get("name", "")).to_lower() == "pilon":
			var p := Vector3.ZERO
			var k := i
			while true:
				var n: Dictionary = nodes[k]
				if n.has("matrix"):
					p += Vector3(n.matrix[12], n.matrix[13], n.matrix[14])
				elif n.has("translation"):
					p += Vector3(n.translation[0], n.translation[1], n.translation[2])
				if not parent.has(k):
					break
				k = parent[k]
			return p
	return null


func _build_visuals() -> void:
	var gunsh := String(stores.station(9).get("w", {}).get("model_path", ""))
	_round_scale = float(stores.station(9).get("w", {}).get("scale", 1.0))
	for i in gun.pool.size():
		var n := _instance(gunsh)
		if n == null:
			break
		n.visible = false
		host.add_child(n)
		_round_nodes.append(n)
	_flash = _muzzle_flash()
	if _flash != null and host.aircraft != null:
		host.aircraft.add_child(_flash)
		_flash.position = _gun_offset() / host.aircraft.scale.x  # local to the (scaled) model
		_flash.visible = false
	for i in stores.stations:
		var st: Dictionary = stores.stations[i]
		if not st.drawn or host.aircraft == null:
			continue
		var nodes := []
		for s in st.slots:
			var n := _instance(String(st.w.model_path))
			if n == null:
				break
			host.aircraft.add_child(n)
			n.position = s
			nodes.append(n)
		_store_nodes[i] = nodes
	_update_store_nodes()


## Stations 0..8 draw `count` stores at slot[0..count−1] (FUN_0053e430) with EXTERNAL STORES on
## and within 9000 m of the camera.
func _update_store_nodes() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var near := cam == null or host.rig == null or cam.global_position.distance_to(host.rig.global_position) < STORES_DRAW_DIST
	for i in _store_nodes:
		var n := int(stores.station(i).get("count", 0))
		for k in _store_nodes[i].size():
			_store_nodes[i][k].visible = Settings.external_stores and near and k < n


## FUN_00411d90: two crossed quads along the gun line, gunFire.tga, 0.85–1.15 long × 0.6 wide
## (s = 1 m: the original's scale UNCERTAIN), redrawn with a new length every frame while firing.
func _muzzle_flash() -> Node3D:
	var path := Settings.assets_dir().path_join("install/resource/3dobjects/gunfire.tga")
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if img != null:
		mat.albedo_texture = ImageTexture.create_from_image(img)
	for k in 2:
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		# The quad's height runs along −z (forward): horizontal (k 1) or turned 90° about z (k 0).
		mi.basis = Basis(Vector3.RIGHT, -PI / 2)
		if k == 0:
			mi.basis = Basis(Vector3.BACK, PI / 2) * mi.basis
		root.add_child(mi)
	return root


func _update_visuals() -> void:
	for k in _round_nodes.size():
		var r: Dictionary = gun.pool[k]
		var n: Node3D = _round_nodes[k]
		n.visible = r.flying
		if r.flying:
			n.position = to_scene(gun.position(r, now))
			var u: Vector3 = r.u
			var du := Vector3(u.x, u.z, -u.y)
			n.basis = Basis.looking_at(du, Vector3.UP if absf(du.y) < 0.99 else Vector3.RIGHT).scaled(Vector3.ONE * _round_scale)
	if _flash != null:
		_flash.visible = firing
		if firing:
			var l := 0.85 + 0.01 * (randi() % 31)
			for mi in _flash.get_children():
				mi.scale = Vector3(1, l, 1)
				mi.position = Vector3(0, 0, -l / 2.0)
	if _gun_sound != null:
		_place_sound(_gun_sound, body_to_world(_gun_offset()))
	_update_store_nodes()


## A 3-D sound at a world point (the sound nodes are not parented to the jet).
func _place_sound(p, w: Vector3) -> void:
	if p is Node3D and is_instance_valid(p):
		p.top_level = true
		p.global_position = to_scene(w)
