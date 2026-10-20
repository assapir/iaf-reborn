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
## TSD action-5 waypoint pens (COLORREF 0x2400ff / 0x360080).
const TSD_RED := Color8(255, 0, 36)
const TSD_PURPLE := Color8(128, 0, 54)

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
var _nav_cur := -1  # the current waypoint the scroll last followed
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
## Ours, "Better cockpit" crisp_mfd: the same pages drawn at the screen's resolution (the drawing primitives below):
## strokes antialiased over the pixels the original's GDI lights, the pixel art through mfd_crisp.gdshader.
var crisp := false
## Canvas px per MFD px: 1 in Original (the canvas is scaled by _s()), _s() when crisp (the canvas at screen px).
var _k := 1.0
## Tests: an Array makes every primitive append [op, its MFD-px arguments…] (the pages' geometry, the same in both
## modes).
var trace = null
## The EO / MAP pictures, under the page's art (show_behind_parent): pictures, drawn as they are in both modes.
var _under: Control
const PORTAL_SHADER := preload("res://cockpit/portal.gdshader")
static var _crisp_material: ShaderMaterial
## The original bitmaps (install resource/cockpits/<file>) and the crisp sprites cut from them, by "file rect".
static var _art := {}
static var _sprites := {}


func setup(c: Control, idx: int, start_page: int) -> void:
	cockpit = c
	index = idx
	page = start_page
	mouse_filter = Control.MOUSE_FILTER_STOP
	_under = Control.new()
	_under.show_behind_parent = true
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.draw.connect(_draw_pictures)
	add_child(_under)


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
	_under.size = size
	var want := Settings.better_cockpit_on("crisp_mfd")
	if want != crisp:
		_set_crisp(want)
	# FUN_005296d0 after every page: a new current waypoint (clamped 0..count) scrolls the NAV list to keep it in its
	# 3 rows (above: it becomes the top row; below: the bottom row). UNCERTAIN: the trigger field (renderer +0x930),
	# taken as the last current waypoint, so the OSB scroll stays free in between.
	var cur := clampi(cockpit.current_waypoint, 0, cockpit.waypoints.size())
	if cur != _nav_cur:
		_nav_cur = cur
		if cur < nav_scroll:
			nav_scroll = cur
		elif cur >= nav_scroll + 3:
			nav_scroll = maxi(cur - 2, 0)
	queue_redraw()
	_under.queue_redraw()


func _set_crisp(on: bool) -> void:
	crisp = on
	if material is ShaderMaterial and material.shader == PORTAL_SHADER:
		material.set_shader_parameter("crisp", on)
		return
	if on and _crisp_material == null:
		_crisp_material = ShaderMaterial.new()
		_crisp_material.shader = preload("res://cockpit/mfd_crisp.gdshader")
	material = _crisp_material if on else null


# --- drawing primitives (MFD pixels) ----------------------------------------------------------
# Every page draws through these, in MFD px. Original: the canvas is scaled by _s() and draws the 1998 look. Crisp:
# the canvas is at screen px (_k = _s()); a GDI stroke (pixels x..x+1 lit) is a 1-px-wide line through the pixel
# centres, the art comes from the original bitmap through mfd_crisp.gdshader.


## Records one primitive for a test.
func _rec(op: Array) -> void:
	if trace != null:
		trace.append(op)


## A GDI MoveTo / LineTo: the pixels from a up to b (b's own pixel not lit).
func _seg(a: Vector2, b: Vector2, color: Color) -> void:
	_rec(["line", a, b, color])
	_stroke(a, b, color)


func _stroke(a: Vector2, b: Vector2, color: Color) -> void:
	if not crisp:
		draw_line(a, b, color, 1.0)
		return
	var d := b - a
	var st := d / maxf(absf(d.x), absf(d.y)) if d != Vector2.ZERO else Vector2.ZERO
	var o := Vector2(0.5, 0.5) - 0.5 * st
	draw_line((a + o) * _k, (b + o) * _k, color, _k, true)


## A 1-px outline of `r` (its edge rows / columns lit).
func _frame(r: Rect2, color := GREEN) -> void:
	_rec(["frame", r, color])
	if not crisp:
		draw_rect(r, color, false, 1.0)
		return
	draw_rect(Rect2((r.position + Vector2(0.5, 0.5)) * _k, r.size * _k), color, false, _k, true)


func _fill(r: Rect2, color: Color) -> void:
	_rec(["fill", r, color])
	draw_rect(Rect2(r.position * _k, r.size * _k), color)


## A filled disc about pixel c.
func _disc(c: Vector2, r: float, color := GREEN) -> void:
	_rec(["disc", c, r, color])
	if not crisp:
		draw_circle(c, r, color)
		return
	draw_circle((c + Vector2(0.5, 0.5)) * _k, r * _k, color, true, -1.0, true)


## A 1-px circle about pixel c.
func _circle(c: Vector2, r: float, color := GREEN) -> void:
	_rec(["circle", c, r, color])
	if not crisp:
		draw_arc(c, r, 0, TAU, 48, color, 1.0)
		return
	draw_arc((c + Vector2(0.5, 0.5)) * _k, r * _k, 0, TAU, 96, color, _k, true)


## A GDI Polyline (crisp: each leg a LineTo).
func _polyline(pts: PackedVector2Array, color := GREEN) -> void:
	_rec(["polyline", pts, color])
	if not crisp:
		draw_polyline(pts, color, 1.0)
		return
	for i in pts.size() - 1:
		_stroke(pts[i], pts[i + 1], color)


func _polygon(pts: PackedVector2Array, color: Color) -> void:
	_rec(["polygon", pts, color])
	if crisp:
		pts = Transform2D.IDENTITY.scaled(Vector2(_k, _k)) * pts
	draw_colored_polygon(pts, color)


func _atlas() -> Texture2D:
	return cockpit.tex.get("MFDS")


## A sprite of mfds.bmp at `dest` (its top-left pixel).
func _blit(src: Rect2, dest: Vector2) -> void:
	_rec(["blit", src, dest])
	if crisp:
		var ct := crisp_sprite("mfds.bmp", src)
		if ct != null:
			draw_texture_rect(ct, Rect2((dest - Vector2.ONE) * _k, (src.size + Vector2(2, 2)) * _k), false)
			return
	var t := _atlas()
	if t == null:
		return
	var a: float = cockpit.layout.get("image_scale", 1)
	draw_texture_rect_region(t, Rect2(dest * _k, src.size * _k), Rect2(src.position * a, src.size * a))


## A crisp sprite: `src` of the original bitmap with a clear 1-px border (the shader's strokes end round inside it),
## null without the bitmap.
static func crisp_sprite(file: String, src: Rect2) -> Texture2D:
	var key := "%s %s" % [file, src]
	if _sprites.has(key):
		return _sprites[key]
	if not _art.has(file):
		var img := Image.new()
		var path: String = Settings.assets_dir().path_join("install/resource/cockpits").path_join(file)
		var ok := FileAccess.file_exists(path) and img.load_bmp_from_buffer(FileAccess.get_file_as_bytes(path)) == OK
		if ok:
			img.convert(Image.FORMAT_RGBA8)
		_art[file] = img if ok else null
	var art: Image = _art[file]
	var t: Texture2D = null
	if art != null:
		var r := Rect2i(src)
		var out := Image.create_empty(r.size.x + 2, r.size.y + 2, false, Image.FORMAT_RGBA8)
		out.blit_rect(art, r, Vector2i.ONE)
		t = ImageTexture.create_from_image(out)
	_sprites[key] = t
	return t


## An rwrsymb.bmp symbol for cockpit.draw_rwr_symbols (canvas px).
func _rwr_symbol(src: Rect2, dest: Rect2, mod: Color) -> void:
	var t := crisp_sprite("rwrsymb.bmp", src)
	if t != null:
		draw_texture_rect(t, dest.grow(dest.size.x / src.size.x), false, mod)


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
		".":
			return 185
		":":
			return 190
		"+":
			return 195
		"-":
			return 200
		"%":
			return 205
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
		_seg(a, b, color)
		return
	if a.is_equal_approx(b):
		return
	var c := _clip
	var poly := PackedVector2Array([c.position, Vector2(c.end.x, c.position.y), c.end, Vector2(c.position.x, c.end.y)])
	for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly):
		if seg.size() >= 2:
			_polyline(seg, color)


# --- pages ------------------------------------------------------------------------------------


func _draw() -> void:
	if cockpit == null or cockpit.layout.is_empty():
		return
	var s := _s()
	_k = s if crisp else 1.0
	draw_set_transform(Vector2.ONE * _bezel() * s, 0.0, Vector2.ONE * s / _k)
	# A portal's hovered label: the touch box (ours; the originals' buttons are in their panel art).
	if _bezel() == 0.0 and hover_osb > 0:
		_frame(touch_rect(hover_osb), DIM_GREEN)
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
		7:
			_tile(TILE_GMT)
		8:
			_tile(TILE_MAP)  # over the picture (_draw_pictures)
		_:
			_tile(TILE_RADAR_AA)
			_text(Vector2(17, 3), RADAR_MODES[mode])
	# FUN_005296d0 case 2: STT (it jumps to the BORE path) and every mode after it call FUN_00533990.
	if mode >= 2:
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
	# STT (FUN_00534160) draws no antenna carets: its carets follow the target.
	if mode != 2:
		_draw_carets(r.get("antenna", Vector2.ZERO))
	var target = null  # STT: the first locked contact; TWS: the selected one; in the window: its point
	var hover = null  # TWS: the contact under the mouse (±4 px)
	for c in r.get("contacts", []):
		if mode == 2 and (not c.locked or target != null):
			continue
		# B-scope: x = 66 + (az + shift)·112 / width, y = 115 − range / (R·16.5446) (R NM = 112 px).
		var p := Vector2(
			66.0 + (float(c.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
			115.0 - float(c.dist) / (nm * 16.5446)
		)
		if p.x <= 8 or p.x >= 124 or p.y <= 8 or p.y >= 124:
			continue
		p = p.round()
		match mode:
			3, 6:
				# FUN_005352c0: the 3×3 box with the \ diagonal.
				_box(p, 1)
				_line(p + Vector2(-1, -1), p + Vector2(1, 1))
			4:
				# FUN_00534840: the 5×5 box, the inner 3×3 with the \ diagonal.
				_box(p, 2)
				_box(p, 1)
				_line(p + Vector2(-1, -1), p + Vector2(1, 1))
			5:
				# FUN_00534b20: the selected contact's disc, the others' 5×5 box; every one its aspect stub.
				if c.selected:
					_disc(p, 3.5)
					target = p
				else:
					_box(p, 2)
				_aspect_stub(p, c)
				if mouse != null and Rect2(p - Vector2(4, 4), Vector2(8, 8)).has_point(mouse):
					hover = c
			2:
				_disc(p, 3.5)
				_aspect_stub(p, c)
				target = p
				hover = c
	# LRS / TWS: the cursor marker, two bars at the mouse x ± 4, y − 5..y + 5.
	if mode in [4, 5] and mouse != null:
		var m: Vector2 = Vector2(mouse).floor()
		for dx in [-4, 4]:
			_line(m + Vector2(dx, -5), m + Vector2(dx, 5))
	_draw_steer_bscope(nm)
	if target != null and mode == 2:
		_draw_carets_at(target)
	# STT and the selected TWS contact (FUN_00533db0): the range scale, the caret, the DLZ, the speed / aspect /
	# closure text.
	if target != null and not r.get("lock", {}).is_empty():
		_draw_stt_scale(r, nm)
		_draw_stt_text(r, nm)
	# Pass 3: the altitude "%02d" (+0x648, kft) right-aligned at (x + 15, y − 3) and the Mach × 10 (+0x67c) at
	# (x − 3, y − 3): beside the STT target (FUN_00534160); in TWS by the mouse over a contact (x = mouse + 2,
	# FUN_00534b20); each only while its anchor (x + 10 / x − 8) is inside the window.
	if hover != null:
		var a: Vector2 = target if mode == 2 else Vector2(mouse).floor() + Vector2(2, 0)
		if a.x + 10 > 8 and a.x + 10 < 124:
			_text_right(a.x + 15, a.y - 3, "%02d" % int(float(hover.get("alt", 0.0)) * 0.0032808398))
		if a.x - 8 > 8 and a.x - 8 < 124:
			_text_right(a.x - 3, a.y - 3, "%02d" % int(float(hover.get("mach", 0.0)) * 10.0))


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
	_caret_pair(clampi(int(a.x * 106.0), 0, 106), clampi(int(a.y * 106.0), 0, 106))


## The STT carets at the target (FUN_00534160): v = clamp(t − 13, 0, 106) per axis, the antenna carets' shapes.
func _draw_carets_at(t: Vector2) -> void:
	_caret_pair(clampi(int(t.x) - 13, 0, 106), clampi(int(t.y) - 13, 0, 106))


func _caret_pair(vx: int, vy: int) -> void:
	_line(Vector2(13 + vx, 117), Vector2(13 + vx, 120))
	_line(Vector2(11 + vx, 117), Vector2(16 + vx, 117))
	_line(Vector2(11, 13 + vy), Vector2(14, 13 + vy))
	_line(Vector2(14, 11 + vy), Vector2(14, 16 + vy))


func _box(p: Vector2, h: int) -> void:
	_frame(Rect2(p - Vector2(h, h), Vector2(2 * h, 2 * h)))


## The aspect stub (FUN_00534b20 / FUN_00534160): bin = aspect_bin(the record's aspect, +0x66c), drawn from 2 px out
## to 6 px: 0 up, 2 right, ±4 down, −2 left, the odd bins the diagonals.
const ASPECT_DIRS := {
	0: Vector2(0, -1),
	1: Vector2(1, -1),
	2: Vector2(1, 0),
	3: Vector2(1, 1),
	4: Vector2(0, 1),
	-4: Vector2(0, 1),
	-3: Vector2(-1, 1),
	-2: Vector2(-1, 0),
	-1: Vector2(-1, -1)
}


func _aspect_stub(p: Vector2, c: Dictionary) -> void:
	var d: Vector2 = ASPECT_DIRS[aspect_bin(float(c.aspect))]
	_line(p + d * 2, p + d * 6)


## The stub's bin: ⌊aspect°⌋ % 360 (truncated), wrapped at ±210, / 45 truncated: −4..4.
static func aspect_bin(aspect: float) -> int:
	var a := int(rad_to_deg(aspect)) % 360
	if a > 210:
		a -= 360
	elif a < -210:
		a += 360
	return a / 45


## The range scale's caret row (FUN_00533db0 pass 4): n = 105 − ⌊r·112/(R·1853)⌋; the caret and the closure show
## only while 0 < n < 112.
static func stt_caret_n(dist: float, nm: float) -> int:
	return 105 - int(dist * 112.0 / (nm * 1853.0))


## STT text (FUN_00533db0 pass 3, right-aligned, FUN_00525920): "%3dK" target speed (at least 0) ending at x 86,
## aspect "%2dL" / "%2dR" ending at x 62 (y 3), the closure "%3dK" ending at x 111 at y = n + 8 (the caret's row − 2).
func _draw_stt_text(r: Dictionary, nm: float) -> void:
	var lk: Dictionary = r.lock
	_text_right(86, 3, "%3dK" % maxi(int(lk.speed), 0))
	_text_right(62, 3, aspect_text(float(lk.aspect)))
	var n := stt_caret_n(float(lk.dist), nm)
	if n > 0 and n < 112:
		_text_right(111, n + 8, "%3dK" % int(float(r.get("closure", 0.0)) * 1.9427955))


## The range scale (FUN_00533db0 pass 4): the line at x 121 (y 10..122), three black ticks (pen +0x5a0) at
## y 39 / 65 / 91 (x 117..121), the selected store's DLZ (S+0x350 min, S+0x348 max, FUN_00456520) as ticks
## x 121..117 at y = 122 − ⌊v·112/(R·1853)⌋ while 0 < 112 − ⌊v·k⌋ < 112, and the ">" caret: its tip at (116, 10 + n),
## its arms to (113, 10 + n ± 3).
func _draw_stt_scale(r: Dictionary, nm: float) -> void:
	for ty in [39, 65, 91]:
		_line(Vector2(117, ty), Vector2(121, ty), Color.BLACK)
	_line(Vector2(121, 10), Vector2(121, 122))
	var dlz: Array = r.get("dlz", [])
	if dlz.size() == 2:
		var k := 112.0 / (nm * 1853.0)
		for v in [dlz[1], dlz[0]]:
			var n := 112 - int(float(v) * k)
			if n > 0 and n < 112:
				_line(Vector2(121, 10 + n), Vector2(117, 10 + n))
	var c := stt_caret_n(float(r.lock.dist), nm)
	if c > 0 and c < 112:
		_line(Vector2(116, 10 + c), Vector2(113, 7 + c))
		_line(Vector2(116, 10 + c), Vector2(113, 13 + c))


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
	var sin_h := sin(hdg)
	var cos_h := cos(hdg)
	return Vector2(e.x * cos_h - e.y * sin_h, -(e.x * sin_h + e.y * cos_h)) / k


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
	return Vector2(
		(w.x + 166828.0 - f.left) / (f.right - f.left) * ISR_SIZE.x,
		(f.top - (w.y + 21164.0)) / (f.top - f.bottom) * ISR_SIZE.y
	)


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
	return {
		"centre": st.get("world", Vector2.ZERO),
		"hdg": deg_to_rad(st.heading),
		"img": Vector2(65, 109),
		"sym": Vector2(66, 109)
	}


## The MAP picture (FUN_0053b0a0, pass 1, before the tile): isr.bmp's green channel (loaded with the
## green palette, FUN_0053ae00(…, 1)) turned heading-up about the centre, S = R·1853·832 / ((top −
## bottom)·94) isr px per MFD px; black outside the image. It shows through the tile's cyan fan.
func _draw_map_picture(r: Dictionary, nm: float) -> void:
	_under.draw_rect(MAP_WINDOW, Color.BLACK)
	var t := _isr()
	if t == null:
		return
	var f := _map_frame(r)
	for piece in map_picture(f.centre, f.hdg, nm, f.img):
		_under.draw_colored_polygon(piece.points, Color(0, 1, 0), piece.uvs, t)


## The MAP picture's polygons in the window: [{points (MFD px), uvs (0..1 of isr.bmp)}] for the centre
## (world X / Y) shown at MFD px `img`, heading-up for `hdg` (rad), range `nm`. isr px q of MFD px p:
## q = q0 + S·(dx·C − dy·S', dx·S' + dy·C), (dx, dy) = p − img.
static func map_picture(centre: Vector2, hdg: float, nm: float, img: Vector2) -> Array:
	var s: float = nm * 1853.0 * ISR_SIZE.y / ((MAPFRAME.top - MAPFRAME.bottom) * 94.0)
	var cos_h := cos(hdg)
	var sin_h := sin(hdg)
	var q0 := isr_px(centre)
	var corners := PackedVector2Array()
	for q in [Vector2.ZERO, Vector2(ISR_SIZE.x, 0), ISR_SIZE, Vector2(0, ISR_SIZE.y)]:
		var d: Vector2 = (q - q0) / s
		corners.append(img + Vector2(d.x * cos_h + d.y * sin_h, -d.x * sin_h + d.y * cos_h))
	var win := PackedVector2Array(
		[
			MAP_WINDOW.position,
			Vector2(MAP_WINDOW.end.x, MAP_WINDOW.position.y),
			MAP_WINDOW.end,
			Vector2(MAP_WINDOW.position.x, MAP_WINDOW.end.y)
		]
	)
	var out := []
	for piece in Geometry2D.intersect_polygons(corners, win):
		if piece.size() < 3:
			continue
		var uvs := PackedVector2Array()
		for p in piece:
			var d: Vector2 = p - img
			uvs.append((q0 + s * Vector2(d.x * cos_h - d.y * sin_h, d.x * sin_h + d.y * cos_h)) / ISR_SIZE)
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
		var cp := (
			(Vector2(66, 109) + _heading_up(Vector2(w.x, w.y) - own, deg_to_rad(st.heading), nm * 1853.0 / 56.0))
			. floor()
		)
		if not c.locked and absf(p.x - cp.x) < 4 and absf(p.y - cp.y) < 4:
			_radar_event(0x2a, c.key)
			return


func _radar_event(ev: int, arg = null) -> void:
	if cockpit.on_radar_event.is_valid():
		cockpit.on_radar_event.call(ev, arg)


## The pictures under the page's art (the _under canvas, MFD px): the radar MAP's (FUN_0053b0a0 pass 1) and the EO
## picture (viewport 1 into the video rect (10,10)–(122,122)); they show through the tile's cyan.
func _draw_pictures() -> void:
	if cockpit == null or cockpit.layout.is_empty():
		return
	var s := _s()
	_under.draw_set_transform(Vector2.ONE * _bezel() * s, 0.0, Vector2(s, s))
	var r: Dictionary = cockpit.radar
	if page == RADAR and int(r.get("mode", 0)) == 8:
		_draw_map_picture(r, RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1])
	elif page == FLIR or (page == TV and int(cockpit.eo.get("tv", {}).get("status", 0)) != 0):
		if cockpit.eo_texture != null and cockpit.eo.get("camera", false):
			_under.draw_texture_rect(cockpit.eo_texture, Rect2(10, 10, 112, 112), false)


## FLIR page (FUN_00536c10): the picture, the tile (0,660), zoom "%1d" right-aligned at (11,33), WIDE / SPOT
## right-aligned at (114,3), LASER OFF / ON at (42,3), the range NM right-aligned at (98,124), the gimbal blob
## at (66 − 56u, 66 + 56v).
func _draw_flir() -> void:
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
	_polyline(
		PackedVector2Array(
			[
				Vector2(x - 1, y - 2),
				Vector2(x + 1, y - 2),
				Vector2(x + 2, y - 1),
				Vector2(x - 2, y - 1),
				Vector2(x - 2, y),
				Vector2(x + 2, y),
				Vector2(x + 2, y + 1),
				Vector2(x - 2, y + 1),
				Vector2(x - 1, y + 2),
				Vector2(x + 2, y + 2)
			]
		)
	)


## TV page (FUN_005369e0): with a source (status ≠ 0) the picture, the tile (0,792), zoom "%1d" (11,33) and the
## seeker ticks (x = 66 − 56u, y 64..69; y = 66 + 56v, x 63..69), else the blank tile; the status right-aligned at
## (114,3); with a source the TV weapon's time left "%3d" right-aligned at (111,110) (FUN_004d6ac0).
const TV_STATUS := ["NO SOURCE", "RDY", "TRA", "TER"]


func _draw_tv() -> void:
	var tv: Dictionary = cockpit.eo.get("tv", {})
	var st := int(tv.get("status", 0))
	if st != 0:
		_tile(TILE_TV)
		_text_right(11, 33, "%d" % int(tv.zoom))
		var x := int(66.0 - 56.0 * float(tv.u))
		var y := int(66.0 + 56.0 * float(tv.v))
		_line(Vector2(x, 64), Vector2(x, 69))
		_line(Vector2(63, y), Vector2(69, y))
		_text_right(111, 110, "%3d" % int(cockpit.eo.get("tv_time", 0)))
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
			_frame(Rect2(e.pos - Vector2(4, 4), Vector2(8, 8)))
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
		_rec(["rwr", cockpit.rwr.size()])
		cockpit.draw_rwr_symbols(self, Vector2(66, 66) * _k, 56.0, _k, _rwr_symbol if crisp else Callable())


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
	_fill(Rect2(14, 124, 19, 5), Color.BLACK)
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
	# The scroll arrows (the diamond's halves) by OSBs 0xb / 0xf.
	_blit(Rect2(164, 792, 8, 4), Vector2(1, 22))
	_blit(Rect2(164, 796, 8, 4), Vector2(1, 107))
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
		_text(Vector2(77, y + 1), " %2dM" % int(d.length() / 1853.0))  # "% 3dM": the space flag
		_text(Vector2(102, y + 1), "%03d" % (b + 360 if b < 0 else b))
		if i == cur:
			_polyline(
				PackedVector2Array(
					[Vector2(8, y - 2), Vector2(8, y + 6), Vector2(1, y + 6), Vector2(1, y - 2), Vector2(8, y - 2)]
				)
			)
	_text(Vector2(72, 124), "ETA   :")
	# "%02d %02d" hours, minutes of the ETA (a time of day; not wrapped at 24 h, as the original), right-aligned at 117.
	if not wps.is_empty():
		var eta: float = preload("res://cockpit/hud.gd").nav_cues(cockpit.state, wps, cur).eta
		var h := int(eta / 3600.0)
		_text_right(117, 124, "%02d %02d" % [h, int((eta - 3600.0 * h) / 60.0)])


## Stores page (FUN_0052c740, docs/mfd.md): per pylon station 0..8 the count and name positions
## (stations 6..8 right-aligned to x 128), the MRM / SRM totals, the gun rounds, the fuel and the
## selected station's box. OSBs 0xd, 0xc, 0xb, 1, 3, 5, 0x10, 0x11, 0x12 select stations 0..8.
const STORES_POS := [
	[4, 62, 4, 72],
	[4, 42, 4, 52],
	[4, 22, 4, 32],
	[24, 3, 17, 12],
	[64, 3, 57, 12],
	[104, 3, 97, 12],
	[128, 22, 128, 32],
	[128, 42, 128, 52],
	[128, 62, 128, 72]
]
const STORES_OSB := [0xd, 0xc, 0xb, 1, 3, 5, 0x10, 0x11, 0x12]


func _draw_stores() -> void:
	_tile(TILE_STORES)
	var wp: Dictionary = cockpit.weapons
	if not wp.is_empty():
		# Pass 0: every station, an empty one as "0" (the state copy zeroes its count and name).
		for i in 9:
			var st: Dictionary = wp.stations[i]
			var pos: Array = STORES_POS[i]
			var count := "%d" % int(st.count)
			var name := String(st.name)
			if i >= 6:
				_text_right(pos[0], pos[1], count)
				_text_right(pos[2], pos[3], name)
			else:
				_text(Vector2(pos[0], pos[1]), count)
				_text(Vector2(pos[2], pos[3]), name)
		# Pass 4: the selected station's box, whatever it holds: 15×8 at (2, 20·(3−i)) for 0..2, (40·i − 98, 1)
		# for 3..5, (114, 20·(i−5)) for 6..8; the gun (9) 36×10 at (48, 82).
		var sel := int(wp.selected)
		if sel >= 0 and sel < 10:
			var box := Rect2(48, 82, 36, 10)
			if sel < 3:
				box = Rect2(2, 20 * (3 - sel), 15, 8)
			elif sel < 6:
				box = Rect2(40 * sel - 98, 1, 15, 8)
			elif sel < 9:
				box = Rect2(114, 20 * (sel - 5), 15, 8)
			_frame(box)
		_text_right(59, 53, "%d" % int(wp.mrm))
		_text_right(59, 63, "%d" % int(wp.srm))
		_text(Vector2(68, 85), "%03d" % int(wp.gun))
		# The ripple quantity / interval (state +0x374 / +0x378).
		_text(Vector2(1, 94), "%dQnt" % int(wp.get("quantity", 2)))
		_text_right(131, 94, "int%d" % int(wp.get("interval", 10)))
		if int(wp.selected) == 9:
			_frame(Rect2(48, 82, 36, 10))
	_text(Vector2(55, 124), "Fuel : %5dLB" % int(cockpit.state.fuel_lbs))


## Damage page rows (FUN_0052bc00): format, x, y, the damage flags that make it NOGO (cockpit state
## +0x558 + 4n = the controller's damage flags, docs/damage.md §5). "ENG %s %s" / "AB %s %s" take
## "L" on twin-engine jets (else ""); the ENG R / AB R rows appear on twin-engine jets only.
const DAMAGE_ROWS := [
	["ENG %s %s", 12, 10, [22, 16, 2]],
	["AB %s %s", 72, 10, [8]],
	["INS  %s", 72, 34, [11]],
	["FUEL %s", 12, 43, [10]],
	["RDR  %s", 72, 43, [15]],
	["AILN %s", 12, 52, [18]],
	["RWR  %s", 72, 52, [14]],
	["FLTC %s", 12, 61, [24]],
	["WPNS %s", 72, 61, [20]],
	["FLAP %s", 12, 70, [4]],
	["GUN  %s", 72, 70, [13]],
	["GEAR %s", 12, 79, [7]],
	["ECM  %s", 72, 79, [1]],
	["HUD  %s", 12, 88, [12]],
	["A/P  %s", 72, 88, [6]],
	["BRAK %s", 12, 97, [5]],
	["ELCT %s", 72, 97, [19]],
	["GNRT %s", 72, 106, [21]],
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
		_text(Vector2(row[1], row[2]), fmt % ["L" if twin else "", state] if fmt.count("%s") == 2 else fmt % state)


## ADI page (9) for cockpits with [HORIZON] OnMfd (FUN_00526fe0 mode 4): the panel's horizon disc
## (cockpit.draw_horizon_disc) centred at (65,74), then in white, right-aligned on the baseline: the speed "%03d"
## at (31,27) (S+0x33c, the indicated airspeed), the heading "%03d"
## at (74,12) and the height above the ground "%05d" at (124,27) (S+0x3c).
func _draw_adi() -> void:
	_tile(TILE_BLANK)
	_rec(["horizon", Vector2(65, 74)])
	cockpit.draw_horizon_disc(self, Vector2(65, 74) * _k, _k, _k if crisp else 0.0)
	var st: Dictionary = cockpit.state
	var hdg := int(st.heading) % 360
	for t in [
		[31, 27, "%03d" % int(st.ias_kt)],
		[74, 12, "%03d" % (hdg + 360 if hdg < 0 else hdg)],
		[124, 27, "%05d" % int(st.get("agl_ft", 0.0))]
	]:
		var font: Font = cockpit.digits_font()
		var w := font.get_string_size(t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		# FUN_00526fe0 case 4: SetBkColor(0), OPAQUE: the digits on black.
		_fill(Rect2(t[0] - w, t[1] - font.get_ascent(11), w, font.get_height(11)), Color.BLACK)
		_rec(["string", Vector2(t[0] - w, t[1]), t[2]])
		# The bitmap font at its 11 px, the canvas scaled for it (crisp: the shader draws its glyphs sharp).
		draw_set_transform(Vector2.ONE * _bezel() * _s(), 0.0, Vector2.ONE * _s())
		draw_string(font, Vector2(t[0] - w, t[1]), t[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_set_transform(Vector2.ONE * _bezel() * _s(), 0.0, Vector2.ONE * _s() / _k)


## TSD page (FUN_00531a50): heading-up, ownship at (65,85), 1 px = scale·16.5446 m (112 px = scale NM: the route
## and the SAM sites @531d92 / @532216, constant 0x60c410).
func _draw_tsd() -> void:
	_tile(TILE_TSD)
	var st: Dictionary = cockpit.state
	var own: Vector2 = st.get("world", Vector2.ZERO)
	var hdg := deg_to_rad(st.heading)
	var sin_h := sin(hdg)
	var cos_h := cos(hdg)
	var k := tsd_scale * 1853.0 / 112.0
	var to_mfd := func(w: Vector2) -> Vector2:
		var ex := w.x - own.x
		var ny := w.y - own.y
		return Vector2(65 + (ex * cos_h - ny * sin_h) / k, 85 - (ex * sin_h + ny * cos_h) / k)
	var clip := PackedVector2Array([Vector2(10, 10), Vector2(122, 10), Vector2(122, 122), Vector2(10, 122)])
	if tsd_options[2]:
		for poly in cockpit.tsd_map:
			var pts := PackedVector2Array()
			for w in poly.points:
				pts.append(to_mfd.call(w))
			for piece in Geometry2D.intersect_polygons(pts, clip):
				# Skip slivers the clipper leaves (they don't triangulate).
				if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
					_polygon(piece, poly.color)
	# Fixed symbology: range circle r=22, ownship, outer ring r=44 with SCL.
	_circle(Vector2(65, 85), 22)
	_clip = Rect2(10, 10, 112, 112)  # the region (10,10)–(122,122)
	if tsd_options[3]:
		_ring(Vector2(65, 85), 44)
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
					_polyline(seg)
			prev = p
			if Rect2(10, 10, 112, 112).has_point(p):
				# The current one filled 5×5 green (pen +0x27a4), the others hollow dark green (+0x27a0); an action-5
				# (target) waypoint a red triangle when current (+0x27ac, 0x2400ff), else a purple filled 5×5
				# (+0x27a8, 0x360080).
				var box := Rect2(p.floor() - Vector2(2, 2), Vector2(5, 5))
				var act5 := int(wps[i].get("action", 0)) == 5
				if i == cockpit.current_waypoint and act5:
					# Rows (dy, x0, x1): the apex edge (x, y−2)–(x+4, y+2) and the fill lines y−1..y+2.
					var q := p.floor()
					_line(q + Vector2(0, -2), q + Vector2(4, 2), TSD_RED)
					for row in [[-1, -1, 1], [0, -2, 2], [1, -3, 3], [2, -3, 4]]:
						_line(q + Vector2(row[1], row[0]), q + Vector2(row[2], row[0]), TSD_RED)
				elif i == cockpit.current_waypoint or act5:
					_fill(box, TSD_PURPLE if act5 else GREEN)
				else:
					_frame(box, DIM_GREEN)
	# SAM sites (state+0x1148, ≤ 16, FUN_00446270 from the TSD table: class 8 units with their ring radius): the 3×3
	# box with the \ diagonal and the ring of radius ⌊r / k⌋ when > 0.
	if tsd_options[0]:
		for site in cockpit.sam_sites:
			var p: Vector2 = to_mfd.call(site.pos).floor()
			_ground_symbol(p, false, true)
			var rr := int(float(site.r) / k)
			if rr > 0:
				_ring(p, rr)
	_clip = Rect2(0, 0, SIZE, SIZE)
	# Option highlight boxes (right OSBs 0x10..0x13).
	for i in 4:
		if tsd_options[i]:
			_frame(Rect2(111, 20 + 20 * i, 17, 9))
	# Pass 3 with MAP on: the option labels again over the map, left-aligned at (113, 22 + 20i).
	if tsd_options[2]:
		for i in 4:
			_text(Vector2(113, 22 + 20 * i), ["sa", "wp", "ma", "sc"][i])
	# FUN_00533990: scale 10 / 20 / 40 / 80 NM → sprites 1..4 (the radar's 5 NM is sprite 0).
	_blit(Rect2(132 + 8 * RADAR_RANGES.find(tsd_scale), 845, 8, 5), Vector2(1, 33))


## A GDI Ellipse of radius r about c, clipped to _clip.
func _ring(c: Vector2, r: float) -> void:
	var n := 48
	for i in n:
		_line(c + Vector2.from_angle(TAU * i / n) * r, c + Vector2.from_angle(TAU * (i + 1) / n) * r)


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
		# GMT / MAP pass 4 and the TWS lock act on the double-click flag (+0x27e0, set by the WM_LBUTTONDBLCLK
		# handler FUN_004dc8a0 → FUN_00522120); LRS and the TWS select on the press (+0x27d8).
		match int(cockpit.radar.get("mode", 0)):
			4:
				_click_blip(p)
			5:
				_click_tws(p, event.double_click)
			7:
				if event.double_click:
					_click_gmt(p)
			8:
				if event.double_click:
					_click_map(p)
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
		var b := Vector2(
			66.0 + (float(c.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
			115.0 - float(c.dist) / (nm * 16.5446)
		)
		if b.distance_to(p) <= 4.0 and cockpit.on_radar_event.is_valid():
			cockpit.on_radar_event.call(0x2a, c.key)
			accept_event()
			return


## TWS (FUN_00534b20): a press on a contact (±4 px) other than the selected one sends event 0x32 (select it,
## FUN_004add20); a double-click sends 0x2a (lock it → STT).
func _click_tws(p: Vector2, double: bool) -> void:
	var r: Dictionary = cockpit.radar
	var nm: float = RADAR_RANGES[clampi(int(r.get("idx", 1)), 1, 6) - 1]
	for c in r.get("contacts", []):
		var b := (
			Vector2(
				66.0 + (float(c.az) + float(r.get("shift", 0.0))) * 112.0 / float(r.get("width", TAU / 3.0)),
				115.0 - float(c.dist) / (nm * 16.5446)
			)
			. round()
		)
		if Rect2(b - Vector2(4, 4), Vector2(8, 8)).has_point(p):
			if double:
				_radar_event(0x2a, c.key)
			elif not c.selected:
				_radar_event(0x32, c.key)
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
				0xb:
					if _flir_menu() and cockpit.on_flir.is_valid():
						cockpit.on_flir.call(self)
				0xd:
					page = STORES
				0xe:
					if not rwr_panel:
						page = RWR
				0xf:
					page = RADAR
				0x11:
					page = NAV
				0x12:
					page = DAMAGE
				0x13:
					page = TSD
				0x14:
					if int(h.get("OnMfd", 0)) == 1:
						page = ADI
		RADAR:
			match osb:
				0xb:
					step_range(1)
				0xc:
					step_range(-1)
				1:
					cycle_radar_mode()
				3:
					if int(cockpit.radar.get("mode", 0)) == 8:
						_radar_event(0x30)  # MAP: NORM <-> EXP
		TSD:
			match osb:
				# FUN_00531850 / FUN_00531950: next / previous, wrapping (80 → 10, 10 → 80).
				0xb:
					tsd_scale = TSD_SCALES[(TSD_SCALES.find(tsd_scale) + 1) % TSD_SCALES.size()]
				0xc:
					tsd_scale = TSD_SCALES[posmod(TSD_SCALES.find(tsd_scale) - 1, TSD_SCALES.size())]
				0x10, 0x11, 0x12, 0x13:
					tsd_options[osb - 0x10] = not tsd_options[osb - 0x10]
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
				0xb:
					_mfd_event(0x14)
				0xc:
					_mfd_event(0x15)
				5:
					if page == FLIR:
						_mfd_event(0x20)
				3:
					if page == FLIR:
						_mfd_event(0x6a)
		NAV:
			match osb:
				0xb:
					nav_scroll = maxi(nav_scroll - 1, 0)
				0xf:
					nav_scroll = mini(nav_scroll + 1, cockpit.waypoints.size())  # FUN_005219e0: 0..count


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
