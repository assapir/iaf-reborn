# The joystick (autoload "Joystick"; docs/controls.md §4): the original's DirectInput poller
# FUN_004df560, run every idle frame (FUN_004e1df0), ported onto Godot's joypad API (SDL). One device: the
# first connected joypad (the original used the first DirectInput joystick its EnumDevices callback
# FUN_004e0f90 could open). Each poll turns the axes into the original's game events, sent only when the
# integer value changes: GEV 1 stick (x, y ±100), GEV 9 throttle (0..100), GEV 10 rudder (±100) and GEV 22
# from the POV hat (the snap views). Buttons reach the key table in the scenes (FUN_004e0dc0 → record +0x1c).
extends Node

## The original's DirectInput axes lX, lY, lZ, lRz as Godot axis numbers: Settings.joy_axes
## (default [0, 1, 2, 3]; ours: Godot / SDL hide the DirectInput axis names, docs/controls.md §4.2).
const DEAD_ZONE := 0.25  ## DIPROP_DEADZONE 2500 (of 10000) on lX, lY and the rudder axis (@4e116f, 4e11f3, 4e12e2 / 4e1333); none on lZ
## The hat as Godot reports it: the D-pad buttons.
const HAT := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]
## POV (hundredths of a degree) → GEV 22 (p1 angle, p2 numpad digit) (@4dfa2c..4dfbae): the snap-view keys'
## own values; centred (0xffff) sends (−1, 5).
const POV := {0: [0, 8], 4500: [45, 9], 9000: [90, 6], 13500: [135, 3], 18000: [180, 2],
	22500: [225, 1], 27000: [270, 4], 31500: [315, 7], 0xffff: [-1, 5]}
const JOY_DIR := "install/resource/menu/joy"

## Tests: device ids to treat as connected (Godot has no script hook to plug a joypad in).
var fake_devices: Array = []
## The flight scene while it takes the events; without one, poll() still runs and its events are
## dropped (the original's poller runs in the menus too).
var consumer: Node = null
## The last values sent (this+0x144 x, +0x148 y, +0x14c throttle, +0x150 rudder; kept across flights).
var last_x := 0
var last_y := 0
var last_throttle := 0
var last_rudder := 0
## POV: the last state (DAT_0064acdc, 0xffff = centred at start), whether a direction was sent
## (DAT_008338ec) and the release to send before the next one (DAT_008338e0 / e4: (−1, −digit)).
var _pov_last := 0xffff
var _pov_sent := false
var _pov_release := [-1, -5]
## The default table's button column from a matching menu/joy/*.joy (FUN_004e1590): record → button
## (records not listed: none); null = no file matched, the table's own column.
var default_buttons = null
var _device := -1


## The joystick in use: the first connected joypad, −1 = none. Tests (Settings.isolated()) see only
## their fake devices, never a real stick that happens to be plugged in.
func device() -> int:
	var ids: Array = fake_devices + ([] if Settings.isolated() else Input.get_connected_joypads())
	return int(ids[0]) if not ids.is_empty() else -1


## The Devices page choices act only with a joystick (this+0x18..0x20 "device has the axis" &&
## this+0x24..0x2c the choice, FUN_004df4e0). Godot cannot tell a missing axis: a device has all four.
func stick_used() -> bool:
	return device() >= 0 and Settings.flight_controls == 1


func throttle_used() -> bool:
	return device() >= 0 and Settings.throttle == 1


func rudder_used() -> bool:
	return device() >= 0 and Settings.rudder == 1


## FUN_004e0f40: the throttle axis (0..100) while used, else −1 (the autopilot's re-sync, docs/autopilot.md).
func throttle_axis() -> int:
	return last_throttle if throttle_used() else -1


## A key-table key event dropped while an axis is used (FUN_004e0b80): roll / pitch (2, 3) with the stick,
## RPM ± 5 and the throttle presets (5, 6, 9) with the throttle, the rudder keys (10) with the rudder.
func drops_key(id: int) -> bool:
	match id:
		2, 3:
			return stick_used()
		5, 6, 9:
			return throttle_used()
		10:
			return rudder_used()
	return false


## A joypad event from the joystick in use.
func ours(event: InputEvent) -> bool:
	return (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == device() and device() >= 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the original polls in every idle frame


func _process(_delta: float) -> void:
	var d := device()
	if d != _device:
		_device = d
		_connected(d)
	if consumer == null or not is_instance_valid(consumer):
		consumer = null
		poll()


## One FUN_004df560 pass: the events [id, p1, p2] of the axes and the hat that changed.
func poll() -> Array:
	var d := device()
	if d < 0:
		return []
	var ax: Array = Settings.joy_axes if Settings.joy_axes.size() == 4 else [0, 1, 2, 3]
	var out := []
	if Settings.flight_controls == 1:
		# MulDiv(lX, 200, max − min) − 100 and MulDiv(lY, −200, max − min) + 100 (@4df6b8, 4df770).
		var x := _lin(_dead(Input.get_joy_axis(d, ax[0])), 200) - 100
		if x != last_x:
			last_x = x
			out.append([1, last_x, last_y])
		var y := 100 - _lin(_dead(Input.get_joy_axis(d, ax[1])), 200)
		if y != last_y:
			last_y = y
			out.append([1, last_x, last_y])
	if Settings.throttle == 1:
		# MulDiv(lZ, −100, max − min) + 100 (@4df825): lever forward (axis −1) = 100.
		var t := 100 - _lin(Input.get_joy_axis(d, ax[2]), 100)
		if t != last_throttle:
			last_throttle = t
			out.append([9, last_throttle, 0])
	if Settings.rudder == 1:
		# MulDiv(lRz, 200, max − min) − 100 (@4df8d7).
		var r := _lin(_dead(Input.get_joy_axis(d, ax[3])), 200) - 100
		if r != last_rudder:
			last_rudder = r
			out.append([10, last_rudder, 0])
	if Settings.flight_controls == 1:
		var pov := _pov(d)
		if pov != _pov_last:
			if _pov_sent:
				out.append([22, _pov_release[0], _pov_release[1]])
			var v: Array = POV.get(pov, [])
			_pov_sent = not v.is_empty()
			if _pov_sent:
				out.append([22, v[0], v[1]])
				_pov_release = [-1, -int(v[1])]
			_pov_last = pov
	return out


## FUN_004e0a60 (the flush): the hat counts as centred again, so a held direction is sent anew; returns
## the GEV 22 (−1, −5) it sends.
func flush() -> Array:
	_pov_last = 0xffff
	return [22, -1, -5]


## DirectInput's dead zone: the centre within ±25 % of the half range, the rest scaled to the full range.
static func _dead(v: float) -> float:
	var a := absf(v)
	return 0.0 if a <= DEAD_ZONE else signf(v) * (a - DEAD_ZONE) / (1.0 - DEAD_ZONE)


## MulDiv(value, scale, 65535) of the axis (−1..1 → DirectInput 0..65535), rounded as MulDiv rounds.
static func _lin(v: float, scale: int) -> int:
	return int(floor((clampf(v, -1.0, 1.0) + 1.0) * 0.5 * scale + 0.5))


## rgdwPOV[0] from the hat buttons: hundredths of a degree clockwise from up, 0xffff = centred.
func _pov(d: int) -> int:
	var u := Input.is_joy_button_pressed(d, HAT[0])
	var r := Input.is_joy_button_pressed(d, HAT[1])
	var dn := Input.is_joy_button_pressed(d, HAT[2])
	var l := Input.is_joy_button_pressed(d, HAT[3])
	if u and r:
		return 4500
	if r and dn:
		return 13500
	if dn and l:
		return 22500
	if l and u:
		return 31500
	if u:
		return 0
	if r:
		return 9000
	if dn:
		return 18000
	if l:
		return 27000
	return 0xffff


func _connected(d: int) -> void:
	default_buttons = null
	if d < 0:
		print("joystick: none")
		return
	var name := Input.get_joy_name(d)
	print("joystick: %s (device %d, %s); axes x / y / throttle / rudder = %s" % [name, d, Input.get_joy_guid(d), str(Settings.joy_axes)])
	_load_joy_map(name)


## FUN_004e1590 (`<install>\Joy\*.JOY`): the first file whose first line is part of the device's product
## name sets the default table's buttons: all none, then line k (0-based after the name) = record n − 1 (n
## in 1..117; 0 = no record) on button k.
func _load_joy_map(name: String) -> void:
	var dir := Settings.assets_dir().path_join(JOY_DIR)
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.to_lower().ends_with(".joy"))
	files.sort()
	for f in files:
		var lines := FileAccess.get_file_as_string(dir.path_join(f)).split("\n")
		var want := lines[0].strip_edges() if lines.size() > 0 else ""
		if want == "" or not name.contains(want):
			continue
		if lines[lines.size() - 1].strip_edges() == "":
			lines.remove_at(lines.size() - 1)  # the last line's end, not a line (fgets)
		default_buttons = {}
		for k in range(1, lines.size()):
			var n := lines[k].strip_edges().to_int()  # atoi
			if n > 0 and n < 0x76:
				default_buttons[n - 1] = k - 1
		print("joystick: buttons from %s" % f)
		return
