# Modern IAF's text over the flight (modern-iaf/docs/front-end.md §8), in the front end's look (menu/look.gd, Heebo),
# mirrored in Hebrew, on the front end's 1080-high canvas scaled to the window:
# - the radio lines and the training messages: a strip centred at the top, the newest at the bottom, each for
#   LINE_S seconds (terrain_view.gd _on_subtitle hands them to the flight add-on instead of the original's console);
# - a panel at the inline-start top for the radio menu and the training result (flight/sim_flight.gd);
# - one key hint line at the bottom: Esc's pause menu, shown for HINT_START_S once the loading screen is gone,
#   HINT_AGAIN_S after a language change, then faded out; hidden while the pilot's notebook is raised.
# All of it follows the game's language, also when the pause menu's Preferences switch it mid-flight: the radio lines
# already shown or still waiting for their voice too (radio.gd `subtitles`).
extends Control

## The game's language changed over the flight (Esc → Preferences).
signal language_changed

const Look := preload("../menu/look.gd")
const CANVAS_H := 1080.0
## A subtitle shows this long (s, real time) and at most BAND_LINES at once.
const LINE_S := 8.0
const BAND_LINES := 3
## A line's text size at the 1080-high canvas: a film subtitle's, the front end's body text less one (the Mac play
## test, 2026-11-11: the 26 px lines were too big).
const SUBTITLE_PX := 20
## The key hint shows this long (s, real time) at the start, again after a language change, and fades out over
## HINT_FADE_S.
const HINT_START_S := 8.0
const HINT_AGAIN_S := 4.0
const HINT_FADE_S := 0.5

var host: Node
var strings := {}
var panel: PanelContainer
var panel_label: Label
var _band: VBoxContainer
var _lines: Array = []  # [Label, shown at (ms)]
var _lang := ""
var _hint_until := 0  # ms


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
	_hint_until = Time.get_ticks_msec() + int(HINT_START_S * 1000.0)


## The strings, the key hint and the mirroring in the game's language; again when the pause menu's Preferences
## switch it (_process), then `language_changed` for the add-on's own text.
func _apply_language() -> void:
	_lang = Settings.language
	strings = Settings.load_json("res://menu/strings_%s.json" % ("he" if he() else "en"))
	var old := get_node_or_null("Hint")
	if old != null:
		remove_child(old)
		old.queue_free()
	_hint()
	var dir := Control.LAYOUT_DIRECTION_RTL if he() else Control.LAYOUT_DIRECTION_LTR
	# The panel's text, not the panel: an RTL control mirrors its own anchors, which put the top-right panel back at
	# the left (the Mac's Hebrew radio menu and "To complete", 2026-11-13). The band and the hint are centred.
	for c in [_band, panel_label, get_node("Hint")]:  # not the add-on's own (an RTL child here mirrors its anchors)
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
	show_hint(HINT_AGAIN_S)
	language_changed.emit()


## A radio line in the game's language (radio.gd `subtitles`: the line in both), else `text` as given.
func _in_language(text: String) -> String:
	var pair = host.radio.subtitles.get(text) if host.get("radio") != null else null
	return String(pair[1 if he() else 0]) if pair != null else text


## The front end's canvas, scaled to the window's height (the original's sizes stay the flight's).
func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := vp.y / CANVAS_H
	scale = Vector2(k, k)
	position = Vector2.ZERO
	size = vp / k


# --- the hint line ----------------------------------------------------------------------------------------------------


## Shows the key hint for `secs` more (real time) unless it already shows longer.
func show_hint(secs: float) -> void:
	_hint_until = maxi(_hint_until, Time.get_ticks_msec() + int(secs * 1000.0))


## The hint: shown until _hint_until, fading over the last HINT_FADE_S; hidden while the
## pilot's notebook (kneeboard.gd, "Checklist") is raised.
func _update_hint(now: int) -> void:
	var pill := get_node_or_null("Hint") as Control
	if pill == null:
		return
	if host.waiting_for_ground:  # the start's 8 s count from the loading screen's end
		_hint_until = now + int(HINT_START_S * 1000.0)
	var a := clampf((_hint_until - now) / (HINT_FADE_S * 1000.0), 0.0, 1.0)
	var side := get_node_or_null("Checklist") as Control
	if side != null and side.visible:
		a = 0.0
	pill.modulate.a = a
	pill.visible = a > 0.0


func _hint() -> void:
	var pill := PanelContainer.new()
	pill.name = "Hint"
	pill.add_theme_stylebox_override("panel", Look.box(Color(Look.BG, 0.75), Color(0, 0, 0, 0), 0, 8, Vector2(20, 6)))
	add_child(pill)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_bottom = -24
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 40)
	pill.add_child(bar)
	_key_row(bar, "Esc", s("pause_menu"), "Muted")


## One key: its cap (as the front end's footer) and what it does.
func _key_row(parent: Control, key: String, what: String, kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	# 18 px from the cap to the text: at 12 the Hebrew "תפריט השהיה" read as touching the Esc cap on the Mac
	# (2026-11-13; measured: no glyph overhangs, the ink gap was the full 12 px, but ת has no side bearing).
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var cap := PanelContainer.new()
	var kb := Look.box(Color(Look.BG, 0.7), Look.DIM, 1, 5, Vector2(9, 1))
	kb.border_width_bottom = 3
	cap.add_theme_stylebox_override("panel", kb)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	var l := Label.new()
	l.text = key
	l.theme_type_variation = "Key"
	l.text_direction = Control.TEXT_DIRECTION_LTR
	cap.add_child(l)
	var t := Label.new()
	t.text = what
	t.theme_type_variation = kind
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("shadow_offset_x", 1)
	t.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(t)
	return row


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
	_update_hint(now)


# --- the panel (radio menu, training result) --------------------------------------------------------------------------


func show_panel(text: String) -> void:
	panel_label.text = text
	panel.visible = text != ""
	panel.reset_size()
