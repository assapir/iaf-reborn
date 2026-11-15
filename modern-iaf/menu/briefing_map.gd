# The mission briefing's map (modern-iaf/docs/front-end.md §10), from IafBriefing (crates/iaf-tools briefing.rs), drawn
# north up with a north arrow and a scale bar: the theatre's ground colour (else the TSD map's polygons), the main
# roads, the towns' names, the base's paved shapes (aprons, shelters' pads, taxiways, stopways, runways, parking spots),
# the taxi, the route with its runway's heading, the mission's other flights' routes (each in its colour, with its
# callsign; the one the briefing's tabs pick wider) and the pins (the place of each run of the briefing text's
# paragraphs, numbered as its paragraphs, with its name). It opens on the base and the route (IafBriefing's `focus`) in
# the room the briefing's cards leave (`aim`). It zooms and scrolls over the whole built theatre: the mouse wheel zooms
# around the pointer, a drag scrolls, a double click shows the mission's area; with the focus, + / − zoom, the arrows
# scroll and 0 shows the mission's area. The ground's tiles (the theatre's colour nodes at the view's detail,
# IafBriefing.tiles) decode on worker threads, and the roads, towns and polygons are asked again (`layers_source`) for
# wherever the view goes. Zoomed in, the runways' designators show. The labels and the photo each turn off (`show_*`,
# the briefing's chips). The map itself never mirrors; in Hebrew its north arrow and scale bar swap sides with the
# layout.
extends Control

const Look := preload("look.gd")
const RUNWAY := Color("4a4f57")
const ROUTE := Look.NAVY
## The taxi's and the route's pale edge.
const CASING := Color(1, 1, 1, 0.75)
## The other flights' routes (Bravo, Charlie, Delta), each in its own colour, apart from the player's NAVY.
const FLIGHT_COLOURS := [Color("c2571a"), Color("2e7d32"), Color("8e24aa")]
## The base's pavement over the ground and the parking spots.
const PAVEMENT := Color("8f8b82")
const SPOT := Color("2a2e35")
## The roads by class: colour and width (`brief`, `width`).
const RoadClasses := preload("res://shared/terrain/road_classes.gd")
## The scale bar's lengths to pick from (m): the longest within a quarter of the map's width.
const SCALES := [100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000]
## The zoom's range (out to the whole theatre, `_zoom_min`) and its step (a wheel notch, a key press).
const ZOOM_MAX := 32.0
const ZOOM_STEP := 1.25
## An arrow key scrolls this share of the view.
const PAN_SHARE := 0.1
## A two-finger scroll's step (px a unit of InputEventPanGesture.delta) and a horizontal wheel notch's (px).
const PAN_GESTURE_PX := 24.0
const WHEEL_PX := 60.0
## Zoomed in this far (px a metre) the runways' designators, centrelines and the parking spots show.
const DETAIL_K := 0.15
const Terrain := preload("res://shared/terrain/terrain.gd")
## The ground's tiles decoding at once (the front end keeps its frame rate, as terrain_preload.gd's MENU_JOBS).
const TILE_JOBS := 2
## Decoded tiles kept at most: the view's and the most recently seen (a BC1 1024² node with its mipmaps ≈ 0.7 MB).
const MAX_TILES := 64
## The room kept round what the map opens on (px): a pin's disc and its stacked discs.
const PIN_ROOM := 40.0

## IafBriefing.map's JSON as a Dictionary, {} for none; its `fills`, `roads` and `places` the view's (`layers_source`).
var data := {}
## The base's label, the runway's label ("25R · 246°"), the units ("km", "m").
var base_label := ""
var runway_label := ""
## The pins' names by place ("start", "hold", "lineup").
var pin_names := {}
var km := "km"
var metres := "m"
## The towns' names in Hebrew.
var hebrew := false
## The map for an aspect (width / height): the front end's IafBriefing call, asked again when the size changes.
var source := Callable()
## The layers over a view ([x0, y0, x1, y1] in the map's metres, the map's north-west corner in UTM metres, metres a
## pixel) -> {fills, roads, places}: the front end's IafBriefing.layers call.
var layers_source := Callable()
## The theatre's folder (absolute; its meta.json and colour nodes); empty: the TSD map's polygons under the map.
var theatre := ""
## The view: the zoom (1 = the whole map) and the map point (m) at the control's centre.
var zoom := 1.0
var center := Vector2.ZERO
## The room the map opens in (px; empty: the whole control), its north arrow at its top inline-end corner; the scale
## bar's inline-start bottom corner (px; negative: the control's corner).
var view := Rect2()
var scale_at := Vector2(-1, -1)
## The layers the chips turn on and off: the labels, the photo (else the TSD map's colours).
var show_labels := true:
	set(v):
		show_labels = v
		queue_redraw()
var show_photo := true:
	set(v):
		show_photo = v
		queue_redraw()
## The flight the briefing's tabs picked (its callsign): another flight's route drawn wider.
var selected := "":
	set(v):
		selected = v
		queue_redraw()
var _aspect := 0.0
var _dragging := false
## The view's ground tiles, coarse to fine: [level, i, j, x0, y0, x1, y1] each (IafBriefing.tiles, the map's metres).
var _tiles := PackedFloat64Array()
## Decoded tiles: Vector3i(i, j, level) -> {tex (null: unreadable), used (msec)}.
var _tex := {}
## The view's tiles still to decode, coarse first; the decode tasks (task id -> tile); their images (under _mutex).
var _want: Array[Vector3i] = []
var _jobs := {}
var _done := {}
var _mutex := Mutex.new()
## The view's tiles as a set (kept when the decoded ones are trimmed to MAX_TILES).
var _keep := {}
## The box (the map's metres) the layers were last asked for, and the scales (m a pixel) they serve: finer than the
## first or coarser than the second asks again.
var _layers_box := Rect2()
var _layers_fine := 0.0
var _layers_coarse := 0.0
var _view_dirty := false


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	# The tiles' mipmaps between their levels.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(_load)


## Every decode task waited for and every tile let go (leaving the screen, quitting).
func _exit_tree() -> void:
	for id in _jobs:
		WorkerThreadPool.wait_for_task_completion(id)
	_jobs.clear()
	_want.clear()
	_done.clear()
	_tex.clear()
	_keep.clear()
	_tiles = PackedFloat64Array()


func _process(_delta: float) -> void:
	if _view_dirty:
		_view_dirty = false
		_update_view()
	for id in _jobs.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_jobs.erase(id)
	_mutex.lock()
	var done := _done
	_done = {}
	_mutex.unlock()
	var now := Time.get_ticks_msec()
	for n in done:
		if done[n] == null:
			push_warning("briefing map: cannot read %s" % _tile_path(n))
		_tex[n] = {"tex": ImageTexture.create_from_image(done[n]) if done[n] != null else null, "used": now}
	if not done.is_empty():
		_trim()
		queue_redraw()
	while _jobs.size() < TILE_JOBS and not _want.is_empty():
		var n: Vector3i = _want.pop_front()
		if not _tex.has(n) and not n in _jobs.values():
			_jobs[WorkerThreadPool.add_task(_decode.bind(n, _tile_path(n)), true, "briefing map tile")] = n


## A tile's JPEG (its BC1 .dds beside it when setup made one).
func _tile_path(n: Vector3i) -> String:
	return theatre.path_join("L%d/c_%d_%d.jpg" % [n.z, n.x, n.y])


## Worker: one tile, decoded as the flight's terrain decodes its colour nodes.
func _decode(n: Vector3i, path: String) -> void:
	var img := Terrain.load_colour(path)
	_mutex.lock()
	_done[n] = img
	_mutex.unlock()


## The view moved: its tiles asked for (the decoded ones kept, the oldest others let go past MAX_TILES), and its
## layers when it left the box they were asked for or its scale changed twofold.
func _update_view() -> void:
	if data.is_empty():
		return
	var inv := _xf().affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, size / (_fit() * zoom))
	var box := PackedFloat64Array([view.position.x, view.position.y, view.end.x, view.end.y])
	var e: Array = data.get("extent", [])
	if e.size() != 4:
		return
	var origin := PackedFloat64Array([float(e[0]), float(e[3])])
	var mpp := 1.0 / (_fit() * zoom)
	if theatre != "":
		_tiles = IafBriefing.tiles(theatre, box, origin, mpp)
		_want.clear()
		var now := Time.get_ticks_msec()
		_keep = {}
		for t in range(0, _tiles.size(), 7):
			var n := Vector3i(int(_tiles[t + 1]), int(_tiles[t + 2]), int(_tiles[t]))
			_keep[n] = true
			if _tex.has(n):
				_tex[n].used = now
			else:
				_want.append(n)
		_trim()
	var fresh := _layers_box.encloses(view) and mpp >= _layers_fine and mpp <= _layers_coarse
	if layers_source.is_valid() and not fresh:
		var grown := view.grow(maxf(view.size.x, view.size.y) / 2.0)
		var l: Dictionary = layers_source.call(
			PackedFloat64Array([grown.position.x, grown.position.y, grown.end.x, grown.end.y]), origin, mpp
		)
		if not l.is_empty():
			for k in ["fills", "roads", "places"]:
				data[k] = l.get(k, [])
		_layers_box = grown
		# Its roads keep a point a pixel and its classes and towns follow the scale: asked again zoomed in twofold.
		_layers_fine = mpp / 2.0
		_layers_coarse = mpp * 2.0
	queue_redraw()


## The decoded tiles down to MAX_TILES: the ones seen longest ago that the view does not need go.
func _trim() -> void:
	if _tex.size() <= MAX_TILES:
		return
	var old := _tex.keys().filter(func(k): return not _keep.has(k))
	old.sort_custom(func(a, b): return _tex[a].used < _tex[b].used)
	for k in old.slice(0, _tex.size() - MAX_TILES):
		_tex.erase(k)


func _load() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or not source.is_valid():
		return
	var a := size.x / size.y
	if absf(a - _aspect) > 0.01:
		_aspect = a
		data = source.call(a)
		# The map's own layers hold its whole area at the most detail.
		_layers_box = Rect2(Vector2.ZERO, _size_m())
		_layers_fine = 0.0
		_layers_coarse = 2.0 / _fit()
		open_view()
	queue_redraw()


## The room to open in (`view`), the map on the base and the route in it.
func aim(r: Rect2) -> void:
	if r.size.x > 0.0 and r.size.y > 0.0 and r != view:
		view = r
		open_view()


## The base and the route (`focus`, the map's metres) fitted into `view`; the whole map without them.
func open_view() -> void:
	var f: Array = data.get("focus", [])
	if f.size() != 4 or size.x <= 0.0:
		reset_view()
		return
	_frame(Rect2(float(f[0]), float(f[1]), float(f[2]) - float(f[0]), float(f[3]) - float(f[1])))


## Fits the box `box` (the map's metres) into the room with PIN_ROOM round it (a disc stacks up to two discs above its
## place), then narrows the room until every pin's name plate, which reaches toward the map's right (the map never
## mirrors), ends inside it.
func _frame(box: Rect2) -> void:
	var font := get_theme_font("font", "Label")
	var room := _room()
	var limit := room.end.x
	var free := room.grow_individual(-PIN_ROOM, -PIN_ROOM * 2.0, -PIN_ROOM, -PIN_ROOM)
	if free.size.x > room.size.x / 3.0 and free.size.y > room.size.y / 3.0:
		room = free
	for i in 4:
		var k := minf(room.size.x / box.size.x, room.size.y / box.size.y)
		zoom = clampf(k / _fit(), _zoom_min(), ZOOM_MAX)
		center = box.get_center() - (room.get_center() - size / 2.0) / (_fit() * zoom)
		var xf := _xf()
		var over := 0.0
		for p in data.get("pins", []):
			var w := font.get_string_size(str(pin_names.get(p.place, "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			var at: Vector2 = _points(p.at, xf)[0]
			over = maxf(over, at.x + 26.0 + w + 16.0 - limit)
		if over <= 0.0 or room.size.x - over < room.size.x / 3.0:
			break
		room.size.x -= over
	_clamp()


## The room the map opens in: `view`, else the whole control.
func _room() -> Rect2:
	return view if view.has_area() else Rect2(Vector2.ZERO, size)


## Zooms by `f` around the room's middle (the chips' + and −).
func zoom_view(f: float) -> void:
	zoom_at(f, _room().get_center())


## The mission's area (the map's `size`) fitted into the room.
func reset_view() -> void:
	_frame(Rect2(Vector2.ZERO, _size_m()))


## The map's area (m).
func _size_m() -> Vector2:
	var s: Array = data.get("size", [1, 1])
	return Vector2(float(s[0]), float(s[1]))


## The box the view's centre stays in: the theatre (the map's metres), else the map's area.
func _bounds() -> Rect2:
	var t = data.get("theatre")
	if t is Array and t.size() == 4:
		return Rect2(float(t[0]), float(t[1]), float(t[2]) - float(t[0]), float(t[3]) - float(t[1]))
	return Rect2(Vector2.ZERO, _size_m())


## The least zoom: the whole theatre in view (1 without it).
func _zoom_min() -> float:
	var b := _bounds()
	return minf(1.0, minf(size.x / b.size.x, size.y / b.size.y) / _fit())


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
	zoom = clampf(zoom * f, _zoom_min(), ZOOM_MAX)
	center = before - (at - size / 2.0) / (_fit() * zoom)
	_clamp()


## Scrolls by `px` (screen pixels).
func pan(px: Vector2) -> void:
	center -= px / (_fit() * zoom)
	_clamp()


## The view's centre stays on the theatre, so a drag moves it at every zoom (the whole theatre too: up to half the view
## past its edge) and the ground never leaves the view.
func _clamp() -> void:
	var b := _bounds()
	center = center.clamp(b.position, b.end)
	_view_dirty = true
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				# One way per scroll, as the cockpit's zoom (Settings.zoom_steps: a Mac's bounce dropped).
				zoom_at(pow(ZOOM_STEP, Settings.zoom_steps(event)), event.position)
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
	if show_photo and not _tiles.is_empty():
		# The TSD map's colours until the view's first tile is in (the map's first frames).
		if not _keep.keys().any(func(n): return _tex.has(n)):
			_draw_fills(xf)
		_draw_tiles(xf, k)
	else:
		_draw_fills(xf)
	_draw_roads(xf)
	_draw_base(xf, k)
	var taxi := _points(data.get("taxi", []), xf)
	var route := _points(data.get("route", []), xf)
	# Always drawn, over a pale casing: navy alone was lost on the dark photo (the user's note, 2026-11-15: "the taxi
	# route button doesn't show anything"; its chip removed).
	for i in taxi.size() - 1:
		draw_line(taxi[i], taxi[i + 1], CASING, 7.0, true)
		draw_dashed_line(taxi[i], taxi[i + 1], ROUTE, 3.0, 8.0)
	if route.size() >= 2:
		draw_polyline(route, CASING, 7.0, true)
		draw_polyline(route, ROUTE, 3.0, true)
		_arrow(route[route.size() - 2], route[route.size() - 1])
		for p in route.slice(1):
			draw_circle(p, 7.0, ROUTE, false, 2.5, true)
	_draw_flights(xf)
	var start := _points(data.get("start", []), xf)
	var at: Vector2 = start[0] if start.size() == 1 else size / 2.0
	var taken: Array[Rect2] = []
	# Clear of the north arrow and the scale bar.
	taken.append(Rect2(_north_at() - Vector2(40, 40), Vector2(80, 80)))
	taken.append(_scale_rect(k))
	var pins := _pins(font, xf, taken)
	if show_labels and k >= DETAIL_K:
		for r in data.get("runways", []):
			var e := _points(r.slice(0, 4), xf)
			var out := (e[0] - e[1]).normalized() * 24.0
			for d in [[str(r[5]), e[0] + out], [str(r[6]), e[1] - out]]:
				var w: float = font.get_string_size(d[0], 0, -1, 17).x
				_tag(font, d[0], d[1] + Vector2(-w / 2.0, 8.0), 17, taken)
	elif show_labels:
		_tag(font, base_label, at + Vector2(-60, 48), 22, taken)
	if show_labels and runway_label != "" and route.size() >= 2 and zoom >= 1.0:
		# Beside the take-off's first leg, a little past the lineup (in the room the cards leave).
		var along := (route[1] - route[0]).normalized() * minf(route[0].distance_to(route[1]), 240.0)
		_tag(font, runway_label, route[0] + along + Vector2(-40, -18), 20, taken)
	if show_labels:
		var flights: Array = data.get("flights", [])
		for i in flights.size():
			var pts := _points(flights[i].pts, xf)
			if not pts.is_empty():
				_tag(font, str(flights[i].callsign), pts[0] + Vector2(12, -12), 19, taken)
	if show_labels:
		_draw_places(font, xf, taken)
	pins.call()
	_north(font)
	_scale(font, k)


## The pins (IafBriefing's `pins`): a disc in the accent numbered with the first paragraph of the briefing's text done
## at its place (moved up off a disc it would cover, a line back to its place); with the labels on, its place's name on
## a dark plate. Their room is taken now; the Callable it answers draws them over everything.
func _pins(font: Font, xf: Transform2D, taken: Array[Rect2]) -> Callable:
	var discs := []
	var plates := []
	for p in data.get("pins", []):
		var at: Vector2 = _points(p.at, xf)[0]
		var c := at
		for i in 6:
			if not discs.any(func(d): return d[1].distance_to(c) < 38.0):
				break
			c.y -= 40.0
		discs.append([at, c, str(int(p.first) + 1)])
		taken.append(Rect2(c - Vector2(18, 18), Vector2(36, 36)))
	# Their names in view only, and not zoomed out past the mission's area (the pins a few pixels apart there).
	if show_labels and zoom >= 1.0:
		var pins: Array = data.get("pins", [])
		for i in pins.size():
			var p: Dictionary = pins[i]
			var c: Vector2 = discs[i][1]
			if not Rect2(Vector2.ZERO, size).has_point(c):
				continue
			var r := _plate(font, str(pin_names.get(p.place, "")), c + Vector2(26, 8), 19, taken)
			plates.append([r, str(pin_names.get(p.place, "")), 19])
	return func():
		for d in discs:
			if d[0] != d[1]:
				draw_line(d[0], d[1], Color.WHITE, 2.0, true)
				draw_circle(d[0], 4.0, Color.WHITE, true, -1.0, true)
		for pl in plates:
			if pl[0].has_area():
				draw_rect(pl[0], Color(Look.BG, 0.88))
				var at: Vector2 = pl[0].position + Vector2(8, pl[2] + 4)
				draw_string(font, at, pl[1], HORIZONTAL_ALIGNMENT_LEFT, -1, pl[2], Look.TEXT)
		for d in discs:
			draw_circle(d[1], 17.0, Look.ACCENT, true, -1.0, true)
			draw_circle(d[1], 17.0, Color.WHITE, false, 2.5, true)
			var w := font.get_string_size(d[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(font, d[1] + Vector2(-w / 2.0, 6.5), d[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Look.NAVY)


## A pin label's plate for text `t` at `at` (its baseline's start), moved down past a plate already there (at most four
## times), its room taken; an empty Rect2 for no text.
func _plate(font: Font, t: String, at: Vector2, px: int, taken: Array[Rect2]) -> Rect2:
	if t == "":
		return Rect2()
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	at.x = clampf(at.x, 8.0, size.x - w - 18.0)
	var plate := Rect2(at + Vector2(-8, -px - 4), Vector2(w + 16, px + 14))
	for i in 4:
		if not taken.any(func(o): return o.intersects(plate)):
			break
		plate.position.y += px + 16
	taken.append(plate)
	return plate


## The ground's decoded tiles, coarse to fine: a finer one over the coarser one it refines.
func _draw_tiles(xf: Transform2D, k: float) -> void:
	for t in range(0, _tiles.size(), 7):
		var e = _tex.get(Vector3i(int(_tiles[t + 1]), int(_tiles[t + 2]), int(_tiles[t])))
		if e != null and e.tex != null:
			var at := xf * Vector2(_tiles[t + 3], _tiles[t + 4])
			draw_texture_rect(
				e.tex, Rect2(at, Vector2(_tiles[t + 5] - _tiles[t + 3], _tiles[t + 6] - _tiles[t + 4]) * k), false
			)


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
				var st: Dictionary = RoadClasses.CLASSES[c]
				if pass_i == 0:
					draw_polyline(pts, Color(0, 0, 0, 0.45), st.width + 2.0, true)
				else:
					draw_polyline(pts, st.brief, st.width, true)


## The towns: a dot and the name in the game's language, a label that would cover an earlier one or reach into the
## header's band left out.
func _draw_places(font: Font, xf: Transform2D, taken: Array[Rect2]) -> void:
	# Below the header's band (the room's top), inside the map.
	var top := Rect2(0.0, _room().position.y, size.x, size.y - _room().position.y)
	for p in data.get("places", []):
		var at: Vector2 = _points(p.at, xf)[0]
		var big: bool = p.kind != "village"
		var px := 21 if p.kind == "city" else (19 if big else 16)
		var t := str(p.he if hebrew else p.en)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var r := Rect2(at + Vector2(-w / 2.0 - 4, -px - 12), Vector2(w + 8, px + 8))
		if not top.encloses(r) or taken.any(func(o): return o.intersects(r)):
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


## A label on a pale plate at `at` (left out when `at` is far off the map), kept inside the map; its plate joins
## `taken`.
func _tag(font: Font, t: String, at: Vector2, px: int, taken: Array[Rect2]) -> void:
	if t == "" or not Rect2(Vector2.ZERO, size).grow(px * 4).has_point(at):
		return
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	at.x = clampf(at.x, 8.0, size.x - w - 18.0)
	at.y = clampf(at.y, px + 8.0, size.y - 8.0)
	var plate := Rect2(at + Vector2(-6, -px - 2), Vector2(w + 12, px + 12))
	taken.append(plate)
	draw_rect(plate, Color(Look.PAPER, 0.85))
	draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Look.INK)


## The mission's other flights (IafBriefing's `flights`): from the start (a square) along the waypoints (rings) to an
## arrow, each in its FLIGHT_COLOURS; the picked one (`selected`) wider.
func _draw_flights(xf: Transform2D) -> void:
	var flights: Array = data.get("flights", [])
	for i in flights.size():
		var pts := _points(flights[i].pts, xf)
		if pts.is_empty():
			continue
		var c: Color = FLIGHT_COLOURS[i % FLIGHT_COLOURS.size()]
		var w := 5.0 if str(flights[i].callsign) == selected else 3.0
		draw_rect(Rect2(pts[0] - Vector2(7, 7), Vector2(14, 14)), c)
		if pts.size() >= 2:
			draw_polyline(pts, CASING, w + 4.0, true)  # the player's route's pale edge, readable on the photo
			draw_polyline(pts, c, w, true)
			_arrow(pts[pts.size() - 2], pts[pts.size() - 1], c)
			for p in pts.slice(1):
				draw_circle(p, 7.0, c, false, 2.5, true)


func _arrow(a: Vector2, b: Vector2, c := ROUTE) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var tip := b - d * 9.0
	draw_colored_polygon(PackedVector2Array([tip, tip - d * 16.0 + n * 8.0, tip - d * 16.0 - n * 8.0]), c)


## The north arrow's centre: the room's top inline-end corner.
func _north_at() -> Vector2:
	var r := _room()
	return Vector2(r.position.x + 40.0 if is_layout_rtl() else r.end.x - 40.0, r.position.y + 40.0)


## The north arrow at the room's top inline-end corner: true north (the grid turned by `north`).
func _north(font: Font) -> void:
	var c := _north_at()
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


## The scale bar's box (its plate) at `scale_at`, else the control's bottom inline-start corner.
func _scale_rect(k: float) -> Rect2:
	var w := scale_metres() * k
	var rtl := is_layout_rtl()
	var c := scale_at if scale_at.x >= 0.0 else Vector2(size.x - 24.0 if rtl else 24.0, size.y - 28.0)
	var x0 := c.x - w if rtl else c.x
	return Rect2(x0 - 10, c.y - 34, w + 20, 46)


func _scale(font: Font, k: float) -> void:
	var m := scale_metres()
	var w := m * k
	var box := _scale_rect(k)
	var x0 := box.position.x + 10.0
	var y := box.position.y + 34.0
	var t := "%d %s" % [int(m / 1000.0), km] if m >= 1000 else "%d %s" % [m, metres]
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_rect(box, Color(Look.BG, 0.8))
	draw_rect(Rect2(x0, y - 4, w / 2.0, 8), Look.TEXT)
	draw_rect(Rect2(x0 + w / 2.0, y - 4, w / 2.0, 8), Look.MUTED)
	draw_string(font, Vector2(x0 + (w - tw) / 2.0, y - 12), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Look.TEXT)
