# The setup wizard's look, all in one place (modern-iaf/docs/setup.md "Look"): Godot's default dark theme with the
# Heebo font and a few type variations the pages use by name. A new look (the user's round 3) replaces only this
# file: the pages ask for "Heading", "Muted", "Note", "Readout", "Card", "Primary", never a colour or a size.
extends RefCounted

const FONT := "res://data/fonts/Heebo-VariableFont_wght.ttf"
## Text sizes at a UI scale of 1 (the window's content scale grows them on a large screen).
const BASE_SIZE := 16


## The theme: Godot's default with Heebo, and the variations.
static func make() -> Theme:
	var heebo := FontFile.new()
	heebo.load_dynamic_font(ProjectSettings.globalize_path(FONT))
	var t := Theme.new()
	t.default_font = _weight(heebo, 400)
	t.default_font_size = BASE_SIZE
	var dim := ThemeDB.get_default_theme().get_color("font_color", "Label")
	dim.a = 0.7
	_variation(t, "Heading", "Label", {"font": _weight(heebo, 600), "font_size": BASE_SIZE + 6})
	_variation(t, "Title", "Label", {"font": _weight(heebo, 700), "font_size": BASE_SIZE + 10})
	_variation(t, "Muted", "Label", {"font_color": dim})
	_variation(t, "Note", "Label", {"font_color": dim, "font_size": BASE_SIZE - 2})
	_variation(t, "Readout", "Label", {"font": _weight(heebo, 600), "font_size": BASE_SIZE + 6})
	t.set_type_variation("Card", "PanelContainer")
	var card: StyleBox = ThemeDB.get_default_theme().get_stylebox("panel", "Panel").duplicate()
	card.set_content_margin_all(10)
	t.set_stylebox("panel", "Card", card)
	# The page's main action (Done's Start the game): a button filled with the default theme's brightest text colour
	# (white), dark bold text.
	var d := ThemeDB.get_default_theme()
	var accent := d.get_color("font_pressed_color", "Button")
	t.set_type_variation("Primary", "Button")
	var fills := {"normal": accent, "hover": accent.lightened(0.15), "pressed": accent.darkened(0.15)}
	for state in fills:
		var b: StyleBox = d.get_stylebox(state, "Button").duplicate()
		if b is StyleBoxFlat:
			b.bg_color = fills[state]
		t.set_stylebox(state, "Primary", b)
	var ink := Color(0.1, 0.12, 0.15)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Primary", ink)
	t.set_font("font", "Primary", _weight(heebo, 600))
	return t


static func _weight(base: Font, w: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	# By the axis' tag number: a "wght" string key leaves the variable font at its default weight.
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return f


static func _variation(t: Theme, name: String, base: String, items: Dictionary) -> void:
	t.set_type_variation(name, base)
	for k in items:
		var v: Variant = items[k]
		if v is Font:
			t.set_font(k, name, v)
		elif v is Color:
			t.set_color(k, name, v)
		else:
			t.set_font_size(k, name, v)
