# The combat logbook on the screens (modern-iaf/docs/front-end.md §3.2): four totals on the Pilot screen's logbook and
# on the debrief sheet, the rest on the More stats page. The counts are the records' (IafPilotLog.combat; the rule in
# crates/iaf-tools combat_log.rs); this script only lays them out. The look is the approved mock's (wt/logbook-mock
# c6c14055; the user, 24 Nov 2026: "too many stats. move the least relvant to some "more stats" or "in depth". no
# need to spell who was failing, just in general"): the losses as counts by cause, never by jet.
extends RefCounted

const Look := preload("look.gd")

## The weapon records by their name ({"AIM-120": {id, kind, powered}}), read once. A powered weapon has its own
## engine (its record's `mach`, Delilah's): released as a bomb, it flies as a missile, so it is launched, not dropped.
static var _weapons := {}


## The pilot's combat logbook (`sortie` 0) or one sortie's (IafPilotLog.combat).
static func data(sortie := 0) -> Dictionary:
	var d = JSON.parse_string(IafPilotLog.combat(Settings.records_db(), Settings.pilot(), sortie))
	return d if d is Dictionary else {}


## Whether record `c` holds any combat.
static func any(c: Dictionary) -> bool:
	for k in ["kills", "ground", "weapons", "lost"]:
		if not c.get(k, []).is_empty():
			return true
	return int(c.get("ejected", 0)) > 0


static func _weapon(name: String) -> Dictionary:
	if _weapons.is_empty():
		var dir := Settings.disk_path("res://data/db/weapons")
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				var r: Dictionary = Settings.load_json(dir.path_join(f))
				_weapons[str(r.get("name", ""))] = {
					"id": str(r.get("id", "")), "kind": str(r.get("kind", "")), "powered": r.has("mach")
				}
	return _weapons.get(name, {})


## A weapon's name on the screens: its store string, else its record name.
static func _weapon_name(fe: Control, name: String) -> String:
	var id := str(_weapon(name).get("id", ""))
	return fe.s("store_" + id) if fe.strings.has("store_" + id) else name


## A weapon's group: "missiles" (launched), "bombs" (dropped) or "gun" (rounds).
static func _group(name: String, gun: bool) -> String:
	if gun:
		return "gun"
	var w := _weapon(name)
	return "missiles" if str(w.get("kind", "")).ends_with("missile") or w.get("powered", false) else "bombs"


## A unit type's name: its string, else its record's label, else the type as recorded.
static func _unit_name(fe: Control, unit: String) -> String:
	if fe.strings.has("unit_" + unit):
		return fe.s("unit_" + unit)
	var path := "res://data/db/units/%s.json" % unit
	return str(Settings.load_json(path).get("label", unit)) if FileAccess.file_exists(path) else unit


## The four totals of `t` (IafPilotLog.combat's `totals`): [figure, label, its line under].
static func _totals(fe: Control, t: Dictionary) -> Array:
	var shared := int(t.get("shared", 0))
	var down := int(t.get("shot_down", 0))
	var crashed := int(t.get("crashed", 0))
	var lost_sub := ""
	if down > 0 and crashed > 0:
		lost_sub = fe.s("combat_lost_sub") % [down, crashed]
	elif down > 0:
		lost_sub = fe.s("combat_lost_down")
	elif crashed > 0:
		lost_sub = fe.s("combat_lost_crashed")
	return [
		[
			str(int(t.get("air_kills", 0))),
			fe.s("combat_air_kills"),
			fe.s("combat_shared_n") % shared if shared > 0 else fe.s("combat_shared_none")
		],
		[str(int(t.get("ground", 0))), fe.s("combat_ground"), fe.s("combat_destroyed")],
		[str(int(t.get("hits", 0))), fe.s("combat_hits"), fe.s("combat_hits_of") % int(t.get("fired", 0))],
		[str(int(t.get("lost", 0))), fe.s("combat_lost"), lost_sub],
	]


static func _caption(fe: Control, parent: Control, t: String) -> Label:
	var l: Label = fe._label(parent, t, "H3")
	l.add_theme_font_size_override("font_size", 20)
	return l


## A figure's cell: a fixed width, at the row's inline end.
static func _num(fe: Control, parent: Control, t: String, kind: String, width: int) -> Label:
	var l: Label = fe._label(parent, t, kind)
	l.custom_minimum_size.x = width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _col(fe: Control, cols: Control) -> VBoxContainer:
	var a: VBoxContainer = fe._vbox(cols, 4)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return a


# --- the logbook ------------------------------------------------------------------------------------------------------


## The combat block at the logbook's top (`rows`, the panel's scrolled list): the four totals of every flight and More
## stats beside Pilot log (`top`, the logbook's top row). Nothing while the pilot has flown no combat.
static func logbook(fe: Control, top: Control, rows: VBoxContainer) -> void:
	var c := data()
	if c.get("flights", []).is_empty():
		return
	var cap: Label = fe._label(rows, fe.s("combat"), "Strong")
	cap.add_theme_font_size_override("font_size", 25)
	var more: Button = fe._action(fe.s("combat_more"), "Secondary", func(): _open(fe, "pilot"))
	more.name = "CombatMore"
	top.add_child(more)
	top.move_child(more, top.get_child_count() - 2)
	var tiles: HBoxContainer = fe._hbox(rows, 10)
	tiles.name = "CombatTotals"
	for t in _totals(fe, c.get("totals", {})):
		_tile(fe, tiles, t[0], t[1], t[2])
	fe._spacer_px(rows, 14)


static func _open(fe: Control, from: String) -> void:
	fe.combat_from = from
	if from == "pilot":
		fe.pilot_back("combat")
	else:
		fe.show_page("combat")


static func _tile(fe: Control, parent: Control, big: String, label: String, sub: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Look.box(Look.RAISED, Look.LINE, 1, 6, Vector2(14, 8)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v: VBoxContainer = fe._vbox(p, 0)
	var num: Label = fe._label(v, big, "Stat")
	num.add_theme_font_size_override("font_size", 34)
	fe._label(v, label, "Key").add_theme_font_size_override("font_size", 19)
	fe._label(v, sub, "Small").add_theme_font_size_override("font_size", 17)


# --- More stats -------------------------------------------------------------------------------------------------------


## The More stats page: from the logbook every combat flight, from the debrief that flight: the air kills and ground
## targets by type, the weapons fired and hit, the jets lost by cause, and (every flight) the combat flights.
static func page(fe: Control) -> void:
	var one: bool = fe.combat_from == "debrief"
	var c := data(fe.record_sortie if one else 0)
	if one:
		fe._header(["hangar", [fe.s("debrief"), "debrief"], fe.s("combat_more")])
	else:
		fe._header(["hangar", "pilot", fe.s("combat_more")])
	var v: VBoxContainer = fe._vbox(fe._body(), 26)
	var sub: String = fe.s("combat_all")
	if one:
		var m: Dictionary = fe.mission_by_name(str(fe.record.get("mission", "")))
		var title: String = fe.title_of(m) if not m.is_empty() else str(fe.record.get("mission", ""))
		sub = "%s · %s" % [fe.day_text(str(fe.record.get("date", ""))), title]
	fe._title(v, fe.s("combat_more"), sub)
	var back: Button = fe.back_button()
	fe._footer("", [back])
	fe._focus = back
	var panel := PanelContainer.new()
	panel.name = "CombatMore"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Look.box(Look.PANEL, Look.LINE, 1, 6, Vector2(28, 24)))
	v.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var pad := MarginContainer.new()  # the figures clear of the scroll bar
	pad.add_theme_constant_override("margin_left" if fe.he() else "margin_right", 22)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var book: VBoxContainer = fe._vbox(pad, 10)
	var cap: Label = fe._label(book, fe.s("combat"), "Strong")
	cap.add_theme_font_size_override("font_size", 25)
	# Three columns: the kills and ground targets by type, the weapons, the losses.
	var cols: HBoxContainer = fe._hbox(book, 56)
	var a: VBoxContainer = _col(fe, cols)
	if not c.get("kills", []).is_empty():
		_caption(fe, a, fe.s("combat_kills_by_type"))
		for k in c.kills:
			var r: HBoxContainer = fe._hbox(a, 8)
			fe._label(r, _unit_name(fe, str(k[0])), "Key").size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if int(k[2]) > 0:
				fe._chip(r, fe.s("combat_shared_n") % int(k[2]), false)
			_num(fe, r, str(int(k[1])), "Key", 36)
		fe._spacer_px(a, 12)
	if not c.get("ground", []).is_empty():
		_caption(fe, a, fe.s("combat_ground_by_type"))
		for g in c.ground:
			var r: HBoxContainer = fe._hbox(a, 8)
			fe._label(r, _unit_name(fe, str(g[0])), "Key").size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_num(fe, r, str(int(g[1])), "Key", 36)
	_weapons_col(fe, _col(fe, cols), c.get("weapons", []))
	var l: VBoxContainer = _col(fe, cols)
	if not c.get("lost", []).is_empty() or int(c.get("ejected", 0)) > 0:
		_caption(fe, l, fe.s("combat_losses"))
		for x in c.get("lost", []):
			_row(fe, l, fe.s("combat_by_" + str(x[0])), int(x[1]))
		if int(c.get("wingmen_lost", 0)) > 0:
			_row(fe, l, fe.s("combat_wingmen"), int(c.wingmen_lost))
		if int(c.get("ejected", 0)) > 0:
			fe._rule(l, Look.LINE)
			_row(fe, l, fe.s("combat_ejections"), int(c.ejected))
	if one:
		return
	fe._spacer_px(book, 14)
	_caption(fe, book, fe.s("combat_flights"))
	for f in c.get("flights", []):
		fe._rule(book, Look.LINE)
		var r: HBoxContainer = fe._hbox(book, 14)
		var day: Label = fe._label(r, fe.day_text(str(f.date)), "Muted")
		day.custom_minimum_size.x = 170
		var mm: Dictionary = fe.mission_by_id(int(f.mission_id))
		var mission: Label = fe._label(r, fe.title_of(mm) if not mm.is_empty() else str(f.mission), "Key")
		mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(f.lost) > 0:
			fe._chip(r, _count(fe, "combat_f_lost", int(f.lost)), false).add_theme_color_override(
				"font_color", Look.WARN
			)
		fe._chip(r, _count(fe, "combat_f_kill", int(f.air_kills)), int(f.air_kills) > 0)
		fe._chip(r, _count(fe, "combat_f_target", int(f.ground)), int(f.ground) > 0)


## "1 kill" / "%d kills": `key` + "1" for one, `key` + "s" for the rest ("combat_f_kill1", "combat_f_kills").
static func _count(fe: Control, key: String, n: int) -> String:
	if n == 1:
		return fe.s(key + "1")
	return fe.s(key + "s") % n if fe.strings.has(key + "s") else fe.s(key) % n


static func _row(fe: Control, parent: Control, label: String, n: int) -> void:
	var r: HBoxContainer = fe._hbox(parent, 8)
	fe._label(r, label, "Key").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_num(fe, r, str(n), "Key", 36)


## The weapons column: a group per kind (missiles fired, bombs dropped, the gun's rounds), each with its own verb (the
## user, 24 Nov 2026: missiles שוגרו, bombs הוטלו, the gun נורו) and the hits.
static func _weapons_col(fe: Control, b: VBoxContainer, weapons: Array) -> void:
	var verbs := {"missiles": "combat_launched", "bombs": "combat_dropped", "gun": "combat_rounds"}
	var first := true
	for group in ["missiles", "bombs", "gun"]:
		var rows := weapons.filter(func(x): return _group(str(x[0]), bool(x[3])) == group)
		if rows.is_empty():
			continue
		if first:
			_caption(fe, b, fe.s("combat_weapons"))
			first = false
		else:
			fe._spacer_px(b, 8)
		var h: HBoxContainer = fe._hbox(b, 8)
		var g: Label = fe._label(h, fe.s("combat_" + group), "Muted")
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_num(fe, h, fe.s(verbs[group]), "Small", 80)
		_num(fe, h, fe.s("combat_hits"), "Small", 80)
		for x in rows:
			var r: HBoxContainer = fe._hbox(b, 8)
			fe._label(r, _weapon_name(fe, str(x[0])), "Key").size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_num(fe, r, str(int(x[1])), "Key", 80)
			_num(fe, r, str(int(x[2])), "Key", 80)


# --- the debrief sheet ------------------------------------------------------------------------------------------------


## The sheet's combat block, under the goals: the flight's four totals (More stats is in the footer). Nothing for a
## flight without combat.
static func sheet(fe: Control, inner: Control) -> void:
	var c := data(fe.record_sortie)
	if not any(c):
		return
	fe._spacer_px(inner, 20)
	fe._label(inner, fe.s("combat").to_upper() if not fe.he() else fe.s("combat"), "PaperHead")
	fe._rule(inner, Look.INK, 2)
	fe._spacer_px(inner, 8)
	var cols: HBoxContainer = fe._hbox(inner, 24)
	cols.name = "Combat"
	var i := 0
	for t in _totals(fe, c.get("totals", {})):
		var col: VBoxContainer = _col(fe, cols)
		fe._label(col, t[1], "PaperLabel")
		var num: Label = fe._label(col, t[0], "PaperNum")
		num.add_theme_font_size_override("font_size", 30)
		if i == 3 and t[0] != "0":
			num.add_theme_color_override("font_color", Color("c62828"))  # jets lost
		fe._label(col, t[2], "PaperLabel")
		i += 1


## The debrief footer's More stats button (beside Pilot log), null for a flight without combat.
static func more_button(fe: Control) -> Button:
	if not any(data(fe.record_sortie)):
		return null
	var b: Button = fe._action(fe.s("combat_more"), "Secondary", func(): _open(fe, "debrief"))
	b.name = "CombatMore"
	return b
