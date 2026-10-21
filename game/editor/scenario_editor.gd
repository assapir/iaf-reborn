# The mission editor's Scenario tab (docs/mission-editor.md §14): "when X then Y" rules built from blocks.
# Drag a WHEN or THEN block onto a rule (or click it: it goes to the highlighted rule); pick units from the
# lists or click one on the map. IafMissionEdit.rules / set_rules (crates/iaf-tools/src/mission_events.rs)
# read and write them as the mission's own event data, so the game runs them as the original's events.
extends VBoxContainer

## [kind, palette label, plain-English title]
const WHENS := [
	["destroyed", "Unit destroyed", "a unit is destroyed"],
	["damaged", "Unit badly hit", "a unit is badly hit"],
	["enters", "Comes within", "a unit comes within a distance of another"],
	["leaves", "Moves away", "a unit that came within a distance moves away again"],
	["start", "Mission start", "the flight starts"],
]
const THENS := [
	["wait", "Wait", "wait some seconds before the next blocks"],
	["message", "Radio message", "play a radio message with its subtitle"],
	["route", "Start its route", "a unit starts the route given on the Units tab"],
	["show", "Appear", "a unit becomes visible"],
	["hide", "Disappear", "a unit becomes invisible"],
	["shield_on", "Cannot be hurt", "a unit takes no damage"],
	["shield_off", "Can be hurt", "a unit takes damage again"],
	["combat_on", "May fight", "a unit may fight again"],
	["combat_off", "Hold fire", "a unit stops fighting"],
	["fire_at", "Fire at a unit", "a unit fires its weapon at another"],
	["explode", "Explode", "a unit explodes"],
	["goal", "Goal done", "counts as one destroyed target"],
	["fail", "Mission fails", "fails the mission"],
]
const TAGS := ["scenario rule", "scenario area", "scenario goal"]
const PALETTE_FONT := 12  # small, so the rules get the room
const RULE_COLOR := Color(0.16, 0.18, 0.2)
const CURRENT_COLOR := Color(0.2, 0.26, 0.32)

var editor: Control  # mission_editor.gd
var rules: Array = []
var drafts: Array = []  # [index, rule]: new or edited rules that cannot be written yet, with their "error"
var current := -1  # the rule a clicked block goes to
var _pick := {}  # {path: [rule, …keys], from: the editor's selection when asked}
var _audio: Array = []
var _sig := ""
var _list: VBoxContainer
var _note: Label


func _init(ed: Control) -> void:
	editor = ed
	name = "Scenario"
	theme = Theme.new()
	theme.default_font_size = 14  # a little smaller than the other tabs: rules are long
	var help := Label.new()
	help.text = "Drag a block onto a rule, or click it to add it to the highlighted rule."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", PALETTE_FONT)
	add_child(help)
	_palette("WHEN", WHENS, "when")
	_palette("THEN", THENS, "then")
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	# The palettes stay; the rules scroll under them.
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)


func _palette(title: String, blocks: Array, side: String) -> void:
	var flow := HFlowContainer.new()
	add_child(flow)
	var head := _text(title + ":", Color(0.6, 0.85, 1.0) if side == "when" else Color(1.0, 0.85, 0.5))
	head.add_theme_font_size_override("font_size", PALETTE_FONT)
	flow.add_child(head)
	for blk in blocks:
		var b := Button.new()
		b.text = blk[1]
		b.tooltip_text = blk[2]
		b.add_theme_font_size_override("font_size", PALETTE_FONT)
		var data := {side: blk[0]}
		b.pressed.connect(func(): _clicked(data))
		b.set_drag_forwarding(func(_at): return _drag(b, data), Callable(), Callable())
		flow.add_child(b)
	if side == "when":
		var n := Button.new()
		n.text = "New empty rule"
		n.tooltip_text = "A rule without a WHEN yet"
		n.add_theme_font_size_override("font_size", PALETTE_FONT)
		n.pressed.connect(func(): add_rule(""))
		flow.add_child(n)


func _drag(b: Button, data: Dictionary) -> Dictionary:
	var p := Label.new()
	p.text = b.text
	b.set_drag_preview(p)
	return {"scenario_block": data}


func _clicked(data: Dictionary) -> void:
	if data.has("when") and (current < 0 or current >= rules.size() or not rules[current].get("editable", true)):
		add_rule(data.when)
	elif current >= 0 and current < rules.size():
		drop_block(current, data)
	elif data.has("then"):
		_note.text = "Make a rule first: click or drag a WHEN block."


# --- the rules ------------------------------------------------------------------------------------------------------


## A new rule with WHEN `kind` ("" = none yet); its index.
func add_rule(kind: String) -> int:
	if editor.read_only:
		return -1
	var r := {"key": null, "editable": true, "when": {"kind": kind}, "then": []}
	_defaults(r.when)
	rules.append(r)
	current = rules.size() - 1
	commit()
	return current


## Block `data` ({"when": kind} or {"then": kind}) dropped on rule `i`.
func drop_block(i: int, data: Dictionary) -> void:
	if i < 0 or i >= rules.size() or not rules[i].get("editable", true) or editor.read_only:
		return
	current = i
	if data.has("when"):
		var w := {"kind": data.when}
		# The units picked keep their places where the new WHEN has them.
		var old: Dictionary = rules[i].when
		var unit = old.get("units", [old.get("who")])[0] if old.has("units") or old.has("who") else null
		_defaults(w, unit)
		rules[i].when = w
	else:
		var b := {"kind": data.then}
		match data.then:
			"wait":
				b.seconds = 30
			"message":
				b.audio = -1
			"fire_at":
				b.merge({"unit": -1, "target": -1, "hit": true})
			"goal", "fail":
				pass
			_:
				b.unit = -1
		rules[i].then.append(b)
	commit()


func _defaults(w: Dictionary, unit = null) -> void:
	var u: int = -1 if unit == null else int(unit)
	match w.kind:
		"destroyed", "damaged":
			w.units = [u]
		"enters", "leaves":
			w.merge({"who": u, "center": -1, "radius": 10000.0}, false)


func move_rule(i: int, by: int) -> void:
	var j := i + by
	if j < 0 or j >= rules.size():
		return
	var r = rules[i]
	rules[i] = rules[j]
	rules[j] = r
	current = j
	commit()


func delete_rule(i: int) -> void:
	rules.remove_at(i)
	current = mini(current, rules.size() - 1)
	commit()


## Sets `value` at `path` ([rule, key, …]) and writes the rules.
func set_value(path: Array, value) -> void:
	var d = rules[path[0]]
	for k in path.slice(1, path.size() - 1):
		d = d[k]
	d[path[-1]] = value
	current = path[0]
	commit()


## Writes the rules into the mission (one undo step); the ones that cannot be written yet stay as drafts.
func commit() -> void:
	var send: Array = []
	for r in rules:
		var c: Dictionary = r.duplicate(true)
		c.erase("error")
		send.append(c)
	var res: Dictionary = editor.api.set_rules(editor.data, send)
	drafts = []
	for e in res.get("errors", []):
		var d: Dictionary = send[int(e.rule)]
		d.key = null
		d.erase("summary")
		d.error = String(e.text)
		drafts.append([int(e.rule), d])
	_sig = ""
	if JSON.stringify(res.get("mission", {})) != JSON.stringify(editor.data):
		editor._edit(res.mission)
	else:
		refresh()


## Reads the rules again from the mission (after any edit) and redraws when they changed.
func refresh() -> void:
	if editor.data.is_empty():
		rules = []
		_note.text = "Open or make a mission first."
		_rebuild()
		return
	if not _pick.is_empty() and editor.sel_id >= 0 and editor.sel_id != int(_pick.from):
		var path: Array = _pick.path
		_pick = {}
		set_value(path, editor.sel_id)
		return
	rules = editor.api.rules(editor.data)
	for d in drafts:  # each at its place in the list
		rules.insert(mini(d[0], rules.size()), d[1])
	_note.text = "An original mission: Fork it to change its rules." if editor.read_only else ""
	var sig := JSON.stringify([rules, current, _pick, editor.read_only])
	if sig != _sig:
		_sig = sig
		_rebuild()


# --- drawing --------------------------------------------------------------------------------------------------------


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in rules.size():
		_list.add_child(_rule_panel(i))


func _rule_panel(i: int) -> Control:
	var r: Dictionary = rules[i]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CURRENT_COLOR if i == current else RULE_COLOR
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	var edit: bool = r.get("editable", true) and not editor.read_only
	if edit:
		panel.set_drag_forwarding(
			Callable(),
			func(_at, d): return d is Dictionary and d.has("scenario_block"),
			func(_at, d): drop_block(i, d.scenario_block)
		)
	panel.gui_input.connect(
		func(ev):
			if ev is InputEventMouseButton and ev.pressed and current != i:
				current = i
				_sig = ""
				refresh()
	)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	var drafted: bool = r.has("error") or not r.has("summary")
	title.text = "%d. %s" % [i + 1, "New rule (not in the mission yet)" if drafted else String(r.summary)]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not editor.read_only:
		_small(head, "↑", "Move the rule up", func(): move_rule(i, -1)).disabled = i == 0
		_small(head, "↓", "Move the rule down", func(): move_rule(i, 1)).disabled = i == rules.size() - 1
	if edit:
		_small(head, "✕", "Delete the rule", func(): delete_rule(i))
	if not r.get("editable", true):
		var why := Label.new()
		why.text = "The original's rule, kept as it is: %s." % String(r.get("why", ""))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.modulate = Color(0.7, 0.7, 0.7)
		box.add_child(why)
		return panel
	if r.has("error"):
		var err := Label.new()
		err.text = "To finish: %s." % r.error
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.modulate = Color(1, 0.6, 0.5)
		box.add_child(err)
	_when_row(box, i, r.when, edit)
	var then: Array = r.then
	if then.is_empty():
		box.add_child(_text("THEN: drop or click a THEN block", Color(0.7, 0.7, 0.7)))
	for j in then.size():
		_then_row(box, i, j, then[j], edit)
	return panel


func _when_row(box: VBoxContainer, i: int, w: Dictionary, edit: bool) -> void:
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(_text("WHEN", Color(0.6, 0.85, 1.0)))
	match String(w.get("kind", "")):
		"destroyed", "damaged":
			var units: Array = w.units
			for k in units.size():
				if k > 0:
					row.add_child(_text("or"))
				_unit_picker(row, [i, "when", "units", k], units[k], edit)
			row.add_child(_text("is destroyed" if w.kind == "destroyed" else "is badly hit"))
			if edit:
				_small(
					row,
					"+ or",
					"Another unit that fires the rule",
					func(): set_value([i, "when", "units"], units + [-1])
				)
		"enters", "leaves":
			_unit_picker(row, [i, "when", "who"], w.get("who", -1), edit)
			row.add_child(_text("comes within" if w.kind == "enters" else "moves away from"))
			_number(row, [i, "when", "radius"], float(w.get("radius", 0)) / 1000.0, "km", 1000.0, edit)
			row.add_child(_text("of"))
			if w.has("at") and w.get("center") == null:
				row.add_child(_text("a point (%d, %d)" % [w.at[0], w.at[1]]))
			_unit_picker(row, [i, "when", "center"], w.get("center", -1), edit)
		"start":
			row.add_child(_text("the flight starts"))
		"":
			row.add_child(_text("drop or click a WHEN block", Color(0.7, 0.7, 0.7)))
		_:
			row.add_child(_text(String(w.get("text", ""))))


func _then_row(box: VBoxContainer, i: int, j: int, b: Dictionary, edit: bool) -> void:
	var row := HFlowContainer.new()
	box.add_child(row)
	row.add_child(_text("THEN", Color(1.0, 0.85, 0.5)))
	var p := [i, "then", j]
	match String(b.kind):
		"wait":
			row.add_child(_text("wait"))
			_number(row, p + ["seconds"], float(b.seconds), "s", 1.0, edit)
		"message":
			row.add_child(_text("play"))
			_audio_picker(row, p + ["audio"], int(b.audio), edit)
		"route":
			_unit_picker(row, p + ["unit"], b.unit, edit)
			row.add_child(_text("starts its route"))
		"fire_at":
			_unit_picker(row, p + ["unit"], b.unit, edit)
			row.add_child(_text("fires at"))
			_unit_picker(row, p + ["target"], b.get("target", -1), edit)
			var c := CheckBox.new()
			c.text = "to kill"
			c.tooltip_text = "Off: a miss for show (its blast hurts nothing)"
			c.button_pressed = bool(b.get("hit", true))
			c.disabled = not edit
			c.toggled.connect(func(on): set_value(p + ["hit"], on))
			row.add_child(c)
		"fire_point":
			_unit_picker(row, p + ["unit"], b.unit, edit)
			row.add_child(_text("fires at the point (%d, %d)" % [b.at[0], b.at[1]]))
		"goal":
			row.add_child(_text("a goal is done (counts as a destroyed target)"))
		"fail":
			row.add_child(_text("the mission fails"))
		var k:
			_unit_picker(row, p + ["unit"], b.unit, edit)
			for t in THENS:
				if t[0] == k:
					row.add_child(_text(String(t[2]).trim_prefix("a unit ")))
	if edit:
		_small(row, "✕", "Remove this block", func(): _remove_then(i, j))


func _remove_then(i: int, j: int) -> void:
	rules[i].then.remove_at(j)
	current = i
	commit()


func _text(t: String, c := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = c
	return l


func _small(parent: Control, t: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


## A number field (shown in `unit`, stored × `scale`), written when Enter is pressed or the field is left.
func _number(row: Control, path: Array, v: float, unit: String, scale: float, edit: bool) -> void:
	var e := LineEdit.new()
	e.text = str(snappedf(v, 0.1))
	e.custom_minimum_size.x = 60
	e.editable = edit
	var done := func(_t = ""):
		if e.text.is_valid_float() and absf(e.text.to_float() - v) > 1e-6:
			set_value(path, e.text.to_float() * scale)
	e.text_submitted.connect(done)
	e.focus_exited.connect(done)
	row.add_child(e)
	row.add_child(_text(unit))


## The mission's units by readable name: "SA6 (SA 6, red)"; a flight leader as its flight.
func _units() -> Array:
	var out := []
	for e in editor.data.get("entities", {}).get("items", []):
		if int(e.get("0x14", 0)) != 0 or String(e.get("0x316", "")) in TAGS:
			continue
		if float(e.get("0x2e4", -1)) < 0 and String(e.get("0x2bc", "")).to_lower().begins_with("player"):
			continue
		var obj: Dictionary = editor.objects.get(int(e.get("0x2c6", -1)), {})
		var kind := (
			String(obj.get("0x528", "")) if String(obj.get("0x528", "")) != "" else String(obj.get("0x514", "?"))
		)
		var side: String = ["blue", "red", "neutral"][clampi(int(e.get("0x2d0", 1)), 1, 3) - 1]
		var label := "%s (%s, %s)" % [e.get("0x2bc", ""), kind, side]
		for f in editor.data.get("formations", {}).get("items", []):
			if int(f.get("0x14", 0)) == 0 and int(f.members[0].get("0x41a", -1)) == int(e["0x1e"]):
				label = "%s: %s" % [f.get("0x3e8", ""), label]
		out.append([int(e["0x1e"]), label])
	out.sort_custom(func(a, b): return a[1].naturalnocasecmp_to(b[1]) < 0)
	return out


func _unit_picker(row: Control, path: Array, id, edit: bool) -> void:
	var o := OptionButton.new()
	o.add_item("pick a unit")
	o.set_item_metadata(0, -1)
	o.custom_minimum_size.x = 230
	o.clip_text = true
	o.fit_to_longest_item = false
	var want := -1 if id == null else int(id)
	for u in _units():
		o.add_item(u[1])
		o.set_item_metadata(o.item_count - 1, u[0])
		if u[0] == want:
			o.select(o.item_count - 1)
	if want >= 0 and o.selected <= 0:
		o.add_item("unit %d (missing)" % want)
		o.select(o.item_count - 1)
	o.disabled = not edit
	o.item_selected.connect(func(k): set_value(path, int(o.get_item_metadata(k))))
	row.add_child(o)
	if edit:
		var picking: bool = _pick.get("path", []) == path
		var b := _small(
			row, "click on map…" if picking else "Map", "Pick the unit by clicking it on the map", Callable()
		)
		b.pressed.connect(
			func():
				_pick = {} if picking else {"path": path, "from": editor.sel_id}
				_sig = ""
				refresh()
		)


func _audio_picker(row: Control, path: Array, id: int, edit: bool) -> void:
	if _audio.is_empty():
		_audio = editor.api.audio_list()
	var o := OptionButton.new()
	o.add_item("pick a message")
	o.set_item_metadata(0, -1)
	o.custom_minimum_size.x = 260
	o.clip_text = true
	o.fit_to_longest_item = false
	for a in _audio:
		var t := String(a.text) if String(a.text) != "" else "(%s, no subtitle)" % a.name
		o.add_item(t.left(70))
		o.set_item_metadata(o.item_count - 1, int(a.id))
		o.set_item_tooltip(o.item_count - 1, String(a.text))
		if int(a.id) == id:
			o.select(o.item_count - 1)
	o.disabled = not edit
	o.item_selected.connect(func(k): set_value(path, int(o.get_item_metadata(k))))
	row.add_child(o)
