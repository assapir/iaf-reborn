# The gun's rounds (docs/weapons.md §3): the aim, the candidate list, the analytic trajectory, the
# 0.1 s hit checks and the detonation, as the original (FUN_00456d40, FUN_00456ff0, FUN_004577c0,
# FUN_005605c0, FUN_0047a491, FUN_00560710, FUN_004d6130). Scene independent: world frame X east,
# Y north, Z up, metres, sim seconds. The host supplies the units (`units()`), the terrain height and
# the damage / effect callbacks.
extends RefCounted

## v1.1 (FUN_00456ff0): the player's shot line is the nose pitched 1° up (v1.0: the nose).
const GUN_ELEVATION_DEG := 1.0
## Aim distance without the AG lead (2781.0 @0x600f5c; v1.0 1854.0).
const AIM_DISTANCE := 2781.0
## AG gun (HUD mode 4) lead: gravity ½g (4.903 @0x601414) over _limitDist / _limitVel.
const HALF_G := 4.903
## Candidate query radius = 10·|A − P| (0x600f60); a locked target counts within 2·|A − P| (4.0 @0x600f18).
const QUERY_FACTOR := 10.0
const LOCK_FACTOR_SQ := 4.0
## At most 10 candidates per round (aim buffer +0x24..).
const MAX_CANDIDATES := 10
## The candidate gate (FUN_004d3fa0(0, 0.5, 0) @453ccf): no list within 0.5 s after the last one.
const LIST_GATE := 0.5
## Hit sphere = _spiralAccel × 0.5 (0x60cdb4) unless Easy aiming (v1.1; v1.0 always the full value).
const EASY_OFF_FACTOR := 0.5
## Aim points farther than 30 km are pulled in (0x602a90).
const MAX_RANGE := 30000.0
## The blast query at a ground / end-of-flight detonation: |c − p|² < (r + radius + 20)²·3 (0x604e6c).
const QUERY_PAD := 20.0

## Motion data of weapons.ibx [WEAPON019] (type 565): accel, limit velocity, velocity jump, check
## period, hit distance.
var abs_accel := -10.0
var limit_vel := 1200.0
var limit_dist := 4500.0
var velocity_jump := 1200.0
var check_period := 0.1
var hit_distance := 50.0
var pool_size := 20

## Callbacks set by the owner: units() -> [{key, pos: Vector3 world}], ground(p) -> height or null,
## detonate(round, pos, hit_units: Array or null, hit_unit or {}) — null = the area query.
var units: Callable
var ground: Callable
var detonate: Callable

## The ring pool (FUN_004d8760): [{flying, p0, u, s, t0, t_end, A, cands, next_check, hit}].
var pool: Array = []
var _next := 0
var _gate_t0 := 1.0e7


func configure(m: Dictionary) -> void:
	abs_accel = float(m.get("_absAcceleration", abs_accel))
	limit_vel = float(m.get("_limitVel", limit_vel))
	limit_dist = float(m.get("_limitDist", limit_dist))
	velocity_jump = float(m.get("_velocityJump", velocity_jump))
	check_period = float(m.get("_timeConstOrientation", check_period))
	hit_distance = float(m.get("_spiralAccel", hit_distance))
	pool_size = int(m.get("_maxNumInAir", pool_size))
	pool.clear()
	for i in pool_size:
		pool.append({"flying": false})
	_next = 0


## The shot line (FUN_00456ff0): the nose rotated 1° up about the right wing (Rodrigues about
## K = N × U), for the player only.
static func shot_dir(nose: Vector3, up: Vector3, elevate := true) -> Vector3:
	if not elevate:
		return nose
	var k := nose.cross(up).normalized()
	return nose.rotated(k, deg_to_rad(GUN_ELEVATION_DEG)) if k.length() > 0.5 else nose


## The aim point A: HUD mode 4 (AG gun) leads with the round's flight time _limitDist / _limitVel and
## gravity; any other mode aims 2781 m down the shot line.
func aim_point(p: Vector3, vel: Vector3, d: Vector3, ag_mode: bool) -> Vector3:
	if ag_mode:
		var t := limit_dist / limit_vel
		return p + (vel + velocity_jump * d) * t - Vector3(0, 0, HALF_G * t * t)
	return p + AIM_DISTANCE * d


## The next pooled round, or {} when it is still flying (the shot is skipped, no ammo used).
func next_round() -> Dictionary:
	if pool.is_empty():
		return {}
	var r: Dictionary = pool[_next]
	return {} if r.flying else r


## One shot (FUN_00456d40 after the ammo checks): `p` jet origin, `muzzle` launch point, `vel` jet
## velocity, `d` shot line, `a` aim point, `locked` the radar-locked unit key ("" = none), `me` the
## shooter key, `easy` Easy aiming. Returns false when the pooled round is busy.
func fire(now: float, p: Vector3, muzzle: Vector3, vel: Vector3, a: Vector3, locked: String, me: String, easy: bool) -> bool:
	var r := next_round()
	if r.is_empty():
		return false
	_next = (_next + 1) % pool.size()
	r.cands = _candidates(now, p, a, locked, me)
	r.hit_r = hit_distance * (1.0 if easy else EASY_OFF_FACTOR)
	# Solver FUN_0047a491: speed = |own velocity| + velocityJump along the line to A, decelerating
	# at _absAcceleration; ends at A.
	var s := vel.length() + velocity_jump
	var dd := a - muzzle
	var dist := dd.length()
	var u := dd / dist if dist > 0.0 else Vector3(0, 1, 0)
	if dist > MAX_RANGE:
		a = muzzle + MAX_RANGE * u
		dist = MAX_RANGE
	r.p0 = muzzle
	r.u = u
	r.s = s
	r.t0 = now
	r.A = a
	r.t_end = now + _flight_time(s, dist)
	r.next_check = now + check_period
	r.flying = true
	return true


## Time to cover `dist` from speed `s` at the deceleration −abs_accel (the gun's case of
## FUN_0047a491: the deceleration phase covers the whole path; a constant-speed tail at
## _limitVel once the speed would fall below it).
func _flight_time(s: float, dist: float) -> float:
	var dec := -abs_accel
	if dec <= 0.0:
		return dist / maxf(s, 1.0)
	var t_c := (s - limit_vel) / dec
	if t_c > 0.0:
		var d_c := s * t_c - 0.5 * dec * t_c * t_c
		if d_c >= dist:
			return (s - sqrt(maxf(s * s - 2.0 * dec * dist, 0.0))) / dec
		return t_c + (dist - d_c) / limit_vel
	return dist / maxf(s, 1.0)


## Position of a round at `now` (FUN_00466fc0): p0 + v0·dt + ½a·dt² along u until t_end, then A.
func position(r: Dictionary, now: float) -> Vector3:
	if now >= r.t_end:
		return r.A
	var dt: float = now - r.t0
	var dec := -abs_accel
	var t_c: float = (r.s - limit_vel) / dec if dec > 0.0 else INF
	if dt <= t_c:
		return r.p0 + r.u * (r.s * dt - 0.5 * dec * dt * dt)
	var d_c: float = r.s * t_c - 0.5 * dec * t_c * t_c
	return r.p0 + r.u * (d_c + limit_vel * (dt - t_c))


## The candidate list (FUN_004577c0): none within 0.5 s of the last list; else the locked target
## (within 2·|A − P|) first, then the units inside 10·|A − P| other than the shooter, at most 10.
## UNCERTAIN: the original's query order (a spatial list); ours is nearest first.
func _candidates(now: float, p: Vector3, a: Vector3, locked: String, me: String) -> Array:
	if now >= _gate_t0 and now <= _gate_t0 + LIST_GATE:
		return []
	_gate_t0 = now
	var reach := (a - p).length()
	var out: Array = []
	var all: Array = units.call() if units.is_valid() else []
	for u in all:
		if u.key == locked and locked != "" and u.pos.distance_squared_to(p) < LOCK_FACTOR_SQ * reach * reach:
			out.append(u.key)
	var near: Array = all.filter(func(u): return u.key != me and not u.key in out and u.pos.distance_to(p) < QUERY_FACTOR * reach)
	near.sort_custom(func(x, y): return x.pos.distance_squared_to(p) < y.pos.distance_squared_to(p))
	for u in near:
		if out.size() >= MAX_CANDIDATES:
			break
		out.append(u.key)
	return out


## Advances the rounds to `now`: the 0.1 s checks (FUN_00560710: the round within the hit sphere of
## a candidate's origin, or at / below the terrain) and the end of flight at t_end (detonation at A).
func update(now: float) -> void:
	for r in pool:
		if not r.flying:
			continue
		while r.flying and r.next_check <= minf(now, r.t_end):
			_check(r, r.next_check)
			r.next_check += check_period
		if r.flying and now >= r.t_end:
			r.flying = false
			detonate.call(r, r.A, null, {})


func _check(r: Dictionary, t: float) -> void:
	var p := position(r, t)
	var pos := {}
	for u in (units.call() if units.is_valid() and not r.cands.is_empty() else []):
		pos[u.key] = u
	for k in r.cands:
		if pos.has(k) and p.distance_to(pos[k].pos) < r.hit_r:
			r.flying = false
			detonate.call(r, p, r.cands, pos[k])
			return
	var h = ground.call(p) if ground.is_valid() else null
	if p.z <= (h if h != null else 0.1):
		r.flying = false
		detonate.call(r, p, null, {"ground": true})


func flying_count() -> int:
	return pool.filter(func(r): return r.flying).size()
