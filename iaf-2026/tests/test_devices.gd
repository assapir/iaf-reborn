# Modern IAF's Preferences → Devices → Keys and Joystick (iaf-2026/docs/front-end.md §9), headless, with synthetic
# input events and a fake joystick (Joystick.fake_devices): a key bound on the Keys screen is in the key table the
# flight reads; a key another command has shows the conflict, Swap trades them; Default and Reset all; an axis given
# the pitch role, inverted with a dead zone, drives the poller's stick y; a button and a hat direction bound by
# pressing them; the Hotas X's device map. The store is a temporary file (Settings.devices_path).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_devices.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const PITCH_UP := 24
const PITCH_DOWN := 25
const GUN := 64
const GEAR := 20
const LOOK_UP := 35
const DIK_K := 0x25
const RUDDER_LEFT := 37
const RUDDER_RIGHT := 38
const DIK_Z := 0x2c
const DIK_X := 0x2d
## The numpad's DIKs (crates/iaf-tools/src/sim.rs KEY_CODES): *, 7..Decimal, Enter, /.
const NUMPAD := [0x37, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x9c, 0xb5]

var kt: GDScript


func key_event(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	return e


func joy_button(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = true
	return e


func axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func store() -> Dictionary:
	return settings().load_json(settings().devices_file())


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.keys_file()):
		print("NEEDS DATA: the sim's key table (./modern-iaf-setup)")
		return
	kt = load("res://shared/controls/key_table.gd")
	s.devices_path = OS.get_temp_dir().path_join("iaf2026-test-devices-%d.json" % OS.get_process_id())
	DirAccess.remove_absolute(s.devices_path)
	s.sim_jet = "f16i"
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	for lang in ["en", "he"]:
		s.language = lang
		fe.pref_group = "devices"
		fe.show_page("prefs")
		await frames(2)
		var open: Button = fe.find_child("Pref_keys_screen", true, false).find_child("Control", true, false)
		check(open != null and fe.find_child("Pref_joystick_screen", true, false) != null, "%s: Devices rows" % lang)
		var joy: Control = fe.find_child("Pref_joystick_screen", true, false)
		check(
			joy.modulate.a < 1.0 and joy.find_child("Control", true, false).disabled and _has(joy, fe.s("joy_none")),
			"%s: no joystick: the Joystick row greyed and says so" % lang
		)
		open.pressed.emit()
		await frames(2)
		check(fe.page == "keys", "%s: Change opens the Keys screen" % lang)
		check(
			fe.layout_direction == (Control.LAYOUT_DIRECTION_RTL if lang == "he" else Control.LAYOUT_DIRECTION_LTR),
			"%s: direction" % lang
		)
	s.language = "en"
	fe.show_page("keys")
	await frames(2)
	await keys(fe)
	await joystick(fe)
	laptop()
	DirAccess.remove_absolute(s.devices_path)
	s.devices_path = ""
	s.apply_devices()


func keys(fe: Control) -> void:
	var s := settings()
	var ks: Node = fe.get_node("Keys")
	check(ks.records_of("sim").has(2) and not ks.records_of("sim").has(104), "listed: Pause; not: the chat")
	var listed := 0
	for g in ks.GROUPS:
		listed += ks.records_of(g).size()
	check(listed == 107, "keys: 107 commands listed (%d)" % listed)
	check(ks.GROUPS.all(func(g): return not ks.records_of(g).has(121)), "keys: no Ctrl+I idle (record 121 empty)")
	check(ks._rows[PITCH_UP].chip.text == "Up", "Pitch up shows Up (%s)" % ks._rows[PITCH_UP].chip.text)
	# Bind: click the row, press K.
	ks._rows[PITCH_UP].row.pressed.emit()
	check(ks.waiting == PITCH_UP and ks._rows[PITCH_UP].chip.text == "Press a key…", "the row waits for its key")
	root.push_input(key_event(KEY_K))
	await frames(1)
	check(int(store().get("keys", {}).get(str(PITCH_UP), 0)) == DIK_K, "the store has Pitch up on K: %s" % store())
	var flight_keys: RefCounted = kt.load_table()
	check(flight_keys.find_key(DIK_K, {}) == PITCH_UP, "the flight's key table has Pitch up on K")
	check(flight_keys.find_key(0xc8, {}) == -1, "and Up runs nothing now")
	check(ks._rows[PITCH_UP].chip.text == "K" and not ks._rows[PITCH_UP].reset.disabled, "the row shows K and Default")
	# Esc cancels.
	ks._rows[PITCH_DOWN].row.pressed.emit()
	root.push_input(key_event(KEY_ESCAPE))
	await frames(1)
	check(ks.waiting == -1 and fe.page == "keys", "Esc cancels the wait and stays on the screen")
	# Conflict: Pitch down on K, which Pitch up has.
	ks._rows[PITCH_DOWN].row.pressed.emit()
	root.push_input(key_event(KEY_K))
	await frames(1)
	check(ks.pending == [PITCH_DOWN, DIK_K, PITCH_UP], "conflict: K is Pitch up's (%s)" % str(ks.pending))
	var panel: Control = fe.find_child("Conflict", true, false)
	var said: Label = panel.find_children("*", "Label", true, false)[0] if panel != null else null
	check(said != null and said.text == fe.s("conflict") % ["K", "Pitch up"], "the conflict: %s" % said.text)
	panel.find_child("Swap", true, false).pressed.emit()
	await frames(1)
	flight_keys = kt.load_table()
	check(
		flight_keys.find_key(DIK_K, {}) == PITCH_DOWN and flight_keys.find_key(0xd0, {}) == PITCH_UP,
		"Swap: Pitch down on K, Pitch up on Down"
	)
	# Default for one, Reset all.
	ks._rows[PITCH_UP].reset.pressed.emit()
	check(kt.load_table().find_key(0xc8, {}) == PITCH_UP, "Default: Pitch up on Up again")
	fe.find_child("ResetAll", true, false).pressed.emit()
	check(store().get("keys", {}).is_empty(), "Reset all: no key stored (%s)" % store())
	check(kt.load_table().find_key(0xd0, {}) == PITCH_DOWN, "Reset all: Pitch down on Down")


func joystick(fe: Control) -> void:
	var s := settings()
	var js: Node = root.get_node("Joystick")
	js.fake_devices = [0]
	fe.pref_group = "devices"
	fe.show_page("prefs")
	Input.joy_connection_changed.emit(0, true)
	await frames(3)
	var joy: Control = fe.find_child("Pref_joystick_screen", true, false)
	check(
		joy.modulate.a == 1.0 and not joy.find_child("Control", true, false).disabled,
		"a joystick plugged in: the Joystick row comes alive"
	)
	fe.show_page("joystick")
	await frames(2)
	var scr: Node = fe.get_node("Joystick")
	check(fe.find_child("Device_0", true, false) != null, "the fake joystick is listed")
	check(
		scr._axis_rows.size() == 6 and scr.role_of(1) == "pitch" and scr.role_of(3) == "rudder", "axes 1..6, defaults"
	)
	# Axis 4 (Godot 3) becomes the pitch, inverted, dead zone 10 %.
	var row: Dictionary = scr._axis_rows[3]
	row.role.select(2)
	row.role.item_selected.emit(2)
	row.invert.button_pressed = true
	row.dead.value = 0.1
	check(scr.role_of(3) == "pitch" and scr.role_of(1) == "", "pitch on axis 4; axis 2 gave it up")
	check(s.joy_axes[1] == 3 and s.joy_axes[3] == -1, "joy_axes: pitch 3, rudder none (%s)" % str(s.joy_axes))
	check(js.tune[1][0] == true and is_equal_approx(js.tune[1][1], 0.1), "Joystick.tune pitch: %s" % str(js.tune[1]))
	check(store().get("axes", {}).has("pitch"), "the store has the pitch axis: %s" % store())
	s.flight_controls = 1
	axis(3, 1.0)
	js.poll()
	check(js.last_y == 100, "axis 4 at +1, inverted: stick y +100 (%d)" % js.last_y)
	axis(3, 0.05)
	js.poll()
	check(js.last_y == 0, "inside the 10 %% dead zone: 0 (%d)" % js.last_y)
	axis(3, 0.55)
	js.poll()
	check(js.last_y == 50, "0.55 inverted past 10 %%: +50 (%d)" % js.last_y)
	check(not js.rudder_used(), "no rudder axis: the rudder keys stay")
	# Roll None: the roll keys fly the roll, the pitch stays the joystick's.
	scr._axis_rows[0].role.item_selected.emit(0)
	check(s.joy_axes[0] == -1 and js.stick_mixed(), "roll none: the stick is mixed (%s)" % str(s.joy_axes))
	check(not js.drops_key(2) and js.drops_key(3), "roll none: the roll keys stay, the pitch keys drop")
	# A button and a hat direction, by pressing them.
	var bs: Node = scr.buttons
	bs._rows[GUN].row.pressed.emit()
	root.push_input(joy_button(5))
	await frames(1)
	check(kt.load_table().find_joystick(5, {}) == GUN, "Gun trigger on button 6")
	bs._rows[GEAR].row.pressed.emit()
	root.push_input(joy_button(JOY_BUTTON_DPAD_UP))
	await frames(1)
	check(bs.pending == [GEAR, 32, LOOK_UP], "hat up is Look up's: conflict (%s)" % str(bs.pending))
	bs.resolve("take")
	var t: RefCounted = kt.load_table()
	check(t.find_joystick(32, {}) == GEAR and int(t.records[LOOK_UP].joystick) == -1, "Use it here: gear on hat up")
	check(js.physical_button(JOY_BUTTON_DPAD_UP) == 32, "the sim's hat is buttons 32..35")
	fe.find_child("ResetAll", true, false).pressed.emit()
	check(store().get("buttons", {}).is_empty() and store().get("axes", {}).is_empty(), "Reset all: %s" % store())
	check(s.joy_axes == [0, 1, 2, 3, 4] and js.tune[1] == [false, 0.25], "Reset all: default axes")
	# The Hotas X's map.
	var map: String = IafDevices.find_map(s.joy_maps_dir(), "Thrustmaster T.Flight Hotas X")
	check(map.ends_with("hotas_x.json"), "the Hotas X has its map (%s)" % map)
	var d = JSON.parse_string(IafDevices.keys(ProjectSettings.globalize_path(s.keys_file()), s.devices_file(), map))
	check(int(d.records[GUN].joystick) == 0 and int(d.records[GEAR].joystick) == 8, "its buttons: gun 1, gear 9")
	js.fake_devices = []
	await frames(2)


## The laptop map (front-end.md §9.1), the platform forced to laptop: the rudder on Z / X, no two records on one key,
## no numpad key; a stored key still wins over it.
func laptop() -> void:
	var s := settings()
	s.laptop_keys = true
	var path := ProjectSettings.globalize_path(s.keys_file())
	check(path.ends_with("keys_laptop.json"), "laptop: the laptop table (%s)" % path)
	var d = JSON.parse_string(IafDevices.keys(path, s.devices_file(), ""))
	var key := func(r: int) -> int: return int(d.records[r].dik) | int(d.records[r].modifiers) << 16
	check(key.call(RUDDER_LEFT) == DIK_Z and key.call(RUDDER_RIGHT) == DIK_X, "laptop: rudder on Z / X")
	var seen := {}
	var twice := []
	var numpad := []
	for r in d.records:
		var k: int = int(r.dik) | int(r.modifiers) << 16
		if int(r.dik) in NUMPAD:
			numpad.append(r.index)
		if k != 0 and seen.has(k):
			twice.append([seen[k], r.index])
		seen[k] = r.index
	check(twice.is_empty(), "laptop: no key on two records %s" % [twice])
	check(numpad.is_empty(), "laptop: no numpad key %s" % [numpad])
	IafDevices.bind(path, s.devices_file(), "", RUDDER_LEFT, "key", DIK_K)
	d = JSON.parse_string(IafDevices.keys(path, s.devices_file(), ""))
	check(
		int(d.records[RUDDER_LEFT].dik) == DIK_K and int(d.records[RUDDER_LEFT].default_key) == DIK_Z, "laptop: K wins"
	)
	IafDevices.reset(s.devices_file(), -1, "key")
	s.laptop_keys = OS.get_name() == "macOS"


func _has(n: Node, text: String) -> bool:
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).text == text:
			return true
	return false
