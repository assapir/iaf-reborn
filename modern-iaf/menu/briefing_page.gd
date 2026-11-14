# The mission briefing, map first (modern-iaf/docs/front-end.md §10; the approved mock r3_briefing, the user's A25
# round 3, 2026-11-13): the map fills the screen (briefing_map.gd); over it at the inline start the mission card (the
# missions as tabs with their pass chips, the title, the facts, the objectives, the Arming summary with Edit, Back and
# Fly), at the inline end the map's chips (Taxi route, Labels, Photo, Zoom) and the ORDER OF ACTIONS card (the steps,
# numbered as the map's pins, each with its key as bound; a step opens to its state to wait for and its switch's
# picture). `build` lays it out on the front end `fe` (front_end.gd), whose building blocks it uses.
extends RefCounted

const Look := preload("look.gd")
const BriefingMap := preload("briefing_map.gd")
## The card's width and the screen's edge (px on the 1920 × 1080 canvas, the mock's).
const CARD_W := 600
const ORDER_W := 640
const EDGE := 68
## The map's chips' row from the top, and the gap kept between the cards and the map's opening view.
const CHIPS_TOP := 120
const GAP := 32


## The briefing of mission `m` on `fe`; the controls named for the tests and the focus (Mission<n>, ArmEdit, Back,
## Fly, MapTaxi, MapLabels, MapPhoto, ZoomIn, ZoomOut, PageMap, Step<n>).
static func build(fe: Control, m: Dictionary) -> void:
	var map := _map(fe, m)
	var card := _card(fe, m)
	var chips := _chips(fe, map)
	var order := _order(fe, m)
	# The map opens on the base and the route in the room between the cards, under the chips.
	var aim := func():
		var r := map.get_global_rect()
		var c := card.get_global_rect()
		var o := order.get_global_rect()
		# The order card's top with its steps closed: a step opened grows it, and the view stays where it is.
		for more in order.find_children("More", "", true, false):
			if more.visible:
				o.position.y += more.size.y + 6.0
		var rtl: bool = fe.he()
		var x0: float = (c.end.x + GAP) if not rtl else (r.position.x + GAP)
		var x1: float = (r.end.x - GAP) if not rtl else (c.position.x - GAP)
		var top := chips.get_global_rect().end.y + 16.0
		map.aim(Rect2(x0 - r.position.x, top - r.position.y, x1 - x0, o.position.y - GAP - top))
		# The scale bar and the credit at the bottom of the room beside the card.
		map.scale_at = Vector2((x0 - r.position.x) if not rtl else (x1 - r.position.x), r.size.y - 70.0)
	for n in [map, card, order]:
		n.resized.connect(aim)
	aim.call_deferred()  # the cards are sized already: their first resized has gone
	var credit: Label = fe._label(fe, fe.s("map_credit"), "Small")
	credit.name = "Credit"
	credit.add_theme_font_size_override("font_size", 16)
	# Readable over a pale ground (the photo off): a dark edge round the letters.
	credit.add_theme_constant_override("outline_size", 6)
	credit.add_theme_color_override("font_outline_color", Color(Look.BG, 0.85))
	credit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fe._place(credit, CARD_W + EDGE + GAP, -1, -44, 0)
	_focus_order(fe, card, chips, order, map)


## The map over the whole screen, under the header's shade.
static func _map(fe: Control, m: Dictionary) -> Control:
	var map := BriefingMap.new()
	map.name = "PageMap"
	var heading = fe.briefing_map(m, 1.0).get("heading") if m.get("runway") is String else null
	var base := str(m.get("start", {}).get("base", "")).to_lower().replace(" ", "_")
	map.base_label = fe.s("base_" + base)
	map.runway_label = fe._ltr(fe.runway_text(m.runway, heading)) if m.get("runway") is String else ""
	map.km = fe.s("km")
	map.metres = fe.s("m")
	map.hebrew = fe.he()
	var rwy: String = fe._ltr(str(m.get("runway", "")))
	map.pin_names = {
		"start": fe.s("pin_start"),
		"hold": fe.s("pin_hold") % rwy,
		"lineup": (fe.s("pin_lineup") % roundi(float(heading))) if heading != null else fe.s("pin_start"),
	}
	map.steps_text = fe.s("pin_steps")
	map.source = func(a: float) -> Dictionary: return fe.briefing_map(m, a, true)
	# Added once set up: its first size loads the map.
	fe.add_child(map)
	fe.move_child(map, 1)  # over the background, under the bars
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return map


## The mission card at the inline start.
static func _card(fe: Control, m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Briefing"
	card.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.94), Look.LINE, 1, 6, Vector2(32, 28)))
	fe.add_child(card)
	fe._place(card, EDGE, -1, 112, 0)
	card.offset_right = card.offset_left + CARD_W
	var v: VBoxContainer = fe._vbox(card, 18)
	# The missions as tabs: the number, the title and the last result's chip.
	var tabs: HBoxContainer = fe._hbox(v, 10)
	tabs.name = "Missions"
	var group := ButtonGroup.new()
	for i in fe.missions.size():
		var mi: Dictionary = fe.missions[i]
		var b := Button.new()
		b.name = "Mission%d" % (i + 1)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == fe.mission_i
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_contents = true
		b.tooltip_text = fe.title_of(mi)
		var pad := Vector2(14, 10)
		b.add_theme_stylebox_override("normal", Look.box(Color(0, 0, 0, 0), Look.LINE, 1, 5, pad))
		b.add_theme_stylebox_override("hover", Look.box(Look.RAISED, Look.EDGE, 1, 5, pad))
		for k in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(k, Look.box(Look.RAISED, Look.ACCENT, 1, 5, pad))
		b.add_theme_stylebox_override("focus", Look.box(Color(0, 0, 0, 0), Look.ACCENT_TEXT, 2, 5, pad))
		tabs.add_child(b)
		var mm: MarginContainer = fe._margin(b, 14, 10)
		mm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row: HBoxContainer = fe._hbox(mm, 12)
		var n: Label = fe._label(row, str(i + 1), "Num")
		n.add_theme_font_size_override("font_size", 28)
		fe._label(row, fe.title_of(mi), "Row").add_theme_font_size_override("font_size", 21)
		var st: int = fe.status(mi)
		if st >= 0:
			var chip_text: String = fe.s("pass" if st == 1 else "fail")
			var best: float = fe.best_time(mi)
			if st == 1 and best > 0:
				chip_text += " · " + fe.clock(best)
			fe._chip(row, chip_text, st == 1)
		for c in b.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.custom_minimum_size.y = mm.get_combined_minimum_size().y
		b.pressed.connect(fe._pick_mission.bind(i))
		if i == fe.mission_i:
			fe._focus = b
	# The title and the line under it: what the mission is and the jet's squadron.
	var tv: VBoxContainer = fe._vbox(v, 4)
	fe._label(tv, fe.title_of(m), "H1")
	var j: Dictionary = fe.jet_of(m)
	var sub: Label = fe._text(
		tv, "%s %s · %s" % [fe.s("desc_" + fe.kind(m)), fe.full_name(j), fe.subtitle(j, false)], "Sub"
	)
	sub.name = "Subtitle"
	_facts(fe, v, m)
	_objectives(fe, v, m)
	_arming(fe, v, m)
	var foot: HBoxContainer = fe._hbox(v, 12)
	var back: Button = fe._button(foot, fe.s("back"), "Secondary", func(): fe.show_page("hangar"))
	back.name = "Back"
	back.custom_minimum_size = Vector2(142, 64)
	var fly: Button = fe._button(foot, fe.s("fly"), "Fly", func(): fe.fly_mission(m))
	fly.name = "Fly"
	fly.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly.custom_minimum_size.y = 76
	fly.disabled = bool(fe.arming(m, fe.mission_loadout(m)).get("blocked", false))
	return card


## The facts: the runway with its heading (a take-off), the time, the wind, the time allowed.
static func _facts(fe: Control, parent: Control, m: Dictionary) -> void:
	var facts: HBoxContainer = fe._hbox(parent, 30)
	facts.name = "Facts"
	var heading = fe.briefing_map(m, 1.0).get("heading") if m.get("runway") is String else null
	var rows := []
	if m.get("runway") is String:
		rows.append(["runway", fe.runway_text(m.runway, heading), ""])
	rows.append(["time", fe.military_time(str(m.get("time", ""))), ""])
	rows.append(["wind", fe.wind_text(m), fe.s("kt")])
	rows.append(["time_allowed", str(int(float(m.training.get("time_budget_s", 0)) / 60.0)), fe.s("min")])
	for f in rows:
		var fv: VBoxContainer = fe._vbox(facts, 0)
		fe._label(fv, fe.s(f[0]), "Small")
		fe._fact(fv, f[1], f[2])


## OBJECTIVES: what the scorer judges, each beside an empty box (the debrief ticks them).
static func _objectives(fe: Control, parent: Control, m: Dictionary) -> void:
	var ov: VBoxContainer = fe._vbox(parent, 8)
	_heading(fe, ov, fe.s("objectives"))
	var objs: VBoxContainer = fe._vbox(ov, 8)
	objs.name = "Objectives"
	var budget: String = fe.s("minutes") % int(float(m.training.get("time_budget_s", 0)) / 60.0)
	for o in fe.objectives(m, budget):
		var row: HBoxContainer = fe._hbox(objs, 12)
		var box := Panel.new()
		box.custom_minimum_size = Vector2(18, 18)
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), Look.ACCENT, 2, 2, Vector2.ZERO))
		var hold: MarginContainer = fe._margin(row, 0, 0)
		hold.add_theme_constant_override("margin_top", 5)
		hold.add_child(box)
		fe._text(row, o, "")


## The Arming summary: the stores on the jet, the take-off weight (red over the maximum) and Edit, which opens the
## loadout screen (the page "arming").
static func _arming(fe: Control, parent: Control, m: Dictionary) -> void:
	var a: Dictionary = fe.arming(m, fe.mission_loadout(m))
	var box := PanelContainer.new()
	box.name = "ArmingSummary"
	box.add_theme_stylebox_override("panel", Look.box(Color(0, 0, 0, 0), Look.LINE, 1, 5, Vector2(16, 12)))
	parent.add_child(box)
	var h: HBoxContainer = fe._hbox(box, 18)
	var left: VBoxContainer = fe._vbox(h, 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading(fe, left, fe.s("tab_arming"))
	var parts := []
	for st in a.get("stores", []):
		if not (st.get("stations", []) as Array).is_empty():
			parts.append("%d × %s" % [int(st.count), fe.short_store(str(st.weapon))])
	var stores: Label = fe._text(left, " · ".join(parts) if not parts.is_empty() else fe.s("arm_empty"), "")
	stores.name = "ArmingStores"
	if a.get("takeoff_kg") != null:
		var wv: VBoxContainer = fe._vbox(h, 0)
		wv.name = "Fact_takeoff_weight"
		wv.size_flags_vertical = Control.SIZE_SHRINK_END
		var cap: Label = fe._label(wv, fe.s("takeoff_weight"), "Small")
		var fact: HBoxContainer = fe._fact(wv, fe.kg_text(a.takeoff_kg), fe.s("kg"))
		if bool(a.get("over", false)):
			for l in fact.get_children() + [cap]:
				l.add_theme_color_override("font_color", Look.WARN)
	var edit: Button = fe._button(h, fe.s("edit"), "CrumbLink", func(): fe.show_page("arming"))
	edit.name = "ArmEdit"
	edit.add_theme_color_override("font_color", Look.ACCENT_TEXT)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## A card's small heading: the accent's text colour, in capitals where the script has them.
static func _heading(fe: Control, parent: Control, t: String) -> Label:
	var l: Label = fe._label(parent, t.to_upper(), "H3")
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Look.ACCENT_TEXT)
	return l


## The map's chips at the top inline end: Taxi route, Labels and Photo turn their layer on and off; Zoom + / −.
static func _chips(fe: Control, map: Control) -> Control:
	var row: HBoxContainer = fe._hbox(fe, 10)
	row.name = "MapChips"
	var chips := [["MapTaxi", "map_taxi", "show_taxi"], ["MapLabels", "map_labels", "show_labels"]]
	chips.append(["MapPhoto", "map_photo", "show_photo"])
	for c in chips:
		var b := Button.new()
		b.name = c[0]
		b.text = fe.s(c[1])
		b.toggle_mode = true
		b.button_pressed = bool(map.get(c[2]))
		_pill(b)
		var prop: String = c[2]
		b.toggled.connect(func(on: bool): map.set(prop, on))
		row.add_child(b)
	var zoom := PanelContainer.new()
	zoom.add_theme_stylebox_override("panel", Look.box(Color(Look.BG, 0.85), Look.EDGE, 1, 22, Vector2(14, 0)))
	row.add_child(zoom)
	var zh: HBoxContainer = fe._hbox(zoom, 2)
	var zl: Label = fe._label(zh, fe.s("map_zoom"), "Row")
	zl.add_theme_font_size_override("font_size", 19)
	zl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for z in [["ZoomIn", "+", BriefingMap.ZOOM_STEP], ["ZoomOut", "−", 1.0 / BriefingMap.ZOOM_STEP]]:
		var b: Button = fe._button(zh, z[1], "CrumbLink", func(): map.zoom_view(z[2]))
		b.name = z[0]
		b.add_theme_font_size_override("font_size", 22)
		b.tooltip_text = fe.s("map_zoom")
	fe._place(row, -1, EDGE, CHIPS_TOP, 0)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return row


## A chip's look: a pill, filled in the accent's tint while on.
static func _pill(b: Button) -> void:
	var pad := Vector2(18, 7)
	b.add_theme_stylebox_override("normal", Look.box(Color(Look.BG, 0.85), Look.EDGE, 1, 22, pad))
	b.add_theme_stylebox_override("hover", Look.box(Look.RAISED, Look.EDGE, 1, 22, pad))
	for k in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, Look.box(Color(Look.ACCENT, 0.3), Look.ACCENT, 1, 22, pad))
	b.add_theme_stylebox_override("focus", Look.box(Color(0, 0, 0, 0), Look.ACCENT_TEXT, 2, 22, pad))
	b.add_theme_font_size_override("font_size", 19)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Look.TEXT)


## ORDER OF ACTIONS at the bottom inline end: a row per step, its number (the map's pins'), the step and its key as
## bound; the row with the focus (a click, the arrows, Tab) opens to the state to wait for and, on a start-up, the
## switch's picture cut from the 3D cockpit with its name and place.
static func _order(fe: Control, m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Order"
	card.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.94), Look.LINE, 1, 6, Vector2(24, 22)))
	fe.add_child(card)
	var v: VBoxContainer = fe._vbox(card, 0)
	var head := _heading(fe, v, fe.s("order"))
	head.custom_minimum_size.y = 40
	var steps: VBoxContainer = fe._vbox(v, 0)
	steps.name = "Steps"
	var list: Array = fe.briefing_steps(m)
	for i in list.size():
		steps.add_child(_step(fe, i, list[i]))
	fe._place(card, -1, EDGE, -40, 0)
	card.offset_left = card.offset_right - ORDER_W
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Its height its content's, grown upward from the bottom (its wrapped lines are measured once it has its width).
	card.offset_bottom = -40
	card.offset_top = -40
	return card


static func _step(fe: Control, i: int, st: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "Step%d" % (i + 1)
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var line := Look.box(Color(0, 0, 0, 0), Look.LINE, 0, 0, Vector2(4, 8))
	line.border_width_top = 1
	var on := Look.box(Color(Look.ACCENT, 0.12), Look.ACCENT_TEXT, 2, 4, Vector2(4, 8))
	row.add_theme_stylebox_override("panel", line)
	var v: VBoxContainer = fe._vbox(row, 6)
	var h: HBoxContainer = fe._hbox(v, 16)
	var n: Label = fe._label(h, str(i + 1), "Strong")
	n.add_theme_color_override("font_color", Look.ACCENT)
	n.custom_minimum_size.x = 22
	n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fe._text(h, st.text, "")
	var cap: Control = fe._keycap(h, st.key)
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# The step opened: the state to wait for, the switch's picture with its name and place (else that in words).
	var more: HBoxContainer = fe._hbox(v, 16)
	more.name = "More"
	more.visible = false
	fe._spacer_px(more, 0).custom_minimum_size.x = 22
	var words: VBoxContainer = fe._vbox(more, 4)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if st.wait != "":
		var w: Label = fe._text(words, st.wait, "Small")
		w.name = "Wait"
		w.add_theme_color_override("font_color", Look.ACCENT_TEXT)
	if st.where != "":
		fe._text(words, st.where, "Small").name = "Where"
	var crop: Texture2D = fe._texture(ProjectSettings.globalize_path(st.crop)) if st.crop != "" else null
	if crop != null:
		var pic := TextureRect.new()
		pic.name = "Switch%d" % (i + 1)
		pic.texture = crop
		pic.tooltip_text = st.where
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(210, 140)
		more.add_child(pic)
	var has_more: bool = st.wait != "" or st.where != "" or crop != null
	row.tooltip_text = st.where
	row.focus_entered.connect(
		func():
			row.add_theme_stylebox_override("panel", on)
			for r in row.get_parent().get_children():
				r.find_child("More", true, false).visible = r == row and has_more
	)
	row.focus_exited.connect(func(): row.add_theme_stylebox_override("panel", line))
	row.gui_input.connect(
		func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				row.grab_focus()
	)
	for c in row.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_PASS if c is TextureRect else Control.MOUSE_FILTER_IGNORE
	return row


## Tab and the arrows: the missions, Edit, Back, Fly; on to the chips, the map, the steps; round. Down from a mission
## reaches Edit, then Fly; across from Fly the chips, down from them the map and the steps.
static func _focus_order(fe: Control, card: Control, chips: Control, order: Control, map: Control) -> void:
	var missions: Array = card.find_child("Missions", true, false).get_children()
	var edit: Control = card.find_child("ArmEdit", true, false)
	var back: Control = card.find_child("Back", true, false)
	var fly: Button = card.find_child("Fly", true, false)
	var chip_list: Array = chips.find_children("*", "Button", true, false)
	var steps: Array = order.find_child("Steps", true, false).get_children()
	var ring: Array = missions + [edit, back] + ([fly] if not fly.disabled else []) + chip_list + [map] + steps
	fe._chain(ring)
	var start := "right" if fe.he() else "left"
	var end := "left" if fe.he() else "right"
	var last_card: Control = fly if not fly.disabled else back
	for b in missions:
		fe._nb(b, {"bottom": edit, "top": b})
	fe._nb(missions[0], {start: missions[0]})
	fe._nb(missions[-1], {end: chip_list[0]})
	fe._nb(edit, {"top": missions[0], "bottom": last_card, start: edit, end: chip_list[0]})
	fe._nb(back, {"top": edit, "bottom": back, start: back, end: last_card})
	fe._nb(fly, {"top": edit, "bottom": fly, start: back, end: steps[0] if not steps.is_empty() else fly})
	fe._nb(chip_list[0], {start: missions[-1]})
	fe._nb(chip_list[-1], {end: chip_list[-1]})
	for c in chip_list:
		fe._nb(c, {"top": c, "bottom": map})
	if not steps.is_empty():
		fe._nb(steps[0], {"top": chip_list[0]})
		fe._nb(steps[-1], {"bottom": steps[-1]})
		for s in steps:
			fe._nb(s, {start: last_card, end: s})
