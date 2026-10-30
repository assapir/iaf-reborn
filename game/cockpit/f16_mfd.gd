# Ours (docs/mfd.md §9, docs/real-mfd.md "F-16C/D Barak"): the F-16's real head-down formats, drawn into a 132 × 132
# MFD (mfd.gd) in MFD px. The F-16I Sufa draws them always, in colour; the F-16D Barak with Extras "MFDs (F-16)" on
# Real, in the monochrome green. The OSB mnemonics sit by their buttons (the real numbering, clockwise from the top
# left); the bottom row on every format holds SWAP, the MFD's three formats and DCLT. Which format each OSB picks, and
# the menu, are IafF16Mfd's (crates/iaf-avionics/src/f16_mfd.rs); this file draws and wires the format's own OSBs to
# the game's events. Layouts: the Hellenic AF dash-34 (1997) figures; colours: the MLU M1 pilot's guide (1998) table
# 1-1 and figures 1-17 / 1-18, the text white as on the Block 50 M4 tape (a simulator manual; inferred for the Sufa).
extends "res://cockpit/pcd_formats.gd"

const MfdNode := preload("res://cockpit/mfd.gd")
## The monochrome MFD's green (the original pages' RGB(0,255,0)).
const MONO := Color8(0, 255, 0)
## The colour MFD's inks, read off the MLU M1 guide's figures (p. 21): green, yellow, the blue it calls cyan, white.
const C_GREEN := Color8(0, 204, 0)
const C_YELLOW := Color8(251, 243, 5)
const C_CYAN := Color8(0, 159, 255)
const C_WHITE := Color8(255, 255, 255)
const C_RED := Color8(255, 40, 30)
## Colour roles (MLU M1 table 1-1 / figs. 1-17, 1-18; the text white per the M4 tape, a simulator manual): the OSB
## mnemonics and text; scales, carets, rings' ticks and the horizon (green); search returns (white); tracks and the
## bug (yellow); friends (green); ownship, the scan volume and the bullseye (cyan); the route and the HSD's rings
## (white); preplanned threats (yellow, red with the jet inside); warnings (red; inferred).
const ROLES := {
	"text": C_WHITE,
	"scale": C_GREEN,
	"search": C_WHITE,
	"track": C_YELLOW,
	"friend": C_GREEN,
	"own": C_CYAN,
	"route": C_WHITE,
	"ring": C_WHITE,
	"threat": C_YELLOW,
	"inside": C_RED,
	"cursor": C_WHITE,
	"warning": C_RED,
	"caution": C_YELLOW,
}
const SIZE := 6.0  # the mnemonics' font size, MFD px (about 18 characters across, real-mfd.md "Colours and font")
const SMALL := 4.8
## The game's stations 0..8 (real 1..9) on the INV page by the OSBs the original's stores page selects them with
## (0xd, 0xc, 0xb, 1, 3, 5, 0x10, 0x11, 0x12 as real numbers): an inverted V, station 1 lower left, 5 top centre.
const STATION_OSB := [18, 19, 20, 1, 3, 5, 6, 7, 8]
## Air-to-air missile types (the AAM page); 590 is the HARM (WPN: HAS).
const AAM_TYPES := [570, 580, 600, 610]
## The damage flags (docs/damage.md §5.2) as fault-list lines (inferred: the MFL's layout is open), each once.
const FAULTS := [
	[[22, 16, 2, 23, 17, 3], "ENG FAIL", "warning"],
	[[24], "FLCS FAIL", "warning"],
	[[8, 9], "AB FAIL", "caution"],
	[[11], "INS FAIL", "caution"],
	[[10], "FUEL LEAK", "caution"],
	[[15], "FCR FAIL", "caution"],
	[[18], "FLCS DEGR", "caution"],
	[[14], "RWR FAIL", "caution"],
	[[20], "SMS FAIL", "caution"],
	[[4], "FLAP FAIL", "caution"],
	[[13], "GUN FAIL", "caution"],
	[[7], "GEAR FAIL", "caution"],
	[[1], "ECM FAIL", "caution"],
	[[12], "HUD FAIL", "caution"],
	[[6], "AP FAIL", "caution"],
	[[5], "BRAKE FAIL", "caution"],
	[[19, 21], "ELEC FAIL", "caution"]
]

static var _font: SystemFont
var m: Control  # the MFD node (mfd.gd)
## The SMS shows its inventory (OSB 4 INV) instead of the selected weapon's page.
var sms_inv := false
## Tests: the colours drawn this frame.
var used := {}


func _init(mfd: Control) -> void:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(
			["DejaVu Sans Mono", "Liberation Mono", "Menlo", "Consolas", "Courier New"]
		)
		_font.font_weight = 600
	super(mfd, mfd.cockpit, _font)
	m = mfd


## The colour of a role: the colour ink on the Sufa, the green on the Barak.
func c(role: String) -> Color:
	var col: Color = ROLES[role] if m.real_look == "colour" else MONO
	used[col] = true
	return col


# --- the frame ------------------------------------------------------------------------------------------------------


## The anchor of real OSB n's mnemonic (MFD px): the buttons sit 20 px apart from 24 along each edge (osb_at's).
static func osb_at(n: int) -> Vector2:
	if n <= 5:
		return Vector2(20 * n + 4, 8)
	if n <= 10:
		return Vector2(130, 20 * (n - 5) + 6)
	if n <= 15:
		return Vector2(20 * (16 - n) + 4, 130)
	return Vector2(2, 20 * (21 - n) + 6)


## A mnemonic by OSB n (centred on the top and bottom rows, against the edge at the sides); `hl` the highlight, an
## inverse box. Decluttered: only the bottom row.
func label(n: int, t: String, hl := false, col_role := "text") -> void:
	if t == "" or (m.real.state().declutter and (n < 11 or n > 15)):
		return
	var a := osb_at(n)
	var w := text_width(t, SIZE)
	var x := a.x - w / 2.0
	if n >= 6 and n <= 10:
		x = a.x - w
	elif n >= 16:
		x = a.x
	var col := c(col_role)
	if hl:
		fill(Rect2(x - 1.0, a.y - SIZE * 0.82, w + 2.0, SIZE * 1.05), col)
		text(Vector2(x, a.y), t, SIZE, Color.BLACK)
	else:
		text(Vector2(x, a.y), t, SIZE, col)


## A line of text centred on x.
func centred(x: float, y: float, t: String, col: Color, size := SIZE) -> void:
	text(Vector2(x - text_width(t, size) / 2.0, y), t, size, col)


## The up / down triangles by OSBs 20 / 19 with a value between them (the range scale, the zoom; dash-34 p. 1-76).
func stepper(value: String) -> void:
	if m.real.state().declutter:
		return
	var col := c("text")
	for k in 2:
		var y := 24.0 if k == 0 else 44.0
		var d := -1.0 if k == 0 else 1.0
		poly(PackedVector2Array([Vector2(3, y + 2 * d), Vector2(9, y + 2 * d), Vector2(6, y - 2 * d)]), col, LINE, true)
	text(Vector2(3, 36), value, SIZE, col)


## The bottom row (fig. 1-43): OSB 15 SWAP, 14..12 the three formats (the primary inverse), OSB 11 DCLT (S-J on the
## SMS).
func bottom_row(shown: String) -> void:
	var st: Dictionary = m.real.state()
	label(15, "SWAP")
	for k in 3:
		label(14 - k, st.slots[k], k == st.primary)
	label(11, "S-J" if shown == "SMS" else "DCLT", st.declutter)


## Draws the format (or the menu) at the MFD's screen scale `s`.
func draw_format(s: float) -> void:
	used.clear()
	begin(Vector2.ONE * m.BEZEL * s, s)
	var st: Dictionary = m.real.state()
	var f: String = "MENU" if st.menu else String(st.shown)
	match f:
		"FCR":
			fcr()
		"SMS":
			sms_format()
		"HSD":
			hsd()
		"WPN":
			wpn()
		"TGP":
			tgp()
		"TEST":
			test()
		"MENU":
			format_menu(String(st.shown))
	bottom_row(f)
	end()


# --- the format menu ------------------------------------------------------------------------------------------------


## Fig. 1-29: the formats by their OSBs, the current one highlighted; TGP only with a targeting pod (the original's
## MENU "FLIR" gate).
func format_menu(current: String) -> void:
	for e in ClassDB.class_call_static("IafF16Mfd", "menu"):
		if e[1] == "TGP" and not m._flir_menu():
			continue
		label(int(e[0]), String(e[1]), e[1] == current)


# --- FCR ------------------------------------------------------------------------------------------------------------


## A contact's place on the B-scope: the game's geometry (mfd.gd: x by the azimuth across the scan's width, 112 px =
## the range), so the cursor and its clicks stay the original's.
static func bscope(r: Dictionary, ct: Dictionary, nm: float) -> Vector2:
	return Vector2(
		66.0 + (float(ct.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
		115.0 - float(ct.dist) / (nm * 16.5446)
	)


## The FCR (figs. 1-84, 1-85, 1-97; pp. 1-118..1-151): the mode row, the range with its triangles, the azimuth scan;
## A-A a B-scope with its range marks, antenna carets, horizon line, targets (search squares, track triangles turned
## to their heading in 22.5° steps with a speed line, the bug circled, altitude in kft below), the steerpoint, the
## STT data line and the DLZ; A-G the GM / GMT fan.
func fcr() -> void:
	var r: Dictionary = cockpit.radar
	var mode := int(r.get("mode", 0))
	var nm: float = MfdNode.RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1]
	var names: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "fcr_mode", mode)
	label(1, names[0])
	label(2, names[1])
	label(3, "EXP" if mode == 8 and r.get("exp", false) else "NORM")
	label(4, "OVRD")
	label(5, "CNTL")
	if mode >= 2:
		stepper("%d" % int(nm))
	if mode >= 2 and mode <= 6:
		label(18, ClassDB.class_call_static("IafF16Mfd", "fcr_azimuth", float(r.get("width", TAU / 3.0))))
	if mode >= 7:
		_ground_map(r, mode, nm)
		return
	var sc := c("scale")
	# Range marks: 3 on the right edge at the quarters (p. 1-122); azimuth tics every 10° to ±30° at the bottom.
	for k in [1, 2, 3]:
		line(Vector2(120, 115 - 28 * k), Vector2(124, 115 - 28 * k), sc, THIN)
	var deg := 112.0 / rad_to_deg(float(r.get("width", TAU / 3.0)))
	for k in range(-3, 4):
		line(Vector2(66 + 10 * k * deg, 116), Vector2(66 + 10 * k * deg, 118 if k != 0 else 119), sc, THIN)
	if mode < 2:
		return
	# Antenna carets: a T on the bottom edge (azimuth), one on the left edge (elevation).
	if mode != 2:
		var a: Vector2 = r.get("antenna", Vector2.ZERO)
		var ax := 13.0 + clampf(a.x * 106.0, 0.0, 106.0)
		var ay := 13.0 + clampf(a.y * 106.0, 0.0, 106.0)
		line(Vector2(ax, 119), Vector2(ax, 123), sc, LINE)
		line(Vector2(ax - 3, 119), Vector2(ax + 3, 119), sc, LINE)
		line(Vector2(12, ay), Vector2(16, ay), sc, LINE)
		line(Vector2(16, ay - 3), Vector2(16, ay + 3), sc, LINE)
	_horizon(sc)
	var lock_p = null
	var h := heading_rad()
	for ct in r.get("contacts", []):
		if mode == 2 and not ct.locked:
			continue
		var p := bscope(r, ct, nm)
		if p.x <= 8 or p.x >= 124 or p.y <= 8 or p.y >= 118:
			continue
		var bug: bool = ct.locked or ct.get("selected", false)
		if mode in [3, 4, 6] and not bug:
			fill(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c("search"))
		else:
			var col := c("track") if ct.get("hostile", true) or m.real_look != "colour" else c("friend")
			# The heading relative to ours, in 22.5° steps (p. 1-122); the line from the nose grows with the speed.
			var hd := snappedf(deg_to_rad(float(ct.get("heading", 0.0))) - h, PI / 8.0)
			var fw := Vector2(sin(hd), -cos(hd))
			var rt := Vector2(-fw.y, fw.x)
			poly(PackedVector2Array([p + fw * 3.0, p - fw * 2.0 + rt * 2.6, p - fw * 2.0 - rt * 2.6]), col, LINE, true)
			var sl := clampf(float(ct.get("speed", 0.0)) / 120.0, 1.0, 8.0)
			line(p + fw * 3.0, p + fw * (3.0 + sl), col, THIN)
			if bug:
				circle(p, 4.6, col, THIN)
				lock_p = p
			centred(p.x, p.y + 9.0, "%02d" % int(float(ct.get("alt", 0.0)) * 0.0032808398), col, SMALL)
	_steerpoint_bscope(nm, r)
	# The acquisition cursor: two short vertical lines (p. 1-124).
	if m.mouse != null:
		var q: Vector2 = m.mouse
		for dx in [-2.0, 2.0]:
			line(q + Vector2(dx, -4), q + Vector2(dx, 4), c("cursor"), LINE)
	var lk: Dictionary = r.get("lock", {})
	if lock_p != null and not lk.is_empty():
		_stt_line(lk, float(r.get("closure", 0.0)))
		_dlz(r.get("dlz", []), float(lk.dist), nm)


## The horizon line (fig. 1-85): broken in the middle, with end ticks, rolled and moved 1 px per degree of pitch.
func _horizon(col: Color) -> void:
	var st: Dictionary = cockpit.state
	var rot := deg_to_rad(-float(st.roll))
	var o := Vector2(66, 66 + clampf(float(st.pitch), -40.0, 40.0))
	for sd in [-1.0, 1.0]:
		var pts := [Vector2(10 * sd, 0), Vector2(40 * sd, 0), Vector2(40 * sd, 3)]
		poly(PackedVector2Array(pts.map(func(q): return o + q.rotated(rot))), col, THIN)


## The steerpoint: a filled triangle at its range and bearing (p. 1-124), within the scan.
func _steerpoint_bscope(nm: float, r: Dictionary) -> void:
	var sp = m._steerpoint()
	if sp == null:
		return
	var rel: Vector2 = sp - own_world()
	var az := wrapf(atan2(rel.x, rel.y) - heading_rad(), -PI, PI)
	var p := bscope(r, {"az": az, "dist": rel.length()}, nm)
	if p.x > 8 and p.x < 124 and p.y > 8 and p.y < 118:
		ci.draw_colored_polygon(
			PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 2), p + Vector2(-3, 2)]), c("route")
		)


## The STT data line under the mode row (figs. 1-84, 1-93): aspect (tens of degrees, L / R), the target's ground
## track, its speed and the closure.
func _stt_line(lk: Dictionary, closure: float) -> void:
	var col := c("text")
	var trk := posmod(int(round(float(lk.get("heading", 0.0)) / 10.0)) * 10, 360)
	var row := [
		MfdNode.aspect_text(float(lk.get("aspect", 0.0))).strip_edges(),
		"%03d°" % trk,
		"%d" % (int(float(lk.get("speed", 0.0)) / 10.0) * 10),
		"%+dK" % int(closure * 1.9438445)
	]
	for i in row.size():
		centred(26 + 27 * i, 17, row[i], col, SMALL)


## The DLZ on the right edge (fig. 1-27): the bracket from Rmin to Rmax and a caret at the target's range.
func _dlz(dlz: Array, dist: float, nm: float) -> void:
	if dlz.size() != 2:
		return
	var col := c("scale")
	var k := 112.0 / (nm * 1852.0)
	var y0 := clampf(115.0 - float(dlz[0]) * k, 10.0, 115.0)
	var y1 := clampf(115.0 - float(dlz[1]) * k, 10.0, 115.0)
	line(Vector2(116, y0), Vector2(116, y1), col, LINE)
	for y in [y0, y1]:
		line(Vector2(113, y), Vector2(116, y), col, LINE)
	var yt := clampf(115.0 - dist * k, 10.0, 115.0)
	poly(PackedVector2Array([Vector2(118, yt), Vector2(121, yt - 2), Vector2(121, yt + 2)]), c("text"), LINE, true)


## GM / GMT (fig. 1-97, pp. 1-142..1-151): the PPI fan from (66, 109), 94 px = the range (the MAP picture's scale),
## its range arcs (10 NM: one at 5; else three a quarter apart), the X-Y cursors on the mouse, the returns (GMT:
## squares) and a tracked target or the designated point as a solid diamond; the steerpoint.
func _ground_map(r: Dictionary, mode: int, nm: float) -> void:
	var sc := c("scale")
	var apex := Vector2(66, 109)
	var rect := PackedVector2Array([Vector2(12, 12), Vector2(120, 12), Vector2(120, 118), Vector2(12, 118)])
	for a in [-PI / 3.0, PI / 3.0]:
		for seg in Geometry2D.intersect_polyline_with_polygon(
			PackedVector2Array([apex, apex + Vector2(sin(a), -cos(a)) * 94.0]), rect
		):
			poly(seg, sc, THIN)
	for f in [0.5] if nm <= 10 else [0.25, 0.5, 0.75]:
		var pts := PackedVector2Array()
		for i in 25:
			var a := -PI / 3.0 + 2.0 * PI / 3.0 * i / 24.0
			pts.append(apex + Vector2(sin(a), -cos(a)) * 94.0 * f)
		for seg in Geometry2D.intersect_polyline_with_polygon(pts, rect):
			poly(seg, sc, THIN)
	var fr: Dictionary = m._map_frame(r) if mode == 8 else {"centre": own_world(), "hdg": heading_rad(), "sym": apex}
	var k := nm * 19.7128
	var any_locked := false
	for ct in r.get("contacts", []):
		var w: Vector3 = ct.pos
		var p: Vector2 = fr.sym + MfdNode._heading_up(Vector2(w.x, w.y) - fr.centre, fr.hdg, k)
		if not Rect2(12, 12, 108, 106).has_point(p):
			continue
		any_locked = any_locked or ct.locked
		if ct.locked:
			_diamond(p, c("track"))
		else:
			fill(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c("search"))
	if mode == 8 and r.get("designated", false) and not any_locked:
		_diamond(fr.sym + MfdNode._heading_up(m._map_point - fr.centre, fr.hdg, k), c("track"))
	var sp = m._steerpoint()
	if sp != null:
		var p: Vector2 = fr.sym + MfdNode._heading_up(sp - fr.centre, fr.hdg, k)
		if Rect2(12, 12, 108, 106).has_point(p):
			ci.draw_colored_polygon(
				PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 2), p + Vector2(-3, 2)]), c("route")
			)
	if m.mouse != null:
		var q: Vector2 = m.mouse
		line(Vector2(12, q.y), Vector2(120, q.y), c("cursor"), THIN)
		line(Vector2(q.x, 12), Vector2(q.x, 118), c("cursor"), THIN)


func _diamond(p: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(
		PackedVector2Array([p + Vector2(0, -3), p + Vector2(3, 0), p + Vector2(0, 3), p + Vector2(-3, 0)]), col
	)


# --- HSD ------------------------------------------------------------------------------------------------------------

const HSD_OWN := Vector2(66, 99)  # the depressed view: the ownship a quarter up from the bottom (fig. 1-45)
const HSD_R := 88.0  # px from the ownship to the outer ring (= the range scale)


## The HSD (fig. 1-45, pp. 1-82..1-83): the range with its triangles, three rings a third of the range apart and the
## north tic, the route through the past, current and next two steerpoints (the current filled), the preplanned
## threats as rings from the game's SAM sites (inferred; MLU figs. 1-18..1-19), the FCR's scan as a wedge, the ownship.
## The Sufa's colour moving map (f16i.md §4) under it all: the game's TSD map, dimmed.
func hsd() -> void:
	var nm: float = ClassDB.class_call_static("IafF16Mfd", "hsd_range_nm", m.tsd_scale)
	var mpp := nm * 1852.0 / HSD_R
	var clip := PackedVector2Array([Vector2(1, 12), Vector2(131, 12), Vector2(131, 121), Vector2(1, 121)])
	if m.real_look == "colour":
		for piece_src in cockpit.tsd_map:
			var pts := PackedVector2Array()
			for w in piece_src.points:
				pts.append(to_scope(w, HSD_OWN, mpp))
			for piece in Geometry2D.intersect_polygons(pts, clip):
				if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
					ci.draw_colored_polygon(piece, Color(piece_src.color).darkened(0.62))
	label(1, "DEP")
	label(5, "CNTL")
	stepper("%d" % int(nm))
	var rc := c("ring")
	for k in [1, 2, 3]:
		for seg in _arc_clipped(HSD_OWN, HSD_R * k / 3.0, clip):
			poly(seg, rc, THIN)
	var hn := -heading_rad()
	var nd := Vector2(sin(hn), -cos(hn))
	var tic_at := HSD_OWN + nd * HSD_R
	if Geometry2D.is_point_in_polygon(tic_at, clip):
		line(tic_at, tic_at + nd * 4.0, rc, LINE)
	# The FCR's scan (A-A search modes): a wedge to the radar's range.
	var r: Dictionary = cockpit.radar
	var mode := int(r.get("mode", 0))
	if mode >= 3 and mode <= 6:
		var half := float(r.get("width", TAU / 3.0)) / 2.0
		var mid := -float(r.get("shift", 0.0))
		var rr: float = MfdNode.RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1] * 1852.0 / mpp
		var pts := PackedVector2Array([HSD_OWN])
		for i in 13:
			var a := mid - half + 2.0 * half * i / 12.0
			pts.append(HSD_OWN + Vector2(sin(a), -cos(a)) * rr)
		pts.append(HSD_OWN)
		for seg in Geometry2D.intersect_polyline_with_polygon(pts, clip):
			poly(seg, c("own"), THIN)
	# The route: the past, current and next two steerpoints.
	var wps: Array = cockpit.waypoints
	var cur: int = cockpit.current_waypoint
	var prev = null
	for i in range(maxi(cur - 1, 0), mini(cur + 3, wps.size())):
		var p := to_scope(wps[i].world, HSD_OWN, mpp)
		if prev != null:
			for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([prev, p]), clip):
				poly(seg, c("route"), THIN)
		prev = p
		if Geometry2D.is_point_in_polygon(p, clip):
			if i == cur:
				ci.draw_circle(p, 2.4, c("route"), true, -1.0, true)
			else:
				circle(p, 2.0, c("route"), THIN)
	# Preplanned threats: a ring of the site's reach with the site's mark; red with the jet inside (a simulator manual).
	for site in cockpit.sam_sites:
		var p := to_scope(site.pos, HSD_OWN, mpp)
		var inside: bool = own_world().distance_to(site.pos) < float(site.r)
		var col := c("inside" if inside else "threat")
		var rad := float(site.r) / mpp
		if rad > 0.5:
			for seg in _arc_clipped(p, rad, clip):
				poly(seg, col, THIN)
		if Geometry2D.is_point_in_polygon(p, clip):
			box(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), col, THIN)
	_ownship(HSD_OWN)


## The ownship: a small aeroplane pointing up.
func _ownship(p: Vector2) -> void:
	var col := c("own")
	line(p + Vector2(0, -4), p + Vector2(0, 4), col, LINE)
	line(p + Vector2(-4, -0.5), p + Vector2(4, -0.5), col, LINE)
	line(p + Vector2(-2, 3.5), p + Vector2(2, 3.5), col, LINE)


# --- SMS ------------------------------------------------------------------------------------------------------------


## The SMS (figs. 1-48..1-71): the inventory (INV), or the selected weapon's page: AAM for air-to-air missiles, the
## gun, A-G for the rest (bombs, the GPS bombs with PRE / VIS, Mavericks, the HARM).
func sms_format() -> void:
	var wp: Dictionary = cockpit.weapons
	if wp.is_empty():
		label(1, "STBY")
		label(4, "INV", true)
		return
	var sel := int(wp.selected)
	var t := int(wp.get("type", 0))
	var page := "INV" if sms_inv or sel < 0 else ("GUN" if sel == 9 else ("AAM" if t in AAM_TYPES else "A-G"))
	label(4, "INV", page == "INV")
	match page:
		"INV":
			label(1, "STBY" if sel < 0 else ("GUN" if sel == 9 else ("AAM" if t in AAM_TYPES else "A-G")))
			_inventory(wp)
		"GUN":
			label(1, "GUN")
			label(2, "EEGS" if int(wp.get("hud_mode", 0)) == 4 else "LCOS")
			label(6, "%dGUN" % (int(wp.gun) / 10))
			centred(66, 66, _status(wp), c("text"))
		"AAM":
			label(1, "AAM")
			label(6, _weapon_name(wp))
			centred(66, 66, _status(wp), c("text"))
			_station_row(wp)
		_:
			_ag_page(wp)


## INV (figs. 1-48, 1-49): each station's count and store by its OSB (an empty one dashed), the selected boxed; the
## gun's rounds in tens by OSB 16.
func _inventory(wp: Dictionary) -> void:
	var sel := int(wp.selected)
	for i in 9:
		var st: Dictionary = wp.stations[i]
		var n := int(st.count)
		var t := "%d %s" % [n, String(st.name)] if n > 0 and String(st.name) != "" else "----"
		var osb: int = STATION_OSB[i]
		if osb <= 5:  # the top stations under the mode row
			var a := osb_at(osb) + Vector2(0, 9)
			var w := text_width(t, SMALL)
			if i == sel:
				fill(Rect2(a.x - w / 2.0 - 1.0, a.y - SMALL * 0.82, w + 2.0, SMALL * 1.05), c("text"))
			centred(a.x, a.y, t, Color.BLACK if i == sel else c("text"), SMALL)
		else:
			label(osb, t, i == sel)
	label(16, "%dGUN" % (int(wp.gun) / 10), sel == 9)
	centred(66, 104, "CHAFF %d  FLARE %d" % [int(wp.get("chaff", 0)), int(wp.get("flares", 0))], c("text"), SMALL)


## The count and store of the selected weapon, e.g. "4 AIM-9X".
func _weapon_name(wp: Dictionary) -> String:
	return "%d %s" % [int(wp.get("total", 0)), String(wp.get("name", ""))]


## RDY / MAL / blank (fig. 1-66).
func _status(wp: Dictionary) -> String:
	if not wp.get("ready", true):
		return "MAL"
	return "RDY" if int(wp.get("total", 0)) > 0 else ""


## The stations holding the selected weapon above the bottom row, the selected one boxed (fig. 1-66).
func _station_row(wp: Dictionary) -> void:
	var x := 112.0
	var col := c("text")
	for i in range(8, -1, -1):
		var st: Dictionary = wp.stations[i]
		if int(st.count) <= 0 or String(st.name) != String(wp.get("name", "")):
			continue
		var t := "%d" % (i + 1)
		text(Vector2(x, 118), t, SIZE, col)
		if i == int(wp.selected):
			box(Rect2(x - 1.0, 118 - SIZE * 0.85, text_width(t, SIZE) + 2.0, SIZE * 1.1), col, THIN)
		x -= 8.0
	text(Vector2(x - 2.0, 118), "M", SIZE, col)


## The A-G page (figs. 1-70, 1-71): OSB 2 the submode (CCIP; a GPS bomb's PRE / VIS, as the real F-16's JDAM page),
## the weapon by OSB 6, the release (SGL / PAIR with Bomb release Real), the interval and the release pulses; RDY;
## for a GPS bomb its target and times (§13; the layout inferred).
func _ag_page(wp: Dictionary) -> void:
	var gps: Dictionary = wp.get("ag", {}).get("gps", {})
	label(1, "A-G")
	label(2, ("PRE" if gps.get("pre", true) else "VIS") if _gps(wp) else "CCIP")
	label(6, _weapon_name(wp))
	if String(wp.get("release", "")) != "":
		label(8, String(wp.release))
	label(9, "%d INT" % int(wp.get("interval", 10)))
	label(10, "RP %d" % int(wp.get("quantity", 2)))
	centred(66, 40, _status(wp), c("text"))
	if _gps(wp):
		_gps_block(wp, 58)


## A GPS bomb is selected: its name (the A-G page's gps block needs HUD mode 5 / 6) or its time to impact.
func _gps(wp: Dictionary) -> bool:
	return not wp.get("ag", {}).get("gps", {}).is_empty() or String(wp.get("name", "")).begins_with("GBU-3")


## A GPS bomb's lines (inferred): the target (a steerpoint's number, else the designation: PRE / VIS), its range and
## bearing, TMR m:ss or IN RNG, and TTI m:ss while the last released bomb flies.
func _gps_block(wp: Dictionary, y: float) -> void:
	var gps: Dictionary = wp.get("ag", {}).get("gps", {})
	var col := c("text")
	var aim = gps.get("aim")
	if aim is Vector3:
		var xy := Vector2(aim.x, aim.y)
		var tgt := "TGT %s" % ("PRE" if gps.get("pre", true) else "VIS")
		for i in cockpit.waypoints.size():
			if cockpit.waypoints[i].world.distance_to(xy) < 100.0:
				tgt = "STPT %d" % (i + 1)
		centred(66, y, tgt, col)
		var rel := xy - own_world()
		var brg := posmod(int(round(rad_to_deg(atan2(rel.x, rel.y)))), 360)
		centred(66, y + 9, "%.1f NM  %03d°" % [rel.length() / 1852.0, brg], col, SMALL)
		var lar: Dictionary = gps.get("lar", {})
		if gps.get("in_range", false):
			centred(66, y + 18, "IN RNG", c("friend"))
		elif lar.get("tmr") != null:
			centred(66, y + 18, "TMR %s" % _mss(float(lar.tmr)), col)
	else:
		centred(66, y, "NO TGT", c("caution"))
	var tti = wp.get("gps_tti")
	if tti != null:
		centred(66, y + 27, "TTI %s" % _mss(float(tti)), col)


static func _mss(s: float) -> String:
	var n := int(ceil(maxf(s, 0.0)))
	return "%d:%02d" % [n / 60, n % 60]


# --- WPN ------------------------------------------------------------------------------------------------------------


## WPN shows the selected weapon's page: HAS for the HARM (figs. 1-296..1-298), the Maverick's video (fig. 1-75),
## a GPS bomb's status (inferred: the real JDAM has no WPN page; the SMS's PRE / VIS and target with a LAR scale like
## the Maverick's launch envelope); else WPN OFF.
func wpn() -> void:
	var wp: Dictionary = cockpit.weapons
	if m.page == MfdNode.HARM:
		_has()
		return
	var tv: Dictionary = cockpit.eo.get("tv", {})
	if int(tv.get("status", 0)) != 0:
		_maverick(wp, tv)
	elif not wp.is_empty() and _gps(wp):
		_jdam(wp)
	else:
		centred(66, 66, "WPN OFF", c("text"))


func _maverick(wp: Dictionary, tv: Dictionary) -> void:
	label(1, "OPER")
	label(2, "VIS")
	label(6, _weapon_name(wp))
	stepper("%d" % int(tv.get("zoom", 1)))
	var col := c("text")
	# The fixed cross and the track gate's four corners about the seeker's point (the original's ticks, u / v).
	line(Vector2(60, 66), Vector2(72, 66), col, THIN)
	line(Vector2(66, 60), Vector2(66, 72), col, THIN)
	var g := Vector2(66.0 - 56.0 * float(tv.get("u", 0.0)), 66.0 + 56.0 * float(tv.get("v", 0.0)))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var q := g + Vector2(6 * sx, 6 * sy)
			line(q, q - Vector2(3 * sx, 0), col, LINE)
			line(q, q - Vector2(0, 3 * sy), col, LINE)
	var st := int(tv.get("status", 0))
	text(Vector2(14, 118), MfdNode.TV_STATUS[clampi(st, 0, 3)], SIZE, col)
	text(Vector2(84, 118), "%03d" % int(cockpit.eo.get("tv_time", 0)), SIZE, col)


func _jdam(wp: Dictionary) -> void:
	var gps: Dictionary = wp.get("ag", {}).get("gps", {})
	label(1, "PRE" if gps.get("pre", true) else "VIS")
	label(6, _weapon_name(wp))
	centred(66, 28, _status(wp), c("text"))
	_gps_block(wp, 44)
	# The LAR scale on the right edge: Rmin / Rmax ticks and a caret at the target's range (0 at the bottom).
	var lar: Dictionary = gps.get("lar", {})
	if lar.is_empty():
		return
	var top := maxf(float(lar.rmax) * 1.25, float(lar.range) * 1.05)
	var y := func(v: float) -> float: return 108.0 - 80.0 * clampf(v / maxf(top, 1.0), 0.0, 1.0)
	var col := c("scale")
	line(Vector2(118, y.call(float(lar.rmin))), Vector2(118, y.call(float(lar.rmax))), col, LINE)
	for v in [float(lar.rmin), float(lar.rmax)]:
		line(Vector2(114, y.call(v)), Vector2(118, y.call(v)), col, LINE)
	text(Vector2(98, y.call(float(lar.rmax)) + 2.0), "RMAX", SMALL, col)
	var yt: float = y.call(float(lar.range))
	poly(PackedVector2Array([Vector2(119, yt), Vector2(123, yt - 2), Vector2(123, yt + 2)]), c("text"), LINE, true)


## HAS (figs. 1-297, 1-298): the boresight lines, each threat's code where the HARM's sensor sees it (mfd.gd's HARM
## geometry, so a click picks it), the selected one boxed; the detected codes in a box under the mode row; RDY in
## range.
func _has() -> void:
	var h: Dictionary = cockpit.harm
	label(1, "HAS")
	label(2, "TBL1")
	label(3, "WIDE")
	var sc := c("scale")
	line(Vector2(14, 66), Vector2(118, 66), sc, THIN)
	line(Vector2(66, 22), Vector2(66, 116), sc, THIN)
	var codes := []
	for e in MfdNode.harm_symbols(h):
		var code: String = MfdNode.HARM_CHAR.get(int(e.type), "U")
		codes.append(code)
		var col := c("track") if e.selected else c("search")
		centred(e.pos.x, e.pos.y + 2.0, code, col)
		if e.selected:
			box(Rect2(e.pos - Vector2(4, 4), Vector2(8, 8)), col, THIN)
	if not codes.is_empty():
		var t := " ".join(codes.slice(0, 5))
		var w := text_width(t, SMALL) + 4.0
		box(Rect2(66 - w / 2.0, 12, w, 8), c("text"), THIN)
		centred(66, 18, t, c("text"), SMALL)
	if h.get("no_source", true):
		centred(66, 118, "NO SOURCE", c("caution"))
	elif h.get("in_range", false):
		centred(66, 118, "RDY", c("text"))


# --- TGP ------------------------------------------------------------------------------------------------------------


## The TGP (figs. 1-163, 1-164): over the pod's picture, the mode row (A-G, WIDE / NARO, the laser on OSB 3, ours),
## the zoom by its triangles, WHOT, the cross, and the range bottom right (L with the laser, T without).
func tgp() -> void:
	var f: Dictionary = cockpit.eo.get("flir", {})
	label(1, "A-G")
	label(5, "CNTL")
	label(6, "WHOT")
	var col := c("text")
	if f.is_empty():
		centred(66, 66, "NOT TIMED OUT", col)
		return
	label(2, "NARO" if f.spot else "WIDE")
	label(3, "LASR", bool(f.laser))
	stepper("%d" % int(f.zoom))
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		line(Vector2(66, 66) + d * 3.0, Vector2(66, 66) + d * 12.0, col, LINE)
	var rt := "%s %s" % ["L" if f.laser else "T", String(f.range)]
	text(Vector2(126 - text_width(rt, SIZE), 118), rt, SIZE, col)


# --- TEST -----------------------------------------------------------------------------------------------------------


## TEST: the fault list (inferred: the MFL's layout is open, real-mfd.md "TEST"); the damage flags as lines, the
## failures red and the cautions yellow in colour.
func test() -> void:
	label(1, "BIT1")
	label(5, "CLR")
	var flags: Array = cockpit.damage_flags
	var y := 24.0
	var n := 0
	for row in FAULTS:
		if row[0].any(func(i): return i < flags.size() and flags[i]):
			text(Vector2(20, y), row[1], SIZE, c(row[2]))
			y += 8.0
			n += 1
			if y > 112.0:
				break
	if n == 0:
		centred(66, 66, "NO FAULTS", c("text"))


# --- the format's own OSBs ------------------------------------------------------------------------------------------


## An OSB press (the game's button id): the frame's (IafF16Mfd) or the shown format's own.
func press(id: int) -> void:
	var r: Dictionary = m.real.press(id)
	match String(r.kind):
		"format":
			show_format(String(r.format))
		"menu":
			var st: Dictionary = m.real.state()
			m.page = MfdNode.MENU if st.menu else _page_of(String(st.shown))
		"swap":
			_swap()
		"own":
			_own(String(m.real.state().shown), int(r.osb))


func _page_of(f: String) -> int:
	var harm := int(cockpit.weapons.get("type", 0)) == 590
	return ClassDB.class_call_static("IafF16Mfd", "page_of", f, harm)


## Shows format `f`: its page; the TGP through the original's MENU "FLIR" (the pod and the FLIR on, flir_on).
func show_format(f: String) -> void:
	if f == "TGP":
		if m.page != MfdNode.FLIR and m._flir_menu() and cockpit.on_flir.is_valid():
			cockpit.on_flir.call(m)
		return
	m.page = _page_of(f)


## SWAP: the left and right MFDs trade formats and pages.
func _swap() -> void:
	var other: Control = null
	for n in cockpit.mfds:
		if n != m and n.real != null:
			other = n
			break
	if other == null:
		return
	m.real.swap_with(other.real)
	var p: int = m.page
	m.page = other.page
	other.page = p


func _own(f: String, osb: int) -> void:
	match f:
		"FCR":
			match osb:
				1:
					m.cycle_radar_mode()
				20, 19:
					m.step_range(1 if osb == 20 else -1)
				3:
					if int(cockpit.radar.get("mode", 0)) == 8:
						m._radar_event(0x30)
		"HSD":
			if osb in [20, 19]:
				m.tsd_scale = ClassDB.class_call_static("IafF16Mfd", "hsd_step", m.tsd_scale, osb == 20)
		"SMS":
			_own_sms(osb)
		"WPN", "TGP":
			match osb:
				20, 19:
					m._mfd_event(0x14 if osb == 20 else 0x15)
				2:
					if f == "TGP":
						m._mfd_event(0x20)
				3:
					if f == "TGP":
						m._mfd_event(0x6a)
				1:
					if f == "WPN" and _gps(cockpit.weapons):
						m._mfd_event(GPS_MODE_EVENT)


## Ours: the GPS bomb's PRE / VIS (key K; player_weapons.gd mfd_event).
const GPS_MODE_EVENT := -1


func _own_sms(osb: int) -> void:
	var wp: Dictionary = cockpit.weapons
	if osb == 4:
		sms_inv = not sms_inv
		return
	if wp.is_empty():
		return
	if sms_inv or int(wp.selected) < 0:
		var i := STATION_OSB.find(osb)
		if osb == 16:
			i = 9
		if i >= 0 and cockpit.on_station_select.is_valid():
			cockpit.on_station_select.call(i)
		return
	match osb:
		6:
			_next_weapon(wp)
		2:
			if _gps(wp):
				m._mfd_event(GPS_MODE_EVENT)
		8:
			if String(wp.get("release", "")) != "" and cockpit.on_ripple_event.is_valid():
				cockpit.on_ripple_event.call(-1, true)
		9, 10:
			# One OSB steps the value, wrapping (IafF16Mfd.wrap_presses); events 0x4b interval ±10, 0x4a pulses ±1.
			var q := osb == 10
			var v := int(wp.get("quantity" if q else "interval", 2 if q else 10))
			var n: int = ClassDB.class_call_static(
				"IafF16Mfd", "wrap_presses", v, 1 if q else 10, 14 if q else 200, 1 if q else 10
			)
			if cockpit.on_ripple_event.is_valid():
				for k in absi(n):
					cockpit.on_ripple_event.call(0x4a if q else 0x4b, n > 0)


## OSB 6 on a weapon page: the next station holding another store (wrapping).
func _next_weapon(wp: Dictionary) -> void:
	var sel := int(wp.selected)
	for k in range(1, 10):
		var i := (sel + k) % 9
		var st: Dictionary = wp.stations[i]
		if int(st.count) > 0 and String(st.name) != String(wp.get("name", "")):
			if cockpit.on_station_select.is_valid():
				cockpit.on_station_select.call(i)
			return
