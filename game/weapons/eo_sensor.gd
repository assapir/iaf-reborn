# The player's EO sensor (docs/mfd.md "FLIR (6), TV (5)"): the controller's EO mode (ctl+0x7f4: 1 TV weapon,
# 2 FLIR pod), the camera of view slot 1 (type 0xb: FUN_005817a0 start, FUN_005805e0 angles, FUN_00581b30 slew,
# FUN_005820e0 / FUN_00582160 zoom), WIDE / SPOT (the FLIR object's +0x14), the laser flag (ctl+0x960) and the
# FLIR / TV page values (FUN_0045d7f0 / FUN_004604c0). Scene independent: world frame X east, Y north, Z up,
# metres, radians, sim seconds; headings clockwise from north.
extends RefCounted

enum { NONE, TV, FLIR }
## Camera +0x50: 1 free (angles from the slew rates), 2 tracking a point or a unit.
enum { FREE = 1, TRACK = 2 }

## The start elevation (0xbdb2b8c2 = −5°) and the gimbal limits by the store's class (FUN_005817a0): class 0x1a
## (660, the pod) az ±45°, el +30° / −80°; the weapons az ±30°, el +15° / −45°. [az, el max, el min].
const EL0 := -0.08726646
const POD_LIMITS := [0.78539816, 0.52359878, -1.3962634]
const WEAPON_LIMITS := [0.52359878, 0.26179939, -0.78539816]
## Zoom 1, 2, 4, 8 (FUN_005820e0 while < 8, FUN_00582160 while > 1); the picture's field of view is 50° / zoom
## across its width (FUN_004dc990: 0x605250 = 50).
const ZOOM_MAX := 8.0
const FOV_DEG := 50.0
## The FLIR / TV page scales (0x601354 = 4/π: ±45° = ±56 px about −5° 0x601358; 0x601524 = 6/π: ±30°).
const FLIR_K := 1.2732395
const TV_K := 1.9098593
## 1/1853 NM per m (0x60c4a0); "XXX.X" from 20 NM (0x60c4a8).
const NM := 1853.0

var mode := NONE
## Slot 1 holds the EO camera (type 0xb) once one was started; it stays (zoom keys still act on it).
var camera := false
var limits: Array = POD_LIMITS
var track := FREE
var point := Vector3.ZERO  # +0x1e0
var target := ""  # +0x60: a tracked unit (key)
var az := 0.0  # +0x1ec
var el := EL0  # +0x1f0
var rate := Vector2.ZERO  # +0x1f4 az, +0x1f8 el (rad/s)
var t0 := 0.0  # +0x1d8
var zoom := 1.0  # +0xc
## +0x208 / +0x220: the base (heading, pitch) frozen when a slew starts from tracking; null = the jet's live one.
var frozen = null
var spot := false  # the FLIR object's +0x14 (false = WIDE)
var laser := false  # ctl+0x960
## weapons.ibx [DEBUGDATA] _debugParam008 (0.09): °/s per key unit (±100) at zoom 1.
var pan_k := 0.09
var _last := Vector2i(6, 6)  # DAT_00843b84 / 88
## Owner: unit_pos(key) -> Vector3 (world) or null when gone.
var unit_pos: Callable


## FUN_00450280 → FUN_005817a0 with a store: EO mode `m`, limits by the store's class (`pod` = class 0x1a), aim
## = null (free), a world point or a unit key (tracked). The zoom starts at 1 only when slot 1 had no EO camera.
func start(m: int, pod: bool, aim, t: float) -> void:
	mode = m
	limits = POD_LIMITS if pod else WEAPON_LIMITS
	az = 0.0
	el = EL0
	rate = Vector2.ZERO
	t0 = t
	frozen = null
	_aim(aim)
	if not camera:
		zoom = 1.0
		camera = true
	_last = Vector2i(6, 6)


## FUN_0044e6e0: leaving the EO master modes.
func stop() -> void:
	mode = NONE


func _aim(aim) -> void:
	target = ""
	if aim == null:
		track = FREE
	elif aim is String:
		target = aim
		track = TRACK
	else:
		point = aim
		track = TRACK


## FUN_005805e0: the camera's (az, el) at `t` against `base` (the jet's heading, pitch) from `eye`; tracking
## stores them (unclamped) as the new az / el; then clamped to the limits.
func angles(t: float, base: Vector2, eye: Vector3) -> Vector2:
	var b: Vector2 = frozen if frozen != null else base
	var a: float
	var e: float
	if track == FREE:
		a = az + rate.x * (t - t0)
		e = el + rate.y * (t - t0)
	else:
		if target != "" and unit_pos.is_valid():
			var p = unit_pos.call(target)
			if p != null:
				point = p
		var d := point - eye
		a = atan2(d.x, d.y) - b.x
		if a > PI:
			a -= TAU
		e = atan2(d.z, Vector2(d.x, d.y).length()) - b.y
		if e > PI:
			e -= TAU
		az = a
		el = e
	a = clampf(a, -limits[0], limits[0])
	if e > limits[1]:
		e = limits[1]
	if e < limits[2]:
		e = limits[2]
	return Vector2(a, e)


## The camera's line of sight (world unit vector) for angles `ae` on `base`: heading + az, pitch + el, roll 0.
func los(ae: Vector2, base: Vector2) -> Vector3:
	var b: Vector2 = frozen if frozen != null else base
	var h: float = b.x + ae.x
	var p: float = b.y + ae.y
	return Vector3(sin(h) * cos(p), cos(h) * cos(p), sin(p))


## Event 0x8a(x, y) (Ctrl+arrows, ±100; release 0): with the keys released and (a launched TV weapon or FLIR) the
## camera locks on the EO centre point `centre`; else FUN_00581b30: a changed (x, y) restarts the slew from the
## current angles (from tracking: free, the base frozen) at 0.09·x / zoom, 0.09·y / zoom °/s.
func pan(x: int, y: int, t: float, base: Vector2, eye: Vector3, centre, launched := false) -> void:
	if mode == NONE or not camera:
		return
	if absi(x) < 10 and absi(y) < 10 and (launched or mode == FLIR):
		frozen = null
		_aim(centre)
		_last = Vector2i(6, 6)
		return
	if Vector2i(x, y) == _last:
		return
	_last = Vector2i(x, y)
	if track == TRACK:
		angles(t, base, eye)  # the stored az / el are the current ones
		track = FREE
		target = ""
		frozen = base
	else:
		var cur := angles(t, base, eye)
		az = cur.x
		el = cur.y
	t0 = t
	rate = Vector2(deg_to_rad(pan_k * x), deg_to_rad(pan_k * y)) / zoom


## Events 0x14 / 0x15 on the EO camera (FUN_005820e0 / FUN_00582160): ×2 while < 8 / ×0.5 while > 1, the slew
## rates the other way; az0 / t0 stay (original quirk: zooming during a slew jumps the picture).
func zoom_step(zoom_in: bool) -> void:
	if not camera:
		return
	if zoom_in and zoom < ZOOM_MAX:
		zoom *= 2.0
		rate *= 0.5
	elif not zoom_in and zoom > 1.0:
		zoom *= 0.5
		rate *= 2.0


## Event 0x20 (FLIR OSB 5): WIDE ↔ SPOT and three zoom steps in (to SPOT) or out (to WIDE).
func wide_spot() -> void:
	var was := spot
	spot = not spot
	for i in 3:
		zoom_step(not was)


## Event 0x6a (L, FLIR OSB 3): only with the pod fitted (ctl+0x93c).
func laser_key(pod_fitted: bool) -> void:
	if pod_fitted:
		laser = not laser


## The FLIR page values (FUN_0045d7f0 → state+0x5e0..0x600): zoom 1..10, gimbal u / v, laser, range text.
func flir_page(ae: Vector2, range_m: float) -> Dictionary:
	var nm := range_m / NM
	return {"zoom": clampi(int(zoom), 1, 10), "u": ae.x * FLIR_K, "v": (ae.y - EL0) * FLIR_K, "laser": laser,
		"spot": spot, "range": "XXX.X" if nm >= 20.0 else "%3.1f" % nm}


## The TV page values (FUN_004604c0 → state+0x5e0..0x5f4): status 0 NO SOURCE / 1 RDY (2 TRA / 3 TER come from a
## launched weapon), zoom, seeker u / v.
func tv_page(ae: Vector2, status: int) -> Dictionary:
	return {"status": status, "zoom": clampi(int(zoom), 1, 10), "u": ae.x * TV_K, "v": ae.y * TV_K}
