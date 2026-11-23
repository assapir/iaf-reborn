# The briefing's PRE targets panel (A61, the user's pick 19 Nov 2026; modern-iaf/docs/front-end.md §10.2): the map's
# "PRE targets" chip puts it in the text card's place. It lists the jet's GPS stations (a rack opens into its bombs);
# a click on a row, then on a mission target, a steerpoint or any point of the map, makes that row's PRE target; a
# right click (or Delete) clears it. The rows and clicks are the shared PRE pick's (shared/weapons/pre_pick.gd, as
# the 1998 game's briefing TSD); the picks live in the pilot's loadout (its `pre`) and the one rule that checks them
# is in Rust (IafBriefing.pre / pre_set, gps::pick_ok). The map shows each target with the stations aimed at it.
extends "res://shared/weapons/pre_pick.gd"

const Look := preload("look.gd")
## The key record of "GPS bomb next PRE target" (keys.json, Shift + K).
const STEP_KEY := 207

var fe: Control
var m: Dictionary
var map: Control
## The panel (in the text card's place) and its rows' list, the refusal's line.
var card: PanelContainer
var list: VBoxContainer
var notice: Label
var footer: Label
## IafBriefing.pre's answer: {rows, aims, default}.
var data := {}


func _init(front: Control, mission: Dictionary, briefing_map: Control) -> void:
	fe = front
	m = mission
	map = briefing_map
	_load()


## The jet carries a GPS store: the chip shows.
func has_rows() -> bool:
	return not data.get("rows", []).is_empty()


func _weapons() -> String:
	return Settings.disk_path("res://data/db/weapons")


## The loadout the mission flies as JSON text: the pilot's for the jet, else the mission's own.
func _lo() -> String:
	var lo: String = fe._arm_now(m)
	return lo if lo != "" else fe.Fly.own_loadout(m)


func _load() -> void:
	var d = JSON.parse_string(IafBriefing.pre(fe._unit_file(m), _weapons(), _lo(), fe.mission_file(m)))
	data = d if d is Dictionary else {}


## The panel at the inline end under the chips (the text card's place), hidden until the chip shows it.
func build(top: int, width: int, edge: int) -> PanelContainer:
	card = PanelContainer.new()
	card.name = "PreTargets"
	card.set_meta("pre", self)  # keeps this panel alive with its card
	card.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.96), Look.LINE, 1, 6, Vector2(28, 24)))
	fe.add_child(card)
	fe._place(card, -1, edge, top, 0)
	card.offset_left = card.offset_right - width
	card.anchor_bottom = 1.0
	card.offset_bottom = -40
	card.visible = false
	var v: VBoxContainer = fe._vbox(card, 12)
	var h: Label = fe._label(v, fe.s("pre_title").to_upper(), "H3")
	h.add_theme_font_size_override("font_size", 19)
	h.add_theme_color_override("font_color", Look.ACCENT_TEXT)
	fe._text(v, fe.s("pre_hint"), "Small").add_theme_font_size_override("font_size", 21)
	notice = fe._label(v, "", "Small")
	notice.name = "PreNotice"
	notice.add_theme_color_override("font_color", Look.WARN)
	notice.visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	list = fe._vbox(scroll, 8)
	list.name = "PreRows"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fe._rule(v, Look.LINE)
	footer = fe._text(v, "", "Small")
	footer.name = "PreFooter"
	footer.add_theme_font_size_override("font_size", 21)
	refresh()
	return card


## Shows or hides the panel: the map takes its clicks and its marks while it shows.
func set_shown(on: bool) -> void:
	card.visible = on
	map.pre_click = _map_click if on else Callable()
	if not on:
		armed = -1
	refresh()
	# The targets in view while the panel shows (the range's lie tens of km from the base); the base's view again off.
	# The places aimed at, else every target.
	var shown: Array = map.pre_marks.filter(func(mk): return mk.tags != "")
	shown = shown if not shown.is_empty() else map.pre_marks
	if on and not shown.is_empty():
		var box := Rect2(shown[0].at, Vector2.ZERO)
		for mk in shown:
			box = box.expand(mk.at)
		map.frame_box(box, 400.0)
	elif not on:
		map.open_view()


## The rows, the footer and the map's marks again from the picks.
func refresh() -> void:
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	var rows: Array = data.get("rows", [])
	var stations := []
	for r in rows:
		if int(r.bomb) < 0:
			stations.append([int(r.station), int(r.count)])
	var own := func(st: int, _n: int) -> bool:
		return rows.any(func(r): return int(r.station) == st and int(r.bomb) >= 0 and r.aim != null)
	for k in row_keys(stations, own):
		_row(_find(k[0], k[1]))
	var d = data.get("default")
	var step: String = fe._ltr(fe.key_name(STEP_KEY))
	footer.text = (fe.s("pre_footer") % [aim_text(d), step] if d is Dictionary else fe.s("pre_footer_none") % step)
	map.pre_marks = marks() if card.visible else []
	map.mouse_default_cursor_shape = Control.CURSOR_CROSS if armed >= 0 and card.visible else Control.CURSOR_ARROW


func _find(st: int, b: int) -> Dictionary:
	for r in data.get("rows", []):
		if int(r.station) == st and int(r.bomb) == b:
			return r
	return {}


## Station row `r`'s aim, or its default (null: none); a bomb's own, else its station's.
func effective(r: Dictionary) -> Variant:
	if r.aim != null:
		return r.aim
	if int(r.bomb) >= 0:
		return effective(_find(int(r.station), -1))
	return data.get("default")


## An aim's words: "Target 2", "Steerpoint 1", "Point 31.04° N 34.61° E".
func aim_text(a: Dictionary) -> String:
	match String(a.kind):
		"target":
			return fe.s("pre_target") % int(a.n)
		"steer":
			return fe.s("pre_steer") % int(a.n)
	return fe.s("pre_point") % (fe.s("pre_latlon") % [float(a.lat), float(a.lon)])


## Row `r`'s name: "STA 4" (a rack with ▾ open, ▸ / ◂ closed), "4-2".
func row_name(r: Dictionary) -> String:
	var st := str(r.label)
	if int(r.bomb) >= 0:
		return "%s-%d" % [st, int(r.bomb) + 1]
	var rack := ""
	if int(r.count) > 1:
		rack = "▾ " if opened.has(int(r.station)) or _bomb_own(int(r.station)) else ("◂ " if fe.he() else "▸ ")
	return rack + fe.s("pre_sta") % st


func _bomb_own(st: int) -> bool:
	return data.get("rows", []).any(func(r): return int(r.station) == st and int(r.bomb) >= 0 and r.aim != null)


## Row `r`'s target text and colour: its pick (amber), the station's or the default (muted), the armed row's prompt.
func row_target(r: Dictionary) -> Array:
	if int(r.station) == armed and int(r.bomb) == armed_bomb:
		return [fe.s("pre_click_map"), Look.ACCENT_TEXT]
	if r.aim != null:
		return [aim_text(r.aim), Look.AMBER]
	var e = effective(r)
	if e == null:
		return [fe.s("pre_none"), Look.MUTED]
	return [fe.s("pre_as_station" if int(r.bomb) >= 0 else "pre_default") % aim_text(e), Look.MUTED]


func _row(r: Dictionary) -> void:
	var st := int(r.station)
	var b := int(r.bomb)
	var line: HBoxContainer = fe._hbox(list, 0)
	if b >= 0:
		var indent := Control.new()
		indent.custom_minimum_size.x = 28
		line.add_child(indent)
	var btn := Button.new()
	btn.name = "PreRow_%d" % st if b < 0 else "PreRow_%d_%d" % [st, b + 1]
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 62 if b < 0 else 52
	var on := st == armed and b == armed_bomb
	var pad := Vector2(20, 6)
	btn.add_theme_stylebox_override(
		"normal", Look.box(Look.RAISED, Look.ACCENT if on else Look.LINE, 2 if on else 1, 5, pad)
	)
	btn.add_theme_stylebox_override(
		"hover", Look.box(Look.DIM, Look.ACCENT if on else Look.EDGE, 2 if on else 1, 5, pad)
	)
	btn.add_theme_stylebox_override("pressed", Look.box(Look.RAISED, Look.ACCENT, 2, 5, pad))
	btn.add_theme_stylebox_override("focus", Look.box(Color(0, 0, 0, 0), Look.ACCENT_TEXT, 2, 5, pad))
	line.add_child(btn)
	var h: HBoxContainer = fe._hbox(btn, 14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 20
	h.offset_right = -20
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl: Label = fe._label(h, row_name(r), "Strong")
	nl.custom_minimum_size.x = 120 if b < 0 else 0
	if b < 0:
		var w: String = fe.s("store_" + str(r.weapon)) + (" × %d" % int(r.count) if int(r.count) > 1 else "")
		fe._label(h, w, "Small").add_theme_font_size_override("font_size", 21)
	var t := row_target(r)
	var tl: Label = fe._label(h, t[0], "Small")
	tl.name = "Target"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if not fe.he() else HORIZONTAL_ALIGNMENT_LEFT
	tl.add_theme_font_size_override("font_size", 21)
	tl.add_theme_color_override("font_color", t[1])
	for l in h.get_children():
		if l is Label:
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.pressed.connect(func(): click(st, b, MOUSE_BUTTON_LEFT))
	btn.gui_input.connect(
		func(e: InputEvent):
			var right: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT
			if right or (e is InputEventKey and e.pressed and e.keycode in [KEY_DELETE, KEY_BACKSPACE]):
				click(st, b, MOUSE_BUTTON_RIGHT)
				btn.accept_event()
	)


## A click on row (station `st`, bomb `b`) with `button`: arms it (left) or clears it (right).
func click(st: int, b: int, button: int) -> void:
	notice.visible = false
	if press(st, b, button):
		set_aim(st, b, "")
	else:
		refresh.call_deferred()


## A click on the map at `px` while a row is armed: the mission target or steerpoint under it (within 24 px), else that
## point, becomes the row's target; false with no row armed.
func _map_click(px: Vector2) -> bool:
	var k := take()
	if k.is_empty():
		return false
	var aim := {}
	var best := 24.0
	for a in data.get("aims", []):
		if not a is Dictionary:
			continue
		var d: float = map.to_px(_map_at(a)).distance_to(px)
		if d < best:
			best = d
			aim = {String(a.kind): int(a.n)}
	if aim.is_empty():
		var at: Vector2 = map.to_map(px)
		var e: Array = map.data.get("extent", [0, 0, 0, 0])
		aim = {"x": float(e[0]) + at.x, "y": float(e[3]) - at.y}
	set_aim(k[0], k[1], JSON.stringify(aim))
	return true


## An aim's place in the map's metres (from its north-west corner, y south).
func _map_at(a: Dictionary) -> Vector2:
	var e: Array = map.data.get("extent", [0, 0, 0, 0])
	return Vector2(float(a.x) - float(e[0]), float(e[3]) - float(a.y))


## Sets the PRE target of station `st` (bomb `b` >= 0: that bomb's own) to `aim` (JSON text, "" clears it) through the
## one rule (IafBriefing.pre_set) and keeps it with the pilot's loadout; a refused pick says so in one line.
func set_aim(st: int, b: int, aim: String) -> void:
	var lo: String = IafBriefing.pre_set(fe._unit_file(m), _weapons(), _lo(), fe.mission_file(m), st, b, aim)
	if lo == "":
		notice.text = fe.s("pre_refused")
		notice.visible = true
	else:
		IafPilotLog.set_loadout(Settings.records_db(), Settings.pilot(), str(fe.jet_of(m).get("unit", "")), lo)
		_load()
	refresh.call_deferred()


## The map's marks (briefing_map.gd pre_marks): every mission target with its name, and each place a station or a
## bomb aims at with their names (a rack whose bombs have picks of their own by bomb, else by station).
func marks() -> Array:
	var out := {}
	var add := func(a: Dictionary, name: String, tag: String) -> void:
		var key := Vector2i((Vector2(float(a.x), float(a.y)) / 5.0).round())
		if not out.has(key):
			out[key] = {"at": _map_at(a), "name": name, "tags": "", "kind": String(a.kind)}
		if out[key].name == "":
			out[key].name = name
		if tag != "":
			out[key].tags = (out[key].tags + " " + tag).strip_edges()
	for a in data.get("aims", []):
		if a is Dictionary and a.kind == "target":
			add.call(a, aim_text(a), "")
	for r in data.get("rows", []):
		var per_bomb: bool = int(r.count) > 1 and _bomb_own(int(r.station))
		if (int(r.bomb) >= 0) != per_bomb:
			continue
		var e = effective(r)
		if e is Dictionary:
			var tag := str(r.label) if int(r.bomb) < 0 else "%s-%d" % [str(r.label), int(r.bomb) + 1]
			add.call(e, aim_text(e) if e.kind != "steer" else "", tag)
	return out.values()
