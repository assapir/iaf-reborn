# Modern IAF's Preferences → Devices → Keys and Joystick (modern-iaf/docs/front-end.md §9), headless, with synthetic
# input events and a fake joystick (Joystick.fake_devices): a key bound on the Keys screen is in the key table the
# flight reads; a key another command has shows the conflict, Swap trades them; Default and Reset all; an axis given
# the pitch role, inverted with a dead zone, drives the poller's stick y; a button bound by pressing it; the axes and
# the hat against the 1998 game's poller; the Hotas X's device map. The keys and buttons are Settings.key_bindings
# (both games' store; a devices.json from before 2026-11-14 and a reborn settings.cfg both load into it), the axes'
# store a temporary file (Settings.devices_path).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_devices.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const PITCH_UP := 24
const PITCH_DOWN := 25
const GUN := 64
const GEAR := 20
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
	old_files()
	DirAccess.remove_absolute(s.devices_path)
	s.devices_path = ""
	s.apply_devices()


func keys(fe: Control) -> void:
	var s := settings()
	var ks: Node = fe.get_node("Keys")
	# The side list follows the scroll; a tab's click scrolls to its group; Back as Esc (items 4, 6).
	var views: Button = fe.find_child("Tab_views", true, false)
	ks.scroll.scroll_vertical = int(ks._heads["views"].position.y) + 20
	await frames(1)
	check(views.button_pressed, "scrolled into Views: its tab lights")
	(fe.find_child("Tab_weapons", true, false) as Button).pressed.emit()
	await frames(1)
	check(
		ks.scroll.scroll_vertical == int(ks._heads["weapons"].position.y) and not views.button_pressed,
		"Weapons' tab: the list at Weapons"
	)
	check(
		fe.find_child("Back", true, false) != null and fe.find_child("Crumb_prefs", true, false) != null, "Back, crumbs"
	)
	check(ks.records_of("sim").has(2) and not ks.records_of("sim").has(104), "listed: Pause; not: the chat")
	var listed := 0
	for g in ks.GROUPS:
		listed += ks.records_of(g).size()
	check(listed == 99, "keys: 99 commands listed, one head-look set (%d)" % listed)
	check(
		ks.GROUPS.all(func(g): return [74, 86, 89, 93].all(func(r): return not ks.records_of(g).has(r))),
		"keys: no free look or F2 rear view (the snap views and the mouse look around)"
	)
	check(ks.records_of("flight").has(121), "keys: Throttle OFF listed (record 121, the engine shutdown)")
	check(ks._rows[PITCH_UP].chip.text == "Up", "Pitch up shows Up (%s)" % ks._rows[PITCH_UP].chip.text)
	# Bind: click the row, press K.
	ks._rows[PITCH_UP].row.pressed.emit()
	check(ks.waiting == PITCH_UP and ks._rows[PITCH_UP].chip.text == "Press a key…", "the row waits for its key")
	root.push_input(key_event(KEY_K))
	await frames(1)
	var b: Dictionary = s.key_bindings
	check(b.get(PITCH_UP, []) == [DIK_K, null], "the store has Pitch up on K, its button the default: %s" % b)
	var flight_keys: RefCounted = kt.load_table()
	check(flight_keys.find_key(DIK_K, b) == PITCH_UP, "the flight's key table has Pitch up on K")
	check(flight_keys.find_key(0xc8, b) == -1, "and Up runs nothing now")
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
		flight_keys.find_key(DIK_K, b) == PITCH_DOWN and flight_keys.find_key(0xd0, b) == PITCH_UP,
		"Swap: Pitch down on K, Pitch up on Down"
	)
	# Default for one, Reset all.
	ks._rows[PITCH_UP].reset.pressed.emit()
	check(kt.load_table().find_key(0xc8, b) == PITCH_UP, "Default: Pitch up on Up again")
	fe.find_child("ResetAll", true, false).pressed.emit()
	check(b.is_empty(), "Reset all: no key stored (%s)" % b)
	check(kt.load_table().find_key(0xd0, b) == PITCH_DOWN, "Reset all: Pitch down on Down")


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
	check(kt.load_table().find_joystick(5, s.key_bindings) == GUN, "Gun trigger on button 6")
	bs._rows[GEAR].row.pressed.emit()
	root.push_input(joy_button(JOY_BUTTON_DPAD_UP))
	await frames(1)
	check(bs.waiting == GEAR and bs.pending.is_empty(), "the hat binds nothing: it is the look (the 1998 game's POV)")
	bs.cancel()
	fe.find_child("ResetAll", true, false).pressed.emit()
	check(
		s.key_bindings.is_empty() and store().get("axes", {}).is_empty(), "Reset all: %s %s" % [s.key_bindings, store()]
	)
	check(s.joy_axes == [0, 1, 2, 3, 4] and js.tune[1] == [false, 0.25], "Reset all: default axes")
	await mapping(scr, js)
	await hat(js)
	# The Hotas X's map.
	var map: String = IafDevices.find_map(s.joy_maps_dir(), "Thrustmaster T.Flight Hotas X")
	check(map.ends_with("hotas_x.json"), "the Hotas X has its map (%s)" % map)
	s._map_buttons(map)
	var t: RefCounted = kt.load_table()
	check(t.default_joystick(GUN) == 0 and t.default_joystick(GEAR) == 8, "its buttons: gun 1, gear 9")
	check(t.default_joystick(PITCH_UP) == -1, "a record the map leaves out: no button")
	js.default_buttons = null
	js.fake_devices = []
	await frames(2)


## The axis mapping against the 1998 game's table (reborn: Settings.joy_axes [0, 1, 2, 3], `tune` empty): with the
## Hotas X's defaults every role sends the event reborn sends, and every bar fills the way the jet responds (the Mac
## finding of 2026-11-11: the throttle lever forward showed an empty bar). Joystick.role_value is the one sense.
func mapping(scr: Node, js: Node) -> void:
	var s := settings()
	s.flight_controls = 1
	s.throttle = 1
	s.rudder = 1
	s.stick_response = "linear"
	s.apply_devices()
	scr.refresh()
	var sim_tune: Array = js.tune
	for v in [-1.0, -0.6, 0.0, 0.4, 1.0]:
		for a in 4:
			axis(a, v)
		js.tune = []
		js.poll()
		var reborn := [js.last_x, js.last_y, js.last_throttle, js.last_rudder]
		js.tune = sim_tune
		js.poll()
		var sim := [js.last_x, js.last_y, js.last_throttle, js.last_rudder]
		check(sim == reborn, "axes at %.1f: the sim sends reborn's events %s (%s)" % [v, str(reborn), str(sim)])
		scr._process(0.0)
		var centred := [sim[0], sim[1], sim[2] * 2 - 100, sim[3]]
		for a in 4:
			var bar: float = scr._axis_rows[a].bar.value
			check(
				signf(bar) == signf(centred[a]) and absf(bar * 100 - centred[a]) <= 1.0,
				"axes at %.1f: %s's bar %.2f is its event %d" % [v, s.JOY_ROLES[a], bar, centred[a]]
			)
	axis(2, -1.0)
	scr._process(0.0)
	check(scr._axis_rows[2].bar.value == 1.0, "the throttle lever forward: a full bar, full power")
	for a in 4:
		axis(a, 0.0)
	await frames(1)


## The hat as the 1998 game reads it (item 3, 2026-11-11; Joystick.poll, the same code reborn runs): its eight
## directions are the snap views, up and right held the front-right corner view (GEV 22 45°, the numpad 9's).
func hat(js: Node) -> void:
	var s := settings()
	s.flight_controls = 1
	js.poll()
	var sent := []
	for b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT]:
		Input.parse_input_event(joy_button(b))
		Input.flush_buffered_events()
		sent.append_array(js.poll())
	check(
		sent.has([22, 0, 8]) and sent.back() == [22, 45, 9], "hat up, then up-right: the front-right view %s" % [sent]
	)
	for b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT]:
		var e := joy_button(b)
		e.pressed = false
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	var out: Array = js.poll()
	check(out == [[22, -1, -9], [22, -1, 5]], "the hat centred: the view released, centred sent %s" % [out])
	await frames(1)


## The laptop map (front-end.md §9.1), the platform forced to laptop: the rudder on Z / X, no two records on one key,
## no numpad key; a stored key still wins over it.
func laptop() -> void:
	var s := settings()
	s.laptop_keys = true
	var path := ProjectSettings.globalize_path(s.keys_file())
	check(path.ends_with("keys_laptop.json"), "laptop: the laptop table (%s)" % path)
	var t: RefCounted = kt.load_table()
	check(t.default_key(RUDDER_LEFT) == DIK_Z and t.default_key(RUDDER_RIGHT) == DIK_X, "laptop: rudder on Z / X")
	var seen := {}
	var twice := []
	var numpad := []
	for r in t.size():
		var k: int = t.default_key(r)
		if int(t.records[r].dik) in NUMPAD:
			numpad.append(r)
		if k != 0 and seen.has(k):
			twice.append([seen[k], r])
		seen[k] = r
	check(twice.is_empty(), "laptop: no key on two records %s" % [twice])
	check(numpad.is_empty(), "laptop: no numpad key %s" % [numpad])
	t.set_column(s.key_bindings, RUDDER_LEFT, "key", DIK_K)
	check(t.key_of(RUDDER_LEFT, s.key_bindings) == DIK_K and t.default_key(RUDDER_LEFT) == DIK_Z, "laptop: K wins")
	s.key_bindings = {}
	s.laptop_keys = OS.get_name() == "macOS"


## Saved bindings of both kinds load into the one store: a devices.json from before 2026-11-14 (keys and buttons
## apart, moved once, its axes kept) and the original game's settings.cfg (r<record> = [key, button]).
func old_files() -> void:
	var s := settings()
	var f := FileAccess.open(s.devices_file(), FileAccess.WRITE)
	f.store_string('{"keys":{"24":37},"buttons":{"64":5,"20":7},"axes":{"pitch":{"axis":3}}}')
	f.close()
	s.key_bindings = {20: [0x22, 2]}
	s._take_old_bindings()
	check(
		s.key_bindings == {24: [37, null], 64: [null, 5], 20: [0x22, 7]},
		"devices.json from before: keys and buttons in key_bindings %s" % s.key_bindings
	)
	check(store() == {"axes": {"pitch": {"axis": 3.0}}}, "and out of the file, the axes kept: %s" % store())
	var t: RefCounted = kt.load_table()
	check(t.key_of(24, s.key_bindings) == 37 and t.joystick_of(24, s.key_bindings) == t.default_joystick(24), "K")
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "r19", [t.key_of(19, {}), 5])
	cfg.set_value("keys", "r24", [37, null])
	s.read_config(cfg)
	check(s.key_bindings == {19: [t.key_of(19, {}), 5], 24: [37, null]}, "settings.cfg: %s" % s.key_bindings)
	check(s.write_config().get_value("keys", "r24") == [37, null], "a default column saves as null")
	s.key_bindings = {}


func _has(n: Node, text: String) -> bool:
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).text == text:
			return true
	return false
