# Ours (the F-35I, docs/f35i.md §4): the panoramic cockpit display (PCD) around the MFD portals, from the cockpit's
# [PCD] section (panel px, tools/f35i/cockpit3d.py): the dark blue glass, the status bar along its top, the frames
# between the portals, the eight lower windows (fuel, engine, gear, cautions, autopilot, countermeasures, navigation)
# and the standby display (ESIS) under the glass. Layer 0 draws under the MFD portals; layer 1, over them, only the
# glass's sheen. Everything shown comes from the cockpit's state (cockpit.gd), which the flight scene fills.
extends Control

const NAVY := Color(0.020, 0.035, 0.095)
const BAR := Color(0.008, 0.014, 0.040)
const FRAME := Color(0.24, 0.32, 0.46)
const CYAN := Color(0.40, 0.88, 1.0)
const GREEN := Color(0.35, 1.0, 0.42)
const WHITE := Color(0.92, 0.95, 0.98)
const AMBER := Color(1.0, 0.74, 0.12)
const RED := Color(1.0, 0.22, 0.16)
const DIM := Color(0.36, 0.44, 0.56)
const SKY := Color(0.16, 0.46, 0.86)
const GROUND := Color(0.50, 0.30, 0.12)

var cockpit: Control
var layer := 0
var font: Font = ThemeDB.fallback_font


func setup(c: Control, l: int) -> void:
	cockpit = c
	layer = l
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	modulate = Color(0.8, 0.8, 0.8) if cockpit != null and cockpit.night else Color.WHITE  # dimmed at night
	queue_redraw()


## A rect of the [PCD] section (panel px [x, y, w, h]) on screen.
func _rect(r: Array) -> Rect2:
	var a: Vector2 = cockpit.panel_to_screen(float(r[0]), float(r[1]))
	return Rect2(a, Vector2(float(r[2]), float(r[3])) * cockpit.ui_scale())


func glass() -> Rect2:
	return _rect(cockpit.layout.PCD.Rect)


## The eight lower windows' screen rects, left to right.
func windows() -> Array:
	var p: Dictionary = cockpit.layout.PCD
	var g := glass()
	var top: float = cockpit.panel_to_screen(0, float(p.WindowTop)).y
	var w := g.size.x / 8.0
	var out := []
	for i in 8:
		out.append(Rect2(g.position.x + i * w, top, w, g.end.y - top))
	return out


func _draw() -> void:
	if cockpit == null or not cockpit.layout.has("PCD"):
		return
	if layer == 1:
		_draw_sheen()
		return
	var g := glass()
	draw_rect(g, NAVY)
	_draw_bar(g)
	_draw_frames(g)
	var w := windows()
	_draw_fuel(w[0])
	_draw_engine(w[1])
	_draw_gear(w[2])
	_draw_icaws(w[3].merge(w[4]))
	_draw_autopilot(w[5])
	_draw_cm(w[6])
	_draw_nav(w[7])
	_draw_esis(_rect(cockpit.layout.PCD.Esis))


func _fs(px: float) -> int:
	return maxi(int(px * cockpit.ui_scale()), 4)


func _text(at: Vector2, t: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, t, align, width, _fs(size), col)


# --- the status bar and the frames ----------------------------------------------------------------------------

## The cautions the lamps / indicators raise (docs/cockpit.md "Panel lights"), worst first: [text, colour].
func cautions() -> Array:
	var ind: Array = cockpit.indicators
	var out := []
	if ind[1] or ind[2]:
		out.append(["ENG FIRE", RED])
	if ind[0]:
		out.append(["MASTER CAUTION", AMBER])
	if ind[3]:
		out.append(["RWR AIR THREAT", AMBER])
	if ind[4]:
		out.append(["RWR SAM THREAT", AMBER])
	if cockpit.damage_flags.any(func(f): return f):
		out.append(["SYSTEM DAMAGE", AMBER])
	if ind[5]:
		out.append(["SPEED BRAKE", CYAN])
	if ind[6]:
		out.append(["ECM ON", CYAN])
	return out


func _draw_bar(g: Rect2) -> void:
	var h: float = float(cockpit.layout.PCD.Bar) * cockpit.ui_scale()
	var bar := Rect2(g.position, Vector2(g.size.x, h))
	draw_rect(bar, BAR)
	var y := bar.position.y + h * 0.78
	var st: Dictionary = cockpit.state
	var c := cautions()
	var warn := c.any(func(e): return e[1] == RED)
	_text(Vector2(g.position.x + 6 * cockpit.ui_scale(), y), "ICAWS", 9, RED if warn else (AMBER if not c.is_empty() else CYAN))
	_text(Vector2(g.position.x + 40 * cockpit.ui_scale(), y), "%d" % c.size(), 9, WHITE)
	_text(Vector2(g.position.x + 62 * cockpit.ui_scale(), y), "AP", 9, GREEN if cockpit.indicators[8] else DIM)
	var tod := int(st.get("tod", 0.0))
	_text(Vector2(g.position.x, y), "%02d:%02d:%02d" % [(tod / 3600) % 24, (tod / 60) % 60, tod % 60], 9, WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, g.size.x)


func _draw_frames(g: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var bar_y: float = g.position.y + float(cockpit.layout.PCD.Bar) * s
	var win_y: float = cockpit.panel_to_screen(0, float(cockpit.layout.PCD.WindowTop)).y
	draw_line(Vector2(g.position.x, bar_y), Vector2(g.end.x, bar_y), FRAME, maxf(1.0, s * 0.8))
	draw_line(Vector2(g.position.x, win_y), Vector2(g.end.x, win_y), FRAME, maxf(1.0, s * 0.8))
	for i in range(1, 8):
		var x := g.position.x + g.size.x * i / 8.0
		draw_line(Vector2(x, win_y), Vector2(x, g.end.y), FRAME, maxf(1.0, s * 0.6))
	for i in range(1, 4):
		var x := g.position.x + g.size.x * i / 4.0
		draw_line(Vector2(x, bar_y), Vector2(x, win_y), FRAME, maxf(1.0, s * 0.8))
	# The two halves (each with its own power and processor): a darker seam down the middle.
	var mid := g.position.x + g.size.x / 2.0
	draw_line(Vector2(mid, g.position.y), Vector2(mid, g.end.y), Color(0, 0, 0, 0.8), maxf(1.5, s * 1.4))
	draw_rect(g, FRAME.darkened(0.3), false, maxf(1.0, s))


func _title(r: Rect2, t: String) -> float:
	var s: float = cockpit.ui_scale()
	_text(r.position + Vector2(3 * s, 9 * s), t, 8, CYAN)
	return r.position.y + 11 * s


# --- the lower windows ------------------------------------------------------------------------------------------

func _draw_fuel(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "FUEL")
	var lbs := int(cockpit.state.get("fuel_lbs", 0.0))
	_text(Vector2(r.position.x, y + 17.4 * s), "%d" % lbs, 14, GREEN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_text(Vector2(r.position.x, y + 30.4 * s), "TOTAL LB", 8, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# The fill bar (internal fuel of 18,250 lb, the F-35A's).
	var fill := clampf(float(cockpit.state.get("fuel_fill", lbs / 18250.0)), 0.0, 1.0)
	var bar := Rect2(r.position.x + 6 * s, r.end.y - 9 * s, r.size.x - 12 * s, 4 * s)
	draw_rect(bar, DIM, false, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), GREEN if fill > 0.15 else AMBER)


func _draw_engine(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "ENG")
	var st: Dictionary = cockpit.state
	var ab := float(st.get("afterburner", 0.0)) > 0.0
	_text(Vector2(r.position.x + 4 * s, y + 14.5 * s), "THR", 8, DIM)
	_text(Vector2(r.position.x, y + 14.5 * s), "%d%%  " % int(round(float(st.throttle) * 100.0)), 11, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)
	_text(Vector2(r.position.x + 4 * s, y + 30.4 * s), "RPM", 8, DIM)
	_text(Vector2(r.position.x, y + 30.4 * s), "%d%%  " % int(round(float(st.get("rpm", 0.0)) * 100.0)), 11, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)
	if ab:
		_text(Vector2(r.position.x, r.end.y - 4 * s), "AB", 11, AMBER, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_gear(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "GEAR")
	var c := Vector2(r.get_center().x, y + 13 * s)
	var spots := [c, c + Vector2(-12, 12) * s, c + Vector2(12, 12) * s]  # nose, left, right
	for i in 3:
		var v: int = cockpit.gear_legs[i]
		var b := Rect2(spots[i] - Vector2(4.5, 4.5) * s, Vector2(9, 9) * s)
		if v == 2:
			draw_rect(b, GREEN)
		elif v == 1:
			draw_rect(b, AMBER)
		else:
			draw_rect(b, DIM, false, 1.0)
	var flaps: int = cockpit.flaps_state
	_text(Vector2(r.position.x, r.end.y - 4 * s), "FLAPS " + ["UP", "TRANS", "DN"][clampi(flaps, 0, 2)], 8,
			[DIM, AMBER, GREEN][clampi(flaps, 0, 2)], HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_icaws(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "ICAWS")
	var c := cautions()
	if c.is_empty():
		_text(Vector2(r.position.x, y + 20.3 * s), "NO CAUTIONS", 9, DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in mini(c.size(), 5):
		_text(Vector2(r.position.x + 6 * s, y + (11.6 + 10.9 * i) * s), c[i][0], 9, c[i][1])


func _draw_autopilot(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "AP")
	var on: bool = cockpit.indicators[8]
	_text(Vector2(r.position.x, y + 17.4 * s), "ON" if on else "OFF", 11, GREEN if on else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var mode := int(cockpit.state.get("ap_mode", 0))
	_text(Vector2(r.position.x, y + 31.9 * s), ["", "LVL", "NAV"][clampi(mode, 0, 2)], 8, CYAN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_cm(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "CM")
	var wp: Dictionary = cockpit.weapons
	for i in 2:
		var key: String = ["chaff", "flares"][i]
		_text(Vector2(r.position.x + 4 * s, y + (14.5 + 15.9 * i) * s), ["CHAFF", "FLARE"][i], 8, DIM)
		var n := int(wp.get(key, 0))
		_text(Vector2(r.position.x, y + (14.5 + 15.9 * i) * s), "%d  " % n, 11, WHITE if n > 0 else AMBER, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)


func _draw_nav(r: Rect2) -> void:
	var s: float = cockpit.ui_scale()
	var y := _title(r, "CNI")
	var st: Dictionary = cockpit.state
	var rows := [["HDG", "%03d" % (int(round(float(st.heading))) % 360)], ["CAS", "%d" % int(st.get("ias_kt", 0.0))],
		["G", "%.1f" % float(st.get("g", 1.0))]]
	for i in rows.size():
		_text(Vector2(r.position.x + 4 * s, y + (14.5 + 14.5 * i) * s), rows[i][0], 8, DIM)
		_text(Vector2(r.position.x, y + (14.5 + 14.5 * i) * s), rows[i][1] + "  ", 11, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)


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
	draw_polyline(PackedVector2Array([c + Vector2(-a, 0), c + Vector2(-a * 0.35, 0), c + Vector2(0, a * 0.25),
			c + Vector2(a * 0.35, 0), c + Vector2(a, 0)]), AMBER, maxf(1.5, s * 1.2))
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
	_text(Vector2(hb.position.x, hb.end.y - bh * 0.22), "%03d" % (int(round(float(st.heading))) % 360), fs, WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, bw)
	draw_rect(r, Color(0, 0, 0), false, maxf(1.0, s))


## The ground's part of the ESIS box `box` below the horizon through `h` (along `right`, ground towards `down`). A
## horizon that grazes a corner leaves a sliver a fraction of a pixel thick that the renderer cannot triangulate
## ("Invalid polygon data"): such slivers are left out.
static func ground_polys(box: PackedVector2Array, h: Vector2, right: Vector2, down: Vector2) -> Array:
	var big := (box[2] - box[0]).length() * 2.0
	var ground := PackedVector2Array([h - right * big, h + right * big, h + right * big + down * big, h - right * big + down * big])
	return Geometry2D.intersect_polygons(box, ground).filter(func(p): return not Geometry2D.triangulate_polygon(p).is_empty())


# --- layer 1: the glass ------------------------------------------------------------------------------------------

## A faint sheen over the whole glass, the canopy's light reflected near its top fading downward.
func _draw_sheen() -> void:
	var g := glass()
	var mid := g.position.y + g.size.y * 0.45
	var top := Color(0.75, 0.82, 0.95, 0.07)
	var clear := Color(0.75, 0.82, 0.95, 0.0)
	draw_polygon(PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), Vector2(g.end.x, mid), Vector2(g.position.x, mid)]),
			PackedColorArray([top, top, clear, clear]))
	# A soft diagonal streak across the left half.
	var x0 := g.position.x + g.size.x * 0.08
	var w := g.size.x * 0.10
	var streak := Color(0.85, 0.9, 1.0, 0.035)
	draw_polygon(PackedVector2Array([Vector2(x0 + w, g.position.y), Vector2(x0 + 2.2 * w, g.position.y),
			Vector2(x0 + w * 1.2, g.end.y), Vector2(x0, g.end.y)]), PackedColorArray([streak, clear, clear, streak]))
