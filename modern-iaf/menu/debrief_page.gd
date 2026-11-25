# The debrief (modern-iaf/docs/front-end.md, "Debrief"; the approved mock r3_debrief, the user's A25 round 3,
# 2026-11-13: "awesome"): the sheet at the inline start (Plane flown, From, Time, Mission, Result; the goals, each with
# what the mission asks, what was flown and a mark; Remarks with "Next time:"), at the inline end the whole flight on
# the briefing map (the recorded track coloured by phase, the planned route, Start / Lift-off / End pins with their
# times, the base inset) and the flight's graphs (flight_graphs.gd). The goals and the "Next time" line are the Rust
# scorer's record (IafTraining.score), the track with its phases and marks IafTraining.track's. A record without a
# recording (older records, a flight file gone) shows the sheet with the right column's empty state. `build` lays it out
# on the front end `fe` (front_end.gd), whose building blocks it uses.
extends RefCounted

const Look := preload("look.gd")
const BriefingMap := preload("briefing_map.gd")
const FlightGraphs := preload("flight_graphs.gd")
const CombatPage := preload("combat_page.gd")
const FileExport := preload("res://shared/util/file_export.gd")
## The sheet's width, the screen's edge, the gap between the columns, the columns' top and their room above the
## footer (px on the 1920 × 1080 canvas, the mock's).
const SHEET_W := 880
const EDGE := 68
const GAP := 32
const TOP := 112
const BOTTOM := 138
## The base inset's size (px).
const INSET := Vector2(300, 160)
## The map's view on the track: this margin around it (or a sixth of its span), at least this wide (m).
const TRACK_MARGIN_M := 600.0
const TRACK_MIN_M := 2000.0
## The phases' colours (training::PHASES: start-up, taxi, hold, roll, airborne): the map's track and the graphs' band.
const PHASE_COLORS := [Color("8fb3ff"), Color("ffd08a"), Color("c9ced6"), Color("ff7a59"), Color("7fd18b")]
## A goal's mark: met, off the mark (the mission still passes), failed.
const MARKS := {"ok": ["✓", Color("2e7d32")], "warn": ["!", Color("c77700")], "fail": ["✗", Color("c62828")]}


## The debrief of `fe.record`, mission `m` as flown, on `fe` under its header; the controls named for the tests and
## the focus (Sheet, Goals, Remarks, NextTime, DebriefMap, Inset, Legend, Graphs, NoRecording, PilotLog, ExportFlight,
## BackMissions, FlyAgain, NextMission).
static func build(fe: Control, m: Dictionary) -> void:
	var j: Dictionary = fe.jet_of(m)
	_sheet(fe, m, j)
	var col: VBoxContainer = fe._vbox(fe, 13)
	col.name = "Flight"
	fe._place(col, EDGE + SHEET_W + GAP, EDGE, TOP, 0)
	col.anchor_bottom = 1.0
	col.offset_bottom = -BOTTOM
	var tr := track(fe, m)
	var map: Control = _map(fe, col, m, tr)
	_graphs(fe, col, m, tr)
	_footer(fe, m, map)


## IafTraining.track of the record's recording ({} without one, or when it cannot be read).
static func track(fe: Control, m: Dictionary) -> Dictionary:
	var flight := str(fe.record.get("flight", ""))
	if flight == "" or not FileAccess.file_exists(flight):
		return {}
	var d = JSON.parse_string(
		IafTraining.track(
			flight,
			Settings.disk_path("res://data/missions/%s.json" % str(m.get("id", ""))),
			Settings.disk_path("res://data/airbases")
		)
	)
	if not d is Dictionary or d.has("error") or d.get("t", []).is_empty():
		push_warning("debrief: %s" % (d.get("error", "an empty recording") if d is Dictionary else "no track"))
		return {}
	return d


## The mission clock `t` s after the start: "08:10" ("08:10:38" with `secs`); m:ss from the start without the
## mission's time.
static func clock_at(fe: Control, m: Dictionary, t: float, secs := false) -> String:
	var start := str(m.get("time", ""))
	if not start.contains(":"):
		return fe.clock(t)
	var c := int(start.get_slice(":", 0)) * 3600 + int(start.get_slice(":", 1)) * 60 + int(t)
	if secs:
		return "%02d:%02d:%02d" % [(c / 3600) % 24, c % 3600 / 60, c % 60]
	return "%02d:%02d" % [(c / 3600) % 24, c % 3600 / 60]


## The day and the mission clock from the start to the end: "2 Nov 2026 · 08:00–08:14" (Hebrew "2 בנובמבר 2026 · …").
static func debrief_time(fe: Control, m: Dictionary) -> String:
	var out: String = fe.day_text(str(fe.record.get("date", "")))
	if str(m.get("time", "")).contains(":"):
		var e := float(fe.record.get("elapsed_s", 0.0))
		out += " · %s" % fe._ltr("%s–%s" % [clock_at(fe, m, 0.0), clock_at(fe, m, e)])
	return out


## A figure with its unit: thousands grouped, seconds as m:ss past a minute; a name (the runway) as it is; "—" for
## none (not reached).
static func value_text(fe: Control, it: Dictionary) -> String:
	if it.get("text") != null:
		return str(it.text)
	if it.get("value") == null:
		return "—"
	var v := float(it.value)
	var unit := str(it.get("unit", ""))
	if unit == "s" and v >= 60.0:
		return "%s %s" % [fe.clock(v), fe.s("u_min")]
	var num := Look.group(v)
	match unit:
		"":
			return num
		"deg":
			return num + "°"
		_:
			return "%s %s" % [num, fe.s("u_" + unit) if fe.strings.has("u_" + unit) else unit]


## A goal's target: as it is, "max 10 m" or "247° ±10".
static func target_text(fe: Control, t: Dictionary) -> String:
	var v := value_text(fe, t)
	if t.get("max", false):
		return fe.s("at_most") % v
	if t.has("tol"):
		return fe._ltr("%s ±%s" % [v, Look.group(float(t.tol))])
	return v


# --- the sheet --------------------------------------------------------------------------------------------------------


static func _sheet(fe: Control, m: Dictionary, j: Dictionary) -> void:
	var rec: Dictionary = fe.record
	var holder: VBoxContainer = fe._vbox(fe, 0)
	fe._place(holder, EDGE, -1, TOP, 0)
	holder.offset_right = holder.offset_left + SHEET_W
	holder.anchor_bottom = 1.0
	holder.offset_bottom = -BOTTOM
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.add_theme_stylebox_override("panel", Look.box(Look.PAPER, Look.PAPER, 0, 5, Vector2.ZERO))
	sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.add_child(sheet)
	var v: VBoxContainer = fe._vbox(sheet, 0)
	var band := PanelContainer.new()
	var bb := Look.box(Look.NAVY, Look.NAVY, 0, 5, Vector2(22, 12))
	bb.corner_radius_bottom_left = 0
	bb.corner_radius_bottom_right = 0
	band.add_theme_stylebox_override("panel", bb)
	v.add_child(band)
	var bh: HBoxContainer = fe._hbox(band, 0)
	fe._label(bh, fe.s("debrief_band"), "Band")
	fe._spacer(bh)
	fe._label(bh, fe.s("number") % ("%04d" % fe.record_sortie), "Band")
	var inner: VBoxContainer = fe._vbox(fe._margin(v, 22, 18), 0)
	_fields(fe, inner, m, j)
	_goals(fe, inner)
	CombatPage.sheet(fe, inner)
	# Remarks: why it failed (the reason that ended it first) or that it passed, then the scorer's "Next time" line.
	var lang := "he" if fe.he() else "en"
	var names: Dictionary = rec.get("strings", {}).get(lang, {})
	var lines := []
	for r in rec.get("reasons", []):
		lines.append(str(names.get(r, fe.s(r) if fe.strings.has(r) else r)))  # "no_score": the front end's
	if rec.get("pass", false) and fe.strings.has("done_" + str(rec.get("kind", ""))):
		lines.append(fe.s("done_" + str(rec.kind)))
	var next = rec.get("next")
	if lines.is_empty() and not next is Dictionary:
		return
	fe._spacer_px(inner, 20)
	fe._label(inner, fe.s("remarks"), "PaperHead")
	fe._rule(inner, Look.INK, 2)
	fe._spacer_px(inner, 12)
	var box := PanelContainer.new()
	box.name = "Remarks"
	var st := Look.box(Color("e8e2d4"), Look.NAVY, 0, 0, Vector2(18, 12))
	# The bar at the inline start (a stylebox's sides do not mirror).
	st.set("border_width_right" if fe.he() else "border_width_left", 4)
	box.add_theme_stylebox_override("panel", st)
	inner.add_child(box)
	var rv: VBoxContainer = fe._vbox(box, 4)
	for l in lines:
		fe._text(rv, l, "Paper")
	if next is Dictionary:
		var rt := RichTextLabel.new()
		rt.name = "NextTime"
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.add_theme_font_override("normal_font", fe._theme.get_font("font", "Paper"))
		rt.add_theme_font_override("bold_font", fe._theme.get_font("font", "PaperHead"))
		for k in ["normal_font_size", "bold_font_size"]:
			rt.add_theme_font_size_override(k, Look.R)
		rt.add_theme_color_override("default_color", Look.INK)
		var tip := str(next.get(lang, next.get("en", ""))).replace("[", "[lb]")
		rt.text = "[b]%s[/b] %s" % [fe.s("next_time"), tip]
		rv.add_child(rt)


## The fields: Plane flown, From, Time, Mission, Result, each a cell of a ruled row.
static func _fields(fe: Control, inner: Control, m: Dictionary, j: Dictionary) -> void:
	var fields: HBoxContainer = fe._hbox(inner, 0)
	fields.add_theme_constant_override("separation", -1)
	var from: String = fe.s("base_" + str(j.get("base", "")))
	if m.has("runway"):
		from = fe.s("from_runway") % [from, m.runway]
	var cells := [
		["plane_flown", fe.full_name(j), 1.0],
		["from", from, 1.15],
		["f_time", debrief_time(fe, m), 1.3],
		["mission", fe.title_of(m) if not m.is_empty() else str(fe.record.get("mission", "")), 0.95],
		["result", "", 0.75],
	]
	for c in cells:
		var cell := PanelContainer.new()
		# Anti-aliased, so the 1 px rules show at every scale (1280 × 720 dropped some).
		var cb := Look.box(Color(0, 0, 0, 0), Look.RULE, 1, 0, Vector2(12, 9))
		cb.anti_aliasing = true
		cell.add_theme_stylebox_override("panel", cb)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = c[2]
		fields.add_child(cell)
		var cv: VBoxContainer = fe._vbox(cell, 2)
		fe._label(cv, fe.s(c[0]), "PaperLabel")
		if c[0] == "result":
			# The box places a plain Control at the inline start; the stamp inside it keeps its tilt (a container
			# resets its own children's rotation).
			var row: HBoxContainer = fe._hbox(cv, 0)
			var tilt := Control.new()
			row.add_child(tilt)
			var stamp: Label = fe._label(
				tilt, fe.s("stamp_pass" if fe.record.get("pass", false) else "stamp_fail"), "Stamp"
			)
			stamp.name = "Stamp"
			stamp.add_theme_stylebox_override("normal", Look.box(Color(0, 0, 0, 0), Look.NAVY, 3, 3, Vector2(10, 0)))
			stamp.rotation_degrees = -4.0
			tilt.custom_minimum_size = stamp.get_combined_minimum_size() + Vector2(0, 10)
			stamp.position.y = 6
		else:
			var val: Label = fe._text(cv, c[1], "PaperValue")
			val.name = "Field_" + c[0]


## The goals: the record's `checks` (the mark, the label, the target and the flown figure); a record from before them
## shows its `goals` items with their figure alone.
static func _goals(fe: Control, inner: Control) -> void:
	var rec: Dictionary = fe.record
	var lang := "he" if fe.he() else "en"
	var rows := []
	for c in rec.get("checks", []):
		var label := str(c.label.get(lang, c.label.get("en", "")))
		rows.append([c.get("mark", "ok"), label, target_text(fe, c.target), value_text(fe, c.flown)])
	if not rec.has("checks"):
		var names: Dictionary = rec.get("strings", {}).get(lang, {})
		var all: Array = rec.get("items", [])
		for g in rec.get("goals", all.map(func(it): return it.id)):
			for it in all:
				if it.id == g and (it.get("value") != null or it.has("text")):
					rows.append(["", str(names.get(it.id, it.id)), "", value_text(fe, it)])
	if rows.is_empty():
		return
	fe._spacer_px(inner, 20)
	fe._label(inner, fe.s("goals"), "PaperHead")
	fe._rule(inner, Look.INK, 2)
	var list: VBoxContainer = fe._vbox(inner, 0)
	list.name = "Goals"
	for r in rows:
		var h: HBoxContainer = fe._hbox(fe._margin(list, 0, 9), 12)
		var mark: Label = fe._label(h, MARKS[r[0]][0] if MARKS.has(r[0]) else "", "PaperNum")
		mark.custom_minimum_size.x = 22
		if MARKS.has(r[0]):
			mark.add_theme_color_override("font_color", MARKS[r[0]][1])
		var l: Label = fe._label(h, r[1], "Paper")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var t: Label = fe._label(h, r[2], "PaperLabel")
		t.custom_minimum_size.x = 120 if r[2] != "" else 0
		var f: Label = fe._label(h, r[3], "PaperNum")
		f.custom_minimum_size.x = 100
		# The figures at the row's inline end (a Label's alignment follows the layout's direction).
		for x in [t, f]:
			x.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fe._rule(list, Look.RULE)


# --- the right column -------------------------------------------------------------------------------------------------


## A panel of the right column with its title; its body (a VBox).
static func _panel(fe: Control, parent: Control, title: String, ratio: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Look.box(Look.PANEL, Look.LINE, 1, 6, Vector2(18, 14)))
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	parent.add_child(p)
	var v: VBoxContainer = fe._vbox(p, 8)
	fe._label(v, title, "H3")
	return v


## The column's empty state: the recording is missing.
static func _empty(fe: Control, v: Control) -> void:
	var l: Label = fe._label(v, fe.s("no_recording"), "Muted")
	l.name = "NoRecording"
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## The whole flight on the map, with the base inset and the legend; the map (null without a recording).
static func _map(fe: Control, col: Control, m: Dictionary, tr: Dictionary) -> Control:
	var v := _panel(fe, col, fe.s("map_flight"), 1.08)
	if tr.is_empty():
		_empty(fe, v)
		return null
	var names: Dictionary = tr.strings.get("he" if fe.he() else "en", {})
	var t: Array = tr.t
	var pins := []
	for p in tr.pins:
		var secs: bool = p.id == "liftoff"
		pins.append([int(p.i), fe.s("pin_t_" + str(p.id)) % clock_at(fe, m, float(t[int(p.i)]), secs), str(p.id)])
	var map := _flight_map(fe, m, tr, true)
	map.name = "DebriefMap"
	# Its north arrow and scale bar where English has them: the inset stays at the bottom left in both languages.
	map.layout_direction = Control.LAYOUT_DIRECTION_LTR
	map.track_pins = pins
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(map)
	# The base inset: the start and the taxi (the briefing's opening view), bottom left (the map never mirrors).
	var frame := PanelContainer.new()
	frame.name = "Inset"
	frame.layout_direction = Control.LAYOUT_DIRECTION_LTR
	frame.add_theme_stylebox_override("panel", Look.box(Look.BG, Color.WHITE, 2, 2, Vector2(2, 2)))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(frame)
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = 12
	frame.offset_right = 12 + INSET.x
	frame.offset_top = -12 - INSET.y
	frame.offset_bottom = -12
	var inset := _flight_map(fe, m, tr, false)
	inset.chrome = false
	inset.show_labels = false
	inset.track_pins = pins.slice(0, 1)
	inset.focus_mode = Control.FOCUS_NONE
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inset)
	var base := str(m.get("start", {}).get("base", "")).to_lower().replace(" ", "_")
	var tag: Label = fe._label(inset, fe.s("inset_base") % fe.s("base_" + base), "Small")
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Look.TEXT)
	tag.add_theme_stylebox_override("normal", Look.box(Color(Look.BG, 0.85), Color(0, 0, 0, 0), 0, 0, Vector2(6, 2)))
	# The main map opens on the whole track in the room beside the inset, its scale bar there too.
	var aim := func():
		var iw := INSET.x + 24.0
		map.aim(Rect2(iw, 0, map.size.x - iw, map.size.y))
		map.scale_at = Vector2(iw + 16.0, map.size.y - 28.0)
	map.resized.connect(aim)
	# The legend: the phases flown and the planned route.
	var legend: HBoxContainer = fe._hbox(v, 22)
	legend.name = "Legend"
	var seen := []
	for r in tr.runs:
		if not seen.has(int(r.phase)):
			seen.append(int(r.phase))
	for p in seen:
		_key(fe, legend, PHASE_COLORS[p], str(names.get("ph_" + str(tr.phases[p]), "")))
	if m.get("runway") is String:
		_key(fe, legend, Look.NAVY.lightened(0.35), fe.s("legend_route"))
	return map


## A map of the mission with the track over it; `whole`: opened on all of the track (else on the start and the taxi,
## the briefing's view). The track comes in the sim's frame (UTM 36N) and goes into the map's metres (from its
## north-west corner, y down).
static func _flight_map(fe: Control, m: Dictionary, tr: Dictionary, whole: bool) -> Control:
	var map := BriefingMap.new()
	map.km = fe.s("km")
	map.metres = fe.s("m")
	map.hebrew = fe.he()
	map.track_phase = tr.phase
	map.track_colors = PHASE_COLORS
	var base := str(m.get("start", {}).get("base", "")).to_lower().replace(" ", "_")
	map.base_label = fe.s("base_" + base)
	map.source = func(a: float) -> Dictionary:
		var d: Dictionary = fe.briefing_map(m, a)
		d.pins = []
		var e: Array = d.get("extent", [])
		if e.size() == 4:
			var at: Array = tr.at
			var pts := PackedVector2Array()
			for i in range(0, at.size() - 1, 2):
				pts.append(Vector2(float(at[i]) - float(e[0]), float(e[3]) - float(at[i + 1])))
			map.track = pts
			if whole and not pts.is_empty():
				var box := Rect2(pts[0], Vector2.ZERO)
				for p in pts:
					box = box.expand(p)
				# Room for the pins' labels: the margin, or a sixth of the track's span.
				box = box.grow(maxf(TRACK_MARGIN_M, maxf(box.size.x, box.size.y) / 6.0))
				var gx := maxf(TRACK_MIN_M - box.size.x, 0.0) / 2.0
				var gy := maxf(TRACK_MIN_M - box.size.y, 0.0) / 2.0
				box = box.grow_individual(gx, gy, gx, gy)
				d.focus = [box.position.x, box.position.y, box.end.x, box.end.y]
		if m.get("runway") is String and d.get("heading") != null:
			map.runway_label = fe._ltr(fe.runway_text(m.runway, d.heading))
		return d
	map.layers_source = func(v: PackedFloat64Array, o: PackedFloat64Array, k: float) -> Dictionary:
		return fe.briefing_layers(m, v, o, k)
	map.theatre = fe.briefing_theatre()
	return map


static func _key(fe: Control, parent: Control, c: Color, t: String) -> void:
	var h: HBoxContainer = fe._hbox(parent, 8)
	var sw := ColorRect.new()
	sw.color = c
	sw.custom_minimum_size = Vector2(20, 4)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	fe._label(h, t, "Small").add_theme_font_size_override("font_size", 16)


## The flight's graphs: speed, height above the ground and load against the mission clock.
static func _graphs(fe: Control, col: Control, m: Dictionary, tr: Dictionary) -> void:
	var title: String = fe.s("graphs")
	if not tr.is_empty():
		title = fe.s("graphs_at") % fe._ltr("%s–%s" % [clock_at(fe, m, 0.0), clock_at(fe, m, float(tr.t[-1]))])
	var v := _panel(fe, col, title, 1.0)
	if tr.is_empty():
		_empty(fe, v)
		return
	var g := FlightGraphs.new()
	g.name = "Graphs"
	g.flight = tr
	g.colors = PHASE_COLORS
	g.names = tr.strings.get("he" if fe.he() else "en", {})
	g.titles = [fe.s("g_speed"), fe.s("g_agl"), fe.s("g_load")]
	g.clock = func(t: float, secs: bool) -> String: return clock_at(fe, m, t, secs)
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(g)


# --- the footer -------------------------------------------------------------------------------------------------------


## Pilot log and Export flight data at the inline start; Back to missions, Fly again and Next mission (the section's
## next one, none after its last) at the end, the last of them the primary and focused. Tab and the arrows go through
## the map and the buttons.
static func _footer(fe: Control, m: Dictionary, map: Control) -> void:
	var log: Button = fe._action(fe.s("pilot_log"), "Secondary", fe.show_page.bind("log"))
	log.name = "PilotLog"
	var back: Button = fe._action(fe.s("back_missions"), "Secondary", func(): fe.back_to_missions(m))
	back.name = "BackMissions"
	var next_id: int = fe.next_of(m)
	var again: Button = fe._action(
		fe.s("fly_again"), "Secondary" if next_id != 0 else "Primary", func(): fe.fly_again(m)
	)
	again.name = "FlyAgain"
	again.disabled = m.is_empty()
	var acts: Array = [back, again]
	if next_id != 0:
		var nx: Button = fe._action(fe.s("next_mission"), "Primary", func(): fe.next_mission(m))
		nx.name = "NextMission"
		acts.append(nx)
	# The flight's recording (the record's `flight`, sim_flight.gd _finish) saved where the player picks (FileExport,
	# reborn's debrief Export flight data); greyed and skipped by the focus when the file is gone.
	var flight_file := str(fe.record.get("flight", ""))
	var export: Button = fe._action(fe.s("export_flight"), "Secondary", FileExport.export_flight.bind(fe, flight_file))
	export.name = "ExportFlight"
	if not FileAccess.file_exists(flight_file):
		export.disabled = true
		export.focus_mode = Control.FOCUS_NONE
		export.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		# Its kind's plain box, the text greyed (as _soon: the theme gives the disabled state no box).
		export.add_theme_stylebox_override("disabled", fe._theme.get_stylebox("normal", "Secondary"))
	var more: Button = CombatPage.more_button(fe)
	fe._footer("", acts, false, [log, export] + ([more] if more != null else []))
	var ring: Array = [log] + ([export] if not export.disabled else []) + ([more] if more != null else [])
	ring += acts.filter(func(b): return not b.disabled)
	if map != null:
		for b in ring:
			fe._nb(b, {"top": map})
		ring.push_front(map)
	fe._chain(ring)
	fe._focus = acts[-1] if not acts[-1].disabled else back
