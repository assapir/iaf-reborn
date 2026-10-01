# The flight window's own overlays (docs/front-end.md §16): the Ctrl+P "II  PAUSE" text with its white
# wash, and the Ctrl+O On-The-Fly menu. GDI-drawn into the 640×480 back surface in the original
# (FUN_004d9080 @4d9351..4d94da, FUN_004ee9f0); here on the 640×480 frame scaled to fit, like the menus.
# It runs while the scene tree is paused (the sim is frozen) and takes the keys then: the flight's own
# input handler is paused with the sim.
extends Control

const Img := preload("res://util/img.gd")
const KeyTable := preload("res://controls/key_table.gd")

## "II  PAUSE" (0x649a98): Arial size 50 weight 900, RGB(0,255,0), TA_BOTTOM|TA_LEFT at (30, 450),
## 500 ms on / 500 ms off (timeGetTime), then a full-screen white wash alpha 0x63 (FUN_004022d0).
const PAUSE_TEXT := "II  PAUSE"
const PAUSE_POS := Vector2(30, 450)
const PAUSE_COLOUR := Color8(0, 255, 0)
const PAUSE_BLINK_MS := 500
const WASH := Color8(255, 255, 255, 0x63)
## The menu (ctor FUN_004ee760): msgs.trx lines, upper-cased (_strupr). 23 "Calibrate joystick" is not in it.
const MENU_ITEMS := [18, 19, 20, 21, 22, 24]
const MENU_ACTIONS := ["resume", "end", "restart", "new", "prefs", "quit"]
## GDI: normal brush RGB(191,191,175), hover RGB(159,159,128), frame pens 2 px RGB(186,186,173) and
## 1 px RGB(21,21,19); Arial size 10 weight 400; layout FUN_004ee7b0(hdc, 5, 10).
const MENU_NORMAL := Color8(191, 191, 175)
const MENU_HOVER := Color8(159, 159, 128)
const MENU_PEN_LIGHT := Color8(186, 186, 173)
const MENU_PEN_DARK := Color8(21, 21, 19)
const MENU_ORIGIN := Vector2(5, 10)
## FUN_004eee10: em = cy · p / 100 with cy ≈ 112 for Arial (docs/front-end.md §4).
const ARIAL_CY := 112.0

## The flight scene (terrain_view.gd): paused, menu_open, keys, menu_choice(), window_key().
var host: Node
var labels: Array[String] = []
var _font: SystemFont
var _pause_font: SystemFont
var hover := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Img.arial(400)
	_pause_font = Img.arial(900)
	var dir := Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var lines: PackedStringArray = String(Settings.load_json(dir.path_join("strings.json")).get("msgs", "")).split("\n")
	for i in MENU_ITEMS:
		labels.append(lines[i].strip_edges().to_upper() if i < lines.size() else "")


## The 640×480 screen scaled to fit and centred (as the menus and the message box).
func _scale() -> float:
	return minf(size.x / 640.0, size.y / 480.0)


func _origin() -> Vector2:
	return size / 2 - Vector2(320, 240) * _scale()


func _menu_px() -> int:
	return int(round(ARIAL_CY * 10.0 / 100.0 * _scale()))


## Item rects in 640×480 coordinates (FUN_004ee7b0): W = widest label, H = tallest; item i at left 15,
## right 15 + W + 16, top 20 + i·(H + 23), bottom top + H + 16.
func item_rects() -> Array:
	var s := _scale()
	var px := _menu_px()
	var w := 0.0
	var h := 0.0
	for l in labels:
		var e := _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, px) / s
		w = maxf(w, e.x)
		h = maxf(h, e.y)
	w = round(w)
	h = round(h)
	var out := []
	for i in labels.size():
		var top := MENU_ORIGIN.y + 10.0 + i * (h + 23.0)
		out.append(Rect2(MENU_ORIGIN.x + 10.0, top, w + 16.0, h + 16.0))
	return out


func _to_screen(r: Rect2) -> Rect2:
	return Rect2(_origin() + r.position * _scale(), r.size * _scale())


func _process(_delta: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if host != null and host.menu_open and host._msgbox == null else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	if host == null or _menu_px() < 1:
		return
	var s := _scale()
	# While a message box is up the box is drawn instead of the menu.
	if host.menu_open and host._msgbox == null:
		var rects := item_rects()
		var px := _menu_px()
		for i in rects.size():
			var r := _to_screen(rects[i])
			_round_rect(r, 8.0 * s, MENU_HOVER if i == hover else MENU_NORMAL, MENU_PEN_DARK, maxf(1.0, s))
			var tw := _font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_string(_font, Vector2(r.get_center().x - tw / 2.0, r.position.y + 8.0 * s + _font.get_ascent(px)),
					labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.BLACK)
		# Frame (NULL_BRUSH, the scene shows between the items): 20×20 corners, 2 px light then 1 px dark.
		var last: Rect2 = rects[rects.size() - 1]
		var frame := _to_screen(Rect2(MENU_ORIGIN, Vector2(last.end.x + 10.0, last.end.y + 10.0) - MENU_ORIGIN))
		_round_rect(frame, 10.0 * s, Color.TRANSPARENT, MENU_PEN_LIGHT, 2.0 * maxf(1.0, s))
		_round_rect(frame, 10.0 * s, Color.TRANSPARENT, MENU_PEN_DARK, maxf(1.0, s))
	if host.paused:
		if (Time.get_ticks_msec() / PAUSE_BLINK_MS) % 2 == 0:
			var px := int(round(ARIAL_CY * 50.0 / 100.0 * s))
			draw_string(_pause_font, _origin() + PAUSE_POS * s - Vector2(0, _pause_font.get_descent(px)), PAUSE_TEXT,
					HORIZONTAL_ALIGNMENT_LEFT, -1, px, PAUSE_COLOUR)
		# The wash is drawn after the text, so it covers it too (D3D only; the software renderer has none).
		draw_rect(Rect2(Vector2.ZERO, size), WASH)


## GDI RoundRect: fill and an outline pen.
func _round_rect(r: Rect2, radius: float, fill: Color, pen: Color, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.draw_center = fill.a > 0.0
	sb.border_color = pen
	sb.set_border_width_all(int(ceil(width)))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _gui_input(event: InputEvent) -> void:
	if host == null or not host.menu_open or host._msgbox != null:
		return
	if event is InputEventMouseMotion:
		hover = _item_at(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Mouse only (no keyboard navigation): hit test FUN_004eec60 → FUN_004dc0d0(item).
		var i := _item_at(event.position)
		if i >= 0:
			host.menu_choice(MENU_ACTIONS[i])
	accept_event()


func _item_at(p: Vector2) -> int:
	if _menu_px() < 1:
		return -1
	var rects := item_rects()
	for i in rects.size():
		if _to_screen(rects[i]).has_point(p):
			return i
	return -1


## Keys while the sim is frozen (the flight's own input handler is paused with it): only the flight
## window's commands (FUN_004dc280: 0x7a Esc, 0x84 Ctrl+P, 0x85 Ctrl+O) reach it then.
func _unhandled_input(event: InputEvent) -> void:
	if host == null or not get_tree().paused or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if host.fe_overlay != null:
		return  # the FlyTSD / in-flight Preferences take their own keys
	var rec: int = host.keys.find_key(host.keys.key_of_event(event), Settings.key_bindings)
	if rec >= 0 and host.window_key(int(host.keys.records[rec].press[0])):
		get_viewport().set_input_as_handled()
