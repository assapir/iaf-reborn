# A fixed weapon's rounds (docs/weapons.md §3): the gun, rockets and decoys. The logic is iaf_avionics::gun
# (crates/iaf-avionics/src/gun.rs) through IafRounds; this keeps the GDScript face: the owner sets the callbacks,
# fires and updates, and reads `pool` (one record per slot, kept for the slot's life: {flying, p0, u, s, t0,
# t_end, A, cands, hit_r}). World frame X east, Y north, Z up, metres, sim seconds.
extends RefCounted

## Callbacks set by the owner: units() -> [{key, pos: Vector3 world}], ground(p) -> height or null,
## detonate(round, pos, hit_units: Array or null, hit_unit or {}) — null = the area query.
var units: Callable
var ground: Callable
var detonate: Callable

var pool: Array = []
## The motion's _velocityJump (the decoys' launch speed over the jet's).
var velocity_jump := 1200.0

var _r = ClassDB.instantiate("IafRounds")
var _by_key := {}


## The motion of a weapons.ibx section; an empty pool.
func configure(m: Dictionary) -> void:
	_r.configure(m)
	velocity_jump = _r.velocity_jump()
	pool.clear()
	_sync()


## The shot line (FUN_00456ff0): the nose 1° up for the player.
static func shot_dir(nose: Vector3, up: Vector3, elevate := true) -> Vector3:
	return ClassDB.class_call_static("IafRounds", "shot_dir", nose, up, elevate)


## The aim point A: HUD mode 4 (AG gun) leads with gravity; any other mode 2781 m down the shot line.
func aim_point(p: Vector3, vel: Vector3, d: Vector3, ag_mode: bool) -> Vector3:
	return _r.aim_point(p, vel, d, ag_mode)


## The flight from `p0` at speed `s` to `a` from `t0` (the decoys): {p0, u, s, t0, t_end, A}.
func flight(t0: float, p0: Vector3, s: float, a: Vector3) -> Dictionary:
	return _r.flight(t0, p0, s, a)


## A record's position at `now`.
func position(r: Dictionary, now: float) -> Vector3:
	return _r.position(r, now)


## The next pooled round is free (a busy one skips the shot, no ammo used).
func next_free() -> bool:
	return _r.next_free()


## One shot (FUN_00456d40 after the ammo checks): `p` jet origin, `muzzle` launch point, `vel` jet velocity, `a`
## aim point, `locked` the radar-locked unit key ("" none), `me` the shooter, `easy` Easy aiming. Returns the
## round's pool slot, −1 when the pooled round is busy.
func fire(now: float, p: Vector3, muzzle: Vector3, vel: Vector3, a: Vector3, locked: String, me: String, easy: bool) -> int:
	var b := _bodies()
	var slot: int = _r.fire(now, p, muzzle, vel, a, locked, me, easy, b[0], b[1])
	_sync()
	return slot


## Advances the rounds to `now`; each detonation is handed to `detonate` before the next check sees the units.
func update(now: float) -> void:
	while flying_count() > 0:
		var b := _bodies()
		var d: Dictionary = _r.step(now, b[0], b[1], ground)
		_sync()
		if d.is_empty():
			return
		var r: Dictionary = pool[d.slot]
		match d.hit:
			"unit":
				detonate.call(r, d.pos, Array(d.candidates), _by_key.get(d.key, {}))
			"ground":
				detonate.call(r, d.pos, null, {"ground": true})
			_:
				detonate.call(r, d.pos, null, {})


func flying_count() -> int:
	return pool.filter(func(r): return r.flying).size()


## [keys, positions] of the units now.
func _bodies() -> Array:
	var keys := PackedStringArray()
	var pos := PackedVector3Array()
	_by_key = {}
	for u in (units.call() if units.is_valid() else []):
		keys.append(u.key)
		pos.append(u.pos)
		_by_key[u.key] = u
	return [keys, pos]


## The pool records follow the slots in place (a landed round keeps its last flight, flying = false).
func _sync() -> void:
	var slots: Array = _r.slots()
	pool.resize(slots.size())
	for i in slots.size():
		if pool[i] == null:
			pool[i] = {"flying": false}
		pool[i].flying = not slots[i].is_empty()
		pool[i].merge(slots[i], true)
