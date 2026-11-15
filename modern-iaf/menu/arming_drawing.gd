# The loadout editor's pieces (modern-iaf/docs/front-end.md §10, the Loadout screen loadout_screen.gd): the stage that
# holds one callout per station (Slot, a drop target), the STORES the jet may carry (Item, a drag source) and their
# column (Shelf, where a store dragged off a station goes back).
#
# A store drags from the stores onto a callout, from a callout onto another or back onto the stores; `on_drop`
# (loadout_screen.gd) answers whether the record allows it, and a refused drop shakes the callout. While a store is
# dragged, the callouts that take it are framed in the accent colour, the others dimmed, and the store's picture
# (data/stores/<weapon id>.png, tests/_store_pictures.gd) follows the pointer. The keyboard: Enter on a callout picks it
# (`on_pick`), Enter on a store hangs that store on it.
extends Control

const Look := preload("look.gd")
const Img := preload("res://shared/util/img.gd")
## The dragged store's picture box: every picture fitted into it by its longest side.
const PIC := Vector2(120, 38)


## One station's callout: "6 · INBOARD", the store and its weight; an empty station's frame dashed with "Empty". A drag
## source and a drop target; a rack's "×n" badge at its bottom corner cycles the count.
class Slot:
	extends Control
	var station := ""
	## Nothing drags or drops (a mission that fixes the loadout).
	var read_only := false
	## While a store is dragged: 1 this station takes it, -1 it does not, 0 no drag.
	var hint := 0
	## Picked by the keyboard (Enter): the store chosen next goes here.
	var picked := false
	## Shaking off a refused drop.
	var refused := false
	## The rack's "×n" badge (a click cycles the count), empty: no rack.
	var badge_rect := Rect2()
	## [weapon id, short name, how many, full name, the rack's capacity there], empty for an empty station.
	var store: Array = []
	## "6 · INBOARD", the store's weight line ("85 kg") and an empty station's word.
	var head := ""
	var sub := ""
	var empty_text := ""
	## Hebrew: the text at the right, the badge at the left (the callout itself never mirrors: it sits by its station).
	var rtl := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE if read_only else Control.FOCUS_ALL
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _get_drag_data(_at: Vector2) -> Variant:
		if read_only or store.is_empty():
			return null
		return {"store": str(store[0]), "from": station}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return not read_only and data is Dictionary and data.has("store")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		get_parent().dropped(data, station)

	func _gui_input(e: InputEvent) -> void:
		if read_only:
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if badge_rect.has_area() and badge_rect.grow(4.0).has_point(e.position):
				accept_event()
				get_parent().on_cycle.call(station)
		elif e.is_action_pressed("ui_accept"):
			accept_event()
			get_parent().on_pick.call(station)

	## A refused drop: a short shake with the frame in the warning colour, no text.
	func shake() -> void:
		var x := position.x
		refused = true
		queue_redraw()
		var tw := create_tween()
		for d in [8.0, -8.0, 5.0, -3.0, 0.0]:
			tw.tween_property(self, "position:x", x + d, 0.05)
		tw.tween_callback(
			func():
				refused = false
				queue_redraw()
		)

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var bold := get_theme_font("font", "Strong")
		var r := Rect2(Vector2.ZERO, size)
		var on := hint > 0 or picked or has_focus()
		var edge := Look.ACCENT if on else (Look.EDGE if not store.is_empty() else Look.DIM)
		if refused:
			edge = Look.WARN
		var w := 2.0 if on or refused else 1.0
		if store.is_empty():
			draw_rect(r, Color(Look.ACCENT, 0.12) if hint > 0 or picked else Color(Look.PANEL, 0.35))
			var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
			for i in 4:
				draw_dashed_line(pts[i], pts[i + 1], edge, w, 6.0)
		else:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(Look.ACCENT, 0.18) if hint > 0 or picked else Look.PANEL
			box.border_color = edge
			box.set_border_width_all(int(w))
			box.set_corner_radius_all(4)
			box.anti_aliasing = true
			draw_style_box(box, r)
		var x := 12.0
		var tw := size.x - 2.0 * x
		var al := HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
		draw_string(font, Vector2(x, 22), head, al, tw, 14, Look.ACCENT_TEXT)
		if store.is_empty():
			draw_string(font, Vector2(x, 54), empty_text, al, tw, 20, Look.MUTED)
		else:
			_badge(font)
			draw_string(bold, Vector2(x, 51), str(store[1]), al, tw, 21, Look.TEXT)
			draw_string(font, Vector2(x, 74), sub, al, tw, 15, Look.MUTED)
		if hint < 0:
			draw_rect(r, Color(Look.BG, 0.6))

	## A rack's count at the bottom corner ("×3"), beside the weight.
	func _badge(font: Font) -> void:
		badge_rect = Rect2()
		if store.size() < 5 or int(store[4]) < 2:
			return
		var t := "×%d" % int(store[2])
		var bw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0
		badge_rect = Rect2(8 if rtl else size.x - bw - 8, size.y - 28, bw, 20)
		var b := StyleBoxFlat.new()
		b.bg_color = Look.ACCENT
		b.set_corner_radius_all(9)
		draw_style_box(b, badge_rect)
		draw_string(font, badge_rect.position + Vector2(6, 15), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Look.NAVY)


## Station number (String) → its Slot.
var slots := {}
## Station number (String) → the store ids it takes (the unit record's `allowed`).
var allowed := {}
var read_only := false
## (data {store, from}, to: the station, "" the inventory) -> bool: the change made (loadout_screen.gd).
var on_drop: Callable
## (station): Enter on a callout.
var on_pick: Callable
## (station): a click on a rack's "×n" badge.
var on_cycle: Callable
## The picture of the store being dragged, null: no drag, and the layer over the callouts it is drawn on.
var _dragged: Texture2D
var _over: Control
var _pointer := Vector2.ZERO
var _pictures := {}


func _ready() -> void:
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_dragged)
	add_child(_over)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## While a store is dragged, the pointer (the viewport's coordinates) from its moves.
func _input(e: InputEvent) -> void:
	if _dragged != null and e is InputEventMouseMotion:
		_pointer = e.position
		_over.queue_redraw()


## A drop on station `to` ("" the inventory); a refused one shakes the callout.
func dropped(data: Dictionary, to: String) -> void:
	if not on_drop.call(data, to) and slots.has(to):
		slots[to].shake()


## While a store is dragged, each callout says whether its station takes it, and the stage shows the store's picture
## over the pointer (drawn on a layer over the callouts).
func _notification(what: int) -> void:
	if what not in [NOTIFICATION_DRAG_BEGIN, NOTIFICATION_DRAG_END] or read_only:
		return
	var d = get_viewport().gui_get_drag_data() if what == NOTIFICATION_DRAG_BEGIN else null
	var id := str(d.store) if d is Dictionary and d.has("store") else ""
	show_drag(id, _pointer if _dragged != null else get_viewport().get_mouse_position())


## The drag of store `id` ("" none) with the pointer at `at` (the viewport's coordinates): the callouts' hints and the
## store's picture.
func show_drag(id: String, at: Vector2) -> void:
	_pointer = at
	_dragged = store_picture(id) if id != "" else null
	if _over != null:
		_over.move_to_front()
		_over.queue_redraw()
	for n in slots:
		var sl: Slot = slots[n]
		sl.hint = 0 if id == "" else (1 if id in allowed.get(n, []) else -1)
		sl.queue_redraw()


## The store's picture (data/stores/<id>.png), null without one.
func store_picture(id: String) -> Texture2D:
	if not _pictures.has(id):
		_pictures[id] = Img.load_texture(ProjectSettings.globalize_path("res://data/stores/%s.png" % id))
	return _pictures[id]


## The dragged store on the pointer (on `_over`, above the callouts), lifted a little over its shadow.
func _draw_dragged() -> void:
	if _dragged == null:
		return
	var ts := Vector2(_dragged.get_size()) * minf(PIC.x / _dragged.get_width(), PIC.y / _dragged.get_height())
	var at := _over.get_global_transform_with_canvas().affine_inverse() * _pointer - ts / 2.0 - Vector2(0, 4)
	_over.draw_texture_rect(_dragged, Rect2(at + Vector2(3, 6), ts), false, Color(0, 0, 0, 0.45))
	_over.draw_texture_rect(_dragged, Rect2(at, ts), false)


## One store the jet may carry, in the STORES grid: its name in a thin frame, and its count where the unit record
## gives one (the ones left). A drag source; Enter hangs it on the callout picked (`on_choose`). An empty `id` is the
## keyboard's "Empty" entry, which takes the picked callout's store off.
class Item:
	extends VBoxContainer
	var id := ""
	var read_only := false
	## False for a store with no model of ours yet: greyed, not dragged or chosen (the user: "disabled for now").
	var flyable := true
	var on_choose: Callable

	func setup(store_id: String, caption: String, count: String) -> void:
		id = store_id
		name = "Item" + (store_id if store_id != "" else "Empty")
		tooltip_text = caption
		add_theme_constant_override("separation", 0)
		focus_mode = Control.FOCUS_NONE if read_only or not flyable else Control.FOCUS_ALL
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		if not flyable:
			modulate = Color(1, 1, 1, 0.35)
		var l := Label.new()
		l.text = caption
		l.add_theme_font_size_override("font_size", 17)
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		if count != "":
			var c := Label.new()
			c.name = "Count"
			c.text = count
			c.theme_type_variation = "Small"
			c.add_theme_color_override("font_color", Look.ACCENT_TEXT)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(c)

	func _get_drag_data(_at: Vector2) -> Variant:
		if read_only or id == "" or not flyable:
			return null
		return {"store": id, "from": ""}

	## The column (Shelf) the item sits in, through its grid.
	func _shelf() -> Node:
		var p := get_parent()
		while p != null and not p.has_method("_drop_data"):
			p = p.get_parent()
		return p

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		var sh := _shelf()
		return sh != null and sh._can_drop_data(at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		_shelf()._drop_data(at, data)

	func _gui_input(e: InputEvent) -> void:
		if not read_only and flyable and e.is_action_pressed("ui_accept"):
			accept_event()
			on_choose.call(id)

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = Look.ACCENT if has_focus() else Look.LINE
		box.set_border_width_all(2 if has_focus() else 1)
		box.set_corner_radius_all(3)
		draw_style_box(box, Rect2(Vector2(-10, -5), size + Vector2(20, 10)))


## The STORES column: a store dragged from a callout and dropped here goes back (`on_drop`, to "").
class Shelf:
	extends VBoxContainer
	var read_only := false
	var on_drop: Callable

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return not read_only and data is Dictionary and str(data.get("from", "")) != ""

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(data, "")
