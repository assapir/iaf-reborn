# Modern IAF's text over the flight (iaf-2026/docs/front-end.md §8), in the front end's look (menu/look.gd, Heebo),
# mirrored in Hebrew, on the front end's 1080-high canvas scaled to the window:
# - the mission card: the mission's title, its objective and the keys that matter, as bound (the compiled mission's
#   `sim.card`, iaf-sim missions); open at the start (the flight frozen), closed by Space, Enter, Esc or a click,
#   opened again by the Mission card key (H);
# - the radio lines and the training messages: a strip centred at the top, the newest at the bottom, each for
#   LINE_S seconds (terrain_view.gd _on_subtitle hands them to the flight add-on instead of the original's console);
# - a panel at the inline-start top for the radio menu and the training result (flight/sim_flight.gd);
# - one key hint line at the bottom: the Mission card key and Esc's pause menu.
# All of it follows the game's language, also when the pause menu's Preferences switch it mid-flight.
extends Control

## The game's language changed over the flight (Esc → Preferences).
signal language_changed

const Look := preload("../menu/look.gd")
const CANVAS_H := 1080.0
## A subtitle shows this long (s, real time) and at most BAND_LINES at once.
const LINE_S := 8.0
const BAND_LINES := 3
## The sim's key records (iaf-2026/data/keys.json): the Mission card key.
const CARD_KEY := 118

var host: Node
var strings := {}
var card: Control
var panel: PanelContainer
var panel_label: Label
var _band: VBoxContainer
var _lines: Array = []  # [Label, shown at (ms)]
var _froze := false
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
	for c in [_band, panel, get_node("Hint")]:  # not the add-on's own (an RTL child here mirrors its anchors)
		c.layout_direction = dir
	# A control under this LTR root mirrors by its own anchors: the panel to the right edge in Hebrew.
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if he() else Control.PRESET_TOP_LEFT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if he() else Control.GROW_DIRECTION_END
	if he():
		panel.offset_right = -48
	else:
		panel.offset_left = 48
	panel.offset_top = 40
	language_changed.emit()


## The front end's canvas, scaled to the window's height (the original's sizes stay the flight's).
func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := vp.y / CANVAS_H
	scale = Vector2(k, k)
	position = Vector2.ZERO
	size = vp / k


func key_name(record: int) -> String:
	var keys: RefCounted = host.keys
	if record >= keys.size():
		return ""
	return String(keys.key_name(keys.key_of(record, Settings.key_bindings)))


# --- the hint line ----------------------------------------------------------------------------------------------------


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
	for k in [[key_name(CARD_KEY), "mission_card"], ["Esc", "pause_menu"]]:
		if k[0] != "":
			_key_row(bar, k[0], s(k[1]), "Muted")


## One key: its cap (as the front end's footer) and what it does.
func _key_row(parent: Control, key: String, what: String, kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var cap := PanelContainer.new()
	var kb := Look.box(Color(Look.BG, 0.7), Color("5a616c"), 1, 5, Vector2(9, 1))
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
	box.add_theme_stylebox_override("panel", Look.box(Color(Look.BG, 0.82), Color(0, 0, 0, 0), 0, 6, Vector2(22, 8)))
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Strong"
	l.add_theme_font_size_override("font_size", 26)
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


# --- the mission card -------------------------------------------------------------------------------------------------


## Opens the card of the flight's mission (`sim`: the compiled mission's "sim"); the flight freezes until it closes.
func open_card(sim: Dictionary) -> void:
	var c: Dictionary = sim.get("card", {}) if sim.get("card") is Dictionary else {}
	if c.is_empty() or card != null:
		return
	var lang := "he" if he() else "en"
	card = CenterContainer.new()
	card.name = "Card"
	add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.layout_direction = Control.LAYOUT_DIRECTION_RTL if he() else Control.LAYOUT_DIRECTION_LTR
	var dim := ColorRect.new()
	dim.color = Color(Look.BG, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.97), Look.LINE, 1, 10, Vector2(56, 44)))
	p.custom_minimum_size.x = 980
	card.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	p.add_child(v)
	_add_label(v, s("mission_card"), "H3")
	_add_label(v, String(sim.get("title", {}).get(lang, "")), "H2")
	var obj := _add_label(v, objective(sim), "Sub")
	obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj.custom_minimum_size.x = 868
	var rule := ColorRect.new()
	rule.color = Look.LINE
	rule.custom_minimum_size.y = 1
	v.add_child(rule)
	var grid := GridContainer.new()
	grid.name = "Keys"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for r in c.get("keys", []):
		var k := key_name(int(r))
		if k != "":
			_key_row(grid, k, String(host.keys.label(int(r), he())), "Row")
	var go := _add_label(v, s("card_go") % _ltr(key_name(CARD_KEY)), "Muted")
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not get_tree().paused:
		_froze = true
		host._freeze(true, true)


func _add_label(parent: Control, t: String, kind: String) -> Label:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = kind
	parent.add_child(l)
	return l


## The objective in the game's language with its keys as bound ({key:N}) and the mission's runway ({runway}).
func objective(sim: Dictionary) -> String:
	var t := String(sim.get("card", {}).get("objective", {}).get("he" if he() else "en", ""))
	var rx := RegEx.create_from_string("\\{key:(\\d+)\\}")
	for m in rx.search_all(t):
		t = t.replace(m.get_string(), _ltr(key_name(int(m.get_string(1)))))
	var rwy = sim.get("runway")
	return t.replace("{runway}", _ltr(rwy) if rwy is String else "")


## A key name or a designator kept whole and left to right inside a Hebrew line: a left-to-right isolate, no break.
static func _ltr(t: String) -> String:
	return "\u2066%s\u2069" % t.replace(" ", "\u00a0")


func close_card() -> void:
	if card == null:
		return
	card.queue_free()
	card = null
	if _froze:
		_froze = false
		host._freeze(false, true)


func _unhandled_input(event: InputEvent) -> void:
	if card == null:
		return
	var close: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey and event.pressed and not event.echo:
		close = event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]
		close = close or host.keys.find_key(host.keys.key_of_event(event), Settings.key_bindings) == CARD_KEY
	if close:
		get_viewport().set_input_as_handled()
		close_card()
