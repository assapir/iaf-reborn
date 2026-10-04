# The IR missile seeker of the SRM HUD mode (docs/weapons.md §5.2). The logic is iaf_avionics::sight
# (crates/iaf-avionics/src/sight.rs) through IafSeeker; this keeps the GDScript face: the owner sets the radar's
# lock (`radar_key`, `radar_aa`) and the `tone` callback, and reads `symbol` / `lock` / `target_key`. Scene
# independent: world frame X east, Y north, Z up; screen offsets are original 640x480 pixels from the HUD centre.
extends RefCounted

var _s = ClassDB.instantiate("IafSeeker")

## The radar's locked unit ("" none) and its A-A flag (slaved).
var radar_key := "":
	set(v):
		radar_key = v
		_s.set_radar(radar_key, radar_aa)
var radar_aa := true:
	set(v):
		radar_aa = v
		_s.set_radar(radar_key, radar_aa)
## Tone callback tone(kind): "seek", "lock" or "" (both off).
var tone: Callable
var _tone := ""

var target_key: String:
	get:
		return _s.target_key()
var lock: bool:
	get:
		return _s.lock()
## The seeker symbol (diamond), px from the HUD centre.
var symbol: Vector2:
	get:
		return _s.symbol()
var rear_only: bool:
	get:
		return _s.rear_only()
var lock_range: float:
	get:
		return _s.lock_range()


func set_generation(gen: int) -> void:
	_s.set_generation(gen)


## The selected missile record (weapon_db.gd): its generation, then the Real overrides (cone, rear).
func set_weapon(w: Dictionary) -> void:
	_s.set_weapon(w)


## Screen offset (px, x right, y down) of a world point from the HUD centre through `own.sight` (else the nose
## basis of `own` {pos, fwd, up, right}); null when behind.
static func screen_offset(own: Dictionary, p: Vector3) -> Variant:
	return ClassDB.class_call_static("IafSeeker", "screen_offset", own, p)


## FUN_00461d10 for missile type `type` (580: limited heat).
func can_track(own: Dictionary, u: Dictionary, type: int) -> bool:
	return _s.can_track(own, u, type)


## FUN_00461f10.
func in_view(own: Dictionary, u: Dictionary) -> bool:
	return _s.in_view(own, u)


func slaved() -> bool:
	return _s.slaved()


## One frame of the IR mode (FUN_00461290). `have_rounds` = the selected store has rounds left.
func update(now: float, own: Dictionary, units: Array, type: int, have_rounds: bool) -> void:
	_s.update(now, own, units, type, have_rounds)
	_sync_tone(false)


## The target a launch takes (FUN_00462ad0): the seeker target when inside the HUD-centre circle.
func target_in_circle(own: Dictionary, units: Array) -> Dictionary:
	return _find(units, _s.target_in_circle(own, units))


func current(units: Array) -> Dictionary:
	return _find(units, target_key)


## FUN_00461b00 on entering IR with an empty station: the seek tone starts; the next update stops it.
func start_empty_chirp() -> void:
	_s.start_empty_chirp()
	_sync_tone(true)


## Leaving the IR mode (FUN_00461bb0): both tones stop.
func exit() -> void:
	_s.exit()
	_sync_tone(true)


## The tone callback on a change (`force`: always, as the original's chirp / exit).
func _sync_tone(force: bool) -> void:
	var t: String = _s.tone()
	if t != _tone or force:
		_tone = t
		if tone.is_valid():
			tone.call(t)


static func _find(units: Array, key: String) -> Dictionary:
	if key == "":
		return {}
	for u in units:
		if u.key == key:
			return u
	return {}
