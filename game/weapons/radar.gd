# The player's radar (docs/radar.md): the radar manager of the player controller (ctl+0x84,
# FUN_004acc20) with its modes (OFF / STBY, STT, BORE, LRS, TWS, ACM, GMT, MAP), the per-aircraft
# range tables, the scan (FUN_004af300, every 2.0 s and on events), the hit test (FUN_004aeb90), the
# contact list (15, nearest first), the lock / designate keys and the STT track (FUN_004b1300). Scene
# independent: world frame X east, Y north, Z up, metres, sim seconds. The owner (player_weapons.gd)
# supplies the own pose, the units and the terrain.
extends RefCounted

enum { OFF, STBY, STT, BORE, LRS, TWS, ACM, GMT, MAP }

## Range scale of index 1..6 (FUN_004b0020, 0x603358..: 5·2^(i−1) NM at 1851.87 m/NM).
const RANGE_M := [9259.372, 18518.744, 37037.488, 74074.977, 148149.95, 296299.9]
## Detection NM → m (0x603390).
const NM := 1854.0
## Full rescan period (DAT_0082f4a8 = 2.0 s).
const SCAN_PERIOD := 2.0
## Cone half-angles (cos): 60° every mode, 12° BORE (static init 0x603440.. / 0x6035d8).
const CONE_COS := 0.5
const BORE_COS := 0.97814760
## Air modes skip targets lower than 30 m above the terrain (0x60337c).
const MIN_AGL := 30.0
## Line-of-sight ends raised 1.5 m (0x603380).
const LOS_RAISE := 1.5
## The candidate query: |c − C|² < 3·(r + R/2)² (0x604e6c).
const QUERY_K := 3.0
## STT auto-range: below 0.33·R one scale down, above 0.75·R one up (0x60355c / 0x603560).
const AUTO_DOWN := 0.33
const AUTO_UP := 0.75
## Antenna sweep period (vt+0x54): 4.0 s, BORE 1.0 s (0x6033b8 / 0x6035e8); bar step 0.25.
const SWEEP := 4.0
const SWEEP_BORE := 1.0
const MAX_CONTACTS := 15
## m/s → kt (0x600a70).
const KT := 1.9427955
## Classes per mode filter (vt+0x3c): air 4b1c70, MAP 4b0ce0, GMT 4b0fc0 (moving only).
const AIR_CLASSES := [0x1c, 3, 2, 1]
const MAP_CLASSES := [10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10]
const GMT_CLASSES := [5, 6, 0xf, 0x10, 8, 9, 10, 0xb]

## Per cockpit index (FUN_00447e70: 0 F-15, 1 F-16, 2 F-4-2000, 3 Lavi, 4 Kfir, 5 F-4E, 6 Mirage,
## 7 MiG-29, 8 MiG-23): A-A table 0x640a74 [LRS, TWS, ACM, BORE] and A-G table 0x640bbc [MAP, GMT],
## each (max range index, detection NM); [0, 0] = no such mode.
const TABLES := [
	[[6, 90], [4, 40], [2, 10], [2, 10], [4, 40], [4, 20]],
	[[5, 45], [4, 35], [2, 10], [2, 10], [4, 40], [4, 30]],
	[[5, 55], [4, 40], [2, 10], [2, 10], [5, 60], [5, 40]],
	[[6, 90], [4, 40], [2, 10], [2, 10], [5, 60], [5, 40]],
	[[2, 8], [0, 0], [1, 5], [1, 5], [2, 10], [2, 10]],
	[[4, 25], [0, 0], [2, 10], [2, 10], [2, 10], [2, 10]],
	[[2, 8], [0, 0], [1, 5], [1, 5], [2, 10], [2, 10]],
	[[5, 45], [4, 35], [2, 10], [2, 10], [2, 10], [2, 10]],
	[[4, 25], [0, 0], [2, 10], [2, 10], [4, 40], [4, 25]],
]
## bdb type code → cockpit index (FUN_00447e70).
const COCKPIT := preload("res://aircraft/player_aircraft.gd").COCKPIT

## Mode objects: mode → {max (range index), nm, idx (current range index 1..max)}.
var modes := {}
var mode := OFF  # +0x30
var last_aa := LRS  # +0x34
var last_ag := GMT  # +0x38
var bore_return := LRS  # +0x3c
var aa := true  # +0x40
var off := true  # +0x44 (OFF or STBY: not radiating)
var damaged := false  # +0x48
var bore_held := false  # +0x54
var dirty := false  # +4 == 5: push to the cockpit
## The contact list (15, priority = 100 / distance, highest first): records {key, unit, pos, heading,
## locked, selected, hostile, prio, aspect, az, el, dist, speed, type}.
var contacts: Array = []
## +0x58: the selected / locked record's unit key ("" none) and whether it is locked (+0x14).
var sel_key := ""
var sel_locked := false
## STT: the locked record (kept between scans).
var stt: Dictionary = {}
## Outside STT: the locked (TWS: selected) record with its unit's position and distance this frame
## (FUN_0044e370 reads the target's live position; the contact list only changes on a scan).
var _live: Dictionary = {}
var antenna := Vector2.ZERO  # carets (az, el) 0..1 (state+0xa0c / +0xa10)
## The designated ground point (event 0x2f, FUN_004ade90): +0x50 flag, +0x58 / +0x5c X / Y, +0x60 the
## terrain height there; +0x4c the MAP page's EXP flag (event 0x30, FUN_004ade70).
var designated := false
var desig := Vector3.ZERO
var exp := false
var heading_shift := 0.0  # state+0xa14 (rad)
var _href = null
var _next_scan := 0.0
var _sweep := {"t0": INF, "dir": true, "bar": 0.0, "step": 0.25}

## Owner callbacks: units() -> [{key, pos, vel, ent}], ground(world) -> height or null,
## own() -> {pos, vel, fwd, up, right, yaw}, on_lock(key, on) (the target's RWR; hook).
var units: Callable
var ground: Callable
var own: Callable
var on_lock: Callable
## FUN_00458130 (the semi-active missiles lose their guidance): called where the original calls it — Q, R, S,
## Return / Shift+Return, a click lock, Backspace with a lock, STT lost and any mode change leaving STT.
var illumination_lost: Callable


## Create (FUN_004ace60) for the aircraft of bdb type `type_code`; `lrs_nm` overrides the LRS / STT
## detection range (Weapon data Real). The radar starts OFF (the constructor: mode 0, A-A, off).
func setup(type_code: int, lrs_nm := 0.0) -> void:
	var t: Array = TABLES[COCKPIT.get(type_code, 1)]
	var ids := [LRS, TWS, ACM, BORE, MAP, GMT]
	for k in ids.size():
		var a: int = t[k][0]
		var b: float = t[k][1]
		if a == 0:
			continue
		if ids[k] == LRS and lrs_nm > 0.0:
			b = lrs_nm
		modes[ids[k]] = {"max": a, "nm": b, "idx": a if ids[k] == BORE else mini(a, 4)}
	# STT takes LRS's (max index, NM), else ACM's.
	var src: Dictionary = modes.get(LRS, modes.get(ACM, {"max": 2, "nm": 10.0}))
	modes[STT] = {"max": src.max, "nm": src.nm, "idx": mini(src.max, 4)}
	last_aa = LRS  # the first A-A mode created (always LRS)


func _m() -> Dictionary:
	return modes.get(mode, {})


func range_index() -> int:
	return int(_m().get("idx", 1))


func range_m() -> float:
	return RANGE_M[clampi(range_index(), 1, 6) - 1]


func _cone_cos(m: int) -> float:
	return BORE_COS if m == BORE else CONE_COS


## The B-scope width (FUN_004ad300: 2·acos(cone cos)): 2π/3, 24° in BORE.
func scope_width() -> float:
	return 2.0 * acos(_cone_cos(mode))


## Has a lock (FUN_004ada80): not damaged, on; TWS: a selection counts; else the record's lock flag.
func has_lock() -> bool:
	if damaged or mode in [OFF, STBY] or sel_key == "":
		return false
	if mode == STT:
		return not stt.is_empty() and stt.locked
	if mode == TWS:
		return true
	return sel_locked


## The locked (or TWS-selected) record ({} none) — the target the HUD, the IR seeker and the gun use.
func locked() -> Dictionary:
	if not has_lock():
		return {}
	if mode == STT:
		return stt
	for c in contacts:
		if c.key == sel_key:
			return _live if _live.get("key", "") == sel_key else c
	return {}


# --- per frame (FUN_004ad300 + the 2 s timer) ---------------------------------------------------------

func update(now: float) -> void:
	if damaged or mode in [OFF, STBY]:
		return
	var o: Dictionary = own.call()
	var h: float = o.yaw
	if _href == null:
		_href = h
	heading_shift = wrapf(float(_href) - h, -PI, PI)
	_antenna(now)
	_stt_transitions(now)
	if now >= _next_scan:
		_next_scan = now + SCAN_PERIOD
		scan(now)
	if mode == STT:
		_track()
	_follow(o)
	if dirty or mode == STT:
		heading_shift = 0.0
		_href = h
		dirty = false


## The lock outside STT at its unit this frame (STT's record is already re-made every frame by _track).
func _follow(o: Dictionary) -> void:
	_live = {}
	if mode == STT or not has_lock():
		return
	var c := _find(sel_key)
	if c.is_empty():
		return
	for u in units.call():
		if u.key == sel_key:
			_live = c.duplicate()
			_live.unit = u
			_live.pos = u.pos
			_live.alt = u.pos.z
			_live.dist = (u.pos - o.pos).length()
			return


## Antenna sweep (FUN_004b0340, cosmetic; one static state shared by the modes).
func _antenna(now: float) -> void:
	if mode == STT:
		antenna = Vector2.ZERO
		return
	var period := SWEEP_BORE if mode == BORE else SWEEP
	var dt: float = now - _sweep.t0
	if dt < 0.0:
		_sweep = {"t0": now, "dir": true, "bar": 0.0, "step": 0.25}
		return
	var az: float = dt / period if _sweep.dir else 1.0 - dt / period
	if now > _sweep.t0 + period:
		_sweep.bar += _sweep.step
		_sweep.dir = not _sweep.dir
		if (_sweep.bar >= 1.0 and _sweep.step > 0.0) or (_sweep.bar <= 0.0 and _sweep.step < 0.0):
			_sweep.step = -_sweep.step
		_sweep.t0 = now
	antenna = Vector2(clampf(az, 0.0, 1.0), clampf(_sweep.bar, 0.0, 1.0))


## FUN_004adde0 (every frame): an A-A lock outside TWS goes to STT; STT without a lock returns to
## BORE (key held) or the last A-A mode, and scans.
func _stt_transitions(now: float) -> void:
	if mode != TWS and has_lock() and aa:
		if mode != STT:
			_set_mode(STT)
		return
	if mode == STT and not has_lock():
		_illum()
		_set_mode(BORE if bore_held else last_aa)
		scan(now)


## SetMode (FUN_004ad880): STT takes the current mode's selected record and locks it; leaving STT drops the
## semi-active missiles' guidance (FUN_00458130).
func _set_mode(m: int) -> void:
	if mode == STT and m != STT:
		_illum()
	if m == STT:
		var r := locked() if mode != TWS else _find(sel_key)
		if r.is_empty():
			return
		stt = r.duplicate()
		stt.locked = true
		sel_locked = true
		_notify(sel_key, true)
	mode = m
	dirty = true


func _illum() -> void:
	if illumination_lost.is_valid():
		illumination_lost.call()


## FUN_004ad880(2) from a semi-active (610) launch with a target: the radar locks its selected record (STT).
func lock_stt() -> void:
	if damaged or mode == STT or not modes.has(STT):
		return
	_set_mode(STT)


# --- the scan (FUN_004af300) -----------------------------------------------------------------------

func _class_ok(m: int, ent: Dictionary, vel: Vector3) -> bool:
	var k := int(ent.get("klass", -1))
	match m:
		MAP:
			return k in MAP_CLASSES
		GMT:
			return k in GMT_CLASSES and vel.length() > 0.0
	return k in AIR_CLASSES


func scan(now: float) -> void:
	_next_scan = now + SCAN_PERIOD
	dirty = true
	_live = {}
	if damaged or mode in [OFF, STBY]:
		return
	if mode == STT:
		return  # STT's list is its track (FUN_004b1300 every frame)
	var o: Dictionary = own.call()
	var O: Vector3 = o.pos
	var ant := Vector2(o.fwd.x, o.fwd.y).normalized()
	var air := not (mode in [GMT, MAP])
	var R := range_m()
	var C := O + Vector3(ant.x, ant.y, 0.0) * R / 2.0
	var rd: float = float(_m().nm) * NM
	var old_key := sel_key
	var old_locked := sel_locked
	var list: Array = []
	var seen := {}
	for u in units.call():
		var ent: Dictionary = u.ent
		if int(ent.get("state", 1)) in [4, 5]:
			continue
		var rad := float(ent.get("coll_radius", 0.0))
		if (u.pos - C).length_squared() >= QUERY_K * pow(rad + R / 2.0, 2):
			continue
		if not _class_ok(mode, ent, u.vel):
			continue
		seen[u.key] = u
		var dist: float = (u.pos - O).length()
		if dist > rd:
			continue  # (ECM rules: no jammer on either side yet, docs/radar.md)
		var r := _hit(u, o, air, _cone_cos(mode))
		if r.is_empty():
			continue
		_insert(list, r)
	# The old selection is kept when its unit is still in the query, re-tested without the range.
	if old_key != "" and seen.has(old_key) and not list.any(func(c): return c.key == old_key):
		var r := _hit(seen[old_key], o, air, _cone_cos(mode))
		if not r.is_empty():
			_insert(list, r)
	contacts = list
	# The cursor: the old id if present, else the nearest; it becomes "selected" (and the target's RWR
	# hears a lock: on-lock notify).
	var cur := ""
	if list.any(func(c): return c.key == old_key):
		cur = old_key
	elif not list.is_empty():
		cur = list[0].key
	if cur != old_key:
		if old_key != "":
			_notify(old_key, false)
		sel_locked = false
		sel_key = cur
		if cur != "":
			_notify(cur, true)
	else:
		sel_locked = old_locked and cur != ""
	for c in contacts:
		c.selected = c.key == sel_key
		c.locked = c.selected and sel_locked
	# BORE / ACM lock the selection (FUN_004b19c0 → FUN_004b06b0).
	if mode in [BORE, ACM] and sel_key != "":
		sel_locked = true
		_find(sel_key).locked = true


## The hit test (FUN_004aeb90) and the record: air modes skip targets below 30 m AGL; the horizontal
## cone about the antenna only (no elevation limit); terrain line of sight (ends +1.5 m).
func _hit(u: Dictionary, o: Dictionary, air: bool, cone: float) -> Dictionary:
	var T: Vector3 = u.pos
	var O: Vector3 = o.pos
	if air:
		var g = ground.call(T) if ground.is_valid() else null
		if g != null and T.z < float(g) + MIN_AGL:
			return {}
	var D := T - O
	if D.length() < 1.0:
		return {}
	var hd := Vector2(D.x, D.y).normalized()
	var ant := Vector2(o.fwd.x, o.fwd.y).normalized()
	var c := hd.dot(ant)
	if c < cone:
		return {}
	var az := acos(clampf(c, -1.0, 1.0))
	var right := Vector2(cos(o.yaw), -sin(o.yaw))
	if right.dot(hd) < 0.0:
		az = -az
	var pitch := asin(clampf(o.fwd.z, -1.0, 1.0))
	var el := asin(clampf(D.z / D.length(), -1.0, 1.0)) - pitch
	if not line_of_sight(O + Vector3(0, 0, LOS_RAISE), T + Vector3(0, 0, LOS_RAISE)):
		return {}
	var ent: Dictionary = u.ent
	var beta := atan2(D.x, D.y)
	var dist := D.length()
	return {"key": u.key, "unit": u, "pos": T, "heading": float(ent.get("heading", 0.0)), "locked": false,
		"selected": false, "hostile": bool(u.get("hostile", true)), "prio": 100.0 / dist if dist > 0.0 else 1e8,
		"aspect": wrapf(deg_to_rad(float(ent.get("heading", 0.0))) - beta, -PI, PI), "az": az, "el": el, "dist": dist,
		"speed": (u.vel as Vector3).length() * KT, "type": int(ent.get("type_code", -1)), "alt": T.z}


## Terrain line of sight (FUN_004020d0; ours samples the segment every 100 m: the original's
## sampling is UNCERTAIN).
func line_of_sight(a: Vector3, b: Vector3) -> bool:
	if not ground.is_valid():
		return true
	var d := b - a
	var n := int(d.length() / 100.0)
	for i in range(1, n):
		var p := a + d * (float(i) / n)
		var g = ground.call(p)
		if g != null and p.z < float(g):
			return false
	return true


## Sorted insert, 15 at most (FUN_004b08e0): when full, a record replaces the last only when its
## priority is strictly higher.
static func _insert(list: Array, r: Dictionary) -> void:
	if list.size() >= MAX_CONTACTS:
		if r.prio <= list[-1].prio:
			return
		list.pop_back()
	var i := 0
	while i < list.size() and list[i].prio >= r.prio:
		i += 1
	list.insert(i, r)


func _find(key: String) -> Dictionary:
	for c in contacts:
		if c.key == key:
			return c
	return {}


func _notify(key: String, on: bool) -> void:
	if on_lock.is_valid():
		on_lock.call(key, on)


# --- STT track (FUN_004b1300, every frame) ------------------------------------------------------------

func _track() -> void:
	if stt.is_empty() or not stt.locked:
		return
	var u = null
	for x in units.call():
		if x.key == stt.key:
			u = x
			break
	var o: Dictionary = own.call()
	var r := {}
	if u != null and not int(u.ent.get("state", 1)) in [4, 5]:
		if (u.pos - o.pos).length() <= float(modes[STT].nm) * NM:
			r = _hit(u, o, true, CONE_COS)
	if r.is_empty():
		_unlock()
		return
	r.locked = true
	r.selected = true
	stt = r
	contacts = [r]
	# Auto-range (FUN_004b1590).
	var m: Dictionary = modes[STT]
	while m.idx > 1 and r.dist < AUTO_DOWN * RANGE_M[m.idx - 1]:
		m.idx -= 1
	while m.idx < m.max and r.dist > AUTO_UP * RANGE_M[m.idx - 1]:
		m.idx += 1


func _unlock() -> void:
	if sel_key != "":
		_notify(sel_key, false)
	stt = {}
	sel_locked = false
	for c in contacts:
		c.locked = false
	dirty = true


# --- keys (FUN_0044a240) -------------------------------------------------------------------------

## Q (event 0x24, FUN_004ad6f0): A-A LRS → TWS → ACM → LRS (missing modes skipped; leaving STT
## unlocks), A-G GMT ↔ MAP; also turns the radar on.
func cycle_mode(now: float) -> void:
	if damaged:
		return
	if aa:
		if mode == STT:
			deselect(now)
		var order := [LRS, TWS, ACM]
		var i := order.find(last_aa)
		for k in 3:
			i = (i + 1) % 3
			if modes.has(order[i]):
				break
		last_aa = order[i]
		mode = last_aa
	else:
		last_ag = MAP if last_ag == GMT else GMT
		mode = last_ag
	_on_tail(now)
	_illum()


## R (event 0x2b, FUN_004ad8f0): A-G or off → the last A-A mode; else the last A-G mode.
func toggle_aa_ag(now: float) -> void:
	if damaged:
		return
	var old := mode
	_unlock()
	sel_key = ""
	if not aa or off:
		aa = true
		mode = last_aa
	else:
		aa = false
		mode = last_ag
	_on_tail(now, old)
	_illum()


## The tail of Q / R: an off radar starts (lists cleared), then a scan.
func _on_tail(now: float, _old := -1) -> void:
	if off:
		off = false
		contacts = []
		sel_key = ""
	scan(now)


## S (event 0x2c, FUN_004ad9c0): STBY; from on: off first (lists cleared), then STBY.
func standby() -> void:
	if damaged:
		return
	if not off:
		_unlock()
		contacts = []
		sel_key = ""
		off = true
		aa = true
	mode = STBY
	dirty = true
	_illum()


## '.' / ',' (events 0x21 / 0x22, FUN_004adb70): range index ±1 within [1, max] (STT: none), then a scan.
func step_range(d: int, now: float) -> void:
	if damaged or mode in [OFF, STBY, STT]:
		return
	var m := _m()
	m.idx = clampi(int(m.idx) + d, 1, int(m.max))
	scan(now)


## '\' down / up (events 0x2d / 0x2e): BORE while held (A-A only), back to the saved mode.
func boresight(down: bool) -> void:
	if not aa or damaged:
		return
	if down:
		if not mode in [OFF, STBY, STT]:
			bore_return = mode
			bore_held = true
			mode = BORE
			dirty = true
	else:
		if not mode in [OFF, STBY]:
			if mode != STT:
				mode = bore_return
			bore_held = false
			dirty = true


## Return / Shift+Return (events 0x26 / 0x27, FUN_004aefd0): the cursor walks to the next (farther) or
## previous contact, wrapping; it becomes the selection; LRS also locks it (→ STT); STT unlocks.
func next_target(forward: bool, _now: float) -> void:
	if damaged or mode in [OFF, STBY]:
		return
	_illum()  # FUN_004adbc0
	if mode == STT:
		_unlock()
		return
	if contacts.size() <= 1:
		return  # (a single contact is locked by clicking its blip, event 0x2a)
	var i := -1
	for k in contacts.size():
		if contacts[k].key == sel_key:
			i = k
	i = posmod(i + (1 if forward else -1), contacts.size())
	var key: String = contacts[i].key
	if key != sel_key:
		if sel_key != "":
			_notify(sel_key, false)
		sel_key = key
		sel_locked = false
		_notify(key, true)
	for c in contacts:
		c.selected = c.key == sel_key
		c.locked = false
	if mode == LRS:
		lock_key(key)
	dirty = true


## Event 0x2a (FUN_004adca0, a click on a blip): lock that contact; from TWS straight to STT.
func lock_key(key: String) -> bool:
	if not damaged and not mode in [OFF, STBY]:
		_illum()  # FUN_004adca0
	var r := _find(key)
	if r.is_empty():
		return false
	if key != sel_key and sel_key != "":
		_notify(sel_key, false)
	sel_key = key
	sel_locked = true
	for c in contacts:
		c.selected = c.key == key
		c.locked = c.selected
	_notify(key, true)
	if mode == TWS:
		_set_mode(STT)
	dirty = true
	return true


## Backspace (event 0x31, FUN_004add60): drop the lock (STT → the last A-A mode on the next frame);
## without a lock it clears the designated point (the EXP flag stays).
func deselect(now: float) -> void:
	if not has_lock():
		designated = false
		desig = Vector3.ZERO
		return
	_unlock()
	_illum()
	_stt_transitions(now)


## Event 0x2f (FUN_004ade90, a MAP page click off the contacts): a lock is dropped first, then the
## point (X, Y, terrain height `z`) is designated.
func designate(x: float, y: float, z: float, now: float) -> void:
	if has_lock():
		deselect(now)
	desig = Vector3(x, y, z)
	designated = true
	dirty = true


## Event 0x30 (FUN_004ade70, MAP page OSB 3): NORM <-> EXP, only with a designated point.
func toggle_exp() -> void:
	if designated:
		exp = not exp
		dirty = true


## Damage (cases 0xf / 0x13 / 0x15, FUN_004adb20): off, every call a no-op.
func set_damaged(on: bool) -> void:
	if on and not damaged:
		_unlock()
		contacts = []
		sel_key = ""
		off = true
		mode = OFF
	damaged = on
	dirty = true
