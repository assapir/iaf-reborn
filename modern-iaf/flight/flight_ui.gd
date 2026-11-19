# Modern IAF's text over the flight (modern-iaf/docs/front-end.md §8), in the front end's look (menu/look.gd, Heebo),
# mirrored in Hebrew, on the front end's 1080-high canvas scaled to the window:
# - the radio lines and the training messages: a strip centred at the top, the newest at the bottom, each for
#   LINE_S seconds (terrain_view.gd _on_subtitle hands them to the flight add-on instead of the original's console);
# - a panel at the inline-start top for the radio menu and the training result (flight/sim_flight.gd);
# No key hint over the flight (the user, 13 Nov: "lets remove the kb hints"; 15 Nov: "remove it completely"): the keys
# are listed in the pilot's notebook (H) and the Keys screen.
# All of it follows the game's language, also when the pause menu's Preferences switch it mid-flight: the radio lines
# already shown or still waiting for their voice too (radio.gd `subtitles`).
extends Control

## The game's language changed over the flight (Esc → Preferences).
signal language_changed

const Look := preload("../menu/look.gd")
## A subtitle shows this long (s, real time) and at most BAND_LINES at once.
const LINE_S := 8.0
const BAND_LINES := 3
## A line's text size at the 1080-high canvas: a film subtitle's, the front end's body text less one (the Mac play
## test, 2026-11-11: the 26 px lines were too big).
const SUBTITLE_PX := 20

var host: Node
var strings := {}
var panel: PanelContainer
var panel_label: Label
var _band: VBoxContainer
var _lines: Array = []  # [Label, shown at (ms)]
var _lang := ""


func _init(h: Node) -> void:
	host = h
	name = "FlightUi"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func he() -> bool:
	return Settings.language == "he"


func s(key: String) -> String:
	return str(strings.get(key, key))


func _ready() -> void:
	theme = Look.make()
	_fit()
	get_viewport().size_changed.connect(_fit)
	# The band: a strip centred at the top, over the sky rather than the cockpit's panel.
	_band = VBoxContainer.new()
	_band.name = "Band"
	_band.add_theme_constant_override("separation", 6)
	add_child(_band)
	_band.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_band.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_band.offset_top = 40
	# The panel: the inline-start top (the right in Hebrew).
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", Look.box(Color(Look.BG, 0.88), Look.LINE, 1, 8, Vector2(28, 20)))
	add_child(panel)
	panel_label = Label.new()
	panel_label.add_theme_font_size_override("font_size", 24)
	panel.add_child(panel_label)
	panel.visible = false
	_apply_language()


## The strings and the mirroring in the game's language; again when the pause menu's Preferences
## switch it (_process), then `language_changed` for the add-on's own text.
func _apply_language() -> void:
	_lang = Settings.language
	strings = Settings.strings("res://menu/strings")
	var dir := Control.LAYOUT_DIRECTION_RTL if he() else Control.LAYOUT_DIRECTION_LTR
	# The panel's text, not the panel: an RTL control mirrors its own anchors, which put the top-right panel back at
	# the left (the Mac's Hebrew radio menu and "To complete", 2026-11-13). The band is centred.
	for c in [_band, panel_label]:  # not the add-on's own (an RTL child here mirrors its anchors)
		c.layout_direction = dir
	# The panel by its anchors: the right edge in Hebrew.
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if he() else Control.PRESET_TOP_LEFT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if he() else Control.GROW_DIRECTION_END
	if he():
		panel.offset_right = -48
	else:
		panel.offset_left = 48
	panel.offset_top = 40
	for x in _lines:  # the lines already shown, in the new language
		var l: Label = x[0].get_child(0)
		l.text = _in_language(l.text)
	language_changed.emit()


## A radio line in the game's language (radio.gd `subtitles`: the line in both), a message with a Hebrew string
## ("msg:" + its English text in menu/strings_he.json), else `text` as given.
func _in_language(text: String) -> String:
	var pair = host.radio.subtitles.get(text) if host.get("radio") != null else null
	if pair != null:
		return String(pair[1 if he() else 0])
	return s("msg:" + text) if he() and strings.has("msg:" + text) else text


## The front end's canvas, scaled to the window's height (the original's sizes stay the flight's).
func _fit() -> void:
	Look.fit(self, get_viewport_rect().size)
	position = Vector2.ZERO


# --- the band ---------------------------------------------------------------------------------------------------------


## A radio line or a message, at the bottom of the band.
func subtitle(text: String) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Look.box(Color(Look.BG, 0.75), Color(0, 0, 0, 0), 0, 5, Vector2(14, 3)))
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = _in_language(text)  # a line said before a language change shows after it
	l.theme_type_variation = "Strong"
	l.add_theme_font_size_override("font_size", SUBTITLE_PX)
	box.add_child(l)
	_band.add_child(box)
	_lines.append([box, Time.get_ticks_msec()])
	while _lines.size() > BAND_LINES:
		_lines.pop_front()[0].queue_free()


func band_texts() -> Array:
	return _lines.map(func(x): return String(x[0].get_child(0).text))


func _process(_delta: float) -> void:
	if Settings.language != _lang:
		_apply_language()
	var now := Time.get_ticks_msec()
	while not _lines.is_empty() and now - int(_lines[0][1]) > LINE_S * 1000.0:
		_lines.pop_front()[0].queue_free()


# --- the panel (radio menu, training result) --------------------------------------------------------------------------


func show_panel(text: String) -> void:
	panel_label.text = text
	panel.visible = text != ""
	panel.reset_size()
