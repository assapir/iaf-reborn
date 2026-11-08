# The front end's look (iaf-2026/docs/front-end.md "Look"): the round-3 palette and type scale on the wizard's Heebo
# (setup/wizard_theme.gd). Sizes are pixels of the 1080-high canvas the front end lays out on (front_end.gd scales it
# to the window), so every length follows the screen height: R, the body text, is 1.9 % of it.
extends RefCounted

const WizardTheme := preload("res://setup/wizard_theme.gd")

const BG := Color("1d2025")
const PANEL := Color("262a31")
const LINE := Color("3b414b")
const EDGE := Color("6b737f")
const TEXT := Color("eef0f2")
const MUTED := Color("aab1bb")
## The Israeli Air Force flag's sky blue and navy (NOTES.md of round 3).
const ACCENT := Color("6699ff")
const NAVY := Color("000055")
const ACCENT_TEXT := Color("9dbdff")
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
	["Chip", "Label", 600, 19, Color("c9ced5")],
	["ChipOk", "Label", 600, 19, ACCENT_TEXT],
	["Menu", "Button", 500, 26, TEXT],
	["Primary", "Button", 600, 24, NAVY],
	["Fly", "Button", 600, 36, NAVY],
	["Secondary", "Button", 600, 24, TEXT],
	["Tab", "Button", 500, 24, TEXT],
	["Card", "Button", 400, R, TEXT],
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
	_button(t, "Secondary", btn, box(Color("323741"), EDGE, 1, 5, Vector2(36, 12)), on)
	var pri := box(ACCENT, ACCENT, 1, 5, Vector2(36, 12))
	_button(
		t,
		"Primary",
		pri,
		box(Color("80aaff"), Color("80aaff"), 1, 5, Vector2(36, 12)),
		box(ACCENT, TEXT, 3, 5, Vector2(36, 12))
	)
	_button(
		t,
		"Fly",
		pri,
		box(Color("80aaff"), Color("80aaff"), 1, 5, Vector2(36, 12)),
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
	var tab := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector2(28, 16))
	var tab_on := box(Color("262d3b"), ACCENT, 0, 0, Vector2(28, 16))
	tab_on.border_width_right = 4
	_button(t, "Tab", tab, tab_on, tab_on)
	t.set_stylebox("pressed", "Tab", tab_on)
	var card := box(PANEL, LINE, 1, 6, Vector2.ZERO)
	_button(t, "Card", card, box(Color("2c313a"), EDGE, 1, 6, Vector2.ZERO), box(PANEL, ACCENT, 4, 6, Vector2.ZERO))
	t.set_stylebox("pressed", "Card", box(PANEL, ACCENT, 4, 6, Vector2.ZERO))
	t.set_stylebox("hover_pressed", "Card", box(PANEL, ACCENT, 4, 6, Vector2.ZERO))
	# Form controls: dropdown, toggle, slider, radio list on the dark panels.
	t.set_stylebox("normal", "OptionButton", box(Color("2a2f37"), EDGE, 1, 5, Vector2(22, 10)))
	t.set_stylebox("hover", "OptionButton", box(Color("323741"), EDGE, 1, 5, Vector2(22, 10)))
	t.set_stylebox("focus", "OptionButton", box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(22, 10)))
	t.set_stylebox("pressed", "OptionButton", box(Color("323741"), ACCENT, 1, 5, Vector2(22, 10)))
	for k in ["CheckButton", "CheckBox"]:
		t.set_stylebox("focus", k, box(Color(0, 0, 0, 0), ACCENT, 2, 5, Vector2(6, 4)))
	# The toggle (on: the knob at the inline end, in the accent) and the radio circles, drawn at the canvas' size.
	var knob := "<circle cx='%d' cy='20' r='15' fill='#ffffff'/>"
	var track := (
		"<svg xmlns='http://www.w3.org/2000/svg' width='80' height='40'>"
		+ "<rect width='80' height='40' rx='20' fill='%s'/>%s</svg>"
	)
	var off_l := _svg(track % ["#3b414b", knob % 20])
	var off_r := _svg(track % ["#3b414b", knob % 60])
	var on_r := _svg(track % ["#6699ff", knob % 60])
	var on_l := _svg(track % ["#6699ff", knob % 20])
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
	t.set_icon("radio_unchecked", "CheckBox", _svg(ring % ["#aab1bb", ""]))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _svg(ring % ["#5a616c", ""]))
	t.set_icon("radio_checked", "CheckBox", _svg(ring % ["#6699ff", "<circle cx='15' cy='15' r='6' fill='#6699ff'/>"]))
	t.set_icon(
		"radio_checked_disabled", "CheckBox", _svg(ring % ["#5a616c", "<circle cx='15' cy='15' r='6' fill='#5a616c'/>"])
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
	return t


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
