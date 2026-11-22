# One homing weapon in flight (class 0x18: IR 570 / 580, HARM 590, radar 600 / 610, Maverick 635, the SAMs
# 620 / 630; docs/weapons.md §5, §11): the original's chase motion. The logic is iaf_avionics::missile
# (crates/iaf-avionics/src/missile.rs) through IafMissile; this keeps the GDScript face. Launcher and scene
# independent: world frame X east, Y north, Z up, metres, sim seconds. The host supplies the target position /
# velocity and the terrain height.
extends RefCounted

var weapon: Dictionary  # weapon_db record
## +0x148: guidance off (the semi-active missiles losing the radar, FUN_00458130; ECM, FUN_004582f0).
var guidance_off: bool:
	get:
		return _m.guidance_off()
	set(v):
		_m.set_guidance_off(v)
var target_key: String:
	get:
		return _s.get("target_key", "")
var has_target: bool:
	get:
		return _s.get("has_target", false)
var aim_point: Vector3:
	get:
		return _s.get("aim_point", Vector3.ZERO)
var t0: float:
	get:
		return _s.get("t0", 0.0)
var p0: Vector3:
	get:
		return _s.get("p0", Vector3.ZERO)
var v0: Vector3:
	get:
		return _s.get("v0", Vector3.ZERO)
var acc: Vector3:
	get:
		return _s.get("acc", Vector3.ZERO)
## The burst point at the end.
var last_pos: Vector3:
	get:
		return _s.get("last_pos", Vector3.ZERO)
var next_update: float:
	get:
		return _s.get("next_update", 0.0)
var ended: bool:
	get:
		return _s.get("ended", false)
## The physical missile ended before its fuze armed: no burst (docs/real-weapons.md §2.5).
var dud: bool:
	get:
		return _s.get("dud", false)

var _m = ClassDB.instantiate("IafMissile")
var _s := {}


## Launch (FUN_004d5d10 -> FUN_00561ef0): motion record `m` (weapons.ibx, with the weapon's Real overrides), launch
## position / velocity / nose, and q (FUN_00457f70); `target` "" = aim at `point`; `debug` = db.debug_param.
func launch(
	w: Dictionary,
	m: Dictionary,
	now: float,
	pos: Vector3,
	vel: Vector3,
	nose: Vector3,
	target: String,
	point: Vector3,
	q: float,
	debug: Callable,
	up := Vector3.ZERO
) -> void:
	weapon = w
	var shot := {"pos": pos, "vel": vel, "nose": nose, "up": up, "target": target, "point": point, "q": q}
	# The physical missile's seeker in flight (docs/real-weapons.md §2.2): its cone, generation and type.
	shot.merge({"generation": int(w.get("generation", 0)), "type": int(w.get("type", 0))})
	# Modern IAF's proximity fuze on the physical missile (docs/real-weapons.md §2.5): the warhead's radius.
	if Settings.modern_fuzes():
		shot["radius"] = float(w.get("radius", 0.0))
	if w.has("real_cone_deg"):
		shot["real_cone_deg"] = float(w.real_cone_deg)
	_m.launch(m, float(w.get("real_max_g", 0.0)), now, shot, debug)
	_s = _m.state()


func position(now: float) -> Vector3:
	return _m.position(now)


func velocity(now: float) -> Vector3:
	return _m.velocity(now)


## One update (FUN_005627e0). `t_pos` / `t_vel` = the target (ignored without one) as of sim time `t_at`, `ground` =
## terrain height under a point. Returns true when the missile ends (detonate at `last_pos`).
func update(now: float, t_pos: Vector3, t_vel: Vector3, t_at: float, ground: Callable) -> bool:
	var end: bool = _m.update(now, t_pos, t_vel, t_at, ground)
	_s = _m.state()
	return end


## FUN_005622e0 (a decoy taking the missile): a new target.
func retarget(key: String) -> void:
	_m.retarget(key)
	_s = _m.state()


## Ours, Modern IAF: the chance a decoy released now takes the seeker (ecm.rs decoy_chance): `flare` (else chaff),
## `ir` an infrared seeker, the target `t` {pos, vel, ab (its afterburner lit), g (its load factor)}.
func decoy_chance(flare: bool, ir: bool, now: float, t: Dictionary) -> float:
	return _m.decoy_chance(flare, ir, now, t)


## The motion's time left (FUN_00468db0): burn − age.
func time_left(now: float) -> float:
	return _m.time_left(now)


## The launcher's radar still tracks the target: the data link's mid-course updates (docs/real-weapons.md §2.2).
func set_link(on: bool) -> void:
	_m.set_link(on)


## The motor's time left (the smoke trail): the physical missile's burn less its age, else time_left.
func motor_left(now: float) -> float:
	return _m.motor_left(now)


## Ours, the post-launch cues (modern-iaf/docs/weapons.md §8.2): {active, impact} seconds at the target {t_pos, t_vel},
## the seeker going active at `active_range` m (0 none); each null when none.
func times(now: float, t_pos: Vector3, t_vel: Vector3, active_range: float) -> Dictionary:
	return _m.times(now, t_pos, t_vel, active_range)


## FUN_005627b0: the distance flown in t seconds from speed s.
static func flown(m: Dictionary, s: float, t: float) -> float:
	return ClassDB.class_call_static("IafMissile", "flown", m, s, t)


## The DLZ (FUN_005624f0) of motion record `m` from a launcher {pos, fwd, vel} at a target {pos, vel} ({} none):
## [max, min] metres.
static func dlz(m: Dictionary, own: Dictionary, target: Dictionary) -> Array:
	return ClassDB.class_call_static("IafMissile", "dlz", m, own, target)
