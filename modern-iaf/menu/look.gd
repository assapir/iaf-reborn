# The front end's look (modern-iaf/docs/front-end.md "Look"): the roundel-blue palette (the user, 2026-11-13, A25) and
# the round-3 type scale on the wizard's Heebo (setup/wizard_theme.gd). Every sim screen takes its colours from here.
# Sizes are pixels of the 1080-high canvas the front end lays out on (front_end.gd scales it to the window), so every
# length follows the screen height: R, the body text, is 1.9 % of it.
extends RefCounted

const WizardTheme := preload("../setup/wizard_theme.gd")  # relative: a test of the original's project loads it too

## The page, one step darker than the roundel's blue; the panels in the roundel's deep blue itself (Wikimedia Commons'
## Roundel_of_Israel.svg #001E50, a drawing, not an official specification; menu-ideas ideas.md round 2).
const BG := Color("00163c")
const PANEL := Color("001e50")
const LINE := Color("1d3a70")
const EDGE := Color("5a73a3")
const TEXT := Color("f2f5fa")
const MUTED := Color("a9b8d4")
## The one accent (buttons, the selection) and the text on it (the roundel blue).
const ACCENT := Color("5b8cff")
const NAVY := Color("001e50")
const ACCENT_TEXT := Color("a8c3ff")
## A raised panel (hover, the lit tab) and a field's fill (dropdowns, text fields), between PANEL and LINE.
const RAISED := Color("0a2a66")
const FIELD := Color("00194a")
## A border or ring with nothing to say (a disabled radio, the key caps).
const DIM := Color("3a5287")
## A figure over its limit (the take-off weight over the maximum).
const WARN := Color("ff6b6b")
## A figure past a warning limit (the wings' stores out of balance).
const AMBER := Color("ffb547")
## The debrief's paper, from the Sufa's light camouflage sand.
const PAPER := Color("f3efe6")
const RULE := Color("b9b09c")
const INK := Color("1d2025")
const INK_MUTED := Color("6b6455")

const R := 21
## The display types whose line is trimmed: the share of the size taken off above and below.
const TIGHT := {"Jet": 0.2, "H1": 0.1, "Name": 0.1}

## Type variations: [name, base type, weight, size, colour].
const TYPES := [
	["Mark", "Label", 800, 28, TEXT],
	["Crumb", "Label", 400, 22, MUTED],
	["CrumbLink", "Button", 400, 22, MUTED],
	["PilotLink", "Button", 600, 22, TEXT],
	["CrumbOn", "Label", 500, 22, TEXT],
	["Muted", "Label", 400, R, MUTED],
	["Small", "Label", 400, 19, MUTED],
	["Strong", "Label", 600, 22, TEXT],
	["H1", "Label", 700, 53, TEXT],
	["H2", "Label", 700, 40, TEXT],
	["H3", "Label", 600, 22, MUTED],
	["Sub", "Label", 400, 24, MUTED],
	["Jet", "Label", 800, 127, TEXT],
	["Code", "Label", 600, 27, MUTED],
	["Big", "Label", 400, 31, TEXT],
	["Name", "Label", 800, 46, TEXT],
	["Stat", "Label", 700, 41, TEXT],
	["Num", "Label", 700, 46, ACCENT],
	["Fact", "Label", 600, 27, TEXT],
	["Row", "Label", 500, 24, TEXT],
	["Paper", "Label", 400, R, INK],
	["PaperLabel", "Label", 500, 19, INK_MUTED],
	["PaperValue", "Label", 500, 23, INK],
	["PaperHead", "Label", 700, 21, INK_MUTED],
	["PaperNum", "Label", 600, R, INK],
	["Band", "Label", 600, R, Color.WHITE],
	["Stamp", "Label", 800, 29, NAVY],
	["Key", "Label", 600, R, TEXT],
	["Avatar", "Label", 700, 22, NAVY],
	["Chip", "Label", 600, 19, MUTED],
	["ChipOk", "Label", 600, 19, ACCENT_TEXT],
	["Menu", "Button", 500, 26, TEXT],
	["Primary", "Button", 600, 24, NAVY],
	["Fly", "Button", 600, 36, NAVY],
	["Secondary", "Button", 600, 24, TEXT],
	["Card", "Button", 400, R, TEXT],
	["Tab", "Button", 500, 24, TEXT],
	["JetRow", "Button", 400, R, TEXT],
	["JetName", "Label", 800, 30, TEXT],
]


static func make() -> Theme:
	var heebo := FontFile.new()
	heebo.load_dynamic_font(ProjectSettings.globalize_path(WizardTheme.FONT))
	var t := Theme.new()
	t.default_font = WizardTheme._weight(heebo, 400)
	t.default_font_size = R
	t.set_color("font_color", "Label", TEXT)
	for ty in TYPES:
		t.set_type_variation(ty[0], ty[1])
		var font := WizardTheme._weight(heebo, ty[2])
		if ty[0] in TIGHT:
			# The display sizes sit on a line of about their own height, as the mock-ups' line-height of 0.95.
			font.set_spacing(TextServer.SPACING_TOP, -int(ty[3] * TIGHT[ty[0]]))
			font.set_spacing(TextServer.SPACING_BOTTOM, -int(ty[3] * TIGHT[ty[0]]))
		t.set_font("font", ty[0], font)
		t.set_font_size("font_size", ty[0], ty[3])
		for k in [
			"font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"
		]:
			t.set_color(k, ty[0], ty[4])
	var btn := box(Color(PANEL, 0.85), EDGE, 1, 5, Vector2(36, 12))
	var on := box(Color(PANEL, 0.85), ACCENT, 3, 5, Vector2(36, 12))
	_button(t, "Secondary", btn, box(RAISED, EDGE, 1, 5, Vector2(36, 12)), on)
	var pri := box(ACCENT, ACCENT, 1, 5, Vector2(36, 12))
	_button(
		t,
		"Primary",
		pri,
		box(ACCENT.lightened(0.15), ACCENT.lightened(0.15), 1, 5, Vector2(36, 12)),
		box(ACCENT, TEXT, 3, 5, Vector2(36, 12))
	)
	_button(
		t,
		"Fly",
		pri,
		box(ACCENT.lightened(0.15), ACCENT.lightened(0.15), 1, 5, Vector2(36, 12)),
		box(ACCENT, TEXT, 3, 5, Vector2(36, 12))
	)
	for k in ["Fly", "Primary"]:
		t.set_stylebox("disabled", k, box(Color(ACCENT, 0.4), Color(ACCENT, 0.4), 1, 5, Vector2(36, 12)))
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.content_margin_top = 9
	flat.content_margin_bottom = 9
	var menu_on := flat.duplicate()
	menu_on.bg_color = Color(ACCENT, 0.16)
	_button(t, "Menu", flat, menu_on, menu_on)
	t.set_constant("align_to_largest_stylebox", "Menu", 1)
	# A list's tab (the Settings' sections, the Keys screen's groups): the picked one filled in the accent's tint, no
	# bar at its side (the user, 2026-11-13); the focus a ring.
	var tab := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, Vector2(28, 16))
	var tab_on := box(Color(ACCENT, 0.22), Color(0, 0, 0, 0), 0, 4, Vector2(28, 16))
	_button(t, "Tab", tab, box(Color(ACCENT, 0.1), Color(0, 0, 0, 0), 0, 4, Vector2(28, 16)), tab)
	t.set_stylebox("focus", "Tab", box(Color(0, 0, 0, 0), ACCENT, 2, 4, Vector2(28, 16)))
	for k in ["pressed", "hover_pressed"]:
		t.set_stylebox(k, "Tab", tab_on)
	# A breadcrumb that opens its screen: the muted text, brighter with a faint accent under the pointer or the focus.
	var crumb := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 5, Vector2(8, 4))
	var crumb_on := box(Color(ACCENT, 0.16), Color(0, 0, 0, 0), 0, 5, Vector2(8, 4))
	_button(t, "CrumbLink", crumb, crumb_on, box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(8, 4)))
	for k in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(k, "CrumbLink", TEXT)
	# The pilot on Home (the nickname, the name, the picture), which opens the Pilot screen: a crumb's look, deeper
	# while pressed.
	_button(t, "PilotLink", crumb, crumb_on, box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(8, 4)))
	t.set_stylebox("pressed", "PilotLink", box(Color(ACCENT, 0.32), Color(0, 0, 0, 0), 0, 5, Vector2(8, 4)))
	# A text field (the Pilot screen's name and nickname): the dropdown's box.
	t.set_stylebox("normal", "LineEdit", box(FIELD, EDGE, 1, 5, Vector2(18, 10)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(18, 10)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", 24)
	var card := box(PANEL, LINE, 1, 6, Vector2.ZERO)
	_button(t, "Card", card, box(RAISED, EDGE, 1, 6, Vector2.ZERO), box(PANEL, ACCENT, 4, 6, Vector2.ZERO))
	t.set_stylebox("pressed", "Card", box(PANEL, ACCENT, 4, 6, Vector2.ZERO))
	t.set_stylebox("hover_pressed", "Card", box(PANEL, ACCENT, 4, 6, Vector2.ZERO))
	# Form controls: dropdown, toggle, slider, radio list on the dark panels.
	t.set_stylebox("normal", "OptionButton", box(FIELD, EDGE, 1, 5, Vector2(22, 10)))
	t.set_stylebox("hover", "OptionButton", box(RAISED, EDGE, 1, 5, Vector2(22, 10)))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(22, 10)))
	t.set_stylebox("pressed", "OptionButton", box(RAISED, ACCENT, 1, 5, Vector2(22, 10)))
	# Right to left (Hebrew) the dropdown draws its *_mirrored boxes: the same ones, or Godot's default plain box shows.
	for k in ["normal", "hover", "pressed"]:
		t.set_stylebox(k + "_mirrored", "OptionButton", t.get_stylebox(k, "OptionButton"))
	for k in ["CheckButton", "CheckBox"]:
		t.set_stylebox("focus", k, box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(6, 4)))
	# The toggle (on: the knob at the inline end, in the accent) and the radio circles, drawn at the canvas' size.
	var knob := "<circle cx='%d' cy='20' r='15' fill='#ffffff'/>"
	var track := (
		"<svg xmlns='http://www.w3.org/2000/svg' width='80' height='40'>"
		+ "<rect width='80' height='40' rx='20' fill='%s'/>%s</svg>"
	)
	var off_l := _svg(track % [_hex(LINE), knob % 20])
	var off_r := _svg(track % [_hex(LINE), knob % 60])
	var on_r := _svg(track % [_hex(ACCENT), knob % 60])
	var on_l := _svg(track % [_hex(ACCENT), knob % 20])
	for k in ["unchecked", "unchecked_disabled"]:
		t.set_icon(k, "CheckButton", off_l)
		t.set_icon(k + "_mirrored", "CheckButton", off_r)
	for k in ["checked", "checked_disabled"]:
		t.set_icon(k, "CheckButton", on_r)
		t.set_icon(k + "_mirrored", "CheckButton", on_l)
	var ring := (
		"<svg xmlns='http://www.w3.org/2000/svg' width='30' height='30'>"
		+ "<circle cx='15' cy='15' r='12' fill='none' stroke='%s' stroke-width='2.5'/>%s</svg>"
	)
	t.set_icon("radio_unchecked", "CheckBox", _svg(ring % [_hex(MUTED), ""]))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _svg(ring % [_hex(DIM), ""]))
	t.set_icon(
		"radio_checked",
		"CheckBox",
		_svg(ring % [_hex(ACCENT), "<circle cx='15' cy='15' r='6' fill='%s'/>" % _hex(ACCENT)])
	)
	t.set_icon(
		"radio_checked_disabled",
		"CheckBox",
		_svg(ring % [_hex(DIM), "<circle cx='15' cy='15' r='6' fill='%s'/>" % _hex(DIM)])
	)
	t.set_constant("h_separation", "CheckBox", 14)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("slider", "HSlider", box(LINE, LINE, 0, 4, Vector2(0, 4)))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, ACCENT, 0, 4, Vector2(0, 4)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, ACCENT, 0, 4, Vector2(0, 4)))
	t.set_stylebox("focus", "HSlider", box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(4, 4)))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, EDGE, 1, 5, Vector2(10, 8)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_font_size("font_size", "PopupMenu", R)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.25), Color(0, 0, 0, 0), 0, 3, Vector2(8, 4)))
	t.set_stylebox("background", "ProgressBar", box(LINE, LINE, 0, 4, Vector2(0, 3)))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, ACCENT, 0, 4, Vector2(0, 3)))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 1, 6, Vector2.ZERO))
	# A list's row that picks one (the Hangar's jets): the picked one filled in the accent's tint, no bar at its side
	# (the user, 2026-11-13); the focus a ring.
	var row := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, Vector2.ZERO)
	var row_on := box(Color(ACCENT, 0.22), Color(0, 0, 0, 0), 0, 6, Vector2.ZERO)
	_button(t, "JetRow", row, box(Color(ACCENT, 0.1), Color(0, 0, 0, 0), 0, 6, Vector2.ZERO), row)
	t.set_stylebox("focus", "JetRow", box(Color(0, 0, 0, 0), ACCENT, 2, 6, Vector2.ZERO))
	for k in ["pressed", "hover_pressed"]:
		t.set_stylebox(k, "JetRow", row_on)
	t.set_stylebox("disabled", "JetRow", row)
	return t


## The Pilot screen's empty picture: a head and shoulders in a colour between the line and the edge, `w` × 4/3 `w`
## px (the 3:4 frame).
static func person_icon(w: int) -> ImageTexture:
	var p := (
		"<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 300 400' fill='%s'>"
		+ "<circle cx='150' cy='155' r='66'/><path d='M36 400C36 292 88 248 150 248S264 292 264 400Z'/></svg>"
	)
	return _svg(p % [w, w * 4 / 3, _hex(LINE.lerp(EDGE, 0.35))])


## The Settings' gear, drawn in the text colour at the canvas' size.
static func gear_icon() -> ImageTexture:
	var g := (
		"<svg xmlns='http://www.w3.org/2000/svg' width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='%s'"
		+ " stroke-width='2'><circle cx='12' cy='12' r='3.2'/><path d='M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1"
		+ " 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1'/></svg>"
	)
	return _svg(g % _hex(TEXT))


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func _svg(src: String) -> ImageTexture:
	var img := Image.new()
	img.load_svg_from_string(src, 1.0)
	return ImageTexture.create_from_image(img)


## A flat box: fill, border colour and width, corner radius, content margins (x, y).
static func box(fill: Color, edge: Color, width: int, radius: int, pad: Vector2) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = edge
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.content_margin_left = pad.x
	b.content_margin_right = pad.x
	b.content_margin_top = pad.y
	b.content_margin_bottom = pad.y
	b.anti_aliasing = radius > 0
	return b


static func _button(t: Theme, kind: String, normal: StyleBox, hover: StyleBox, focus: StyleBox) -> void:
	t.set_stylebox("normal", kind, normal)
	t.set_stylebox("hover", kind, hover)
	t.set_stylebox("pressed", kind, hover)
	t.set_stylebox("focus", kind, focus)


## "16,069" / "-1,234.5": a figure with a thousands separator, one decimal where it has a fraction (the front end's
## figures, the kneeboard's runway row).
static func group(v: float) -> String:
	var whole := v == roundf(v)
	var t := str(int(absf(v))) if whole else "%.1f" % absf(v)
	var ip := t.get_slice(".", 0)
	var out := ""
	while ip.length() > 3:
		out = "," + ip.right(3) + out
		ip = ip.left(ip.length() - 3)
	out = ip + out
	if not whole:
		out += "." + t.get_slice(".", 1)
	return ("-" if v < 0 else "") + out


## "250° / 8": the wind as pilots read it, direction and speed (its unit beside it, `kt`), from the mission's
## wind_from and wind_kt ("000° / 0" when calm).
static func wind(m: Dictionary) -> String:
	return "%03d° / %d" % [int(m.get("wind_from", 0)), int(m.get("wind_kt", 0))]


## Scales `page` so the 1080-high canvas fills the height of a viewport `vp` px large (its width follows the aspect).
static func fit(page: Control, vp: Vector2) -> void:
	var k := vp.y / 1080.0
	page.scale = Vector2(k, k)
	page.size = vp / k
