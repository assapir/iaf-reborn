# The briefing's Arming drawing (modern-iaf/docs/front-end.md §10): our own jet's front view in light lines
# (data/drawings/<jet>_front.png, traced from its model by tests/_jet_fronts.gd; its stations' places in
# <jet>_front.json) and under it one slot per station (a Slot Control each, a drop target later): a thin rounded
# frame with the station's number on its edge, the store's side view (data/stores/<weapon id>.png,
# tests/_store_pictures.gd) and its short name under it, the name also the tooltip; an empty station shows its empty
# slot. The wing stations' slots form one row in station order (9 to 1 left to right as the front view shows them),
# the drop tanks' a second row straight under stations 4 and 6; each slot's leader runs straight up, or up and then
# across at its station's height, to its station, none crossing another. A jet with internal stations (the Adir's
# bays) has their slots in the second row instead, side by side under the fuselage, each marked "internal" on its
# bottom edge, and every leader straight from its slot to its station (to where a bay opens). Every slot is the same
# size and every store picture fits one box (PIC). The drawing never
# mirrors: station 1, the left wing tip, is on the viewer's right as the jet faces the reader.
extends Control

const Look := preload("look.gd")
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


## One station's slot: its frame, number, store picture and name (display only for now).
class Slot:
	extends Control
	var station := ""
	## [weapon id, name], empty for an empty station.
	var store: Array = []
	var tex: Texture2D
	## The mark on its bottom edge ("internal"), empty: none.
	var tag := ""

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var box := StyleBoxFlat.new()
		box.bg_color = Color(Look.PANEL, 0.0)
		box.border_color = Look.EDGE if not store.is_empty() else Look.LINE
		box.set_border_width_all(1)
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
		if store.is_empty():
			return
		if tex != null:
			# Fitted into the picture box by its longest side.
			var ts := Vector2(tex.get_size()) * minf(PIC.x / tex.get_width(), PIC.y / tex.get_height())
			var at := Vector2((size.x - ts.x) / 2.0, 14.0 + (PIC.y - ts.y) / 2.0)
			draw_texture_rect(tex, Rect2(at, ts), false)
		# The caption under the box, on two lines where it needs them.
		var y := 14.0 + PIC.y + 15.0
		draw_multiline_string(
			font, Vector2(4, y), str(store[1]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 14, 2, Look.MUTED
		)


## The drawing and its stations {"1": [x, y], …} in its pixels.
var picture: Texture2D
var stations := {}
## Station number → [the store's weapon id, its name] (absent: none).
var stores := {}
## The internal stations' numbers (String), and the mark their slots carry.
var internal: Array = []
var internal_tag := ""
## Station number (String) → its Slot.
var slots := {}
var _pictures := {}
## Each slot's leader as drawn: station → [its start on the slot's top edge, the station].
var _leaders := {}


func _ready() -> void:
	resized.connect(_layout)


## Loads `<dir>/<name>.json` and its picture; false when either is missing.
func load_drawing(dir: String, name: String) -> bool:
	var meta := Settings.load_json(dir.path_join(name + ".json"))
	if meta.is_empty():
		return false
	var img := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(str(meta.get("image", "")))))
	if img == null or img.is_empty():
		return false
	picture = ImageTexture.create_from_image(img)
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
			sl.tooltip_text = str(sl.store[1])
		if str(n) in internal:
			sl.tag = internal_tag
		sl.size = SLOT
		add_child(sl)
		slots[str(n)] = sl
	_layout()


## The store's picture (data/stores/<id>.png), null without one.
func store_picture(id: String) -> Texture2D:
	if not _pictures.has(id):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://data/stores/%s.png" % id))
		_pictures[id] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
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
		# The first row clear of the outer bay leaders where they pass its bottom edge.
		edges = []
		for k in [lower[0][1], lower[-1][1]]:
			var c := Vector2(slots[k].position.x + SLOT.x / 2.0, y2)
			var st := _at(k, fr)
			edges.append(lerpf(c.x, st.x, ROW_GAP / (y2 - st.y)))
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
		if not internal.is_empty():
			# A jet with bays: each leader straight from its slot's top middle to its station, a fan that crosses none.
			_leaders[n] = [Vector2(sl.position.x + sl.size.x / 2.0, sl.position.y), st, true]
			continue
		# Straight up from the slot's top edge where its station is over it (clear of the number), else from its middle.
		var x := (
			st.x
			if st.x > sl.position.x + 34.0 and st.x < sl.position.x + sl.size.x - 12.0
			else sl.position.x + sl.size.x / 2.0
		)
		_leaders[n] = [Vector2(x, sl.position.y), st]
	queue_redraw()


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
	draw_texture_rect(picture, _frame(), false)
	for n in _leaders:
		var top: Vector2 = _leaders[n][0]
		var st: Vector2 = _leaders[n][1]
		var from := Vector2(top.x, top.y - 3.0)
		var to: Vector2
		var d := Vector2.UP
		if _leaders[n].size() > 2:
			d = (st - from).normalized()
			to = st - d * 6.0
			draw_line(from, to, MUTED, 1.5, true)
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


## One store the jet may carry, in the Arming page's inventory column: its picture and caption, and the count the unit
## record gives (none: no count). One Control each, so dragging it onto a slot is a small step later.
class Item:
	extends VBoxContainer
	var id := ""

	func setup(store_id: String, tex: Texture2D, caption: String, count) -> void:
		id = store_id
		name = "Item" + store_id
		tooltip_text = caption
		add_theme_constant_override("separation", 2)
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = PIC
			pic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			add_child(pic)
		var l := Label.new()
		l.text = caption if count == null else "%s × %d" % [caption, int(count)]
		l.theme_type_variation = "Small"
		add_child(l)
