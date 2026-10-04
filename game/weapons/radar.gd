# The player's radar (docs/radar.md). The logic is iaf_avionics::radar (crates/iaf-avionics/src/radar.rs) through
# IafRadar; this keeps its GDScript face: the owner (player_weapons.gd) sets the callbacks, calls the keys and
# update(), and reads the mirrored state. World frame X east, Y north, Z up, metres, sim seconds.
extends RefCounted

enum { OFF, STBY, STT, BORE, LRS, TWS, ACM, GMT, MAP }

## bdb type code → cockpit index (FUN_00447e70).
const COCKPIT := preload("res://aircraft/player_aircraft.gd").COCKPIT

# Mirrored after every call (IafRadar.state()).
var modes := {}  ## mode → {max (range index), nm, idx (current range index 1..max)}
var mode := OFF
var last_aa := LRS
var aa := true
var off := true
var damaged := false
## The contact list (15, nearest first): {key, unit, pos, heading, locked, selected, hostile, prio, aspect, az,
## el, dist, speed, type, alt}.
var contacts: Array = []
var antenna := Vector2.ZERO
var designated := false
var desig := Vector3.ZERO
var exp := false
var heading_shift := 0.0

## Owner callbacks: units() -> [{key, pos, vel, ent, hostile}], ground(world) -> height or null,
## own() -> {pos, vel, fwd, up, right, yaw}, on_lock(key, on) (the target's RWR), illumination_lost()
## (FUN_00458130: the semi-active missiles lose their guidance).
var units: Callable
var ground: Callable
var own: Callable
var on_lock: Callable
var illumination_lost: Callable

var _r = ClassDB.instantiate("IafRadar")
var _st := {}
var _by_key := {}


## Create (FUN_004ace60) for the aircraft of bdb type `type_code`; `lrs_nm` overrides the LRS / STT detection
## range (Weapon data Real). The radar starts OFF.
func setup(type_code: int, lrs_nm := 0.0) -> void:
	_r.setup(COCKPIT.get(type_code, 1), lrs_nm)
	_sync()


## Hands the own pose, the units and the terrain to the next call.
func _feed() -> void:
	var list := []
	_by_key = {}
	for u in (units.call() if units.is_valid() else []):
		var e: Dictionary = u.ent
		_by_key[u.key] = u
		list.append({"key": u.key, "pos": u.pos, "vel": u.vel, "klass": int(e.get("klass", -1)),
			"state": int(e.get("state", 1)), "coll_radius": float(e.get("coll_radius", 0.0)),
			"heading": float(e.get("heading", 0.0)), "type": int(e.get("type_code", -1)), "hostile": bool(u.get("hostile", true))})
	_r.set_input(own.call() if own.is_valid() else {}, list, ground)


## Mirrors the state and runs the events of the call, in order.
func _sync() -> void:
	_st = _r.state()
	modes = _st.modes
	mode = _st.mode
	last_aa = _st.last_aa
	aa = _st.aa
	off = _st.off
	damaged = _st.damaged
	antenna = _st.antenna
	designated = _st.designated
	desig = _st.desig
	exp = _st.exp
	heading_shift = _st.heading_shift
	contacts = (_st.contacts as Array).map(_attach)
	_st.locked = _attach(_st.locked)
	for e in _r.events():
		if e[0] == "lock":
			if on_lock.is_valid():
				on_lock.call(e[1], e[2])
		elif illumination_lost.is_valid():
			illumination_lost.call()


## A record gets its unit ({key, pos, vel, ent, hostile}) back.
func _attach(c: Dictionary) -> Dictionary:
	if not c.is_empty() and _by_key.has(c.key):
		c.unit = _by_key[c.key]
	return c


func range_index() -> int:
	return int(_st.get("range_index", 1))


func range_m() -> float:
	return float(_st.get("range_m", 9259.372))


## The B-scope width (FUN_004ad300: 2·acos(cone cos)): 2π/3, 24° in BORE.
func scope_width() -> float:
	return float(_st.get("scope_width", TAU / 3.0))


## Has a lock (FUN_004ada80): not damaged, on; TWS: a selection counts; else the record's lock flag.
func has_lock() -> bool:
	return bool(_st.get("has_lock", false))


## The locked (or TWS-selected) record ({} none) — the target the HUD, the IR seeker and the gun use; outside STT
## at its unit's position this frame (FUN_0044e370).
func locked() -> Dictionary:
	return _st.get("locked", {})


func _find(key: String) -> Dictionary:
	for c in contacts:
		if c.key == key:
			return c
	return {}


# --- per frame and keys (FUN_004ad300, FUN_0044a240; docs/radar.md §2) -----------------------------

func update(now: float) -> void:
	_feed()
	_r.update(now)
	_sync()


func scan(now: float) -> void:
	_feed()
	_r.scan(now)
	_sync()


## Q (event 0x24).
func cycle_mode(now: float) -> void:
	_feed()
	_r.cycle_mode(now)
	_sync()


## R (event 0x2b).
func toggle_aa_ag(now: float) -> void:
	_feed()
	_r.toggle_aa_ag(now)
	_sync()


## S (event 0x2c).
func standby() -> void:
	_r.standby()
	_sync()


## '.' / ',' (events 0x21 / 0x22).
func step_range(d: int, now: float) -> void:
	_feed()
	_r.step_range(d, now)
	_sync()


## '\' down / up (events 0x2d / 0x2e).
func boresight(down: bool) -> void:
	_r.boresight(down)
	_sync()


## Return / Shift+Return (events 0x26 / 0x27).
func next_target(forward: bool, _now: float) -> void:
	_r.next_target(forward)
	_sync()


## Event 0x2a (a click on a blip).
func lock_key(key: String) -> bool:
	var ok: bool = _r.lock_key(key)
	_sync()
	return ok


## Backspace (event 0x31).
func deselect(now: float) -> void:
	_feed()
	_r.deselect(now)
	_sync()


## Event 0x2f (a MAP page click off the contacts): the point (X, Y, terrain height `z`).
func designate(x: float, y: float, z: float, now: float) -> void:
	_feed()
	_r.designate(Vector3(x, y, z), now)
	_sync()


## Event 0x30 (MAP page OSB 3).
func toggle_exp() -> void:
	_r.toggle_exp()
	_sync()


## FUN_004ad880(2) from a semi-active (610) launch with a target: STT on the selection.
func lock_stt() -> void:
	_r.lock_stt()
	_sync()


## Damage (cases 0xf / 0x13 / 0x15, FUN_004adb20): off, every call a no-op.
func set_damaged(on: bool) -> void:
	_r.set_damaged(on)
	_sync()
