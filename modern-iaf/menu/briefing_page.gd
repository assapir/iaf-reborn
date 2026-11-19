# The mission briefing, map first (modern-iaf/docs/front-end.md §10; the approved mock r3_briefing, the user's A25 round
# 3, 2026-11-13): the map fills the screen (briefing_map.gd); over it at the inline start the mission card (the title, a
# mission of several flights its FLIGHTS tabs, the facts, the objectives, the Arming summary with Edit, Back to the
# section's list, Arming and Fly), at the inline end the map's chips (Labels, Photo, Zoom) and the mission's text (the
# user's note, 2026-11-15: what you will learn, then how and what to do, in prose with the keys as bound, its paragraphs
# numbered as the map's pins; a start-up's switch pictures under their paragraphs). `build` lays it out on the front end
# `fe` (front_end.gd), whose building blocks it uses.
extends RefCounted

const Look := preload("look.gd")
const BriefingMap := preload("briefing_map.gd")
const PrePanel := preload("pre_panel.gd")
## The card's width and the screen's edge (px on the 1920 × 1080 canvas, the mock's).
const CARD_W := 600
const TEXT_W := 640
const EDGE := 68
## The map's chips' row from the top, and the gap kept between the cards and the map's opening view.
const CHIPS_TOP := 120
const GAP := 32
## The text card's top (under the chips) and the explanation's type size (readable at 1280 × 720: 15 px there).
const TEXT_TOP := 190
const TEXT_PX := 23


## The briefing of mission `m` on `fe`; the controls named for the tests and the focus (ArmEdit, Back,
## Arming, Fly, MapPre (a GPS store aboard: the PRE targets panel, PreTargets), MapLabels, MapPhoto, ZoomIn, ZoomOut,
## PageMap, Purpose, HowScroll, Para<n>; with several flights Flights, Flight_<callsign>, FlightDetail).
static func build(fe: Control, m: Dictionary) -> void:
	var map := _map(fe, m)
	var card := _card(fe, m, map)
	var chips := _chips(fe, map)
	var text := _text_card(fe, m)
	_pre_chip(fe, m, map, chips, text)
	# The map opens on the base and the route in the room between the cards, under the chips, over the scale bar.
	var aim := func():
		var r := map.get_global_rect()
		var c := card.get_global_rect()
		var o := text.get_global_rect()
		var rtl: bool = fe.he()
		var x0: float = (c.end.x + GAP) if not rtl else (o.end.x + GAP)
		var x1: float = (o.position.x - GAP) if not rtl else (c.position.x - GAP)
		var top := chips.get_global_rect().end.y + 16.0
		map.aim(Rect2(x0 - r.position.x, top - r.position.y, x1 - x0, r.end.y - 110.0 - top))
		# The scale bar and the credit at the bottom of the room beside the card.
		map.scale_at = Vector2((x0 - r.position.x) if not rtl else (x1 - r.position.x), r.size.y - 70.0)
	for n in [map, card, text]:
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
	_focus_order(fe, card, chips, text, map)


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
	map.source = func(a: float) -> Dictionary: return fe.briefing_map(m, a)
	map.layers_source = func(v: PackedFloat64Array, o: PackedFloat64Array, k: float) -> Dictionary:
		return fe.briefing_layers(m, v, o, k)
	map.theatre = fe.briefing_theatre()
	# Added once set up: its first size loads the map.
	fe.add_child(map)
	fe.move_child(map, 1)  # over the background, under the bars
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return map


## The mission card at the inline start.
static func _card(fe: Control, m: Dictionary, map: Control) -> Control:
	var card := PanelContainer.new()
	card.name = "Briefing"
	card.add_theme_stylebox_override("panel", Look.box(Color(Look.PANEL, 0.94), Look.LINE, 1, 6, Vector2(32, 28)))
	fe.add_child(card)
	fe._place(card, EDGE, -1, 112, 0)
	card.offset_right = card.offset_left + CARD_W
	var v: VBoxContainer = fe._vbox(card, 18)
	# The title and the line under it: what the mission is and the jet's squadron.
	var tv: VBoxContainer = fe._vbox(v, 4)
	fe._label(tv, fe.title_of(m), "H1")
	var j: Dictionary = fe.jet_of(m)
	var sub: Label = fe._text(
		tv, "%s %s · %s" % [fe.s("desc_" + fe.kind(m)), fe.full_name(j), fe.subtitle(j, false)], "Sub"
	)
	sub.name = "Subtitle"
	_flights(fe, v, m, map)
	_facts(fe, v, m)
	_objectives(fe, v, m)
	_arming(fe, v, m)
	var foot: HBoxContainer = fe._hbox(v, 12)
	var back: Button = fe._button(foot, fe.s("back"), "Secondary", func(): fe.show_page("section"))
	back.name = "Back"
	back.custom_minimum_size = Vector2(142, 64)
	_arming_button(fe, foot)
	var fly: Button = fe._button(foot, fe.s("fly"), "Fly", func(): fe.fly_mission(m))
	fly.name = "Fly"
	fly.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly.custom_minimum_size.y = 76
	fly.disabled = bool(fe.arming(m, fe.mission_loadout(m)).get("blocked", false))
	return card


## Arming beside Fly (the user's note, 2026-11-15: the way to the loadout screen was unclear): the page "arming", as
## the summary's Edit. No key of its own (the user, 2026-11-15: "remove the key shortcut for arming").
static func _arming_button(fe: Control, foot: Control) -> Button:
	var b: Button = fe._button(foot, fe.s("tab_arming"), "Secondary", func(): fe.show_page("arming"))
	b.name = "Arming"
	b.custom_minimum_size.y = 64
	b.tooltip_text = fe.s("arming_tip")
	return b


## FLIGHTS, in a mission of more than one (the player's, Alpha, and Bravo..; one flight shows none): a tab a flight,
## the player's first and picked, and under them the picked flight's jets, task and stores (the player's as the Arming
## summary's). The picked flight's route stands out on the map (briefing_map.gd `selected`).
static func _flights(fe: Control, parent: Control, m: Dictionary, map: Control) -> void:
	var list: Array = fe.flights(m)
	if list.size() < 2:
		return
	var fv: VBoxContainer = fe._vbox(parent, 8)
	fv.name = "Flights"
	_heading(fe, fv, fe.s("flights"))
	var tabs: HBoxContainer = fe._hbox(fv, 10)
	tabs.name = "FlightTabs"
	var detail: Label = fe._text(fv, "", "")
	detail.name = "FlightDetail"
	var group := ButtonGroup.new()
	for f in list:
		var b := Button.new()
		b.name = "Flight_" + str(f.callsign)
		b.text = fe._ltr(str(f.callsign))
		b.toggle_mode = true
		b.button_group = group
		_pill(b)
		tabs.add_child(b)
		var line := _flight_line(fe, m, f)
		var callsign := str(f.callsign)
		b.toggled.connect(
			func(on: bool):
				if on:
					detail.text = line
					map.selected = callsign
		)
		if bool(f.player):
			b.button_pressed = true


## A flight's line: "Your flight · 1 × F-16I Sufa · Training · 6 × AIM-9M · 2 × 370 gal tank".
static func _flight_line(fe: Control, m: Dictionary, f: Dictionary) -> String:
	var parts := [fe.s("your_flight")] if bool(f.player) else []
	# The player's jet is the mission's as the page shows it (the Hangar's jet: front_end.gd section_missions).
	var unit := str(m.get("start", {}).get("unit", f.unit)) if bool(f.player) else str(f.unit)
	var name := unit.to_upper()
	var script: GDScript = fe.get_script()
	for j in script.JETS + script.SOON:
		if j.unit == unit:
			name = fe.full_name(j)
	parts.append("%d × %s" % [int(f.count), name])
	parts.append(fe.s("task_" + str(f.task)))
	var stores: Array = fe.arming(m, fe.mission_loadout(m)).get("stores", []) if bool(f.player) else f.stores
	parts.append(_stores_text(fe, stores))
	return " · ".join(parts)


## Stores as "6 × AIM-9M · 2 × 370 gal tank" ({weapon, count} each; an Arming store off every station left out), else
## "Empty".
static func _stores_text(fe: Control, stores: Array) -> String:
	var parts := []
	for st in stores:
		if not (st.get("stations", [0]) as Array).is_empty():
			parts.append("%d × %s" % [int(st.count), fe.short_store(str(st.weapon))])
	return " · ".join(parts) if not parts.is_empty() else fe.s("arm_empty")


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
	var stores: Label = fe._text(left, _stores_text(fe, a.get("stores", [])), "")
	stores.name = "ArmingStores"
	# A store that cannot be employed (a laser bomb with no pod): the loadout screen's line, Fly off.
	var need: String = fe.need_text(a)
	if need != "":
		var warn: Label = fe._label(left, need, "Small")  # one short line (the user, 17 Nov)
		warn.name = "ArmingNeed"
		warn.add_theme_color_override("font_color", Look.WARN)
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


## The map's chips at the top inline end: Labels and Photo turn their layer on and off; Zoom + / −.
static func _chips(fe: Control, map: Control) -> Control:
	var row: HBoxContainer = fe._hbox(fe, 10)
	row.name = "MapChips"
	var chips := [["MapLabels", "map_labels", "show_labels"], ["MapPhoto", "map_photo", "show_photo"]]
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


## The PRE targets chip first among the map's chips, while the jet carries a GPS store (A61, pre_panel.gd): on, its
## panel takes the text card's place and the map's clicks pick the targets.
static func _pre_chip(fe: Control, m: Dictionary, map: Control, chips: Control, text: Control) -> void:
	# A mission that fixes its loadout flies its own stores: no picks of the pilot's (fly.gd arm).
	if bool(m.get("fixed_loadout", false)):
		return
	var pre := PrePanel.new(fe, m, map)
	if not pre.has_rows():
		return
	var card := pre.build(TEXT_TOP, TEXT_W, EDGE)
	var b := Button.new()
	b.name = "MapPre"
	b.text = fe.s("pre_title")
	b.toggle_mode = true
	_pill(b)
	chips.add_child(b)
	chips.move_child(b, 0)
	b.toggled.connect(
		func(on: bool):
			text.visible = not on
			pre.set_shown(on)
			if on:
				var first := card.find_child("PreRow_*", true, false)
				if first != null:
					first.grab_focus.call_deferred()
	)


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


## The mission's text at the inline end, under the chips to the bottom: WHAT YOU WILL LEARN (a training mission's;
## another's PURPOSE), the mission's `briefing.purpose`; then HOW, its `briefing.how` paragraphs in a scrolled list,
## each numbered as the map's pins (a pin carries the number of the first paragraph done at its place), its keys as
## bound in key caps, a start-up's switch pictures under their paragraph. The list scrolls by the wheel (a
## touchscreen's drag) and with the focus by the arrows / the gamepad's pad and Page Up / Down; at its ends the arrows
## move the focus on.
static func _text_card(fe: Control, m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Text"
	var off := Look.box(Color(Look.PANEL, 0.94), Look.LINE, 1, 6, Vector2(28, 24))
	var on := Look.box(Color(Look.PANEL, 0.94), Look.ACCENT_TEXT, 2, 6, Vector2(28, 24))
	card.add_theme_stylebox_override("panel", off)
	fe.add_child(card)
	fe._place(card, -1, EDGE, TEXT_TOP, 0)
	card.offset_left = card.offset_right - TEXT_W
	card.anchor_bottom = 1.0
	card.offset_bottom = -40
	var v: VBoxContainer = fe._vbox(card, 10)
	var lang := "he" if fe.he() else "en"
	var b: Dictionary = m.get("briefing", {})
	_heading(fe, v, fe.s("learn" if str(m.get("category", "")) == "training" else "purpose"))
	var purpose := _rich(fe, v, fill_text(fe, m, str(b.get("purpose", {}).get(lang, ""))))
	purpose.name = "Purpose"
	purpose.add_theme_color_override("default_color", Look.ACCENT_TEXT)
	fe._spacer_px(v, 6)
	_heading(fe, v, fe.s("how"))
	var scroll := ScrollContainer.new()
	scroll.name = "HowScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	v.add_child(scroll)
	var list: VBoxContainer = fe._vbox(scroll, 18)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var how: Array = b.get("how", [])
	var unit := str(m.get("start", {}).get("unit", ""))
	for i in how.size():
		var row: HBoxContainer = fe._hbox(list, 14)
		row.name = "Para%d" % (i + 1)
		var n: Label = fe._label(row, str(i + 1), "Strong")
		n.add_theme_color_override("font_color", Look.ACCENT)
		n.add_theme_font_size_override("font_size", TEXT_PX)
		n.custom_minimum_size.x = 24
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var pv: VBoxContainer = fe._vbox(row, 10)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rich(fe, pv, fill_text(fe, m, str(how[i].get(lang, ""))))
		var pics := HFlowContainer.new()
		pics.add_theme_constant_override("h_separation", 12)
		pics.add_theme_constant_override("v_separation", 12)
		for sw in how[i].get("switches", []):
			var crop: Texture2D = fe._texture(
				ProjectSettings.globalize_path(fe.get_script().SWITCHES.path_join(unit).path_join(str(sw) + ".webp"))
			)
			if crop == null:
				continue
			var pic := TextureRect.new()
			pic.name = "Switch_" + str(sw)
			pic.texture = crop
			pic.tooltip_text = _where(m, str(sw), lang)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = Vector2(240, 160)
			pics.add_child(pic)
		if pics.get_child_count() > 0:
			pv.add_child(pics)
		else:
			pics.free()
	scroll.focus_entered.connect(func(): card.add_theme_stylebox_override("panel", on))
	scroll.focus_exited.connect(func(): card.add_theme_stylebox_override("panel", off))
	scroll.gui_input.connect(func(e: InputEvent): _scroll_keys(scroll, e))
	return card


## The arrows (the gamepad's pad: ui_up / ui_down) and Page Up / Down scroll the list with the focus; at its top or
## bottom an arrow is left to move the focus on.
static func _scroll_keys(scroll: ScrollContainer, e: InputEvent) -> void:
	var bar := scroll.get_v_scroll_bar()
	var page := scroll.size.y * 0.85
	var step := 0.0
	if e.is_action_pressed("ui_down", true):
		step = 80.0
	elif e.is_action_pressed("ui_up", true):
		step = -80.0
	elif e is InputEventKey and e.pressed and e.keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		step = page if e.keycode == KEY_PAGEDOWN else -page
	if step == 0.0:
		return
	var top := bar.max_value - bar.page
	if (step > 0.0 and bar.value >= top - 1.0) or (step < 0.0 and bar.value <= 0.0):
		return
	scroll.scroll_vertical = int(clampf(bar.value + step, 0.0, top))
	scroll.accept_event()


## A text of the card: wrapped, its height its content's, in the language's direction.
static func _rich(fe: Control, parent: Control, bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.text_direction = Control.TEXT_DIRECTION_RTL if fe.he() else Control.TEXT_DIRECTION_LTR
	r.add_theme_font_size_override("normal_font_size", TEXT_PX)
	r.add_theme_constant_override("line_separation", 6)
	r.add_theme_color_override("default_color", Look.TEXT)
	parent.add_child(r)
	r.text = bb
	return r


## A start-up step's switch and its place (the jet's checklist card's item `where`, data/checklists), for its
## picture's tooltip.
static func _where(m: Dictionary, step: String, lang: String) -> String:
	var unit := str(m.get("start", {}).get("unit", ""))
	for f in DirAccess.get_files_at("res://data/checklists"):
		var card := Settings.load_json("res://data/checklists/" + f)
		if not unit in card.get("jets", []):
			continue
		for sec in card.get("sections", []):
			for it in sec.items:
				if str(it.id) == step:
					return str(it.get("where", {}).get(lang, ""))
	return ""


## A briefing text as BBCode: {runway}, {tolerance} (the climb-out's ± degrees) and {minutes} (the time allowed)
## filled in, {key:<record>} / {key:<record>:<pick>} as the key table's key as bound (the radio menu's pick after it)
## in a key cap kept left to right; the text's own brackets escaped.
static func fill_text(fe: Control, m: Dictionary, t: String) -> String:
	var tr: Dictionary = m.get("training", {})
	t = t.replace("[", "[lb]")
	t = t.replace("{runway}", fe._ltr(str(m.get("runway", ""))))
	t = t.replace("{tolerance}", str(int(tr.get("heading_tolerance_deg", 10))))
	t = t.replace("{minutes}", str(int(float(tr.get("time_budget_s", 0)) / 60.0)))
	var re := RegEx.create_from_string("\\{key:(\\d+)(?::(\\d+))?\\}")
	for k in re.search_all(t):
		var name: String = fe.key_name(int(k.get_string(1)))
		if name == "":
			name = "—"
		elif k.get_string(2) != "":
			name += ", " + k.get_string(2)
		var cap := (
			"[bgcolor=#%s][color=#%s]\u2066\u00a0%s\u00a0\u2069[/color][/bgcolor]"
			% [
				Color(Look.BG, 0.9).to_html(),
				Look.TEXT.to_html(false),
				name.replace("[", "[lb]").replace(" ", "\u00a0")
			]
		)
		t = t.replace(k.get_string(), cap)
	return t


## Tab and the arrows: the flights' tabs (several flights), Edit, Back, Arming, Fly; on to the chips, the map, the
## text; round. Fly takes the focus (Arming when the loadout keeps Fly off); across from Fly the text, up from the
## text's top the chips, down from them the map; up from Edit the flights' tabs, down from them Edit.
static func _focus_order(fe: Control, card: Control, chips: Control, text: Control, map: Control) -> void:
	var edit: Control = card.find_child("ArmEdit", true, false)
	var back: Control = card.find_child("Back", true, false)
	var arm: Control = card.find_child("Arming", true, false)
	var fly: Button = card.find_child("Fly", true, false)
	var chip_list: Array = chips.find_children("*", "Button", true, false)
	var how: Control = text.find_child("HowScroll", true, false)
	var tabs: Array = card.find_children("Flight_*", "Button", true, false)
	var ring: Array = tabs + [edit, back, arm] + ([fly] if not fly.disabled else []) + chip_list + [map, how]
	fe._chain(ring)
	var start := "right" if fe.he() else "left"
	var end := "left" if fe.he() else "right"
	var last_card: Control = fly if not fly.disabled else arm
	fe._focus = last_card
	var up: Control = edit if tabs.is_empty() else tabs[0]
	for t in tabs:
		fe._nb(t, {"top": t, "bottom": edit})
	fe._nb(edit, {"top": up, "bottom": last_card, start: edit, end: chip_list[0]})
	fe._nb(back, {"top": edit, "bottom": back, start: back, end: arm})
	fe._nb(arm, {"top": edit, "bottom": arm, start: back, end: fly if not fly.disabled else how})
	fe._nb(fly, {"top": edit, "bottom": fly, start: arm, end: how})
	fe._nb(chip_list[0], {start: edit})
	fe._nb(chip_list[-1], {end: chip_list[-1]})
	for c in chip_list:
		fe._nb(c, {"top": c, "bottom": map})
	fe._nb(how, {"top": chip_list[0], "bottom": how, start: last_card, end: how})
