# The flight window's own overlays (docs/front-end.md §16): the Ctrl+P "II  PAUSE" text with its white
# wash, and the Ctrl+O On-The-Fly menu. GDI-drawn into the 640×480 back surface in the original
# (FUN_004d9080 @4d9351..4d94da, FUN_004ee9f0); here on the 640×480 frame scaled to fit, like the menus.
# It runs while the scene tree is paused (the sim is frozen) and takes the keys then: the flight's own
# input handler is paused with the sim.
extends Control

const Gdi := preload("res://util/gdi.gd")
const KeyTable := preload("res://controls/key_table.gd")

## "II  PAUSE" (0x649a98): Arial size 50 weight 900 (Arial Bold, 58 ppem), RGB(0,255,0), TA_BOTTOM|TA_LEFT at (30, 450),
## 500 ms on / 500 ms off (timeGetTime), then a white wash alpha 0x63 over the surface (0, 0, 640, 480) (FUN_004022d0).
const PAUSE_TEXT := "II  PAUSE"
const PAUSE_POS := Vector2i(30, 450)
const PAUSE_COLOUR := Color8(0, 255, 0)
const PAUSE_BLINK_MS := 500
const PAUSE_WEIGHT := 900
const WASH := Color8(255, 255, 255, 0x63)
## The menu (ctor FUN_004ee760): msgs.trx lines, upper-cased (_strupr). 23 "Calibrate joystick" is not in it.
const MENU_ITEMS := [18, 19, 20, 21, 22, 24]
const MENU_ACTIONS := ["resume", "end", "restart", "new", "prefs", "quit"]
## FUN_004ee7b0: normal brush RGB(191,191,175), hover RGB(159,159,128), pens PS_INSIDEFRAME 2 px RGB(186,186,173)
## and 1 px RGB(21,21,19); Arial size 10 weight 400 (11 ppem); layout FUN_004ee7b0(hdc, 5, 10).
const NORMAL := Color8(191, 191, 175)
const HOVER := Color8(159, 159, 128)
const PEN_LIGHT := Color8(186, 186, 173)
const PEN_DARK := Color8(21, 21, 19)
const MENU_ORIGIN := Vector2i(5, 10)
const MENU_SIZE := 10
const MENU_WEIGHT := 400
## DAT_00606508 / 0060650c = 8 (item padding, corner ellipse 16×16), DAT_00606518 / 0060651c = 10 (frame margin,
## corner ellipse 20×20).
const ITEM_PAD := 8
const FRAME_PAD := 10

## The flight scene (terrain_view.gd): paused, menu_open, keys, menu_choice(), window_key().
var host: Node
var labels: Array[String] = []
var _font: SystemFont
var _pause_font: SystemFont
## The item under the cursor (FUN_004ee9f0 reads GetCursorPos every frame), -1 for none.
var hover := -1
var _rects: Array[Rect2i] = []
## The cursor (window coordinates), from the last mouse event.
var mouse := Vector2(-1, -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Gdi.arial(MENU_WEIGHT)
	_pause_font = Gdi.arial(PAUSE_WEIGHT)
	var lines := Settings.msgs()
	for i in MENU_ITEMS:
		labels.append(lines[i].strip_edges().to_upper() if i < lines.size() else "")


## GDI on the flight window's own surface (client coordinates, the menu at (5, 10) in its top-left corner,
## FUN_004ee7b0(hdc, 5, 10)): 640×480 units scaled to the window's height, anchored at its top-left corner
## (not a centred 4:3 box: on a wide window the menu stays in the corner as in the original).
func _scale() -> float:
	return minf(size.x / 640.0, size.y / 480.0)


## Item rects in 640×480 units (FUN_004ee7b0): W = widest label, H = tallest (GetTextExtentPoint32: Arial
## 11 ppem, cell 14); item i at left 15, right 15 + W + 16, top 20 + i·(H + 23), bottom top + H + 16.
func item_rects() -> Array[Rect2i]:
	if _rects.is_empty():
		var w := 0
		var h := 0
		for l in labels:
			var e := Gdi.extent(_font, MENU_WEIGHT, l, Gdi.ppem(MENU_SIZE))
			w = maxi(w, e.x)
			h = maxi(h, e.y)
		for i in labels.size():
			var top := MENU_ORIGIN.y + FRAME_PAD + i * (h + 7 + 2 * ITEM_PAD)
			_rects.append(Rect2i(MENU_ORIGIN.x + FRAME_PAD, top, w + 2 * ITEM_PAD, h + 2 * ITEM_PAD))
	return _rects


## The outer frame: (5, 10) to (item right + 10, last item bottom + 10).
func frame_rect() -> Rect2i:
	var r := item_rects()
	return Rect2i(MENU_ORIGIN, Vector2i(r[0].end.x + FRAME_PAD, r[r.size() - 1].end.y + FRAME_PAD) - MENU_ORIGIN)


## A window point in 640×480 units (whole pixels of the original's surface).
func to_units(p: Vector2) -> Vector2i:
	return Vector2i((p / _scale()).floor())


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse = event.position


func _process(_delta: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if host != null and host.menu_open else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var s := _scale()
	if host == null or s <= 0.0:
		return
	# FUN_004d9080 @4d946f: while a message box is up the box is drawn instead of the menu.
	if host.menu_open and host._msgbox == null:
		hover = _item_at(mouse)
		var rects := item_rects()
		for i in rects.size():
			var r := rects[i]
			# FUN_004ee9f0: RoundRect 16×16 with the 1 px dark pen, hover brush under the cursor (not while paused).
			Gdi.round_rect(
				self, r, 2 * ITEM_PAD, 2 * ITEM_PAD, PEN_DARK, 1, HOVER if i == hover and not host.paused else NORMAL, s
			)
			Gdi.text_out(
				self,
				_font,
				MENU_WEIGHT,
				labels[i],
				Gdi.ppem(MENU_SIZE),
				(r.position.x + r.end.x) / 2,
				r.position.y + ITEM_PAD,
				s,
				Color.BLACK,
				true
			)
		# The frame with NULL_BRUSH (the scene shows between the items): RoundRect 20×20, 2 px light pen, then 1 px dark.
		var f := frame_rect()
		Gdi.round_rect(self, f, 2 * FRAME_PAD, 2 * FRAME_PAD, PEN_LIGHT, 2, Color.TRANSPARENT, s)
		Gdi.round_rect(self, f, 2 * FRAME_PAD, 2 * FRAME_PAD, PEN_DARK, 1, Color.TRANSPARENT, s)
	if host.paused:
		if (Time.get_ticks_msec() / PAUSE_BLINK_MS) % 2 == 0:
			Gdi.text_out(
				self,
				_pause_font,
				PAUSE_WEIGHT,
				PAUSE_TEXT,
				Gdi.ppem(50, PAUSE_WEIGHT),
				PAUSE_POS.x,
				PAUSE_POS.y,
				s,
				PAUSE_COLOUR,
				false,
				true
			)
		# The wash is drawn after the text, so it covers it too (D3D only; the software renderer has none). Its
		# rect (0, 0, 640, 480) is the whole back surface: here the whole window.
		draw_rect(Rect2(Vector2.ZERO, size), WASH)


func _gui_input(event: InputEvent) -> void:
	if host == null or not host.menu_open:
		return
	# Mouse only (no keyboard navigation): WM_LBUTTONDOWN (0x4dc810) → hit test FUN_004eec60 → FUN_004dc0d0(item).
	# The original tests the items even while a message box hides the menu; clicks on the box itself go to the box.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not host.paused:
		var i := _item_at(event.position)
		if i >= 0:
			host.menu_choice(MENU_ACTIONS[i])
	accept_event()


func _item_at(p: Vector2) -> int:
	var u := to_units(p)
	var rects := item_rects()
	for i in rects.size():
		if Gdi.hit(rects[i], u):
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
