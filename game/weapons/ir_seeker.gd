# The IR missile seeker of the SRM HUD mode (docs/weapons.md §5.2; IR mode object FUN_00461210,
# update FUN_00461290, search FUN_00461680, can-track FUN_00461d10, field of view FUN_00461f10,
# per-generation limits FUN_00462460, tones FUN_00461bf0). Scene independent: world frame X east,
# Y north, Z up. Screen offsets are original 640x480 pixels from the HUD centre (cx, cy) through the 3D
# camera, as angles at 12 px/deg from the camera ray through that point (`own.sight`; the nose without
# one). The helmet (free look / padlock views, docs/weapons.md §5.4): `own.helmet` and the camera axis
# `own.view_fwd`.
extends RefCounted

## Per missile generation (bdb 0x762): seeker cone (0x6016c0.., the radar- or helmet-slaved gimbal limit) and
## lock range in NM (0x82f6c4); generation 0 / other keeps the previous values (static default:
## generation 4).
const CONE_DEG := {1: 15.0, 2: 21.0, 3: 35.0, 4: 70.0}
const RANGE_NM := {1: 6.0, 2: 8.0, 3: 10.0, 4: 15.0}
const NM := 1854.0  # 0x6016a0
## Narrow seeker field of view (cos 6°, 0x6016c8).
const FOV_DEG := 6.0
## The circle around the HUD centre for the search and the launch (vfunc +0x44: 60·100 px²).
const CIRCLE_PX2 := 6000.0
## Search at most every 0.5 s; the seeker part of the update every 0.05 s.
const SEARCH_PERIOD := 0.5
const UPDATE_PERIOD := 0.05
## Limited heat (580): azimuth from the own heading at most 60° (0x6016e8).
const LIMITED_AZ_DEG := 60.0
## HUD pixels per degree (v1.1 HUD scale).
const PX_PER_DEG := 12.0
## Seeker symbol easing: pos = 0.3·goal + 0.7·pos (0x601680 / 0x601684); snaps within 5 px.
const EASE := 0.3
const SNAP_PX := 5.0

var cone_cos := cos(deg_to_rad(70.0))
var lock_range := 15.0 * NM
## Weapon data Real (real_weapons.gd): a rear-aspect seeker sees only a target moving away (ours:
## the target's velocity has a component away from the launcher; docs/real-weapons.md).
var rear_only := false
var target_key := ""  # this+0x14
var lock := false  # 0x82f6ec
## The seeker symbol (diamond), px from the HUD centre.
var symbol := Vector2.ZERO
var _next_search := -1.0e9
var _next_update := -1.0e9

## The radar's locked unit ("" none) and its A-A flag (FUN_00461680 / FUN_004625f0: slaved).
var radar_key := ""
var radar_aa := true

## Tone callback tone(kind): "seek", "lock" or "" (both off).
var tone: Callable
var _tone := ""


func set_generation(gen: int) -> void:
	if CONE_DEG.has(gen):
		cone_cos = cos(deg_to_rad(CONE_DEG[gen]))
		lock_range = RANGE_NM[gen] * NM


## The selected missile record (weapon_db.gd): its generation, then the Real overrides (cone, rear).
func set_weapon(w: Dictionary) -> void:
	set_generation(int(w.get("generation", 0)))
	if w.has("real_cone_deg"):
		cone_cos = cos(deg_to_rad(float(w.real_cone_deg)))
	rear_only = bool(w.get("real_rear", false))


## Screen offset (px, x right, y down) of a world point from the HUD centre: from the ray `own.sight`
## {fwd, up, right} (the camera ray through the HUD centre), else the nose basis of `own` {pos, fwd, up,
## right}; null when behind.
static func screen_offset(own: Dictionary, p: Vector3) -> Variant:
	var b: Dictionary = own.get("sight", own)
	var d: Vector3 = p - own.pos
	var f: float = d.dot(b.fwd)
	if f <= 0.0:
		return null
	return Vector2(rad_to_deg(atan2(d.dot(b.right), f)), -rad_to_deg(atan2(d.dot(b.up), f))) * PX_PER_DEG


## FUN_00461d10: limited heat (580) only within ±60° of the own heading (bearing, not aspect); range
## ≤ R; beyond R/2 only a target with a controller and its afterburner on.
func can_track(own: Dictionary, u: Dictionary, type: int) -> bool:
	var d: Vector3 = u.pos - own.pos
	if type == 580:
		var az := wrapf(atan2(d.x, d.y) - float(own.yaw), -PI, PI)
		if absf(az) > deg_to_rad(LIMITED_AZ_DEG):
			return false
	var r := d.length()
	if rear_only and (u.get("vel", Vector3.ZERO) as Vector3).dot(d) <= 0.0:
		return false
	if r > lock_range:
		return false
	return r <= lock_range / 2.0 or bool(u.get("afterburner", false))


## FUN_00461f10. With an A-A radar lock (FUN_004625f0): the target within the per-generation cone of the
## nose. Else in the free-look / padlock views (`own.helmet`): the camera axis `own.view_fwd` within the cone
## of the nose and the target within 6° of that axis. Else: within 6° of the nose.
func in_view(own: Dictionary, u: Dictionary) -> bool:
	var d: Vector3 = u.pos - own.pos
	if d.length() <= 0.0:
		return false
	var fov := cos(deg_to_rad(FOV_DEG))
	if radar_key != "" and radar_aa:
		return own.fwd.dot(d.normalized()) >= cone_cos
	if own.get("helmet", false):
		var a: Vector3 = own.view_fwd
		return own.fwd.dot(a) >= cone_cos and a.dot(d.normalized()) >= fov
	return own.fwd.dot(d.normalized()) >= fov


func slaved() -> bool:
	return radar_key != "" and radar_aa and target_key == radar_key


## FUN_00461680: keep a target that still passes can-track; else, at most every 0.5 s, the unit
## nearest the HUD centre inside the 6000 px² circle that passes can-track (no side test).
func search(now: float, own: Dictionary, units: Array, type: int) -> Dictionary:
	# A radar lock clears the seeker's own target; in A-A the seeker takes the locked unit at once
	# (no 0.5 s gate, no HUD circle).
	if radar_key != "":
		target_key = ""
		if radar_aa:
			target_key = radar_key
			return _find(units, radar_key)
	var cur := _find(units, target_key)
	if not cur.is_empty():
		if can_track(own, cur, type):
			return cur
		target_key = ""
		cur = {}
	if now < _next_search:
		return {}
	_next_search = now + SEARCH_PERIOD
	var best := CIRCLE_PX2
	for u in units:
		var off = screen_offset(own, u.pos)
		if off == null or off.length_squared() >= best or not can_track(own, u, type):
			continue
		best = off.length_squared()
		cur = u
	target_key = cur.get("key", "")
	return cur


## One frame of the IR mode (FUN_00461290): the seeker part every 0.05 s. `have_rounds` = the
## selected store has rounds left.
func update(now: float, own: Dictionary, units: Array, type: int, have_rounds: bool) -> void:
	if now < _next_update:
		return
	_next_update = now + UPDATE_PERIOD
	var t := search(now, own, units, type)
	if t.is_empty() or not in_view(own, t):
		_set_tone(false, have_rounds)
		symbol = symbol * (1.0 - EASE)
		return
	_set_tone(can_track(own, t, type), have_rounds)
	var goal = screen_offset(own, t.pos)
	if goal != null:
		symbol = EASE * goal + (1.0 - EASE) * symbol
		if absf(symbol.x - goal.x) < SNAP_PX and absf(symbol.y - goal.y) < SNAP_PX:
			symbol = goal


## The target a launch takes (FUN_00462ad0): the seeker target when inside the HUD-centre circle.
func target_in_circle(own: Dictionary, units: Array) -> Dictionary:
	var t := _find(units, target_key)
	if t.is_empty():
		return {}
	var off = screen_offset(own, t.pos)
	return t if off != null and off.length_squared() < CIRCLE_PX2 else {}


func current(units: Array) -> Dictionary:
	return _find(units, target_key)


## FUN_00461b00 on entering IR with an empty station: the seek tone starts; the next update stops it.
func start_empty_chirp() -> void:
	_tone = "seek"
	if tone.is_valid():
		tone.call("seek")


## FUN_00461bf0: no rounds → both tones off and no lock; else the lock or the seek tone.
func _set_tone(on: bool, have_rounds: bool) -> void:
	lock = on and have_rounds
	var want := "" if not have_rounds else ("lock" if on else "seek")
	if want != _tone:
		_tone = want
		if tone.is_valid():
			tone.call(want)


## Leaving the IR mode (FUN_00461bb0): both tones stop.
func exit() -> void:
	_tone = ""
	lock = false
	target_key = ""
	symbol = Vector2.ZERO
	if tone.is_valid():
		tone.call("")


static func _find(units: Array, key: String) -> Dictionary:
	if key == "":
		return {}
	for u in units:
		if u.key == key:
			return u
	return {}
