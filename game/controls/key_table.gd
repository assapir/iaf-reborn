# The original key table (docs/controls.md, docs/front-end.md §12.7): 117 command records from
# iafjets.exe (converted by `iaf-convert keys` into assets/converted/keys.json), each with a press
# and a release command (id, p1, p2), a key (DirectInput scancode | modifier << 16), a joystick
# button and a "shown in the Controls list" flag. The player's rebinds are overrides kept in
# Settings.key_bindings ({record index: [key, joystick button]}); everything else is the default.
extends RefCounted

const PATH := "converted/keys.json"
## Modifier bits of a key (FUN_004df110 / 5103c0): one modifier per key, tested in this order.
const CTRL := 0x11
const SHIFT := 0x22
const ALT := 0x44
const WIN := 0x88

## DirectInput scancode -> Godot key (US positions, like the scancodes themselves).
const DIK_TO_KEY := {
	0x01: KEY_ESCAPE, 0x02: KEY_1, 0x03: KEY_2, 0x04: KEY_3, 0x05: KEY_4, 0x06: KEY_5, 0x07: KEY_6,
	0x08: KEY_7, 0x09: KEY_8, 0x0a: KEY_9, 0x0b: KEY_0, 0x0c: KEY_MINUS, 0x0d: KEY_EQUAL,
	0x0e: KEY_BACKSPACE, 0x0f: KEY_TAB, 0x10: KEY_Q, 0x11: KEY_W, 0x12: KEY_E, 0x13: KEY_R, 0x14: KEY_T,
	0x15: KEY_Y, 0x16: KEY_U, 0x17: KEY_I, 0x18: KEY_O, 0x19: KEY_P, 0x1a: KEY_BRACKETLEFT,
	0x1b: KEY_BRACKETRIGHT, 0x1c: KEY_ENTER, 0x1e: KEY_A, 0x1f: KEY_S, 0x20: KEY_D, 0x21: KEY_F,
	0x22: KEY_G, 0x23: KEY_H, 0x24: KEY_J, 0x25: KEY_K, 0x26: KEY_L, 0x27: KEY_SEMICOLON,
	0x28: KEY_APOSTROPHE, 0x29: KEY_QUOTELEFT, 0x2b: KEY_BACKSLASH, 0x2c: KEY_Z, 0x2d: KEY_X,
	0x2e: KEY_C, 0x2f: KEY_V, 0x30: KEY_B, 0x31: KEY_N, 0x32: KEY_M, 0x33: KEY_COMMA, 0x34: KEY_PERIOD,
	0x35: KEY_SLASH, 0x37: KEY_KP_MULTIPLY, 0x39: KEY_SPACE, 0x3a: KEY_CAPSLOCK, 0x3b: KEY_F1,
	0x3c: KEY_F2, 0x3d: KEY_F3, 0x3e: KEY_F4, 0x3f: KEY_F5, 0x40: KEY_F6, 0x41: KEY_F7, 0x42: KEY_F8,
	0x43: KEY_F9, 0x44: KEY_F10, 0x45: KEY_NUMLOCK, 0x46: KEY_SCROLLLOCK, 0x47: KEY_KP_7, 0x48: KEY_KP_8,
	0x49: KEY_KP_9, 0x4a: KEY_KP_SUBTRACT, 0x4b: KEY_KP_4, 0x4c: KEY_KP_5, 0x4d: KEY_KP_6,
	0x4e: KEY_KP_ADD, 0x4f: KEY_KP_1, 0x50: KEY_KP_2, 0x51: KEY_KP_3, 0x52: KEY_KP_0,
	0x53: KEY_KP_PERIOD, 0x57: KEY_F11, 0x58: KEY_F12, 0x64: KEY_F13, 0x65: KEY_F14, 0x66: KEY_F15,
	0x9c: KEY_KP_ENTER, 0xb5: KEY_KP_DIVIDE, 0xb7: KEY_PRINT, 0xc7: KEY_HOME, 0xc8: KEY_UP,
	0xc9: KEY_PAGEUP, 0xcb: KEY_LEFT, 0xcd: KEY_RIGHT, 0xcf: KEY_END, 0xd0: KEY_DOWN,
	0xd1: KEY_PAGEDOWN, 0xd2: KEY_INSERT, 0xd3: KEY_DELETE, 0xdd: KEY_MENU,
}
## Modifier keys are never bound on their own (the capture skips them, 5103c0).
const MODIFIER_KEYS := [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]

var records: Array = []
var key_names := {}
var modifier_prefixes: Array = []
var button_format := "Button %d"
var _key_to_dik := {}


static func load_table() -> RefCounted:
	var t: RefCounted = load("res://controls/key_table.gd").new()
	t._load(Settings.assets_dir().path_join(PATH))
	return t


func _load(path: String) -> void:
	for dik in DIK_TO_KEY:
		_key_to_dik[DIK_TO_KEY[dik]] = dik
	if not FileAccess.file_exists(path):
		push_error("key table missing (%s): run tools/setup.sh" % path)
		return
	var d := Settings.load_json(path)
	if d.is_empty():
		return
	records = d.records
	key_names = d.key_names
	modifier_prefixes = d.modifiers
	button_format = d.get("button_format", button_format)


func size() -> int:
	return records.size()


## The default key of record i: DIK | modifiers << 16 (0 = none).
func default_key(i: int) -> int:
	return int(records[i].dik) | (int(records[i].modifiers) << 16)


func default_joystick(i: int) -> int:
	return int(records[i].joystick)


## The key / joystick button of record i with the player's overrides.
func key_of(i: int, overrides: Dictionary) -> int:
	return int(overrides[i][0]) if overrides.has(i) else default_key(i)


func joystick_of(i: int, overrides: Dictionary) -> int:
	return int(overrides[i][1]) if overrides.has(i) else default_joystick(i)


## Sets record i's key (or button) in `overrides`, dropping the entry when it is the default again.
func set_binding(overrides: Dictionary, i: int, key: int, joystick: int) -> void:
	if key == default_key(i) and joystick == default_joystick(i):
		overrides.erase(i)
	else:
		overrides[i] = [key, joystick]


## The label of record i (keys.trx line i; the Hebrew pack's line when present and asked for).
func label(i: int, hebrew := false) -> String:
	var r: Dictionary = records[i]
	if hebrew and r.get("label_he") != null and String(r.label_he) != "":
		return r.label_he
	return r.label


## Key name as the Controls page shows it (FUN_005107c0): "Ctrl + " etc. + the DIK name.
func key_name(key: int) -> String:
	if key == 0:
		return ""
	var mods := (key >> 16) & 0xff
	var prefix := ""
	for m in modifier_prefixes:
		if mods & int(m.bits):
			prefix = m.prefix
			break
	return prefix + String(key_names.get(str(key & 0xffff), ""))


## Joystick button name (FUN_00511070): "Button n" (1-based), empty for none.
func button_name(joystick: int) -> String:
	return button_format.replace("%d", str(joystick + 1)) if joystick > -1 else ""


## The records listed on the Controls page (shown flag ≠ 0, FUN_005102f0), in table order.
func shown_records() -> Array:
	var out := []
	for i in records.size():
		if records[i].shown:
			out.append(i)
	return out


## DirectInput scancode of a Godot key event (physical position; tests send only keycodes), 0 = none.
func dik_of(event: InputEventKey) -> int:
	var k := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	return _key_to_dik.get(k, 0)


func godot_key(dik: int) -> Key:
	return DIK_TO_KEY.get(dik, KEY_NONE)


## The one modifier of an event: Ctrl, then Shift, Alt, Win (the capture's order).
static func modifiers_of(event: InputEventWithModifiers) -> int:
	if event.ctrl_pressed:
		return CTRL
	if event.shift_pressed:
		return SHIFT
	if event.alt_pressed:
		return ALT
	if event.meta_pressed:
		return WIN
	return 0


## The key of an event as the table stores it (0 for a lone modifier or an unknown key).
func key_of_event(event: InputEventKey) -> int:
	var dik := dik_of(event)
	if dik == 0:
		return 0
	return dik | (modifiers_of(event) << 16)


## The first record bound to this key (FUN_004df3d0 stops at the first match), -1 = none.
func find_key(key: int, overrides: Dictionary, exclude := -1) -> int:
	if key == 0:
		return -1
	for i in records.size():
		if i != exclude and key_of(i, overrides) == key:
			return i
	return -1


func find_joystick(button: int, overrides: Dictionary, exclude := -1) -> int:
	if button < 0:
		return -1
	for i in records.size():
		if i != exclude and joystick_of(i, overrides) == button:
			return i
	return -1


## True while record i's key is held with exactly its modifier (polled every frame for the
## held commands: stick, rudder).
func held(i: int, overrides: Dictionary) -> bool:
	var key := key_of(i, overrides)
	var k := godot_key(key & 0xffff)
	if k == KEY_NONE or not (Input.is_physical_key_pressed(k) or Input.is_key_pressed(k)):
		return false
	return _held_modifiers() == (key >> 16) & 0xff


static func _held_modifiers() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return CTRL
	if Input.is_key_pressed(KEY_SHIFT):
		return SHIFT
	if Input.is_key_pressed(KEY_ALT):
		return ALT
	if Input.is_key_pressed(KEY_META):
		return WIN
	return 0
