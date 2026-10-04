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

var _m = ClassDB.instantiate("IafMissile")
var _s := {}


## Launch (FUN_004d5d10 -> FUN_00561ef0): motion record `m` (weapons.ibx, with the weapon's Real overrides), launch
## position / velocity / nose, and q (FUN_00457f70); `target` "" = aim at `point`; `debug` = db.debug_param.
func launch(w: Dictionary, m: Dictionary, now: float, pos: Vector3, vel: Vector3, nose: Vector3, target: String, point: Vector3, q: float, debug: Callable, up := Vector3.ZERO) -> void:
	weapon = w
	_m.launch(m, float(w.get("real_max_g", 0.0)), now, pos, vel, nose, up, target, point, q, debug)
	_s = _m.state()


func position(now: float) -> Vector3:
	return _m.position(now)


func velocity(now: float) -> Vector3:
	return _m.velocity(now)


## One update (FUN_005627e0). `t_pos` / `t_vel` = the target now (ignored without one), `ground` = terrain height
## under a point. Returns true when the missile ends (detonate at `last_pos`).
func update(now: float, t_pos: Vector3, t_vel: Vector3, ground: Callable) -> bool:
	var end: bool = _m.update(now, t_pos, t_vel, ground)
	_s = _m.state()
	return end


## FUN_005622e0 (a decoy taking the missile): a new target.
func retarget(key: String) -> void:
	_m.retarget(key)
	_s = _m.state()


## The motion's time left (FUN_00468db0): burn − age.
func time_left(now: float) -> float:
	return _m.time_left(now)


## FUN_005627b0: the distance flown in t seconds from speed s.
static func flown(m: Dictionary, s: float, t: float) -> float:
	return ClassDB.class_call_static("IafMissile", "flown", m, s, t)


## The DLZ (FUN_005624f0) of motion record `m` from a launcher {pos, fwd, vel} at a target {pos, vel} ({} none):
## [max, min] metres.
static func dlz(m: Dictionary, own: Dictionary, target: Dictionary) -> Array:
	return ClassDB.class_call_static("IafMissile", "dlz", m, own, target)
