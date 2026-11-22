# The player's radar (docs/radar.md). The logic is iaf_avionics::radar (crates/iaf-avionics/src/radar.rs) through
# IafRadar; this keeps its GDScript face: the owner (player_weapons.gd) sets the callbacks, calls the keys and
# update(), and reads the mirrored state. World frame X east, Y north, Z up, metres, sim seconds.
extends RefCounted

enum { OFF, STBY, STT, BORE, LRS, TWS, ACM, GMT, MAP }
## Ours: the real F-16 FCR's events (player_weapons.gd radar_event; no original event has these numbers).
const EV_TMS := -20
const EV_SUBMODE := -21
const EV_AZIMUTH := -22
const EV_BARS := -23
const EV_ELEVATION := -24
const EV_OVRD := -25
const EV_CURSOR := -26
const EV_CNTL := -27
## Ours, the real FCR's A-G: the GM format's OSBs 7..10 (arg the OSB), the ground cursor on a world point (arg).
const EV_AG_OSB := -28
const EV_GROUND := -29

## bdb type code → cockpit index (FUN_00447e70).
const COCKPIT := preload("res://shared/aircraft/player_aircraft.gd").COCKPIT
## Ours: a jet with an aircraft definition has its radar.row (the F-16I's iaf_avionics::radar::F16I, docs/f16i.md §2;
## the F-35I's radar::F35I).

# Mirrored after every call (IafRadar.state()).
var modes := {}  ## mode → {max (range index), nm, idx (current range index 1..max)}
var mode := OFF
var last_aa := LRS
var aa := true
var off := true
var damaged := false
## The contact list (15, nearest first): {key, unit, pos, heading, locked, selected, hostile, prio, aspect, az,
## el, dist, speed, type, alt, mach}.
var contacts: Array = []
var antenna := Vector2.ZERO
var designated := false
var desig := Vector3.ZERO
var exp := false
var heading_shift := 0.0
## Radiating (ours: not with weight on wheels; the real FCR not in OVRD).
var emit := false
## Ours, the real F-16 FCR (docs/radar.md §9; {} the original's radar): half (scan's half width, deg), bars, elevation,
## cursor (0..1 across ±60°, up), cursor_alt (ft high / low, NAN none), vsr, sam (keys, the primary last), acm (0
## 20, 1 60, 2 SLEW), ovrd, volume (az from, az to, el low, el high; deg), vsr_max (kt), exp (EXP showing), cntl (the
## CNTL page's value indices, IafRadar.cntl_table's order), history (TGT HIS: x, y on the scope, z the frames back),
## ag (A-G: {name, fov, zoom, frame {centre, yaw, k, sym}, cursor (MFD px), ground, frozen, snowplow, tgt, agr, pic};
## IafRadar ag).
var real := {}
## Ours: the point the A-G weapons aim at (radar.rs target_point: the real FCR's ground track, else the designated
## point), null none; the real FCR's GM picture of the last frame (LA8 bytes over real.ag.pic.window).
var spi = null
var pic := PackedByteArray()
var _pic_serial := -1

## Owner callbacks: units() -> [{key, pos, vel, ent, hostile}], ground(world) -> height or null,
## own() -> {pos, vel, fwd, up, right, yaw}, on_lock(key, on) (the target's RWR), illumination_lost()
## (FUN_00458130: the semi-active missiles lose their guidance), detected(key) (a scan recorded the unit: known to
## the player, @4afae6).
var units: Callable
var ground: Callable
var own: Callable
var on_lock: Callable
var illumination_lost: Callable
var detected: Callable

var _r = ClassDB.instantiate("IafRadar")
var _st := {}
var _by_key := {}


## Create (FUN_004ace60) for the aircraft of bdb type `type_code`; `lrs_nm` overrides the LRS / STT detection
## range (Weapon data Real). The radar starts OFF. Ours, with either Weapon data: a jet with an aircraft definition
## takes its radar.row (the F-16I Sufa the APG-68(V)9's, the F-35I the APG-81's); both start at 80 NM (in Modern
## IAF in STBY); its radar.fcr gives the real F-16 FCR's controls (the Sufa's) where Settings.modern_radar()
## (Modern IAF), with its power rules: STBY at power-on, no radiating with weight on wheels (docs/radar.md §9.1). A
## definition's radar.auto (the F-35I: no radar switch, the mission systems run it) takes the power rules in both games.
func setup(type_code: int, lrs_nm := 0.0) -> void:
	var def: Dictionary = Settings.airframe(type_code).get("radar", {})
	var row := int(def.get("row", COCKPIT.get(type_code, 1)))
	var modern: bool = Settings.modern_radar()
	var fcr := int(def.get("fcr", {}).get("sam_tracks", 0)) if modern else 0
	_r.setup(row, lrs_nm, fcr, modern or bool(def.get("auto", false)))
	# The real FCR's GM picture shows the runways dark (shared/terrain/airbases.gd: world metres, width).
	if modern:
		var list := []
		for b in load("res://shared/terrain/airbases.gd").bases():
			for rw in b.get("runways", []):
				var e: Array = rw.ends
				list.append(PackedFloat64Array([e[0][0], e[0][1], e[1][0], e[1][1], float(rw.width)]))
		_r.set_runways(list)
	_sync()


## Hands the own pose, the units and the terrain to the next call.
func _feed() -> void:
	var list := []
	_by_key = {}
	for u in units.call() if units.is_valid() else []:
		var e: Dictionary = u.ent
		_by_key[u.key] = u
		list.append(
			{
				"key": u.key,
				"pos": u.pos,
				"vel": u.vel,
				"klass": int(e.get("klass", -1)),
				"state": int(e.get("state", 1)),
				"coll_radius": float(e.get("coll_radius", 0.0)),
				"heading": float(e.get("heading", 0.0)),
				"type": int(e.get("type_code", -1)),
				"hostile": bool(u.get("hostile", true)),
				"rcs": e.get("rcs"),  # ours: Modern IAF's drones (docs/ai.md §16); absent: the tables' ranges
				"jam": float(e.get("jam", 0.0))  # ours: its jammer on (Modern IAF, docs/radar.md §8)
			}
		)
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
	emit = _st.emit
	real = _st.real
	spi = _st.get("spi")
	var serial := int(real.get("ag", {}).get("pic", {}).get("serial", -1))
	if serial != _pic_serial:
		_pic_serial = serial
		pic = _r.picture()
	contacts = (_st.contacts as Array).map(_attach)
	_st.locked = _attach(_st.locked)
	for e in _r.events():
		if e[0] == "lock":
			if on_lock.is_valid():
				on_lock.call(e[1], e[2])
		elif e[0] == "detected":
			if detected.is_valid():
				detected.call(e[1])
		elif illumination_lost.is_valid():
			illumination_lost.call()


## A record gets its unit ({key, pos, vel, ent, hostile}) back.
func _attach(c: Dictionary) -> Dictionary:
	if not c.is_empty() and _by_key.has(c.key):
		c.unit = _by_key[c.key]
	return c


## Ours: the last search's jam strobes, each a jammer's azimuth off the nose (rad; docs/radar.md §8).
func strobes() -> PackedFloat64Array:
	return _st.get("strobes", PackedFloat64Array())


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


## Ours, the DGFT / MSL OVRD switch (player_weapons.gd override_key): mode `m` at once (IafRadar.set_mode).
func set_mode(m: int, now: float) -> void:
	_feed()
	_r.set_mode(m, now)
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


## Event 0x32 (a TWS press on a blip): select it, unlocked.
func select_key(key: String) -> bool:
	var ok: bool = _r.select_key(key)
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


# --- ours: the real FCR (docs/radar.md §9) ------------------------------------------------------


## The TMS: 0 up (bug / lock; ACM BORE), 1 down (drop; ACM 30 × 20), 2 right (CRM submode; ACM 10 × 60), 3 left
## (ACM SLEW).
func tms(dir: int, now: float) -> void:
	_feed()
	_r.tms(dir, now)
	_sync()


## OSB 2: CRM's RWS / TWS / VSR, ACM's 20 / 60 / SLEW / BORE.
func cycle_submode(now: float) -> void:
	_feed()
	_r.cycle_submode(now)
	_sync()


## OSB 18 (azimuth) or OSB 17 (bars).
func step_scan(bars: bool) -> void:
	_r.step_scan(bars)
	_sync()


## The antenna elevation thumbwheel (−1..1, 0 stops).
func set_elevation_rate(rate: float) -> void:
	_r.set_elevation_rate(rate)


## The cursor's slew (x right, y up, −1..1) and its place on the scope (0..1 across, up).
func set_cursor_slew(x: float, y: float) -> void:
	_r.set_cursor_slew(x, y)


func set_cursor(x: float, y: float) -> void:
	_r.set_cursor(x, y)


## A press on the CNTL page's OSB.
func cntl_press(osb: int) -> void:
	_r.cntl_press(osb)
	_sync()


## OSB 4 OVRD.
func toggle_ovrd() -> void:
	_r.toggle_ovrd()
	_sync()


## The GM format's OSB 7 FZ, 8 SP, 9 CZ, 10 STP / TGT.
func ag_press(osb: int, now: float) -> void:
	_feed()
	_r.ag_press(osb, now)
	_sync()


## The A-G ground cursor on a world point (a mouse move over the GM display).
func set_ground_cursor(w: Vector3) -> void:
	_r.set_ground_cursor(w)


## AGR: a visual delivery's aim point (the CCIP pipper's ground point), null none.
func set_agr(at) -> void:
	_r.set_agr(at)


## Damage (cases 0xf / 0x13 / 0x15, FUN_004adb20): off, every call a no-op.
func set_damaged(on: bool) -> void:
	_r.set_damaged(on)
	_sync()
