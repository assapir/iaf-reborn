# The setup wizard's look, all in one place (iaf-2026/docs/setup.md "Look"): Godot's default dark theme with the
# Heebo font and a few type variations the pages use by name. A new look (the user's round 3) replaces only this
# file: the pages ask for "Heading", "Muted", "Note", "Readout", "Code", "Card", never a colour or a size.
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
	# Commands and paths: a monospace system font (Heebo draws "--" as dashes).
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace", "Menlo", "Consolas"])
	_variation(t, "Code", "Label", {"font": mono, "font_size": BASE_SIZE - 1})
	t.set_type_variation("Card", "PanelContainer")
	var card: StyleBox = ThemeDB.get_default_theme().get_stylebox("panel", "Panel").duplicate()
	card.set_content_margin_all(10)
	t.set_stylebox("panel", "Card", card)
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
