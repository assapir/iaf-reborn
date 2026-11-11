# The mission briefing's map (modern-iaf/docs/front-end.md §10), from IafBriefing (crates/iaf-tools briefing.rs), drawn
# north up with a north arrow and a scale bar: the theatre's ground colour (else the TSD map's polygons), the main
# roads, the towns' names, the base's paved shapes (aprons, shelters' pads, taxiways, stopways, runways, parking
# spots), the taxi, the route with its runway's heading and the start. It zooms and scrolls: the mouse wheel zooms
# around the pointer, a drag scrolls, a double click resets; with the focus, + / − zoom, the arrows scroll and 0 resets.
# Zoomed in, the runways' designators and the start spot's label show. The map itself never mirrors; in Hebrew its
# north arrow and scale bar swap sides with the layout.
extends Control

const Look := preload("look.gd")
const RUNWAY := Color("4a4f57")
const ROUTE := Look.NAVY
## The base's pavement over the ground and the parking spots.
const PAVEMENT := Color("8f8b82")
const SPOT := Color("2a2e35")
## The roads by class (iaf_avionics::roads CLASS_*: motorway, trunk, primary, secondary): colour, width (px).
const ROAD_STYLE := [[Color("f2b84b"), 3.0], [Color("f2b84b"), 2.6], [Color("fff6e0"), 2.2], [Color("f4efe4"), 1.6]]
## The scale bar's lengths to pick from (m): the longest within a quarter of the map's width.
const SCALES := [100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000]
## The zoom's range and its step (a wheel notch, a key press).
const ZOOM_MAX := 32.0
const ZOOM_STEP := 1.25
## An arrow key scrolls this share of the view.
const PAN_SHARE := 0.1
## A two-finger scroll's step (px a unit of InputEventPanGesture.delta) and a horizontal wheel notch's (px).
const PAN_GESTURE_PX := 24.0
const WHEEL_PX := 60.0
## Zoomed in this far (px a metre) the runways' designators, centrelines, the parking spots and the start's label show.
const DETAIL_K := 0.15

## IafBriefing.map's JSON as a Dictionary, {} for none; `texture`: the ground colour.
var data := {}
## The base's label, the runway's label ("25R · 254°"), the start spot's label, the units ("km", "m").
var base_label := ""
var runway_label := ""
var start_label := ""
var km := "km"
var metres := "m"
## The towns' names in Hebrew.
var hebrew := false
## The map for an aspect (width / height): the front end's IafBriefing call, asked again when the size changes.
var source := Callable()
## The view: the zoom (1 = the whole map) and the map point (m) at the control's centre.
var zoom := 1.0
var center := Vector2.ZERO
var _aspect := 0.0
var _dragging := false


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	resized.connect(_load)


func _load() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or not source.is_valid():
		return
	var a := size.x / size.y
	if absf(a - _aspect) > 0.01:
		_aspect = a
		data = source.call(a)
		reset_view()
	queue_redraw()


## The whole map in view.
func reset_view() -> void:
	var s: Array = data.get("size", [1, 1])
	zoom = 1.0
	center = Vector2(float(s[0]), float(s[1])) / 2.0
	queue_redraw()


## Px a metre at zoom 1: the map fitted.
func _fit() -> float:
	var s: Array = data.get("size", [1, 1])
	return minf(size.x / float(s[0]), size.y / float(s[1]))


## Metres of the map → px of the control at the view.
func _xf() -> Transform2D:
	var k := _fit() * zoom
	return Transform2D(0.0, Vector2(k, k), 0.0, size / 2.0 - center * k)


## Zooms by `f` keeping the map point under `at` (px) in place; the view stays on the map.
func zoom_at(f: float, at: Vector2) -> void:
	var before := _xf().affine_inverse() * at
	zoom = clampf(zoom * f, 1.0, ZOOM_MAX)
	center = before - (at - size / 2.0) / (_fit() * zoom)
	_clamp()


## Scrolls by `px` (screen pixels).
func pan(px: Vector2) -> void:
	center -= px / (_fit() * zoom)
	_clamp()


## The view's centre stays on the map, so a drag moves it at every zoom (the whole map too: up to half the view past
## its edge) and the map never leaves the view.
func _clamp() -> void:
	var s: Array = data.get("size", [1, 1])
	center = Vector2(clampf(center.x, 0.0, float(s[0])), clampf(center.y, 0.0, float(s[1])))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_at(ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_at(1.0 / ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_LEFT:
				pan(Vector2(WHEEL_PX * maxf(event.factor, 1.0), 0))
			MOUSE_BUTTON_WHEEL_RIGHT:
				pan(Vector2(-WHEEL_PX * maxf(event.factor, 1.0), 0))
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				grab_focus()
				if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
					reset_view()
				else:
					_dragging = true
			_:
				return
		accept_event()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_dragging = false
		accept_event()
	elif (
		event is InputEventMouseMotion
		and (_dragging or event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE))
	):
		# A drag (also one that began before the press reached the map: the button held in the motion).
		pan(event.relative)
		accept_event()
	elif event is InputEventPanGesture:
		# A trackpad's two-finger scroll: the map follows the fingers.
		grab_focus()
		pan(-event.delta * PAN_GESTURE_PX)
		accept_event()
	elif event is InputEventMagnifyGesture:
		# A trackpad's pinch.
		grab_focus()
		zoom_at(event.factor, event.position)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var step := size * PAN_SHARE
		match event.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_at(ZOOM_STEP, size / 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_at(1.0 / ZOOM_STEP, size / 2.0)
			KEY_LEFT:
				pan(Vector2(step.x, 0))
			KEY_RIGHT:
				pan(Vector2(-step.x, 0))
			KEY_UP:
				pan(Vector2(0, step.y))
			KEY_DOWN:
				pan(Vector2(0, -step.y))
			KEY_0, KEY_KP_0, KEY_HOME:
				reset_view()
			_:
				return
		accept_event()


static func _points(flat: Array, xf: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(xf * Vector2(float(flat[i]), float(flat[i + 1])))
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Look.BG)
	if data.is_empty():
		return
	var xf := _xf()
	var k := xf.get_scale().x
	var font := get_theme_font("font", "Label")
	var s: Array = data.size
	var rect := Rect2(xf.origin, Vector2(float(s[0]), float(s[1])) * k)
	if data.get("texture") is Texture2D:
		draw_texture_rect(data.texture, rect, false)
	else:
		_draw_fills(xf)
	_draw_roads(xf)
	_draw_base(xf, k)
	var taxi := _points(data.get("taxi", []), xf)
	for i in taxi.size() - 1:
		draw_dashed_line(taxi[i], taxi[i + 1], ROUTE, 3.0, 8.0)
	var route := _points(data.get("route", []), xf)
	if route.size() >= 2:
		draw_polyline(route, ROUTE, 3.0, true)
		_arrow(route[route.size() - 2], route[route.size() - 1])
		for p in route.slice(1):
			draw_circle(p, 7.0, ROUTE, false, 2.5, true)
	var start := _points(data.get("start", []), xf)
	var at: Vector2 = start[0] if start.size() == 1 else size / 2.0
	if start.size() == 1:
		draw_circle(at, 9.0, Look.ACCENT, true, -1.0, true)
		draw_circle(at, 9.0, ROUTE, false, 2.5, true)
	var taken: Array[Rect2] = []
	# Clear of the north arrow and the scale bar.
	var rtl := is_layout_rtl()
	taken.append(Rect2(Vector2(8.0 if rtl else size.x - 88.0, 18.0), Vector2(80, 80)))
	taken.append(Rect2(Vector2(size.x - 300.0 if rtl else 0.0, size.y - 80.0), Vector2(300, 80)))
	if k >= DETAIL_K:
		_tag(font, start_label, at + Vector2(16, 6), 18, taken)
		for r in data.get("runways", []):
			var e := _points(r.slice(0, 4), xf)
			var out := (e[0] - e[1]).normalized() * 24.0
			for d in [[str(r[5]), e[0] + out], [str(r[6]), e[1] - out]]:
				var w: float = font.get_string_size(d[0], 0, -1, 17).x
				_tag(font, d[0], d[1] + Vector2(-w / 2.0, 8.0), 17, taken)
	else:
		_tag(font, base_label, at + Vector2(-60, 48), 22, taken)
	if runway_label != "" and route.size() >= 2:
		# Beside the take-off's first leg, past the base.
		_tag(font, runway_label, route[0].lerp(route[1], 0.55) + Vector2(-40, -18), 20, taken)
	_draw_places(font, xf, taken)
	_north(font)
	_scale(font, k)
	draw_rect(Rect2(Vector2.ZERO, size), Look.LINE, false, 1.0)


## The TSD map's polygons (without the theatre's ground colour).
func _draw_fills(xf: Transform2D) -> void:
	for f in data.get("fills", []):
		var pts := _points(f.tris, xf)
		var cs := PackedColorArray()
		cs.resize(pts.size())
		cs.fill(Color8(int(f.color[0]), int(f.color[1]), int(f.color[2])))
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cs)


## The main roads, the lesser first, each over a dark casing.
func _draw_roads(xf: Transform2D) -> void:
	var roads: Array = data.get("roads", [])
	for pass_i in 2:
		for c in [3, 2, 1, 0]:
			for r in roads:
				if int(r["class"]) != c:
					continue
				var pts := _points(r.pts, xf)
				if pts.size() < 2:
					continue
				var st: Array = ROAD_STYLE[c]
				if pass_i == 0:
					draw_polyline(pts, Color(0, 0, 0, 0.45), st[1] + 2.0, true)
				else:
					draw_polyline(pts, st[0], st[1], true)


## The towns: a dot and the name in the game's language, a label that would cover an earlier one left out.
func _draw_places(font: Font, xf: Transform2D, taken: Array[Rect2]) -> void:
	for p in data.get("places", []):
		var at: Vector2 = _points(p.at, xf)[0]
		var big: bool = p.kind != "village"
		var px := 21 if p.kind == "city" else (19 if big else 16)
		var t := str(p.he if hebrew else p.en)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var r := Rect2(at + Vector2(-w / 2.0 - 4, -px - 12), Vector2(w + 8, px + 8))
		if not Rect2(Vector2.ZERO, size).encloses(r) or taken.any(func(o): return o.intersects(r)):
			continue
		taken.append(r)
		draw_circle(at, 5.0 if big else 3.5, Color.WHITE, true, -1.0, true)
		draw_circle(at, 5.0 if big else 3.5, Color(0, 0, 0, 0.8), false, 1.5, true)
		var pos := at + Vector2(-w / 2.0, -10)
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0, 0, 0, 0.6))
		draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)


## The airbase: the aprons and the shelters' pads, the taxiways and the stopways, the runways; zoomed in the
## centrelines and the parking spots.
func _draw_base(xf: Transform2D, k: float) -> void:
	for key in ["aprons", "shelters"]:
		for poly in data.get(key, []):
			var pts := _points(poly, xf)
			if pts.size() >= 3:
				var tris := IafEmf.fill_triangles([pts] as Array[PackedVector2Array], true)
				var cs := PackedColorArray()
				cs.resize(tris.size())
				cs.fill(PAVEMENT)
				RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), tris, cs)
	for t in data.get("taxiways", []):
		var pts := _points(t.pts, xf)
		if pts.size() >= 2:
			draw_polyline(pts, PAVEMENT, maxf(float(t.w) * k, 1.0), true)
	var widest := 0.0
	for r in data.get("runways", []):
		widest = maxf(widest, float(r[4]))
	for l in data.get("stopways", []):
		var pts := _points(l, xf)
		if pts.size() >= 2:
			draw_polyline(pts, PAVEMENT, maxf(widest * k, 1.0), true)
	for r in data.get("runways", []):
		var e := _points(r.slice(0, 4), xf)
		draw_line(e[0], e[1], RUNWAY, maxf(float(r[4]) * k, 3.0))
		if k >= DETAIL_K:
			draw_dashed_line(e[0], e[1], Color.WHITE, 1.0, 10.0)
	if k >= DETAIL_K:
		for p in _points(data.get("parking", []), xf):
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), SPOT)


## A label on a pale plate, kept inside the map; its plate joins `taken`.
func _tag(font: Font, t: String, at: Vector2, px: int, taken: Array[Rect2]) -> void:
	if t == "":
		return
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	at.x = clampf(at.x, 8.0, size.x - w - 18.0)
	at.y = clampf(at.y, px + 8.0, size.y - 8.0)
	var plate := Rect2(at + Vector2(-6, -px - 2), Vector2(w + 12, px + 12))
	taken.append(plate)
	draw_rect(plate, Color(Look.PAPER, 0.85))
	draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Look.INK)


func _arrow(a: Vector2, b: Vector2) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var tip := b - d * 9.0
	draw_colored_polygon(PackedVector2Array([tip, tip - d * 16.0 + n * 8.0, tip - d * 16.0 - n * 8.0]), ROUTE)


## The north arrow at the top inline-end corner: true north (the grid turned by `north`).
func _north(font: Font) -> void:
	var rtl := is_layout_rtl()
	var c := Vector2(48.0 if rtl else size.x - 48.0, 58.0)
	var d := Vector2.UP.rotated(deg_to_rad(float(data.get("north", 0.0))))
	var n := Vector2(-d.y, d.x)
	draw_circle(c, 30.0, Color(Look.BG, 0.8), true, -1.0, true)
	draw_colored_polygon(PackedVector2Array([c + d * 22.0, c - d * 10.0 + n * 10.0, c - d * 4.0]), Look.TEXT)
	draw_colored_polygon(PackedVector2Array([c + d * 22.0, c - d * 4.0, c - d * 10.0 - n * 10.0]), Look.MUTED)
	draw_string(font, c - d * 13.0 + Vector2(-7, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Look.TEXT)


## The scale bar at the bottom inline-start corner: the longest of SCALES within a quarter of the width.
func scale_metres() -> int:
	var k := _fit() * zoom
	var m: int = SCALES[0]
	for s in SCALES:
		if s * k <= size.x / 4.0:
			m = s
	return m


func _scale(font: Font, k: float) -> void:
	var m := scale_metres()
	var w := m * k
	var rtl := is_layout_rtl()
	var x0 := size.x - 24.0 - w if rtl else 24.0
	var y := size.y - 28.0
	var t := "%d %s" % [int(m / 1000.0), km] if m >= 1000 else "%d %s" % [m, metres]
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_rect(Rect2(x0 - 10, y - 34, w + 20, 46), Color(Look.BG, 0.8))
	draw_rect(Rect2(x0, y - 4, w / 2.0, 8), Look.TEXT)
	draw_rect(Rect2(x0 + w / 2.0, y - 4, w / 2.0, 8), Look.MUTED)
	draw_string(font, Vector2(x0 + (w - tw) / 2.0, y - 12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Look.TEXT)
