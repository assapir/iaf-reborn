# The full-screen weapon MFD (key Z, view mode 0xb, FullScreenRender.cpp; docs/mfd.md §3 "Full-screen weapon MFD"):
# the whole 640×480 screen instead of the world view, panel, HUD, MFDs and console — the EO camera's picture in
# RENDER_RECT (128,49)–(513,431), the TV or FLIR layer of the MFD it was opened from in 2 px RGB(0,255,0) lines and
# ANSI_VAR_FONT text, the waypoint circle and the attitude bar, then fsmfd.bmp: the frame outside the rect and its
# white-keyed rounded corners (with the zoom arrows) over the picture. The bezel's 20 OSBs run that MFD's buttons.
extends Control

const GREEN := Color8(0, 255, 0)
const PEN := 2.0
## Data.ibx's RENDER_RECT (the shipped value; read from the file when present).
var render_rect := Rect2(128, 49, 385, 382)
var corners: Array[Rect2] = []
var render_corners: Array[Rect2] = []
## The OSB strips (table 0x65cd18): buttons every 57 px, live on their first 27; ids as the small MFD's.
const STRIPS := [[Vector2(193, 12), true, 1], [Vector2(192, 441), true, 6], [Vector2(88, 108), false, 11], [Vector2(522, 109), false, 16]]
const STRIP_DEPTH := [27.0, 29.0, 28.0, 28.0]

var cockpit: Control  # cockpit.gd: eo / weapons / state / waypoints
## The MFD the mode was opened from (fs[0xb7]): the last showing page 5 / 6, else 0.
var mfd_index := 0
var picture: Texture2D
## The current waypoint in the picture (camera projection, 640 space) or null (host).
var waypoint_at = null
var waypoint_label := ""
var _frame: Texture2D
var _keyed: Texture2D
var _font: Font
var _blink := false
var _blink_ms := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # the art's key edges stay crisp
	_font = preload("res://util/img.gd").arial(400, false)
	var dir: String = Settings.assets_dir().path_join("install/resource/cockpits/fsmfd")
	var ibx: Dictionary = Settings.load_ibx(dir.path_join("data.ibx"))
	var rect := func(k: String) -> Rect2:
		var s: Dictionary = ibx.get(k, {})
		return Rect2(Vector2(int(s.left), int(s.top)), Vector2(int(s.right) - int(s.left), int(s.bottom) - int(s.top)))
	if ibx.has("RENDER_RECT"):
		render_rect = rect.call("RENDER_RECT")
	for i in 4:
		if ibx.has("CORNER%03d" % i):
			corners.append(rect.call("CORNER%03d" % i))
		if ibx.has("RENDERCORNER%03d" % i):
			render_corners.append(rect.call("RENDERCORNER%03d" % i))
	var img := Image.load_from_file(dir.path_join("fsmfd.bmp")) if FileAccess.file_exists(dir.path_join("fsmfd.bmp")) else null
	if img != null:
		_frame = ImageTexture.create_from_image(img)
		# The RENDERCORNER surfaces' colour key 0xffffff: white shows the picture through.
		var k := img.duplicate()
		k.convert(Image.FORMAT_RGBA8)
		for y in k.get_height():
			for x in k.get_width():
				if k.get_pixel(x, y) == Color.WHITE:
					k.set_pixel(x, y, Color(0, 0, 0, 0))
		_keyed = ImageTexture.create_from_image(k)


## 640×480 → screen: the height fills the window, centred across (outside it black).
func _s() -> float:
	return size.y / 480.0


func _o() -> Vector2:
	return Vector2((size.x - 640.0 * _s()) / 2.0, 0.0)


func _p(v: Vector2) -> Vector2:
	return _o() + v * _s()


func _ln(a: Vector2, b: Vector2) -> void:
	draw_line(_p(a), _p(b), GREEN, PEN * _s() * 0.5 if _s() < 2.0 else PEN)


func _text(at: Vector2, t: String, centre := false) -> void:
	var fs := maxi(int(round(13.0 * _s())), 1)
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := _p(at) + Vector2(-w / 2.0 if centre else 0.0, _font.get_ascent(fs))
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GREEN)


## The page (5 TV / 6 FLIR) of the MFD the mode came from.
func page() -> int:
	return int(cockpit.mfds[mfd_index].page) if mfd_index < cockpit.mfds.size() else -1


func _process(_delta: float) -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	var ms := Time.get_ticks_msec()
	if ms - _blink_ms > 300:
		_blink_ms = ms
		_blink = not _blink
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if picture != null:
		draw_texture_rect(picture, Rect2(_p(render_rect.position), render_rect.size * _s()), false)
	match page():
		5: _draw_tv()
		6: _draw_flir()
	if _frame != null:
		for r in corners:
			draw_texture_rect_region(_frame, Rect2(_p(r.position), r.size * _s()), r)
		for r in render_corners:
			draw_texture_rect_region(_keyed, Rect2(_p(r.position), r.size * _s()), r)


## The layers' frame: x0, y0 = the rect + 2, w, h = its size − 4, centre (320, 240); 190 / 189 px per unit u / v.
func _centre() -> Vector2:
	return render_rect.position + Vector2(2, 2) + (render_rect.size - Vector2(4, 4)) / 2.0


## TV (FUN_00524570): the cross-hair with a 10 px gap (20 at TER), the seeker ticks outside it, the texts, the
## waypoint circle (time left > 15 s or RDY), the attitude bar.
func _draw_tv() -> void:
	var tv: Dictionary = cockpit.eo.get("tv", {})
	var st := int(tv.get("status", 0))
	var c := _centre()
	var x0 := render_rect.position.x + 2
	var y0 := render_rect.position.y + 2
	var x1 := x0 + render_rect.size.x - 4
	var y1 := y0 + render_rect.size.y - 4
	var g := 20.0 if st == 3 else 10.0
	_ln(Vector2(c.x, y0), Vector2(c.x, c.y - g))
	_ln(Vector2(c.x, c.y + g), Vector2(c.x, y1))
	_ln(Vector2(x0, c.y), Vector2(c.x - g, c.y))
	_ln(Vector2(c.x + g, c.y), Vector2(x1, c.y))
	var du := 190.0 * float(tv.get("u", 0.0))
	var dv := 189.0 * float(tv.get("v", 0.0))
	if absf(du) > g:
		_ln(Vector2(c.x - du, 236), Vector2(c.x - du, 245))
	if absf(dv) > g:
		_ln(Vector2(315, c.y + dv), Vector2(325, c.y + dv))
	var wp: Dictionary = cockpit.weapons
	_text(Vector2(187, 59), "TV")
	_text(Vector2(254, 59), "%d %s " % [int(wp.get("total", 0)), String(wp.get("name", ""))])
	_text(Vector2(403, 59), ["NO SOURCE", "RDY", "TRA", "TER"][clampi(st, 0, 3)])
	_text(Vector2(140, 145), "X%d" % int(tv.get("zoom", 1)))
	var t := float(cockpit.eo.get("tv_time", 0.0))
	_text(Vector2(378, 399), "XXX SEC" if t >= 250.0 else "%3d SEC" % int(t))
	if t > 15.0 or st == 1:
		_draw_waypoint()
	_draw_attitude()


## FLIR (FUN_00524a60): the short cross-hair, the four corner brackets, the gimbal blob, the texts, the waypoint
## circle, the attitude bar.
func _draw_flir() -> void:
	var f: Dictionary = cockpit.eo.get("flir", {})
	var c := _centre()
	_ln(Vector2(c.x, 191), Vector2(c.x, 230))
	_ln(Vector2(c.x, 250), Vector2(c.x, 289))
	_ln(Vector2(270, c.y), Vector2(310, c.y))
	_ln(Vector2(330, c.y), Vector2(371, c.y))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_ln(c + Vector2(80 * sx, 50 * sy), c + Vector2(80 * sx, 80 * sy))
			_ln(c + Vector2(80 * sx, 80 * sy), c + Vector2(50 * sx, 80 * sy))
	var b := c + Vector2(-190.0 * float(f.get("u", 0.0)), 189.0 * float(f.get("v", 0.0)))
	draw_rect(Rect2(_p(b - Vector2(2, 2)), Vector2(5, 5) * _s()), GREEN)
	_text(Vector2(187, 59), "FLIR")
	_text(Vector2(284, 59), "LASER ON" if f.get("laser", false) else "LASER OFF")
	_text(Vector2(403, 59), "SPOT" if f.get("spot", false) else "WIDE")
	_text(Vector2(140, 145), "X%d" % int(f.get("zoom", 1)))
	_text(Vector2(378, 399), String(f.get("range", "")))
	_draw_waypoint()
	_draw_attitude()


## The waypoint circle (FUN_005256f0): r 15 about the current waypoint's picture point, moved along the line from
## the centre onto the rect inset 20 when outside it; its number (or "T") centred 7 px above its centre.
func _draw_waypoint() -> void:
	if waypoint_at == null or not (waypoint_at as Vector2).is_finite():
		return
	var inner := render_rect.grow(-20)
	var c := _centre()
	var p: Vector2 = waypoint_at
	if not inner.has_point(p):
		var d := p - c
		var k := 1.0
		if d.x != 0.0:
			k = minf(k, ((inner.end.x if d.x > 0 else inner.position.x) - c.x) / d.x)
		if d.y != 0.0:
			k = minf(k, ((inner.end.y if d.y > 0 else inner.position.y) - c.y) / d.y)
		p = c + d * maxf(k, 0.0)
	draw_arc(_p(p), 15.0 * _s(), 0.0, TAU, 32, GREEN, PEN * _s() * 0.5)
	_text(p - Vector2(0, 7), waypoint_label, true)


## The attitude bar (FUN_00525030): the DASH symbol's bar about (320, 240) at 4 px per degree, (∓162, 10) →
## (∓162, 0) → (∓10, 0); beyond ±40° held there and blinking (300 ms).
func _draw_attitude() -> void:
	var st: Dictionary = cockpit.state
	var p := fposmod(float(st.get("pitch", 0.0)), 360.0)
	var r := fposmod(float(st.get("roll", 0.0)), 360.0)
	if p > 90.0 and p < 270.0:
		p = 180.0 - p
		r += 180.0
	elif p >= 270.0:
		p -= 360.0
	if absf(p) > 40.0:
		p = clampf(p, -40.0, 40.0)
		if _blink:
			return
	var rr := deg_to_rad(r)
	var c := Vector2(320, 240)
	for side in [-1.0, 1.0]:
		var pts: Array[Vector2] = []
		for q in [Vector2(162 * side, 10), Vector2(162 * side, 0), Vector2(10 * side, 0)]:
			pts.append(c + Vector2(q.x * cos(rr) + q.y * sin(rr), 4.0 * p + q.y * cos(rr) - q.x * sin(rr)))
		_ln(pts[0], pts[1])
		_ln(pts[1], pts[2])


## The OSB under 640-space point `q` (1..20) or 0.
func osb_at(q: Vector2) -> int:
	for i in STRIPS.size():
		var s: Array = STRIPS[i]
		var along: float = (q.x - s[0].x) if s[1] else (q.y - s[0].y)
		var across: float = (q.y - s[0].y) if s[1] else (q.x - s[0].x)
		if across < 0.0 or across > STRIP_DEPTH[i] or along < 0.0:
			continue
		var n := int(along / 57.0)
		if n < 5 and fmod(along, 57.0) < 27.0:
			return int(s[2]) + n
	return 0


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var q: Vector2 = (event.position - _o()) / _s()
	var osb := osb_at(q)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if osb > 0 else Control.CURSOR_ARROW
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# That page's OSB action on the MFD (FUN_005219e0); 6 MENU is dropped while the mode is on (event 0x5b).
		if osb > 0 and osb != 6 and mfd_index < cockpit.mfds.size():
			cockpit.mfds[mfd_index].press(osb)
		accept_event()
