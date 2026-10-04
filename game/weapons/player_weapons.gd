# The player's weapons (docs/weapons.md): the weapon system of the player controller (ctl+0xf0) with
# its stores (ctl+0xfc), the master modes and HUD modes, the weapon keys, the gun (trigger, 0.2 s shot
# timer, rounds, muzzle flash, sounds), the IR seeker and missiles, the stores drawn on the pylons and
# the stores weight / drag the flight model carries. Owned by the flight scene (terrain_view.gd, the
# `host`), which calls update() every frame and command() / release() for the key commands.
# Generic for every aircraft: stations from the descriptor, loadout from the mission / bdb.
extends Node

const PlayerAircraft := preload("res://aircraft/player_aircraft.gd")
const WeaponDb := preload("res://weapons/weapon_db.gd")
const Stores := preload("res://weapons/stores.gd")
const GunRounds := preload("res://weapons/gun_rounds.gd")
const IrSeeker := preload("res://weapons/ir_seeker.gd")
const Missile := preload("res://weapons/missile.gd")
const Guided := preload("res://weapons/guided.gd")
const MrmSight := preload("res://weapons/mrm_sight.gd")
const Radar := preload("res://weapons/radar.gd")
const Rwr := preload("res://weapons/rwr.gd")
const EoSensor := preload("res://weapons/eo_sensor.gd")
const HarmSensor := preload("res://weapons/harm_sensor.gd")
const DamageEffects := preload("res://mission/damage_effects.gd")
const Bombs := preload("res://weapons/bombs.gd")
const Views := preload("res://terrain/views.gd")
const Hud := preload("res://cockpit/hud.gd")
const Terrain := preload("res://terrain/terrain.gd")

## The gun's shot timer period (DAT_0082f4e8 = 0.2 s, sim time).
const GUN_PERIOD := 0.2
## Stores are drawn within 9000 m of the camera (0x638a08).
const STORES_DRAW_DIST := 9000.0
## Weapon bays (ours, the F-35I): a bay station's release waits for its doors to open (0.5 s); they stay open
## this long after.
const BAY_HOLD := 2.0
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
## The EO sensor (FLIR pod / TV weapon camera, docs/mfd.md "FLIR (6), TV (5)") and the HARM page's list.
var eo: RefCounted
var harm: RefCounted
## ctl+0x93c: a store named "...FLIR..." on stations 0..8 (FUN_004586b0 at the flight start).
var flir_pod := false
## The EO camera this frame: (az, el), line of sight (world), the EO centre point (FUN_00450480).
var eo_ae := Vector2.ZERO
var eo_dir := Vector3(0, 1, 0)
var eo_centre := Vector3.ZERO
## Pages 5 / 6 put up by the master modes: page -> [mfd, the page it replaced] (ctl+0x930 / +0x934).
var _eo_replaced := {}
## Physics "fix_lock_threat" (ours): a radar lock makes the player the AI target's threat (brain+0x7c).
var lock_threat_fix := false
## Homing weapons in flight, any launcher (missile.gd with metas id, owner, node, sound).
var missiles: Array = []
## Guided weapons in flight (640 TV missiles, 650 laser bombs; guided.gd).
var guided: Array = []
## The TV camera's weapon (mcp+0xc, docs/weapons.md §12): the last TV weapon launched since the camera started
## (cleared by each EO start); while it flies the camera rides it. eo_on_unit = the camera started on a unit
## (mcp+0x10, FUN_0045dde0: only the Maverick, on the radar's target).
var tv_weapon: RefCounted
var eo_on_unit := false
## The EO camera's eye (world) while it rides a launched weapon, else null (the jet).
var eo_eye = null
var now := 0.0

## ctl+0x78 master mode, +0x80 the previous one, +0x7c the M key cycle, +0x5c the HUD mode (iaf_avionics::master
## through IafModes).
var master: int:
	get:
		return _modes.master()
var master_prev: int:
	get:
		return _modes.master_prev()
var m_cycle: int:
	get:
		return _modes.m_cycle()
var hud_mode: int:
	get:
		return _modes.hud()
	set(v):
		_modes.set_hud(v)
var _modes = ClassDB.instantiate("IafModes")
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
var _bay_until := -1.0
var _releases := 0
var _bay_retry := false  # a missile release waiting for the bay doors
var _pod_nodes: Array = []  # rocket boxes
## The rocket box model and its scale ([Weapons] RocketBoxScale, default 4.0).
const ROCKET_BOX := "weapons/lau61/lau61_m.gltf"
const ROCKET_BOX_SCALE := 4.0
## The Present scale of the store models (bdb weapons: 2.0), the scale the stores on the jet get.
const STORE_PRESENT_SCALE := 2.0
## The AA gun LCOS pipper (FUN_0045f3b0 -> FUN_0045f410; iaf_avionics::gun::Lcos).
var lcos = ClassDB.instantiate("IafLcos")


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
	gun.ground = host.mission_ground
	gun.detonate = _gun_detonate
	seeker = IrSeeker.new()
	seeker.tone = _tone
	radar = Radar.new()
	radar.units = _units
	radar.ground = host.mission_ground
	radar.own = own
	radar.on_lock = _radar_lock
	radar.illumination_lost = _illumination_lost
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
	eo = EoSensor.new()
	eo.pan_k = db.debug_param(8, 0.09)
	eo.unit_pos = func(key: String):
		var u: Dictionary = _rwr_unit(key)
		return u.get("pos")
	harm = HarmSensor.new()
	for i in 9:
		if "FLIR" in stores.name_of(i):
			flir_pod = true
	_push_stores()
	# The tanks' fuel (FUN_005a8980 before the start fills the fuel to FuelWeight + tanks).
	if host.flight != null:
		host.flight.set_fuel_capacity(stores.tank_fuel)
	_build_visuals()


## The Arming screen's pylon loads of the player's flight replace pylons 0..8 (FUN_004f00f0 ->
## FUN_004f0140 writes them to the flight's aircraft; docs/front-end.md §15). Only for the mission's
## own jet (`entity` set), or a plane the Arming screen arms as picked (ours, PlayerAircraft.ARM_AS_PICKED): a jet
## flown in place of another keeps its type's load.
func _arm(load: Array, entity: Dictionary) -> Array:
	var n = host.get("player_flight_number") if host != null else null
	var as_picked: bool = host != null and int(host.player.get("type", -1)) in PlayerAircraft.ARM_AS_PICKED
	if (entity.is_empty() and not as_picked) or n == null or not Settings.arm_loadouts.has(int(n)):
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

func to_scene(w: Vector3) -> Vector3:
	return host.world_to_scene(w)


func to_world(p: Vector3) -> Vector3:
	return host.scene_to_world(p)


## The own jet in the world frame: {pos, vel, fwd, up, right, yaw}.
func own() -> Dictionary:
	var b: Basis = host.rig.global_basis
	var vel := Vector3.ZERO
	if host.flight != null:
		vel = Terrain.dir_to_world(host.flight.state().velocity)
	var fwd := Terrain.dir_to_world(-b.z)
	var o := {"pos": to_world(host.rig.global_position), "vel": vel, "fwd": fwd, "up": Terrain.dir_to_world(b.y),
		"right": Terrain.dir_to_world(b.x), "yaw": atan2(fwd.x, fwd.y)}
	o.merge(seeker_view())
	return o


## The IR seeker's view of the cockpit camera (docs/weapons.md §5.1 / §5.4), {} outside the cockpit views:
## `sight` the camera ray through the HUD centre (cx, cy) {fwd, up, right}, `view_fwd` the camera axis,
## `helmet` in the free-look / padlock views.
func seeker_view() -> Dictionary:
	var cam: Camera3D = host.get("camera")
	var c: Control = host.get("cockpit")
	if cam == null or c == null or not cam.current or host.get("views") == null or not host.views.cockpit_like():
		return {}
	var cb := cam.global_basis.orthonormalized()
	var f := Terrain.dir_to_world(Hud.ray_normal(cam, c.hud_centre_screen())).normalized()
	var r := Terrain.dir_to_world(cb.x)
	r = (r - f * r.dot(f)).normalized()
	return {"sight": {"fwd": f, "right": r, "up": r.cross(f)}, "view_fwd": Terrain.dir_to_world(-cb.z),
		"helmet": host.views.snap == null and host.views.type in [Views.FREE_LOOK, Views.PADLOCK]}


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


func _me() -> Dictionary:
	return host.runtime.player_entity() if host.runtime != null else {}


# --- master and HUD modes (FUN_0044ec80, FUN_00449810, FUN_0044a220) ---------------------------------

## FUN_0044ec80: the master mode and HUD mode of the selected store; `aa_key` = reached by ']'.
func _master_from_type(aa_key: bool) -> void:
	var mh: Array = ClassDB.class_call_static("IafModes", "for_store", stores.current_type(), aa_key, flir_pod)
	if mh.is_empty():
		return  # type 660 / nothing: the mode stays
	_modes.set_master(mh[0])
	_set_hud_mode(mh[1])


func _set_hud_mode(h: int) -> void:
	if hud_mode == 1 and h != 1:
		seeker.exit()
	var entering_ir := h == 1 and hud_mode != 1
	hud_mode = h
	if entering_ir:
		seeker.set_weapon(stores.station(stores.cur).get("w", {}))
		# FUN_00461b00: the seek tone starts only when the selected station is empty (FUN_0053bcd0); the
		# next update (FUN_00461bf0, no rounds) stops it, so the seeker must know it is playing.
		if not _station_has_rounds():
			seeker.start_empty_chirp()


## FUN_00449810: the MFD page of the master mode (NAV 0; bombs / AG gun stores; AA gun radar; the
## IR missiles leave the pages; radar missiles radar; HARM 10; laser bombs with the FLIR pod 6, TV weapons 5)
## and the EO sensor: 5 with the pod starts the FLIR, 6 the TV camera; the other modes leave them
## (FUN_0044e6e0: the pages they replaced come back).
func _mfd_page() -> void:
	var page: int = _modes.mfd_page(stores.current_type(), flir_pod)
	harm.active = master == 4 and stores.current_type() == 590
	if master < 5:
		_eo_leave()
	# Placed like event 0x5a (FUN_00449f90 / FUN_00449f20; UNCERTAIN: same rule).
	if page >= 0 and host.cockpit != null:
		var m = host.cockpit.show_mfd_page(page)
		if page in [5, 6] and m != null:
			_eo_replaced[page] = [m, host.cockpit.replaced_page]
	if master == 5 and flir_pod:
		_eo_start(EoSensor.FLIR)
	elif master == 6:
		_eo_start(EoSensor.TV)


## FUN_0044e6e0: with an EO mode and the previous master mode 5 / 6, page 5 (and page 6 when leaving 5 for
## another mode) go back to what they replaced; EO mode 0.
func _eo_leave() -> void:
	if eo.mode == EoSensor.NONE or not master_prev in [5, 6]:
		return
	for page in [5, 6]:
		if not _eo_replaced.has(page) or (page == 6 and master_prev != 5):
			continue
		var r: Array = _eo_replaced[page]
		if is_instance_valid(r[0]) and r[0].page == page:
			r[0].page = r[1]
		_eo_replaced.erase(page)
	eo.stop()


## The EO start of master modes 5 / 6 and event 0x5a(6) (FUN_00449810, FUN_00450280): FLIR on the pod (class
## 0x1a limits), TV on the selected store; aimed at the radar's target (FLIR; TV only the Maverick 635), else
## (FLIR) at the EO centre point with the laser on, else free.
func _eo_start(mode: int) -> void:
	var aim = null
	var lk: Dictionary = radar.locked()
	if not radar.damaged and not lk.is_empty() and (mode == EoSensor.FLIR or stores.current_type() == 635):
		aim = String(lk.key)
	elif mode == EoSensor.FLIR and eo.laser:
		aim = eo_centre
	eo.start(mode, mode == EoSensor.FLIR, aim, now)
	eo_on_unit = aim is String
	tv_weapon = null


## Event 0x5a(6) (key I) / 0x5b(6) (MENU "FLIR"): only with the pod, page 6 not shown and page 5 not shown;
## then page 6 (on `mfd`, or placed like 0x5a) and the FLIR. Not a toggle.
func flir_on(mfd = null) -> bool:
	var c = host.cockpit
	if not flir_pod or c == null or c.mfds.any(func(m): return m.page in [5, 6]):
		return false
	if mfd != null:
		mfd.page = 6
	else:
		c.show_mfd_page(6)
	_eo_start(EoSensor.FLIR)
	return true


## The MFD and key events of the EO / HARM / stores pages (FUN_005219e0 → the controller): 0x14 / 0x15 EO zoom,
## 0x20 WIDE / SPOT, 0x6a laser, 0x37 HARM select.
func mfd_event(ev: int, arg = null) -> void:
	match ev:
		0x14, 0x15:
			eo.zoom_step(ev == 0x14)
		0x20:
			eo.wide_spot()
		0x6a:
			eo.laser_key(flir_pod)
		0x37:
			harm.select(String(arg))
			_harm_capture()


## Event 0x8a(x, y): the EO slew / lock (docs/mfd.md); a TV camera locks only while its launched weapon flies.
func eo_pan(x: int, y: int) -> void:
	var o := own()
	eo.pan(x, y, now, _eo_base(o), _eo_from(o), eo_centre, tv_flying())


## The launched TV weapon still flies (mcp+0xc's +0x48 == 1).
func tv_flying() -> bool:
	return tv_weapon != null and not tv_weapon.ended


## The camera's eye: the flying TV weapon, else the jet (FUN_004604c0).
func _eo_from(o: Dictionary) -> Vector3:
	return tv_weapon.position(now) if tv_flying() else o.pos


## The camera's base (heading, pitch): the flying TV weapon's velocity, else the jet's nose.
func _eo_base(o: Dictionary) -> Vector2:
	if tv_flying():
		var v: Vector3 = tv_weapon.velocity(now)
		if v.length() > 0.0:
			return Vector2(atan2(v.x, v.y), asin(clampf(v.z / v.length(), -1.0, 1.0)))
	return _base(o)


## The jet's (heading, pitch) for the EO camera's base (roll 0).
static func _base(o: Dictionary) -> Vector2:
	var f: Vector3 = o.fwd
	return Vector2(atan2(f.x, f.y), asin(clampf(f.z, -1.0, 1.0)))


## The EO camera this frame and its centre point (FUN_00450480): with the cockpit drawn (views 1, 0x12, 0x16,
## the snaps) the terrain under the line of sight (ours: ray-marched; nothing → 1e8 m along it), else 1e7 m
## along it.
func _eo_update() -> void:
	if not eo.camera:
		return
	var o := own()
	var b := _eo_base(o)
	var eye := _eo_from(o)
	eo_eye = eye if tv_flying() else null
	eo_ae = eo.angles(now, b, eye)
	eo_dir = eo.los(eo_ae, b)
	var views = host.get("views")
	if views != null and not views.cockpit_drawn():
		eo_centre = eye + eo_dir * 1.0e7
		return
	var hit = ground_hit(eye, eo_dir)
	eo_centre = hit if hit != null else eye + eo_dir * 1.0e8


## The first terrain point along a ray (world), or null within 100 km: steps of 2 % of the distance (at
## least 25 m), then 8 halvings.
func ground_hit(from: Vector3, dir: Vector3) -> Variant:
	var a := 0.0
	var s := 25.0
	while a < 100000.0:
		var b := a + s
		var p := from + dir * b
		var g = host.mission_ground(p)
		if g != null and p.z <= float(g):
			for i in 8:
				var m := (a + b) * 0.5
				var q := from + dir * m
				var gm = host.mission_ground(q)
				if gm != null and q.z <= float(gm):
					b = m
				else:
					a = m
			return from + dir * b
		a = b
		s = maxf(25.0, b * 0.02)
	return null


## The HARM list capture from the RWR's slots (the mcp's refresh, with the RWR's 2 s refresh and a selection).
func _harm_capture() -> void:
	var o := own()
	harm.capture(rwr.slots, o.pos, _base(o))


## The TV status (FUN_00460940): 0 NO SOURCE unless the TV weapon (the flying one, else the selected store) is a
## 635 / 640 / 650; 1 RDY before launch and for a launched Maverick, else the guided weapon's 2 TRA / 3 TER; 0 when
## the selected store has no rounds left and (nothing flies or a Maverick flies).
func tv_status() -> int:
	var flying := tv_flying()
	var ft: int = int(tv_weapon.weapon.type) if flying else -1
	var gs: int = tv_weapon.status() if flying and ft != 635 else 0
	return ClassDB.class_call_static("IafRelease", "tv_status", ft, gs, stores.current_type(),
		stores.total(stores.current_type(), stores.current_name()))


## The TV page's "%3d" (FUN_004d6ac0 of the TV weapon's time left: < 0 → 0, > 300 → 60); 0 before a launch
## (UNCERTAIN: the original reads the store's motion then).
func tv_time() -> int:
	if tv_weapon == null:
		return 0
	return int(ClassDB.class_call_static("IafRelease", "shown_time", tv_weapon.time_left(now)))


## ']' (event 0x3e): next AA store unless an AA missile is already selected in NAV.
func select_aa() -> void:
	if _modes.aa_key_cycles(stores.current_type()):
		_next(1)
	_master_from_type(true)
	_mfd_page()


## '[' (event 0x3c): next AG store unless a non-AA store is already selected in NAV.
func select_ag() -> void:
	if _modes.ag_key_cycles(stores.current_type()):
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
	match _modes.master_key():
		"aa":
			select_aa()
		"ag":
			select_ag()
		"nav":
			_set_hud_mode(0)
			_mfd_page()
	host.sounds.play("SFX_BUTTON")


## N (event 0x62, p = 0): the master mode p (NAV).
func nav_key(p: int) -> void:
	_modes.nav_key(p)
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
	if not ClassDB.class_call_static("IafRelease", "space_allowed", hud_mode, host.gear_down, safety_off,
			stores.current_type() == Stores.GUN, _flag(20)):
		return
	# FUN_00454270
	if _weapons_down() or releasing or stores.total(stores.current_type(), stores.current_name()) == 0:
		return
	releasing = true
	match stores.current_type():
		Stores.GUN:
			gun_trigger()
		570, 580, 590, 600, 610:
			_release_missile()
			releasing = false  # FUN_004545e0: W+0xac cleared after a non-bomb release
		635, 640:
			_release_tv()
			releasing = false
		500, 510, 560, 650:
			_bomb_space()


## Space up (event 0x41, FUN_00456100): bomb types stop the ripple timer and unfreeze the HUD.
func release_selected() -> void:
	releasing = false
	if stores.current_type() == Stores.GUN:
		gun_stop()
	if stores.current_type() in BOMB_TYPES:
		_ripple_next = INF
		ripple_left = 0
		if hud_mode in [5, 6]:
			ag.frozen = false  # FUN_0045d150(1)


# --- jettison (Shift+C, event 0x48) ----------------------------------------------------------------

## W+0xb8 tanks jettisoned, W+0xbc bombs jettisoned.
var tanks_jettisoned := false
var bombs_jettisoned := false


## Event 0x48: nothing with the gear handle down; the first press drops the tanks (FUN_00458760), the
## next ones the bombs (FUN_00458d10).
func jettison() -> void:
	if host.gear_down:
		return
	if not tanks_jettisoned:
		_jettison_tanks()
	elif not bombs_jettisoned:
		_jettison_bombs()


## FUN_0045ee10, the release permission of bombs and jettisons: load factor ≥ 0 and |roll| ≤ 90°.
func release_allowed() -> bool:
	var st: Dictionary = host.flight.state() if host.flight != null else {}
	return st.is_empty() or ClassDB.class_call_static("IafRelease", "release_allowed", float(st.g), float(st.roll))


## FUN_00458760 (with the release permission): every pylon whose store name contains "LB" releases
## one store (count −1 even with Unlimited ammo, drag updated, no weight update), falling as a
## ballistic object to the ground 500 m ahead (_fireEndVec); then, when the fuel is at or above
## FuelWeight, the fuel and its maximum become FuelWeight (motion 0x18): the tanks' fuel is gone.
func _jettison_tanks() -> void:
	if not release_allowed():
		return
	var was: bool = stores.unlimited
	stores.set_unlimited(false)
	for i in 9:
		if stores.stations.has(i) and "LB" in stores.name_of(i) and stores.displayed(i) > 0:
			_drop_store(i, _jettison_aim(int(stores.type_of(i))))
			stores.jettisoned(i)
	stores.set_unlimited(was)
	if host.flight != null:
		var st: Dictionary = host.flight.state()
		if float(st.fuel_lbs) >= float(st.internal_fuel_kg) * 2.2046:
			host.flight.set_fuel(float(st.internal_fuel_kg))
	tanks_jettisoned = true
	_push_stores()
	_update_store_nodes()


## FUN_00458d10 (with the release permission; Unlimited ammo off meanwhile): every round of the
## stations 0..8 holding a bomb type other than rockets (500, 510, 650) falls to the ground 500 m
## ahead (_fireEndVec), with the usual drag / weight updates; then W+0xbc.
func _jettison_bombs() -> void:
	if not release_allowed():
		return
	var was: bool = stores.unlimited
	stores.set_unlimited(false)
	for i in 9:
		var t: int = stores.type_of(i)
		if not t in [500, 510, 650]:
			continue
		while stores.displayed(i) > 0:
			_drop_store(i, _jettison_aim(t))
			stores.fired(i)
	stores.set_unlimited(was)
	bombs_jettisoned = true
	_push_stores()
	_update_store_nodes()


## FUN_004d7260: the store's _fireEndVec (0, 500, 0) in body axes from the jet, on the terrain.
func _jettison_aim(type: int) -> Vector3:
	var m: Dictionary = db.motion_for(type, 0)
	var fe := Vector3(m.get("_fireEndVecX", 0.0), m.get("_fireEndVecY", 500.0), m.get("_fireEndVecZ", 0.0))
	var o := own()
	var a: Vector3 = o.pos + o.right * fe.x + o.fwd * fe.y + o.up * fe.z
	a.z = Bombs._h(host.mission_ground, a)
	return a


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
	if not gun.next_free():
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
	if not hit.is_empty():
		gun_hit_effect(hit.pos if hit.has("pos") else pos)


## A gun round's impact at world point `at` (also the ground units' AAA rounds): a splash on water, else the
## small fireball and SFX_WEAPON_EXPLODED/OST_GUNBULLET.
func gun_hit_effect(at: Vector3) -> void:
	var sp := to_scene(at)
	var water: bool = (host.terrain.surface_at(sp) & host.terrain.SURFACE_WATER) != 0
	var g = host.terrain.height_at(sp)
	if water and (g == null or sp.y < g + 10.5):
		host.effects.smoke_puff(sp, true)  # splash (look UNCERTAIN)
		_place_sound(host.sounds.play("SFX_SPLASH"), at)
		return
	host.effects.explosion(sp, DamageEffects.F_SMALL_FIRE, 1.5, 1.2, g if g != null else sp.y)
	_place_sound(host.sounds.play("SFX_WEAPON_EXPLODED", "OST_GUNBULLET"), at)


# --- homing weapons (class 0x18: 570, 580, 590, 600, 610, 635; docs/weapons.md §5, §11) ---------------

## The OST of each weapon type (the sound table's sub code 1).
const WEAPON_OST := {570: "OST_HEATMISSILE", 580: "OST_LIMITEDHEATMISSILE", 590: "OST_HARM", 600: "OST_RADARMISSILE",
	610: "OST_SEMIRADARMISSILE", 620: "OST_HEATSAM", 630: "OST_RADARSAM", 635: "OST_MAVRICK", 640: "OST_TVMISSILE",
	650: "OST_LASERBOMB"}
## W+0x274: the semi-active (610) missiles launched at a target and still flying; the radar losing its track
## (FUN_00458130) turns their guidance off.
var semi_active: Array = []
var _missile_id := 0


## FUN_004545e0 -> FUN_00454b70 (570 / 580 / 590 / 600 / 610): HUD mode 1, 2 or 8; the target and q of
## FUN_00457f70 from that HUD mode's object (1 the IR seeker, 2 the MRM sight on the radar's target, 8 the HARM
## sight on the HARM page's selection). A 610 with a target makes the radar lock it (FUN_004ad880(2), STT) and
## joins the semi-active list.
func _release_missile() -> void:
	if not hud_mode in [1, 2, 8]:
		return
	var i: int = stores.fire_station()
	if i < 0 or stores.displayed(i) <= 0:
		return
	if _bay_wait(i):
		_bay_retry = true
		return
	var st: Dictionary = stores.station(i)
	var w: Dictionary = st.w
	var o := own()
	var tq := _launch_target(o)
	var target: Dictionary = tq[0]
	var q: float = tq[1]
	# Release point: the store's slot (the last drawn) or the pylon, through the attitude.
	var slots: Array = st.slots
	var n := int(st.count)
	var at: Vector3 = slots[n - 1] if n >= 1 and n <= slots.size() else st.attach
	var mis := launch_homing(w, body_to_world(at), o, String(target.get("key", "")), q, _me())
	if int(w.type) == 610 and not target.is_empty():
		radar.lock_stt()
		semi_active.append(mis)
	_place_sound(host.sounds.play("SFX_AIRCRAFT_FIRED_WEAPON", WEAPON_OST.get(int(w.type), "OST_RADARMISSILE")), mis.p0)
	stores.fired(i)
	_push_stores()
	_update_store_nodes()


## FUN_004545e0 -> FUN_00454b70 cases 0x27b / 0x280 (the TV weapons, player): the launch data of FUN_0045db70 —
## the camera not started on a unit: the EO centre point (FUN_00450480), no unit, q 1; started on one (the
## Maverick): the radar's target (radar on, a lock or a TWS selection) and the EO centre as the point (UNCERTAIN:
## the original leaves the point uninitialised). The Maverick 635 flies the homing motion at the unit or the
## point; the TV missile 640 the guided motion at the point. The camera then rides it.
func _release_tv() -> void:
	var i: int = stores.fire_station()
	if i < 0 or stores.displayed(i) <= 0:
		return
	var st: Dictionary = stores.station(i)
	var w: Dictionary = st.w
	var o := own()
	var unit := ""
	if eo_on_unit and not radar.damaged:
		unit = String(radar.locked().get("key", ""))
	var slots: Array = st.slots
	var n := int(st.count)
	var at: Vector3 = slots[n - 1] if n >= 1 and n <= slots.size() else st.attach
	var pos := body_to_world(at)
	if int(w.type) == 635:
		tv_weapon = launch_homing(w, pos, o, unit, 1.0, _me(), eo_centre)
	else:
		tv_weapon = launch_guided(w, pos, o.vel, eo_centre, _me())
	_place_sound(host.sounds.play("SFX_AIRCRAFT_FIRED_WEAPON", WEAPON_OST.get(int(w.type), "OST_TVMISSILE")), pos)
	stores.fired(i)
	_push_stores()
	_update_store_nodes()


## One guided weapon (640 / 650) leaves its launcher (FUN_004d5d10 -> FUN_00563f90) toward the aim point; its
## model, no trail (FUN_004da090 draws them for 560..635 only). Not player-specific.
func launch_guided(w: Dictionary, pos: Vector3, vel: Vector3, point: Vector3, owner: Dictionary) -> RefCounted:
	var g := Guided.new()
	g.launch(w, _motion(w), now, pos, vel, point, db.debug_param)
	g.set_meta("owner", owner)
	var node := _instance(String(w.get("model_path", "")))
	if node != null:
		host.add_child(node)
		node.scale = Vector3.ONE * float(w.get("scale", 1.0))
	g.set_meta("node", node)
	g.set_meta("sound", host.sounds.play("SFX_OBJECT_SPECIFIC", WEAPON_OST.get(int(w.type), "OST_TVMISSILE")))
	guided.append(g)
	if is_same(owner, _me()):
		last_launched = g
	return g


## The guided weapons' flight; the TV missile steers to the EO centre point while the cockpit is drawn (each TV
## update: weapon vfunc +0x2c, a non-Maverick in TRA / TER, views 1 / 0x12 / 0x16). Bursts as a falling store.
func _update_guided() -> void:
	var views = host.get("views")
	if tv_flying() and tv_weapon in guided and (views == null or views.cockpit_drawn()):
		tv_weapon.set_aim(eo_centre)
	for g in guided.duplicate():
		var gone := false
		while not gone and g.next_update <= now:
			gone = g.update(g.next_update, host.mission_ground)
		var p: Vector3 = g.last_pos if gone else g.position(now)
		var node: Node3D = g.get_meta("node")
		if node != null:
			node.position = to_scene(p)
			_orient(node, g.velocity(now))
		_place_sound(g.get_meta("sound"), p)
		if gone:
			guided.erase(g)
			_bomb_detonate({"w": g.weapon, "node": node, "sound": g.get_meta("sound")}, p)


## FUN_00457f70 with the HUD mode's object: [target unit {} none, q]. Without Easy aiming the object's target
## counts only inside its launch circle (vfunc +0x30) and q = vfunc +0x38 × 0.8 (v1.1); with Easy aiming any
## target and q = 1. A target with a controller whose ECM is on, against the radar seeker (vfunc +0x18 = 2):
## q − rand. At least 0.1.
func _launch_target(o: Dictionary) -> Array:
	var units := _units()
	var sight_q := 1.0
	var target := {}
	match hud_mode:
		1:
			target = seeker.current(units) if easy_aiming else seeker.target_in_circle(o, units)
		2, 8:
			var s := _sight(o, units)
			if not s.target.is_empty() and (easy_aiming or MrmSight.target_in_circle(IrSeeker.screen_offset(o, s.target.pos), s.locked)):
				target = s.target
				sight_q = float(s.q)
	if target.is_empty():
		return [target, 1.0]
	var ecm = float(randi() & 0x7fff) / 32767.0 if hud_mode == 2 and bool(target.get("ecm", false)) else null
	return [target, ClassDB.class_call_static("IafRelease", "launch_q", hud_mode, seeker.lock, sight_q, easy_aiming, ecm)]


## The MRM (mode 2) / HARM (mode 8) sight this frame: {target (vfunc +0x28: the radar's A-A lock or TWS
## selection / the HARM page's selected emitter), locked (vfunc +0x2c), dlz [max, min], dist, r (the circle
## size), pred (the predicted point, world), q (vfunc +0x38)}.
func _sight(o: Dictionary, units: Array) -> Dictionary:
	var target := {}
	var locked := false
	if hud_mode == 8:
		locked = harm.selected != ""
		target = _unit(units, harm.selected)
	else:
		locked = radar.has_lock()
		var lk: Dictionary = radar.locked()
		if radar.aa and not lk.is_empty():
			target = _unit(units, String(lk.key))
	var out := {"target": target, "locked": locked, "dlz": [], "dist": 0.0, "r": MrmSight.R0, "pred": null, "q": 1.0}
	if target.is_empty() or not locked:
		return out
	var d: float = (target.pos - o.pos).length()
	out.dist = d
	out.dlz = selected_dlz(o, target)
	out.r = MrmSight.circle(true, out.dlz, d)
	out.pred = MrmSight.predicted(target.pos, target.get("vel", Vector3.ZERO), d)
	var hud_only: bool = host.get("views") != null and host.views.type == Views.HUD_ONLY
	out.q = MrmSight.in_circle(IrSeeker.screen_offset(o, out.pred), out.r, hud_only)[1]
	return out


static func _unit(units: Array, key: String) -> Dictionary:
	if key == "":
		return {}
	for u in units:
		if u.key == key:
			return u
	return {}


## The DLZ (weapon vfunc +0x24 -> its motion's +0x74) of the selected store from the jet at a target ({} none):
## [max, min] metres; [] for a store without one (gun, decoys, pods).
func selected_dlz(o: Dictionary, target: Dictionary) -> Array:
	var w: Dictionary = stores.station(stores.cur).get("w", {})
	var t := int(w.get("type", 0))
	if t in [640, 650]:
		var g = host.mission_ground(o.pos)
		return Guided.dlz(_motion(w), o.pos.z - (float(g) if g != null else 0.1), o.vel, db.debug_param)
	if not t in [570, 580, 590, 600, 610, 635]:
		return []
	return Missile.dlz(_motion(w), {"pos": o.pos, "fwd": o.fwd, "vel": o.vel}, target)


## The weapons.ibx record of a weapon with its Real overrides.
func _motion(w: Dictionary) -> Dictionary:
	var m: Dictionary = db.motion_for(int(w.type), int(w.generation)).duplicate()
	m.merge(w.get("motion", {}), true)
	return m


## One homing weapon leaves its launcher (FUN_004d5d10 -> FUN_004d80c0): the chase motion from `pos` at the
## launcher's velocity / attitude `from` {vel, fwd, up, right}, at the unit `target` ("" = the _fireEndVec point
## in the launcher's body axes) with q. `owner` = the launcher's mission entity (the blast's attacker). The
## weapon's model and flight loop; a target with a controller (the player) hears the launch on its RWR
## (FUN_004d8130 -> FUN_0044e160). Not player-specific: AI launchers use it too.
func launch_homing(w: Dictionary, pos: Vector3, from: Dictionary, target: String, q: float, owner: Dictionary, at = null) -> RefCounted:
	var m := _motion(w)
	var fe := Vector3(m.get("_fireEndVecX", 0.0), m.get("_fireEndVecY", 10000.0), m.get("_fireEndVecZ", 0.0))
	var point: Vector3 = at if at != null else pos + from.right * fe.x + from.fwd * fe.y + from.up * fe.z
	var mis := Missile.new()
	mis.launch(w, m, now, pos, from.vel, from.fwd, target, point, q, db.debug_param, from.up)
	_missile_id += 1
	mis.set_meta("id", _missile_id)
	mis.set_meta("owner", owner)
	# The launch distance: the RWR's missile list is sorted by it (FUN_004598a0), the decoy rule's scan order.
	var tu: Dictionary = _rwr_unit(target)
	mis.set_meta("dist", pos.distance_to(own().pos if target == String(_me().get("key", "")) else tu.get("pos", pos)))
	missiles.append(mis)
	_missile_visual(mis)
	if is_same(owner, _me()):
		last_launched = mis
	if target != "" and target == String(_me().get("key", "")):
		rwr.launch(String(owner.get("key", "")), _rwr_missile(mis))
	return mis


func _rwr_missile(mis: RefCounted) -> Dictionary:
	return {"id": mis.get_meta("id"), "pos": mis.position(now), "decoy": String(mis.target_key).begins_with("decoy:"), "m": mis}


func _missile_visual(mis: RefCounted) -> void:
	var node := _instance(String(mis.weapon.get("model_path", "")))
	if node != null:
		host.add_child(node)
		node.position = to_scene(mis.p0)
	mis.set_meta("node", node)
	# Flight loop (UNCERTAIN: code 0x8337e4, probably SFX_OBJECT_SPECIFIC / the weapon's OST).
	var s = host.sounds.play("SFX_OBJECT_SPECIFIC", WEAPON_OST.get(int(mis.weapon.type), "OST_HEATMISSILE"))
	mis.set_meta("sound", s)


## A homing weapon's target now ({pos, vel}, {} gone): a mission unit, the player's jet, or a decoy
## ("decoy:<n>", its position; after its end it stays where it ended, UNCERTAIN).
func target_state(key: String, units: Dictionary) -> Dictionary:
	if key.begins_with("decoy:"):
		var dc: Dictionary = _decoy_by_id.get(int(key.substr(6)), {})
		if dc.is_empty():
			return {}
		var t: float = minf(now, float(dc.end))
		return {"pos": _decoy_motion[dc.type].position(dc.r, t), "vel": Vector3.ZERO}
	if key != "" and key == String(_me().get("key", "")):
		var o := own()
		return {"pos": o.pos, "vel": o.vel}
	return units.get(key, {})


func _update_missiles() -> void:
	var units := {}
	for u in _units():
		units[u.key] = u
	for mis in missiles.duplicate():
		var gone := false
		while not gone and mis.next_update <= now:
			var t := target_state(mis.target_key, units)
			var tp: Vector3 = t.get("pos", mis.last_pos)
			if mis.has_target and t.is_empty():
				tp = Vector3.ZERO  # target gone: FUN_0045a180's static default (UNCERTAIN: origin)
			gone = mis.update(mis.next_update, tp, t.get("vel", Vector3.ZERO), host.mission_ground)
		var node: Node3D = mis.get_meta("node")
		var p: Vector3 = mis.last_pos if gone else mis.position(now)
		var v: Vector3 = mis.velocity(now)
		if node != null:
			node.position = to_scene(p)
			var dv := Terrain.dir_to_scene(v)
			if dv.length() > 1.0:
				node.basis = Basis.looking_at(dv.normalized(), Vector3.UP if absf(dv.normalized().y) < 0.99 else Vector3.RIGHT)
		_place_sound(mis.get_meta("sound"), p)
		if not gone:
			_trail(mis, node)
		if gone:
			_missile_detonate(mis)


## FUN_004d6130 for a homing weapon: every unit around (the blast decides), explosion and sound
## (UNCERTAIN look: a fireball of the weapon explosion), the flight loop stops; a missile at the player
## leaves its RWR (FUN_004d8160 -> FUN_0044e1d0).
func _missile_detonate(mis: RefCounted) -> void:
	missiles.erase(mis)
	semi_active.erase(mis)
	var p: Vector3 = mis.last_pos
	var owner: Dictionary = mis.get_meta("owner", {})
	var hit := []
	if host.runtime != null and not owner.is_empty():
		hit = host.runtime.area_damage(p, float(mis.weapon.power), float(mis.weapon.radius), owner, "missile")
	var sp := to_scene(p)
	var g = host.terrain.height_at(sp)
	host.effects.explosion(sp, DamageEffects.F_FIREBALL | DamageEffects.F_PUFF, 1.0, 5.0, g if g != null else sp.y)
	_place_sound(host.sounds.play("SFX_WEAPON_EXPLODED", WEAPON_OST.get(int(mis.weapon.type), "OST_HEATMISSILE")), p)
	if not hit.is_empty():
		_place_sound(host.sounds.play("SFX_WEAPON_HIT_TARGET"), p)
	var node: Node3D = mis.get_meta("node")
	if node != null:
		node.queue_free()
	if mis.get_meta("sound") != null:
		host.sounds.stop(mis.get_meta("sound"))
	if rwr.missiles.any(func(e): return e.missile.id == mis.get_meta("id")):
		rwr.missile_end(String(owner.get("key", "")), _rwr_missile(mis))


## FUN_00458130 (the radar drops or changes its track: Q, R, S, Return, a click lock, Backspace, STT lost, a mode
## leaving STT): every semi-active missile still flying loses its guidance (motion +0x148 = 1); the list empties.
func _illumination_lost() -> void:
	for mis in semi_active:
		mis.guidance_off = true
	semi_active.clear()


## FUN_0053bcd0: the selected station has rounds left (not the weapon's total over every station).
func _station_has_rounds() -> bool:
	return float(stores.station(stores.cur).get("count", 0.0)) > 0.0


func _tone(kind: String) -> void:
	for pair in [["seek", "_seek_sound", "SFX_IR_SEEK"], ["lock", "_lock_sound", "SFX_IR_LOCK"]]:
		var cur = get(pair[1])
		if kind == pair[0]:
			if cur == null:
				set(pair[1], host.sounds.play(pair[2]))
		elif cur != null:
			host.sounds.stop(cur)
			set(pair[1], null)


# --- bombs and rockets (docs/weapons.md §9) ----------------------------------------------------------

## The bomb types ("bomb types" of FUN_00457bc0): 500 bomb, 510 cluster, 560 rockets, 650 laser bomb.
const BOMB_TYPES := [500, 510, 560, 650]
const OST := {500: "OST_BOMB", 510: "OST_CLUSTERBOMB", 560: "OST_ROCKET", 650: "OST_LASERBOMB", 660: "OST_SHELL"}
## After the last bomb the symbols blink for 1.0 s (_DAT_0082f620).
const BLINK_TIME := 1.0
## The player's bombs: along-track correction clamped to ±_debugParam016 (single player).
const BOMB_CLAMP_PARAM := 16

## W+0xd4 quantity (1..14), W+0xd8 interval (10..200, the spacing in m and the period in ms),
## W+0xdc the period (s) (iaf_avionics::release::Ripple), W+0xd0 bombs left in this ripple, W+0x288 the ripple
## timer (next tick).
var ripple_qty: int:
	get:
		return _ripple.qty()
	set(v):
		_ripple.set_qty(v)
var ripple_int: int:
	get:
		return _ripple.interval()
var ripple_period: float:
	get:
		return _ripple.period()
var _ripple = ClassDB.instantiate("IafRipple")
var ripple_left := 0
var _ripple_next := INF
## W+0xf4..: the ripple line frozen at the first bomb.
var _ripple_line: Array = []
## The mode-5 HUD object (FUN_0045d0a0 / update FUN_0045d1d0): +0xc impact, +0x18 target, +0x2c off the
## HUD (cockpit views), +0x30 time-to-go, +0x3c frozen (Space held), +0x40 blinking (until), and
## the world point the pipper is drawn at.
var ag := {"impact": Vector3.ZERO, "target": Vector3.ZERO, "off": false, "ttg": -1.0, "frozen": false,
	"blink_until": -INF, "pipper": null}
## The host's HUD test (cockpit views only): world point -> {off: bool, origin, dir (scene ray through
## the point clipped to the HUD edge toward the flight path marker)}; unset = always on the HUD
## (the original's other views).
var hud_clip: Callable
## Physics "fix_bomb_burst" (ours): bombs burst where they meet the terrain.
var bomb_burst_fix := false
## Falling stores: {b (bombs.gd state), w, node, sound, t0}.
var bombs: Array = []
## Rockets (560): the fixed-weapon motion of the gun rounds with weapons.ibx 560; {r, w, node}.
var rockets: RefCounted
var _rocket_nodes := {}  # pool index -> {node, w}


## Events 0x4a / 0x4b (stores MFD OSBs 0xe / 0xf quantity ±1, 0x13 / 0x14 interval ±10) ->
## FUN_004562a0 -> FUN_004562f0: quantity 1..14, interval 10..200, period max(0.1, interval / 1000).
func ripple_event(ev: int, up: bool) -> void:
	_ripple.step(ev == 0x4a, up)


## FUN_00454270, bomb types (player): HUD mode 5 or 6; without a running ripple: W+0xd0 = quantity,
## the HUD freezes (FUN_0045d130: one update, then +0x3c), the timer starts now (the first bomb on
## the next tick), then one per period while Space is held.
func _bomb_space() -> void:
	if not hud_mode in [5, 6]:
		return
	if _ripple_next != INF:
		return
	ripple_left = ripple_qty
	_update_ag()
	ag.frozen = true
	_ripple_next = now


## The ripple timer callback (FUN_0045a680 -> FUN_004545e0, player bombs).
func _ripple_tick() -> void:
	var t: int = stores.current_type()
	if stores.total(t, stores.current_name()) == 0 or _weapons_down():
		_ripple_end()
		return
	var i: int = stores.fire_station()
	if i < 0 or stores.displayed(i) <= 0:
		releasing = false
		return
	if t == 560 and not _rockets().next_free():
		return  # the station's pool object is still flying: wait for the next tick
	# FUN_00454b70: the aim = the HUD target (off the HUD) or the impact, spread on the ripple line.
	var p: Vector3 = ag.target if ag.off else ag.impact
	if ripple_left == ripple_qty or _ripple_line.size() != ripple_qty:
		_ripple_line = Bombs.ripple_line(p, ripple_qty, float(ripple_int), own().yaw, host.mission_ground)
	var aim: Vector3 = _ripple_line[_ripple.index(ripple_left)]
	if t == 650:
		aim = _laser_aim(p, aim)
	# FUN_0045ee10 and the delayed release (the first bomb waits for time-to-go ≤ 0.9 s).
	if not release_allowed() or _bay_wait(i):
		return
	if ClassDB.class_call_static("IafRelease", "first_bomb_waits", ag.off, ripple_left == ripple_qty, float(ag.ttg)):
		return
	ripple_left -= 1
	if ripple_left <= 0:
		_ripple_end()
	_drop_store(i, aim)
	stores.fired(i)
	_push_stores()
	_update_store_nodes()


## FUN_00454b70 case 0x28a: with the laser on (ctl+0x960, `FUN_00450430`) the designation (`FUN_00450410` →
## `FUN_0045db70`: the EO centre point, or the unit the camera started on, its position now) replaces the ripple aim
## when it lies within 60° of the line to the bomb's point P (cos 60°, 0x82f4e0 from 0x600ee8) and at most 2 m
## above the terrain (0x600f08); else the ripple aim (`FUN_00457c20`). Recomputed per store.
func _laser_aim(p: Vector3, ripple: Vector3) -> Vector3:
	if not eo.laser:
		return ripple
	var d: Vector3 = eo_centre
	if eo_on_unit and eo.target != "" and eo.unit_pos.is_valid():
		var u = eo.unit_pos.call(eo.target)
		if u != null:
			d = u
	var g = host.mission_ground(d)
	return ClassDB.class_call_static("IafRelease", "laser_aim", own().pos, p, ripple, d, float(g) if g != null else 0.1)


## The ripple ends (timer killed, FUN_0045d150(0): the symbols blink for 1 s); W+0xac cleared.
func _ripple_end() -> void:
	_ripple_next = INF
	releasing = false
	ag.blink_until = now + BLINK_TIME


## One store leaves station i toward `aim` (the release of FUN_004545e0): from its slot (the last
## drawn) or the pylon through the attitude, at the jet's velocity; rockets (560) fly the
## fixed-weapon motion, laser bombs (650) the guided one (§12), everything else the ballistic one. Sounds: the release
## (SFX_AIRCRAFT_FIRED_WEAPON) and the fall loop (SFX_OBJECT_SPECIFIC).
func _drop_store(i: int, aim: Vector3) -> void:
	var st: Dictionary = stores.station(i)
	var w: Dictionary = st.w
	var type := int(w.type)
	var o := own()
	var slots: Array = st.slots
	var n := int(st.count)
	var at: Vector3 = slots[n - 1] if n >= 1 and n <= slots.size() else st.attach
	var p0 := body_to_world(at)
	var ost: String = OST.get(type, "OST_BOMB")
	_place_sound(host.sounds.play("SFX_AIRCRAFT_FIRED_WEAPON", ost), p0)
	if type == 650:
		launch_guided(w, p0, o.vel, aim, _me())  # the laser bomb always flies the guided motion (§12)
		return
	if type == 560:
		var g: RefCounted = _rockets()
		var k: int = g.fire(now, o.pos, p0, o.vel, aim, "", String(_me().get("key", "")), false)
		var node := _instance(String(w.model_path))
		if node != null:
			host.add_child(node)
			node.scale = Vector3.ONE * float(w.get("scale", 1.0))
		_rocket_nodes[k] = {"node": node, "w": w}
		return
	# v1.1 logic with any data: v1.0's weapons.ibx has 1.0 here (v1.1 changed it to 15, docs/v1.1.md), so a v1.0
	# install gets the v1.1 value (drop_bomb).
	drop_bomb(w, p0, o.vel, aim, _me())


## One ballistic store from `p0` at `vel` toward `aim` (Bombs.launch), its model and fall loop; `owner` = the
## releasing unit (the blast's attacker). Not player-specific: AI jets drop through it too.
func drop_bomb(w: Dictionary, p0: Vector3, vel: Vector3, aim: Vector3, owner: Dictionary) -> void:
	var clamp_acc: float = db.debug_param(BOMB_CLAMP_PARAM, 15.0)
	if is_equal_approx(clamp_acc, 1.0):
		clamp_acc = 15.0
	var b := Bombs.launch(now, p0, vel, aim, clamp_acc)
	var node := _instance(String(w.model_path))
	if node != null:
		host.add_child(node)
	var snd = host.sounds.play("SFX_OBJECT_SPECIFIC", OST.get(int(w.type), "OST_BOMB"))
	bombs.append({"b": b, "w": w, "node": node, "sound": snd, "t0": now, "owner": owner})
	_place_bomb(bombs[-1])


func _rockets() -> RefCounted:
	if rockets == null:
		rockets = GunRounds.new()
		var m: Dictionary = {"_spiralAccel": 0.0}
		m.merge(db.motion_for(560, 0), true)
		rockets.configure(m)
		rockets.units = _units
		rockets.ground = host.mission_ground
		rockets.detonate = _rocket_detonate
	return rockets


## The mode-5 HUD object update (FUN_0045d1d0). Not frozen: the impact I (FUN_0045e7f0) and, when its
## pipper is off the HUD (cockpit views), the target T = the ground under the pipper clipped to the
## HUD edge, time-to-go = horizontal |I − T| / ground speed. Frozen (Space): off the HUD I and the
## time-to-go follow the jet and the pipper shows the frozen T; on the HUD the frozen I.
func _update_ag() -> void:
	var o := own()
	var st: Dictionary = stores.station(stores.cur)
	var w: Dictionary = st.get("w", {})
	var extra := 0.0
	if int(w.get("type", 0)) == 560:
		extra = float(db.motion_for(560, 0).get("_limitVel", 1000.0))
	var gs := Vector2(o.vel.x, o.vel.y).length()
	if not ag.frozen:
		ag.impact = Bombs.predict_impact(o.pos, o.vel, o.fwd, float(w.get("drag", 0.0)), extra, host.mission_ground).point
		var c: Dictionary = hud_clip.call(ag.impact) if hud_clip.is_valid() else {}
		ag.off = bool(c.get("off", false))
		ag.pipper = ag.impact
		if ag.off:
			var t = _ray_ground(c.origin, c.dir)
			if t != null:
				ag.target = t
			ag.ttg = _hdist(ag.impact, ag.target) / maxf(gs, 1.0)
	elif ag.off:
		ag.impact = Bombs.predict_impact(o.pos, o.vel, o.fwd, float(w.get("drag", 0.0)), extra, host.mission_ground).point
		ag.ttg = _hdist(ag.impact, ag.target) / maxf(gs, 1.0)
		ag.pipper = ag.target
	else:
		ag.ttg = -1.0
		ag.pipper = ag.impact


static func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()


## The terrain point on a scene ray (the renderer's screen-point query FUN_00401fc0), world frame.
func _ray_ground(origin: Vector3, dir: Vector3) -> Variant:
	var o := to_world(origin)
	var d := Terrain.dir_to_world(dir).normalized()
	if d.z >= -1e-4:
		return null
	var step := 50.0
	var prev := o
	for k in 1200:
		var q := o + d * step * float(k + 1)
		if q.z <= Bombs._h(host.mission_ground, q):
			var lo := prev
			var hi := q
			for j in 12:
				var m := (lo + hi) * 0.5
				if m.z <= Bombs._h(host.mission_ground, m):
					hi = m
				else:
					lo = m
			return hi
		prev = q
	return null


func _update_bombs() -> void:
	for bm in bombs.duplicate():
		var hit: Dictionary = Bombs.check(bm.b, now, host.mission_ground, bomb_burst_fix)
		_place_bomb(bm)
		if not hit.is_empty():
			bombs.erase(bm)
			_bomb_detonate(bm, hit.pos)
	if rockets != null:
		rockets.update(now)
		for k in _rocket_nodes:
			var e: Dictionary = _rocket_nodes[k]
			var r: Dictionary = rockets.pool[k]
			if e.node != null and r.flying:
				e.node.position = to_scene(rockets.position(r, now))
				_orient(e.node, r.u)
				_trail(["rocket", k], e.node)


func _place_bomb(bm: Dictionary) -> void:
	var p := Bombs.position(bm.b, now)
	if bm.node != null:
		bm.node.position = to_scene(p)
		_orient(bm.node, Bombs.velocity(bm.b, now))
		bm.node.scale = Vector3.ONE * float(bm.w.get("scale", 1.0))
	_place_sound(bm.sound, p)


## The trail of a flying missile / rocket (types 560, 570..635, FUN_004da090): its head is
## MissileFlareDistance (1.0) + half the model length behind the model's centre, along its axis.
func _trail(key, node: Node3D) -> void:
	if host.trails == null or node == null:
		return
	if not node.has_meta("half_length"):
		node.set_meta("half_length", 0.5 * preload("res://util/gltf.gd").model_aabb(node).size.z * node.scale.z)
	var back := node.global_basis.z.normalized()  # looking_at: the nose is −Z
	host.trails.emit(key, node.global_position + back * (MISSILE_FLARE_DISTANCE + float(node.get_meta("half_length"))), host.trails.MISSILE)


## [SFX] MissileFlareDistance (default 1.0, 0x6389fc): how far behind the tail the trail starts.
const MISSILE_FLARE_DISTANCE := 1.0


## A store's attitude from its velocity (world vector).
static func _orient(node: Node3D, v: Vector3) -> void:
	var dv := Terrain.dir_to_scene(v)
	if dv.length() > 1.0:
		var s := node.scale
		node.basis = Basis.looking_at(dv.normalized(), Vector3.UP if absf(dv.normalized().y) < 0.99 else Vector3.RIGHT).scaled(s)


## FUN_004d6130 for a falling store: one area blast (bdb power / radius) over every unit, the
## explosion of the ballistic class (FUN_0059df20, class 0x16 / 0x19): on water a splash; 510 the
## cluster (0x2000, radius 100, 3 s: 48 small fires in 3 rings, every second one smoking); else
## 0x4008 (flash, smoke streamers, column); low bursts are drawn at the ground. Sound
## SFX_WEAPON_EXPLODED of the store's OST.
func _bomb_detonate(bm: Dictionary, p: Vector3) -> void:
	var w: Dictionary = bm.w
	var me: Dictionary = bm.get("owner", _me())
	var hit := []
	if host.runtime != null and not me.is_empty() and float(w.power) > 0.0:
		hit = host.runtime.area_damage(p, float(w.power), float(w.radius), me, "bomb")
	var type := int(w.type)
	_explosion_effect(p, type)
	_place_sound(host.sounds.play("SFX_WEAPON_EXPLODED", OST.get(type, "OST_BOMB")), p)
	if not hit.is_empty():
		_place_sound(host.sounds.play("SFX_WEAPON_HIT_TARGET"), p)
	if bm.node != null:
		bm.node.queue_free()
	if bm.sound != null:
		host.sounds.stop(bm.sound)


## The weapon explosion of FUN_0059df20 by type; `p` world.
func _explosion_effect(p: Vector3, type: int) -> void:
	var sp := to_scene(p)
	var g = host.terrain.height_at(sp)
	var gy: float = g if g != null else sp.y
	var low := sp.y < gy + 10.5
	if low and sp.y < gy:
		sp.y = gy
	var water: bool = (host.terrain.surface_at(sp) & host.terrain.SURFACE_WATER) != 0
	if water and low:
		host.effects.smoke_puff(sp, true)  # splash 0x60000 (look UNCERTAIN, as the gun's)
		return
	match type:
		510:
			host.effects.explosion(sp, DamageEffects.F_CLUSTER, 4.0, 3.0, gy, 100.0)
		560:
			var f := DamageEffects.F_FIREBALL | (DamageEffects.F_KICK | DamageEffects.F_SMOKE_TRAILS if low else 0)
			host.effects.explosion(sp, f, 4.0, 95.0, gy)
		_:
			host.effects.explosion(sp, DamageEffects.F_FLASH | DamageEffects.F_SMOKE_TRAILS, 4.0, 95.0, gy)


## A rocket's end (FUN_004d6130): hit sphere 0, so at the terrain or at its aim; the blast over every
## unit around, the fixed-weapon explosion (0x10, low 0x98), SFX_WEAPON_EXPLODED / OST_ROCKET.
func _rocket_detonate(r: Dictionary, pos: Vector3, _cands, _hit: Dictionary) -> void:
	var k := -1
	for j in rockets.pool.size():
		if is_same(rockets.pool[j], r):
			k = j
	var e: Dictionary = _rocket_nodes.get(k, {})
	_rocket_nodes.erase(k)
	var w: Dictionary = e.get("w", {"power": 0.0, "radius": 0.0, "type": 560})
	var me := _me()
	if host.runtime != null and not me.is_empty() and float(w.power) > 0.0:
		host.runtime.area_damage(pos, float(w.power), float(w.radius), me, "rocket")
	rocket_effect(pos)
	if e.get("node") != null:
		e.node.queue_free()


## A rocket's burst at world point `pos` (also the ground units' rockets).
func rocket_effect(pos: Vector3) -> void:
	_explosion_effect(pos, 560)
	_place_sound(host.sounds.play("SFX_WEAPON_EXPLODED", "OST_ROCKET"), pos)


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
			var g = host.mission_ground(Vector3(arg.x, arg.y, 0.0))
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
	if lock_threat_fix:
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
		# The record keeps no unit once its unit left the list (destroyed / hidden this frame): no closure then.
		closure = (o.vel - (lk.unit.vel as Vector3)).dot(d) if lk.has("unit") else 0.0
	return {"mode": radar.mode, "idx": radar.range_index(), "width": radar.scope_width(),
		"shift": radar.heading_shift, "antenna": radar.antenna, "contacts": radar.contacts,
		"lock": lk, "closure": closure, "has_lock": not lk.is_empty(),
		"exp": radar.exp, "designated": radar.designated, "dlz": s348}


# --- chaff and flares (events 0x44 / 0x45, docs/weapons.md §10) ------------------------------------

## A decoy ends when it reaches its aim point A, at most 4.0 s after its release (FUN_004d7690: the
## motion's time left (+0x78 - now) capped at 4.0, _DAT_00605120); its pool object is busy until then.
const DECOY_LIFE := 4.0
## Decoys in the air: {type, r (round record of the decoy motion), end}.
var decoys: Array = []
## Every decoy released, by id (a missile chasing one keeps its key "decoy:<id>"; the record stays after the decoy
## ends: the pool object sits where it ended).
var _decoy_by_id := {}
var _decoy_id := 0
## Their look (decoy_fx.gd).
var decoy_fx: Node3D
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
	var st: Dictionary = host.flight.state() if host.flight != null else {}
	if not release_decoy(type, body_to_world(stores.station(i).attach), own(), String(_me().get("key", "")),
			int(st.get("afterburner", 0)) > 0, float(st.get("g", 1.0))):
		return false
	stores.consume(i)
	return true


## One decoy (FUN_004545e0 → FUN_00454b70, the player's or an AI jet's: one ring pool per jet, `_maxNumInAir` 15) from
## `p0` with the jet's pose `o` {pos, vel, fwd, up, right}; `key` the releasing jet, `ab` its afterburner lit, `g`
## its load factor (the decoy rule). False when the pool object is still alive.
func release_decoy(type: int, p0: Vector3, o: Dictionary, key: String, ab: bool, g_load: float) -> bool:
	var pool_key := "%s:%d" % [key, type]
	if not _decoy_motion.has(type):
		var w: Dictionary = stores.station(10 if type == Stores.CHAFF else 11).get("w", {})
		var m: Dictionary = db.motion_for(type, 0).duplicate()
		m.merge(w.get("motion", {}), true)
		var gr := GunRounds.new()
		gr.configure(m)
		_decoy_motion[type] = gr
	if not _decoy_pool.has(pool_key):
		_decoy_pool[pool_key] = []
		for k in maxi(int(db.motion_for(type, 0).get("_maxNumInAir", 15)), 1):
			_decoy_pool[pool_key].append(-INF)
		_decoy_next[pool_key] = 0
	var g: RefCounted = _decoy_motion[type]
	var k: int = _decoy_next[pool_key]
	if now < float(_decoy_pool[pool_key][k]):
		return false  # that pool object is still alive (w+0x48)
	_decoy_next[pool_key] = (k + 1) % _decoy_pool[pool_key].size()
	# Aim point: the _fireEndVec in body axes (0, -200, -10: 200 m aft, 10 m below; composition UNCERTAIN).
	var m2: Dictionary = db.motion_for(type, 0)
	var fe := Vector3(m2.get("_fireEndVecX", 0.0), m2.get("_fireEndVecY", -200.0), m2.get("_fireEndVecZ", -10.0))
	var a: Vector3 = p0 + o.right * fe.x + o.fwd * fe.y + o.up * fe.z
	# The fixed-weapon flight (FUN_005605c0 -> FUN_0047a1e2, as a gun round): |V| + velocityJump along
	# the line to A, decelerating at 50 m/s², then at A. No hit sphere (_spiralAccel 0): no damage.
	var r: Dictionary = g.flight(now, p0, (o.vel as Vector3).length() + g.velocity_jump, a)
	var end: float = minf(r.t_end, now + DECOY_LIFE)
	_decoy_pool[pool_key][k] = end
	_decoy_id += 1
	var dc := {"type": type, "r": r, "end": end, "id": _decoy_id}
	decoys.append(dc)
	_decoy_by_id[_decoy_id] = dc
	var ost := "OST_CHAFF" if type == Stores.CHAFF else "OST_FLARE"
	_place_sound(host.sounds.play("SFX_AIRCRAFT_FIRED_WEAPON", ost), p0)
	_decoy_effect(type, _decoy_id, key, ab, g_load)
	return true


## The decoy rule (FUN_00454b70, chaff @455775 / flare @455968): over the missiles launched at the releasing jet (its
## RWR missile list, by launch distance; every aircraft has one), not already chasing a decoy and of the decoy's kind
## (chaff: 600 / 610 / 630; flares: 570 / 580 / 620), roll rand against p (chaff 0.1, above 4 g 0.3; flares 0.33,
## above 4 g 0.5, none with the afterburner lit); a success retargets the missile at the decoy (FUN_004d83c0 →
## FUN_005622e0), the first failure ends the scan (quirk). The bearing gates compare radians with degrees × 57.3: never
## taken. The player's list empties with RWR damage (flag 14).
const DECOY_KINDS := {540: [600, 610, 630], 550: [570, 580, 620]}


func _decoy_effect(type: int, dc_id: int, key: String, ab: bool, g_load: float) -> void:
	if key == String(_me().get("key", "")) and _flag(14):
		return
	var list := missiles.filter(func(m): return String(m.target_key) == key)
	list.sort_custom(func(a, b): return float(a.get_meta("dist", 0.0)) < float(b.get_meta("dist", 0.0)))
	for mis in list:
		if not int(mis.weapon.get("type", 0)) in DECOY_KINDS[type]:
			continue
		var p := (0.3 if g_load > 4.0 else 0.1) if type == Stores.CHAFF else (0.0 if ab else (0.5 if g_load > 4.0 else 0.33))
		if (type == Stores.FLARE and ab) or randf() > p:
			break
		mis.retarget("decoy:%d" % dc_id)


func _update_decoys() -> void:
	if decoy_fx == null:
		decoy_fx = preload("res://weapons/decoy_fx.gd").new()
		decoy_fx.effects = host.get("effects")
		host.add_child(decoy_fx)
	decoy_fx.update(now, decoys, func(dc, t): return to_scene(_decoy_motion[dc.type].position(dc.r, t)))
	decoys = decoys.filter(func(dc): return now < dc.end)


## A decoy's world position now.
func decoy_position(dc: Dictionary) -> Vector3:
	return _decoy_motion[dc.type].position(dc.r, now)


# --- every frame ------------------------------------------------------------------------------------

## Advances the weapons to sim time `t`.
func update(t: float) -> void:
	now = t
	if _bay_retry:
		_bay_retry = false
		_release_missile()
	if stores.releases != _releases:
		_releases = stores.releases
		if _internal(stores.last_fired):
			_bay_until = now + BAY_HOLD
	while firing and _gun_next <= now:
		_gun_shot()  # catch-up shots share the timestamp
		_gun_next += GUN_PERIOD
	gun.update(now)
	if hud_mode in [5, 6]:
		_update_ag()
	while _ripple_next <= now:
		_ripple_next += ripple_period
		_ripple_tick()
	_update_bombs()
	_update_missiles()
	_update_guided()
	_update_decoys()
	# Radar damage (15; generator failures 19 / 21 set it too): FUN_004adb20 switches it off for good.
	if _flag(15) and not radar.damaged:
		radar.set_damaged(true)
	radar.update(now)
	rwr.damaged = _flag(14)
	var refreshed: bool = now >= rwr._next_refresh
	rwr.update(now)
	if harm.active and (refreshed or harm.list.is_empty()):
		_harm_capture()
	_eo_update()
	# FUN_00461680: an A-A radar lock slaves the IR seeker (any lock clears the seeker's own target).
	seeker.radar_key = String(radar.locked().get("key", ""))
	seeker.radar_aa = radar.aa
	if hud_mode == 1:
		var st: Dictionary = stores.station(stores.cur)
		seeker.update(now, own(), _units(), int(st.get("w", {}).get("type", 0)), _station_has_rounds())
	# The AA gun LCOS (mode 3): the lock's range, else 450 m; out of mode 3 its rate filters restart.
	if hud_mode == 3 and host.flight != null:
		var lk: Dictionary = radar.locked()
		lcos.step(now, host.flight.state(), lk.dist if not lk.is_empty() else null)
	else:
		lcos.reset()
	_update_cockpit_dlz()
	_update_visuals()
	_publish()


## The cockpit's DLZ and weapon time (FUN_00456520, every frame while the radar has a lock / TWS selection or
## the HARM sensor a target; otherwise both keep their last values): S+0x348.. = the selected store's DLZ
## [max, min] at the radar's target (without one: the DLZ with no target), S+0x380 = the time left of the last
## launched weapon (not decoys / gun / pods: FUN_0053bec0, its motion's vfunc +0x80 clamped by FUN_004d6ac0:
## below 0 → 0, above 300 → 60).
var s348: Array = []
var s380 := 0.0
var harm_in_range := false
## The last launched weapon (a homing missile; FUN_0053bec0 → station +0x24).
var last_launched: RefCounted


func _update_cockpit_dlz() -> void:
	if not (radar.has_lock() or (harm.active and harm.selected != "")):
		return
	var o := own()
	var target := {}
	var lk: Dictionary = radar.locked()
	if not lk.is_empty():
		var u := _unit(_units(), String(lk.key))
		target = u if not u.is_empty() else {"pos": lk.pos, "vel": Vector3.ZERO}
	s348 = selected_dlz(o, target)
	s380 = 0.0
	if last_launched != null:
		s380 = ClassDB.class_call_static("IafRelease", "shown_time", last_launched.time_left(now))


## state+0x4c (FUN_00429390 ← FUN_0044e770): the locked target's bearing from the own heading (rad, wrapped
## ±π; the caret on the missile circle); null without a lock.
func _lock_bearing(o: Dictionary) -> Variant:
	var lk: Dictionary = radar.locked()
	if lk.is_empty():
		return null
	return ClassDB.class_call_static("IafRelease", "lock_bearing", o.pos, float(o.yaw), lk.pos)


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
	var counts: Array = stores.missile_counts()
	var srm: int = counts[0]
	var mrm: int = counts[1]
	var o := own()
	# The MRM / HARM HUD objects (FUN_00460ee0 / FUN_00460ac0): the circle, the predicted point (with a radar
	# lock), the shoot cue (state+0x1010: inside the circle, rounds left, the radar in A-A, min ≤ dist ≤ max) and
	# the HARM's "In Range" (dist < the DLZ max) and its target point (state+0xe6c, the HUD diamond).
	var circle := 5.0
	var mrm_pt = null
	var shoot := false
	var harm_pt = null
	if hud_mode in [2, 8]:
		var sg := _sight(o, _units())
		var have: bool = stores.total(t, stores.current_name()) > 0
		if hud_mode == 2:
			circle = float(sg.r)
			if sg.pred != null and radar.has_lock():
				mrm_pt = sg.pred
				var hud_only: bool = host.get("views") != null and host.views.type == Views.HUD_ONLY
				var inside: bool = MrmSight.in_circle(IrSeeker.screen_offset(o, sg.pred), sg.r, hud_only)[0]
				shoot = ClassDB.class_call_static("IafRelease", "shoot_cue", inside, have, radar.aa, sg.dlz, float(sg.dist))
		elif not sg.target.is_empty():
			harm_pt = sg.target.pos
			harm_in_range = ClassDB.class_call_static("IafRelease", "harm_in_range", have, sg.dlz, float(sg.dist))
		if sg.target.is_empty():
			harm_in_range = false
	if hud_mode != 8:
		harm_in_range = false
	var pip = null
	if hud_mode == 3:
		pip = lcos.offset() * rad_to_deg(1.0) * 12.0  # px from the gun cross
	elif hud_mode == 4:
		var d: Vector3 = GunRounds.shot_dir(o.fwd, o.up)
		pip = gun.aim_point(o.pos, o.vel, d, true)  # world point, projected by the HUD
	c.radar = radar_snapshot()
	c.eo = {"mode": eo.mode, "camera": eo.camera, "fov": eo.FOV_DEG / eo.zoom, "flir": eo.flir_page(eo_ae,
		(eo_centre - o.pos).length()), "tv": eo.tv_page(eo_ae, tv_status()), "tv_time": tv_time(), "flir_pod": flir_pod}
	c.harm = harm.page(_base(o), stores.total(stores.current_type(), stores.current_name()), harm_in_range)
	c.rwr = rwr.display()
	c.indicators[Rwr.LAMP_AI] = rwr.lamps[Rwr.LAMP_AI]
	c.indicators[Rwr.LAMP_SAM] = rwr.lamps[Rwr.LAMP_SAM]
	c.weapons = {
		"hud_mode": hud_mode, "master": master, "stations": list, "selected": stores.cur,
		"name": stores.current_name(), "type": t, "total": stores.total(t, stores.current_name()),
		"ready": not mal, "srm": srm, "mrm": mrm, "gun": stores.displayed(9),
		"chaff": stores.displayed(10), "flares": stores.displayed(11),
		"quantity": ripple_qty, "interval": ripple_int, "seeker": seeker.symbol, "lock": seeker.lock,
		"have_missiles": stores.total(t, stores.current_name()) > 0, "circle": circle, "mrm_point": mrm_pt,
		"shoot": shoot, "harm_point": harm_pt, "tv_point": eo_centre if hud_mode == 7 and tv_status() != 0 else null, "sec": s380, "bearing": _lock_bearing(o),
		"pipper": pip, "pipper_world": hud_mode == 4, "firing": firing,
		# The mode-5 object's cockpit state (FUN_00445db0: +0x620 off, +0x624 point, +0x638 time-to-go
		# capped at 1000, +0x62c frozen, +0x630 blinking).
		"ag": {"pipper": ag.pipper if hud_mode in [5, 6] else null, "off": ag.off, "frozen": ag.frozen,
			"ttg": ClassDB.class_call_static("IafRelease", "ttg_shown", float(ag.ttg)), "blink": now < float(ag.blink_until)},
	}


# --- visuals ----------------------------------------------------------------------------------------

func _instance(path: String) -> Node3D:
	if path == "":
		return null
	var model = preload("res://util/gltf.gd").object(path)
	if model == null:
		return null
	return preload("res://util/gltf.gd").instance(model)


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
	# Rockets (560): one "Rocket box" per pylon (FUN_0053c1f0: object 0x753d, weapons\\Lau61\\Lau61_m,
	# [Weapons] RocketBoxScale 4.0 instead of the stores' Present scale 2) at the attach point; it stays
	# when empty (UNCERTAIN).
	for i in stores.stations:
		var st: Dictionary = stores.stations[i]
		if i < 9 and stores.type_of(i) == 560 and host.aircraft != null:
			var n := _instance(ROCKET_BOX)
			if n != null:
				host.aircraft.add_child(n)
				n.position = st.attach
				n.scale = Vector3.ONE * ROCKET_BOX_SCALE / STORE_PRESENT_SCALE  # the stores ride on the jet's scale
				_pod_nodes.append(n)
	_update_store_nodes()


## The weapon bays' doors are commanded open (a release from a bay station in the last BAY_HOLD s).
func bay_open() -> bool:
	return now < _bay_until


## Ours: a release from bay station i opens the doors (and keeps them open); true while they are not fully open.
func _bay_wait(i: int) -> bool:
	if not _internal(i):
		return false
	_bay_until = maxf(_bay_until, now + BAY_HOLD)
	return host.aircraft != null and host.aircraft.bay_fraction() < 1.0


## Station i is in a weapon bay (descriptor `internal_stations`, letters A..I; ours).
func _internal(i: int) -> bool:
	return i >= 0 and i < 9 and "ABCDEFGHI"[i] in String(descriptor.get("internal_stations", ""))


## Stations 0..8 draw `count` stores at slot[0..count−1] (FUN_0053e430) with EXTERNAL STORES on
## and within 9000 m of the camera. Ours: a bay station's stores only while its doors are half open.
func _update_store_nodes() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var near := cam == null or host.rig == null or cam.global_position.distance_to(host.rig.global_position) < STORES_DRAW_DIST
	var bay_shown: bool = host.aircraft != null and host.aircraft.bay_fraction() > 0.5
	for i in _store_nodes:
		var n := int(stores.station(i).get("count", 0))
		for k in _store_nodes[i].size():
			_store_nodes[i][k].visible = Settings.external_stores and near and k < n and (bay_shown or not _internal(i))
	for b in _pod_nodes:
		b.visible = Settings.external_stores and near


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
			var du := Terrain.dir_to_scene(u)
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
