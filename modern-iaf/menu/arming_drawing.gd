# The briefing's Arming drawing (modern-iaf/docs/front-end.md §10): our own jet's front view in light lines
# (data/drawings/<jet>_front.png, traced from its model by tests/_jet_fronts.gd; its stations' places in
# <jet>_front.json) and under it one slot per station (a Slot Control each, a drop target): a thin rounded
# frame with the station's number on its edge, the store's side view (data/stores/<weapon id>.png,
# tests/_store_pictures.gd) and its short name under it, the name also the tooltip; an empty station shows its empty
# slot. The wing stations' slots form one row in station order (9 to 1 left to right as the front view shows them),
# the drop tanks' a second row straight under stations 4 and 6; each slot's leader runs straight up, or up and then
# across at its station's height, to its station, none crossing another. A jet with internal stations (the Adir's
# bays) has their slots in the second row instead, side by side under the fuselage, each marked "internal" on its
# bottom edge, and every leader straight from its slot to its station (to where a bay opens). Every slot is the same
# size and every store picture fits one box (PIC). The drawing never
# mirrors: station 1, the left wing tip, is on the viewer's right as the jet faces the reader.
#
# The loadout editor: a store drags from the inventory (Item) onto a slot, from a slot onto another or back onto the
# inventory (Shelf); `on_drop` (front_end.gd) answers whether the record allows it, and a refused drop shakes the
# slot. While a store is dragged, the slots that take it are framed in the accent colour, the others dimmed. The
# keyboard: Enter on a slot picks it (`on_pick`), Enter on an inventory entry hangs that store on it.
extends Control

const Look := preload("look.gd")
const Img := preload("res://shared/util/img.gd")
const MUTED := Color("8a919b")
## The F-16's wet inboard stations: their slots (the drop tanks') in the second row.
const LOWER := ["4", "5", "6"]
## Every slot's size, for every station and jet, and the one picture box every store's picture is fitted into by
## its longest side (a drop tank and a missile take the same room), in the slots and in the inventory.
const SLOT := Vector2(88, 80)
const PIC := Vector2(76, 24)
## The room between two slots in a row, and between the jet and the first row and between the rows (px).
const GAP := 14.0
const ROW_GAP := 26.0


## One station's slot: its frame, number, store picture and name; a drag source and a drop target.
class Slot:
	extends Control
	var station := ""
	## Nothing drags or drops (a mission that fixes the loadout).
	var read_only := false
	## While a store is dragged: 1 this station takes it, -1 it does not, 0 no drag.
	var hint := 0
	## Picked by the keyboard (Enter): the inventory entry chosen next goes here.
	var picked := false
	## Shaking off a refused drop.
	var refused := false
	## The rack's "×n" badge on the frame's corner (a click cycles the count), empty: no rack.
	var badge_rect := Rect2()
	## [weapon id, name], empty for an empty station.
	var store: Array = []
	var tex: Texture2D
	## The mark on its bottom edge ("internal"), empty: none.
	var tag := ""

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
		var box := StyleBoxFlat.new()
		box.bg_color = Color(Look.ACCENT, 0.12) if hint > 0 or picked else Color(Look.PANEL, 0.0)
		box.border_color = Look.EDGE if not store.is_empty() else Look.LINE
		if hint > 0 or picked or has_focus():
			box.border_color = Look.ACCENT
		if refused:
			box.border_color = Look.WARN
		box.set_border_width_all(2 if picked or has_focus() or refused else 1)
		box.set_corner_radius_all(8)
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		# The number on the frame's top edge, a patch of the panel's colour behind it.
		var nw := font.get_string_size(station, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_rect(Rect2(10, -9, nw + 8, 18), Look.PANEL)
		draw_string(font, Vector2(14, 6), station, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Look.ACCENT_TEXT)
		if tag != "":
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_rect(Rect2(size.x - tw - 18, size.y - 8, tw + 8, 16), Look.PANEL)
			draw_string(font, Vector2(size.x - tw - 14, size.y + 5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
		if not store.is_empty():
			_draw_store(font)
		if hint < 0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(Look.PANEL, 0.6))

	## The store's picture fitted into the picture box by its longest side (a rack: its bar and the stores two to a
	## row under it, a "×3" badge at the frame's corner), its caption under the box on up to two lines.
	func _draw_store(font: Font) -> void:
		var n := int(store[2]) if store.size() > 2 else 1
		var rack := store.size() > 4 and int(store[4]) > 1
		badge_rect = Rect2()
		if tex != null and not rack:
			var ts := Vector2(tex.get_size()) * minf(PIC.x / tex.get_width(), PIC.y / tex.get_height())
			draw_texture_rect(tex, Rect2(Vector2((size.x - ts.x) / 2.0, 14.0 + (PIC.y - ts.y) / 2.0), ts), false)
		elif tex != null:
			draw_rect(Rect2((size.x - PIC.x * 0.8) / 2.0, 11.0, PIC.x * 0.8, 3.0), Look.EDGE)
			var cell := Vector2(PIC.x / 2.0, (PIC.y - 2.0) / 2.0)
			var ts := (
				Vector2(tex.get_size()) * minf((cell.x - 2.0) / tex.get_width(), (cell.y - 1.0) / tex.get_height())
			)
			for i in n:
				var row := i / 2
				var in_row := mini(2, n - row * 2)
				var x0 := (size.x - in_row * cell.x) / 2.0 + (i % 2) * cell.x
				draw_texture_rect(tex, Rect2(Vector2(x0 + (cell.x - ts.x) / 2.0, 15.0 + row * cell.y), ts), false)
			var badge := "×%d" % n
			var bw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0
			var b := StyleBoxFlat.new()
			b.bg_color = Look.ACCENT
			b.set_corner_radius_all(8)
			badge_rect = Rect2(size.x - bw - 4, -9, bw, 18)
			draw_style_box(b, badge_rect)
			draw_string(font, Vector2(size.x - bw + 1, 5), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Look.NAVY)
		var y := 14.0 + PIC.y + 15.0
		draw_multiline_string(
			font, Vector2(4, y), str(store[1]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 14, 2, Look.MUTED
		)


## The drawing and its stations {"1": [x, y], …} in its pixels.
var picture: Texture2D
var stations := {}
## Station number → [the store's weapon id, its short name, how many, its full name, its rack's capacity there]
## (absent: none).
var stores := {}
## The internal stations' numbers (String), and the mark their slots carry.
var internal: Array = []
var internal_tag := ""
## Station number (String) → its Slot.
var slots := {}
## Station number (String) → the store ids it takes (the unit record's `allowed`).
var allowed := {}
var read_only := false
## (data {store, from}, to: the station, "" the inventory) -> bool: the change made (front_end.gd).
var on_drop: Callable
## (station): Enter on a slot.
var on_pick: Callable
## (station): a click on a rack's "×n" badge.
var on_cycle: Callable
## The picture of the store being dragged, null: no drag, and the layer over the slots it is drawn on.
var _dragged: Texture2D
var _over: Control
var _pointer := Vector2.ZERO
var _pictures := {}
## Each slot's leader as drawn: station → [its start on the slot's top edge, the station].
var _leaders := {}


func _ready() -> void:
	resized.connect(_layout)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_dragged)
	add_child(_over)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # the drawing's own box: right to left the same


## While a store is dragged, the pointer (the viewport's coordinates) from its moves.
func _input(e: InputEvent) -> void:
	if _dragged != null and e is InputEventMouseMotion:
		_pointer = e.position
		_over.queue_redraw()


## Loads `<dir>/<name>.json` and its picture; false when either is missing.
func load_drawing(dir: String, name: String) -> bool:
	var meta := Settings.load_json(dir.path_join(name + ".json"))
	if meta.is_empty():
		return false
	var tex := Img.load_texture(ProjectSettings.globalize_path(dir.path_join(str(meta.get("image", "")))))
	if tex == null:
		return false
	picture = tex
	stations = meta.get("stations", {})
	return true


## The slots, one per station with its store (call after `stores` is set).
func make_slots() -> void:
	for n in stations:
		var sl := Slot.new()
		sl.name = "Slot" + str(n)
		sl.station = str(n)
		if stores.has(int(n)):
			sl.store = stores[int(n)]
			sl.tex = store_picture(str(sl.store[0]))
			var full := str(sl.store[3]) if sl.store.size() > 3 else str(sl.store[1])
			var many := int(sl.store[2]) if sl.store.size() > 2 else 1
			sl.tooltip_text = full + ("" if many < 2 else " × %d" % many)
		if str(n) in internal:
			sl.tag = internal_tag
		sl.size = SLOT
		sl.read_only = read_only
		add_child(sl)
		slots[str(n)] = sl
	if _over != null:
		move_child(_over, -1)
	_layout()


## A drop on station `to` ("" the inventory); a refused one shakes the slot.
func dropped(data: Dictionary, to: String) -> void:
	if not on_drop.call(data, to) and slots.has(to):
		slots[to].shake()


## While a store is dragged, each slot says whether its station takes it, and the drawing shows the store's picture
## over the pointer (drawn here, on a layer over the slots, the slot under the pointer left in view).
func _notification(what: int) -> void:
	if what not in [NOTIFICATION_DRAG_BEGIN, NOTIFICATION_DRAG_END] or read_only:
		return
	var d = get_viewport().gui_get_drag_data() if what == NOTIFICATION_DRAG_BEGIN else null
	var id := str(d.store) if d is Dictionary and d.has("store") else ""
	show_drag(id, _pointer if _dragged != null else get_viewport().get_mouse_position())


## The drag of store `id` ("" none) with the pointer at `at` (the viewport's coordinates): the slots' hints and the
## store's picture.
func show_drag(id: String, at: Vector2) -> void:
	_pointer = at
	_dragged = store_picture(id) if id != "" else null
	if _over != null:
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


## Whether the station's slot is in the second row: the internal stations' when the jet has any, else the F-16's
## wet inboard ones.
func _lower(n: String) -> bool:
	return n in internal if not internal.is_empty() else n in LOWER


## The drawing's place: centred (also up and down when it has no slots), as wide as the height the slot rows leave
## allows (at most 62 % of the width).
func _frame() -> Rect2:
	var a := float(picture.get_width()) / picture.get_height()
	var rows_h := 0.0 if slots.is_empty() else ROW_GAP * 2.0 + SLOT.y * 2.0 + 10.0
	var w := minf(size.x * 0.62, (size.y - rows_h) * a)
	var y := 0.0 if not slots.is_empty() else maxf((size.y - w / a) / 2.0, 0.0)
	return Rect2(Vector2((size.x - w) / 2.0, y), Vector2(w, w / a))


## The station's place on the panel.
func _at(n: String, fr: Rect2) -> Vector2:
	var p: Array = stations[n]
	return fr.position + Vector2(float(p[0]), float(p[1])) * fr.size.x / picture.get_width()


## Places the slots: the second row's under their stations, the first row's in station order in the room between
## the second row's leaders, each run as near its stations as the slots' widths allow; then the leaders.
func _layout() -> void:
	_leaders.clear()
	if picture == null or slots.is_empty():
		queue_redraw()
		return
	var fr := _frame()
	var y1 := fr.end.y + ROW_GAP
	var y2 := y1 + SLOT.y + ROW_GAP
	var upper := []
	var lower := []
	var cuts := []
	for n in slots:
		var x := _at(n, fr).x
		if not _lower(n):
			upper.append([x, n])
		elif internal.is_empty():
			slots[n].position = Vector2(x - SLOT.x / 2.0, y2)
			cuts.append(x)
		else:
			lower.append([x, n])
	upper.sort()
	cuts.sort()
	# Where the first row's runs end: the second row's leaders (the tanks'), or the internal row's sides.
	var edges := cuts.duplicate()
	if not lower.is_empty():
		# The internal row side by side, centred under its stations; the first row clear of it on both sides.
		lower.sort()
		var mid := (float(lower[0][0]) + float(lower[-1][0])) / 2.0
		var half := (lower.size() * (SLOT.x + GAP) - GAP) / 2.0
		for i in lower.size():
			slots[lower[i][1]].position = Vector2(mid - half + i * (SLOT.x + GAP), y2)
		cuts = [mid, mid]
		# The first row clear of the bay leaders, which run straight up under their stations.
		edges = [_at(lower[0][1], fr).x, _at(lower[-1][1], fr).x]
	var runs := [[]]
	var c := 0
	for u in upper:
		while c < cuts.size() and u[0] > cuts[c]:
			c += 1
			runs.append([])
		runs[-1].append(u)
	while runs.size() <= cuts.size():
		runs.append([])
	var w1 := 0.0
	for u in upper:
		w1 = maxf(w1, slots[u[1]].size.x)
	var bounds := [4.0 + w1 / 2.0]
	for x in edges:
		bounds.append(x - GAP - w1 / 2.0)
		bounds.append(x + GAP + w1 / 2.0)
	bounds.append(size.x - 4.0 - w1 / 2.0)
	for r in runs.size():
		if runs[r].is_empty():
			continue
		var xs := _spread(runs[r].map(func(u): return u[0]), bounds[2 * r], bounds[2 * r + 1], w1)
		for i in xs.size():
			slots[runs[r][i][1]].position = Vector2(xs[i] - w1 / 2.0, y1)
	for n in slots:
		var sl: Control = slots[n]
		var st := _at(n, fr)
		if n in internal:
			# A bay slot: up from its middle, across in the gap over the bay row (the outer pair higher than the inner,
			# so none crosses), straight up under its station to its bay's outline.
			var k := lower.map(func(u): return u[1]).find(n)
			var outer: bool = k == 0 or k == lower.size() - 1
			var bottom: float = _bays(fr)[0].end.y
			var y := y2 - (18.0 if outer else 8.0)
			_leaders[n] = [Vector2(sl.position.x + sl.size.x / 2.0, sl.position.y), Vector2(st.x, bottom), y]
			continue
		# Straight up from the slot's top edge where its station is over it (clear of the number), else from its middle.
		var x := (
			st.x
			if st.x > sl.position.x + 34.0 and st.x < sl.position.x + sl.size.x - 12.0
			else sl.position.x + sl.size.x / 2.0
		)
		_leaders[n] = [Vector2(x, sl.position.y), st]
	queue_redraw()


## The bays' outlines on the panel: each pair of internal stations (by place, left to right) a box around them under
## the fuselage.
func _bays(fr: Rect2) -> Array:
	var xs := internal.map(func(n): return _at(n, fr))
	xs.sort_custom(func(a, b): return a.x < b.x)
	var out := []
	var pad := fr.size.x / picture.get_width() * 14.0
	for i in range(0, xs.size() - 1, 2):
		var y := maxf(xs[i].y, xs[i + 1].y)
		out.append(Rect2(xs[i].x - pad, y - pad * 0.6, xs[i + 1].x - xs[i].x + 2.0 * pad, pad * 1.4))
	return out


## Centres as near `want` (rising) as `w` + GAP apart allows, inside [lo, hi] where they fit.
static func _spread(want: Array, lo: float, hi: float, w: float) -> Array:
	var xs := want.duplicate()
	var d := w + GAP
	for i in range(1, xs.size()):
		xs[i] = maxf(xs[i], xs[i - 1] + d)
	var over: float = xs[-1] - hi
	if over > 0.0:
		for i in xs.size():
			xs[i] -= over
	for i in range(xs.size() - 2, -1, -1):
		xs[i] = minf(xs[i], xs[i + 1] - d)
	var under: float = lo - xs[0]
	if under > 0.0:
		for i in xs.size():
			xs[i] += under
	return xs


func _draw() -> void:
	if picture == null:
		return
	var fr := _frame()
	draw_texture_rect(picture, fr, false)
	if not internal.is_empty():
		# The bays' outlines under the fuselage, in the drawing's line style.
		for r in _bays(fr):
			draw_rect(r, Color("dfe3e8"), false, 2.0, true)
	for n in _leaders:
		var top: Vector2 = _leaders[n][0]
		var st: Vector2 = _leaders[n][1]
		var from := Vector2(top.x, top.y - 3.0)
		var to: Vector2
		var d := Vector2.UP
		if _leaders[n].size() > 2:
			# Up, across at its height, up to the bay.
			var y: float = _leaders[n][2]
			to = st + Vector2(0, 3)
			draw_polyline(PackedVector2Array([from, Vector2(from.x, y), Vector2(st.x, y), to]), MUTED, 1.5, true)
		elif absf(st.x - top.x) < 0.5:
			# Straight up under its station.
			to = Vector2(top.x, st.y + 8.0)
			draw_line(from, to, MUTED, 1.5, true)
		else:
			# Up to the station's height, then across to it.
			var corner := Vector2(top.x, st.y)
			to = st + Vector2(signf(top.x - st.x) * 8.0, 0.0)
			d = (to - corner).normalized()
			draw_line(from, corner, MUTED, 1.5, true)
			draw_line(corner, to, MUTED, 1.5, true)
		var nn := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([to, to - d * 9.0 + nn * 4.5, to - d * 9.0 - nn * 4.5]), MUTED)


## The dragged store on the pointer (on `_over`, above the slots), the slots' picture box size, lifted a little over
## its shadow.
func _draw_dragged() -> void:
	if _dragged == null:
		return
	var ts := Vector2(_dragged.get_size()) * minf(PIC.x / _dragged.get_width(), PIC.y / _dragged.get_height())
	var at := _over.get_global_transform_with_canvas().affine_inverse() * _pointer - ts / 2.0 - Vector2(0, 4)
	_over.draw_texture_rect(_dragged, Rect2(at + Vector2(3, 6), ts), false, Color(0, 0, 0, 0.45))
	_over.draw_texture_rect(_dragged, Rect2(at, ts), false)


## One store the jet may carry, in the Arming page's inventory column: its picture and caption, and its count: the
## ones left where the unit record gives a count, else the ones on the jet. A drag source; Enter hangs it on the slot
## picked (`on_choose`). An empty `id` is the keyboard's "Empty" entry, which takes the picked slot's store off.
class Item:
	extends VBoxContainer
	var id := ""
	var tex: Texture2D
	var read_only := false
	## False for a store with no model of ours yet: greyed, not dragged or chosen (the user: "disabled for now").
	var flyable := true
	var on_choose: Callable

	func setup(store_id: String, picture: Texture2D, caption: String, count) -> void:
		id = store_id
		tex = picture
		name = "Item" + (store_id if store_id != "" else "Empty")
		tooltip_text = caption
		add_theme_constant_override("separation", 2)
		focus_mode = Control.FOCUS_NONE if read_only or not flyable else Control.FOCUS_ALL
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		if not flyable:
			modulate = Color(1, 1, 1, 0.35)
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = PIC
			pic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(pic)
		custom_minimum_size.x = 128
		var l := Label.new()
		l.text = caption
		l.theme_type_variation = "Small"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(l)
		if count != "":
			var c := Label.new()
			c.name = "Count"
			c.text = count
			c.theme_type_variation = "Small"
			c.add_theme_color_override("font_color", Look.ACCENT_TEXT)
			add_child(c)

	func _get_drag_data(_at: Vector2) -> Variant:
		if read_only or id == "" or not flyable:
			return null
		return {"store": id, "from": ""}

	## The inventory column (Shelf) the item sits in, through its group's grid.
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
		if has_focus():
			var box := StyleBoxFlat.new()
			box.draw_center = false
			box.border_color = Look.ACCENT
			box.set_border_width_all(2)
			box.set_corner_radius_all(6)
			draw_style_box(box, Rect2(Vector2(-6, -4), size + Vector2(12, 8)))


## The inventory column: a store dragged from a slot and dropped here goes back (`on_drop`, to "").
class Shelf:
	extends VBoxContainer
	var read_only := false
	var on_drop: Callable

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return not read_only and data is Dictionary and str(data.get("from", "")) != ""

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(data, "")
