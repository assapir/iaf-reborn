# The in-flight message box (CIAFRenderMsgBoxDlg, docs/front-end.md §16.4): while the flight window exists,
# FUN_004e3f30 → FUN_004e66c0 builds this box instead of the menus' mbgback.bmp box (game/mission/mission_box.gd).
# GDI-drawn into the flight's surface (FUN_004e5c40 from FUN_004d9080 via FUN_004e69a0), in the On-The-Fly menu's
# style: a text panel, round buttons with msgs.trx labels, a two-pen frame; the scene shows between them. Laid out
# by FUN_004e52a0, centred on the surface (CenterWindow). Mouse only: a button acts on the press (WM_LBUTTONDOWN
# 0x4e6350, ButtonIn.wav); clicks outside the box go to the flight window (the menu's items, the cockpit).
extends Control

signal chosen(button: String)

const Gdi := preload("res://util/gdi.gd")
const Overlay := preload("res://terrain/flight_overlay.gd")
## Arial size 11 weight 400 (12 ppem, cell 15), "Arial" at 0x605ab0.
const FONT_SIZE := 11
const WEIGHT := 400
## DAT_00605ab8 / abc = 8 (button padding), ac0 / ac4 = 8 (text panel padding), ac8 / acc = 10 (frame margin).
const PAD := 8
const MARGIN := 10
## The button labels: msgs.trx lines (the strings at 0x836be8 + line·300). The exe's Yes / No / Cancel box labels
## its third button with line 1 (NO) too (FUN_004e52a0 @4e52d2).
const LABEL_LINE := {"yes": 0, "no": 1, "ok": 2, "can": 1, "deb": 4, "fly": 5, "exit": 6}

## The raw msgs.trx line; drawn upper-cased (_strupr), on one line (TextOut).
var text := ""
var buttons: Array = []
var labels: Array[String] = []
## In box units (origin at the box's top-left corner): the box size, the text panel and the buttons (in `buttons`
## order, left to right).
var box_size := Vector2i.ZERO
var panel := Rect2i()
var button_rects: Array[Rect2i] = []
var _font: SystemFont
var _sfx: AudioStreamPlayer
## The cursor (window coordinates), from the last mouse event (GetCursorPos every frame in the original).
var mouse := Vector2(-1, -1)


func setup(msg: int, button_names: Array) -> void:
	buttons = button_names
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var lines := Settings.msgs()
	text = lines[msg].strip_edges() if msg < lines.size() else ""
	for b in buttons:
		var i: int = LABEL_LINE.get(b, 2)
		labels.append(lines[i].strip_edges().to_upper() if i < lines.size() else "")
	_font = Gdi.arial(WEIGHT)
	_layout()
	_sfx = AudioStreamPlayer.new()
	var dir := Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var wav := dir.path_join("wav/buttonin.wav")
	if FileAccess.file_exists(wav):
		_sfx.stream = AudioStreamWAV.load_from_file(wav)
	add_child(_sfx)


## FUN_004e52a0. tw × th = the upper-cased text's extent, bh = the tallest label. Button width bw = widest label
## + 48 (OK, Yes / No) or + 24 (the others). Width = max(tw + 16, buttons) + 20 with buttons = bw + 16 (OK),
## 2·(bw + 26) (two), 3·(bw + 16) + 40 (three); height = th + bh + 59. Text panel (10, 10, W - 10, th + 26);
## buttons from the panel's bottom + 7, bh + 16 high: the first at the left (10), the last ending at W - 10, a
## middle / single one centred (W/2 - 8 - bw/2 to W/2 + 8 + bw/2).
func _layout() -> void:
	var px := Gdi.ppem(FONT_SIZE)
	var t := Gdi.extent(_font, WEIGHT, text.to_upper(), px)
	var lw := 0
	var bh := 0
	for l in labels:
		var e := Gdi.extent(_font, WEIGHT, l, px)
		lw = maxi(lw, e.x)
		bh = maxi(bh, e.y)
	var n := labels.size()
	var bw := lw + (48 if n <= 1 or buttons == ["yes", "no"] else 24)
	var row := bw + 2 * PAD
	if n == 2:
		row = (bw + 2 * PAD + 10) * 2
	elif n == 3:
		row = (bw + 2 * PAD) * 3 + 40
	var w := maxi(t.x + 2 * PAD, row) + 2 * MARGIN
	box_size = Vector2i(w, bh + 2 * (PAD + MARGIN + PAD) + t.y + 7)
	panel = Rect2i(MARGIN, MARGIN, w - 2 * MARGIN, t.y + 2 * PAD)
	var top := panel.end.y + 7
	var h := bh + 2 * PAD
	button_rects.clear()
	for i in n:
		var x := w / 2 - PAD - bw / 2  # centred: one button, or the middle of three
		if n > 1 and i == 0:
			x = MARGIN
		elif n > 1 and i == n - 1:
			x = panel.end.x - 2 * PAD - bw
		button_rects.append(Rect2i(x, top, bw + 2 * PAD, h))


func _scale() -> float:
	return minf(size.x / 640.0, size.y / 480.0)


## The box's top-left corner in 640×480 units: CenterWindow on the surface ((640 - W)/2 at 640×480; on a wider
## window the window's centre, as the menus' box).
func origin() -> Vector2i:
	var s := _scale()
	return (
		Vector2i(int(size.x / s) / 2 - box_size.x / 2, int(size.y / s) / 2 - box_size.y / 2)
		if s > 0.0
		else Vector2i.ZERO
	)


## Clicks reach the box only inside its window (a child window of the main window); the rest go to the flight.
func _has_point(p: Vector2) -> bool:
	return Rect2i(origin(), box_size + Vector2i.ONE).has_point(Vector2i((p / _scale()).floor()))


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse = event.position


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := _scale()
	if s <= 0.0:
		return
	var o := origin()
	var px := Gdi.ppem(FONT_SIZE)
	var cursor := Vector2i((mouse / s).floor()) - o
	# FUN_004e5c40: the text panel (normal brush, 1 px dark pen, 16×16 corners), the text TA_CENTER|TA_TOP.
	Gdi.round_rect(
		self, Rect2i(panel.position + o, panel.size), 2 * PAD, 2 * PAD, Overlay.PEN_DARK, 1, Overlay.NORMAL, s
	)
	Gdi.text_out(
		self,
		_font,
		WEIGHT,
		text.to_upper(),
		px,
		o.x + (panel.position.x + panel.end.x) / 2,
		o.y + panel.position.y + PAD,
		s,
		Color.BLACK,
		true
	)
	# The buttons: the hover brush under the cursor (FUN_004f0680, edges included).
	for i in button_rects.size():
		var r := button_rects[i]
		var brush := Overlay.HOVER if Gdi.hit(r, cursor) else Overlay.NORMAL
		Gdi.round_rect(self, Rect2i(r.position + o, r.size), 2 * PAD, 2 * PAD, Overlay.PEN_DARK, 1, brush, s)
		Gdi.text_out(
			self,
			_font,
			WEIGHT,
			labels[i],
			px,
			o.x + (r.position.x + r.end.x) / 2,
			o.y + r.position.y + PAD,
			s,
			Color.BLACK,
			true
		)
	# The frame (0, 0, W, H) with NULL_BRUSH, 20×20 corners: the 2 px light pen, then the 1 px dark pen.
	var f := Rect2i(o, box_size)
	Gdi.round_rect(self, f, 2 * MARGIN, 2 * MARGIN, Overlay.PEN_LIGHT, 2, Color.TRANSPARENT, s)
	Gdi.round_rect(self, f, 2 * MARGIN, 2 * MARGIN, Overlay.PEN_DARK, 1, Color.TRANSPARENT, s)


## The button under a point in box units, -1 for none.
func button_at(p: Vector2i) -> int:
	for i in button_rects.size():
		if Gdi.hit(button_rects[i], p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var i := button_at(Vector2i((event.position / _scale()).floor()) - origin())
		if i >= 0:
			if _sfx.stream != null and get_parent() != null:
				# The box closes on the choice; the click sound plays on.
				remove_child(_sfx)
				get_parent().add_child(_sfx)
				_sfx.finished.connect(_sfx.queue_free)
				_sfx.play()
			chosen.emit(buttons[i])
	accept_event()
