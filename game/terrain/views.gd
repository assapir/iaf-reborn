# The original's in-flight cameras (docs/views.md §4): the view manager DAT_00699304 (slot 0 main camera, slot 2
# the snap views while a Numpad snap key is held), the view setters (FUN_0057f2a0, FUN_005808c0, FUN_005811b0,
# FUN_00581640, FUN_00581390) and the per-frame pose FUN_00582880. Scene coordinates (Y up, −Z north); the
# targets are Node3Ds (the player's rig, AI jets, mission units, missiles).
extends RefCounted

## View types (camera +8).
const COCKPIT := 1
const HUD_ONLY := 5
const CHASE := 6  # chase (F10) and the two-object views (F5–F8)
const FOLLOW := 9  # fly-by, radar target, weapon (path-follow with the swoop)
const CIRCLE := 0x10  # the player killed: circle around the jet
const FREE_LOOK := 0x12
const FLYBY := 0x13  # requested id of F9; the camera's type becomes 9
const WRECK := 0x15  # circle around a destroyed object (wall-clock angle)
const PADLOCK := 0x16

## Position modes (+0x70): orbit / path-follow, circle, two-object; cockpit types sit at the jet.
enum Pos { JET, ORBIT, CIRCLE, TWO }

const PAN_RATE := PI / 4.0  # 0x610e10: pans, head return speed (rad/s)
const ZOOM_RATE := 60.0  # 0x610e1c: orbit distance m/s
const HEAD_PITCH_MIN := -0.20944  # 0x610e5c (−12°)
const HEAD_PITCH_MAX := 1.48353  # 0x610e58 (85°)
const PADLOCK_DEAD := 0.0872665  # 0x610e98 (5°)
const TRAIL_SAMPLES := 100
const ORBIT_DMIN_CAP := 1500.0  # 0x610f50
const SWOOP_BASE := 0.3  # 0x610e94
const TWO_BACK := 150.0  # DAT_00843b80 = 100 · 1.5
const TWO_SIDE := 30.0  # 0x66d718
const TWO_UP := 30.0  # 0x66d71c
const CIRCLE_RATE := 0.314159  # 0x610e68 (18°/s)
const CIRCLE_R := 600.0  # 0x610e6c
## Snap views (FUN_0057fd10): id 0x1c..0x23 → head yaw (fractions of π: 0x610f14..0x610f2c) and pitch.
const SNAPS := {0: Vector2(0, 0.261799), 45: Vector2(0.2 * PI, 0), 90: Vector2(0.5 * PI, 0), 135: Vector2(0.8 * PI, 0),
	180: Vector2(PI, 0.20944), 225: Vector2(-0.8 * PI, 0), 270: Vector2(-0.5 * PI, 0), 315: Vector2(-0.2 * PI, 0)}

## Host (terrain_view.gd): terrain heights (`ground_at(scene pos)`), the clock.
var ground_at: Callable
var now := 0.0

var type := COCKPIT
## DAT_0083370c: F1 goes to HUD-only (5) rather than the cockpit (1); DAT_00833704 the last requested id.
var hud_pref := false
var last_id := COCKPIT
var pos_mode := Pos.JET
## +0x88 / +0x60: the object followed / looked at; +0x80 / +0x64 the eye object (two-object A).
var target: Node3D
var eye_obj: Node3D
var player: Node3D

# --- head (cockpit types): yaw right +, pitch up + (radians) ---
var head := Vector2.ZERO
## Slot 2: the snap view's head while its key is held (null = slot 0).
var snap = null
var _ret: Dictionary = {}  # head return to (0, 0) (FUN_0057fa10): from, t0, dur
var _pan_rate := Vector2.ZERO
var _pan_from := Vector2.ZERO
var _pan_t0 := 0.0

# --- orbit / path-follow (position mode 3) ---
var orbit_pitch := 0.0  # +0x12c
var orbit_heading := 0.0  # +0x14c
var dist := 0.0  # +0x16c
var dmin := 0.0
var dmax := 0.0
var _rates := Vector3.ZERO  # pitch, heading, distance
var _trail: Array = []  # [scene pos, time], newest last
var _swoop: Dictionary = {}  # dir, len, t0
# --- circle ---
var _circle_h := 0.0
var _circle_t0 := 0.0
var _circle_wall := false
var _circle_centre := Vector3.ZERO  # a destroyed object's last position


func cockpit_like() -> bool:
	return snap != null or type in [COCKPIT, FREE_LOOK, PADLOCK, HUD_ONLY]


## The cockpit art is drawn (types 1, 0x12, 0x16 and every snap); 5 draws the HUD only.
func cockpit_drawn() -> bool:
	return snap != null or type in [COCKPIT, FREE_LOOK, PADLOCK]


func hud_only() -> bool:
	return snap == null and type == HUD_ONLY


## The head angles the cockpit is panned by (slot 2 while a snap is held).
func head_angles() -> Vector2:
	return snap if snap != null else head


# --- setters -------------------------------------------------------------------------------------

## FUN_0057f2a0 case 1 / 5: the cockpit or HUD-only view; coming from a panned or padlocked cockpit view
## the head returns to straight ahead linearly at 45°/s on the larger axis (FUN_0057fa10), from an
## external view it starts at 0.
func set_cockpit(t: int) -> void:
	if type in [COCKPIT, FREE_LOOK, PADLOCK, HUD_ONLY] and head != Vector2.ZERO:
		_ret = {"from": head, "t0": now, "dur": maxf(absf(head.x), absf(head.y)) / PAN_RATE}
	else:
		head = Vector2.ZERO
		_ret = {}
	_pan_rate = Vector2.ZERO
	type = t
	pos_mode = Pos.JET
	target = null


## FUN_005808c0: the orbit / path-follow camera on `ent`: offs = {x, y, z, pitch, ·, heading}, `scale` for
## the distance (dmin = min(1500, scale · size), start 3·dmin, max 20·dmin); id FLYBY adds the swoop from the
## (random) offset point; the type becomes 9 then.
func set_orbit(ent: Node3D, offs: Array, scale: float, id: int, random: bool) -> void:
	if ent == null:
		return
	target = ent
	eye_obj = ent
	pos_mode = Pos.ORBIT
	type = FOLLOW if id == FLYBY else id
	orbit_pitch = offs[3]
	orbit_heading = offs[5]
	_rates = Vector3.ZERO
	dmin = minf(ORBIT_DMIN_CAP, scale * size_of(ent))
	dist = 3.0 * dmin
	dmax = 20.0 * dmin
	# FUN_00586670: the trail is pre-filled with the current position.
	_trail = [[ent.global_position, now]]
	_swoop = {}
	if id == FLYBY:
		var o := Vector3(offs[0], offs[1], offs[2])
		if random:
			# x and z get a random sign (rand > 16383.5), each axis × (0.5 + rand / 32767) (0x610f54, f58, f18).
			o.x *= 1.0 if randi() % 32768 > 16383 else -1.0
			o.z *= 1.0 if randi() % 32768 > 16383 else -1.0
			for a in 3:
				o[a] *= 0.5 + float(randi() % 32768) / 32767.0
		# The offset in the target's body axes (x right, y forward, z up; UNCERTAIN), ≥ ground + 15 m.
		var b := ent.global_basis.orthonormalized()
		var e := ent.global_position + b.x * o.x - b.z * o.y + b.y * o.z
		e.y = maxf(e.y, _ground(e) + 15.0)
		var p0 := _path_point(ent)
		if (e - p0).length() > 0.01:
			_swoop = {"dir": (e - p0).normalized(), "len": (e - p0).length(), "t0": now}


## FUN_005811b0: eye beside A looking at B (F5–F8), type 6.
func set_two(a: Node3D, b: Node3D) -> void:
	if a == null or b == null:
		return
	eye_obj = a
	target = b
	pos_mode = Pos.TWO
	type = CHASE


## FUN_00581640: padlock `ent` from the cockpit; the head starts where it is.
func set_padlock(ent: Node3D) -> void:
	if ent == null:
		return
	if not type in [COCKPIT, FREE_LOOK, PADLOCK, HUD_ONLY]:
		head = Vector2.ZERO
	_ret = {}
	_pan_rate = Vector2.ZERO
	target = ent
	pos_mode = Pos.JET
	type = PADLOCK


## FUN_0057f2a0 case 0x10 (player killed) / FUN_00581390 (type 0x15, wall-clock angle): circle `ent` at
## radius 600 m, height `h`.
func set_circle(ent: Node3D, h: float, t: int) -> void:
	target = ent
	_circle_centre = ent.global_position if ent != null else _circle_centre
	_circle_h = h
	_circle_t0 = now
	_circle_wall = t == WRECK
	pos_mode = Pos.CIRCLE
	type = t
	snap = null


# --- keys ----------------------------------------------------------------------------------------

## Pans (23 right, 24 left, 26 up, 27 down) and zoom (20 in, 21 out) → FUN_00582290 codes; `down` = press.
## External orbit views (6 / 9): ±45°/s heading / pitch, ±60 m/s distance (FUN_00582510); cockpit-like
## views: free look (FUN_00582370; padlock breaks; zoom codes enter it with no motion); else nothing.
func pan(cmd: int, down: bool) -> void:
	var axis: int = {23: 1, 24: 1, 26: 0, 27: 0, 20: 2, 21: 2}.get(cmd, -1)
	if axis < 0:
		return
	var sign := 1.0 if cmd in [23, 26, 21] else -1.0
	if type in [CHASE, FOLLOW]:
		_rates[axis] = (ZOOM_RATE if axis == 2 else PAN_RATE) * sign if down else 0.0
	elif type in [COCKPIT, FREE_LOOK, PADLOCK]:
		if not down:
			if type == FREE_LOOK:
				# Release: both rates stop and the head stays where it is.
				head = _free_look_head()
				_pan_from = head
				_pan_t0 = now
				_pan_rate = Vector2.ZERO
			return
		if type == PADLOCK:
			type = COCKPIT  # panning breaks padlock
		var h := head_now()
		if type == FREE_LOOK:
			h = _free_look_head()
		_ret = {}
		_pan_from = h
		head = h
		_pan_t0 = now
		type = FREE_LOOK
		if axis == 1:
			_pan_rate.x = PAN_RATE * sign
		elif axis == 0:
			_pan_rate.y = PAN_RATE * sign


## Event 22 in a cockpit-like view: snap `angle` (slot 2, instant) or −1 = release (back to slot 0).
func snap_key(angle: int) -> void:
	snap = SNAPS.get(angle) if angle >= 0 else null


# --- per frame -----------------------------------------------------------------------------------

func head_now() -> Vector2:
	if type == FREE_LOOK:
		head = _free_look_head()
		return head
	if not _ret.is_empty():
		var k := 1.0 if _ret.dur <= 0.0 else clampf((now - _ret.t0) / _ret.dur, 0.0, 1.0)
		head = _ret.from.lerp(Vector2.ZERO, k)
		if k >= 1.0:
			_ret = {}
	return head


## FUN_0057ff60 @580138: angle = start + rate · f, f = 2·dt·(1 − 0.9^dt): the pan speeds up towards 90°/s.
func _free_look_head() -> Vector2:
	var dt := now - _pan_t0
	var f := 2.0 * dt * (1.0 - pow(0.9, dt))
	var h := _pan_from + _pan_rate * f
	h.x = wrapf(h.x, -PI, PI)
	h.y = clampf(h.y, HEAD_PITCH_MIN, HEAD_PITCH_MAX)
	return h


## Advances the cameras by `dt` of sim time; the trail takes one sample per frame (FUN_00582880 step 2).
func update(dt: float) -> void:
	now += dt
	if type == PADLOCK and is_instance_valid(target) and is_instance_valid(player):
		_padlock_step(dt)
	elif type in [COCKPIT, HUD_ONLY, FREE_LOOK]:
		head_now()
	if pos_mode in [Pos.ORBIT, Pos.TWO] and is_instance_valid(target):
		_circle_centre = target.global_position  # where a destroyed followed object was last
	if pos_mode == Pos.ORBIT and is_instance_valid(target):
		_trail.append([target.global_position, now])
		if _trail.size() > TRAIL_SAMPLES:
			_trail.pop_front()


## Look mode 8: the target's direction in the jet's body frame, pitch ≥ −12°, (0, 0) within 5° of the
## nose; the head moves there with 0.9^(10·dt) of the error left (FUN_005858e0).
func _padlock_step(dt: float) -> void:
	var b := player.global_basis.orthonormalized()
	var d := b.inverse() * (target.global_position - player.global_position)
	var yaw := atan2(d.x, -d.z)
	var pitch := maxf(atan2(d.y, Vector2(d.x, d.z).length()), HEAD_PITCH_MIN)
	if absf(yaw) < PADLOCK_DEAD and pitch < PADLOCK_DEAD:
		yaw = 0.0
		pitch = 0.0
	var k := pow(0.9, 10.0 * dt)
	head = Vector2(yaw - wrapf(yaw - head.x, -PI, PI) * k, pitch - (pitch - head.y) * k)


## The external camera: [eye, look-at point] in scene coordinates, or [] in the cockpit-like views.
func external_pose(dt: float) -> Array:
	match pos_mode:
		Pos.ORBIT:
			if not is_instance_valid(target):
				return []
			orbit_pitch += _rates.x * dt
			orbit_heading += _rates.y * dt
			dist = clampf(dist + _rates.z * dt, dmin, dmax)
			var t := target.global_position
			var p := _path_point(target)
			if type in [CHASE, FOLLOW] and not _swoop.is_empty():
				p += _swoop.dir * _swoop.len * pow(SWOOP_BASE, now - _swoop.t0)
			var eye := t + _orbit_rotate(p - t)
			eye.y = maxf(eye.y, _ground(eye) + maxf(15.0, 0.2 * (eye - t).length()))
			return [eye, t]
		Pos.TWO:
			if not is_instance_valid(target) or not is_instance_valid(eye_obj):
				return []
			# Case 8 @583547 in world axes (z up): W = unit(A − B), N = (−W.y, W.x, 0), U = W × N.
			var a := _world(eye_obj.global_position)
			var w := (a - _world(target.global_position)).normalized()
			var n := Vector3(-w.y, w.x, 0.0)
			var u := w.cross(n)
			var eye := _scene(a + TWO_BACK * w + TWO_SIDE * n + TWO_UP * u)
			eye.y = maxf(eye.y, _ground(eye) + 2.0)
			return [eye, target.global_position]
		Pos.CIRCLE:
			var c := _circle_centre
			if is_instance_valid(target):
				c = target.global_position
				_circle_centre = c
			var t := (Time.get_ticks_msec() * 0.001) if _circle_wall else (now - _circle_t0)
			var a := CIRCLE_RATE * t
			var eye := _scene(_world(c) + Vector3(CIRCLE_R * cos(a), CIRCLE_R * sin(a), _circle_h))
			eye.y = maxf(eye.y, _ground(eye) + 15.0)
			return [eye, c]
	return []


## The trail point L = dist back along the recorded path (FUN_005867f0); a path shorter than L goes on
## from the oldest sample along the target's −forward axis (UNCERTAIN axis).
func _path_point(ent: Node3D) -> Vector3:
	var t := ent.global_position
	var acc := 0.0
	var prev := t
	for i in range(_trail.size() - 1, -1, -1):
		var q: Vector3 = _trail[i][0]
		var seg := prev.distance_to(q)
		if acc + seg >= dist and seg > 0.0:
			return prev.lerp(q, (dist - acc) / seg)
		acc += seg
		prev = q
	var back := ent.global_basis.orthonormalized().z  # −forward
	var have := prev.distance_to(t)
	return prev + back * maxf(dist - have, 0.0) if have + 0.1 < dist else prev


## FUN_00586e80: D rotated about the vertical by the heading (+ = the camera swings right, UNCERTAIN
## sign), then elevated by the pitch (+ = higher).
func _orbit_rotate(d: Vector3) -> Vector3:
	d = d.rotated(Vector3.UP, -orbit_heading)
	var horiz := Vector3(d.x, 0, d.z)
	if horiz.length() < 1e-6:
		return d
	var axis := horiz.normalized().cross(Vector3.UP)
	return d.rotated(axis, -orbit_pitch)


## Largest model dimension (TgenAPI getObjectDimensions; UNCERTAIN full or half size): the scaled AABB.
static func size_of(n: Node3D) -> float:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (n.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return 10.0
	var s := n.global_basis.get_scale()
	var sz := box.size * s
	return maxf(sz.x, maxf(sz.y, sz.z))


func _ground(p: Vector3) -> float:
	var g = ground_at.call(p) if ground_at.is_valid() else null
	return float(g) if g != null else -1.0e9


static func _world(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y)


static func _scene(w: Vector3) -> Vector3:
	return Vector3(w.x, w.z, -w.y)
