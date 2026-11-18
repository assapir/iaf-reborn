# Ours (the F-35I, docs/f35i.md §4.3, docs/real-mfd.md "F-35I"): the formats of the panoramic cockpit display, drawn
# into a portal in panel px (the caller sets the canvas transform: origin = the portal's top-left, scale = the
# cockpit's UI scale). Black glass; cyan for the option legends, green for good / friends, yellow for caution /
# unknown, red for warnings / hostiles, grey for maps and outlines, white for the selected (Code One; a simulator
# manual for cyan and white). Everything shown comes from the cockpit's state (cockpit.gd).
extends RefCounted

const Mfd := preload("res://shared/cockpit/mfd.gd")

const CYAN := Color(0.30, 0.85, 1.0)
const GREEN := Color(0.30, 1.0, 0.38)
const DARK_GREEN := Color(0.12, 0.45, 0.16)
const WHITE := Color(0.94, 0.96, 0.98)
const YELLOW := Color(1.0, 0.88, 0.20)
const RED := Color(1.0, 0.24, 0.18)
const MAGENTA := Color(1.0, 0.35, 0.95)
const GREY := Color(0.52, 0.56, 0.62)
const DARK_GREY := Color(0.22, 0.24, 0.28)
const PURPLE := Color(0.62, 0.52, 1.0)
const SKY := Color(0.10, 0.38, 0.78)
const EARTH := Color(0.50, 0.32, 0.14)
## Line widths in panel px (×UI scale on screen).
const THIN := 0.45
const LINE := 0.7
const BOLD := 1.1
## The formats a portal can show (the MENU grid, in its order). TSD-1..3 are three independent TSDs; SRCH is the
## radar's air-to-air page and ASR its air-to-surface one (one game page: the radar's mode picks).
const FORMATS := ["TSD-1", "TSD-2", "TSD-3", "SRCH", "SMS", "TFLIR", "TWD", "EFI", "ICAWS", "FUEL", "ENG"]
## The RWR's threat codes by bdb type (the rwrsymb.bmp glyphs, docs/mfd.md §3 "RWR").
const THREAT_CODE := {
	290: "2",
	300: "3",
	310: "5",
	320: "6",
	330: "8",
	340: "HK",
	350: "A",
	360: "A",
	380: "A",
	390: "A",
	150: "21",
	160: "23",
	180: "29",
	170: "25",
	120: "F4",
	200: "F4",
	110: "15",
	100: "16",
	130: "M",
	190: "M",
	140: "L"
}

var ci: CanvasItem
var cockpit: Control
var font: Font
## What the last draw of each format showed (tests): srch {mode, kinds, cursor, no_rad}, asr {name, fov, picture,
## kinds}, tsd {link, tracks}, twd {labels, maw}.
var shown := {}


func _init(canvas: CanvasItem, c: Control, f: Font) -> void:
	ci = canvas
	cockpit = c
	font = f


# --- primitives (panel px) ----------------------------------------------------------------------------------------


func text(at: Vector2, t: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	# Drawn unscaled at its screen size (a raster font: each glyph rasterises once per size, fast; an MSDF font
	# built each new glyph's field on the main thread, a stall when a click brought up new text).
	var px := _px(size)
	var x := at.x
	if align != HORIZONTAL_ALIGNMENT_LEFT and width > 0.0:
		x += (width - text_width(t, size)) * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	ci.draw_set_transform_matrix(Transform2D(0.0, (_base * Vector2(x, at.y)).round()))
	ci.draw_string(font, Vector2.ZERO, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	ci.draw_set_transform_matrix(_base)


## A size in panel px as whole screen px.
func _px(size: float) -> int:
	return maxi(int(round(size * _base.get_scale().x)), 6)


func text_width(t: String, size: float) -> float:
	return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(size)).x / _base.get_scale().x


var _base := Transform2D.IDENTITY


## The portal's transform (set by pcd.gd before each format); `squeeze` narrows it across (the function bar's group of
## legends in the other half, pcd.gd _draw_fab).
func begin(origin: Vector2, scale: float, squeeze := 1.0) -> void:
	_base = Transform2D(0.0, Vector2(scale * squeeze, scale), 0.0, origin)
	ci.draw_set_transform_matrix(_base)


func end() -> void:
	_base = Transform2D.IDENTITY
	ci.draw_set_transform_matrix(_base)


func line(a: Vector2, b: Vector2, col: Color, w := LINE) -> void:
	ci.draw_line(a, b, col, w, true)


func poly(pts: PackedVector2Array, col: Color, w := LINE, closed := false) -> void:
	if closed and pts.size() > 0:
		pts = pts.duplicate()
		pts.append(pts[0])
	ci.draw_polyline(pts, col, w, true)


func circle(c: Vector2, r: float, col: Color, w := LINE) -> void:
	ci.draw_arc(c, r, 0.0, TAU, maxi(24, int(r * 2.0)), col, w, true)


func dashed_circle(c: Vector2, r: float, col: Color, w := LINE, dashes := 36) -> void:
	for i in dashes:
		var a0 := TAU * i / dashes
		ci.draw_arc(c, r, a0, a0 + TAU / dashes * 0.55, 4, col, w, true)


func dashed_line(a: Vector2, b: Vector2, col: Color, w := LINE, dash := 3.0) -> void:
	var n := maxi(1, int(a.distance_to(b) / dash))
	for i in range(0, n, 2):
		line(a.lerp(b, float(i) / n), a.lerp(b, minf(1.0, float(i + 1) / n)), col, w)


func box(r: Rect2, col: Color, w := LINE) -> void:
	poly(
		PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		col,
		w,
		true
	)


func fill(r: Rect2, col: Color) -> void:
	ci.draw_rect(r, col)


## A legend on the portal's edge: cyan text; `boxed` draws the selected-option box around it (white).
func legend(at: Vector2, t: String, right := false, boxed := false, size := 5.0) -> void:
	var w := text_width(t, size)
	var x := at.x - w if right else at.x
	text(Vector2(x, at.y), t, size, WHITE if boxed else CYAN)
	if boxed:
		box(Rect2(x - 1.0, at.y - size * 0.95, w + 2.0, size * 1.25), WHITE, THIN)


## A track (Skaff, Lockheed Martin): friend a green circle, suspect / unknown a yellow square, hostile a red diamond;
## an air track has its direction-of-travel line, a ground threat sits on a short base line (inferred: the sources
## say air and ground shapes differ, not how).
func track(p: Vector2, kind: String, heading = null, ground := false, size := 3.0) -> void:
	var col: Color = {"friend": GREEN, "unknown": YELLOW, "hostile": RED}[kind]
	match kind:
		"friend":
			circle(p, size, col, LINE)
		"unknown":
			box(Rect2(p - Vector2(size, size) * 0.85, Vector2(size, size) * 1.7), col, LINE)
		_:
			poly(
				PackedVector2Array(
					[
						p + Vector2(0, -size * 1.2),
						p + Vector2(size * 1.2, 0),
						p + Vector2(0, size * 1.2),
						p + Vector2(-size * 1.2, 0)
					]
				),
				col,
				LINE,
				true
			)
	if heading != null:
		var d := Vector2(sin(heading), -cos(heading))
		line(p + d * size * 1.2, p + d * size * 3.6, col, LINE)
	if ground:
		line(p + Vector2(-size * 1.6, size * 1.9), p + Vector2(size * 1.6, size * 1.9), col, LINE)


## The ownship: a small cyan F-35 planform pointing up.
func ownship(p: Vector2, size := 4.0) -> void:
	var k := size / 4.0
	var pts := PackedVector2Array(
		[
			Vector2(0, -4.5),
			Vector2(0.9, -1.5),
			Vector2(4.0, 1.2),
			Vector2(4.0, 2.2),
			Vector2(1.2, 1.6),
			Vector2(1.6, 4.0),
			Vector2(-1.6, 4.0),
			Vector2(-1.2, 1.6),
			Vector2(-4.0, 2.2),
			Vector2(-4.0, 1.2),
			Vector2(-0.9, -1.5)
		]
	)
	for i in pts.size():
		pts[i] = p + pts[i] * k
	poly(pts, CYAN, LINE, true)


# --- shared state ------------------------------------------------------------------------------------------------


func own_world() -> Vector2:
	return cockpit.state.get("world", Vector2.ZERO)


func heading_rad() -> float:
	return deg_to_rad(float(cockpit.state.get("heading", 0.0)))


## A world point (metres, X east / Y north) relative to the ownship, heading-up, in px at `m_per_px`.
func to_scope(w: Vector2, centre: Vector2, m_per_px: float) -> Vector2:
	var o := own_world()
	var h := heading_rad()
	var ex := w.x - o.x
	var ny := w.y - o.y
	return centre + Vector2(ex * cos(h) - ny * sin(h), -(ex * sin(h) + ny * cos(h))) / m_per_px


## to_scope() as one transform, for many points at once (`scope_xform(...) * points`, native).
func scope_xform(centre: Vector2, m_per_px: float) -> Transform2D:
	var h := heading_rad()
	var x := Vector2(cos(h), -sin(h)) / m_per_px
	var y := Vector2(-sin(h), -cos(h)) / m_per_px
	var o := own_world()
	return Transform2D(x, y, centre - x * o.x - y * o.y)


## A track's symbol: Modern IAF's combat ID (ews.gd state.ident, aiff.rs combat_id: a friend that answers, a hostile
## named by the data link or heard on the threat warning, else unknown), else its side (the 1998 game's F-35I).
func track_kind(c: Dictionary) -> String:
	var ident: Dictionary = cockpit.ews.get("ident", {})
	if ident.has(c.get("key", "")):
		return String(ident[c.key])
	return "hostile" if bool(c.get("hostile", true)) else "friend"


# --- TSD ---------------------------------------------------------------------------------------------------------


## The TSD (tactical situation display, the plan view): the compass rose about the ownship, heading-up, its radius
## = the range; the map's outlines grey; the route white with the steerpoint; the radar's tracks and the known SAM
## sites with their threat rings (red, dashed). `range_nm` = the rose's radius.
func tsd(r: Rect2, range_nm: float, show_map := true) -> void:
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.54)
	var rad := minf(r.size.x * 0.46, minf(c.y - r.position.y, r.end.y - c.y) * 0.95)  # inside a wide portal too
	var mpp := range_nm * 1852.0 / rad
	var clip := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if show_map:
		# The map's outlines (grey), cut at the portal's edge (the cut itself not drawn).
		# One transform per frame, applied natively: the own TSD map (OpenStreetMap) holds some 10,000 points, which
		# point by point took 64 ms a frame (measured 2026-11-08) and slowed the F-35I's flight.
		var xf := scope_xform(c, mpp)
		for p in cockpit.tsd_map:
			var pts: PackedVector2Array = xf * (p.points as PackedVector2Array)
			if pts.size() > 0:
				pts.append(pts[0])
			for seg in Geometry2D.intersect_polyline_with_polygon(pts, clip):
				poly(seg, DARK_GREY, THIN)
	# The rose: ticks every 10°, longer every 30°, numbers every 30° (N E S W letters), rotating with the heading.
	circle(c, rad, GREY, THIN)
	dashed_circle(c, rad * 0.5, DARK_GREY, THIN, 48)
	var h := heading_rad()
	for deg in range(0, 360, 10):
		var a := deg_to_rad(deg) - h
		var d := Vector2(sin(a), -cos(a))
		var long := deg % 30 == 0
		line(c + d * rad, c + d * (rad - (3.0 if long else 1.6)), GREY, THIN)
		if long:
			var lab: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(deg, "%d" % (deg / 10))
			var q := c + d * (rad - 6.5)
			text(q + Vector2(-text_width(lab, 4.2) / 2.0, 1.6), lab, 4.2, GREY)
	text(c + Vector2(rad * 0.72, -rad * 0.72), "%d" % int(range_nm), 4.5, CYAN)
	text(c + Vector2(rad * 0.37, -rad * 0.37), "%d" % int(range_nm / 2.0), 4.0, DARK_GREY.lightened(0.4))
	# The route (white), its steerpoints (circles; the current one larger with its number).
	var wps: Array = cockpit.waypoints
	var prev = null
	for i in wps.size():
		var p := to_scope(wps[i].world, c, mpp)
		if prev != null:
			for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([prev, p]), clip):
				poly(seg, WHITE, THIN)
		prev = p
		if r.has_point(p):
			if i == cockpit.current_waypoint:
				circle(p, 2.4, WHITE, LINE)
				text(p + Vector2(3.0, -2.0), "%d" % (i + 1), 4.2, WHITE)
			else:
				circle(p, 1.4, WHITE, THIN)
	# The SAM sites (state+0x1148, the TSD table) and their engagement rings.
	for site in cockpit.sam_sites:
		var p := to_scope(site.pos, c, mpp)
		if not r.grow(rad).has_point(p):
			continue
		var rr := float(site.r) / mpp
		if rr > 0.5:
			for seg in _arc_clipped(p, rr, clip):
				poly(seg, RED, THIN)
		if r.has_point(p):
			track(p, "hostile", null, true, 2.2)
	# The data link's tracks (Modern IAF, ews.gd: the flight's jets with their number, the AWACS's picture by its combat
	# ID; datalink.rs), under the radar's own.
	# One symbol per unit: a unit the radar tracks shows as the radar's track (fused; inferred).
	var radar_keys := {}
	for ct in cockpit.radar.get("contacts", []):
		radar_keys[ct.get("key", "")] = true
	var shown_keys := {}
	for t in cockpit.ews.get("link", []):
		var lp := to_scope(Vector2(t.pos.x, t.pos.y), c, mpp)
		if not r.has_point(lp) or radar_keys.has(t.key):
			continue
		var team: bool = t.kind == "team"
		var kind := "friend" if t.kind != "hostile" else track_kind(t)
		track(lp, kind, deg_to_rad(float(t.heading)) - h, false, 2.4)
		if team:
			text(lp + Vector2(-1.3, 1.6), "%d" % int(t.n), 3.6, GREEN)
		shown_keys[t.key] = true
	shown.tsd = {"link": shown_keys.size(), "tracks": 0}
	# The radar's tracks (fused with the data link on the real jet).
	var radar: Dictionary = cockpit.radar
	for ct in radar.get("contacts", []):
		var w: Vector3 = ct.pos
		var p := to_scope(Vector2(w.x, w.y), c, mpp)
		if r.has_point(p):
			var hd = deg_to_rad(float(ct.heading)) - h if ct.has("heading") else null
			track(p, track_kind(ct), hd, false, 2.4)
			shown.tsd.tracks += 1
			if ct.get("locked", false):
				circle(p, 5.0, WHITE, THIN)
	ownship(c, 4.0)


## The arcs of a circle inside the clip polygon.
func _arc_clipped(c: Vector2, rad: float, clip: PackedVector2Array) -> Array:
	var pts := PackedVector2Array()
	for i in 73:
		var a := TAU * i / 72.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return Geometry2D.intersect_polyline_with_polygon(pts, clip)


# --- SRCH / ASR: the radar ---------------------------------------------------------------------------------------

const RANGES := [5, 10, 20, 40, 80, 160]
const MODE_NAMES := ["OFF", "STBY", "STT", "BORE", "LRS", "TWS", "ACM", "GMT", "MAP"]


## The radar (SRCH air-to-air, ASR air-to-surface; the layout is open, inferred: an azimuth / range fan like the
## Driven Technologies picture's, G32): the apex at the ownship, ±the scan's half width, range arcs at quarters; the
## tracks by their combat ID with their direction lines; the lock ringed with its data on top. Modern IAF's real FCR
## (radar.rs, airframe radar.fcr; docs/radar.md §9) adds the mode and submode, the scan, its limits, the acquisition
## cursor with its altitude coverage, NO RAD; its air-to-surface modes draw the ASR (_asr).
func radar(r: Rect2) -> void:
	var rd: Dictionary = cockpit.radar
	var mode := int(rd.get("mode", 0))
	var nm: float = RANGES[clampi(int(rd.get("idx", 1)), 1, 6) - 1]
	var real: Dictionary = rd.get("real", {})
	var ag: Dictionary = real.get("ag", {})
	var apex := Vector2(r.get_center().x, r.end.y - 4.0)
	var half := float(rd.get("width", TAU / 3.0)) / 2.0
	# As tall as the portal allows, the fan's edges inside its sides.
	var rad := minf(r.size.y - 26.0, (r.size.x / 2.0 - 3.0) / sin(clampf(half, PI / 6.0, PI / 2.0)))
	if mode <= 1:
		text(
			Vector2(r.position.x, r.get_center().y),
			"RADAR " + MODE_NAMES[mode],
			7.0,
			CYAN,
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x
		)
		shown.srch = {"mode": MODE_NAMES[mode]}
		return
	if not ag.is_empty():
		_asr(r, rd, ag, nm)
		return
	var ground := mode >= 7
	var col := GREY if ground else DARK_GREEN.lightened(0.25)
	for k in [0.25, 0.5, 0.75, 1.0]:
		ci.draw_arc(apex, rad * k, -PI / 2.0 - half, -PI / 2.0 + half, 32, col, THIN, true)
	for a in [-half, half]:
		line(apex, apex + Vector2(sin(a), -cos(a)) * rad, col, THIN)
	dashed_line(apex, apex + Vector2(0, -rad), DARK_GREY.lightened(0.2), THIN)
	# The antenna's azimuth (a dotted spoke); the real FCR's scan limits in search and TWS (two spokes).
	var ant: Vector2 = rd.get("antenna", Vector2.ZERO)
	if not ground and mode != 2 and real.is_empty():
		var aa := clampf(ant.x, -half, half)
		dashed_line(apex, apex + Vector2(sin(aa), -cos(aa)) * rad, CYAN.darkened(0.3), THIN, 2.0)
	if not real.is_empty() and mode in [4, 5] and not real.get("exp", false):
		var vol: Vector4 = real.volume
		for edge in [vol.x, vol.y]:
			var e := deg_to_rad(edge)
			dashed_line(apex, apex + Vector2(sin(e), -cos(e)) * rad, CYAN.darkened(0.3), THIN, 2.0)
	var shift := float(rd.get("shift", 0.0))
	var h := heading_rad()
	var lock_p = null
	var kinds := []
	for ct in rd.get("contacts", []):
		var bug: bool = ct.get("locked", false) or ct.get("selected", false)
		# The real FCR's ACM and BORE show nothing until the lock; STT the lock only; a TWS file flashes its last 8 s.
		if not real.is_empty() and (mode in [3, 6] or mode == 2) and not bug:
			continue
		if not real.is_empty() and mode == 5 and float(ct.get("age", 0.0)) > 5.0 and Time.get_ticks_msec() % 500 < 250:
			continue
		var p: Vector2
		if not real.is_empty() and ct.has("scope"):
			p = _fan_place(apex, rad, ct.scope)
		else:
			var az := float(ct.az) + shift
			var d := float(ct.dist) / (nm * 1852.0)
			if absf(az) > half or d > 1.0:
				continue
			p = apex + Vector2(sin(az), -cos(az)) * rad * d
		if not real.is_empty() and not r.has_point(p):
			continue
		var kind := track_kind(ct)
		kinds.append(kind)
		if ground:
			track(p, kind, null, true, 2.2)
		else:
			track(p, kind, deg_to_rad(float(ct.get("heading", 0.0))) - h, false, 2.6)
		if bug:
			circle(p, 5.2, WHITE, LINE)
			lock_p = p
		elif real.get("sam", []).has(ct.key):
			dashed_circle(p, 5.2, WHITE, THIN, 12)
		if not ground:
			_msl_mark(p, deg_to_rad(float(ct.get("heading", 0.0))) - h, String(ct.key))
	# The mode (the real FCR's names, inferred for the APG-81: its own are not public) and the scan.
	var mode_text: String = MODE_NAMES[mode]
	if not real.is_empty():
		var named := int(rd.get("last_aa", 4)) if mode == 2 else mode
		var names: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "fcr_mode", named)
		var sub: String = ClassDB.class_call_static("IafF16Mfd", "fcr_real_submode", named, real.vsr, real.acm)
		mode_text = "%s %s" % [names[0], sub] + (" STT" if mode == 2 else "")
		if mode in [4, 5]:
			var az: String = ClassDB.class_call_static("IafF16Mfd", "fcr_azimuth", deg_to_rad(2.0 * float(real.half)))
			text(Vector2(r.position.x + 2.0, r.end.y - 2.0), "%s B%d" % [az, int(real.bars)], 4.4, CYAN)
	text(Vector2(r.position.x + 2.0, r.position.y + 6.0), mode_text, 5.0, GREEN)
	var no_rad: bool = not real.is_empty() and not bool(rd.get("emit", false))
	if no_rad:
		text(Vector2(r.position.x, apex.y - rad * 0.3), "NO RAD", 6.0, YELLOW, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# The acquisition cursor (the real FCR's, search and TWS): two short bars, the altitudes it covers (kft).
	var cursor := false
	if not real.is_empty() and mode in [4, 5]:
		var q := _fan_place(apex, rad, real.cursor)
		cursor = true
		for dx in [-1.6, 1.6]:
			line(q + Vector2(dx, -3.0), q + Vector2(dx, 3.0), WHITE, LINE)
		var alt: Vector2 = real.get("cursor_alt", Vector2(NAN, NAN))
		if not is_nan(alt.x) and not real.vsr:
			text(q + Vector2(3.0, -1.0), "%d" % clampi(roundi(alt.x / 1000.0), -99, 99), 3.8, WHITE)
			text(q + Vector2(3.0, 4.0), "%d" % clampi(roundi(alt.y / 1000.0), -99, 99), 3.8, WHITE)
	shown.srch = {"mode": mode_text, "kinds": kinds, "cursor": cursor, "no_rad": no_rad}
	# The lock's data (STT / the TWS selection): range, aspect, closure, altitude.
	var lk: Dictionary = rd.get("lock", {})
	if lock_p != null and not lk.is_empty():
		var dist := (
			(Vector3(lk.pos) - Vector3(own_world().x, own_world().y, float(cockpit.state.get("alt_ft", 0.0)) * 0.3048))
			. length()
		)
		var alt := float(Vector3(lk.pos).z) * 3.28084 / 1000.0
		var row := "%.1f  %dK  Vc %d" % [dist / 1852.0, int(round(alt)), int(float(rd.get("closure", 0.0)) * 1.944)]
		text(Vector2(r.position.x, r.position.y + 12.0), row, 5.0, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# Ours: the post-launch time to active / to impact (modern-iaf/docs/weapons.md §8.2; the F-16 FCR's, inferred place).
	var mt = cockpit.weapons.get("msl_time")
	if mt != null:
		var tt := ("A%02d" if mt.active else "T%02d") % mini(ceili(float(mt.s)), 99)
		text(Vector2(r.position.x, r.position.y + 18.0), tt, 5.0, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 2.0)
		shown.srch["msl_time"] = tt
	# The steerpoint (a white circle on the fan when inside it).
	if not cockpit.waypoints.is_empty() and cockpit.current_waypoint < cockpit.waypoints.size():
		var w: Vector2 = cockpit.waypoints[cockpit.current_waypoint].world
		var rel := w - own_world()
		var az := atan2(rel.x, rel.y) - h
		az = wrapf(az, -PI, PI)
		var d := rel.length() / (nm * 1852.0)
		if absf(az) <= half and d <= 1.0:
			circle(apex + Vector2(sin(az), -cos(az)) * rad * d, 2.0, WHITE, THIN)
	ownship(apex + Vector2(0, -1.0), 3.0)


## Ours (modern-iaf/docs/weapons.md §8.2): a target the player's missile flies at carries a tail behind its symbol
## (heading `hd` on the fan), flashing once the missile's radar seeker is active, and an X for its last 8 s (the F-16
## FCR's marks; the APG-81's own are not public).
func _msl_mark(p: Vector2, hd: float, key: String) -> void:
	var mk: Dictionary = cockpit.weapons.get("msl_targets", {}).get(key, {})
	if mk.is_empty():
		return
	var fw := Vector2(sin(hd), -cos(hd))
	var rt := Vector2(-fw.y, fw.x)
	if not mk.active or Time.get_ticks_msec() % 500 < 250:
		var b := p - fw * 2.6
		poly(PackedVector2Array([b + rt, b - fw * 5.0 + rt, b - fw * 5.0 - rt, b - rt]), WHITE, THIN, true)
	if mk.final:
		line(p + Vector2(-4, -4), p + Vector2(4, 4), WHITE, THIN)
		line(p + Vector2(-4, 4), p + Vector2(4, -4), WHITE, THIN)


## A place on the real FCR's scope (0..1 across ±60°, up the range; radar.rs scope_xy) on the fan.
func _fan_place(apex: Vector2, rad: float, q: Vector2) -> Vector2:
	var az := (q.x - 0.5) * TAU / 3.0
	return apex + Vector2(sin(az), -cos(az)) * rad * q.y


## The real FCR's MFD window (the F-16's A-G display, MFD px; f16_mfd.gd _real_ground_map) that the ASR scales into
## its portal.
const AG_WINDOW := Rect2(12, 12, 108, 106)


## The ASR (the APG-81's air-to-surface format; LM slide 8 and a simulator manual show a grey SAR picture): the real
## FCR's ground map from the shared radar code (radar.rs render: GM's map, EXP / DBS1 / DBS2 patches, FZ, SP, CZ,
## STP / TGT, GMT's movers, SEA's ships, AGR) drawn grey and square in the portal; the fan in NORM; the ground
## tracks by their combat ID, a lock or the designated point ringed; the steerpoint; the X-Y cursor; the mode and
## the patch's name on top (the F-16's names stand in; the APG-81's own are not public, inferred).
func _asr(r: Rect2, rd: Dictionary, ag: Dictionary, nm: float) -> void:
	var side := minf(r.size.x - 6.0, r.size.y - 16.0)
	var sq := Rect2(Vector2(r.get_center().x - side / 2.0, r.position.y + 10.0), Vector2(side, side * 106.0 / 108.0))
	var k := side / AG_WINDOW.size.x
	var xf := Transform2D(0.0, Vector2(k, k), 0.0, sq.position - AG_WINDOW.position * k)
	var head := "%s %s" % [ag.name, ag.fov]
	var flags := []
	for f in [["FZ", ag.frozen], ["SP", ag.snowplow]]:
		if f[1]:
			flags.append(f[0])
	flags.append("TGT" if ag.tgt else "STP")
	text(Vector2(r.position.x + 2.0, r.position.y + 6.0), head, 5.0, GREEN)
	text(
		Vector2(r.position.x, r.position.y + 6.0),
		" ".join(flags) + " ",
		4.6,
		CYAN,
		HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x
	)
	var fr: Dictionary = ag.frame
	var picture := false
	if ag.name == "AGR":
		var m_agr := float(ag.agr)
		text(
			Vector2(sq.position.x, sq.get_center().y), "%.1f" % (m_agr / 1852.0) if m_agr >= 0.0 else "---", 7.0, WHITE
		)
	elif not fr.is_empty() and not cockpit.mfds.is_empty():
		# The radar's picture, drawn by the MFD node's own picture code through the portal's transform.
		ci.draw_set_transform_matrix(_base * xf)
		cockpit.mfds[0]._draw_ag_picture(rd, ag, ci, true)
		ci.draw_set_transform_matrix(_base)
		picture = cockpit.mfds[0]._ag_tex != null
	box(sq, GREY, THIN)
	var kinds := []
	if not fr.is_empty():
		var clip := PackedVector2Array(
			[sq.position, Vector2(sq.end.x, sq.position.y), sq.end, Vector2(sq.position.x, sq.end.y)]
		)
		if Vector2(fr.sym) == Vector2(66, 109):
			# NORM: the fan's edges at ±60° and its range arcs (f16_mfd.gd _fan).
			var apex: Vector2 = xf * Vector2(66, 109)
			var fan := 94.0 * k
			for a in [-PI / 3.0, PI / 3.0]:
				for seg in Geometry2D.intersect_polyline_with_polygon(
					PackedVector2Array([apex, apex + Vector2(sin(a), -cos(a)) * fan]), clip
				):
					poly(seg, GREY, THIN)
			for f in [0.5] if nm <= 10 else [0.25, 0.5, 0.75]:
				var pts := PackedVector2Array()
				for i in 25:
					var a := -PI / 3.0 + 2.0 * PI / 3.0 * i / 24.0
					pts.append(apex + Vector2(sin(a), -cos(a)) * fan * f)
				for seg in Geometry2D.intersect_polyline_with_polygon(pts, clip):
					poly(seg, GREY, THIN)
		var any_lock := false
		for ct in rd.get("contacts", []):
			var p: Vector2 = xf * Mfd.ag_px(fr, ct.pos)
			if not sq.has_point(p):
				continue
			# Every ground return the mode lists is a fused track (GMT the movers, SEA the ships; inferred).
			var kind := track_kind(ct)
			kinds.append(kind)
			track(p, kind, null, true, 2.2)
			if ct.locked:
				any_lock = true
				circle(p, 5.0, WHITE, LINE)
		if rd.get("designated", false) and not any_lock:
			var dp: Vector2 = xf * Mfd.ag_px(fr, rd.desig)
			if sq.has_point(dp):
				poly(
					PackedVector2Array(
						[dp + Vector2(0, -3), dp + Vector2(3, 0), dp + Vector2(0, 3), dp + Vector2(-3, 0)]
					),
					WHITE,
					LINE,
					true
				)
		if not cockpit.waypoints.is_empty() and cockpit.current_waypoint < cockpit.waypoints.size():
			var w: Vector2 = cockpit.waypoints[cockpit.current_waypoint].world
			var sp: Vector2 = xf * Mfd.ag_px(fr, Vector3(w.x, w.y, 0.0))
			if sq.has_point(sp):
				circle(sp, 2.0, WHITE, THIN)
		if ag.frozen:
			var op: Vector2 = xf * Mfd.ag_px(fr, Vector3(own_world().x, own_world().y, 0.0))
			if sq.has_point(op):
				ownship(op, 3.0)
	if ag.cursor != null:
		var q: Vector2 = xf * Vector2(ag.cursor)
		if sq.has_point(q):
			line(Vector2(sq.position.x, q.y), Vector2(q.x - 2.5, q.y), WHITE, THIN)
			line(Vector2(q.x + 2.5, q.y), Vector2(sq.end.x, q.y), WHITE, THIN)
			line(Vector2(q.x, sq.position.y), Vector2(q.x, q.y - 2.5), WHITE, THIN)
			line(Vector2(q.x, q.y + 2.5), Vector2(q.x, sq.end.y), WHITE, THIN)
	if not bool(rd.get("emit", false)):
		text(Vector2(r.position.x, sq.get_center().y), "NO RAD", 6.0, YELLOW, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	shown.asr = {"name": String(ag.name), "fov": String(ag.fov), "picture": picture, "kinds": kinds}


# --- SMS ---------------------------------------------------------------------------------------------------------

## The real stations (1..11, docs/f35i.md §3.1) of the game's A..I, and where they sit on the planform (x from the
## centreline, y down from the nose, in planform units).
const STATION_OF := [1, 3, 4, 5, 6, 7, 8, 9, 11]
const STATION_AT := {
	1: Vector2(-40, 62),
	3: Vector2(-27, 50),
	4: Vector2(-10, 40),
	5: Vector2(-5, 38),
	6: Vector2(0, 46),
	7: Vector2(5, 38),
	8: Vector2(10, 40),
	9: Vector2(27, 50),
	11: Vector2(40, 62)
}
## The F-35 seen from above (half outline, x ≥ 0; mirrored), planform units: the nose at y 0.
const PLANFORM := [
	Vector2(0, 0),
	Vector2(3, 10),
	Vector2(6, 22),
	Vector2(12, 32),
	Vector2(44, 58),
	Vector2(45, 66),
	Vector2(16, 68),
	Vector2(16, 74),
	Vector2(30, 86),
	Vector2(30, 92),
	Vector2(8, 92),
	Vector2(6, 96),
	Vector2(0, 96)
]


## The SMS (stores management): the planform with each station's store (green: missiles slim, bombs fat; the
## selected station boxed white), the selected weapon, the bays' doors, the gun, chaff and flares.
func sms(r: Rect2) -> void:
	var wp: Dictionary = cockpit.weapons
	var k := minf(r.size.x / 104.0, minf(r.size.y * 0.62, r.size.y - 47.0) / 100.0)  # the GUN line inside a short portal
	var o := Vector2(r.get_center().x, r.position.y + 14.0)
	var pts := PackedVector2Array()
	for p in PLANFORM:
		pts.append(o + p * k)
	for i in range(PLANFORM.size() - 1, -1, -1):
		pts.append(o + Vector2(-PLANFORM[i].x, PLANFORM[i].y) * k)
	poly(pts, GREY, LINE, true)
	# The bays (two long outlines either side of the centreline).
	for sx in [-1.0, 1.0]:
		box(Rect2(o + Vector2(sx * 12.5 - 6.0, 30) * k, Vector2(12.0, 22.0) * k), DARK_GREY.lightened(0.3), THIN)
	if wp.is_empty():
		return
	var sel := int(wp.get("selected", -1))
	for i in 9:
		var st: Dictionary = wp.stations[i]
		var at: Vector2 = o + STATION_AT[STATION_OF[i]] * k
		var n := int(st.count)
		var t := int(st.type)
		text(at + Vector2(-1.2, -9.5 * k), "%d" % STATION_OF[i], 3.6, GREY)
		if n > 0 and t > 0:
			_store(at, t, k)
			if n > 1:
				text(at + Vector2(1.6 * k, 8.5 * k), "%d" % n, 3.6, GREEN)
		else:
			line(at + Vector2(-1.5, 0), at + Vector2(1.5, 0), DARK_GREY.lightened(0.3), THIN)
		if i == sel:
			box(Rect2(at - Vector2(3.4, 9.0) * k, Vector2(6.8, 17.0) * k), WHITE, THIN)
	# The selected weapon (or none), its count; the gun; the countermeasures.
	var y := o.y + 100.0 * k
	var name := String(wp.get("name", ""))
	var label := "NO WPN SELECTED" if sel < 0 or name == "" else "%s  %d" % [name.to_upper(), int(wp.get("total", 0))]
	var lw := text_width(label, 5.0) + 6.0
	var lb := Rect2(Vector2(r.get_center().x - lw / 2.0, y), Vector2(lw, 7.5))
	fill(lb, Color(0.04, 0.16, 0.06))
	box(lb, GREEN, THIN)
	text(
		Vector2(lb.position.x, lb.end.y - 2.0),
		label,
		5.0,
		GREEN if wp.get("ready", true) else YELLOW,
		HORIZONTAL_ALIGNMENT_CENTER,
		lw
	)
	# Ours: the master arm over the weapon (Modern IAF's, SAFE until Shift+A; inferred), only where the game has one.
	if Settings.starts_safe():
		var arm: bool = wp.get("armed", false)
		text(
			Vector2(lb.position.x, lb.position.y - 1.5),
			"ARM" if arm else "SAFE",
			4.6,
			GREEN if arm else YELLOW,
			HORIZONTAL_ALIGNMENT_CENTER,
			lw
		)
	# Ours: the IR missile's seeker SPOT / SCAN (Ctrl + S; modern-iaf/docs/weapons.md §8.1), at the right of the weapon.
	var head: Dictionary = wp.get("srm_head", {})
	if not head.is_empty() and int(wp.get("type", 0)) in [570, 580]:
		text(
			Vector2(r.position.x, lb.end.y - 2.0),
			"SCAN" if head.scan else "SPOT",
			4.6,
			GREEN,
			HORIZONTAL_ALIGNMENT_RIGHT,
			r.size.x - 2.0
		)
	var cm := Rect2(Vector2(r.get_center().x - 16.0, y + 11.0), Vector2(32.0, 15.0))
	box(cm, GREY, THIN)
	text(Vector2(cm.position.x + 2.0, cm.position.y + 6.0), "CHAFF", 4.6, WHITE)
	text(Vector2(cm.position.x + 2.0, cm.position.y + 12.5), "FLARE", 4.6, WHITE)
	for j in 2:
		var cnt := int(wp.get(["chaff", "flares"][j], 0))
		text(
			Vector2(cm.position.x, cm.position.y + 6.0 + 6.5 * j),
			"%d " % cnt,
			4.6,
			WHITE if cnt > 0 else YELLOW,
			HORIZONTAL_ALIGNMENT_RIGHT,
			cm.size.x
		)
	text(Vector2(r.position.x + 2.0, cm.end.y + 7.0), "GUN %d" % int(wp.get("gun", 0)), 4.6, GREEN)


## A store's glyph on the planform: a missile slim with fins, a bomb fat, a tank fatter (bdb types).
func _store(at: Vector2, t: int, k: float) -> void:
	var missile := t in [570, 580, 590, 600, 610, 635, 640]
	var hl := 7.0 * k
	if missile:
		fill(Rect2(at - Vector2(0.55, hl), Vector2(1.1, 2.0 * hl)), GREEN)
		line(at + Vector2(-1.6, hl - 1.2), at + Vector2(1.6, hl - 1.2), GREEN, THIN)
	else:
		var w := 2.8 if t != 660 else 3.6
		ci.draw_rect(Rect2(at - Vector2(w / 2.0, hl * 0.85), Vector2(w, 1.7 * hl)), GREEN)


# --- TWD: the threats --------------------------------------------------------------------------------------------


## The TWD (threat warning display; its picture is open: inferred a heading-up threat circle like the F-16's RWR
## azimuth indicator). Modern IAF (ews.gd): the shared threat display's symbols (ews.rs Twd: each threat at its
## bearing on the ring of its lethality, its label by class, the top one in a diamond, a lock in a square, a launch in
## a flashing circle; the range's drones with their radars on show as "35" / "16"), yellow searching, red locking or
## launching, and the DAS's missile warnings (ews.rs Maw: an "M" at the missile's bearing with the seconds to impact).
## The 1998 game's F-35I: every RWR entry at its bearing and distance (37 km at the rim), its code.
func twd(r: Rect2) -> void:
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.48)
	var rad := minf(r.size.x * 0.44, r.size.y * 0.40)
	circle(c, rad, GREY, THIN)
	dashed_circle(c, rad * 0.5, DARK_GREY, THIN, 40)
	var h := heading_rad()
	for deg in range(0, 360, 30):
		var a := deg_to_rad(deg) - h
		var d := Vector2(sin(a), -cos(a))
		line(c + d * rad, c + d * (rad - 2.5), GREY, THIN)
	ownship(c, 3.5)
	var blink := int(Time.get_ticks_msec() / 300) % 2 == 0
	var n := 0
	var labels := []
	if cockpit.ews.has("symbols"):
		for sy in cockpit.ews.symbols:
			var p: Vector2 = c + Vector2(sy.at.x, -sy.at.y) * rad * 0.86
			var col := RED if sy.lethal or sy.launch else YELLOW
			labels.append(String(sy.label))
			n += 1
			if (sy.new or sy.launch) and not blink:
				continue
			var lw := text_width(sy.label, 5.0)
			text(p + Vector2(-lw / 2.0, 1.8), sy.label, 5.0, col)
			if sy.kind == "air":
				poly(
					PackedVector2Array([p + Vector2(-2.6, -5.4), p + Vector2(0, -7.2), p + Vector2(2.6, -5.4)]),
					col,
					THIN
				)
			if sy.launch:
				circle(p, 4.8, RED, LINE)
			elif sy.lethal:
				box(Rect2(p - Vector2(4.2, 4.6), Vector2(8.4, 8.4)), RED, THIN)
			if sy.diamond:
				poly(
					PackedVector2Array(
						[p + Vector2(0, -6.4), p + Vector2(6.0, 0), p + Vector2(0, 6.0), p + Vector2(-6.0, 0)]
					),
					col,
					THIN,
					true
				)
	else:
		for e in cockpit.rwr:
			if not e.get("active", false):
				continue
			var p := to_scope(e.pos, c, 37060.0 / rad)
			if p.distance_to(c) > rad:
				p = c + (p - c).normalized() * rad
			var code: String = THREAT_CODE.get(int(e.type), "U")
			var col := YELLOW if e.get("search", false) else RED
			var w := text_width(code, 5.0)
			text(p + Vector2(-w / 2.0, 1.8), code, 5.0, col)
			labels.append(code)
			if e.get("launch", false) and blink:
				circle(p, 4.8, RED, LINE)
			n += 1
	var maw := []
	for wn in cockpit.ews.get("maw", []):
		var d := Vector2(sin(float(wn.bearing)), -cos(float(wn.bearing)))
		var p := c + d * rad
		var tti := "--" if is_inf(float(wn.tti)) else "%d" % mini(int(wn.tti), 99)
		maw.append(tti)
		if blink:
			text(p + Vector2(-text_width("M", 6.0) / 2.0, 2.0), "M", 6.0, RED)
		text(p + Vector2(-text_width(tti, 4.6) / 2.0, 8.0), tti, 4.6, RED)
	shown.twd = {"labels": labels, "maw": maw}
	text(
		Vector2(r.position.x, r.end.y - 4.0),
		"%d THREATS" % n if n > 0 else "NO THREATS",
		4.8,
		RED if n > 0 else GREY,
		HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x
	)


# --- EFI: the flight instruments ---------------------------------------------------------------------------------


## The EFI (a simulator manual: the ADI over a partial HSI): the attitude ball (blue / brown), the speed and altitude
## boxes, the heading arc below.
func efi(r: Rect2) -> void:
	var st: Dictionary = cockpit.state
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.36)
	var rad := minf(r.size.x * 0.40, r.size.y * 0.30)
	var roll := deg_to_rad(float(st.get("roll", 0.0)))
	var pitch := float(st.get("pitch", 0.0))
	var k := rad / 40.0  # px per degree (±40° on the ball)
	var right := Vector2(cos(roll), -sin(roll))
	var down := Vector2(sin(roll), cos(roll))
	var hz := c + down * pitch * k
	var disc := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		disc.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(disc, SKY)
	var big := rad * 4.0
	var ground := PackedVector2Array(
		[hz - right * big, hz + right * big, hz + right * big + down * big, hz - right * big + down * big]
	)
	for piece in Geometry2D.intersect_polygons(disc, ground):
		if Geometry2D.triangulate_polygon(piece).size() > 0:
			ci.draw_colored_polygon(piece, EARTH)
	for p in range(-30, 31, 10):
		if p == 0:
			continue
		var m := hz - down * p * k
		var w := rad * 0.28
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([m - right * w, m + right * w]), disc):
			poly(seg, WHITE, THIN)
	for seg in Geometry2D.intersect_polyline_with_polygon(
		PackedVector2Array([hz - right * big, hz + right * big]), disc
	):
		poly(seg, WHITE, LINE)
	circle(c, rad, GREY, THIN)
	poly(
		PackedVector2Array(
			[
				c + Vector2(-rad * 0.5, 0),
				c + Vector2(-rad * 0.15, 0),
				c + Vector2(0, rad * 0.1),
				c + Vector2(rad * 0.15, 0),
				c + Vector2(rad * 0.5, 0)
			]
		),
		YELLOW,
		BOLD
	)
	# Speed (left) and altitude (right) boxes.
	for i in 2:
		var b := Rect2(Vector2(r.position.x + 2.0 if i == 0 else r.end.x - 26.0, c.y - 4.5), Vector2(24.0, 9.0))
		fill(b, Color.BLACK)
		box(b, WHITE, THIN)
		var v := (
			"%d" % int(st.get("ias_kt", 0.0)) if i == 0 else "%d" % int(round(float(st.get("alt_ft", 0.0)) / 10.0) * 10)
		)
		text(Vector2(b.position.x, b.end.y - 2.2), v, 5.6, WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
	text(Vector2(r.position.x + 2.0, c.y + 11.0), "M %.2f" % float(st.get("mach", 0.0)), 4.6, GREEN)
	text(Vector2(r.end.x - 26.0, c.y + 11.0), "G %.1f" % float(st.get("g", 1.0)), 4.6, GREEN)
	# The heading arc (±40°) with the lubber line.
	var hc := Vector2(c.x, r.end.y + r.size.y * 0.10)
	var hr := r.size.y * 0.34
	var hdg := float(st.get("heading", 0.0))
	ci.draw_arc(hc, hr, -PI / 2.0 - deg_to_rad(42), -PI / 2.0 + deg_to_rad(42), 32, GREY, THIN, true)
	for deg in range(int(hdg) - 40, int(hdg) + 41):
		if posmod(deg, 5) != 0:
			continue
		var a := deg_to_rad(deg - hdg)
		var d := Vector2(sin(a), -cos(a))
		var long := posmod(deg, 10) == 0
		line(hc + d * hr, hc + d * (hr - (2.6 if long else 1.4)), GREY, THIN)
		if posmod(deg, 30) == 0:
			var lab := "%d" % (posmod(deg, 360) / 10)
			text(hc + d * (hr - 6.5) + Vector2(-text_width(lab, 4.2) / 2.0, 1.5), lab, 4.2, WHITE)
	line(hc + Vector2(0, -hr - 3.0), hc + Vector2(0, -hr + 1.0), YELLOW, BOLD)
	var hb := Rect2(Vector2(hc.x - 9.0, hc.y - hr - 12.0), Vector2(18.0, 7.5))
	fill(hb, Color.BLACK)
	box(hb, WHITE, THIN)
	text(
		Vector2(hb.position.x, hb.end.y - 1.8),
		"%03d" % (int(round(hdg)) % 360),
		5.2,
		WHITE,
		HORIZONTAL_ALIGNMENT_CENTER,
		hb.size.x
	)


# --- ICAWS -------------------------------------------------------------------------------------------------------

## The damage flags as caution lines (docs/damage.md §5.2), each once.
const DAMAGE_CAUTIONS := [
	[[22, 16, 2], "ENGINE FAIL", "warning"],
	[[8], "AB FAIL", "caution"],
	[[11], "INS FAIL", "caution"],
	[[10], "FUEL LEAK", "caution"],
	[[15], "RADAR FAIL", "caution"],
	[[18], "FCS DEGD", "caution"],
	[[14], "RWR FAIL", "caution"],
	[[24], "FCS FAIL", "warning"],
	[[20], "WPN FAIL", "caution"],
	[[4], "FLAPS FAIL", "caution"],
	[[13], "GUN FAIL", "caution"],
	[[7], "GEAR FAIL", "caution"],
	[[1], "ECM FAIL", "caution"],
	[[12], "HMD FAIL", "caution"],
	[[6], "AP FAIL", "caution"],
	[[5], "BRAKES FAIL", "caution"],
	[[19, 21], "ELEC FAIL", "caution"]
]


## The ICAWS lines, worst first: [text, "warning" | "caution" | "advisory"].
func icaws_lines(base: Array) -> Array:
	var out: Array = base.duplicate()
	var flags: Array = cockpit.damage_flags
	for row in DAMAGE_CAUTIONS:
		if row[0].any(func(f): return f < flags.size() and flags[f]):
			out.append([row[1], row[2]])
	out.sort_custom(
		func(a, b): return ["warning", "caution", "advisory"].find(a[1]) < ["warning", "caution", "advisory"].find(b[1])
	)
	return out


func level_colour(level: String) -> Color:
	return {"warning": RED, "caution": YELLOW}.get(level, GREEN)


func icaws(r: Rect2, lines: Array) -> void:
	text(Vector2(r.position.x + 3.0, r.position.y + 7.0), "WARNING / CAUTION / ADVISORY", 4.2, GREY)
	if lines.is_empty():
		text(Vector2(r.position.x, r.get_center().y), "NO ICAWS", 6.0, GREEN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	for i in mini(lines.size(), int((r.size.y - 14.0) / 8.0)):
		var col := level_colour(lines[i][1])
		var y := r.position.y + 16.0 + 8.0 * i
		if lines[i][1] == "warning":
			fill(Rect2(r.position.x + 2.0, y - 5.6, r.size.x - 4.0, 7.2), Color(0.35, 0.03, 0.02))
		text(Vector2(r.position.x + 4.0, y), lines[i][0], 5.4, col)


# --- FUEL and ENG ------------------------------------------------------------------------------------------------

## JOKER / BINGO (lb; inferred: the game sets none, the F-35A's 18,250 lb internal fuel × 0.3 / 0.2).
const JOKER_LB := 5500.0
const BINGO_LB := 3600.0
const INTERNAL_LB := 18250.0


func fuel(r: Rect2) -> void:
	var st: Dictionary = cockpit.state
	var total := float(st.get("fuel_lbs", 0.0))
	var internal := minf(total, float(st.get("internal_fuel_kg", total / 2.20462)) * 2.20462)
	var external := maxf(0.0, total - internal)
	var x := r.position.x + 4.0
	var y := r.position.y + 12.0
	text(Vector2(x, y), "TOTAL", 4.6, GREY)
	text(Vector2(r.position.x, y), "%d " % int(total), 6.5, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 3.0)
	text(Vector2(x, y + 9.0), "INT", 4.6, GREY)
	text(Vector2(r.position.x, y + 9.0), "%d " % int(internal), 5.6, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 3.0)
	text(Vector2(x, y + 17.0), "EXT", 4.6, GREY)
	text(Vector2(r.position.x, y + 17.0), "%d " % int(external), 5.6, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 3.0)
	# The internal tank bar (light purple) with the JOKER / BINGO marks (white).
	var bar := Rect2(Vector2(r.get_center().x - 5.0, y + 28.0), Vector2(10.0, minf(r.end.y - y - 40.0, 80.0)))
	box(bar, GREY, THIN)
	var f := clampf(internal / INTERNAL_LB, 0.0, 1.0)
	fill(Rect2(Vector2(bar.position.x, bar.end.y - bar.size.y * f), Vector2(bar.size.x, bar.size.y * f)), PURPLE)
	for m in [[JOKER_LB, "JOKER"], [BINGO_LB, "BINGO"]]:
		var my := bar.end.y - bar.size.y * float(m[0]) / INTERNAL_LB
		line(Vector2(bar.position.x - 3.0, my), Vector2(bar.end.x + 3.0, my), WHITE, THIN)
		text(Vector2(bar.end.x + 4.0, my + 1.6), m[1], 4.0, YELLOW if internal < float(m[0]) else WHITE)


func engine(r: Rect2) -> void:
	var st: Dictionary = cockpit.state
	var rpm := float(st.get("rpm", 0.0)) * 100.0
	var thr := float(st.get("throttle", 0.0)) * 100.0
	var ab := float(st.get("afterburner", 0.0)) > 0.0
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.30)
	var rad := minf(r.size.x * 0.34, r.size.y * 0.22)
	gauge(c, rad, rpm / 110.0, "%d" % int(round(rpm)), "RPM %", YELLOW if ab else GREEN)
	var y := c.y + rad + 14.0
	for row in [
		["THROTTLE", "%d %%" % int(round(thr))],
		["AB", "ON" if ab else "OFF"],
		["THRUST", "%d %%" % int(round(maxf(rpm - 30.0, 0.0) / 70.0 * 100.0)) if not ab else "MAX AB"]
	]:
		text(Vector2(r.position.x + 4.0, y), row[0], 4.6, GREY)
		text(
			Vector2(r.position.x, y),
			row[1] + " ",
			5.6,
			YELLOW if row[0] == "AB" and ab else WHITE,
			HORIZONTAL_ALIGNMENT_RIGHT,
			r.size.x - 3.0
		)
		y += 9.0


## A round gauge: a 270° scale, the needle at `f` (0..1), the value under it.
func gauge(c: Vector2, rad: float, f: float, value: String, label: String, col: Color) -> void:
	var a0 := deg_to_rad(135.0)
	var span := deg_to_rad(270.0)
	ci.draw_arc(c, rad, a0, a0 + span, 40, GREY, THIN, true)
	ci.draw_arc(c, rad - 0.8, a0, a0 + span * clampf(f, 0.0, 1.0), 40, col, BOLD, true)
	var a := a0 + span * clampf(f, 0.0, 1.0)
	line(c, c + Vector2(cos(a), sin(a)) * (rad - 1.5), WHITE, LINE)
	text(Vector2(c.x - rad, c.y + rad * 0.62), value, 6.5, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 2.0 * rad)
	text(Vector2(c.x - rad, c.y + rad + 7.0), label, 4.2, GREY, HORIZONTAL_ALIGNMENT_CENTER, 2.0 * rad)


# --- TFLIR -------------------------------------------------------------------------------------------------------


## The TFLIR (the EOTS's picture, "TFLIR" on the displays): the EO camera's picture (the game's FLIR view) square
## in the portal, the cross, the zoom, WIDE / SPOT, the laser and the range.
func tflir(r: Rect2) -> void:
	var side := minf(r.size.x - 4.0, r.size.y - 22.0)
	var v := Rect2(Vector2(r.get_center().x - side / 2.0, r.position.y + 12.0), Vector2(side, side))
	var eo: Dictionary = cockpit.eo
	if cockpit.eo_texture != null and eo.get("camera", false):
		ci.draw_texture_rect(cockpit.eo_texture, v, false)
	else:
		fill(v, Color(0.06, 0.07, 0.08))
		text(Vector2(v.position.x, v.get_center().y), "NO VIDEO", 6.0, GREY, HORIZONTAL_ALIGNMENT_CENTER, v.size.x)
	box(v, GREY, THIN)
	var f: Dictionary = eo.get("flir", {})
	# The cross is the line of sight (the laser spot, FUN_00450480's centre pixel): fixed at the picture's centre.
	var cc := v.get_center()
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		line(cc + d * 2.5, cc + d * 8.0, WHITE, LINE)
	if f.is_empty():
		return
	text(Vector2(v.position.x + 2.0, v.position.y - 2.0), "Z%d" % int(f.zoom), 4.6, GREEN)
	text(
		Vector2(v.position.x, v.position.y - 2.0),
		"SPOT" if f.spot else "WIDE",
		4.6,
		GREEN,
		HORIZONTAL_ALIGNMENT_RIGHT,
		v.size.x - 2.0
	)
	text(
		Vector2(v.position.x + 2.0, v.end.y + 7.0),
		"LSR ARM" if f.laser else "LSR SAFE",
		4.6,
		YELLOW if f.laser else GREEN
	)
	text(Vector2(v.position.x, v.end.y + 7.0), String(f.range), 4.6, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, v.size.x - 2.0)


# --- MENU --------------------------------------------------------------------------------------------------------


## The MENU grid: every format a button (3 columns), the current one white. Returns the buttons' rects by name. The
## same grid with other `names` under another `title`: the strip's MENU page, a CNTL page.
func menu(r: Rect2, current: String, names: Array = FORMATS, title := "MENU") -> Dictionary:
	var out := {}
	var cols := 3
	var bw := (r.size.x - 8.0) / cols
	var bh := 13.0
	text(Vector2(r.position.x, r.position.y + 8.0), title, 6.0, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in names.size():
		var b := Rect2(
			Vector2(r.position.x + 4.0 + bw * (i % cols), r.position.y + 14.0 + (bh + 3.0) * (i / cols)),
			Vector2(bw - 3.0, bh)
		)
		var on: bool = names[i] == current
		box(b, WHITE if on else CYAN, THIN)
		text(
			Vector2(b.position.x, b.end.y - 4.0),
			names[i],
			5.2,
			WHITE if on else CYAN,
			HORIZONTAL_ALIGNMENT_CENTER,
			b.size.x
		)
		out[names[i]] = b
	return out
