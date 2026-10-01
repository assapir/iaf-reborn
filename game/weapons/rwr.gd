# The RWR of a controller (ctl+0x5b0, ctor FUN_004515d0; docs/rwr.md): 10 emitter slots filled by the
# lock / unlock notifications of the radars and sensors that lock the jet (FUN_0044deb0 / FUN_0044e030,
# from the radar manager's on-lock FUN_004b0510 / on-unlock FUN_004b04d0) and by the missiles launched at
# it (FUN_0044e160 / FUN_0044e1d0), the 2 s refresh (FUN_00451a70), the panel lights 3 'ai' / 4 'sam'
# (FUN_00450bc0), the new-emitter and launch sounds, the nearest threat (FUN_00451f70) and the cockpit
# copy (FUN_00446200). Scene independent: world frame X east, Y north, Z up, metres, sim seconds; the owner
# (player_weapons.gd) supplies the units, the own pose and the sounds.
extends RefCounted

const SLOTS := 10
## Emitter test (FUN_004521c0): within 37080 m (0x600d14); ground classes always, others only more than
## 120° off the own nose (0x600d18).
const RANGE := 37080.0
const REAR := 2.0943951
const GROUND := [8, 9, 10, 5, 0x10]
## bdb type codes the lock notifications ignore (FUN_0044deb0 / FUN_0044e030).
const IGNORED_TYPES := [220, 250, 270]
## The nearest threat (FUN_00451f70): within 370800 m.
const NEAREST := 370800.0
## The refresh rides the controller's 2.0 s timer (DAT_0082f4a8, with the radar scan; FUN_0044a1a0).
const REFRESH := 2.0
## WRN_NEW_GUY at most once per 1.0 s (gate ctl+0x860, FUN_004d3fa0(0, 1.0, 0) @4479fd).
const NEW_GUY_GATE := 1.0
## Panel lights (docs/cockpit.md): 3 'ai', 4 'sam'.
const LAMP_AI := 3
const LAMP_SAM := 4

## Slots (+0xc + 0x24·i): unit key ("" = free), type (bdb type code, 0 = free), pos (Vector3), launch flag
## (+0x14), missiles in flight (+0x18), drop pending (+0x1c), active (+0x20).
var slots: Array = []
var count := 0  # +0x174
## Missiles launched at the jet (+0x178): {dist (missile to jet at the launch), missile}, decoy targets left out.
var missiles: Array = []
## Damage 14 (RWR) blocks every notification (FUN_0045cc90(0xe)).
var damaged := false
## Betty fitted (ctl+0x964): "Missile" on every launch.
var betty := false
var lamps := {LAMP_AI: false, LAMP_SAM: false}
var _gate := [-INF, -INF]
var _launch_loop: Node = null  # ctl+0x8c8
var _next_refresh := 0.0

## Owner callbacks: unit(key) -> {pos, klass, type, state} or {} (gone); own() -> {pos, yaw};
## play(code, sub1) -> Node; stop(Node); now() -> sim seconds.
var unit: Callable
var own: Callable
var play: Callable
var stop: Callable
var now: Callable


func _init() -> void:
	_clear_slots()


func _clear_slots() -> void:
	slots = []
	for i in SLOTS:
		slots.append({"unit": "", "type": 0, "pos": Vector3.ZERO, "launch": false, "missiles": 0, "drop": false,
			"active": false})
	count = 0


func _find(key: String) -> int:
	for i in SLOTS:
		if slots[i].unit == key:
			return i
	return -1


static func is_ground(klass: int) -> bool:
	return klass in GROUND


## The emitter test (FUN_004521c0): ≤ 37080 m (3-D) and, unless a ground class, more than 120° off the
## own nose (relative bearing FUN_0044e770).
func emitter_test(key: String) -> bool:
	if key == "":
		return false
	var u: Dictionary = unit.call(key)
	if u.is_empty():
		return false
	var o: Dictionary = own.call()
	var d: Vector3 = u.pos - o.pos
	if d.length() > RANGE:
		return false
	if is_ground(int(u.klass)):
		return true
	var rel := wrapf(atan2(d.x, d.y) - float(o.yaw), -PI, PI)
	return absf(rel) > REAR


## Add (FUN_004518d0): refused when full (count > 9) or listed; the first slot with type 0; the active
## flag from the emitter test.
func _add(key: String) -> bool:
	if count > 9 or _find(key) >= 0:
		return false
	var i := -1
	for k in SLOTS:
		if int(slots[k].type) == 0:
			i = k
			break
	if i < 0:
		return false
	var u: Dictionary = unit.call(key)
	var s: Dictionary = slots[i]
	s.type = int(u.get("type", 0))
	s.unit = key
	s.pos = u.get("pos", Vector3.ZERO)
	s.active = emitter_test(key)
	count += 1
	return true


## Remove (FUN_004519e0): with missiles still flying only the drop is marked; else the slot is cleared
## (not compacted: the original's display copies only the first `count` slots).
func _remove(key: String) -> bool:
	var i := _find(key)
	if i < 0:
		return false
	var s: Dictionary = slots[i]
	if int(s.missiles) == 0:
		slots[i] = {"unit": "", "type": 0, "pos": s.pos, "launch": false, "missiles": 0, "drop": false, "active": false}
		count -= 1
	else:
		s.drop = true
	return true


func _type_ok(key: String) -> bool:
	if damaged or key == "":
		return false
	var u: Dictionary = unit.call(key)
	return not u.is_empty() and not int(u.get("type", 0)) in IGNORED_TYPES


## A radar / sensor locks the jet (FUN_0044deb0): listed; when the new entry is active, its light
## (4 'sam' for a ground class, else 3 'ai') and WRN_NEW_GUY (gated 1 s).
func lock(key: String) -> void:
	if not _type_ok(key) or not _add(key):
		return
	var s: Dictionary = slots[_find(key)]
	if s.active:
		_light_on(LAMP_SAM if is_ground(int(unit.call(key).klass)) else LAMP_AI)


## The lock is dropped (FUN_0044e030): removed; with the list empty, its light goes off.
func unlock(key: String) -> void:
	if not _type_ok(key):
		return
	var klass := int(unit.call(key).klass)
	if _remove(key) and count == 0:
		lamps[LAMP_SAM if is_ground(klass) else LAMP_AI] = false


## A missile was launched at the jet by `key` (FUN_0044e160 → FUN_00451be0): the entry (added if new)
## gets the launch flag, one more missile in flight and active; the missile joins the list unless it
## chases a decoy; the WRN_MISSILE_LAUNCH loop starts, Betty "Missile" with Betty. `missile` = {id, pos,
## decoy} or {}.
func launch(key: String, missile := {}) -> void:
	if damaged or key == "":
		return
	_launch_entry(key, missile)
	if _launch_loop == null or not is_instance_valid(_launch_loop):
		_launch_loop = play.call("SFX_WARNING", "WRN_MISSILE_LAUNCH") if play.is_valid() else null
	if betty and play.is_valid():
		play.call("VOC_BBETTY", "BTY_MISS")


## FUN_00451be0.
func _launch_entry(key: String, missile: Dictionary) -> void:
	var i := _find(key)
	if i < 0:
		_add(key)
		if count > 9:
			return  # original quirk: the add that filled the list leaves the launch unmarked
		i = _find(key)
	if i >= 0:
		var s: Dictionary = slots[i]
		s.launch = true
		s.missiles = int(s.missiles) + 1
		s.active = true
	if not missile.is_empty() and not missile.get("decoy", false):
		if not missiles.any(func(m): return m.missile.id == missile.id):
			missiles.append({"dist": (missile.pos - own.call().pos).length(), "missile": missile})


## That missile is gone (FUN_0044e1d0 → FUN_00451e30): one missile less; at none the launch flag drops
## (and a pending drop removes the entry); the missile leaves the list; with no launch flag left the
## launch loop stops.
func missile_end(key: String, missile := {}) -> void:
	if damaged or key == "":
		return
	var i := _find(key)
	if i >= 0:
		var s: Dictionary = slots[i]
		s.missiles = int(s.missiles) - 1
		if s.missiles == 0:
			s.launch = false
			if s.drop:
				_remove(key)
	if not missile.is_empty():
		missiles = missiles.filter(func(m): return m.missile.id != missile.id)
	if not any_launch() and _launch_loop != null:
		if stop.is_valid():
			stop.call(_launch_loop)
		_launch_loop = null


## FUN_004520f0: any entry with the launch flag.
func any_launch() -> bool:
	return slots.any(func(s): return s.launch)


## Damage 14 / 19 / 21 (FUN_00451b90): every entry and the missile list cleared.
func clear() -> void:
	_clear_slots()
	missiles = []


## The 2 s refresh (FUN_00451a70): positions; active = the emitter test or the launch flag; a destroyed
## emitter (state 5) is removed.
func refresh() -> void:
	for s in slots:
		var key: String = s.unit
		if key != "":
			var u: Dictionary = unit.call(key)
			if not u.is_empty():
				s.pos = u.pos
		s.active = emitter_test(key) or s.launch
		if key != "":
			var u2: Dictionary = unit.call(key)
			if u2.is_empty() or int(u2.get("state", 1)) == 5:
				_remove(key)


## Every frame (the 2 s timer and FUN_00450bc0): with an empty list both lights off; else a light comes on
## (with WRN_NEW_GUY, gated 1 s) while an active entry of its kind exists, and goes off without one.
func update(t: float) -> void:
	if t >= _next_refresh:
		_next_refresh = t + REFRESH
		refresh()
	if count == 0:
		lamps[LAMP_AI] = false
		lamps[LAMP_SAM] = false
		return
	var ground := false
	var air := false
	for s in slots:
		if s.active and s.unit != "":
			var u: Dictionary = unit.call(s.unit)
			if not u.is_empty() and is_ground(int(u.klass)):
				ground = true
			elif not u.is_empty():
				air = true
	if ground and not lamps[LAMP_SAM]:
		_light_on(LAMP_SAM)
	if air and not lamps[LAMP_AI]:
		_light_on(LAMP_AI)
	if not ground:
		lamps[LAMP_SAM] = false
	if not air:
		lamps[LAMP_AI] = false


func _light_on(i: int) -> void:
	lamps[i] = true
	var t: float = now.call() if now.is_valid() else 0.0
	# FUN_004d4100: passes when now is outside [last, next], then next = now + 1.0.
	if t >= _gate[0] and t <= _gate[1]:
		return
	_gate = [t, t + NEW_GUY_GATE]
	if play.is_valid():
		play.call("SFX_WARNING", "WRN_NEW_GUY")


## The nearest listed emitter within 370.8 km after a refresh (FUN_00451f70: F5's threat, AI action 430,
## condition 38), "" = none.
func nearest() -> String:
	refresh()
	var best := ""
	var bd := NEAREST
	var o: Dictionary = own.call()
	for s in slots:
		if s.unit == "":
			continue
		var u: Dictionary = unit.call(s.unit)
		var p: Vector3 = u.pos if not u.is_empty() else s.pos
		var d: float = (p - o.pos).length()
		if d < bd:
			bd = d
			best = s.unit
	return best


## The cockpit copy (FUN_00446200): the first `count` slots (at most 15; original bug kept: slots are not
## compacted), each {type, pos (world X / Y), launch, active}.
func display() -> Array:
	var out := []
	for i in mini(count, 15):
		var s: Dictionary = slots[i]
		out.append({"type": int(s.type), "pos": Vector2(s.pos.x, s.pos.y), "launch": s.launch, "active": s.active})
	return out
