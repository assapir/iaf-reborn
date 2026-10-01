# Bombs (docs/weapons.md §9): the HUD impact prediction (FUN_0045e7f0), the ripple line
# (FUN_00457c20) and the falling store, the original's ballistic class 0x16 (solver FUN_005611b0,
# motion FUN_00468470, impact check FUN_00561750). Scene independent: world frame X east, Y north,
# Z up, metres, sim seconds. The terrain height comes from a callable ground(p) -> float or null.
extends RefCounted

## ½g and g of the impact solvers (0x601414 4.903, 0x60cde0 −19.612, 0x60cdf0 1/9.806).
const HALF_G := 4.903
const G := 9.806
## The motion's vertical acceleration (0xc11ce560 = −9.806).
const ACC_Z := -9.806
## Impact check period (0x60ce20 −0.5), "at the aim" distance (0x60cddc 2.0) and the ground band
## (0x60ce18 −1.0: at or below terrain + 1).
const CHECK_PERIOD := 0.5
const HIT_AIM := 2.0
const GROUND_BAND := 1.0
## The terrain height where none is loaded (0x60ce14).
const NO_GROUND := 0.1


## FUN_0045e7f0 (the HUD's predicted impact): V = the jet's velocity, minus the store's bdb drag
## (0x73a) as m/s along the nose, plus `extra` m/s along the nose (rockets: _limitVel); the fall
## time t = (vz + √(vz² + 19.612·h)) / 9.806 to the terrain under the jet, I = P + V·t − (0, 0, 4.903·t²);
## then once more for the terrain under I, whose height I takes. Returns {point, t}.
static func predict_impact(p: Vector3, vel: Vector3, nose: Vector3, drag: float, extra: float, ground: Callable) -> Dictionary:
	var v := vel
	if absf(extra) > 0.0:
		v += nose * extra
	if drag > 0.0:
		v -= nose * drag
	var t := fall_time(v.z, p.z - _h(ground, p))
	var i := p + v * t - Vector3(0, 0, HALF_G * t * t)
	var gi := _h(ground, i)
	if gi < i.z:
		t = fall_time(v.z, p.z - gi)
		i = p + v * t - Vector3(0, 0, HALF_G * t * t)
		gi = _h(ground, i)
		i.z = minf(i.z, gi)
	return {"point": i, "t": t}


## FUN_0045e330: the later root of h + vz·t − 4.903·t² = 0 (0 when there is none).
static func fall_time(vz: float, h: float) -> float:
	var d := vz * vz + 4.0 * HALF_G * h
	if d < 0.0:
		return 0.0
	return maxf((vz + sqrt(d)) / (2.0 * HALF_G), (vz - sqrt(d)) / (2.0 * HALF_G))


static func _h(ground: Callable, p: Vector3) -> float:
	var h = ground.call(p) if ground.is_valid() else null
	return float(h) if h != null else NO_GROUND


## FUN_00457c20: the ripple line, frozen at the first release: `qty` points `spacing` m apart along
## the heading (sin h, cos h), centred (index qty/2) on P, each on the terrain.
static func ripple_line(p: Vector3, qty: int, spacing: float, heading_rad: float, ground: Callable) -> Array:
	var d := Vector3(sin(heading_rad), cos(heading_rad), 0.0)
	var start := p - d * float(qty / 2) * spacing
	var out := []
	for k in qty:
		var a := start + d * float(k) * spacing
		a.z = _h(ground, a)
		out.append(a)
	return out


## The falling store (ballistic motion, the solver FUN_005611b0 at launch): the horizontal velocity
## is turned toward the aim (speed kept), the fall time to the aim's height fixes the along-track
## acceleration that lands it on the aim, clamped to ±`clamp_acc` (the player's bombs in single
## player: _debugParam016 15 m/s²; 0 = none). Returns the bomb state.
static func launch(now: float, p: Vector3, v: Vector3, aim: Vector3, clamp_acc: float) -> Dictionary:
	var b := {"t0": now, "p0": p, "v0": v, "aim": aim, "acc": Vector3(0, 0, ACC_Z), "end": now,
		"next_check": now, "opened": false, "done": false}
	var dxy := Vector2(aim.x - p.x, aim.y - p.y)
	var dist := dxy.length()
	var vh := Vector2(v.x, v.y).length()
	var u := dxy / dist if dist > 0.0 else Vector2.ZERO
	b.v0 = Vector3(u.x * vh, u.y * vh, v.z)
	var a := 0.0
	var d := v.z * v.z + 4.0 * HALF_G * (p.z - aim.z)
	if d >= 0.0:
		var t := (sqrt(d) + v.z) / G
		b.end = now + t
		if t > 0.0:
			a = 2.0 * (dist - vh * t) / (t * t)
	if clamp_acc > 0.0:
		a = clampf(a, -clamp_acc, clamp_acc)
	b.acc = Vector3(u.x * a, u.y * a, ACC_Z)
	return b


## FUN_00468470 / FUN_004684d0: p0 + v0·dt + ½·acc·dt² (v1.1: no cap at the impact time).
static func position(b: Dictionary, now: float) -> Vector3:
	var dt := maxf(now - float(b.t0), 0.0)
	return b.p0 + b.v0 * dt + b.acc * (0.5 * dt * dt)


static func velocity(b: Dictionary, now: float) -> Vector3:
	return b.v0 + b.acc * maxf(now - float(b.t0), 0.0)


## The impact checks of FUN_00561750 up to `now` (the first at launch, then every 0.5 s): the bomb
## ends within 2 m of its aim or at / below terrain + 1, bursting at the check point (quirk: up to
## ~0.5·|vz| under the ground). `fix_burst` (Physics "Bombs burst at the ground", ours): the burst
## moves up to where the last 0.5 s step crossed the terrain. Returns {} or {pos, t}. `open_h` > 0
## (510): the cluster opens that high above the terrain (visual; b.opened).
static func check(b: Dictionary, now: float, ground: Callable, fix_burst := false, open_h := 0.0) -> Dictionary:
	while not b.done and float(b.next_check) <= now:
		var t: float = b.next_check
		b.next_check = t + CHECK_PERIOD
		var p := position(b, t)
		var g := _h(ground, p)
		if open_h > 0.0 and p.z <= g + open_h:
			b.opened = true
		if p.distance_to(b.aim) < HIT_AIM or p.z <= g + GROUND_BAND:
			b.done = true
			if fix_burst and p.z < g:
				p = _ground_crossing(b, t - CHECK_PERIOD, t, ground)
			return {"pos": p, "t": t}
	return {}


## Bisection on the last check step for the point where the bomb meets the terrain (ours).
static func _ground_crossing(b: Dictionary, t0: float, t1: float, ground: Callable) -> Vector3:
	var lo := maxf(t0, float(b.t0))
	var hi := t1
	for i in 20:
		var m := 0.5 * (lo + hi)
		var p := position(b, m)
		if p.z <= _h(ground, p):
			hi = m
		else:
			lo = m
	var q := position(b, hi)
	q.z = maxf(q.z, _h(ground, q))
	return q
