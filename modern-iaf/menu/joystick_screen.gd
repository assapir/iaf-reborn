# Modern IAF's Joystick screen (modern-iaf/docs/front-end.md §9.2): the detected devices (the one with the roll flies),
# each device's axes with a live bar, a role (roll, pitch, throttle, rudder, roll trim or none), an invert switch and a
# dead zone, then the commands with their buttons (keys_screen.gd in its "button" column: press a button or a hat
# direction). Reset all puts the buttons and axes back to the defaults: the device map's (data/devices) or the key
# table's. The axes' store is Rust's (IafDevices), the buttons are Settings.key_bindings (keys_screen.gd);
# Settings.apply_devices hands the axes to the Joystick autoload the flight reads.
extends Control

const KeysScreen := preload("res://menu/keys_screen.gd")
const Look := preload("res://menu/look.gd")
## The axes a Godot joypad reports (JOY_AXIS_SDL_MAX).
const AXES := 6

var fe: Control
var scroll: ScrollContainer
var buttons: Control  # the KeysScreen list of the buttons
## The roles from the store (IafDevices.axes): {role: {axis, invert, dead, device}}.
var roles := {}
## Per axis of each device, the main joystick's first: {dev, axis, bar, role, invert, dead, pct}.
var _axis_rows: Array = []
var _heads := {}
var _quiet := false  # while refresh() sets the controls


func _init(front_end: Control) -> void:
	fe = front_end
	name = "Joystick"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func page(front_end: Control) -> Node:
	var me = load("res://menu/joystick_screen.gd").new(front_end)
	front_end.add_child(me)
	var first = "hangar" if front_end.flight == null else [front_end.s("paused"), "pause"]
	front_end._header([first, "preferences", "devices", "joystick_screen"])
	# The Settings' frame (front_end.gd settings_frame): the same title row, side list and columns.
	var f: Dictionary = front_end.settings_frame(front_end.s("joystick_screen"), front_end.s("joystick_sub"))
	var h: HBoxContainer = f.h
	var nav: VBoxContainer = f.nav
	me.scroll = ScrollContainer.new()
	me.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	me.scroll.follow_focus = true
	me.scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(me.scroll)
	var m: MarginContainer = front_end._margin(me.scroll, 32, 0)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me.build(front_end._vbox(m, 0), nav)
	front_end._focus = nav.get_child(0)
	var reset: Button = front_end._action(front_end.s("reset_all"), "Secondary", me.reset_all)
	reset.name = "ResetAll"
	front_end._footer("", [front_end.back_button(), reset])
	return me


func build(body: VBoxContainer, nav: VBoxContainer) -> void:
	var group := ButtonGroup.new()
	var tabs := []
	var ids: Array = Joystick.connected()
	# No joystick connected: no axis rows (their bars and roles have nothing to read), the devices' line says so.
	var parts := ["joy_devices", "joy_axes", "joy_buttons"] if not ids.is_empty() else ["joy_devices", "joy_buttons"]
	for part in parts:
		var tab := Button.new()
		tab.name = "Tab_" + part
		tab.text = fe.s(part)
		tab.theme_type_variation = "Tab"
		tab.toggle_mode = true
		tab.button_group = group
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.button_pressed = part == "joy_devices"
		nav.add_child(tab)
		tabs.append(tab)
	_head(body, "joy_devices", true)
	if ids.is_empty():
		fe._label(fe._margin(body, 0, 14), fe.s("joy_none"), "Muted")
	for d in ids:
		var row: HBoxContainer = fe._hbox(fe._margin(body, 0, 14), 20)
		row.name = "Device_%d" % d
		var device_name: String = Joystick.dev_key(d)
		var name_l: Label = fe._label(row, device_name if device_name != "" else "#%d" % d, "Row")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text_direction = Control.TEXT_DIRECTION_LTR
		if d == Joystick.device():
			fe._chip(row, fe.s("joy_in_use"), true)
		fe._rule(body, Look.LINE)
	if "joy_axes" in parts:
		_head(body, "joy_axes", false)
		# Every device's axes, the main joystick's first; with several devices each under its name.
		var main: int = Joystick.device()
		var order: Array = [main] + ids.filter(func(d): return d != main)
		for d in order:
			if ids.size() > 1:
				var l: Label = fe._label(fe._margin(body, 0, 10), Joystick.dev_key(d), "Muted")
				l.text_direction = Control.TEXT_DIRECTION_LTR
			var c := _axis_count(d)
			for i in AXES if c < 0 else clampi(c, 1, AXES):
				_axis_row(body, d, i)
	_head(body, "joy_buttons", false)
	fe._label(fe._margin(body, 0, 8), fe.s("joy_buttons_note"), "Small")
	buttons = KeysScreen.new(fe, "button")
	add_child(buttons)
	buttons.head_size = 25
	buttons.first_gap = 16
	buttons.scroll = scroll
	buttons.build(body, null)
	fe.spy(scroll, tabs, _heads.values())
	refresh()


func _head(body: VBoxContainer, part: String, first: bool) -> void:
	var head: MarginContainer = fe._margin(body, 0, 0)
	head.add_theme_constant_override("margin_top", 0 if first else 40)
	_heads[part] = head
	var hv: VBoxContainer = fe._vbox(head, 12)
	fe._label(hv, fe.s(part), "Strong").add_theme_font_size_override("font_size", 31)
	fe._rule(hv, Look.LINE)


## A device's input axes from its USB descriptor (Joystick.axis_count for the main one), −1 = unknown.
func _axis_count(d: int) -> int:
	if d == Joystick.device() or Settings.isolated():
		return Joystick.axis_count
	return IafHid.axis_count(Input.get_joy_guid(d))


## Axis i of device d: its number, the live bar, the role, Invert, the dead zone.
func _axis_row(body: VBoxContainer, d: int, i: int) -> void:
	var k := _axis_rows.size()
	var m: MarginContainer = fe._margin(body, 0, 12)
	m.name = "Axis_%d" % i if d == Joystick.device() else "Device_%d_Axis_%d" % [d, i]
	var h: HBoxContainer = fe._hbox(m, 24)
	var num: Label = fe._label(h, fe.s("axis_n") % (i + 1), "Strong")
	num.custom_minimum_size.x = 96
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = -1.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR  # the stick's right is the bar's right in Hebrew too
	h.add_child(bar)
	var role := OptionButton.new()
	role.name = "Role"
	role.custom_minimum_size = Vector2(220, 58)
	role.add_item(fe.s("role_none"))
	for r in Settings.JOY_ROLES:
		role.add_item(fe.s("role_" + r))
	role.item_selected.connect(func(n): _set_role(k, "" if n == 0 else Settings.JOY_ROLES[n - 1]))
	h.add_child(role)
	_spacer(h)
	var inv := CheckButton.new()
	inv.name = "Invert"
	inv.text = fe.s("invert")
	inv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inv.toggled.connect(func(_on): _tune(k))
	h.add_child(inv)
	var dz: Label = fe._label(h, fe.s("dead_zone"), "Muted")
	dz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sl := HSlider.new()
	sl.name = "DeadZone"
	sl.custom_minimum_size = Vector2(150, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.max_value = 0.5
	sl.step = 0.01
	sl.value_changed.connect(func(_x): _tune(k))
	h.add_child(sl)
	var pct: Label = fe._label(h, "", "Row")
	pct.text_direction = Control.TEXT_DIRECTION_LTR
	pct.custom_minimum_size.x = 64
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_axis_rows.append({"dev": d, "axis": i, "bar": bar, "role": role, "invert": inv, "dead": sl, "pct": pct})
	fe._rule(body, Look.LINE)


func _spacer(parent: Control) -> void:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


## The role on axis row k ("" none): the role whose axis and device are the row's.
func role_of(k: int) -> String:
	var row: Dictionary = _axis_rows[k]
	for r in Settings.JOY_ROLES:
		var e: Dictionary = roles.get(r, {})
		var n := str(e.get("device", ""))
		if int(e.get("axis", -1)) == row.axis and (Joystick.device() if n == "" else Joystick.by_name(n)) == row.dev:
			return r
	return ""


## The axes' controls again from the store.
func refresh() -> void:
	roles = JSON.parse_string(IafDevices.axes(Settings.devices_file(), Settings.devices_map(), _soft()))
	_quiet = true
	for i in _axis_rows.size():
		var row: Dictionary = _axis_rows[i]
		var r := role_of(i)
		row.role.select(0 if r == "" else Settings.JOY_ROLES.find(r) + 1)
		row.invert.disabled = r == ""
		row.invert.button_pressed = r != "" and bool(roles[r].invert)
		# The throttle has no centre: no dead zone (joystick.gd reads none on it).
		row.dead.editable = r != "" and r != "throttle"
		row.dead.modulate.a = 1.0 if row.dead.editable else 0.35
		row.dead.value = float(roles[r].dead) if r != "" else 0.0
		row.pct.text = "%d%%" % roundi(row.dead.value * 100) if row.dead.editable else "—"
	_quiet = false


func _soft() -> bool:
	return Settings.stick_response == "soft"


func _set_role(k: int, r: String) -> void:
	if _quiet:
		return
	var old := role_of(k)
	var d: int = _axis_rows[k].dev
	if old != "" and old != r:
		_store(old, d, -1, bool(roles[old].invert), float(roles[old].dead))
	if r != "":
		_store(r, d, _axis_rows[k].axis, bool(roles[r].invert), float(roles[r].dead))
	refresh()


func _tune(k: int) -> void:
	if _quiet:
		return
	var r := role_of(k)
	if r == "":
		return
	var row: Dictionary = _axis_rows[k]
	_store(r, row.dev, row.axis, row.invert.button_pressed, row.dead.value)
	refresh()


## Role r on axis `axis` (−1 none) of device d.
func _store(r: String, d: int, axis: int, invert: bool, dead: float) -> void:
	var choice := {
		"axis": axis,
		"invert": invert,
		"dead": dead,
		"device": Joystick.dev_key(d),
		"main": Joystick.dev_key(Joystick.device()),
	}
	IafDevices.set_axis(Settings.devices_file(), Settings.devices_map(), r, choice, _soft())
	Settings.apply_devices()


func reset_all() -> void:
	IafDevices.reset_axes(Settings.devices_file())
	buttons.reset_all()
	Settings.apply_devices()
	refresh()


## The live bars: an axis with a role as the flight reads it (Joystick.role_value: the role's invert, dead zone and
## sense, so the throttle lever forward is a full bar), the raw value without a role.
func _process(_delta: float) -> void:
	for k in _axis_rows.size():
		var row: Dictionary = _axis_rows[k]
		var r := role_of(k)
		var v: float = Joystick.role_value(Settings.JOY_ROLES.find(r)) if r != "" else Joystick.axis(row.dev, row.axis)
		row.bar.value = v
