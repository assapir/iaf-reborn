# A floating frame window of the original menus (docs/front-end.md §7): black client, borders
# cropped from horzborder/vertborder, corners, a title bar with its tab art and close / max / min
# buttons. Content is a briefing text (RichTextLabel with the original custom scrollbar, §6) or a
# bitmap. Geometry is in the original 640x480 space, relative to the TSD client origin.
extends Control

signal closed
signal link_clicked(name: String)

const BORDER := 5.0
const TITLE_Y := 4.0
const TITLE_H := 11.0
const BTN := Vector2(9, 8)
## Briefing rich edit background (EM_SETBKGNDCOLOR 0x685e5e, FUN_0050d710).
const RICH_BG := Color8(94, 94, 104)
const SCROLL_W := 10.0
## Briefing text: \fs24 = 12 pt at 96 dpi.
const TEXT_PX := 16.0
const MIN_SIZE := Vector2(150, 100)

var fe: Control  # the front end (textures, scale, sounds)
var origin := Vector2.ZERO  # TSD client origin (640 space)
var rect := Rect2()  # window rect in TSD client coordinates
var tab_art := "framewnd/brief_t.png"
## Title-bar buttons, right to left: close always, then max / min when present.
var has_max := true
var has_min := true
var active := true
var maximised := false
var restore_rect := Rect2()
var bounds := Rect2(0, 0, 453, 357)  # where maximise goes (TSD client)

var rich: RichTextLabel
var body_clip: Control
var image: Texture2D
var scroll := 0.0  # text scroll in 640-space pixels
var pressed_btn := ""
var drag_from := Vector2.INF
var drag_thumb := -1.0


func setup(front_end: Control, client_origin: Vector2, r: Rect2) -> void:
	fe = front_end
	origin = client_origin
	rect = r
	mouse_filter = Control.MOUSE_FILTER_STOP


## Shows RTF text (BBCode from briefings.json). Underlined runs named in `links` become links.
func set_text(bbcode: String, links: Array) -> void:
	if rich == null:
		rich = RichTextLabel.new()
		rich.bbcode_enabled = true
		rich.fit_content = true
		rich.scroll_active = false
		rich.mouse_filter = Control.MOUSE_FILTER_PASS
		rich.meta_underlined = false
		rich.meta_clicked.connect(func(meta): link_clicked.emit(str(meta)))
		for pair in [["normal_font", 400, false], ["bold_font", 700, false], ["italics_font", 400, true], ["bold_italics_font", 700, true]]:
			rich.add_theme_font_override(pair[0], preload("res://util/img.gd").arial(pair[1], pair[2]))
		body_clip = Control.new()
		body_clip.clip_contents = true
		body_clip.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(body_clip)
		body_clip.add_child(rich)
	# Hebrew briefings are right-to-left paragraphs; one without a Hebrew version (English text) stays left-aligned.
	var text := _linkify(bbcode, links)
	var hebrew: bool = fe._he() and RegEx.create_from_string("[\\x{05D0}-\\x{05EA}]").search(text) != null
	rich.text = "[right]%s[/right]" % text if hebrew else text
	image = null
	scroll = 0.0


func set_image(tex: Texture2D) -> void:
	image = tex
	if rich != null:
		body_clip.queue_free()
		rich = null
		body_clip = null


## The original makes every underlined run that matches a .brl entry name clickable.
static func _linkify(bbcode: String, links: Array) -> String:
	var re := RegEx.create_from_string("\\[u\\](.+?)\\[/u\\]")
	var out := ""
	var at := 0
	for m in re.search_all(bbcode):
		out += bbcode.substr(at, m.get_start() - at)
		var name := m.get_string(1)
		var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(name, "", true).strip_edges().to_lower()
		if plain in links:
			out += "[url=%s]%s[/url]" % [plain, m.get_string(0)]
		else:
			out += m.get_string(0)
		at = m.get_end()
	return out + bbcode.substr(at)


func _s() -> float:
	return fe._scale()


func _process(_delta: float) -> void:
	# Parent is the TSD client; geometry is client-local.
	position = rect.position * _s()
	size = rect.size * _s()
	if rich != null:
		var s := _s()
		var body := _body()
		var fs := int(round(TEXT_PX * s))
		rich.add_theme_font_size_override("normal_font_size", fs)
		rich.add_theme_font_size_override("bold_font_size", fs)
		rich.add_theme_font_size_override("italics_font_size", fs)
		rich.add_theme_font_size_override("bold_italics_font_size", fs)
		body_clip.position = body.position * s
		body_clip.size = Vector2(body.size.x - SCROLL_W, body.size.y) * s
		rich.size = Vector2(body.size.x - SCROLL_W - 4, 0) * s
		rich.position = Vector2(2, 2 - scroll) * s
		scroll = clampf(scroll, 0.0, _max_scroll())
	queue_redraw()


## Client area below the title bar (window-local, 640 space).
func _body() -> Rect2:
	return Rect2(BORDER, TITLE_Y + TITLE_H + 1, rect.size.x - 2 * BORDER, rect.size.y - TITLE_Y - TITLE_H - 1 - 4)


func _max_scroll() -> float:
	if rich == null:
		return 0.0
	return maxf(0.0, rich.get_content_height() / _s() + 4 - _body().size.y)


func _blit(path: String, src: Rect2, dest: Vector2) -> void:
	var t: Texture2D = fe._tex(path)
	if t != null:
		var a: float = fe.art_scale
		draw_texture_rect_region(t, Rect2(dest * _s(), src.size * _s()), Rect2(src.position * a, src.size * a))


func _art_size(path: String) -> Vector2:
	var t: Texture2D = fe._tex(path)
	return fe._art_size(t) if t != null else Vector2.ZERO


func _draw() -> void:
	var s := _s()
	var w := rect.size.x
	var h := rect.size.y
	draw_rect(Rect2(Vector2.ZERO, rect.size * s), Color.BLACK)
	# Content.
	var body := _body()
	if rich != null:
		draw_rect(Rect2(body.position * s, body.size * s), RICH_BG)
	elif image != null:
		var isz: Vector2 = fe._art_size(image)
		var shown := isz.min(body.size)
		draw_texture_rect_region(image, Rect2(body.position * s, shown * s), Rect2(Vector2.ZERO, shown * fe.art_scale))
	# Borders: centre-cropped strips, corners last.
	_blit("framewnd/horzborder.png", Rect2(320 - w / 2, 0, w, 4), Vector2.ZERO)
	_blit("framewnd/horzborder.png", Rect2(320 - w / 2, 0, w, 4), Vector2(0, h - 4))
	_blit("framewnd/vertborder.png", Rect2(0, 210 - h / 2, 5, h), Vector2.ZERO)
	_blit("framewnd/vertborder.png", Rect2(0, 210 - h / 2, 5, h), Vector2(w - 5, 0))
	_blit("framewnd/crnr_ul.png", Rect2(0, 0, 5, 5), Vector2.ZERO)
	_blit("framewnd/crnr_ur.png", Rect2(0, 0, 5, 5), Vector2(w - 5, 0))
	_blit("framewnd/crnr_bl.png", Rect2(0, 0, 5, 5), Vector2(0, h - 5))
	_blit("framewnd/crnr_br.png", Rect2(0, 0, 5, 5), Vector2(w - 5, h - 5))
	# Title bar: the 640-wide bar image with the tab art centred in it, cropped to the bar.
	var bar_w := w - 2 * BORDER
	var buttons := _buttons()
	var btn_w := buttons.size() * (BTN.x + 1)
	var src_x := (640 + btn_w - bar_w) / 2
	var bar := "framewnd/title_a.png" if active else "framewnd/title_na.png"
	_blit(bar, Rect2(src_x, 0, bar_w, TITLE_H), Vector2(BORDER, TITLE_Y))
	var tab := _art_size(tab_art)
	if tab != Vector2.ZERO:
		var tab_x := (640 - tab.x) / 2 - src_x
		var vis := Rect2(maxf(0, -tab_x), 0, minf(tab.x, bar_w - tab_x) - maxf(0, -tab_x), tab.y)
		if vis.size.x > 0:
			_blit(tab_art, vis, Vector2(BORDER + tab_x + vis.position.x, TITLE_Y))
	for b in buttons:
		var art: String = b[0]
		if art == "maxbut" and maximised:
			art = "normbut"
		var frame := 2 if pressed_btn == b[0] else 0
		_blit("framewnd/%s_%d.png" % [art, frame], Rect2(Vector2.ZERO, BTN), b[1])
	# Custom vertical scrollbar at the right edge of the text (§6).
	if rich != null:
		var x := body.end.x - SCROLL_W
		var track_h := body.size.y
		_blit("framewnd/scroll.png", Rect2(0, 0, SCROLL_W, track_h), Vector2(x, body.position.y))
		_blit("framewnd/slupb_%d.png" % (2 if pressed_btn == "up" else 0), Rect2(Vector2.ZERO, Vector2(10, 8)), Vector2(x, body.position.y))
		_blit("framewnd/sldownb_%d.png" % (2 if pressed_btn == "down" else 0), Rect2(Vector2.ZERO, Vector2(10, 8)), Vector2(x, body.end.y - 8))
		_blit("framewnd/slider.png", Rect2(0, 0, 10, 23), Vector2(x, _thumb_y()))


## Title-bar buttons, right to left: [art, position] (window-local, 640 space).
func _buttons() -> Array:
	var out := []
	var x := rect.size.x - BORDER - 1 - BTN.x
	var y := TITLE_Y + (TITLE_H - BTN.y) / 2
	out.append(["closebut", Vector2(x, y)])
	if has_max:
		x -= BTN.x + 1
		out.append(["maxbut", Vector2(x, y)])
	if has_min:
		x -= BTN.x + 1
		out.append(["minbut", Vector2(x, y)])
	return out


func _thumb_range() -> Vector2:
	var body := _body()
	return Vector2(body.position.y + 8, body.end.y - 8 - 23)


func _thumb_y() -> float:
	var r := _thumb_range()
	var m := _max_scroll()
	return r.x if m <= 0.0 else lerpf(r.x, r.y, scroll / m)


func _gui_input(event: InputEvent) -> void:
	var p: Vector2 = event.position / _s() if "position" in event else Vector2.ZERO
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_scroll_by(-TEXT_PX * 3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else TEXT_PX * 3)
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			get_parent().move_child(self, -1)  # a click raises the window
			for b in _buttons():
				if Rect2(b[1], BTN).has_point(p):
					pressed_btn = b[0]
					accept_event()
					return
			if rich != null:
				var body := _body()
				var x := body.end.x - SCROLL_W
				if Rect2(x, body.position.y, SCROLL_W, 8).has_point(p):
					pressed_btn = "up"
					_scroll_by(-TEXT_PX)
				elif Rect2(x, body.end.y - 8, SCROLL_W, 8).has_point(p):
					pressed_btn = "down"
					_scroll_by(TEXT_PX)
				elif Rect2(x, _thumb_y(), SCROLL_W, 23).has_point(p):
					drag_thumb = p.y - _thumb_y()
				elif Rect2(x, body.position.y, SCROLL_W, body.size.y).has_point(p):
					_scroll_by(body.size.y * (1 if p.y > _thumb_y() else -1))
			if p.y < TITLE_Y + TITLE_H and pressed_btn == "":
				drag_from = p
			accept_event()
		else:
			var was := pressed_btn
			pressed_btn = ""
			drag_from = Vector2.INF
			drag_thumb = -1.0
			for b in _buttons():
				if b[0] == was and Rect2(b[1], BTN).has_point(p):
					_title_button(was)
			accept_event()
	elif event is InputEventMouseMotion:
		if drag_from != Vector2.INF and not maximised:
			rect.position += p - drag_from
		elif drag_thumb >= 0.0:
			var r := _thumb_range()
			scroll = clampf(inverse_lerp(r.x, r.y, p.y - drag_thumb), 0.0, 1.0) * _max_scroll()


func _scroll_by(d: float) -> void:
	scroll = clampf(scroll + d, 0.0, _max_scroll())


func _title_button(which: String) -> void:
	match which:
		"closebut":
			closed.emit()
			queue_free()
		"maxbut":
			if maximised:
				rect = restore_rect
			else:
				restore_rect = rect
				rect = bounds
			maximised = not maximised
		"minbut":
			# Minimised: only the title bar stays (UNCERTAIN how the original lays it out).
			if rect.size.y > TITLE_Y + TITLE_H + 5:
				restore_rect = rect
				rect.size = Vector2(MIN_SIZE.x, TITLE_Y + TITLE_H + 5)
			else:
				rect = restore_rect
