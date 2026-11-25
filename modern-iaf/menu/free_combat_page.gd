# Modern IAF's Scramble screen (הזנקה, modern-iaf/docs/front-end.md §2.1): the player picks the flight and the start,
# then flies; no mission, the jet's Scramble start at its home base (data/missions/<base>_free.json) carries it. The
# fight's area is drawn at Fly (Fly.free_area: a base within reach of the jet's), the enemy in flight at the Pilot
# screen's enemy skill (IafFreeCombat.roll), and the AWACS gives the task and where by radio (flight/free_combat.gd).
# One panel of rows, each a label and its segments; the Time row: the flight's start time, Israel time, as 24-hour
# military time HHMM, stepped by an hour (the arrows beside its hours) and five minutes (beside its minutes); the Date
# row: its day and month this year, stepped by a day and a month; each with Random (drawn at Fly from the Scramble's
# seed, IafFreeCombat.start_time / start_day; the kneeboard's DATA page shows them). A line under the panel names the
# enemy skill. The flight and the start are kept at once (Settings.free_combat); the time and date only for the
# screen's visit (when). A load the one load rule blocks turns Fly off and says why in one line. The footer: Back,
# Arming (the Loadout screen, on that start), Fly.
extends RefCounted

const Look := preload("res://menu/look.gd")
const DEFAULT := {"flight": 2, "start": "air"}
## The start time and date for this visit to the screen, never stored (the user, 25 Nov 2026: "No need to remember
## last choice"): reset() at each opening to 0800 and today, Random off. time: minutes after local midnight; date:
## the day of this year.
static var when := {}
const STARTS := ["air", "runway", "ground"]


## The picks now: Settings.free_combat over the defaults, with the jet's base as `home` (its JETS row's `base`).
static func picks(fe: Control) -> Dictionary:
	var fc: Dictionary = DEFAULT.merged(Settings.free_combat, true)
	if not fc.start in STARTS:
		fc.start = DEFAULT.start
	if not int(fc.flight) in [1, 2, 4]:
		fc.flight = DEFAULT.flight
	if when.is_empty():
		reset()
	fc.merge(when, true)
	fc.home = _section(str(fe.jet().get("base", "")))
	return fc


## The start time and date as the screen opens: 0800 today, Random off.
static func reset() -> void:
	var d := Time.get_date_dict_from_system()
	when = {
		"time": 480,
		"time_random": false,
		"date": IafFreeCombat.day_of_year(d.year, d.month, d.day),
		"date_random": false
	}


## This year (the date's: no year to pick).
static func year() -> int:
	return int(Time.get_date_dict_from_system().year)


## The iaf.ibx section of base key `key` (strings base_<key>: ramon -> Ramon, tel_nof -> TelNof, ramat_david -> David).
static func _section(key: String) -> String:
	return "David" if key == "ramat_david" else key.to_pascal_case()


## Why the picks cannot fly, one line ("" they can): the one load rule (fe.need_text).
static func refusal(fe: Control) -> String:
	if fe.missions.is_empty():
		return fe.s("fc_no_start")
	var a: Dictionary = fe.arming(fe.missions[0], fe.mission_loadout(fe.missions[0]))
	if bool(a.get("blocked", false)):
		return fe.need_text(a)
	return ""


static func build(fe: Control) -> void:
	var fc := picks(fe)
	fe._header(["hangar", [fe.full_name(fe.jet()), "missions"], "sec_fly_now"])
	var v: VBoxContainer = fe._vbox(fe._body(96, 130, 130), 34)
	fe._title(v, fe.s("sec_fly_now"), fe.s("fc_sub") % fe.s("base_" + str(fe.jet().get("base", ""))))
	var cols: HBoxContainer = fe._hbox(v, 56)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := []
	var own := _panel(fe, cols, "fc_flight_h")
	rows.append(_row(fe, own, "flight", [["fc_flight_1", 1], ["fc_flight_2", 2], ["fc_flight_4", 4]], fc))
	rows.append(_row(fe, own, "start", STARTS.map(func(k): return ["fc_start_" + k, k]), fc))
	rows.append(_time_row(fe, own))
	rows.append(_date_row(fe, own))
	var skill: Label = fe._label(
		own.get_parent(), fe.s("fc_skill") % fe.s("skill_%d" % int(Settings.enemy_skill())), "Small"
	)
	skill.name = "Skill"
	var back: Button = fe.back_button()
	var arm: Button = fe._action(fe.s("tab_arming"), "Secondary", func(): fe.show_page("arming"))
	arm.name = "Arming"
	arm.disabled = fe.missions.is_empty()
	var fly: Button = fe._action(fe.s("fly"), "Primary", func(): fe.fly_free())
	fly.name = "Fly"
	var line: Label = fe._footer(" ", [arm, fly], false, [back])
	line.name = "Notice"
	line.add_theme_color_override("font_color", Look.WARN)
	line.add_theme_font_size_override("font_size", 16)
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	var update := func():
		var why := refusal(fe)
		line.text = why
		fly.disabled = why != ""
	update.call()
	for r in rows:
		for b in r:
			b.pressed.connect(update)
	# Tab: row by row, then the footer; the arrows move inside a row and between rows by their place.
	var all := []
	for r in rows:
		all += r
	fe._chain(all + [back, arm, fly])
	fe._focus = rows[0].filter(func(b): return b.button_pressed).front()


## The Time row (the flight's start time, Israel time, HHMM: left to right in both languages, as the digits read: the
## hour's down / up, the time, the minutes' down / up) and the Date row (the day's down / up, the day and its month,
## the month's down / up; in Hebrew right to left), each with Random; their buttons.
static func _time_row(fe: Control, g: GridContainer) -> Array:
	var steps := [
		["hour_down", func(v): return IafFreeCombat.time_step(v, -1, 0)],
		["hour_up", func(v): return IafFreeCombat.time_step(v, 1, 0)],
		[],
		["min_down", func(v): return IafFreeCombat.time_step(v, 0, -1)],
		["min_up", func(v): return IafFreeCombat.time_step(v, 0, 1)],
	]
	return _step_row(fe, g, "time", steps, func(v): return IafFreeCombat.clock(v), true)


static func _date_row(fe: Control, g: GridContainer) -> Array:
	var y := year()
	var steps := [
		["day_down", func(v): return IafFreeCombat.date_step(y, v, -1, 0)],
		["day_up", func(v): return IafFreeCombat.date_step(y, v, 1, 0)],
		[],
		["month_down", func(v): return IafFreeCombat.date_step(y, v, 0, -1)],
		["month_up", func(v): return IafFreeCombat.date_step(y, v, 0, 1)],
	]
	return _step_row(fe, g, "date", steps, func(v): return date_text(fe, y, v), false)


## The day `doy` of `year` as the screen shows it: "25 November", "25 בנובמבר".
static func date_text(fe: Control, y: int, doy: int) -> String:
	var md: Vector2i = IafFreeCombat.month_day(y, doy)
	return fe.s("fc_date_fmt") % [md.y, fe.s("month_%d" % md.x)]


## A row of `key`'s value (when[key]) with its step buttons `steps` ([name, step(value) -> value], [] the value's
## place), shown by `text`, and Random (when[key + "_random"]) beside them; `ltr` keeps the steps left to right in
## Hebrew. A step or Random is kept for the screen's visit (when); Random dims the value and its arrows.
static func _step_row(fe: Control, g: GridContainer, key: String, steps: Array, text: Callable, ltr: bool) -> Array:
	var l: Label = fe._label(g, fe.s("fc_" + key), "Row")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row: HBoxContainer = fe._hbox(g, 8)
	row.name = "Row_" + key
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: HBoxContainer = fe._hbox(row, 6)
	if ltr:
		box.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var shown: Label = Label.new()
	shown.name = "Value_" + key
	shown.theme_type_variation = "Row"
	shown.add_theme_font_size_override("font_size", 30)
	shown.custom_minimum_size.x = 96 if ltr else 200
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons := []
	for d in steps:
		if d.is_empty():
			box.add_child(shown)
			continue
		var b := Button.new()
		b.name = "%s_%s" % [key, d[0]]
		b.text = "▲" if d[0].ends_with("up") else "▼"
		b.tooltip_text = fe.s("fc_" + d[0])
		b.theme_type_variation = "Segment"
		b.custom_minimum_size = Vector2(52, 44)
		box.add_child(b)
		var step: Callable = d[1]
		b.pressed.connect(func(): when[key] = step.call(int(when[key])))
		buttons.append(b)
	var rnd: Button = fe._segment(row, fe.s("fc_random"), null, bool(when[key + "_random"]))
	rnd.name = key + "_random"
	rnd.custom_minimum_size.x = 220
	rnd.toggled.connect(func(on: bool): when[key + "_random"] = on)
	var show := func():
		var on := bool(when[key + "_random"])
		shown.text = text.call(int(when[key]))
		shown.modulate.a = 0.4 if on else 1.0
		for b in buttons:
			b.disabled = on
			b.focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
	show.call()
	for b in buttons + [rnd]:
		b.pressed.connect(show)
	return buttons + [rnd]


## Stores pick `key` = `value` in Settings.free_combat at once.
static func _store(fe: Control, key: String, value) -> void:
	var now := picks(fe)
	for k in ["home"] + when.keys():
		now.erase(k)
	now[key] = value
	Settings.free_combat = now
	Settings.save()


## A panel of rows under its heading `title`; the box the rows go in.
static func _panel(fe: Control, parent: Control, title: String) -> GridContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.94), Look.LINE, 1, 6, Vector2(32, 28)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(p)
	var v: VBoxContainer = fe._vbox(p, 22)
	fe._label(v, fe.s(title), "H2")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 18)
	v.add_child(g)
	return g


## Row `key`: its label and one segment per choice [label key, value] (the one `fc` holds lit); its buttons. A pick is
## stored at once in Settings.
static func _row(fe: Control, g: GridContainer, key: String, choices: Array, fc: Dictionary) -> Array:
	var l: Label = fe._label(g, fe.s("fc_" + key), "Row")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var seg: HBoxContainer = fe._hbox(g, -1)
	seg.name = "Row_" + key
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	var out := []
	for c in choices:
		var b: Button = fe._segment(seg, fe.s(c[0]) if fe.strings.has(c[0]) else c[0], group, fc.get(key) == c[1])
		b.name = "%s_%s" % [key, str(c[1])]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value = c[1]
		b.pressed.connect(func(): _store(fe, key, value))
		out.append(b)
	return out
