# The switch keys of the sim's key table in a flight (modern-iaf/data/keys.json records 200-207; the user, 2026-11-18:
# the speedbrakes worked only through the wheel-brake key, and MPO, CAT III, the roll trim and the GPS bomb's keys had
# no row on the Keys screen). The Barak's take-off mission, the jet put in the air at 200 m/s:
# - the wheel-brake key (Shift + G) in the air opens no speedbrake;
# - B held opens the speedbrakes at their own rate; let go, they stay; Shift + B closes them (the user, 2026-11-18:
#   "B should be the airbrake");
# - Alt + Right held moves the roll trim; Alt + M held is MPO; Alt + S flips STORES CONFIG;
# - a key bound to one of them on the Keys screen works it, and its old key no longer does;
# - no command of the table is the drag chute's; chaff, flares and the weapon view are on keys a Mac laptop has.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_switch_keys.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## key_table.gd, loaded in run(): it names the Settings autoload, which a preload here would compile before.
var kt: GDScript
const MPO := 204


func _press(tv: Node, k: Key, mods := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = mods == kt.SHIFT
	e.alt_pressed = mods == kt.ALT
	e.pressed = true
	tv._unhandled_input(e)


func _name(tv: Node, record: int) -> String:
	return tv.keys.key_name(tv.keys.default_key(record))


func run() -> void:
	await require_data()
	kt = load("res://shared/controls/key_table.gd")
	var s := settings()
	var was: bool = kt.cmd_is_ctrl
	kt.cmd_is_ctrl = false  # the key names as the table writes them
	var id := sim_mission("ramat_david_takeoff")
	check(load("res://flight/fly.gd").prepare(id), "the Barak's take-off mission prepared (%d)" % id)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	tv.addon.result = {"pass": true}  # unscored: the flight goes on
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 3000.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 200.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.7
	tv.brakes = false
	await frames(10)
	var keys = tv.keys
	check(
		not range(keys.size()).any(func(i): return keys.default_key(i) != 0 and keys.records[i].press[0] == 19),
		"no key for a drag chute"
	)
	var mac := [70, 71, 84].map(func(r): return _name(tv, r))
	check(mac == ["Ctrl + Z", "Ctrl + X", "F2"], "chaff, flares and the weapon view on a Mac laptop's keys %s" % [mac])
	# The wheel-brake key alone: the switch moves, no speedbrake.
	_press(tv, KEY_G, kt.SHIFT)
	await fly(tv, 1.0)
	check(tv.brakes and tv._speed_brake_deg < 0.1 and not tv.speed_brake_out(), "Shift + G in the air: no speedbrake")
	check(not tv.gear_down, "Shift + G leaves the gear alone")
	_press(tv, KEY_G, kt.SHIFT)
	check(not tv.brakes, "Shift + G again: the wheel brakes off")
	# B held for a second: 30 deg/s; let go: they stay.
	set_key(KEY_B, true)
	await fly(tv, 1.0)
	set_key(KEY_B, false)
	await frames(2)
	var half: float = tv._speed_brake_deg
	check(half > 20.0 and half < 40.0 and tv.speed_brake_out(), "B held 1 s: half open (%.1f)" % half)
	await fly(tv, 1.0)
	var stays: float = tv._speed_brake_deg
	check(absf(stays - half) < 3.0, "let go: the speedbrakes stay (%.1f)" % stays)
	# Shift + B, with Shift let go first (as a hand does): B alone, still down, opens nothing.
	set_key(KEY_SHIFT, true)
	set_key(KEY_B, true)
	_press(tv, KEY_B, kt.SHIFT)
	await frames(2)
	set_key(KEY_SHIFT, false)
	await fly(tv, 3.0)
	set_key(KEY_B, false)
	await frames(2)
	check(tv._speed_brake_deg < 0.1 and not tv.speed_brake_out(), "Shift + B: closed (%.1f)" % tv._speed_brake_deg)
	# The roll trim, MPO and STORES CONFIG by their records' keys.
	set_key(KEY_ALT, true)
	set_key(KEY_RIGHT, true)
	set_key(KEY_M, true)
	await fly(tv, 0.5)
	var trim: float = tv.flight.roll_trim()
	check(trim > 0.0 and tv.mpo_on, "Alt + Right trims right (%.3f), Alt + M is MPO (%s)" % [trim, tv.mpo_on])
	set_key(KEY_RIGHT, false)
	set_key(KEY_M, false)
	set_key(KEY_ALT, false)
	await fly(tv, 0.5)
	check(tv.flight.roll_trim() == trim and not tv.mpo_on, "let go: the trim stays, MPO off")
	# The arrow down before Alt: a key with a modifier still starts when the modifier comes second.
	set_key(KEY_RIGHT, true)
	await frames(2)
	set_key(KEY_ALT, true)
	await fly(tv, 0.5)
	set_key(KEY_RIGHT, false)
	set_key(KEY_ALT, false)
	await frames(2)
	check(tv.flight.roll_trim() > trim, "Right, then Alt: the trim moves (%.3f)" % tv.flight.roll_trim())
	trim = tv.flight.roll_trim()
	_press(tv, KEY_S, kt.ALT)
	check(tv.cat3, "Alt + S: STORES CONFIG at CAT III")
	_press(tv, KEY_S, kt.ALT)
	check(not tv.cat3, "Alt + S again: CAT I")
	_press(tv, KEY_K)  # the GPS bomb's key with no such bomb: nothing, and no error
	# Rebound on the Keys screen: MPO on J; Alt + M no longer holds it.
	keys.set_column(s.key_bindings, MPO, "key", 0x24)
	set_key(KEY_J, true)
	await frames(3)
	check(tv.mpo_on, "MPO rebound to J: J holds it")
	set_key(KEY_J, false)
	set_key(KEY_ALT, true)
	set_key(KEY_M, true)
	await frames(3)
	check(not tv.mpo_on, "MPO rebound to J: Alt + M does nothing")
	set_key(KEY_M, false)
	set_key(KEY_ALT, false)
	s.key_bindings = {}
	kt.cmd_is_ctrl = was
