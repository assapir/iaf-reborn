# Modern IAF's Scramble screen (הזנקה, modern-iaf/docs/front-end.md §2.1): the player picks the flight and the start,
# then flies; no mission, the jet's Scramble start at its home base (data/missions/<base>_free.json) carries it. The
# fight's area is drawn at Fly (Fly.free_area: a base within reach of the jet's), the enemy in flight at the Pilot
# screen's enemy skill (IafFreeCombat.roll), and the AWACS gives the task and where by radio (flight/free_combat.gd).
# One panel of rows, each a label and its segments; a line under it names the enemy skill. A pick is kept at once
# (Settings.free_combat). A load the one load rule blocks turns Fly off and says why in one line. The footer: Back,
# Arming (the Loadout screen, on that start), Fly.
extends RefCounted

const Look := preload("res://menu/look.gd")
const DEFAULT := {"flight": 2, "start": "air"}
const STARTS := ["air", "runway", "ground"]


## The picks now: Settings.free_combat over the defaults, with the jet's base as `home` (its JETS row's `base`).
static func picks(fe: Control) -> Dictionary:
	var fc: Dictionary = DEFAULT.merged(Settings.free_combat, true)
	if not fc.start in STARTS:
		fc.start = DEFAULT.start
	if not int(fc.flight) in [1, 2, 4]:
		fc.flight = DEFAULT.flight
	fc.home = _section(str(fe.jet().get("base", "")))
	return fc


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
		b.pressed.connect(
			func():
				var now := picks(fe)
				now.erase("home")
				now[key] = value
				Settings.free_combat = now
				Settings.save()
		)
		out.append(b)
	return out
