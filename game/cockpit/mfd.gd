# One cockpit MFD (docs/mfd.md): a 132x132 display placed on the panel at [MFD] <Side>OffsetX/Y,
# with its pages drawn from the mfds.bmp atlas, the 5x5 sprite font and GDI-style vectors, and the
# bezel buttons (OSBs) around it as click zones. Generic for every cockpit; the cockpit node
# (cockpit.gd) supplies layout, textures and the flight state.
extends Control

const SIZE := 132.0
## Bezel strips reach 16 px outside the display.
const BEZEL := 16.0
const GREEN := Color8(0, 255, 0)
const DIM_GREEN := Color8(0, 128, 0)

## Pages (state+0x504): 0 NAV, 1 stores, 2 radar, 3 TSD, 4 damage, 5 TV, 6 FLIR, 7 RWR, 8 MENU,
## 9 ADI, 10 HARM.
enum { NAV, STORES, RADAR, TSD, DAMAGE, TV, FLIR, RWR, MENU, ADI, HARM }

## mfds.bmp tiles (table 0x65d068), by page / radar mode.
const TILE_BLANK := Vector2(0, 0)
const TILE_RWR := Vector2(132, 0)
const TILE_STORES := Vector2(0, 132)
const TILE_RADAR_AA := Vector2(0, 264)
const TILE_TSD := Vector2(0, 396)
const TILE_MAP := Vector2(132, 528)
const TILE_FLIR := Vector2(0, 660)
const TILE_GMT := Vector2(132, 660)
const TILE_TV := Vector2(0, 792)

## Radar sub-modes (state+0xa04) and their labels.
const RADAR_MODES := ["OFF", "STBY", "STT", "BORE", "LRS", "TWS", "ACM", "GMT", "MAP"]
const RADAR_RANGES := [5, 10, 20, 40, 80, 160]
const TSD_SCALES := [10, 20, 40, 80]

var cockpit: Control
var index := 0  # 0 left, 1 right, 2 middle (a panoramic display: the portal's number)
## A portal of a panoramic display ([MFD] Portals) is the MFD drawn at this scale.
var portal_scale := 1.0
var page := RADAR
## TSD: scale (+0x279c, default 40) and the SAM / WPT / MAP / SCL options (default on).
var tsd_scale := 40
var tsd_options := [true, true, true, true]
var nav_scroll := 0
var hover_osb := -1
## The mouse over the display (MFD px; null = elsewhere): the MAP / GMT cross-hair (renderer +0x27b4 while
## this MFD owns the cursor, +0x27e4).
var mouse = null
## The MAP page's latches (FUN_00535ea0 globals): the last EXP flag (DAT_0083e358), the heading and the
## centre frozen on entering EXP (DAT_0083e368, DAT_0083e350 / 354), the last clicked point
## (DAT_0083e360 / 364, world X / Y).
var _map_exp_prev := false
var _map_heading := 0.0
var _map_centre := Vector2.ZERO
var _map_point := Vector2.ZERO
## Line clipping (MFD px): the whole display (the GDI clip rect of pass 4), the MAP window there.
var _clip := Rect2(0, 0, SIZE, SIZE)


func setup(c: Control, idx: int, start_page: int) -> void:
	cockpit = c
	index = idx
	page = start_page
	mouse_filter = Control.MOUSE_FILTER_STOP


func _panel_offset() -> Vector2:
	var m: Dictionary = cockpit.layout.MFD
	if m.has("Portals"):
		return Vector2(float(m.Portals[index][0]), float(m.Portals[index][1]))
	var side: String = ["Left", "Right", "Middle"][index]
	return Vector2(float(m[side + "OffsetX"]), float(m[side + "OffsetY"]))


## The bezel the node covers around its page: none for a portal (its neighbours' pages are there; it is pressed on
## its labels, touch_osb).
func _bezel() -> float:
	return 0.0 if cockpit.layout.get("MFD", {}).has("Portals") else BEZEL


## Screen px per MFD px.
func _s() -> float:
	return cockpit.ui_scale() * portal_scale


func _process(_delta: float) -> void:
	var s := _s()
	var o := _panel_offset()
	var b := _bezel()
	position = cockpit.panel_to_screen(o.x - b * portal_scale, o.y - b * portal_scale)
	size = Vector2.ONE * (SIZE + 2 * b) * s
	queue_redraw()


# --- drawing primitives (MFD pixels) ----------------------------------------------------------

func _atlas() -> Texture2D:
	return cockpit.tex.get("MFDS")


func _blit(src: Rect2, dest: Vector2) -> void:
	var t := _atlas()
	if t == null:
		return
	var a: float = cockpit.layout.get("image_scale", 1)
	draw_texture_rect_region(t, Rect2(dest, src.size), Rect2(src.position * a, src.size * a))


func _tile(at: Vector2) -> void:
	_blit(Rect2(at, Vector2(SIZE, SIZE)), Vector2.ZERO)


## 5x5 sprite font (FUN_00525890): letters from (132,850), digits and symbols from (132,840).
static func _glyph_x(c: String) -> int:
	var u := c.unicode_at(0)
	if u >= 65 and u <= 90:
		return 5 * (u - 65)
	if u >= 97 and u <= 122:
		return 5 * (u - 97)
	if u >= 48 and u <= 57:
		return 130 + 5 * (u - 48)
	match c:
		".": return 185
		":": return 190
		"+": return 195
		"-": return 200
		"%": return 205
	return 180


func _text(pos: Vector2, text: String) -> void:
	for i in text.length():
		var x := _glyph_x(text[i])
		var src := Rect2(132 + x, 850, 5, 5) if x < 130 else Rect2(132 + x - 130, 840, 5, 5)
		_blit(src, pos + Vector2(5 * i, 0))


func _text_right(end_x: float, y: float, text: String) -> void:
	_text(Vector2(end_x - 5 * text.length(), y), text)


func _line(a: Vector2, b: Vector2, color := GREEN) -> void:
	if _clip.has_point(a) and _clip.has_point(b):
		draw_line(a, b, color, 1.0)
		return
	if a.is_equal_approx(b):
		return
	var c := _clip
	var poly := PackedVector2Array([c.position, Vector2(c.end.x, c.position.y), c.end, Vector2(c.position.x, c.end.y)])
	for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly):
		if seg.size() >= 2:
			draw_polyline(seg, color, 1.0)


# --- pages ------------------------------------------------------------------------------------

func _draw() -> void:
	if cockpit == null or cockpit.layout.is_empty():
		return
	var s := _s()
	draw_set_transform(Vector2.ONE * _bezel() * s, 0.0, Vector2(s, s))
	# A portal's hovered label: the touch box (ours; the originals' buttons are in their panel art).
	if _bezel() == 0.0 and hover_osb > 0:
		draw_rect(touch_rect(hover_osb), DIM_GREEN, false, 1.0)
	match page:
		RADAR:
			_draw_radar()
		TSD:
			_draw_tsd()
		RWR:
			_draw_rwr()
		MENU:
			_draw_menu()
		NAV:
			_draw_nav()
		STORES:
			_draw_stores()
		DAMAGE:
			_draw_damage()
		ADI:
			_draw_adi()
		HARM:
			_draw_harm()
		FLIR:
			_draw_flir()
		TV:
			_draw_tv()
	draw_set_transform(Vector2.ZERO)


## The radar page (FUN_005333d0 and helpers) from the radar snapshot (cockpit.radar, state+0x640..
## / +0xa00..; docs/radar.md): tile and label, range sprite, horizon bars, antenna carets, contacts.
func _draw_radar() -> void:
	var r: Dictionary = cockpit.radar
	var mode := int(r.get("mode", 0))
	var idx := int(r.get("idx", 1))
	var nm: float = RADAR_RANGES[clampi(idx, 1, 6) - 1]
	match mode:
		7: _tile(TILE_GMT)
		8:
			_draw_map_picture(r, nm)
			_tile(TILE_MAP)
		_:
			_tile(TILE_RADAR_AA)
			_text(Vector2(17, 3), RADAR_MODES[mode])
	if mode >= 3:
		_blit(Rect2(132 + 8 * (idx - 1), 845, 8, 5), Vector2(1, 33))
	if mode == 8:
		_text(Vector2(60, 3), "EXP" if r.get("exp", false) else "NORM")
		_draw_map_symbols(r, nm)
		return
	if mode == 7:
		_draw_gmt(r, nm)
		return
	if mode >= 2:
		_draw_horizon_bars()
	if mode < 2:
		return
	_draw_carets(r.get("antenna", Vector2.ZERO))
	for c in r.get("contacts", []):
		# B-scope: x = 66 + (az + shift)·112 / width, y = 115 − range / (R·16.5446) (R NM = 112 px).
		var p := Vector2(66.0 + (float(c.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
				115.0 - float(c.dist) / (nm * 16.5446))
		if p.x <= 8 or p.x >= 124 or p.y <= 8 or p.y >= 124:
			continue
		p = p.round()
		match mode:
			3, 6:
				_box(p, 1)
				_line(p + Vector2(-1, 1), p + Vector2(1, -1))
			4:
				_box(p, 2)
				_box(p, 1)
			5:
				if c.selected:
					draw_circle(p, 3.5, GREEN)
					_aspect_stub(p, c)
				else:
					_box(p, 2)
			2:
				draw_circle(p, 3.5, GREEN)
				_aspect_stub(p, c)
	_draw_steer_bscope(nm)
	if mode == 2 and not r.get("lock", {}).is_empty():
		_draw_stt_text(r, nm)


## The steerpoint (state+0x70: the current waypoint, from the nav update FUN_004459f0) on the A-A pages
## (FUN_005338b0): d = distance / (R·16.5446) px, b = ⌊bearing°⌋ − ⌊heading°⌋ wrapped to ±180; within
## ±60° a triangle at x = 66 + b, its base at y = 125 − d.
func _draw_steer_bscope(nm: float) -> void:
	var sp = _steerpoint()
	if sp == null:
		return
	var st: Dictionary = cockpit.state
	var own: Vector2 = st.get("world", Vector2.ZERO)
	var dv: Vector2 = sp - own
	var d := int(dv.length() / (nm * 16.5446))
	var h := int(st.heading)
	if h < 0:
		h += 360
	var b := int(rad_to_deg(atan2(dv.x, dv.y))) - h
	if b > 180:
		b -= 360
	if b < -180:
		b += 360
	if b >= 60 or b <= -60:
		return
	_steer_triangle(Vector2(66 + b, 122 - d))


## The steer triangle about (x, y) (FUN_005338b0 / FUN_00535400 / FUN_00535ea0): base (x−3, y+3)–(x+4, y+3),
## sides (x−3, y+2)–(x, y−3)–(x+4, y+4).
func _steer_triangle(p: Vector2) -> void:
	_line(p + Vector2(-3, 3), p + Vector2(4, 3))
	_line(p + Vector2(-3, 2), p + Vector2(0, -3))
	_line(p + Vector2(0, -3), p + Vector2(4, 4))


## The current waypoint's world X / Y (state+0x70), or null.
func _steerpoint():
	var wps: Array = cockpit.waypoints
	var i: int = cockpit.current_waypoint
	return wps[i].world if i >= 0 and i < wps.size() else null


## Antenna carets (FUN_00533500): v = clamp(⌊val·106⌋, 0, 106); azimuth at x = 13 + v (y 117..120,
## bar x 11+v..16+v at y 117), elevation at y = 13 + v (x 11..14, bar at x 14).
func _draw_carets(a: Vector2) -> void:
	var vx := clampi(int(a.x * 106.0), 0, 106)
	var vy := clampi(int(a.y * 106.0), 0, 106)
	_line(Vector2(13 + vx, 117), Vector2(13 + vx, 120))
	_line(Vector2(11 + vx, 117), Vector2(16 + vx, 117))
	_line(Vector2(11, 13 + vy), Vector2(14, 13 + vy))
	_line(Vector2(14, 11 + vy), Vector2(14, 16 + vy))


func _box(p: Vector2, h: int) -> void:
	draw_rect(Rect2(p - Vector2(h, h), Vector2(2 * h, 2 * h)), GREEN, false, 1.0)


## The 4 px aspect stub, quantised to 45° (TWS / STT): the target's heading on the heading-up scope
## (UNCERTAIN: the reference of the stub).
func _aspect_stub(p: Vector2, c: Dictionary) -> void:
	var own_h: float = cockpit.state.get("heading", 0.0)
	var a := deg_to_rad(round(wrapf(float(c.heading) - own_h, -180.0, 180.0) / 45.0) * 45.0)
	_line(p, p + Vector2(sin(a), -cos(a)) * 4.0)


## STT text (FUN_00533db0 / FUN_00534160): "%3dK" target speed at (86,3), aspect "%2dL" / "%2dR" at
## (62,3), the range scale at x 121 (y 10..122) with the "<" caret at y = 115 − r·112/(R·1853) and the
## closure "%3dK" at (111, caret + 8). (The two envelope ticks of the scale are not drawn: DLZ untraced.)
func _draw_stt_text(r: Dictionary, nm: float) -> void:
	var lk: Dictionary = r.lock
	_text(Vector2(86, 3), "%3dK" % int(lk.speed))
	_text(Vector2(62, 3), aspect_text(float(lk.aspect)))
	_line(Vector2(121, 10), Vector2(121, 122))
	var y := 115.0 - float(lk.dist) * 112.0 / (nm * 1853.0)
	y = clampf(y, 10.0, 122.0)
	_line(Vector2(118, y - 2), Vector2(116, y))
	_line(Vector2(116, y), Vector2(118, y + 2))
	_text_right(128, y + 8, "%3dK" % int(float(r.get("closure", 0.0)) * 1.9427955))


## Aspect "%2dL" / "%2dR" (FUN_0052ef20): n = (⌊aspect°⌋ % 360) / 10 wrapped to ±18; the sign gives
## L or R (UNCERTAIN which), |n| shown.
static func aspect_text(aspect: float) -> String:
	var n := (int(rad_to_deg(aspect)) % 360) / 10
	if n > 18:
		n -= 36
	elif n < -18:
		n += 36
	return "%2d%s" % [absi(n), "R" if n >= 0 else "L"]


## The heading-up transform of a world offset (ex east, ny north) to MFD px at k m/px.
static func _heading_up(e: Vector2, hdg: float, k: float) -> Vector2:
	var S := sin(hdg)
	var C := cos(hdg)
	return Vector2(e.x * C - e.y * S, -(e.x * S + e.y * C)) / k


## A ground contact (GMT / MAP): ±10 cross when locked, then the 3×3 box (MAP: with the \ diagonal).
func _ground_symbol(p: Vector2, locked: bool, diagonal: bool) -> void:
	if locked:
		_line(p - Vector2(10, 0), p + Vector2(10, 0))
		_line(p - Vector2(0, 10), p + Vector2(0, 10))
	_line(p + Vector2(-1, -1), p + Vector2(-1, 1))
	_line(p + Vector2(-1, 1), p + Vector2(1, 1))
	_line(p + Vector2(1, 1), p + Vector2(1, -1))
	_line(p + Vector2(1, -1), p + Vector2(-1, -1))
	if diagonal:
		_line(p + Vector2(-1, -1), p + Vector2(1, 1))


## The mouse cross-hair (GMT / MAP while this MFD owns the cursor): lines to the display edges with a 3 px
## gap; 5 px ticks at ±31 px (not in EXP).
func _cross_hair(ticks: bool) -> void:
	if mouse == null:
		return
	var m: Vector2 = mouse
	_line(Vector2(m.x - 3, m.y), Vector2(0, m.y))
	_line(Vector2(m.x + 3, m.y), Vector2(SIZE, m.y))
	_line(Vector2(m.x, m.y - 3), Vector2(m.x, 0))
	_line(Vector2(m.x, m.y + 3), Vector2(m.x, SIZE))
	if ticks:
		for sgn in [-31.0, 31.0]:
			_line(Vector2(m.x + sgn, m.y - 2), Vector2(m.x + sgn, m.y + 3))
			_line(Vector2(m.x - 2, m.y + sgn), Vector2(m.x + 3, m.y + sgn))


## GMT (FUN_00535400): heading-up PPI from (66,109) at R·1853/56 m/px: the cross-hair, the contacts, the
## steerpoint triangle, the horizon bars and the antenna carets.
func _draw_gmt(r: Dictionary, nm: float) -> void:
	_cross_hair(true)
	var st: Dictionary = cockpit.state
	var own: Vector2 = st.get("world", Vector2.ZERO)
	var hdg := deg_to_rad(st.heading)
	var k := nm * 1853.0 / 56.0
	for c in r.get("contacts", []):
		var w: Vector3 = c.pos
		var p := (Vector2(66, 109) + _heading_up(Vector2(w.x, w.y) - own, hdg, k)).floor()
		_ground_symbol(p, c.locked, false)
	var sp = _steerpoint()
	if sp != null:
		_steer_triangle((Vector2(66, 109) + _heading_up(sp - own, hdg, k)).floor())
	_draw_horizon_bars()
	_draw_carets(r.get("antenna", Vector2.ZERO))


## isr.bmp (640 × 832) georeference, cockpits.ibx [MAPFRAME] (shared by every cockpit; FUN_005226e0):
## col = (X + 166828 − left) / (right − left) · 640, row = (top − (Y + 21164)) / (top − bottom) · 832
## (FUN_00535ea0 @53608b), i.e. 1280 m per isr pixel.
const MAPFRAME := {"left": 0.0, "top": 1064960.0, "bottom": 0.0, "right": 819200.0}
const ISR_SIZE := Vector2(640, 832)
## The MAP window (15,15)–(116,109): 101 × 94 px, 94 px = R NM (FUN_0053b0a0 pass 1).
const MAP_WINDOW := Rect2(15, 15, 101, 94)


static func isr_px(w: Vector2) -> Vector2:
	var f: Dictionary = MAPFRAME
	return Vector2((w.x + 166828.0 - f.left) / (f.right - f.left) * ISR_SIZE.x,
			(f.top - (w.y + 21164.0)) / (f.top - f.bottom) * ISR_SIZE.y)


## The MAP page centre and heading: NORM = the ownship and its heading; EXP = the point clicked last and
## the heading, both latched when EXP comes on (DAT_0083e350 / 354, DAT_0083e368).
func _map_frame(r: Dictionary) -> Dictionary:
	var st: Dictionary = cockpit.state
	var e: bool = r.get("exp", false)
	if e != _map_exp_prev:
		_map_heading = deg_to_rad(st.heading)
		_map_centre = _map_point
		_map_exp_prev = e
	if e:
		return {"centre": _map_centre, "hdg": _map_heading, "img": Vector2(65, 62), "sym": Vector2(66, 66)}
	return {"centre": st.get("world", Vector2.ZERO), "hdg": deg_to_rad(st.heading), "img": Vector2(65, 109),
		"sym": Vector2(66, 109)}


## The MAP picture (FUN_0053b0a0, pass 1, before the tile): isr.bmp's green channel (loaded with the
## green palette, FUN_0053ae00(…, 1)) turned heading-up about the centre, S = R·1853·832 / ((top −
## bottom)·94) isr px per MFD px; black outside the image. It shows through the tile's cyan fan.
func _draw_map_picture(r: Dictionary, nm: float) -> void:
	draw_rect(MAP_WINDOW, Color.BLACK)
	var t := _isr()
	if t == null:
		return
	var f := _map_frame(r)
	for piece in map_picture(f.centre, f.hdg, nm, f.img):
		draw_colored_polygon(piece.points, Color(0, 1, 0), piece.uvs, t)


## The MAP picture's polygons in the window: [{points (MFD px), uvs (0..1 of isr.bmp)}] for the centre
## (world X / Y) shown at MFD px `img`, heading-up for `hdg` (rad), range `nm`. isr px q of MFD px p:
## q = q0 + S·(dx·C − dy·S', dx·S' + dy·C), (dx, dy) = p − img.
static func map_picture(centre: Vector2, hdg: float, nm: float, img: Vector2) -> Array:
	var s: float = nm * 1853.0 * ISR_SIZE.y / ((MAPFRAME.top - MAPFRAME.bottom) * 94.0)
	var C := cos(hdg)
	var S := sin(hdg)
	var q0 := isr_px(centre)
	var corners := PackedVector2Array()
	for q in [Vector2.ZERO, Vector2(ISR_SIZE.x, 0), ISR_SIZE, Vector2(0, ISR_SIZE.y)]:
		var d: Vector2 = (q - q0) / s
		corners.append(img + Vector2(d.x * C + d.y * S, -d.x * S + d.y * C))
	var win := PackedVector2Array([MAP_WINDOW.position, Vector2(MAP_WINDOW.end.x, MAP_WINDOW.position.y),
		MAP_WINDOW.end, Vector2(MAP_WINDOW.position.x, MAP_WINDOW.end.y)])
	var out := []
	for piece in Geometry2D.intersect_polygons(corners, win):
		if piece.size() < 3:
			continue
		var uvs := PackedVector2Array()
		for p in piece:
			var d: Vector2 = p - img
			uvs.append((q0 + s * Vector2(d.x * C - d.y * S, d.x * S + d.y * C)) / ISR_SIZE)
		out.append({"points": piece, "uvs": uvs})
	return out


func _isr() -> Texture2D:
	if not cockpit.tex.has("ISR"):
		cockpit._add_tex("ISR", "isr.bmp")
		if not cockpit.tex.has("ISR"):
			cockpit.tex["ISR"] = null
	return cockpit.tex.ISR


## MAP symbols (FUN_00535ea0 pass 4, clipped to the window (15,15)–(116,109)) at R·19.7128 m/px from the
## centre: the cross-hair, the contacts, the designation cross (a designated point and no locked contact),
## the steerpoint triangle, the horizon bars and the antenna carets.
func _draw_map_symbols(r: Dictionary, nm: float) -> void:
	_clip = MAP_WINDOW
	var f := _map_frame(r)
	var k := nm * 19.7128
	var centre: Vector2 = f.centre
	var sym: Vector2 = f.sym
	_cross_hair(not r.get("exp", false))
	var any_locked := false
	for c in r.get("contacts", []):
		var w: Vector3 = c.pos
		var p := (sym + _heading_up(Vector2(w.x, w.y) - centre, f.hdg, k)).floor()
		any_locked = any_locked or c.locked
		_ground_symbol(p, c.locked, true)
	if r.get("designated", false) and not any_locked:
		var p := (sym + _heading_up(_map_point - centre, f.hdg, k)).floor()
		_line(p - Vector2(10, 0), p + Vector2(10, 0))
		_line(p - Vector2(0, 10), p + Vector2(0, 10))
	var sp = _steerpoint()
	if sp != null:
		_steer_triangle((sym + _heading_up(sp - centre, f.hdg, k)).floor())
	_draw_horizon_bars()
	_draw_carets(r.get("antenna", Vector2.ZERO))
	_clip = Rect2(0, 0, SIZE, SIZE)


## A MAP click (FUN_00535ea0 pass 4): on an unlocked contact (±4 px) event 0x2a (lock it), else event 0x2f
## with the world point under the cursor (designate); either becomes the latched point.
func _click_map(p: Vector2) -> void:
	var r: Dictionary = cockpit.radar
	var nm: float = RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1]
	var f := _map_frame(r)
	var k := nm * 19.7128
	for c in r.get("contacts", []):
		var w: Vector3 = c.pos
		var cp := (Vector2(f.sym) + _heading_up(Vector2(w.x, w.y) - f.centre, f.hdg, k)).floor()
		if not c.locked and absf(p.x - cp.x) < 4 and absf(p.y - cp.y) < 4:
			_map_point = Vector2(w.x, w.y).floor()
			_radar_event(0x2a, c.key)
			return
	var a := (p.x - 66.0) * k
	var b := (float(f.sym.y) - p.y) * k
	var ang := atan2(a, b) + float(f.hdg)
	_map_point = (Vector2(f.centre) + Vector2(sin(ang), cos(ang)) * sqrt(a * a + b * b)).floor()
	_radar_event(0x2f, _map_point)


## A GMT click (FUN_00535400): on an unlocked contact (±4 px) event 0x2a.
func _click_gmt(p: Vector2) -> void:
	var r: Dictionary = cockpit.radar
	var nm: float = RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1]
	var st: Dictionary = cockpit.state
	var own: Vector2 = st.get("world", Vector2.ZERO)
	for c in r.get("contacts", []):
		var w: Vector3 = c.pos
		var cp := (Vector2(66, 109) + _heading_up(Vector2(w.x, w.y) - own, deg_to_rad(st.heading), nm * 1853.0 / 56.0)).floor()
		if not c.locked and absf(p.x - cp.x) < 4 and absf(p.y - cp.y) < 4:
			_radar_event(0x2a, c.key)
			return


func _radar_event(ev: int, arg = null) -> void:
	if cockpit.on_radar_event.is_valid():
		cockpit.on_radar_event.call(ev, arg)


## The EO picture (viewport 1 into the video rect (10,10)–(122,122), before the tile: it shows through the
## tile's cyan box).
func _eo_picture() -> void:
	if cockpit.eo_texture != null and cockpit.eo.get("camera", false):
		draw_texture_rect(cockpit.eo_texture, Rect2(10, 10, 112, 112), false)


## FLIR page (FUN_00536c10): the picture, the tile (0,660), zoom "%1d" right-aligned at (11,33), WIDE / SPOT
## right-aligned at (114,3), LASER OFF / ON at (42,3), the range NM right-aligned at (98,124), the gimbal blob
## at (66 − 56u, 66 + 56v).
func _draw_flir() -> void:
	_eo_picture()
	_tile(TILE_FLIR)
	var f: Dictionary = cockpit.eo.get("flir", {})
	if f.is_empty():
		return
	_text_right(11, 33, "%d" % int(f.zoom))
	_text_right(114, 3, "SPOT" if f.spot else "WIDE")
	_text(Vector2(42, 3), "LASER ON" if f.laser else "LASER OFF")
	_text_right(98, 124, String(f.range))
	var x := int(66.0 - 56.0 * float(f.u))
	var y := int(66.0 + 56.0 * float(f.v))
	draw_polyline(PackedVector2Array([Vector2(x - 1, y - 2), Vector2(x + 1, y - 2), Vector2(x + 2, y - 1),
		Vector2(x - 2, y - 1), Vector2(x - 2, y), Vector2(x + 2, y), Vector2(x + 2, y + 1), Vector2(x - 2, y + 1),
		Vector2(x - 1, y + 2), Vector2(x + 2, y + 2)]), GREEN, 1.0)


## TV page (FUN_005369e0): with a source (status ≠ 0) the picture, the tile (0,792), zoom "%1d" (11,33) and the
## seeker ticks (x = 66 − 56u, y 64..69; y = 66 + 56v, x 63..69), else the blank tile; the status right-aligned at
## (114,3). (The "%3d" at (111,110) comes from a launched weapon: not drawn, deviations.md.)
const TV_STATUS := ["NO SOURCE", "RDY", "TRA", "TER"]


func _draw_tv() -> void:
	var tv: Dictionary = cockpit.eo.get("tv", {})
	var st := int(tv.get("status", 0))
	if st != 0:
		_eo_picture()
		_tile(TILE_TV)
		_text_right(11, 33, "%d" % int(tv.zoom))
		var x := int(66.0 - 56.0 * float(tv.u))
		var y := int(66.0 + 56.0 * float(tv.v))
		_line(Vector2(x, 64), Vector2(x, 69))
		_line(Vector2(63, y), Vector2(69, y))
	else:
		_tile(TILE_BLANK)
	_text_right(114, 3, TV_STATUS[clampi(st, 0, 3)])


## HARM page (FUN_005358b0): "harm"; per emitter in the window 8 < x, y < 124 its character at (x − 2, y − 2)
## and a 8×8 box on the selected one, x = 66 + (az + dpsi)·112 / field, y = 66 − (el + dtheta)·112 / field;
## the cross-hair while the mouse is over the display; "no source" / "In Range" / "No Range" right-aligned at
## (114,3).
const HARM_CHAR := {290: "2", 300: "3", 310: "5", 320: "6", 330: "8", 340: "H", 350: "A", 360: "G", 9: "I", 0xb: "R"}


func _draw_harm() -> void:
	_tile(TILE_BLANK)
	_text(Vector2(17, 3), "harm")
	_cross_hair(false)
	var h: Dictionary = cockpit.harm
	for e in harm_symbols(h):
		_text(e.pos - Vector2(2, 2), HARM_CHAR.get(int(e.type), "0"))
		if e.selected:
			draw_rect(Rect2(e.pos - Vector2(4, 4), Vector2(8, 8)), GREEN, false, 1.0)
	var status := ""
	if h.get("no_source", true):
		status = "no source"
	elif h.get("in_range", false):
		status = "In Range"
	elif not h.get("list", []).is_empty():
		status = "No Range"
	_text_right(114, 3, status)


## The HARM symbols inside the window: [{key, type, selected, pos}].
static func harm_symbols(h: Dictionary) -> Array:
	var out := []
	var k: float = 112.0 / float(h.get("field", 0.5235988))
	for e in h.get("list", []):
		var x := 66 + int((float(e.az) + float(h.get("dpsi", 0.0))) * k)
		var y := 66 + int(-(float(e.el) + float(h.get("dtheta", 0.0))) * k)
		if x > 8 and x < 124 and y > 8 and y < 124:
			out.append({"key": e.key, "type": e.type, "selected": e.selected, "pos": Vector2(x, y)})
	return out


## The RWR page (FUN_00531290): the tile; with RWR damage (state+0x590 = flag 14) "Mal" at (101,3), else the
## symbols about (66,66), radius 56.
func _draw_rwr() -> void:
	_tile(TILE_RWR)
	var f: Array = cockpit.damage_flags
	if f.size() > 14 and f[14]:
		_text(Vector2(101, 3), "Mal")
	else:
		cockpit.draw_rwr_symbols(self, Vector2(66, 66), 56.0, 1.0)


## Artificial horizon bars (FUN_00533620): centre (66,66), rolled, 1 px per degree of pitch.
func _draw_horizon_bars() -> void:
	var st: Dictionary = cockpit.state
	var pitch := clampf(st.pitch, -40.0, 40.0)
	if absf(st.pitch) > 40.0 and int(Time.get_ticks_msec() / 300) % 2 == 1:
		return
	var rot := deg_to_rad(-st.roll)
	var centre := Vector2(66, 66 + pitch)
	for side in [-1.0, 1.0]:
		var pts := [Vector2(31 * side, 4), Vector2(31 * side, 0), Vector2(5 * side, 0)]
		for i in 2:
			_line(centre + pts[i].rotated(rot), centre + pts[i + 1].rotated(rot))


## MENU (FUN_0052b800): the labels by their OSBs; a black fill (14,124)–(33,129) erases the tile's "MENU";
## "FLIR" only with MenuFlirOn and the FLIR pod (state+0x610).
func _flir_menu() -> bool:
	return int(cockpit.layout.get("MFD", {}).get("MenuFlirOn", 1)) == 1 and cockpit.eo.get("flir_pod", false)


func _draw_menu() -> void:
	_tile(TILE_BLANK)
	draw_rect(Rect2(14, 124, 19, 5), Color.BLACK)
	var h: Dictionary = cockpit.layout.get("HORIZON", {})
	var rwr_panel := int(cockpit.layout.get("PANELRWR", {}).get("Active", 0)) == 1
	var left := {0xb: "FLIR" if _flir_menu() else "", 0xd: "stores", 0xe: "" if rwr_panel else "rwr", 0xf: "radar"}
	var right := {0x11: "NAV", 0x12: "damage", 0x13: "tactical", 0x14: "adi" if int(h.get("OnMfd", 0)) == 1 else ""}
	for id in left:
		_text(Vector2(5, 22 + 20 * (id - 0xb)), left[id])
	for id in right:
		_text_right(124, 42 + 20 * (id - 0x11), right[id])


func _draw_nav() -> void:
	_tile(TILE_BLANK)
	var wps: Array = cockpit.waypoints
	var cur: int = cockpit.current_waypoint
	var own: Vector2 = cockpit.state.get("world", Vector2.ZERO)
	for row in 3:
		var i := nav_scroll + row
		if i >= wps.size():
			break
		var y := 42 + 20 * row
		_text_right(8, y, "%d" % (i + 1))
		_text(Vector2(12, y + 1), String(wps[i].name).substr(0, 12))
		# FUN_0052c450: "% 3dM" NM at x 77, "%03d" bearing (true, from the ownship) at x 102, y + 1 (the original's
		# distance is 3-D; our route has no waypoint heights: horizontal).
		var d: Vector2 = wps[i].world - own
		var b := int(rad_to_deg(atan2(d.x, d.y)))
		_text(Vector2(77, y + 1), "%3dM" % int(d.length() / 1853.0))
		_text(Vector2(102, y + 1), "%03d" % (b + 360 if b < 0 else b))
		if i == cur:
			draw_polyline(PackedVector2Array([Vector2(8, y - 2), Vector2(8, y + 6), Vector2(1, y + 6), Vector2(1, y - 2),
				Vector2(8, y - 2)]), GREEN, 1.0)
	_text(Vector2(72, 124), "ETA   :")


## Stores page (FUN_0052c740, docs/mfd.md): per pylon station 0..8 the count and name positions
## (stations 6..8 right-aligned to x 128), the MRM / SRM totals, the gun rounds, the fuel and the
## selected station's box. OSBs 0xd, 0xc, 0xb, 1, 3, 5, 0x10, 0x11, 0x12 select stations 0..8.
const STORES_POS := [[4, 62, 4, 72], [4, 42, 4, 52], [4, 22, 4, 32], [24, 3, 17, 12], [64, 3, 57, 12],
	[104, 3, 97, 12], [128, 22, 128, 32], [128, 42, 128, 52], [128, 62, 128, 72]]
const STORES_OSB := [0xd, 0xc, 0xb, 1, 3, 5, 0x10, 0x11, 0x12]


func _draw_stores() -> void:
	_tile(TILE_STORES)
	var wp: Dictionary = cockpit.weapons
	if not wp.is_empty():
		for i in 9:
			var st: Dictionary = wp.stations[i]
			if int(st.type) == 0:
				continue
			var pos: Array = STORES_POS[i]
			var count := "%d" % int(st.count)
			var name := String(st.name)
			if i >= 6:
				_text_right(pos[0], pos[1], count)
				_text_right(pos[2], pos[3], name)
			else:
				_text(Vector2(pos[0], pos[1]), count)
				_text(Vector2(pos[2], pos[3]), name)
			if i == int(wp.selected):
				# Box 15x8 around the count (placement UNCERTAIN).
				var x: float = pos[0] - (5 * count.length() if i >= 6 else 0)
				draw_rect(Rect2(x - 2, pos[1] - 2, 15, 8), GREEN, false, 1.0)
		_text_right(59, 53, "%d" % int(wp.mrm))
		_text_right(59, 63, "%d" % int(wp.srm))
		_text(Vector2(68, 85), "%03d" % int(wp.gun))
		# The ripple quantity / interval (state +0x374 / +0x378).
		_text(Vector2(1, 94), "%dQnt" % int(wp.get("quantity", 2)))
		_text_right(131, 94, "int%d" % int(wp.get("interval", 10)))
		if int(wp.selected) == 9:
			draw_rect(Rect2(48, 82, 36, 10), GREEN, false, 1.0)
	_text(Vector2(55, 124), "Fuel : %5dLB" % int(cockpit.state.fuel_lbs))


## Damage page rows (FUN_0052bc00): format, x, y, the damage flags that make it NOGO (cockpit state
## +0x558 + 4n = the controller's damage flags, docs/damage.md §5). "ENG %s %s" / "AB %s %s" take
## "L" on twin-engine jets (else ""); the ENG R / AB R rows appear on twin-engine jets only.
const DAMAGE_ROWS := [
	["ENG %s %s", 12, 10, [22, 16, 2]], ["AB %s %s", 72, 10, [8]], ["INS  %s", 72, 34, [11]],
	["FUEL %s", 12, 43, [10]], ["RDR  %s", 72, 43, [15]], ["AILN %s", 12, 52, [18]],
	["RWR  %s", 72, 52, [14]], ["FLTC %s", 12, 61, [24]], ["WPNS %s", 72, 61, [20]],
	["FLAP %s", 12, 70, [4]], ["GUN  %s", 72, 70, [13]], ["GEAR %s", 12, 79, [7]],
	["ECM  %s", 72, 79, [1]], ["HUD  %s", 12, 88, [12]], ["A/P  %s", 72, 88, [6]],
	["BRAK %s", 12, 97, [5]], ["ELCT %s", 72, 97, [19]], ["GNRT %s", 72, 106, [21]],
]
const DAMAGE_ROWS_TWIN := [["ENG R %s", 12, 19, [23, 17, 3]], ["AB R %s", 72, 19, [9]]]


func _draw_damage() -> void:
	_tile(TILE_BLANK)
	var flags: Array = cockpit.damage_flags
	var twin: bool = cockpit.twin_engines
	for row in DAMAGE_ROWS + (DAMAGE_ROWS_TWIN if twin else []):
		var nogo := false
		for f in row[3]:
			nogo = nogo or (f < flags.size() and flags[f])
		var state := "NOGO" if nogo else "GO"
		var fmt: String = row[0]
		_text(Vector2(row[1], row[2]), fmt % [("L" if twin else ""), state] if fmt.count("%s") == 2 else fmt % state)


## ADI page (9) for cockpits with [HORIZON] OnMfd (FUN_00526fe0 mode 4): the panel's horizon disc
## (cockpit.draw_horizon_disc) centred at (65,74), then in white, right-aligned on the baseline: the speed "%03d"
## at (31,27) (S+0x33c, the indicated airspeed), the heading "%03d"
## at (74,12) and the height above the ground "%05d" at (124,27) (S+0x3c).
func _draw_adi() -> void:
	_tile(TILE_BLANK)
	cockpit.draw_horizon_disc(self, Vector2(65, 74), 1.0)
	var st: Dictionary = cockpit.state
	var hdg := int(st.heading) % 360
	for t in [[31, 27, "%03d" % int(st.ias_kt)], [74, 12, "%03d" % (hdg + 360 if hdg < 0 else hdg)],
			[124, 27, "%05d" % int(st.get("agl_ft", 0.0))]]:
		var font: Font = cockpit.digits_font()
		draw_string(font, Vector2(t[0] - font.get_string_size(t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, t[1]), t[2],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## TSD page (FUN_00531a50): heading-up, ownship at (65,85), 1 px = 112·scale m.
func _draw_tsd() -> void:
	_tile(TILE_TSD)
	var st: Dictionary = cockpit.state
	var own: Vector2 = st.get("world", Vector2.ZERO)
	var hdg := deg_to_rad(st.heading)
	var S := sin(hdg)
	var C := cos(hdg)
	var k := 112.0 * tsd_scale
	var to_mfd := func(w: Vector2) -> Vector2:
		var ex := w.x - own.x
		var ny := w.y - own.y
		return Vector2(65 + (ex * C - ny * S) / k, 85 - (ex * S + ny * C) / k)
	var clip := PackedVector2Array([Vector2(10, 10), Vector2(122, 10), Vector2(122, 122), Vector2(10, 122)])
	if tsd_options[2]:
		for poly in cockpit.tsd_map:
			var pts := PackedVector2Array()
			for w in poly.points:
				pts.append(to_mfd.call(w))
			for piece in Geometry2D.intersect_polygons(pts, clip):
				# Skip slivers the clipper leaves (they don't triangulate).
				if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
					draw_colored_polygon(piece, poly.color)
	# Fixed symbology: range circle r=22, ownship, outer ring r=44 with SCL.
	draw_arc(Vector2(65, 85), 22, 0, TAU, 48, GREEN, 1.0)
	if tsd_options[3]:
		draw_arc(Vector2(65, 85), 44, 0, TAU, 64, GREEN, 1.0)
	_line(Vector2(60, 81), Vector2(71, 81))
	_line(Vector2(65, 78), Vector2(65, 91))
	_line(Vector2(63, 91), Vector2(68, 91))
	# Compass letters S, E, N, W on radius 18, rotating with the heading.
	for i in 4:
		var bearing := deg_to_rad([180.0, 90.0, 0.0, 270.0][i]) - hdg
		var p := Vector2(65, 85) + Vector2(sin(bearing), -cos(bearing)) * 18
		_blit(Rect2(132 + 6 * i, 855, 6, 7), p - Vector2(3, 3))
	# Waypoints: route polyline, current one filled.
	if tsd_options[1]:
		var wps: Array = cockpit.waypoints
		var prev = null
		for i in wps.size():
			var p: Vector2 = to_mfd.call(wps[i].world)
			if prev != null:
				for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([prev, p]), clip):
					draw_polyline(seg, GREEN, 1.0)
			prev = p
			if Rect2(10, 10, 112, 112).has_point(p):
				var box := Rect2(p - Vector2(2, 2), Vector2(5, 5))
				if i == cockpit.current_waypoint:
					draw_rect(box, Color8(0, 255, 0))
				else:
					draw_rect(box, Color8(0, 128, 0), false, 1.0)
	# Option highlight boxes (right OSBs 0x10..0x13).
	for i in 4:
		if tsd_options[i]:
			draw_rect(Rect2(111, 20 + 20 * i, 17, 9), GREEN, false, 1.0)
	_blit(Rect2(132 + 8 * TSD_SCALES.find(tsd_scale), 845, 8, 5), Vector2(1, 33))


# --- bezel buttons (FUN_00520db0 hit test, FUN_005219e0 actions) ---------------------------------

## OSB id under an MFD-local point: top 1-5, bottom 6-10, left 11-15, right 16-20; -1 = none.
static func osb_at(p: Vector2) -> int:
	var along := -1.0
	var base := 0
	if p.y >= -16 and p.y < 0 and p.x >= 22 and p.x < 108:
		along = p.x
		base = 0
	elif p.y >= 131 and p.y < 147 and p.x >= 22 and p.x < 108:
		along = p.x
		base = 5
	elif p.x >= -16 and p.x < 0 and p.y >= 21 and p.y < 108:
		along = p.y
		base = 10
	elif p.x >= 132 and p.x < 149 and p.y >= 21 and p.y < 108:
		along = p.y
		base = 15
	if along < 0 or int(along) % 20 >= 8:
		return -1
	var n := int(along) / 20
	return base + n if n >= 1 and n <= 5 else -1


## A portal of a panoramic display is a touchscreen (ours, the F-35I's): the option labels drawn along the page's
## edges are pressed themselves. The OSB whose label is under a page point (the 14 px band along each edge, OSB n
## centred 20 n + 4 px along it, as osb_at's buttons); -1 = none.
## The touch zone of OSB `osb` on a portal's page (MFD px), the box drawn around a hovered label.
static func touch_rect(osb: int) -> Rect2:
	var n := (osb - 1) % 5 + 1
	var c := 20.0 * n + 4.0
	match (osb - 1) / 5:
		0:
			return Rect2(c - 10, 0, 20, 14)
		1:
			return Rect2(c - 10, SIZE - 14, 20, 14)
		2:
			return Rect2(0, c - 9, 16, 18)
		_:
			return Rect2(SIZE - 16, c - 9, 16, 18)


static func touch_osb(p: Vector2) -> int:
	if not Rect2(0, 0, SIZE, SIZE).has_point(p):
		return -1
	var along := -1.0
	var base := 0
	if p.y < 14:
		along = p.x
	elif p.y >= SIZE - 14:
		along = p.x
		base = 5
	elif p.x < 16:
		along = p.y
		base = 10
	elif p.x >= SIZE - 16:
		along = p.y
		base = 15
	if along < 0:
		return -1
	var n := int(round((along - 4.0) / 20.0))
	return base + n if n >= 1 and n <= 5 else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var q: Vector2 = event.position / _s() - Vector2.ONE * _bezel()
		mouse = q if Rect2(10, 10, 112, 112).has_point(q) else null
		if _bezel() == 0.0:
			hover_osb = touch_osb(q)
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position / _s() - Vector2.ONE * _bezel()
	# A portal: its labels (its bezel zones would lie over the neighbouring portals' pages).
	var osb := touch_osb(p) if cockpit.layout.get("MFD", {}).has("Portals") else osb_at(p)
	if osb > 0:
		press(osb)
		accept_event()
	elif page == HARM and Rect2(10, 10, 112, 112).has_point(p):
		# FUN_005358b0 pass 3: a click in an emitter's ±4 px box sends event 0x37(id).
		for e in harm_symbols(cockpit.harm):
			if Rect2(e.pos - Vector2(4, 4), Vector2(8, 8)).has_point(p):
				_mfd_event(0x37, e.key)
				break
		accept_event()
	elif page == RADAR and Rect2(10, 10, 112, 112).has_point(p):
		match int(cockpit.radar.get("mode", 0)):
			4: _click_blip(p)
			7: _click_gmt(p)
			8: _click_map(p)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		mouse = null
		hover_osb = -1


## LRS (FUN_00534840): a click on a blip sends event 0x2a (lock that contact). Ours: within 4 px.
func _click_blip(p: Vector2) -> void:
	var r: Dictionary = cockpit.radar
	var nm: float = RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1]
	for c in r.get("contacts", []):
		var b := Vector2(66.0 + (float(c.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
				115.0 - float(c.dist) / (nm * 16.5446))
		if b.distance_to(p) <= 4.0 and cockpit.on_radar_event.is_valid():
			cockpit.on_radar_event.call(0x2a, c.key)
			accept_event()
			return


## OSB actions.
func press(osb: int) -> void:
	if osb == 6:
		page = MENU
		return
	match page:
		MENU:
			var h: Dictionary = cockpit.layout.get("HORIZON", {})
			var rwr_panel := int(cockpit.layout.get("PANELRWR", {}).get("Active", 0)) == 1
			match osb:
				0xb: if _flir_menu() and cockpit.on_flir.is_valid(): cockpit.on_flir.call(self)
				0xd: page = STORES
				0xe: if not rwr_panel: page = RWR
				0xf: page = RADAR
				0x11: page = NAV
				0x12: page = DAMAGE
				0x13: page = TSD
				0x14: if int(h.get("OnMfd", 0)) == 1: page = ADI
		RADAR:
			match osb:
				0xb: step_range(1)
				0xc: step_range(-1)
				1: cycle_radar_mode()
				3: if int(cockpit.radar.get("mode", 0)) == 8: _radar_event(0x30)  # MAP: NORM <-> EXP
		TSD:
			match osb:
				0xb: tsd_scale = TSD_SCALES[mini(TSD_SCALES.find(tsd_scale) + 1, TSD_SCALES.size() - 1)]
				0xc: tsd_scale = TSD_SCALES[maxi(TSD_SCALES.find(tsd_scale) - 1, 0)]
				0x10, 0x11, 0x12, 0x13: tsd_options[osb - 0x10] = not tsd_options[osb - 0x10]
		STORES:
			var i := STORES_OSB.find(osb)
			if i >= 0 and cockpit.on_station_select.is_valid():
				cockpit.on_station_select.call(i)
			# OSBs 0xe / 0xf quantity +1 / −1 (event 0x4a), 0x13 / 0x14 interval +10 / −10 (0x4b).
			var rip := {0xe: [0x4a, true], 0xf: [0x4a, false], 0x13: [0x4b, true], 0x14: [0x4b, false]}
			if rip.has(osb) and cockpit.on_ripple_event.is_valid():
				cockpit.on_ripple_event.call(rip[osb][0], rip[osb][1])
		TV, FLIR:
			# FUN_005219e0 cases 5 / 6: 0xb zoom in (0x14), 0xc out (0x15); FLIR: top 5 WIDE / SPOT (0x20),
			# top 3 laser (0x6a).
			match osb:
				0xb: _mfd_event(0x14)
				0xc: _mfd_event(0x15)
				5: if page == FLIR: _mfd_event(0x20)
				3: if page == FLIR: _mfd_event(0x6a)
		NAV:
			match osb:
				0xb: nav_scroll = maxi(nav_scroll - 1, 0)
				0xf: nav_scroll = mini(nav_scroll + 1, maxi(0, cockpit.waypoints.size() - 3))


func _mfd_event(ev: int, arg = null) -> void:
	if cockpit.on_mfd_event.is_valid():
		cockpit.on_mfd_event.call(ev, arg)


## Radar OSBs (0xb range +, 0xc range −, top 1 Q) and keys go to the radar (docs/radar.md).
func step_range(d: int) -> void:
	if cockpit.on_radar_event.is_valid():
		cockpit.on_radar_event.call(0x21 if d > 0 else 0x22)


func cycle_radar_mode() -> void:
	if cockpit.on_radar_event.is_valid():
		cockpit.on_radar_event.call(0x24)
