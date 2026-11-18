# Modern IAF's Loadout screen (modern-iaf/docs/front-end.md §10, the round-3 design r3_loadout): the picked mission's
# arming on a screen of its own, opened from its briefing. In the middle the jet seen from beneath, where the stores
# hang (shared/aircraft/turntable.gd's model with the stores as the flight hangs them, the camera under it, the bays
# open), each station a callout (number, its place on the wing, the store, its weight; an empty station a dashed
# "Empty") with a line to the station on the model. At the inline start the LOADOUTS: the mission's own and the
# pilot's saved ones (named, per jet: IafPilotLog.saved_loadouts), "+ Save this loadout"; at the inline end the
# TAKE-OFF WEIGHT (IafBriefing.arming: the figure, a bar with the share of the maximum, the wings' balance, fuel, gun
# rounds, chaff / flares) and the STORES the jet may carry. The footer: Reset to the mission's, Briefing, Fly.
#
# The editor's rules are arming_drawing.gd's and loadout.rs's: a store drags from STORES onto a callout, between
# callouts and back; an edit changes that station only, and its mirror station too while "Mirror to the other wing" is
# on (off by default); a station that does not take it shakes; a rack's "×n" badge cycles its count. The keyboard: Enter
# on a callout picks it and moves to the first store it takes ("Empty" takes its store off), Enter there hangs it, Esc
# leaves the callout as it was. The loadout is the pilot's per jet (IafPilotLog.loadout): the flight and the Hangar's
# jet carry it. A mission with `fixed_loadout` shows its own, read-only.
extends Control

const Look := preload("res://menu/look.gd")
const ArmingDrawing := preload("res://menu/arming_drawing.gd")
const Turntable := preload("res://shared/aircraft/turntable.gd")
const AircraftModel := preload("res://shared/aircraft/aircraft_model.gd")
## A callout's size, the room between two in a column and the stage's room on each side of the jet (canvas px).
const CALLOUT := Vector2(170, 84)
const GAP := 14.0
const SIDE := 200.0
## The saved rows' Delete (×) column, kept empty beside the mission's row.
const DELETE_W := 36.0

## The focus to take back after the screen is made again (a Control's name), "" none.
static var _refocus := ""
## "Mirror to the other wing": an edit fills the mirror station too (loadout.rs `pair`). Off by default (the user,
## 15 Nov: "by default change only the station that was used"); kept while the game runs.
static var mirror := false

var fe: Control
var m: Dictionary
var unit := ""
## The pilot's loadout now (JSON text, "" the mission's own) and its arming figures.
var now := ""
var a := {}
var fixed := false
## The station picked by the keyboard, "" none.
var pick := ""
## The stage: an arming drawing without a picture (the drag hints, the drop, the dragged store's picture) holding the
## jet and the callouts; the lines drawn on `lines`.
var stage: Control
var lines: Control
var tt: TextureRect
var callouts := {}


## The Loadout screen in the front end for its picked mission.
static func page(front_end: Control) -> Node:
	var me = load("res://menu/loadout_screen.gd").new()
	me.fe = front_end
	me.name = "Loadout"
	me.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front_end.add_child(me)
	me.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	me.build()
	return me


func s(key: String) -> String:
	return fe.s(key)


func build() -> void:
	m = fe.missions[fe.mission_i] if fe.mission_i < fe.missions.size() else {}
	var j: Dictionary = fe.jet_of(m)
	unit = str(j.get("unit", ""))
	fixed = bool(m.get("fixed_loadout", false))
	now = "" if fixed else fe._arm_now(m)
	a = fe.arming(m, now)
	fe._header(fe.section_crumbs() + [[fe.title_of(m), "mission"], "tab_arming"])
	_stage(j)
	_loadouts()
	_weight()
	# Reset: none on a mission that fixes the loadout.
	var reset: Button = null if fixed else fe._action(s("lo_reset"), "Secondary", func(): set_loadout(""))
	if reset != null:
		reset.name = "ArmReset"
		reset.disabled = now == ""
	var brief: Button = fe._action(s("lo_briefing"), "Secondary", func(): fe.show_page("mission"))
	brief.name = "ToBriefing"
	var fly: Button = fe._action(s("fly"), "Primary", func(): fe.fly_mission(m))
	fly.name = "Fly"
	fly.disabled = bool(a.get("blocked", a.get("over", false)))
	# A store that cannot be employed (a laser bomb with no pod): Fly off and the line saying what to add.
	var need: String = fe.need_text(a)
	var line: Label = fe._footer(need, [brief, fly], false, [] if fixed else [reset])
	if need != "":
		# One short line at the screen's notice size (as the balance warning's), not a wrapped paragraph (the user,
		# 17 Nov: "too long and big").
		line.name = "NeedLine"
		line.add_theme_color_override("font_color", Look.WARN)
		line.add_theme_font_size_override("font_size", 16)
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
	if reset != null and reset.disabled:
		# Its plain box, dimmed (the theme's disabled box reads as another kind of button).
		reset.add_theme_stylebox_override("disabled", reset.get_theme_stylebox("normal"))
		reset.modulate = Color(1, 1, 1, 0.45)
	_focus_order()
	var want: Control = find_child(_refocus, true, false) if _refocus != "" else null
	_refocus = ""
	fe._focus = want if want != null else _picked_row()


# --- the jet from beneath ---------------------------------------------------------------------------------------------


## The stage between the side columns: the caption, the jet from beneath and the callouts, left to right in both
## languages (the jet never mirrors: its left wing shows on the right, as seen from under it).
func _stage(j: Dictionary) -> void:
	stage = ArmingDrawing.new()
	stage.name = "Stage"
	stage.layout_direction = Control.LAYOUT_DIRECTION_LTR
	stage.read_only = fixed
	add_child(stage)
	fe._place(stage, 400, 400, 104, 880)
	var takes := {}
	var al = a.get("allowed", {})
	for k in al if al is Dictionary else {}:
		takes[k] = al[k].map(func(e): return str(e.id))
	stage.allowed = takes
	stage.on_drop = func(data: Dictionary, to: String) -> bool: return drop(data, to)
	stage.on_pick = func(st: String): pick_station(st)
	stage.on_cycle = func(st: String): cycle(st)
	var cap: Label = fe._label(stage, s("lo_seen_below"), "Muted")
	cap.name = "Caption"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var plane := str(
		Settings.load_json("res://shared/extra/planes/%s/airframe.json" % j.airframe).get("base", j.airframe)
	)
	if not AircraftModel.load_descriptor(plane).is_empty():
		tt = Turntable.new()
		tt.name = "Jet"
		tt.below = true
		stage.add_child(tt)
		if not tt.show_jet(plane, fe.jet_stores(j, _shown())):
			tt.queue_free()
			tt = null
	lines = Control.new()
	lines.name = "Lines"
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.draw.connect(_draw_lines)
	stage.add_child(lines)
	var slots: Dictionary = a.get("slots", {}) if a.get("slots") is Dictionary else {}
	var pos: Dictionary = a.get("positions", {}) if a.get("positions") is Dictionary else {}
	for st in takes:
		if takes[st].is_empty():
			continue  # a station the sim hangs nothing on (the Adir's 2 / 10)
		var c := ArmingDrawing.Slot.new()
		c.name = "Slot" + st
		c.station = st
		c.read_only = fixed
		c.size = CALLOUT
		var nm: String = fe.station_label(a, st)
		c.head = ("%s · %s" % [nm, s("pos_" + str(pos.get(st, "")))]).to_upper() if pos.has(st) else nm
		c.empty_text = s("arm_empty")
		c.rtl = fe.he()
		if slots.has(st):
			var e: Dictionary = slots[st]
			var n := int(e.get("count", 1))
			c.store = [str(e.id), fe.short_store(str(e.id)), n, s("store_" + str(e.id)), int(e.get("max", 1))]
			c.sub = "%s %s" % [fe.kg_text(e.kg), s("kg")] if e.get("kg") != null else ""
			c.tooltip_text = s("store_" + str(e.id)) + ("" if n < 2 else " × %d" % n)
		stage.add_child(c)
		c.focus_entered.connect(lines.queue_redraw)
		c.focus_exited.connect(lines.queue_redraw)
		stage.slots[st] = c
		callouts[st] = c
	stage.resized.connect(_layout)
	_layout.call_deferred()


## The jet in the middle of the stage, the callouts in a column on each side of it in the order of their stations'
## height on the screen (so the lines do not cross), a station on the middle line under the jet.
func _layout() -> void:
	if not is_instance_valid(stage):
		return
	var w: float = stage.size.x
	var h: float = stage.size.y
	if tt != null:
		tt.position = Vector2(SIDE - 20.0, 30)
		tt.size = Vector2(w - 2.0 * SIDE + 40.0, h - 30)
		tt.fit()
	lines.position = Vector2.ZERO
	lines.size = stage.size
	var pts := points()
	var mid := w / 2.0
	var sides := {-1: [], 1: [], 0: []}
	for st in callouts:
		var p = pts.get(st)
		var off := 0.0 if p == null else float(p.x) - mid
		var side := 0 if p != null and absf(off) < 12.0 else (1 if off > 0.0 or (p == null and _right(st)) else -1)
		sides[side].append([float(p.y) if p != null else float(st), st])
	for side in [-1, 1]:
		var col: Array = sides[side]
		col.sort()
		var tall := col.size() * (CALLOUT.y + GAP) - GAP
		var ys := pts.values().map(func(p): return p.y)
		var centre: float = (ys.reduce(func(x, y): return x + y, 0.0) / ys.size()) if not ys.is_empty() else h / 2.0
		var top := clampf(centre - tall / 2.0, 40.0, h - tall)
		var x := 0.0 if side < 0 else w - CALLOUT.x
		for i in col.size():
			callouts[col[i][1]].position = Vector2(x, top + i * (CALLOUT.y + GAP))
	var bottom: Array = sides[0]
	for i in bottom.size():
		var x := mid - (bottom.size() * (CALLOUT.x + GAP) - GAP) / 2.0 + i * (CALLOUT.x + GAP)
		callouts[bottom[i][1]].position = Vector2(x, h - CALLOUT.y)
	lines.queue_redraw()


## Whether station `st` sits on the jet's left wing (its numbers from the left wing tip), shown on the right from
## beneath: the side of a station the model gives no place.
func _right(st: String) -> bool:
	var all := callouts.keys().map(func(k): return int(k))
	return int(st) * 2 < (all.max() if not all.is_empty() else 0) + 1


## Each station's place on the stage (station → px) from the model seen from beneath (its pylon's attach point).
func points() -> Dictionary:
	var out := {}
	if tt == null:
		return out
	var by_pylon: Dictionary = tt.points()
	var pylons: Dictionary = a.get("pylons", {}) if a.get("pylons") is Dictionary else {}
	for st in callouts:
		var i := int(pylons[st]) if pylons.get(st) != null else -1  # the engine's station (loadout.rs letter)
		if i >= 0 and by_pylon.has(i):
			out[st] = tt.position + by_pylon[i]
	return out


## A line from each callout's inner edge to its station, a dot on the station.
func _draw_lines() -> void:
	var pts := points()
	for st in pts:
		var c: Control = callouts[st]
		var p: Vector2 = pts[st]
		var from := c.position + Vector2(c.size.x if c.position.x + c.size.x / 2.0 < p.x else 0.0, c.size.y / 2.0)
		if absf(c.position.x + c.size.x / 2.0 - p.x) < CALLOUT.x / 2.0:
			from = c.position + Vector2(c.size.x / 2.0, 0.0)  # the one under the jet: up from its top
		var on: bool = c.has_focus() or c.picked or c.hint > 0
		lines.draw_line(from, p, Color(Look.ACCENT if on else Look.EDGE, 0.95), 1.5, true)
		lines.draw_circle(p, 7.0, Look.TEXT)
		lines.draw_circle(p, 5.0, Look.ACCENT)


# --- the loadouts -----------------------------------------------------------------------------------------------------


## The LOADOUTS column: the mission's own (badge Mission), the pilot's saved ones (badge Saved, each with Delete), the
## one on the jet now in the accent's tint (no bar at its side: the user, A25 round 3); "+ Save this loadout" opens a
## name field.
func _loadouts() -> void:
	var col: VBoxContainer = fe._vbox(self, 10)
	col.name = "Loadouts"
	fe._place(col, 68, -1, 112, 0)
	col.custom_minimum_size.x = 310
	col.offset_right = col.offset_left + 310
	var h3: Label = fe._label(col, s("lo_loadouts").to_upper(), "H3")
	h3.add_theme_font_size_override("font_size", 19)
	var group := ButtonGroup.new()
	var mine := _slots_of(now)
	_row(col, group, "Mission", fe.title_of(m), s("lo_mission"), "", mine == _slots_of(""), func(): set_loadout(""))
	if not fixed:
		var saved = JSON.parse_string(IafPilotLog.saved_loadouts(Settings.records_db(), Settings.pilot(), unit))
		for e in saved if saved is Array else []:
			var lo := JSON.stringify(e.stations)
			var on := mine == _slots_of(lo)
			var row := _row(
				col, group, "Saved%d" % int(e.id), str(e.name), s("lo_saved"), lo, on, func(): set_loadout(lo)
			)
			var del: Button = fe._button(row, "×", "CrumbLink", func(): ask_delete(int(e.id), str(e.name)))
			del.name = "Delete%d" % int(e.id)
			del.tooltip_text = s("lo_delete")
			del.add_theme_font_size_override("font_size", 28)
			del.custom_minimum_size.x = DELETE_W
			del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var save: Button = fe._button(col, s("lo_save"), "CrumbLink", open_name)
		save.name = "SaveLoadout"
		save.alignment = HORIZONTAL_ALIGNMENT_LEFT
		save.add_theme_color_override("font_color", Look.ACCENT_TEXT)
		# A load that cannot be employed (a laser bomb with no pod) is not saved (the user, 17 Nov: "don't allow to
		# save presetting with laser that doesn't have it"): Save off, the footer's line says what is missing.
		var need: String = fe.need_text(a)
		save.disabled = need != ""
		save.tooltip_text = need
		var form: HBoxContainer = fe._hbox(col, 8)
		form.name = "NameForm"
		form.visible = false
		var field := LineEdit.new()
		field.name = "LoadoutName"
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.placeholder_text = s("lo_name")
		field.add_theme_font_size_override("font_size", 20)
		field.text_submitted.connect(func(_t): save_named())
		field.gui_input.connect(_field_keys)
		form.add_child(field)
		fe._button(form, s("save"), "Secondary", save_named).name = "SaveName"
		form.get_child(1).custom_minimum_size = Vector2(0, 48)


## One loadout's row: the toggle (its name, the badge, the stores in short) and, for a saved one, Delete beside it.
func _row(
	col: Control, group: ButtonGroup, id: String, title: String, badge: String, lo: String, on: bool, pick_it: Callable
) -> HBoxContainer:
	var row: HBoxContainer = fe._hbox(col, 4)
	var b := Button.new()
	b.name = "Loadout" + id
	b.theme_type_variation = "JetRow"
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = on
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Every row framed by a thin line; the one on the jet filled in the accent's tint, no bar at its side.
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := Color(Look.ACCENT, 0.22) if k.begins_with("pressed") or k == "hover_pressed" else Color(0, 0, 0, 0)
		if k == "hover":
			fill = Color(Look.ACCENT, 0.1)
		b.add_theme_stylebox_override(k, Look.box(fill, Look.LINE, 1, 6, Vector2.ZERO))
	b.disabled = fixed and id != "Mission"
	row.add_child(b)
	var v: VBoxContainer = fe._vbox(fe._margin(b, 18, 12), 2)
	v.get_parent().set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top: HBoxContainer = fe._hbox(v, 8)
	var name_l: Label = fe._label(top, title, "Strong")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var chip: Label = fe._chip(top, badge, id == "Mission")
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_stylebox_override(
		"normal", Look.box(Color(0, 0, 0, 0), Look.ACCENT if id == "Mission" else Look.EDGE, 1, 10, Vector2(9, 1))
	)
	var sum: Label = fe._label(v, summary(lo), "Small")
	sum.name = "Summary"
	sum.add_theme_font_size_override("font_size", 16)
	sum.clip_text = true
	sum.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = "%s\n%s" % [title, sum.text]
	for c in b.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(pick_it)
	if id == "Mission" and not fixed:
		fe._spacer_px(row, 0).custom_minimum_size.x = DELETE_W  # the saved rows' Delete column: every row one width
	return row


## "4 × AIM-9M · 2 × 370 gal tank": the stores of loadout `lo` ("" the mission's) by store, in station order.
func summary(lo: String) -> String:
	var parts := []
	for e in fe.arming(m, lo).get("stores", []):
		if not e.get("stations", []).is_empty():
			parts.append("%d × %s" % [int(e.count), fe.short_store(str(e.weapon))])
	return " · ".join(parts) if not parts.is_empty() else s("lo_clean")


## The stations of loadout `lo` as the record allows them (the arming's slots), to tell which row is on the jet.
func _slots_of(lo: String) -> Dictionary:
	var out := {}
	var sl = fe.arming(m, lo).get("slots", {})
	for k in sl if sl is Dictionary else {}:
		out[k] = [str(sl[k].id), int(sl[k].count)]
	return out


func _picked_row() -> Control:
	for b in find_children("Loadout*", "Button", true, false):
		if b.button_pressed:
			return b
	return find_child("LoadoutMission", true, false)


## "+ Save this loadout": the name field in its place, a name offered ("My loadout, 14 Nov 2026") and selected.
func open_name() -> void:
	var save: Control = find_child("SaveLoadout", true, false)
	var form: Control = find_child("NameForm", true, false)
	var field: LineEdit = find_child("LoadoutName", true, false)
	save.visible = false
	form.visible = true
	field.text = s("lo_default_name") % fe.day_text(Time.get_datetime_string_from_system())
	_focus_order()
	field.grab_focus()
	field.select_all()


## Esc in the name field closes it, the link back in its place.
func _field_keys(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_name()


func close_name() -> bool:
	var form: Control = find_child("NameForm", true, false)
	if form == null or not form.visible:
		return false
	form.visible = false
	var save: Control = find_child("SaveLoadout", true, false)
	save.visible = true
	_focus_order()
	save.grab_focus()
	return true


## Saves the loadout on the jet under the name typed (the same name again replaces that one); an empty name keeps
## the field open.
func save_named() -> void:
	var field: LineEdit = find_child("LoadoutName", true, false)
	if fe.need_text(a) != "":
		return  # the pod rule (weapons.md §7.1): a load that cannot be employed is never stored
	var st := {}
	var slots: Dictionary = a.get("slots", {}) if a.get("slots") is Dictionary else {}
	for k in slots:
		st[k] = {"id": str(slots[k].id), "count": int(slots[k].count)}
	var lo := JSON.stringify(st)
	var id: int = IafPilotLog.save_loadout(Settings.records_db(), Settings.pilot(), unit, field.text, lo)
	if id < 0:
		field.grab_focus()
		return
	_refocus = "Loadout" + "Saved%d" % id
	fe.show_page("arming")


func ask_delete(id: int, title: String) -> void:
	fe.modal(
		s("lo_delete_q") % title,
		"",
		s("lo_delete"),
		func():
			IafPilotLog.delete_saved_loadout(Settings.records_db(), Settings.pilot(), id)
			fe.show_page("arming")
	)


# --- the weight and the stores ----------------------------------------------------------------------------------------


## The TAKE-OFF WEIGHT panel at the inline end: the figure (red over the maximum), the bar and its share of the
## maximum, the wings' balance (Left / Right as the pilot sits; amber past the record's limit), fuel with the tanks',
## gun rounds, chaff / flares, then the STORES.
func _weight() -> void:
	var panel := PanelContainer.new()
	panel.name = "Weight"
	add_child(panel)
	fe._place(panel, -1, 68, 112, 0)
	panel.custom_minimum_size.x = 316
	panel.offset_left = -68 - 316
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var v: VBoxContainer = fe._vbox(fe._margin(panel, 22, 20), 8)
	var h3: Label = fe._label(v, s("takeoff_weight").to_upper(), "H3")
	h3.add_theme_font_size_override("font_size", 19)
	var over := bool(a.get("over", false))
	var tk := float(a.get("takeoff_kg", 0.0)) if a.get("takeoff_kg") != null else 0.0
	var mx := float(a.get("max_takeoff_kg", 0.0)) if a.get("max_takeoff_kg") != null else 0.0
	var fig: HBoxContainer = fe._fact(v, fe.kg_text(tk), s("kg"))
	fig.name = "TakeoffWeight"
	for l in fig.get_children():
		l.add_theme_font_size_override("font_size", 36)
		if over:
			l.add_theme_color_override("font_color", Look.WARN)
	if mx > 0.0:
		var bar := ProgressBar.new()
		bar.name = "WeightBar"
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.max_value = mx
		bar.value = minf(tk, mx)
		if over:
			bar.add_theme_stylebox_override("fill", Look.box(Look.WARN, Look.WARN, 0, 4, Vector2(0, 3)))
		v.add_child(bar)
		var pct: Label = fe._label(v, s("lo_of_max") % [roundi(100.0 * tk / mx), fe.kg_text(mx)], "Small")
		pct.name = "OfMax"
		if over:
			pct.add_theme_color_override("font_color", Look.WARN)
	_balance(v)
	var grid := GridContainer.new()
	grid.name = "Figures"
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var lf: Dictionary = a.get("loadout", {}) if a.get("loadout") is Dictionary else {}
	var rows := []
	if a.get("fuel_kg") != null:
		rows.append(["fuel", "%s %s" % [fe.kg_text(float(a.fuel_kg) + float(a.get("tank_fuel_kg", 0.0))), s("kg")]])
	rows.append(["rounds", str(int(lf.get("20mm", 0)))])
	rows.append(["lo_chaff_flares", "%d / %d" % [int(lf.get("chaff", 0)), int(lf.get("flare", 0))]])
	for r in rows:
		var k: Label = fe._label(grid, s(r[0]), "Muted")
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val: Label = fe._label(grid, r[1], "Strong")
		val.name = "Fig_" + r[0]
		val.text_direction = Control.TEXT_DIRECTION_LTR if r[0] != "fuel" else Control.TEXT_DIRECTION_AUTO
	fe._spacer_px(v, 6)
	_stores(v)


## The wings' balance: a track from Left to Right (as the pilot sits, in both languages), its middle marked, the
## marker where the stores lean; under it "Wings balanced" or which wing is heavier and by how much.
func _balance(v: VBoxContainer) -> void:
	var row: HBoxContainer = fe._hbox(v, 10)
	row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	fe._label(row, s("lo_left"), "Small").add_theme_font_size_override("font_size", 16)
	var bad := bool(a.get("imbalanced", false))
	var at := clampf(float(a.get("balance", 0.0)), -1.0, 1.0)
	var gauge := Control.new()
	gauge.name = "Balance"
	gauge.custom_minimum_size = Vector2(0, 20)
	gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge.draw.connect(
		func():
			var y := gauge.size.y / 2.0
			gauge.draw_rect(Rect2(0, y - 3, gauge.size.x, 6), Look.LINE)
			gauge.draw_rect(Rect2(gauge.size.x / 2.0 - 1, y - 6, 2, 12), Look.EDGE)
			var x := gauge.size.x / 2.0 * (1.0 + at)
			gauge.draw_rect(Rect2(x - 2, y - 9, 4, 18), Look.AMBER if bad else Look.ACCENT_TEXT)
	)
	row.add_child(gauge)
	fe._label(row, s("lo_right"), "Small").add_theme_font_size_override("font_size", 16)
	var kg := float(a.get("imbalance_kg", 0.0))
	var t := s("lo_balanced")
	if absf(kg) >= 1.0:
		t = s("lo_heavier_left" if kg > 0.0 else "lo_heavier_right") % fe.kg_text(absf(kg))
	var cap: Label = fe._label(v, t, "Small")
	cap.name = "BalanceText"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if bad:
		cap.add_theme_color_override("font_color", Look.AMBER)
	if not fixed:
		var mir := CheckButton.new()
		mir.name = "Mirror"
		mir.text = s("lo_mirror")
		mir.button_pressed = mirror
		mir.add_theme_font_size_override("font_size", 18)
		mir.toggled.connect(_set_mirror)
		v.add_child(mir)


func _set_mirror(on: bool) -> void:
	mirror = on


## The STORES the jet may carry (the unit record's `inventory`), two to a row, each a framed name that drags to a
## callout (greyed without a model of ours yet); a store dragged from a callout onto them goes back. The keyboard's
## "Empty" entry at its top shows while a callout is picked.
func _stores(v: VBoxContainer) -> void:
	var shelf := ArmingDrawing.Shelf.new()
	shelf.name = "Inventory"
	shelf.read_only = fixed
	shelf.add_theme_constant_override("separation", 10)
	shelf.on_drop = func(data: Dictionary, to: String) -> bool: return drop(data, to)
	v.add_child(shelf)
	var h3: Label = fe._label(shelf, s("lo_stores").to_upper(), "H3")
	h3.add_theme_font_size_override("font_size", 19)
	var grid := GridContainer.new()
	grid.name = "StoreGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 14)
	shelf.add_child(grid)
	var choose := func(id: String): choose_store(id)
	var empty := ArmingDrawing.Item.new()
	empty.on_choose = choose
	empty.setup("", s("arm_empty"), "")
	empty.visible = false
	grid.add_child(empty)
	for e in a.get("inventory", []):
		var it := ArmingDrawing.Item.new()
		it.read_only = fixed
		it.flyable = bool(e.get("ready", true))
		it.on_choose = choose
		var n := "× %d" % int(e.left) if e.get("left") != null else ""
		it.setup(str(e.id), fe.short_store(str(e.id)), n)
		it.tooltip_text = s("store_" + str(e.id))
		it.custom_minimum_size.x = 116
		grid.add_child(it)


# --- the editing ------------------------------------------------------------------------------------------------------


## A store dropped (data {store, from: a station, "" the inventory}) on station `to` ("" the inventory): the loadout
## changed as the record allows (IafBriefing put / shift / take; its mirror station too while `mirror` is on), stored
## and shown; false when refused.
func drop(data: Dictionary, to: String) -> bool:
	var pair := mirror
	var u: String = fe._unit_file(m)
	var from := str(data.get("from", ""))
	var lo := ""
	if to == "":
		lo = IafBriefing.take(u, _shown(), int(from), pair) if from != "" else ""
	elif from == "":
		lo = IafBriefing.put(u, _shown(), int(to), str(data.store), pair)
	elif from != to:
		lo = IafBriefing.shift(u, _shown(), int(from), int(to), pair)
	if lo == "":
		return from == to and from != ""  # dropped where it was: nothing to refuse
	var fo := get_viewport().gui_get_focus_owner()
	_refocus = ("Slot" + pick) if pick != "" else (str(fo.name) if fo != null else "")
	set_loadout.call_deferred(lo)
	return true


## The loadout on the screen as JSON text: the pilot's, else the mission's own ("" the record's).
func _shown() -> String:
	return now if now != "" else fe.Fly.own_loadout(m)


## Stores the loadout `lo` ("" the mission's) as the pilot's for the jet and makes the screen again with it.
func set_loadout(lo: String) -> void:
	IafPilotLog.set_loadout(Settings.records_db(), Settings.pilot(), unit, lo)
	if _refocus == "":
		var fo := get_viewport().gui_get_focus_owner()
		_refocus = str(fo.name) if fo != null else ""
	fe.show_page("arming")


## A click on a rack's "×n" badge: one store fewer, from one back to full (its mirror's too while `mirror` is on).
func cycle(st: String) -> void:
	var lo: String = IafBriefing.cycle(fe._unit_file(m), _shown(), int(st), mirror)
	if lo != "":
		_refocus = "Slot" + st
		set_loadout(lo)


## Enter on a callout: picked, the focus on the first store the station takes ("Empty" to take its store off); Enter
## there hangs it (choose_store), Esc leaves the callout as it was.
func pick_station(st: String) -> void:
	unpick()
	pick = st
	callouts[st].picked = true
	callouts[st].queue_redraw()
	lines.queue_redraw()
	var empty: Control = find_child("ItemEmpty", true, false)
	empty.visible = not callouts[st].store.is_empty()
	var takes: Array = stage.allowed.get(st, [])
	var first: Control = empty if empty.visible else null
	for c in find_child("StoreGrid", true, false).get_children():
		if c is ArmingDrawing.Item and c.id in takes and c.flyable:
			first = c
			break
	if first != null:
		first.grab_focus()


## Leaves the picked callout as it was (Esc); false when none was picked.
func unpick() -> bool:
	if pick == "" or not callouts.has(pick):
		return false
	var c: Control = callouts[pick]
	pick = ""
	find_child("ItemEmpty", true, false).visible = false
	c.picked = false
	c.queue_redraw()
	c.grab_focus()
	return true


## Enter on a store: hung on the callout picked (its mirror too while `mirror` is on), or with "Empty" its store
## off; the store already on its rack: the next count. A station that does not take it shakes.
func choose_store(id: String) -> void:
	if pick == "":
		return
	var c: Control = callouts[pick]
	if c.store.size() > 4 and str(c.store[0]) == id and int(c.store[4]) > 1:
		cycle(pick)
		return
	var data := {"store": id, "from": ""} if id != "" else {"store": "", "from": pick}
	stage.dropped(data, pick if id != "" else "")


## Esc on this screen: the name field closed, else the picked callout left; false when neither (the screen goes back).
func escape() -> bool:
	return close_name() or unpick()


## Tab through the loadouts, Save (or the name field and its Save while open), the callouts by station number from the
## highest down, Mirror, the stores, Reset, Briefing and Fly.
func _focus_order() -> void:
	var order: Array = find_children("Loadout*", "Button", true, false).filter(func(b): return not b.disabled)
	for d in find_children("Delete*", "Button", true, false):
		order.insert(order.find(find_child("LoadoutSaved" + str(d.name).trim_prefix("Delete"), true, false)) + 1, d)
	var save: Control = find_child("SaveLoadout", true, false)
	if save != null:
		var form: Control = find_child("NameForm", true, false)
		if form.visible:
			order.append_array([find_child("LoadoutName", true, false), find_child("SaveName", true, false)])
		else:
			order.append(save)
	var cs := callouts.keys()
	cs.sort_custom(func(x, y): return int(x) > int(y))  # 9 .. 1: the left column (the right wing) first
	if not fixed:
		order.append_array(cs.map(func(k): return callouts[k]))
		order.append(find_child("Mirror", true, false))
		order.append_array(
			find_child("StoreGrid", true, false).get_children().filter(
				func(c): return c.focus_mode != Control.FOCUS_NONE and c.visible
			)
		)
	for n in ["ArmReset", "ToBriefing", "Fly"]:
		var b: Control = fe.find_child(n, true, false)
		if b != null and not (b is Button and b.disabled):
			order.append(b)
	fe._chain(order)
