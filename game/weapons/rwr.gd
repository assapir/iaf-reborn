# The RWR of a controller (ctl+0x5b0; docs/rwr.md): 10 emitter slots filled by the lock / unlock notifications and
# the missiles launched at the jet, the 2 s refresh, the panel lights 3 'ai' / 4 'sam', the nearest threat and the
# cockpit copy. The logic is iaf_avionics::rwr (crates/iaf-avionics/src/rwr.rs) through IafRwr; this keeps the
# GDScript face and plays the sounds (WRN_NEW_GUY, the WRN_MISSILE_LAUNCH loop, Betty). World frame X east, Y north,
# Z up, metres, sim seconds; the owner (player_weapons.gd) supplies the units, the own pose and the sounds.
extends RefCounted

const SLOTS := 10
## Panel lights (docs/cockpit.md): 3 'ai', 4 'sam'.
const LAMP_AI := 3
const LAMP_SAM := 4

## Mirrors of the Rust state: slots [{unit ("" free), type, pos, launch, missiles, drop, active}], count,
## the missiles launched at the jet [{dist, missile}], the lights.
var slots: Array = []
var count := 0
var missiles: Array = []
var lamps := {LAMP_AI: false, LAMP_SAM: false}
var _next_refresh := 0.0
## Ours (Flight data = Real): the display lists every used slot.
var compact := false:
	set(v):
		compact = v
		_r.set_compact(v)
## Damage 14 (RWR) blocks every notification.
var damaged := false:
	set(v):
		damaged = v
		_r.set_damaged(v)
## Betty fitted (ctl+0x964): "Missile" on every launch.
var betty := false

## Owner callbacks: unit(key) -> {pos, klass, type, state} or {} (gone); own() -> {pos, yaw};
## play(code, sub1) -> Node; stop(Node); now() -> sim seconds.
var unit: Callable
var own: Callable
var play: Callable
var stop: Callable
var now: Callable

var _r = ClassDB.instantiate("IafRwr")
var _launch_loop: Node = null  # ctl+0x8c8
var _by_id := {}  # missile id -> the launch record


func _init() -> void:
	_sync()


func _t() -> float:
	return now.call() if now.is_valid() else 0.0


func _find(key: String) -> int:
	for i in SLOTS:
		if slots[i].unit == key:
			return i
	return -1


## A radar / sensor locks the jet (FUN_0044deb0).
func lock(key: String) -> void:
	_r.lock(key, unit, own.call(), _t())
	_sync()


## The lock is dropped (FUN_0044e030).
func unlock(key: String) -> void:
	_r.unlock(key, unit, own.call(), _t())
	_sync()


## A missile was launched at the jet by `key` (FUN_0044e160): the entry's launch flag, the missile list, the
## WRN_MISSILE_LAUNCH loop, Betty "Missile". `missile` = {id, pos, decoy} or {}.
func launch(key: String, missile := {}) -> void:
	if not missile.is_empty():
		_by_id[missile.id] = missile
	var heard: bool = _r.launch(key, missile, unit, own.call(), _t())
	_sync()
	if not heard:
		return
	if _launch_loop == null or not is_instance_valid(_launch_loop):
		_launch_loop = play.call("SFX_WARNING", "WRN_MISSILE_LAUNCH") if play.is_valid() else null
	if betty and play.is_valid():
		play.call("VOC_BBETTY", "BTY_MISS")


## That missile is gone (FUN_0044e1d0); with no launch flag left the launch loop stops.
func missile_end(key: String, missile := {}) -> void:
	if not _r.missile_end(key, missile.get("id")):
		return
	_sync()
	if not any_launch() and _launch_loop != null:
		if stop.is_valid():
			stop.call(_launch_loop)
		_launch_loop = null


## FUN_004520f0: any entry with the launch flag.
func any_launch() -> bool:
	return slots.any(func(s): return s.launch)


## Damage 14 / 19 / 21 (FUN_00451b90): every entry and the missile list cleared.
func clear() -> void:
	_r.clear()
	_sync()


## The 2 s refresh (FUN_00451a70).
func refresh() -> void:
	_r.refresh(unit, own.call(), _t())
	_sync()


## Every frame: the 2 s refresh and the lights (FUN_00450bc0).
func update(t: float) -> void:
	_r.update(unit, own.call(), t)
	_sync()


## The nearest listed emitter within 370.8 km after a refresh (FUN_00451f70), "" = none.
func nearest() -> String:
	var k: String = _r.nearest(unit, own.call(), _t())
	_sync()
	return k


## The cockpit copy (FUN_00446200): [{type, pos (world X / Y), launch, active}].
func display() -> Array:
	return _r.display()


func _sync() -> void:
	var st: Dictionary = _r.state()
	slots = st.slots
	count = st.count
	lamps[LAMP_AI] = st.ai
	lamps[LAMP_SAM] = st.sam
	_next_refresh = st.next_refresh
	missiles = []
	var ids := {}
	for th in st.threats:
		ids[th.id] = true
		missiles.append({"dist": th.dist, "missile": _by_id.get(th.id, {"id": th.id})})
	for id in _by_id.keys():
		if not ids.has(id):
			_by_id.erase(id)
	if _r.take_new_guy() and play.is_valid():
		play.call("SFX_WARNING", "WRN_NEW_GUY")
