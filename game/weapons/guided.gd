# One guided weapon in flight (class 0x19: the TV missile 640, the laser bomb 650; docs/weapons.md §12): the
# original's guided motion (motion vtable 0x601f70 / 0x601ed0, config FUN_00563d30, start FUN_00563f90, update
# FUN_005643a0 every 0.5 s, errors FUN_00564fe0, aim FUN_00469f00, status FUN_004d8030, time left FUN_00564f10, DLZ
# FUN_005641c0). It flies to an aim POINT (the target unit is ignored). Launcher and scene independent: world frame
# X east, Y north, Z up, metres, sim seconds. Between updates p0 + v0·dt + ½a·dt²; each update re-bases and sets a
# new acceleration.
extends RefCounted

## Update period (0x60cf48 = −0.5).
const PERIOD := 0.5
## Mode 0 pitch law (0x60cf58 = −24°, 0x60cf5c = 40°) and gravity (0xc11ce560).
const PITCH_BIAS := 0.41887903
const PITCH_CAP := 0.69813168
const G := 9.806
## The end / mode checks start at age 0.001 s (0x60cf60); time left is capped at 280 s (0x60cf70).
const CHECK_AGE := 0.001
const TIME_LEFT_MAX := 280.0
## The DLZ's dive angle (rad per degree, 0x60cf28) and its minimum acceleration (0x60cf38).
const DEG := 0.01745329

var weapon: Dictionary  # weapon_db record
## weapons.ibx fields (FUN_00563d30; the ibx comments name their real use): _absAcceleration +0x78 the engine,
## _timeAcceleration +0x88 its time, _timeConstVel +0x74 the squared distance of the switch to mode 1,
## _absDeceleration +0x7c the turn gain, _timeDecceleration +0xa0 the up acceleration, _spiralAccelBeta +0xa8
## the down acceleration, _spiralAccel +0x118 the end time, _absReleaseAcceleration +0x120 the maximum velocity,
## _timeRelease +0x11c the velocity damp, _timeConstOrientation +0x98 tCO, _rollRate +0xc8 the maximum up angle.
var engine := 10.0
var t_acc := 2.0
var switch2 := 3.0e7
var turn := 150.0
var up_acc := 20.0
var down_acc := 70.0
var end_time := 420.0
var max_vel := 300.0
var damp := 8.0
var t_co := 2.0
var max_up := 0.0179065
## _debugParam013 (burst at the aim point within it) and _debugParam014 (mode 2 inside it).
var burst_dist := 200.0
var near_dist := 200.0

var aim := Vector3.ZERO  # +0xb0
## +0x70: 0 far (climb / glide law with gravity), 1 near, 2 terminal (the aim is frozen). The first update runs
## with the mode the constructor left (UNCERTAIN, uninitialised; taken 0); the start sets 0 after it.
var mode := 0
var t_start := 0.0
var t0 := 0.0
var p0 := Vector3.ZERO
var v0 := Vector3.ZERO
var acc := Vector3.ZERO
var last_pos := Vector3.ZERO
var ended := false
var next_update := 0.0


## FUN_00563d30 + FUN_00563f90: motion record `m` (weapons.ibx), the release point / velocity, the aim point.
## UNCERTAIN: the release push (+0x80 along +0xbc, while age < +0x90) reads fields nothing sets: taken as none.
func launch(w: Dictionary, m: Dictionary, now: float, pos: Vector3, vel: Vector3, point: Vector3, debug: Callable) -> void:
	weapon = w
	engine = float(m.get("_absAcceleration", engine))
	t_acc = float(m.get("_timeAcceleration", t_acc))
	switch2 = float(m.get("_timeConstVel", switch2))
	turn = float(m.get("_absDeceleration", turn))
	up_acc = float(m.get("_timeDecceleration", up_acc))
	down_acc = float(m.get("_spiralAccelBeta", down_acc))
	end_time = float(m.get("_spiralAccel", end_time))
	max_vel = float(m.get("_absReleaseAcceleration", max_vel))
	damp = float(m.get("_timeRelease", damp))
	t_co = float(m.get("_timeConstOrientation", t_co))
	max_up = float(m.get("_rollRate", max_up))
	burst_dist = float(debug.call(13, burst_dist))
	near_dist = float(debug.call(14, near_dist))
	aim = point
	t_start = now
	t0 = now
	p0 = pos
	v0 = vel
	last_pos = pos
	acc = Vector3.ZERO
	update(now, Callable())
	mode = 0


func position(now: float) -> Vector3:
	var dt := now - t0
	return p0 + v0 * dt + 0.5 * acc * dt * dt


func velocity(now: float) -> Vector3:
	return v0 + acc * (now - t0)


## FUN_00469f00: a new aim point, ignored in mode 2.
func set_aim(p: Vector3) -> void:
	if mode != 2:
		aim = p


## FUN_004d8030: 2 TRA (mode 0), 3 TER.
func status() -> int:
	return 3 if mode != 0 else 2


## FUN_00564f10: |aim − position| / speed, at most 280 s.
func time_left(now: float) -> float:
	var s := velocity(now).length()
	return minf(position(now).distance_to(aim) / s, TIME_LEFT_MAX) if s > 0.0 else TIME_LEFT_MAX


## The heading / pitch errors toward the aim (FUN_00564fe0): heading = atan2(dx, dy) − the velocity's heading,
## wrapped only above π (original quirk: below −π it turns the long way); the pitch target asin(LOS z), in mode 0
## the maximum up angle, never above it; its error wrapped the same way.
func errors(p: Vector3, v: Vector3) -> Vector2:
	var los := aim - p
	var l := los.length()
	var u := los / l if l > 0.0 else Vector3(0, 1, 0)
	var h := atan2(v.x, v.y)
	var pitch := asin(clampf(v.z / v.length(), -1.0, 1.0)) if v.length() > 0.0 else 0.0
	var eh := atan2(u.x, u.y) - h
	if eh > PI:
		eh -= TAU
	var tp := asin(clampf(u.z, -1.0, 1.0))
	if mode == 0:
		tp = max_up
	tp = minf(tp, max_up)
	var ep := tp - pitch
	if ep > PI:
		ep -= TAU
	return Vector2(eh, ep)


## One update (FUN_005643a0). `ground` = terrain height under a point (invalid = 0.1). Returns true when the
## weapon ends (burst at `last_pos`).
func update(now: float, ground: Callable) -> bool:
	var age := now - t_start
	var p := position(now)
	var v := velocity(now)
	p0 = p
	v0 = v
	t0 = now
	acc = Vector3.ZERO
	var g = ground.call(p) if ground.is_valid() else null
	var gh: float = g if g != null else 0.1
	var below := p.z <= gh
	if below:
		p.z = gh
		p0 = p
	else:
		var sp := v.length()
		var h := atan2(v.x, v.y)
		var d := v / sp if sp > 0.0 else Vector3(sin(h), cos(h), 0.0)
		var e := errors(p, v)
		acc = Vector3(cos(h), -sin(h), 0.0) * turn * e.x  # D × U (roll 0): the right axis
		if mode == 0:
			var x := minf(e.y + PITCH_BIAS, PITCH_CAP)
			acc += Vector3(0, 0, -G) + Vector3(0, 0, 1) * (up_acc if x > 0.0 else down_acc) * x
		elif mode == 1 or mode == 2:
			acc += Vector3(0, 0, 1) * 2.0 * down_acc * e.y
		if age < t_acc:
			acc += d * engine
		elif (max_vel - sp) * damp < 0.0:
			acc += d  # original bug: the damping product is computed and dropped, the unit axis added (+1 m/s²)
	last_pos = p
	if age < CHECK_AGE:
		next_update = now + PERIOD
		return false
	var dh := Vector2(aim.x - p.x, aim.y - p.y)
	var d2 := dh.length_squared()
	if d2 > switch2:
		mode = 0
	elif d2 < switch2 and d2 > near_dist * near_dist:
		mode = 1
	if d2 < near_dist * near_dist:
		mode = 2
	if (age > end_time or below) and age >= t_co:
		ended = true
		if p.distance_to(aim) < burst_dist:
			last_pos = aim
		return true
	next_update = now + PERIOD
	return false


## The DLZ (FUN_005641c0) from `pos` (height `agl` above the terrain, at least 0) at velocity `vel`: the fall time
## t of a = 9.806 − _debugParam011·(π/180)·up accel (at least 1) from the height, max root of (−vz_down ± √(vz_down²
## + 2ah)) / (2a) (UNCERTAIN: 2a, not a); the engine's distance over min(t, tAcc), then the glide at d1 = the
## distance flown so far capped at the maximum velocity (original bug: a distance used as a speed) for
## min(t − tAcc, end time − tAcc). [max, min] = [range, range].
static func dlz(m: Dictionary, agl: float, vel: Vector3, debug: Callable) -> Array:
	var h := maxf(agl, 0.0)
	var vd := -vel.z
	var a := 9.806 - float(debug.call(11, 70.0)) * DEG * float(m.get("_timeDecceleration", 20.0))
	if a < 1.0:
		a = 1.0
	var disc := vd * vd + 2.0 * a * h
	var t := h
	if disc >= 0.0:
		var r := sqrt(disc)
		t = maxf(-(vd + r) / (2.0 * a), (r - vd) / (2.0 * a))
	var tacc := float(m.get("_timeAcceleration", 2.0))
	var tt := minf(t, tacc)
	var d1 := tt * Vector2(vel.x, vel.y).length()
	var rng := d1 + 0.5 * tt * tt * float(m.get("_absAcceleration", 10.0))
	if t > tacc:
		d1 = minf(d1, float(m.get("_absReleaseAcceleration", 300.0)))
		rng += minf(t - tacc, float(m.get("_spiralAccel", 420.0)) - tacc) * d1
	return [rng, rng]
