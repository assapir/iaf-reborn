# One guided weapon in flight (class 0x19: the TV missile 640, the laser bomb 650; docs/weapons.md §12): the
# original's guided motion. The logic is iaf_avionics::guided (crates/iaf-avionics/src/guided.rs) through
# IafGuided; this keeps the GDScript face. It flies to an aim POINT. World frame X east, Y north, Z up, metres,
# sim seconds.
extends RefCounted

var weapon: Dictionary  # weapon_db record
## +0x70: 0 far, 1 near, 2 terminal (the aim is frozen).
var mode: int:
	get:
		return _s.get("mode", 0)
var aim: Vector3:
	get:
		return _s.get("aim", Vector3.ZERO)
var last_pos: Vector3:
	get:
		return _s.get("last_pos", Vector3.ZERO)
var next_update: float:
	get:
		return _s.get("next_update", 0.0)
var ended: bool:
	get:
		return _s.get("ended", false)

var _g = ClassDB.instantiate("IafGuided")
var _s := {}


## FUN_00563d30 + FUN_00563f90: motion record `m` (weapons.ibx), the release point / velocity, the aim point;
## `debug` = db.debug_param.
func launch(w: Dictionary, m: Dictionary, now: float, pos: Vector3, vel: Vector3, point: Vector3, debug: Callable) -> void:
	weapon = w
	_g.launch(m, now, pos, vel, point, debug)
	_s = _g.state()


func position(now: float) -> Vector3:
	return _g.position(now)


func velocity(now: float) -> Vector3:
	return _g.velocity(now)


## FUN_00469f00: a new aim point, ignored in mode 2.
func set_aim(p: Vector3) -> void:
	_g.set_aim(p)
	_s = _g.state()


## FUN_004d8030: 2 TRA (mode 0), 3 TER.
func status() -> int:
	return 3 if mode != 0 else 2


## FUN_00564f10: |aim − position| / speed, at most 280 s.
func time_left(now: float) -> float:
	return _g.time_left(now)


## One update (FUN_005643a0). `ground` = terrain height under a point. Returns true when the weapon ends (burst at
## `last_pos`).
func update(now: float, ground: Callable) -> bool:
	var end: bool = _g.update(now, ground)
	_s = _g.state()
	return end


## The DLZ (FUN_005641c0) from `agl` above the terrain at `vel`: [range, range].
static func dlz(m: Dictionary, agl: float, vel: Vector3, debug: Callable) -> Array:
	return ClassDB.class_call_static("IafGuided", "dlz", m, agl, vel, debug)
