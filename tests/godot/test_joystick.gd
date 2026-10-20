# Joystick (docs/controls.md §4): the original's DirectInput poller FUN_004df560 on Godot's joypad API, with
# a fake device (Joystick.fake_devices) and injected joypad events. No device: nothing changes. With one:
# stick / throttle / rudder axes per the Devices page (linear ±100, 25 % dead zone on the stick and rudder),
# the keyboard axis keys dropped while their axis is used, the hat's snap views, buttons through the key
# table (bound on the Keyboard page, kept in settings.cfg, used in flight), menu/joy/*.joy, hot-plug and the
# autopilot's throttle re-sync from the axis.
extends "res://../tests/godot/base.gd"

const DT := 1.0 / 60.0


func joy() -> Node:
	return root.get_node("Joystick")


func axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func button(b: int, down: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	return e


func run() -> void:
	var prefs := settings()
	var js := joy()
	prefs.player_flight = 0
	check(js.device() == -1, "no joystick in tests (a real one plugged in is ignored)")
	# The original defaults: FLIGHT CONTROLS joystick, rudder / throttle keyboard (FUN_004f0750).
	check(prefs.flight_controls == 1 and prefs.rudder == 0 and prefs.throttle == 0, "Devices defaults 1 / 0 / 0")

	var tv = await start_mission(324)
	tv.frozen = true
	tv.autopilot._engage(0)  # the air start's AP LVL would keep small stick events

	# --- no device: the Devices choices do nothing, the keys work, the poller sends nothing ----------
	prefs.throttle = 1
	prefs.rudder = 1
	check(
		not js.stick_used() and not js.drops_key(2) and not js.drops_key(9) and js.throttle_axis() == -1,
		"no device: no axis in use, no key dropped"
	)
	check(js.poll().is_empty(), "no device: the poller sends nothing")
	set_key(KEY_DOWN, true)
	tv._read_controls(DT)
	check(tv.stick.y == 1.0, "no device: Down arrow pulls (%.2f)" % tv.stick.y)
	set_key(KEY_DOWN, false)
	tv._read_controls(DT)
	key(tv, KEY_2)
	check(is_equal_approx(tv.throttle, 0.10), "no device: key 2 = throttle 0.10 (%.2f)" % tv.throttle)
	prefs.throttle = 0
	prefs.rudder = 0

	# --- plugged in (hot-plug) ---------------------------------------------------------------------
	js.fake_devices = [0]
	await frames(2)
	check(js.device() == 0 and js.stick_used() and not js.throttle_used(), "plugged in: device 0, stick used")
	# Stick: x right = +, pulled back = pull; linear after the 25 % dead zone, MulDiv-rounded.
	axis(JOY_AXIS_LEFT_X, 1.0)
	axis(JOY_AXIS_LEFT_Y, 1.0)
	tv._read_controls(DT)
	check(tv.stick == Vector2(1, 1), "full right + pulled back → stick (1, 1) (%s)" % str(tv.stick))
	axis(JOY_AXIS_LEFT_X, 0.2)
	axis(JOY_AXIS_LEFT_Y, -0.625)
	tv._read_controls(DT)
	check(tv.stick == Vector2(0, -0.5), "x 0.2 in the dead zone → 0; y −0.625 → push 0.5 (%s)" % str(tv.stick))
	check(js.last_x == 0 and js.last_y == 50, "original values x 0, y +50 (%d, %d)" % [js.last_x, js.last_y])
	check(js.poll().is_empty(), "unchanged axes send nothing")
	# The pitch / roll keys are dropped while the stick axis is used.
	set_key(KEY_UP, true)
	tv._read_controls(DT)
	check(tv.stick == Vector2(0, -0.5), "Up arrow dropped while the stick is used")
	set_key(KEY_UP, false)
	tv._read_controls(DT)
	# Devices: KEYBOARD flight controls → the axes are ignored and the keys work.
	prefs.flight_controls = 0
	axis(JOY_AXIS_LEFT_X, -1.0)
	set_key(KEY_DOWN, true)
	tv._read_controls(DT)
	check(
		tv.stick == Vector2(0, 1), "flight controls KEYBOARD: stick axis ignored, Down arrow pulls (%s)" % str(tv.stick)
	)
	set_key(KEY_DOWN, false)
	tv._read_controls(DT)
	prefs.flight_controls = 1
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	tv._read_controls(DT)
	check(tv.stick == Vector2.ZERO, "stick centred")

	# Throttle (lZ): lever forward (−1) = 100 %, no dead zone; the throttle keys are dropped.
	prefs.throttle = 1
	axis(JOY_AXIS_RIGHT_X, -1.0)
	tv._read_controls(DT)
	check(is_equal_approx(tv.throttle, 1.0), "throttle axis forward → 1.0 (%.2f)" % tv.throttle)
	axis(JOY_AXIS_RIGHT_X, 0.48)
	tv._read_controls(DT)
	check(is_equal_approx(tv.throttle, 0.26), "throttle axis 0.48 → 0.26 (%.3f)" % tv.throttle)
	key(tv, KEY_6)
	check(is_equal_approx(tv.throttle, 0.26), "key 6 (90 %) dropped while the throttle axis is used")
	# Autopilot NAV → off: the throttle goes back to the axis (FUN_005a29d0 / FUN_004e0f40).
	tv.autopilot._engage(2)
	tv.throttle = 0.9
	tv.autopilot.key()
	check(
		tv.autopilot.mode == 0 and is_equal_approx(tv.throttle, 0.26),
		"leaving NAV re-syncs to the axis (%.2f)" % tv.throttle
	)

	# Rudder (lRz): ±100 with the dead zone; the rudder keys are dropped.
	prefs.rudder = 1
	axis(JOY_AXIS_RIGHT_Y, -1.0)
	tv._read_controls(DT)
	check(tv.rudder == -1.0, "rudder axis full left → −1 (%.2f)" % tv.rudder)
	set_key(KEY_KP_PERIOD, true)
	tv._read_controls(DT)
	check(tv.rudder == -1.0, "rudder key dropped while the rudder axis is used")
	set_key(KEY_KP_PERIOD, false)
	axis(JOY_AXIS_RIGHT_Y, 0.1)
	tv._read_controls(DT)
	check(tv.rudder == 0.0, "rudder axis in the dead zone → 0")
	prefs.rudder = 0
	prefs.throttle = 0

	# Hat: the snap views (GEV 22, the numpad snap keys' values); centred releases.
	tv.views.snap = null
	button(JOY_BUTTON_DPAD_RIGHT, true)
	tv._read_controls(DT)
	check(tv.views.snap != null, "hat right → snap view 90 right")
	button(JOY_BUTTON_DPAD_RIGHT, false)
	tv._read_controls(DT)
	check(tv.views.snap == null, "hat centred → back")

	# Buttons through the key table: Button 1 (index 0) = Fire gun by default; a rebound one runs its record.
	var kt = tv.keys
	check(kt.find_joystick(0, prefs.key_bindings) == 64, "Button 1 = Fire gun")
	prefs.key_bindings = {19: [kt.key_of(19, {}), 5]}  # Flaps on Button 6
	var f0: float = tv.flaps
	button(5, true)
	await frames(1)
	button(5, false)
	await frames(1)
	check(tv.flaps != f0, "Button 6 bound to Flaps moves the flaps")
	# A button on Rudder left moves the rudder (GEV 10 is sent as it is), released → centre.
	prefs.key_bindings = {37: [kt.key_of(37, {}), 7]}
	button(7, true)
	await frames(1)
	check(tv.rudder == -1.0, "Button 8 on Rudder left: rudder −1 (%.2f)" % tv.rudder)
	button(7, false)
	await frames(1)
	check(tv.rudder == 0.0, "released: centred")
	prefs.key_bindings = {}

	# Unplugged: the keys work again.
	js.fake_devices = []
	await frames(2)
	set_key(KEY_DOWN, true)
	tv._read_controls(DT)
	check(js.device() == -1 and tv.stick.y == 1.0, "unplugged: Down arrow pulls again")
	set_key(KEY_DOWN, false)
	tv._read_controls(DT)
	tv.queue_free()
	await frames(2)

	# menu/joy/*.joy (FUN_004e1590): a device whose name contains a file's first line gets its buttons.
	js._load_joy_map("Microsoft SideWinder Precision Pro (USB)")
	check(
		kt.default_joystick(64) == 0 and kt.default_joystick(69) == 1 and kt.default_joystick(22) == 9,
		"sw_precp.joy: gun 1, weapon 2, brakes 10"
	)
	check(kt.default_joystick(61) == -1, "records not in the file: no button")
	js.default_buttons = null
	check(kt.default_joystick(58) == 2, "no file: the table's own buttons")

	# Keyboard page: a joystick button binds the selected function; a taken one asks msg 37; Yes saves.
	js.fake_devices = [0]
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Preferences"))
	await frames(2)
	while fe.busy:
		await process_frame
	fe._on_button(fe._key_for_label("Controls"))
	var rows: Array = fe._ctrl_rows()
	fe._ctrl_select(rows.find(19))
	fe.ctrl_focus = true
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = 5
	e.pressed = true
	fe._unhandled_input(e)
	check(
		kt.joystick_of(19, fe.pref_work.key_bindings) == 5 and kt.button_name(5) == "Button 6",
		"Flaps bound to Button 6"
	)
	e = e.duplicate()
	e.button_index = 0
	fe._unhandled_input(e)
	check(
		fe.msgbox != null and fe.msgbox.text.begins_with("This button is already assigned"), "taken button asks msg 37"
	)
	var yes: Rect2 = fe.msgbox.rects()[0]
	fe.msgbox._gui_input(mouse_button(yes.get_center(), true))
	fe.msgbox._gui_input(mouse_button(yes.get_center(), false))
	check(
		kt.joystick_of(19, fe.pref_work.key_bindings) == 0 and kt.joystick_of(64, fe.pref_work.key_bindings) == -1,
		"Yes: Flaps on Button 1, Fire gun none"
	)
	# Devices page choices go through the same working copy.
	fe.pref_work.rudder = 1
	fe._pref_close("main", true)
	await frames(2)
	check(
		prefs.key_bindings.get(19, [])[1] == 0 and prefs.rudder == 1,
		"Yes to Save changes: bindings and Devices committed"
	)
	# settings.cfg round trip.
	var cfg: ConfigFile = prefs.write_config()
	prefs.key_bindings = {}
	prefs.rudder = 0
	prefs.read_config(cfg)
	check(
		prefs.key_bindings.get(19, [])[1] == 0 and prefs.key_bindings.get(64, [])[1] == -1 and prefs.rudder == 1,
		"settings.cfg keeps the buttons and the Devices choices"
	)
	prefs.key_bindings = {}
	prefs.rudder = 0
	fe.queue_free()
	js.fake_devices = []
	await frames(2)

	# Ours: Extras "Throttle detent = MIL" maps the lever's detent to MIL (74), below it 0..74, above it 74..100.
	var js2 = joy()
	check(js2.detent_map(60, -1) == 60, "detent off: the original's linear lever")
	check(
		js2.detent_map(85, 85) == 74 and js2.detent_map(0, 85) == 0 and js2.detent_map(100, 85) == 100,
		"detent 85: 85 -> MIL 74, ends kept"
	)
	check(
		js2.detent_map(42, 85) == 37 and js2.detent_map(90, 85) == 82,
		"detent 85: linear below, AB 78..100 above the hold"
	)
	check(
		js2.detent_map(51, 50) == 74 and js2.detent_map(53, 50) == 74 and js2.detent_map(54, 50) == 78,
		"detent 50: a lever resting a point or two past the detent stays MIL (75 would light AB 1); AB from 78"
	)

	# Unknown sticks: the hat (D-pad 11..14) is never a button; with our mapping Godot 15..20 = buttons 12..17.
	check(
		(
			js2.physical_button(3) == 3
			and js2.physical_button(JOY_BUTTON_DPAD_UP) == -1
			and js2.physical_button(JOY_BUTTON_DPAD_RIGHT) == -1
		),
		"hat is not a button"
	)
	js2.remapped = true
	check(
		js2.physical_button(15) == 11 and js2.physical_button(20) == 16 and js2.physical_button(10) == 10,
		"remapped: misc1 = button 12"
	)
