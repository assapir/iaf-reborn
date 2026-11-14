# The pilot's paper notebook (modern-iaf/docs/training.md §11, the user's look A of 2026-11-13): a board of sections,
# one tab each down its outer edge, each section cut into pages that fit the paper. A tab click opens its section; the
# wheel, the page's own ‹ › and the owner's keys (turn) turn the pages, past a section's last page into the next one.
# No key hints, no clip, no mission title on it. Laid out on the front end's 1080-high canvas (W x H px), mirrored in
# Hebrew (the tabs down the left edge). The flight's kneeboard (kneeboard.gd) holds one.
# A section: {"id", "tab": its tab's text, "title", "red": the emergency tab's red, "blocks": BBCode paragraphs}; the
# page breaks fall between blocks (a block taller than a page has a page of its own, cut off at its foot).
extends Control

## The page shown changed (a tab, a turn).
signal turned

const WizardTheme := preload("../setup/wizard_theme.gd")
const W := 460.0
const H := 620.0
## The tabs' strip on the outer edge, each tab's height and the gap between them.
const TAB_W := 38.0
const TAB_H := 78.0
const TAB_GAP := 4.0
const TAB_TOP := 40.0
## The paper inside the board: its inset from the board's edges (the tabs' side holds the tabs).
const INSET := Vector2(12, 14)
const PAD := 14.0  # the paper's text inset
const TITLE_Y := 22.0  # the title's top below the paper's (the binding's rings above it)
const BODY_Y := 54.0
const FOOT_H := 30.0
## The colours of the round-2 mock-up (kb.css look A).
const BOARD := Color("3f4248")
const PAPER := Color("f3efe6")
const PAPER_EDGE := [Color("d8d2c4"), Color("c9c2b2")]
const TAB := Color("ddd6c6")
const TAB_LINE := Color("b9b09c")
const TAB_INK := Color("3a3a3a")
const RED := Color("c62828")
const INK := Color("1b1b1b")
const RING := Color("222222")
## The body's text sizes (px at the canvas).
const BODY_PX := 15
const SMALL_PX := 12
const TITLE_PX := 19

var sections: Array = []
var rtl := false
## The section and the page shown.
var tab := 0
var page := 0
var _pages: Array = []  # per section: [[first block, end block], ...]
var _body: RichTextLabel
var _measure: RichTextLabel
var _title: Label
var _count: Label
var _fonts := {}


func _init() -> void:
	name = "Notebook"
	size = Vector2(W, H)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_PASS  # the right drag (looking about) passes on; clicks and the wheel taken
	_title = Label.new()
	_title.add_theme_color_override("font_color", INK)
	_title.add_theme_font_size_override("font_size", TITLE_PX)
	_title.clip_text = true
	_body = _rich()
	_measure = _rich()
	_measure.visible = false
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_color_override("font_color", Color(INK, 0.75))
	_count.add_theme_font_size_override("font_size", 14)
	for c in [_title, _body, _measure, _count]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.clip_contents = true
	r.add_theme_color_override("default_color", INK)
	r.add_theme_font_size_override("normal_font_size", BODY_PX)
	r.add_theme_font_size_override("bold_font_size", BODY_PX)
	r.add_theme_font_size_override("italics_font_size", BODY_PX)
	r.add_theme_constant_override("line_separation", 1)
	r.add_theme_constant_override("table_h_separation", 6)
	return r


## Lays out `secs` (in Hebrew with `right_to_left`), keeping the section shown when its id is still there.
func set_sections(secs: Array, right_to_left: bool) -> void:
	var was: String = String(sections[tab].id) if tab < sections.size() else ""
	var lang_changed := right_to_left != rtl or _fonts.is_empty()
	sections = secs
	rtl = right_to_left
	if lang_changed:
		_set_fonts()
	var paper := paper_rect()
	_title.position = Vector2(paper.position.x + PAD, paper.position.y + TITLE_Y)
	_title.size = Vector2(paper.size.x - 2 * PAD, TITLE_PX + 8)
	for r in [_body, _measure]:
		r.position = Vector2(paper.position.x + PAD, paper.position.y + BODY_Y)
		r.size = Vector2(paper.size.x - 2 * PAD, body_height())
		r.text_direction = Control.TEXT_DIRECTION_RTL if rtl else Control.TEXT_DIRECTION_LTR
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
	_title.text_direction = _body.text_direction
	_count.position = Vector2(paper.position.x, paper.end.y - FOOT_H + 4)
	_count.size = Vector2(paper.size.x, FOOT_H - 8)
	_pages = sections.map(_paginate)
	var keep := -1
	for i in sections.size():
		if String(sections[i].id) == was:
			keep = i
	if keep < 0:
		tab = 0
		page = 0
	else:
		tab = keep
		page = mini(page, _pages[tab].size() - 1)
	_show()


## The tab of section `id` opened at its first page (or the page holding block `block`).
func open(id: String, block := 0) -> void:
	for i in sections.size():
		if String(sections[i].id) == id:
			tab = i
			page = 0
			for p in _pages[i].size():
				if block >= int(_pages[i][p][0]) and block < int(_pages[i][p][1]):
					page = p
			_show()


## The next page (way 1) or the previous one (-1); past a section's end the next section's first page (its last,
## going back); no turn past the notebook's ends.
func turn(way: int) -> void:
	if sections.is_empty():
		return
	var p := page + way
	var t := tab
	if p >= _pages[t].size():
		if t + 1 >= sections.size():
			return
		t += 1
		p = 0
	elif p < 0:
		if t == 0:
			return
		t -= 1
		p = _pages[t].size() - 1
	tab = t
	page = p
	_show()


func page_count() -> int:
	return _pages[tab].size() if tab < _pages.size() else 0


func current_id() -> String:
	return String(sections[tab].id) if tab < sections.size() else ""


## The page's text as shown (tests).
func page_text() -> String:
	return _body.get_parsed_text()


func paper_rect() -> Rect2:
	var x := TAB_W + 2.0 if rtl else INSET.x
	return Rect2(x, INSET.y, W - INSET.x - TAB_W - 2.0, H - INSET.y - 12.0)


func body_height() -> float:
	return paper_rect().size.y - BODY_Y - FOOT_H


## Tab `i`'s rect (the one open stands out over the paper's edge).
func tab_rect(i: int) -> Rect2:
	var on := i == tab
	var w := TAB_W + (8.0 if on else 0.0)
	var x := W - TAB_W - 2.0 - (8.0 if on else 0.0)
	if rtl:
		x = W - x - w
	return Rect2(x, TAB_TOP + i * (TAB_H + TAB_GAP), w, TAB_H)


## The footer's ‹ and › (previous, next) hit rects, in reading order's sides.
func arrow_rects() -> Array:
	var paper := paper_rect()
	var c := paper.get_center().x
	var y := paper.end.y - FOOT_H
	var left := Rect2(c - 92, y, 44, FOOT_H)
	var right := Rect2(c + 48, y, 44, FOOT_H)
	return [right, left] if rtl else [left, right]


func _set_fonts() -> void:
	var heebo := FontFile.new()
	heebo.load_dynamic_font(ProjectSettings.globalize_path(WizardTheme.FONT))
	var regular: Font = WizardTheme._weight(heebo, 400)
	var bold: Font = WizardTheme._weight(heebo, 700)
	if not rtl:
		# A typewriter's monospace for the paper (the mock-up's IBM Plex Mono where installed; the platform's own
		# monospace else), Heebo for any glyph it lacks.
		regular = _mono(400, [regular])
		bold = _mono(700, [bold])
	var italic := FontVariation.new()
	italic.base_font = regular
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2 if not rtl else 0.0, 1), Vector2.ZERO)
	_fonts = {"normal": regular, "bold": bold, "italics": italic}
	for r in [_body, _measure]:
		r.add_theme_font_override("normal_font", regular)
		r.add_theme_font_override("bold_font", bold)
		r.add_theme_font_override("italics_font", italic)
	_title.add_theme_font_override("font", bold)
	_count.add_theme_font_override("font", regular)


static func _mono(weight: int, fallbacks: Array) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(
		["IBM Plex Mono", "BlexMono Nerd Font Mono", "Menlo", "DejaVu Sans Mono", "Consolas", "monospace"]
	)
	f.font_weight = weight
	f.fallbacks = fallbacks
	return f


## Section `s` cut into pages: each block's height measured at the body's width, added up to the body's height.
func _paginate(s: Dictionary) -> Array:
	var pages := []
	var first := 0
	var y := 0.0
	var blocks: Array = s.blocks
	var sep := float(_body.get_theme_constant("paragraph_separation"))
	for i in blocks.size():
		_measure.text = String(blocks[i])
		var h := float(_measure.get_content_height()) + sep
		if i > first and y + h > body_height():
			pages.append([first, i])
			first = i
			y = 0.0
		y += h
	pages.append([first, blocks.size()])
	return pages


func _show() -> void:
	if sections.is_empty():
		return
	var s: Dictionary = sections[tab]
	var span: Array = _pages[tab][page]
	_title.text = String(s.title)
	_body.text = "\n".join(s.blocks.slice(int(span[0]), int(span[1])))
	_count.text = "%d / %d" % [page + 1, _pages[tab].size()]
	queue_redraw()
	turned.emit()


func _gui_input(event: InputEvent) -> void:
	# The wheel or a trackpad's scroll, in the player's scroll direction (Settings.wheel_steps).
	var n := Settings.wheel_steps(event)
	for i in absi(n):
		turn(signi(n))
	if n != 0 or event is InputEventPanGesture:
		accept_event()  # a pan's fraction of a page too: it does not zoom the view behind the notebook
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)
		accept_event()


func _click(at: Vector2) -> void:
	for i in sections.size():
		if tab_rect(i).has_point(at):
			tab = i
			page = 0
			_show()
			return
	var a := arrow_rects()
	if a[0].has_point(at):
		turn(-1)
	elif a[1].has_point(at):
		turn(1)


func _draw() -> void:
	var board := StyleBoxFlat.new()
	board.bg_color = BOARD
	board.set_corner_radius_all(12)
	board.shadow_color = Color(0, 0, 0, 0.45)
	board.shadow_size = 10
	board.shadow_offset = Vector2(0, 6)
	draw_style_box(board, Rect2(Vector2.ZERO, size))
	for i in sections.size():  # the closed tabs under the paper, the open one over it
		if i != tab:
			_draw_tab(i)
	var paper := paper_rect()
	for k in 2:
		draw_rect(Rect2(paper.position + Vector2(2, 2) * (k + 1), paper.size), PAPER_EDGE[1 - k])
	draw_rect(paper, PAPER)
	if tab < sections.size() and bool(sections[tab].get("red", false)):
		var strip := Rect2(paper.end.x - 10 if rtl else paper.position.x, paper.position.y, 10, paper.size.y)
		draw_rect(strip, RED)
	_draw_tab(tab)
	# The binding: a row of rings along the paper's top.
	var x := paper.position.x + 18.0
	while x < paper.end.x - 12.0:
		draw_circle(Vector2(x, paper.position.y + 9.0), 4.0, RING)
		x += 26.0
	# The page's ‹ › (dimmed at the notebook's ends).
	var a := arrow_rects()
	var f: Font = _fonts.get("bold", get_theme_default_font())
	var first := tab == 0 and page == 0
	var last := tab == sections.size() - 1 and page == page_count() - 1
	for k in 2:
		var glyph: String = ["‹", "›"][k] if not rtl else ["›", "‹"][k]
		var on := not (first if k == 0 else last)
		var r: Rect2 = a[k]
		draw_string(
			f,
			Vector2(r.position.x, r.end.y - 9),
			glyph,
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x,
			24,
			Color(INK, 0.8 if on else 0.2)
		)


func _draw_tab(i: int) -> void:
	var r := tab_rect(i)
	var s: Dictionary = sections[i]
	var red := bool(s.get("red", false))
	var box := StyleBoxFlat.new()
	box.bg_color = RED if red else (PAPER if i == tab else TAB)
	box.border_color = Color("8e1c1c") if red else TAB_LINE
	box.set_border_width_all(1)
	if rtl:
		box.corner_radius_top_left = 6
		box.corner_radius_bottom_left = 6
	else:
		box.corner_radius_top_right = 6
		box.corner_radius_bottom_right = 6
	draw_style_box(box, r)
	var ink := Color.WHITE if red else (Color.BLACK if i == tab else TAB_INK)
	var f: Font = _fonts.get("bold", get_theme_default_font())
	var px := 11 if not rtl else 13
	var text := String(s.tab)
	while px > 8 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > r.size.y - 8.0:
		px -= 1  # a long tab (Hebrew's "הסעה / המראה") smaller to fit
	var outer := r.position.x + (r.size.x - TAB_W if not rtl else 0.0) + TAB_W / 2.0  # the strip's middle
	var half := (f.get_ascent(px) - f.get_descent(px)) / 2.0
	# Down the tab: English top to bottom (glyphs' tops outward), Hebrew bottom to top (as a book's spine).
	if rtl:
		draw_set_transform(Vector2(outer + half, r.end.y), -PI / 2.0)
	else:
		draw_set_transform(Vector2(outer - half, r.position.y), PI / 2.0)
	draw_string(f, Vector2(0, 0), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.y, px, ink)
	draw_set_transform(Vector2.ZERO)
