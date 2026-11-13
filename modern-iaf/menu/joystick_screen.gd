# Modern IAF's Joystick screen (modern-iaf/docs/front-end.md §9.2): the detected devices (the first one flies), each of
# its axes with a live bar, a role (roll, pitch, throttle, rudder, roll trim or none), an invert switch and a dead zone,
# then the commands with their buttons (keys_screen.gd in its "button" column: press a button or a hat direction).
# Reset all puts the buttons and axes back to the defaults: the device map's (data/devices) or the key table's. The
# store is Rust's (IafDevices); Settings.apply_devices hands the axes to the Joystick autoload the flight reads.
extends Control

const KeysScreen := preload("res://menu/keys_screen.gd")
const Look := preload("res://menu/look.gd")
## The axes a Godot joypad reports (JOY_AXIS_SDL_MAX).
const AXES := 6

## Device names for fake joysticks (Joystick.fake_devices), which Godot leaves unnamed: the pictures' sample stick.
static var fake_names := {}

var fe: Control
var scroll: ScrollContainer
var buttons: Control  # the KeysScreen list of the buttons
## The roles from the store (IafDevices.axes): {role: {axis, invert, dead}}.
var roles := {}
var _axis_rows: Array = []  # per axis: {bar, role, invert, dead, pct}
var _heads := {}
var _quiet := false  # while refresh() sets the controls


func _init(front_end: Control) -> void:
	fe = front_end
	name = "Joystick"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func page(front_end: Control) -> Node:
	var me = load("res://menu/joystick_screen.gd").new(front_end)
	front_end.add_child(me)
	if front_end.flight == null:
		front_end._header(["hangar", "preferences", "devices", "joystick_screen"])
	var v: VBoxContainer = front_end._vbox(front_end._body(96, 112 if front_end.flight == null else 60), 28)
	front_end._title(v, front_end.s("joystick_screen"), front_end.s("joystick_sub"))
	var h: HBoxContainer = front_end._hbox(v, 96)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav: VBoxContainer = front_end._vbox(h, 0)
	nav.custom_minimum_size.x = 384
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
	for part in ["joy_devices", "joy_axes", "joy_buttons"]:
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
	var ids: Array = Joystick.fake_devices + ([] if Settings.isolated() else Input.get_connected_joypads())
	if ids.is_empty():
		fe._label(fe._margin(body, 0, 14), fe.s("joy_none"), "Muted")
	for d in ids:
		var row: HBoxContainer = fe._hbox(fe._margin(body, 0, 14), 20)
		row.name = "Device_%d" % d
		var device_name: String = fake_names.get(d, Input.get_joy_name(d))
		var name_l: Label = fe._label(row, device_name if device_name != "" else "#%d" % d, "Row")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text_direction = Control.TEXT_DIRECTION_LTR
		if d == Joystick.device():
			fe._chip(row, fe.s("joy_in_use"), true)
		fe._rule(body, Look.LINE)
	_head(body, "joy_axes", false)
	var n := AXES if Joystick.axis_count < 0 else clampi(Joystick.axis_count, 1, AXES)
	for i in n:
		_axis_row(body, i)
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


## Axis i: its number, the live bar, the role, Invert, the dead zone.
func _axis_row(body: VBoxContainer, i: int) -> void:
	var m: MarginContainer = fe._margin(body, 0, 12)
	m.name = "Axis_%d" % i
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
	role.item_selected.connect(func(k): _set_role(i, "" if k == 0 else Settings.JOY_ROLES[k - 1]))
	h.add_child(role)
	_spacer(h)
	var inv := CheckButton.new()
	inv.name = "Invert"
	inv.text = fe.s("invert")
	inv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inv.toggled.connect(func(_on): _tune(i))
	h.add_child(inv)
	var dz: Label = fe._label(h, fe.s("dead_zone"), "Muted")
	dz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sl := HSlider.new()
	sl.name = "DeadZone"
	sl.custom_minimum_size = Vector2(150, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.max_value = 0.5
	sl.step = 0.01
	sl.value_changed.connect(func(_x): _tune(i))
	h.add_child(sl)
	var pct: Label = fe._label(h, "", "Row")
	pct.text_direction = Control.TEXT_DIRECTION_LTR
	pct.custom_minimum_size.x = 64
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_axis_rows.append({"bar": bar, "role": role, "invert": inv, "dead": sl, "pct": pct})
	fe._rule(body, Look.LINE)


func _spacer(parent: Control) -> void:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


## The role on axis i ("" none).
func role_of(i: int) -> String:
	for r in Settings.JOY_ROLES:
		if int(roles.get(r, {}).get("axis", -1)) == i:
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


func _set_role(i: int, r: String) -> void:
	if _quiet:
		return
	var old := role_of(i)
	if old != "" and old != r:
		_store(old, -1, bool(roles[old].invert), float(roles[old].dead))
	if r != "":
		_store(r, i, bool(roles[r].invert), float(roles[r].dead))
	refresh()


func _tune(i: int) -> void:
	if _quiet:
		return
	var r := role_of(i)
	if r == "":
		return
	var row: Dictionary = _axis_rows[i]
	_store(r, i, row.invert.button_pressed, row.dead.value)
	refresh()


func _store(r: String, axis: int, invert: bool, dead: float) -> void:
	IafDevices.set_axis(Settings.devices_file(), Settings.devices_map(), r, axis, invert, dead, _soft())
	Settings.apply_devices()


func reset_all() -> void:
	IafDevices.reset_joystick(Settings.devices_file())
	Settings.apply_devices()
	refresh()
	buttons.cancel()


## The live bars: an axis with a role as the flight reads it (Joystick.role_value: the role's invert, dead zone and
## sense, so the throttle lever forward is a full bar), the raw value without a role.
func _process(_delta: float) -> void:
	var d: int = Joystick.device()
	for i in _axis_rows.size():
		var v := 0.0
		if d >= 0:
			var r := role_of(i)
			v = Joystick.role_value(d, Settings.JOY_ROLES.find(r)) if r != "" else Joystick.axis(d, i)
		_axis_rows[i].bar.value = v
