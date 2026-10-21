# Ours (the F-35I, docs/f35i.md §4.3, docs/real-mfd.md "F-35I"): the panoramic cockpit display (PCD) as the real one
# lays it out, from the cockpit's [PCD] section (panel px, tools/f35i/cockpit3d.py): the black glass; the Function
# Access Button strip along its top (engine, fuel, weapons, gear, ICAWS, autopilot, SWAP, radios, recorder, MENU, the
# time and alerts); four portals, each a format (pcd_formats.gd) with its name and master mode, its option legends and
# two sub-portal tabs that swap in; a portal's MENU grid; and the standby display (ESIS) under the glass. Layer 0 draws
# it all; layer 1, over it, only the glass's sheen. Each portal keeps an MFD node (mfd.gd, hidden) whose page follows
# the format, so the systems that read the pages (the EO camera, the M key, the full-screen MFD) work as before.
extends Control

const Formats := preload("res://cockpit/pcd_formats.gd")
const F := Formats
const SKY := Color(0.16, 0.46, 0.86)
const GROUND := Color(0.50, 0.30, 0.12)
const WHITE := Color(0.94, 0.96, 0.98)
const AMBER := Color(1.0, 0.74, 0.12)
const FAB_H := 26.0  # the strip's height, panel px (about 0.9 in of the 8 in glass)
const TAB_H := 11.0
const HEAD_H := 15.0
## The game page each format drives (the hidden MFD node's page; none: the page stays).
const PAGE_OF := {"TSD-1": 3, "TSD-2": 3, "TSD-3": 3, "SRCH": 2, "SMS": 1, "TFLIR": 6, "TWD": 7, "EFI": 9, "ICAWS": 4}
## The format a game page shows when something else sets it (the M key, a weapon, the full-screen MFD).
const FORMAT_OF := {
	0: "TSD-1", 1: "SMS", 2: "SRCH", 3: "TSD-1", 4: "ICAWS", 5: "TFLIR", 6: "TFLIR", 7: "TWD", 9: "EFI", 10: "SMS"
}

var cockpit: Control
var layer := 0
var font: Font
var fmt: Formats
## Per portal: the main format, its two sub-portal tabs, the MENU grid open, the page last seen on its MFD node.
var main := ["TSD-1", "SRCH", "SMS", "TWD"]
var tabs := [["FUEL", "ENG"], ["TFLIR", "EFI"], ["TSD-2", "ICAWS"], ["TSD-3", "EFI"]]
var menu_open := [false, false, false, false]
var _page_seen := [-1, -1, -1, -1]
## Clickable areas of the last frame: [Rect2 (screen px), Callable].
var _hits: Array = []


func setup(c: Control, l: int) -> void:
	cockpit = c
	layer = l
	mouse_filter = Control.MOUSE_FILTER_IGNORE if l == 1 else Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(
		["Arial Narrow", "Liberation Sans Narrow", "DejaVu Sans Condensed", "Arial", "Liberation Sans"]
	)
	sf.font_weight = 600
	sf.multichannel_signed_distance_field = true
	font = sf
	fmt = Formats.new(self, c, font)


func _process(_delta: float) -> void:
	modulate = Color(0.8, 0.8, 0.8) if cockpit != null and cockpit.night else Color.WHITE  # dimmed at night
	if layer == 0 and cockpit != null:
		_follow_pages()
	queue_redraw()


## A rect of the [PCD] section (panel px [x, y, w, h]) on screen.
func _rect(r: Array) -> Rect2:
	var a: Vector2 = cockpit.panel_to_screen(float(r[0]), float(r[1]))
	return Rect2(a, Vector2(float(r[2]), float(r[3])) * cockpit.ui_scale())


func glass() -> Rect2:
	return _rect(cockpit.layout.PCD.Rect)


## The four portals' screen rects, left to right (under the strip, to the glass's foot).
func portals() -> Array:
	var g := glass()
	var s: float = cockpit.ui_scale()
	var top := g.position.y + FAB_H * s
	var w := g.size.x / 4.0
	var out := []
	for i in 4:
		out.append(Rect2(g.position.x + i * w, top, w, g.end.y - top))
	return out


# --- portals and their pages ----------------------------------------------------------------------------------------


## Keeps each portal's format and its MFD node's page together: a page set elsewhere (the M key, a weapon) picks the
## matching format; a format the pilot picks sets the page.
func _follow_pages() -> void:
	for i in mini(4, cockpit.mfds.size()):
		var m = cockpit.mfds[i]
		m.visible = false
		if m.page != _page_seen[i]:
			_page_seen[i] = m.page
			var want: String = FORMAT_OF.get(int(m.page), main[i])
			if PAGE_OF.get(main[i], -1) != int(m.page) and want != main[i]:
				_show(i, want)


## Portal `i` shows format `f`: a tab holding it swaps with the main format; the MFD node's page follows.
func _show(i: int, f: String) -> void:
	if f == "MENU":
		menu_open[i] = true
		return
	var t: int = tabs[i].find(f)
	if t >= 0:
		tabs[i][t] = main[i]
	main[i] = f
	menu_open[i] = false
	if i < cockpit.mfds.size() and PAGE_OF.has(f):
		cockpit.mfds[i].page = PAGE_OF[f]
		_page_seen[i] = PAGE_OF[f]


func _gui_input(event: InputEvent) -> void:
	if layer != 0 or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position
	for h in _hits:
		if h[0].has_point(p):
			h[1].call()
			accept_event()
			return


## A clickable area in the current portal transform (`r` in panel px from `origin`).
func _hit(origin: Vector2, r: Rect2, f: Callable) -> void:
	var s: float = cockpit.ui_scale()
	_hits.append([Rect2(origin + r.position * s, r.size * s), f])


# --- drawing ------------------------------------------------------------------------------------------------------


func _draw() -> void:
	if cockpit == null or not cockpit.layout.has("PCD"):
		return
	if layer == 1:
		_draw_sheen()
		return
	_hits.clear()
	var g := glass()
	draw_rect(g, Color.BLACK)
	_draw_fab(g)
	var ps := portals()
	for i in 4:
		_draw_portal(i, ps[i])
	# The two halves (each with its own power and processor): a dark seam down the middle.
	var s: float = cockpit.ui_scale()
	draw_line(
		Vector2(g.get_center().x, g.position.y),
		Vector2(g.get_center().x, g.end.y),
		Color(0.12, 0.13, 0.15),
		maxf(1.0, s * 0.9)
	)
	draw_rect(g, Color(0.10, 0.11, 0.13), false, maxf(1.0, s))
	_draw_esis(_rect(cockpit.layout.PCD.Esis))


## The master mode under a portal's format name: NAV, A-A or A-S (a simulator manual), from the HUD mode.
func master_mode() -> String:
	var hm := int(cockpit.weapons.get("hud_mode", 0))
	return "A-A" if hm in [1, 2, 3] else ("A-S" if hm >= 4 else "NAV")


func _draw_portal(i: int, pr: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var pw := pr.size.x / s
	var ph := pr.size.y / s
	fmt.begin(pr.position, s)
	# Frame lines between portals (grey, thin).
	if i > 0:
		fmt.line(Vector2(0, 0), Vector2(0, ph), F.DARK_GREY, F.THIN)
	var name: String = main[i]
	var shown := name
	if name == "SRCH" and int(cockpit.radar.get("mode", 0)) >= 7:
		shown = "ASR"
	# The header: the format name over the master mode (tap: the MENU grid); CNTL on the right.
	fmt.text(Vector2(3.0, 6.5), shown.replace("-", ""), 5.6, F.GREEN)
	fmt.text(Vector2(3.0, 12.5), master_mode(), 4.6, F.GREEN)
	fmt.legend(Vector2(pw - 3.0, 6.5), "CNTL>", true)
	_hit(pr.position, Rect2(0, 0, 30, HEAD_H), func(): menu_open[i] = not menu_open[i])
	var body := Rect2(2.0, HEAD_H + 1.0, pw - 4.0, ph - HEAD_H - TAB_H - 4.0)
	if menu_open[i]:
		var buttons: Dictionary = fmt.menu(body, name)
		for f in buttons:
			_hit(pr.position, buttons[f], func(): _show(i, f))
	else:
		_draw_format(i, name, body, pr.position, pw)
	# The two sub-portal tabs (cyan, swap in on a tap) and the corner arrows.
	for t in 2:
		var tr := Rect2(pw * (0.10 + 0.42 * t), ph - TAB_H - 1.0, pw * 0.36, TAB_H - 1.5)
		fmt.box(tr, F.CYAN, F.THIN)
		fmt.text(
			Vector2(tr.position.x, tr.end.y - 2.6),
			tabs[i][t].replace("-", ""),
			5.0,
			F.CYAN,
			HORIZONTAL_ALIGNMENT_CENTER,
			tr.size.x
		)
		_hit(pr.position, tr, func(): _show(i, tabs[i][t]))
	for side: float in [0.0, 1.0]:
		var x := 2.5 + side * (pw - 5.0)
		var d := 1.0 if side == 0.0 else -1.0
		fmt.poly(
			PackedVector2Array([Vector2(x, ph - 6.0), Vector2(x + 3.0 * d, ph - 9.0), Vector2(x + 3.0 * d, ph - 3.0)]),
			F.CYAN,
			F.THIN,
			true
		)
	fmt.end()


func _draw_format(i: int, name: String, body: Rect2, origin: Vector2, pw: float) -> void:
	var m = cockpit.mfds[i] if i < cockpit.mfds.size() else null
	match name:
		"TSD-1", "TSD-2", "TSD-3":
			var scale: int = m.tsd_scale if m != null else 40
			var map_on: bool = m.tsd_options[2] if m != null else true
			fmt.tsd(body, scale, map_on)
			_range_legends(origin, body, "%d" % scale, func(d): _tsd_range(m, d))
			fmt.legend(Vector2(pw - 3.0, body.position.y + 26.0), "MAP", true, map_on)
			_hit(origin, Rect2(pw - 18.0, body.position.y + 20.0, 16.0, 8.0), func(): _toggle_map(m))
		"SRCH":
			fmt.radar(body)
			var rd: Dictionary = cockpit.radar
			_range_legends(
				origin, body, "%d" % F.RANGES[clampi(int(rd.get("idx", 1)), 1, 6) - 1], func(d): _radar_range(m, d)
			)
			fmt.legend(Vector2(pw - 3.0, body.position.y + 26.0), "MODE", true)
			_hit(origin, Rect2(pw - 22.0, body.position.y + 20.0, 20.0, 8.0), func(): _radar_mode(m))
		"SMS":
			fmt.sms(body)
		"TFLIR":
			fmt.tflir(body)
		"TWD":
			fmt.twd(body)
		"EFI":
			fmt.efi(body)
		"ICAWS":
			fmt.icaws(body, fmt.icaws_lines(cautions()))
		"FUEL":
			fmt.fuel(body)
		"ENG":
			fmt.engine(body)


## The range legends down the left edge: ▲, the range, ▼ (taps step it).
func _range_legends(origin: Vector2, body: Rect2, value: String, step: Callable) -> void:
	var y := body.position.y + 20.0
	fmt.poly(PackedVector2Array([Vector2(3, y), Vector2(6, y - 4), Vector2(9, y)]), F.CYAN, F.THIN, true)
	fmt.text(Vector2(3.0, y + 8.0), value, 5.0, F.CYAN)
	fmt.poly(PackedVector2Array([Vector2(3, y + 11), Vector2(6, y + 15), Vector2(9, y + 11)]), F.CYAN, F.THIN, true)
	_hit(origin, Rect2(1, y - 6, 12, 7), func(): step.call(1))
	_hit(origin, Rect2(1, y + 10, 12, 7), func(): step.call(-1))


func _toggle_map(m) -> void:
	if m != null:
		m.tsd_options[2] = not m.tsd_options[2]


func _radar_range(m, d: int) -> void:
	if m != null:
		m.step_range(d)


func _radar_mode(m) -> void:
	if m != null:
		m.cycle_radar_mode()


func _tsd_range(m, d: int) -> void:
	if m == null:
		return
	var sc: Array = m.TSD_SCALES
	m.tsd_scale = sc[clampi(sc.find(m.tsd_scale) + d, 0, sc.size() - 1)]


## The cautions the lamps / indicators raise (docs/cockpit.md "Panel lights"), worst first: [text, level].
func cautions() -> Array:
	var ind: Array = cockpit.indicators
	var out := []
	if ind[1] or ind[2]:
		out.append(["ENG FIRE", "warning"])
	if ind[0]:
		out.append(["MASTER CAUTION", "caution"])
	if ind[3]:
		out.append(["RWR AIR THREAT", "caution"])
	if ind[4]:
		out.append(["RWR SAM THREAT", "caution"])
	if ind[5]:
		out.append(["SPEED BRAKE", "advisory"])
	if ind[6]:
		out.append(["ECM ON", "advisory"])
	return out


# --- the Function Access Button strip ----------------------------------------------------------------------------


## The strip along the glass's top (a pilot: "always has a small fuel section"; the order from the Driven
## Technologies picture and a simulator manual): engine dial, fuel, weapon counts, the gear planform, ICAWS, AP / AT,
## SWAP across the halves' seam, the radios, the recorder, MENU, then the time and alerts.
func _draw_fab(g: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var pw := g.size.x / s
	var ph := FAB_H
	var st: Dictionary = cockpit.state
	var wp: Dictionary = cockpit.weapons
	fmt.begin(g.position, s)
	fmt.line(Vector2(0, ph), Vector2(pw, ph), F.DARK_GREY, F.THIN)
	# Engine: the RPM dial.
	var rpm := float(st.get("rpm", 0.0))
	var ab := float(st.get("afterburner", 0.0)) > 0.0
	var ec := Vector2(14, 13)
	draw_arc(ec, 9.0, deg_to_rad(135), deg_to_rad(405), 32, F.GREEN, F.THIN, true)
	var a := deg_to_rad(135.0 + 270.0 * clampf(rpm / 1.1, 0.0, 1.0))
	fmt.line(ec, ec + Vector2(cos(a), sin(a)) * 8.0, F.YELLOW if ab else F.GREEN, F.LINE)
	fmt.text(Vector2(5, 24.5), "%d" % int(round(rpm * 100.0)), 4.2, F.WHITE)
	if ab:
		fmt.box(Rect2(20, 19.5, 9, 6), F.YELLOW, F.THIN)
		fmt.text(Vector2(21, 24.4), "AB", 4.0, F.YELLOW)
	# Fuel: total / internal / external with light purple bars.
	var total := float(st.get("fuel_lbs", 0.0))
	var internal := minf(total, float(st.get("internal_fuel_kg", total / 2.20462)) * 2.20462)
	var rows := [["T", total, F.INTERNAL_LB + 5000.0], ["I", internal, F.INTERNAL_LB], ["E", total - internal, 5000.0]]
	for k in 3:
		var y := 7.5 + 7.0 * k
		fmt.text(Vector2(30, y), rows[k][0], 4.4, F.GREEN)
		fmt.text(Vector2(30, y), "%.1f" % (float(rows[k][1]) / 1000.0), 4.4, F.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 22.0)
		fmt.fill(Rect2(54, y - 4.6, 8.0 * clampf(float(rows[k][1]) / float(rows[k][2]), 0.0, 1.0) + 0.6, 5.0), F.PURPLE)
	fmt.text(Vector2(64, 24.5), "JKR %.1f" % (F.JOKER_LB / 1000.0), 3.6, F.WHITE if total > F.JOKER_LB else F.YELLOW)
	# Weapons: the counts.
	var bombs := 0
	for st2 in wp.get("stations", []).slice(0, 9):
		if int(st2.type) in [500, 510, 520, 530, 540, 650]:
			bombs += int(st2.count)
	var counts := [["MRM", int(wp.get("mrm", 0))], ["SRM", int(wp.get("srm", 0))], ["BOMB", bombs]]
	for k in 3:
		fmt.text(Vector2(80, 7.5 + 7.0 * k), "%d %s" % [counts[k][1], counts[k][0]], 4.4, F.GREEN)
	fmt.text(Vector2(103, 7.5), "%d" % int(wp.get("chaff", 0)), 4.4, F.WHITE)
	fmt.text(Vector2(103, 14.5), "%d" % int(wp.get("flares", 0)), 4.4, F.WHITE)
	fmt.text(Vector2(103, 21.5), "%d" % int(wp.get("gun", 0)), 4.4, F.WHITE)
	# The gear planform: green with the legs down, the legs' lights.
	var gc := Vector2(126, 12)
	var gpts := PackedVector2Array()
	for p in [
		Vector2(0, -9),
		Vector2(1.5, -3),
		Vector2(7, 3),
		Vector2(7, 5),
		Vector2(2, 4),
		Vector2(3, 9),
		Vector2(-3, 9),
		Vector2(-2, 4),
		Vector2(-7, 5),
		Vector2(-7, 3),
		Vector2(-1.5, -3)
	]:
		gpts.append(gc + p)
	var legs: Array = cockpit.gear_legs
	var down := legs.all(func(v): return v == 2)
	fmt.poly(gpts, F.GREEN if down else F.GREY, F.LINE, true)
	for k in 3:
		var at: Vector2 = gc + [Vector2(0, -6), Vector2(-4, 5), Vector2(4, 5)][k]
		var v: int = legs[k]
		if v == 2:
			fmt.fill(Rect2(at - Vector2(1.1, 1.1), Vector2(2.2, 2.2)), F.GREEN)
		elif v == 1:
			fmt.fill(Rect2(at - Vector2(1.1, 1.1), Vector2(2.2, 2.2)), F.RED)
	fmt.text(Vector2(116, 25), "FLAPS " + ["UP", "TR", "DN"][clampi(cockpit.flaps_state, 0, 2)], 3.4, F.GREEN)
	# ICAWS: the worst line.
	var lines: Array = fmt.icaws_lines(cautions())
	fmt.text(Vector2(142, 10.5), "ICAWS", 5.6, F.CYAN if lines.is_empty() else fmt.level_colour(lines[0][1]))
	if not lines.is_empty():
		fmt.text(
			Vector2(142, 19.5),
			lines[0][0] + ("  +%d" % (lines.size() - 1) if lines.size() > 1 else ""),
			4.4,
			fmt.level_colour(lines[0][1])
		)
	# AP / AT.
	var ap_on: bool = cockpit.indicators[8]
	var mode := int(st.get("ap_mode", 0))
	fmt.text(
		Vector2(200, 10.5),
		"AP" + ([" ", " LVL", " NAV"][clampi(mode, 0, 2)] if ap_on else ""),
		4.8,
		F.GREEN if ap_on else F.GREY
	)
	fmt.text(Vector2(200, 19.5), "AT", 4.8, F.GREY)
	# SWAP across the seam.
	var cx := pw / 2.0
	fmt.poly(PackedVector2Array([Vector2(cx - 13, 13), Vector2(cx - 5, 5), Vector2(cx - 5, 21)]), F.CYAN, F.THIN, true)
	fmt.poly(PackedVector2Array([Vector2(cx + 13, 13), Vector2(cx + 5, 5), Vector2(cx + 5, 21)]), F.CYAN, F.THIN, true)
	fmt.text(Vector2(cx - 12, 15), "SW", 3.8, F.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 7.0)
	fmt.text(Vector2(cx + 5, 15), "AP", 3.8, F.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 7.0)
	# The radios: A / B / C on UHF.
	for k in 3:
		fmt.text(Vector2(cx + 20, 8.0 + 7.0 * k), "%s  U  1" % ["A", "B", "C"][k], 4.2, F.GREEN)
	fmt.text(Vector2(cx + 46, 8.0), "NAV", 4.2, F.GREEN)
	fmt.text(Vector2(cx + 46, 15.0), "RTE %d" % (cockpit.current_waypoint + 1), 4.2, F.WHITE)
	# The recorder.
	fmt.text(Vector2(cx + 70, 7.5), "RECORDER", 4.0, F.CYAN)
	var rec := Settings.blackbox
	fmt.circle(Vector2(cx + 79, 14.5), 2.6, F.GREEN if rec else F.GREY, F.THIN)
	if rec:
		fmt.circle(Vector2(cx + 79, 14.5), 1.1, F.RED, F.LINE)
	var tod := int(st.get("tod", 0.0))
	fmt.text(Vector2(cx + 70, 23.5), "%02d:%02d:%02d" % [(tod / 3600) % 24, (tod / 60) % 60, tod % 60], 4.0, F.GREEN)
	# MENU: the grid icon.
	var mg := Rect2(cx + 104, 4, 18, 18)
	for k in 4:
		fmt.line(
			Vector2(mg.position.x, mg.position.y + 6.0 * k), Vector2(mg.end.x, mg.position.y + 6.0 * k), F.GREY, F.THIN
		)
		fmt.line(
			Vector2(mg.position.x + 6.0 * k, mg.position.y), Vector2(mg.position.x + 6.0 * k, mg.end.y), F.GREY, F.THIN
		)
	fmt.text(
		Vector2(mg.position.x, mg.get_center().y + 1.8), "MENU", 4.6, F.WHITE, HORIZONTAL_ALIGNMENT_CENTER, mg.size.x
	)
	# The right block: speed / altitude, the alerts (CABIN, GCAS, ALOW), the time.
	var rx := cx + 128
	fmt.text(Vector2(rx, 7.5), "CAS %d" % int(st.get("ias_kt", 0.0)), 4.2, F.WHITE)
	fmt.text(Vector2(rx, 14.5), "ALT %d" % int(round(float(st.get("alt_ft", 0.0)) / 10.0) * 10), 4.2, F.WHITE)
	fmt.text(Vector2(rx, 21.5), "M %.2f" % float(st.get("mach", 0.0)), 4.2, F.WHITE)
	var low := float(st.get("agl_ft", 9999.0)) < 500.0 and not bool(st.get("on_ground", false))
	fmt.text(Vector2(rx + 36, 7.5), "CABIN", 4.2, F.GREEN)
	fmt.text(Vector2(rx + 36, 14.5), "GCAS", 4.2, F.GREEN)
	fmt.text(Vector2(rx + 36, 21.5), "ALOW 500", 4.2, F.YELLOW if low else F.GREEN)
	fmt.text(
		Vector2(rx, 7.5),
		"%02d:%02d Z" % [(tod / 3600) % 24, (tod / 60) % 60],
		4.2,
		F.WHITE,
		HORIZONTAL_ALIGNMENT_RIGHT,
		pw - rx - 3.0
	)
	fmt.end()


func _fs(px: float) -> int:
	return maxi(int(px * cockpit.ui_scale()), 4)


func _text(at: Vector2, t: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, t, align, width, _fs(size), col)


# --- the standby display ------------------------------------------------------------------------------------------


## The ESIS (electronic standby instrument): the attitude sphere as a flat sky / ground split rolled and pitched
## (2 px per degree of the 60° tall field), pitch lines every 10°, the fixed aircraft, speed and altitude boxes and
## the heading.
func _draw_esis(r: Rect2) -> void:
	var st: Dictionary = cockpit.state
	var s: float = cockpit.ui_scale()
	var c := r.get_center()
	var k := r.size.y / 60.0  # screen px per degree
	var roll := deg_to_rad(float(st.roll))
	var right := Vector2(cos(roll), -sin(roll))
	var down := Vector2(sin(roll), cos(roll))
	var h := c + down * float(st.pitch) * k  # the horizon's centre
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_rect(r, SKY)
	for poly in ground_polys(box, h, right, down):
		draw_colored_polygon(poly, GROUND)
	for p in range(-30, 31, 10):
		var w := (0.30 if p == 0 else 0.12) * r.size.x
		var m := h - down * p * k
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([m - right * w, m + right * w]), box):
			draw_polyline(seg, WHITE, maxf(1.0, s * 0.6))
	# The aircraft symbol, then the speed / altitude / heading readouts.
	var a := 0.16 * r.size.x
	draw_polyline(
		PackedVector2Array(
			[
				c + Vector2(-a, 0),
				c + Vector2(-a * 0.35, 0),
				c + Vector2(0, a * 0.25),
				c + Vector2(a * 0.35, 0),
				c + Vector2(a, 0)
			]
		),
		AMBER,
		maxf(1.5, s * 1.2)
	)
	var fs := r.size.y / s * 0.12
	var bw := r.size.x * 0.30
	var bh := r.size.y * 0.17
	for i in 2:
		var b := Rect2(Vector2(r.position.x if i == 0 else r.end.x - bw, c.y - bh / 2), Vector2(bw, bh))
		draw_rect(b, Color(0, 0, 0, 0.85))
		draw_rect(b, WHITE, false, 1.0)
		var v := "%d" % int(st.get("ias_kt", 0.0)) if i == 0 else "%d" % int(round(float(st.alt_ft) / 10.0) * 10)
		_text(Vector2(b.position.x, b.end.y - bh * 0.22), v, fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER, bw)
	var hb := Rect2(Vector2(c.x - bw * 0.5, r.end.y - bh), Vector2(bw, bh))
	draw_rect(hb, Color(0, 0, 0, 0.85))
	_text(
		Vector2(hb.position.x, hb.end.y - bh * 0.22),
		"%03d" % (int(round(float(st.heading))) % 360),
		fs,
		WHITE,
		HORIZONTAL_ALIGNMENT_CENTER,
		bw
	)
	draw_rect(r, Color(0, 0, 0), false, maxf(1.0, s))


## The ground's part of the ESIS box `box` below the horizon through `h` (along `right`, ground towards `down`). A
## horizon that grazes a corner leaves a sliver a fraction of a pixel thick that the renderer cannot triangulate
## ("Invalid polygon data"): such slivers are left out.
static func ground_polys(box: PackedVector2Array, h: Vector2, right: Vector2, down: Vector2) -> Array:
	var big := (box[2] - box[0]).length() * 2.0
	var ground := PackedVector2Array(
		[h - right * big, h + right * big, h + right * big + down * big, h - right * big + down * big]
	)
	return Geometry2D.intersect_polygons(box, ground).filter(
		func(p): return not Geometry2D.triangulate_polygon(p).is_empty()
	)


# --- layer 1: the glass ------------------------------------------------------------------------------------------


## A faint sheen over the whole glass, the canopy's light reflected near its top fading downward.
func _draw_sheen() -> void:
	var g := glass()
	var mid := g.position.y + g.size.y * 0.45
	var top := Color(0.75, 0.82, 0.95, 0.07)
	var clear := Color(0.75, 0.82, 0.95, 0.0)
	draw_polygon(
		PackedVector2Array(
			[g.position, Vector2(g.end.x, g.position.y), Vector2(g.end.x, mid), Vector2(g.position.x, mid)]
		),
		PackedColorArray([top, top, clear, clear])
	)
	# A soft diagonal streak across the left half.
	var x0 := g.position.x + g.size.x * 0.08
	var w := g.size.x * 0.10
	var streak := Color(0.85, 0.9, 1.0, 0.035)
	draw_polygon(
		PackedVector2Array(
			[
				Vector2(x0 + w, g.position.y),
				Vector2(x0 + 2.2 * w, g.position.y),
				Vector2(x0 + w * 1.2, g.end.y),
				Vector2(x0, g.end.y)
			]
		),
		PackedColorArray([streak, clear, clear, streak])
	)
