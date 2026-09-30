# One IR missile in flight (docs/weapons.md §5): the original's chase motion (type 0x17, FUN_00561c30
# fields, FUN_00561ef0 start, FUN_005627e0 update every 0.1 s, FUN_00563b70 / FUN_00563ad0 aim).
# Scene independent: world frame X east, Y north, Z up, metres, sim seconds. Between updates the
# motion is p0 + v0·dt + ½a·dt² (no gravity, no speed cap); each update re-bases and adds the
# steering acceleration. The host supplies the target position / velocity and the terrain height.
extends RefCounted

## Update period (0x60ced8 = −0.1).
const PERIOD := 0.1
## The flight ends burn + 6 s after launch (0x60ce98).
const END_AFTER_BURN := 6.0
## Hit distance (0x60ceb0).
const HIT_DIST := 1.5
## Overshoot: cos(velocity, line of sight) below this (0x60cec0).
const OVERSHOOT_COS := -0.01
## Chase init: q is clamped to [0.1, 1] (0x60cef4 / 0x60cef0); below 0.7 (0x60cef8) the
## proportional chase becomes the dog chase.
const Q_MIN := 0.1
const Q_PROP := 0.7
## Ground impact near the target: within 60 m² horizontally (0x60cea8) and 15 m above it (0x60ceac)
## the burst is put at the target's height, else at most 1 m below the ground (FUN_0049a7c0).
const NEAR_TARGET_XY2 := 60.0
const NEAR_TARGET_DZ := 15.0
## Launch speed when the launcher is slower than 5 m/s (0x60ce54, _debugParam000 = 100.1).
const MIN_LAUNCH_SPEED := 5.0

var weapon: Dictionary  # weapon_db record
var target_key := ""  # "" = flying at the aim point
var aim_point := Vector3.ZERO  # +0xc8 (no target)
var has_target := false  # +0x84
var chase := 2  # +0x88: 1 dog chase, 2 proportional (collision course)
var accel := 100.0  # +0x94 _absAcceleration
var beta := 0.08  # +0x13c _spiralAccelBeta
var gain := 1000.0  # +0x138 _spiralAccel · q
var t_co := 2.0  # +0xb8 _timeConstOrientation (flies straight until then)
var burn := 16.0  # +0x108 tAcc + tConstVel + tDecel
var high_angle_turn := false
var overshoot_dist := 1.0e7  # _debugParam001 (or 015 with _highAngleTurn)
var no_end := false  # _debugParam005 == 1

var t_start := 0.0
var t0 := 0.0
var p0 := Vector3.ZERO
var v0 := Vector3.ZERO
var acc := Vector3.ZERO  # +0x48
var last_pos := Vector3.ZERO  # +0xe4 (the burst point at the end)
var cos_prev := 0.0  # +0x128
var ended := false  # +0x118
var next_update := 0.0
var hit_ground := false


## Launch (FUN_004d5d10 -> FUN_00561ef0 after FUN_00563b70 / FUN_00563ad0): motion record `m`
## (weapons.ibx, with the weapon's Real overrides), launch position / velocity / nose, and q
## (FUN_00457f70); `target` "" = aim at `point`.
func launch(w: Dictionary, m: Dictionary, now: float, pos: Vector3, vel: Vector3, nose: Vector3, target: String, point: Vector3, q: float, debug: Callable) -> void:
	weapon = w
	accel = float(m.get("_absAcceleration", accel))
	beta = float(m.get("_spiralAccelBeta", beta))
	t_co = float(m.get("_timeConstOrientation", t_co))
	burn = float(m.get("burn", float(m.get("_timeAcceleration", 0)) + float(m.get("_timeConstVel", 0)) + float(m.get("_timeDecceleration", 0))))
	high_angle_turn = float(m.get("_highAngleTurn", 0)) != 0.0
	overshoot_dist = float(debug.call(15, 1000.0)) if high_angle_turn else float(debug.call(1, 1.0e7))
	no_end = float(debug.call(5, 0.0)) == 1.0
	chase = int(m.get("_chaseType", 1))
	var spiral := float(m.get("_spiralAccel", gain))
	if target != "":
		has_target = true
		target_key = target
		q = clampf(q, Q_MIN, 1.0)
		if chase == 2 and q < Q_PROP:
			chase = 1
		gain = spiral * q
	else:
		has_target = false
		aim_point = point
		gain = spiral  # FUN_00563ad0: q not applied
	t_start = now
	t0 = now
	p0 = pos
	last_pos = pos
	v0 = vel if vel.length() >= MIN_LAUNCH_SPEED else nose * float(debug.call(0, 100.1))
	acc = Vector3.ZERO
	next_update = now  # the first update runs at launch time


func position(now: float) -> Vector3:
	var dt := now - t0
	return p0 + v0 * dt + 0.5 * acc * dt * dt


func velocity(now: float) -> Vector3:
	return v0 + acc * (now - t0)


## FUN_0046ca82: the point of segment a -> b closest to p (p itself when p lies on the line or
## behind a; a when the segment is shorter than 0.1 m).
static func closest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var l := a.distance_to(b)
	if l <= 0.1:
		return a
	var d := (b - a) / l
	var ap := p - a
	var along := ap.dot(d)
	if (ap - d * along).length() <= 0.1 or along <= 0.0:
		return p
	return a + d * minf(along, l)


## One update (FUN_005627e0). `t_pos` / `t_vel` = the target now (ignored without one), `ground`
## = terrain height under a point (null = 0.1). Returns true when the missile ends (detonate at
## `last_pos`).
func update(now: float, t_pos: Vector3, t_vel: Vector3, ground: Callable) -> bool:
	var age := now - t_start
	var t_end := burn + END_AFTER_BURN
	var v := velocity(now)
	var p_old := last_pos
	var tp := t_pos if has_target else aim_point
	var tv := t_vel if has_target else Vector3.ZERO
	var p := position(now)
	p0 = p
	v0 = v
	t0 = now
	acc = Vector3.ZERO
	last_pos = p
	var g = ground.call(p) if ground.is_valid() else null
	var gh: float = g if g != null else 0.1
	hit_ground = p.z <= gh
	if hit_ground:
		last_pos = _snap(closest_on_segment(tp, p_old, p), tp, gh)
	var los := tp - p
	var dist := los.length()
	var sp := v.length()
	var uv := v / sp if sp > 0.0 else Vector3(0, 1, 0)
	var u := Vector3(0, 1, 0)
	var hit := dist <= HIT_DIST or hit_ground
	if not hit:
		u = los / dist
		var gdir := uv
		if age > t_co and age < t_end and not ended:
			var d := u
			if chase == 2:
				var vperp_t := tv - u * tv.dot(u)
				var pp := vperp_t.length()
				d = (u * sqrt(sp * sp - pp * pp) + vperp_t).normalized() if pp < sp else vperp_t / pp
			var v_perp := v - d * d.dot(v)
			var gv := dist * d - gain * v_perp
			gdir = gv.normalized() if gv.length() > 0.0 else d
		acc += gdir * (accel - beta * sp * gdir.dot(uv))
	# End of flight.
	var cos_old := cos_prev
	var cos_new := uv.dot(u)
	cos_prev = cos_new
	if age < 0.001:
		next_update = now + PERIOD
		return false
	var timeout := age > t_end
	var overshoot := cos_new < OVERSHOOT_COS and dist <= overshoot_dist
	var end := ((hit or timeout or overshoot) and age >= t_co) if has_target else (hit or overshoot or timeout)
	if no_end:
		end = false
	if not end:
		next_update = now + PERIOD
		return false
	ended = true
	if cos_old > 0.0 and cos_new < 0.0 and has_target and not timeout and not hit_ground:
		last_pos = _snap(closest_on_segment(tp, p_old, p), tp, gh)
	return true


func _snap(q: Vector3, tp: Vector3, gh: float) -> Vector3:
	var dx := q.x - tp.x
	var dy := q.y - tp.y
	if dx * dx + dy * dy <= NEAR_TARGET_XY2 and q.z - tp.z <= NEAR_TARGET_DZ:
		q.z = tp.z
	else:
		q.z = maxf(q.z, gh - 1.0)
	return q
