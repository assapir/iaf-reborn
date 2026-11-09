# Modern IAF's Keys screen (iaf-2026/docs/front-end.md §9.1), and the command list the Joystick screen shows for its
# buttons (column "button"). Every command of the sim's key table that has a group, by group, each with its key or
# button. Click a row, then press the new key (or the joystick button or hat): Esc cancels. A key another command
# already uses opens a choice in place: swap the two, use it here (the other loses it) or cancel. Each changed row has
# Default; the footer has Reset all. The store, the conflicts and the merge are Rust's (IafDevices, Settings.
# devices_file); this script displays and asks.
extends Control

const KeyTable := preload("res://shared/controls/key_table.gd")
const Look := preload("res://menu/look.gd")
## The groups in the order shown (data/keys.json "group").
const GROUPS := ["flight", "weapons", "sensors", "views", "sim"]
const HAT_NAMES := ["hat_up", "hat_right", "hat_down", "hat_left"]

## The front end: its strings and building blocks.
var fe: Control
## "key" or "button".
var column := "key"
## The merged key table (Settings.key_table_data).
var table: RefCounted
## The record waiting for its key / button, −1 = none.
var waiting := -1
## The conflict shown: [record, value, other record] or [].
var pending: Array = []
var scroll: ScrollContainer
## The group headings' size and the first one's space above (smaller inside the Joystick screen's Buttons part).
var head_size := 31
var first_gap := 0
var _rows := {}  # record -> {chip: Label, chip_box: PanelContainer, reset: Button, row: Button}
var _heads := {}  # group -> its heading
var _list: VBoxContainer
var _conflict: Control


func _init(front_end: Control, col := "key") -> void:
	fe = front_end
	column = col
	name = "Keys" if col == "key" else "Buttons"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The whole Keys page in the front end.
static func page(front_end: Control) -> Node:
	var me = load("res://menu/keys_screen.gd").new(front_end, "key")
	front_end.add_child(me)
	if front_end.flight == null:
		front_end._header(["home", "preferences", "devices", "keys_screen"])
	var v: VBoxContainer = front_end._vbox(front_end._body(96, 112 if front_end.flight == null else 60), 28)
	front_end._title(v, front_end.s("keys_screen"), front_end.s("keys_sub"))
	var h: HBoxContainer = front_end._hbox(v, 96)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav: VBoxContainer = front_end._vbox(h, 0)
	nav.custom_minimum_size.x = 384
	me.scroll = ScrollContainer.new()
	me.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	me.scroll.follow_focus = true
	me.scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(me.scroll)
	var body: VBoxContainer = front_end._vbox(front_end._margin(me.scroll, 32, 0), 0)
	body.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me.build(body, nav)
	front_end._focus = nav.get_child(0) if nav.get_child_count() > 0 else null
	var reset: Button = front_end._action(front_end.s("reset_all"), "Secondary", me.reset_all)
	reset.name = "ResetAll"
	front_end._footer("", [reset])
	return me


## The list into `body`, a tab per group into `nav` (null: none) that scrolls `scroll` to it.
func build(body: VBoxContainer, nav: VBoxContainer) -> void:
	_list = body
	table = KeyTable.load_table()
	var group := ButtonGroup.new()
	var first := true
	for g in GROUPS:
		var recs := records_of(g)
		if recs.is_empty():
			continue
		if nav != null:
			var tab := Button.new()
			tab.name = "Tab_" + g
			tab.text = fe.s("group_" + g)
			tab.theme_type_variation = "Tab"
			tab.toggle_mode = true
			tab.button_group = group
			tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
			tab.button_pressed = first
			tab.pressed.connect(func(): scroll_to(_heads[g]))
			nav.add_child(tab)
		var head: MarginContainer = fe._margin(body, 0, 0)
		head.add_theme_constant_override("margin_top", first_gap if first else 40)
		_heads[g] = head
		var hv: VBoxContainer = fe._vbox(head, 12)
		fe._label(hv, fe.s("group_" + g), "Strong").add_theme_font_size_override("font_size", head_size)
		fe._rule(hv, Look.LINE)
		for i in recs:
			_row(body, i)
		first = false
	refresh()


## The listed records of group `g`, in table order.
func records_of(g: String) -> Array:
	var out := []
	for i in table.size():
		if str(table.records[i].get("group", "")) == g and _label_of(i) != "":
			out.append(i)
	return out


func scroll_to(c: Control) -> void:
	if scroll != null:
		scroll.scroll_vertical = int(c.position.y)


func _label_of(i: int) -> String:
	return table.label(i, fe.he())


func _row(parent: Control, i: int) -> void:
	var row := Button.new()
	row.name = "Row_%d" % i
	row.theme_type_variation = "Menu"
	row.custom_minimum_size.y = 58
	row.pressed.connect(listen.bind(i))
	parent.add_child(row)
	var h: HBoxContainer = fe._hbox(row, 20)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = fe._label(h, _label_of(i), "Row")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reset: Button = fe._button(h, fe.s("default"), "Menu", reset_one.bind(i))
	reset.name = "Default"
	reset.add_theme_font_size_override("font_size", 19)
	reset.add_theme_color_override("font_color", Look.ACCENT_TEXT)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.focus_mode = Control.FOCUS_NONE
	var box := PanelContainer.new()
	box.custom_minimum_size.x = 250
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(box)
	var chip: Label = fe._label(box, "", "Key")
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows[i] = {"row": row, "chip": chip, "box": box, "reset": reset}
	fe._rule(parent, Look.LINE)


## Record i's binding in this column.
func value(i: int) -> int:
	return table.default_key(i) if column == "key" else int(table.records[i].joystick)


func default_value(i: int) -> int:
	var r: Dictionary = table.records[i]
	return int(r.get("default_key" if column == "key" else "default_joystick", value(i)))


## A binding as the row shows it: the key's name (Cmd on macOS), "Button n", a hat direction; "—" for none.
func value_name(v: int) -> String:
	if column == "key":
		return table.key_name(v) if v != 0 else "—"
	if v >= 32 and v < 36:
		return fe.s(HAT_NAMES[v - 32])
	return fe.s("button_n") % (v + 1) if v >= 0 else "—"


## Every row's binding again from the store.
func refresh() -> void:
	table = KeyTable.load_table()
	for i in _rows:
		var r: Dictionary = _rows[i]
		var on: bool = i == waiting
		r.chip.text = fe.s("press_key" if column == "key" else "press_button") if on else value_name(value(i))
		r.chip.theme_type_variation = "ChipOk" if on else "Key"
		var kb = Look.box(Color(0, 0, 0, 0), Look.ACCENT if on else Color("5a616c"), 2 if on else 1, 5, Vector2(12, 3))
		kb.border_width_bottom = 3
		r.box.add_theme_stylebox_override("panel", kb)
		r.reset.modulate.a = 1.0 if value(i) != default_value(i) else 0.0
		r.reset.disabled = value(i) == default_value(i)


## Record i waits for its new key / button.
func listen(i: int) -> void:
	_drop_conflict()
	waiting = i
	refresh()


func cancel() -> void:
	waiting = -1
	_drop_conflict()
	refresh()


func _input(event: InputEvent) -> void:
	if waiting < 0 and pending.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancel()
		return
	if waiting < 0:
		return
	var v := -2
	if column == "key" and event is InputEventKey and event.pressed and not event.echo:
		v = table.key_of_event(event)
		if v == 0:
			return  # a lone modifier (or a key the table has no name for): wait for the key
	elif column == "button" and event is InputEventJoypadButton and event.pressed and Joystick.ours(event):
		v = Joystick.physical_button(int(event.button_index))
		if v < 0:
			return
	if v == -2:
		return
	get_viewport().set_input_as_handled()
	choose(waiting, v)


## Binds record i to v, or shows the conflict when another command has v.
func choose(i: int, v: int) -> void:
	waiting = -1
	var other: int = IafDevices.conflict(_table_path(), Settings.devices_file(), Settings.devices_map(), i, column, v)
	if other >= 0:
		pending = [i, v, other]
		_show_conflict()
	else:
		_bind(i, v)
	refresh()


## The conflict's choices: "swap" (the other takes this one's old binding), "take" (the other has none), "cancel".
func resolve(how: String) -> void:
	if pending.is_empty():
		return
	var i: int = pending[0]
	var v: int = pending[1]
	var other: int = pending[2]
	_drop_conflict()
	if how == "swap":
		_bind(other, value(i))
	elif how == "take":
		_bind(other, 0 if column == "key" else -1)
	if how != "cancel":
		_bind(i, v)
	refresh()


func reset_one(i: int) -> void:
	IafDevices.reset(Settings.devices_file(), i, column)
	cancel()


func reset_all() -> void:
	IafDevices.reset(Settings.devices_file(), -1, column)
	cancel()


func _bind(i: int, v: int) -> void:
	IafDevices.bind(_table_path(), Settings.devices_file(), Settings.devices_map(), i, column, v)
	table = KeyTable.load_table()


func _table_path() -> String:
	return ProjectSettings.globalize_path(Settings.keys_file())


func _show_conflict() -> void:
	var i: int = pending[0]
	var row: Control = _rows[i].row
	var panel := PanelContainer.new()
	panel.name = "Conflict"
	panel.add_theme_stylebox_override("panel", Look.box(Color("262d3b"), Look.ACCENT, 1, 6, Vector2(24, 16)))
	_list.add_child(panel)
	_list.move_child(panel, row.get_index() + 1)
	var h: HBoxContainer = fe._hbox(panel, 16)
	var t: Label = fe._text(h, fe.s("conflict") % [value_name(pending[1]), _label_of(pending[2])], "Row")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.text_direction = Control.TEXT_DIRECTION_INHERITED  # a Hebrew line that starts with a Latin key name stays RTL
	fe._button(h, fe.s("swap"), "Primary", resolve.bind("swap")).name = "Swap"
	fe._button(h, fe.s("take"), "Secondary", resolve.bind("take")).name = "Take"
	fe._button(h, fe.s("cancel"), "Secondary", resolve.bind("cancel")).name = "Cancel"
	_conflict = panel
	fe._grab.call_deferred(panel.find_child("Swap", true, false))


func _drop_conflict() -> void:
	pending = []
	if _conflict != null and is_instance_valid(_conflict):
		_conflict.queue_free()
		_list.remove_child(_conflict)
	_conflict = null
