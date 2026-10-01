# The pre-flight Tactical Situation Display (screen 0x1e, docs/front-end.md §6, §8): the EMF
# vector map with grid / text overlays, units and waypoints, zoom and scrollbars, and the
# briefing window with its link windows. Panels and buttons are drawn by the front end, which
# forwards TSD button presses here.
extends Control

## Content window (TSD client) in 640x480 space.
const CLIENT := Rect2(155, 42, 453, 357)
## Map extent at zoom 1 (0x607fa8/e4).
const MAP_SIZE := Vector2(454, 590)
const ZOOM_STEP := 1.5
const ZOOM_MAX := 32.0
## Scrollbars by axis (0 = horizontal, 1 = vertical), screen coordinates, and the lengths of their
## arrow / thumb art along the bar.
const BARS := [Rect2(146, 399, 462, 10), Rect2(608, 42, 10, 356)]
const BAR_UP := [24.0, 23.0]
const BAR_DOWN := [21.0, 21.0]
const BAR_THUMB := [74.0, 75.0]
const BAR_ART := ["h", "v"]
const BAR_ARROWS := [["left", "right"], ["up", "down"]]
## Scroll arrow step: 5 map units (round(5·z) px).
const ARROW_STEP := 5.0
## World -> map (FUN_00500ec0): X shift = DataXShiftPR, Y shift, width / height of the world.
const WORLD_X_SHIFT := 166850.0
const WORLD_Y_SHIFT := 21144.0
const WORLD_W := 819200.0
const WORLD_H := 1064960.0
const MAP_X_FACTOR := 1.0071394
## Flight colours 1..4 (Alpha..Delta), 5-6 white.
const FLIGHT_COLORS := [Color8(226, 0, 180), Color8(4, 178, 39), Color8(0, 82, 250), Color8(215, 134, 1), Color.WHITE, Color.WHITE]
const FLIGHT_NAMES := ["alpha", "bravo", "charlie", "delta"]
## Flyable type codes (FUN_00505730).
const FLYABLE_TYPES := [100, 110, 120, 130, 140, 160, 180, 190, 200]
## bdb object class (0x5aa) -> icon class: 1 aircraft, 2 ship, 3 structure, 4 vehicle, 5 SAM, 6 AAA.
const ICON_CLASS := {2: 1, 3: 1, 0x1c: 1, 0xf: 2, 0x10: 2, 0xc: 3, 0xd: 3, 0x1d: 3, 0x1e: 3, 5: 4, 6: 4, 8: 5, 9: 5, 10: 6}
const ICON_ART := {1: "icair", 2: "icshp", 3: "icstr", 4: "icveh", 5: "icsam", 6: "icaaa"}
const FILTERS := {1: "aircrafts", 2: "ships", 3: "structures", 4: "vehicles", 5: "samsites", 6: "aaasites"}
## SAM ring radius (world units) by type code (class 8).
const SAM_RING := {290: 37080.0, 340: 37080.0, 300: 16686.0, 320: 22248.0}

const Img := preload("res://util/img.gd")
const MissionRuntime := preload("res://mission/mission_runtime.gd")

static var _map_cache := {}

var fe: Control
var zoom := 1.0
var scroll := Vector2.ZERO  # top-left of the view in map units
var layers := {"waypoint": true, "text": true, "grid": true}
var map_name := "82"
var map_canvas: Control
var overlay: Control
var windows: Control
var brief_window: Control
var link_windows := {}  # brl type -> window
var mission_id := -1
## Units shown on the map: {pos (map units), klass, side, heading, leader, flight, type, art}.
var units: Array = []
## Flights by number: {members: [unit index], points: [map units], leader: unit index}.
var flights := {}
var mission_title := ""
var mission_clock := ""
var selected := -1  # unit index
var sel_textures := {}
var drag_wp := -1  # waypoint of the selected flight being dragged
var pressed_arrow := ""
var dragging := -1  # axis of the thumb being dragged
var drag_offset := 0.0


func setup(front_end: Control, mission: int) -> void:
	fe = front_end
	mission_id = mission
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Missions 110–119 use the 1967 map, 120–129 the 1973 map (FUN_004ffba0).
	if mission_id >= 110 and mission_id <= 119:
		map_name = "67"
	elif mission_id >= 120 and mission_id <= 129:
		map_name = "73"
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(clip)
	map_canvas = preload("res://menu/tsd_map.gd").new()
	map_canvas.tsd = self
	clip.add_child(map_canvas)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	clip.add_child(overlay)
	windows = Control.new()
	windows.clip_contents = true
	windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(windows)
	map_canvas.load_maps(_map(map_name), _map("grid"), _map("text"))
	_load_units()


## World (mission) coordinates -> TSD map units (FUN_00500ec0).
static func world_to_map(x: float, y: float) -> Vector2:
	return Vector2((x + WORLD_X_SHIFT) * MAP_SIZE.x * MAP_X_FACTOR / WORLD_W, MAP_SIZE.y - (y + WORLD_Y_SHIFT) * MAP_SIZE.y / WORLD_H)


## Inverse (FUN_00500f70).
static func map_to_world(m: Vector2) -> Vector2:
	return Vector2(m.x * WORLD_W / (MAP_SIZE.x * MAP_X_FACTOR) - WORLD_X_SHIFT, (MAP_SIZE.y - m.y) * WORLD_H / MAP_SIZE.y - WORLD_Y_SHIFT)


## The selected flight's route in world coordinates (what the TSD may have changed), for the flight.
func selected_route() -> Array:
	var n := default_flight()
	if not flights.has(n):
		return []
	var out := []
	for p in flights[n].points:
		out.append(map_to_world(p))
	return out


## What the spawner creates from the mission and its base missions (docs/front-end.md §8.1):
## entities whose bdb class has an icon, placed in the world (the unused player slots sit at (-1, -1);
## as in mission_runtime.gd only both coordinates negative means unplaced).
func _load_units() -> void:
	var bdbs := {}
	var first := true
	for file in MissionRuntime.mission_files(mission_id):
		var m: Dictionary = file.data
		if m.is_empty():
			continue
		var bdb_name := String(m.get("bdb", "")).to_lower()
		if not bdbs.has(bdb_name):
			bdbs[bdb_name] = MissionRuntime.bdb_objects(MissionRuntime.load_bdb(m))
		var objects: Dictionary = bdbs[bdb_name]
		if first:
			var misc: Dictionary = m.misc.items[0]
			mission_title = misc.get("0x44c", "")
			var t := int(misc.get("0x460", 0.0))
			mission_clock = "%02d:%02d:%02d" % [t / 3600, t / 60 % 60, t % 60]
		var by_id := {}
		for e in m.entities.items:
			if not (e is Dictionary) or (float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0):
				continue
			var obj: Dictionary = objects.get(int(e.get("0x2c6", -1)), {})
			var klass: int = ICON_CLASS.get(int(obj.get("0x5aa", -1)), 0)
			if klass == 0 or int(e.get("0x35c", 0)) == 0:
				continue
			var type := int(obj.get("0x5b4", -1))
			var u := {
				"pos": world_to_map(float(e["0x2e4"]), float(e["0x2ee"])),
				"klass": klass, "side": int(e.get("0x2d0", 0)), "heading": float(e.get("0x302", 0)),
				"type": type, "cls": int(obj.get("0x5aa", -1)), "leader": false, "flight": 0,
				"airport": type == 450,
			}
			by_id[int(e["0x1e"])] = units.size()
			units.append(u)
		for f in m.formations.items:
			var n := int(f.get("0x3f2", 0))
			if n == -1:
				n = 8
			if n <= 0 or not first:
				continue
			var members: Array = []
			for mem in f.get("members", []):
				var id := int(mem.get("0x41a", -1))
				members.append(by_id.get(id, -1))
			var alive := members.filter(func(i): return i >= 0)
			if alive.is_empty():
				continue
			var leader: int = alive[0]
			var pts: Array = []
			for p in f.get("points", []):
				pts.append(world_to_map(float(p[1]), float(p[2])))
			flights[n] = {"members": alive, "points": pts, "leader": leader}
			units[leader].leader = true
			for i in alive:
				units[i].flight = n
		first = false
	# The default selection is the flight holding the player object (FUN_005bcd70), which is the
	# leader of flight 1, else 2, 3, 4 (FUN_004bb439; mission_runtime.gd player_flight()).
	for n in [1, 2, 3, 4]:
		if flights.has(n):
			select_flight(n)
			break


## Flight number the player starts in (0 = none).
func default_flight() -> int:
	return int(units[selected].flight) if selected >= 0 else 0


## Alpha..Delta enable rule (FUN_00505820).
func flight_enabled(n: int) -> bool:
	if not flights.has(n) or n > 4:
		return false
	var leader: Dictionary = units[flights[n].leader]
	return int(leader.type) in FLYABLE_TYPES and int(leader.side) == 1


## Selects a flight: its leader becomes the selected unit and the view centres on it.
func select_flight(n: int) -> void:
	if not flights.has(n):
		return
	selected = flights[n].leader
	centre_on(units[selected].pos)


func _map(name: String) -> Dictionary:
	if not _map_cache.has(name):
		var path: String = fe.dir.path_join("emf/%s.json" % name)
		_map_cache[name] = Settings.load_json(path)
	return _map_cache[name]


func _process(_delta: float) -> void:
	var client: Rect2 = fe._rect(CLIENT)
	for c in [get_child(0), windows]:
		c.position = client.position
		c.size = client.size
	map_canvas.position = -scroll * zoom * fe._scale()
	map_canvas.size = MAP_SIZE * zoom * fe._scale()
	overlay.size = client.size
	overlay.queue_redraw()
	queue_redraw()


# --- view ---------------------------------------------------------------------------------

func _view_size() -> Vector2:
	return CLIENT.size / zoom


func _clamp_scroll() -> void:
	scroll = scroll.clamp(Vector2.ZERO, (MAP_SIZE - _view_size()).max(Vector2.ZERO))


## Zoom, then centre the selected unit, or keep the view centre (5032d0).
func zoom_by(factor: float) -> void:
	var centre: Vector2 = units[selected].pos if selected >= 0 else scroll + _view_size() / 2
	var new_zoom := clampf(zoom * factor, 1.0, ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom):
		return
	zoom = new_zoom
	centre_on(centre)
	map_canvas.queue_redraw()


func can_zoom_in() -> bool:
	return zoom < ZOOM_MAX - 0.001


func can_zoom_out() -> bool:
	return zoom > 1.001


func centre_on(map_point: Vector2) -> void:
	scroll = map_point - _view_size() / 2
	_clamp_scroll()


func set_layer(name: String, on: bool) -> void:
	layers[name] = on
	map_canvas.queue_redraw()


# --- briefing window (§6) -------------------------------------------------------------------

func _briefing() -> Dictionary:
	return fe.briefings.get("missions", {}).get(str(mission_id), {})


func has_briefing() -> bool:
	return not _briefing().is_empty()


func open_briefing(open: bool) -> void:
	if not open:
		for w in [brief_window] + link_windows.values():
			if is_instance_valid(w):
				w.queue_free()
		brief_window = null
		link_windows.clear()
		return
	if is_instance_valid(brief_window):
		return
	var b := _briefing()
	if b.is_empty():
		return
	brief_window = _new_window(Rect2(0, 0, floor(2 * CLIENT.size.x / 3), CLIENT.size.y), "framewnd/brief_t.png")
	brief_window.set_text(_text_of(b), _link_names(b))
	brief_window.link_clicked.connect(_on_link.bind(b))
	brief_window.closed.connect(func(): fe.tsd_briefing_closed())


func _new_window(r: Rect2, tab: String) -> Control:
	var w := preload("res://menu/frame_window.gd").new()
	w.setup(fe, CLIENT.position, r)
	w.tab_art = tab
	w.bounds = Rect2(Vector2.ZERO, CLIENT.size)
	windows.add_child(w)
	return w


## Briefing text in the current language; "<header>" becomes "<rank> <callsign>" (DAT_0083b820 /
## DAT_0083b834); no pilot records yet: a new pilot's rank.
func _text_of(entry: Dictionary) -> String:
	var lang := "he" if fe._he() else "en"
	# null = no translation (briefings.json has "he": null where the Hebrew pack lacks the file).
	var texts: Dictionary = entry.get("text", {})
	var text: String = texts.get(lang) if texts.get(lang) != null else ""
	if text == "":
		text = texts.get("en") if texts.get("en") != null else ""
	var re := RegEx.create_from_string("(?i)<header>")
	return re.sub(text, "Second Lieutenant", false)


func _link_names(entry: Dictionary) -> Array:
	var lang := "he" if fe._he() else "en"
	var names := []
	for e in entry.get("entries", []):
		var t = e.title.get(lang)
		names.append(String(t if t != null else e.title.en).to_lower())
	return names


## A link opens a window by its .brl type (FUN_00502cd0); an open slot is reused.
func _on_link(name: String, entry: Dictionary) -> void:
	var names := _link_names(entry)
	var i := names.find(name)
	if i < 0:
		return
	var link: Dictionary = entry.entries[i]
	var kind := int(link.get("type", 0))
	var file := String(link.file)
	var stem := file.get_file().get_basename().to_lower()
	var w: Control = link_windows.get(kind)
	var W := CLIENT.size.x
	var H := CLIENT.size.y
	match kind:
		0:
			var lesson: Dictionary = fe.briefings.get("lessons", {}).get(stem, {})
			if lesson.is_empty():
				return
			if not is_instance_valid(w):
				w = _new_window(Rect2(floor(W / 3), floor(H / 2), floor(2 * W / 3), floor(H / 2)), "framewnd/brief_t.png")
				link_windows[kind] = w
				w.link_clicked.connect(func(n): _on_link(n, lesson))
			w.set_text(_text_of(lesson), _link_names(lesson))
		3:
			var tex: Texture2D = fe.briefing_image(stem)
			if tex == null:
				return
			if not is_instance_valid(w):
				w = _new_window(Rect2(floor(W / 2), 0, floor(W / 2), floor(H / 2)), "")
				w.has_max = false
				link_windows[kind] = w
			w.set_image(tex)
		_:
			# 2 = 3D model window (obj_t), 5 = target window (targ_t): not built yet.
			return
	windows.move_child(w, -1)


# --- drawing ------------------------------------------------------------------------------

func _draw() -> void:
	# Each bar: track, arrows at the ends, thumb between them.
	for axis in 2:
		var bar: Rect2 = BARS[axis]
		var a: String = BAR_ART[axis]
		fe_blit("tsd/%sscroll.png" % a, bar.position)
		fe_blit("tsd/%sslupb_%d.png" % [a, 1 if pressed_arrow == BAR_ARROWS[axis][0] else 0], bar.position)
		fe_blit("tsd/%ssldownb_%d.png" % [a, 1 if pressed_arrow == BAR_ARROWS[axis][1] else 0], _along(bar.position, axis, bar.end[axis] - BAR_DOWN[axis]))
		fe_blit("tsd/%sslider.png" % a, _along(bar.position, axis, _thumb(axis)))


func fe_blit(path: String, pos: Vector2) -> void:
	var t: Texture2D = fe._tex(path)
	if t != null:
		draw_texture_rect(t, fe._rect(Rect2(pos, fe._art_size(t))), false)


## `v` with its `axis` component replaced by `value`.
static func _along(v: Vector2, axis: int, value: float) -> Vector2:
	v[axis] = value
	return v


## Thumb travel along a bar (screen coordinates of the thumb's start).
func _thumb_range(axis: int) -> Vector2:
	var bar: Rect2 = BARS[axis]
	return Vector2(bar.position[axis] + BAR_UP[axis], bar.end[axis] - BAR_DOWN[axis] - BAR_THUMB[axis])


func _thumb(axis: int) -> float:
	var r := _thumb_range(axis)
	var room := MAP_SIZE[axis] - _view_size()[axis]
	return r.x if room <= 0.0 else lerpf(r.x, r.y, scroll[axis] / room)


## Labels of text.emf: re-issued at their map position without scaling (501060); then units,
## waypoints and the mission title / clock.
func _draw_overlay() -> void:
	var s: float = fe._scale()
	if layers.text:
		for op in map_canvas.text_ops:
			var pos: Vector2 = (op.pos - scroll) * zoom * s
			var px := int(round(op.px * s))
			if px < 1:
				continue
			overlay.draw_string(fe.font, pos, op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, op.color)
	_draw_units(s)
	if layers.waypoint:
		for n in [1, 2, 3, 4]:
			if flights.has(n) and n != default_flight():
				_draw_route(n, s)
		if flights.has(default_flight()):
			_draw_route(default_flight(), s)
	# Title and clock: Arial p10 weight 600, white (the second line is always empty).
	var fs := int(round(11 * s))
	var line_h: float = fe.font_bold.get_height(fs) / s
	overlay.draw_string(fe.font_bold, Vector2(4, 4) * s + Vector2(0, fe.font_bold.get_ascent(fs)), mission_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	overlay.draw_string(fe.font_bold, Vector2(14, line_h + 6) * s + Vector2(0, fe.font_bold.get_ascent(fs)), mission_clock, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## Map units -> client pixels (640 space).
func _to_client(m: Vector2) -> Vector2:
	return (m - scroll) * zoom


func _unit_visible(u: Dictionary) -> bool:
	var filter: String = "airports" if u.airport else FILTERS[u.klass]
	return fe.tsd_checks.get("%s%d" % [filter, 1 if u.side == 1 else 2], true)


## Unit icons (FUN_00504ea0), centred on the unit; plain copies of the icon cell.
func _draw_units(s: float) -> void:
	for i in units.size():
		var u: Dictionary = units[i]
		if not _unit_visible(u):
			continue
		var c := _to_client(u.pos)
		var art: String = "icairport" if u.airport else ICON_ART[u.klass]
		var cell: Rect2
		if u.klass == 1:
			var row := 1 if u.side > 1 else (0 if u.leader else 2)
			var col := (int(fposmod(u.heading, 360.0)) / 45) % 8
			cell = Rect2(col * 27, row * 21, 27, 21)
		else:
			cell = Rect2(0, (1 if u.side > 1 else 0) * 17, 27, 17)
		var top_left := (c - (cell.size / 2).floor()).floor()
		var t: Texture2D = fe._tex("tsd/%s.png" % art)
		if t != null:
			var a: float = fe.art_scale
			overlay.draw_texture_rect_region(t, Rect2(top_left * s, cell.size * s), Rect2(cell.position * a, cell.size * a))
		if u.cls == 8 and SAM_RING.has(u.type):
			var r := floorf(floorf(SAM_RING[u.type]) * MAP_SIZE.x / WORLD_W) * zoom
			overlay.draw_arc(c * s, r * s, 0, TAU, 64, Color.WHITE, maxf(1.0, s), true)
		if u.klass == 1 and u.flight >= 1 and u.flight <= 4:
			overlay.draw_rect(Rect2((top_left - Vector2(2, 2)) * s, (cell.size + Vector2(4, 4)) * s), FLIGHT_COLORS[u.flight - 1], false, 2 * s)
	if selected >= 0 and _unit_visible(units[selected]):
		var u: Dictionary = units[selected]
		var t := _selection_texture("icselair" if u.klass == 1 else "icselveh")
		if t != null:
			var sz: Vector2 = Vector2(t.get_width(), t.get_height()) / fe.art_scale
			overlay.draw_texture_rect(t, Rect2(((_to_client(u.pos) - (sz / 2).floor()).floor()) * s, sz * s), false)


## Selection art: a masked sprite (top half sprite, bottom half its AND mask).
func _selection_texture(name: String) -> Texture2D:
	if sel_textures.has(name):
		return sel_textures[name]
	var src: Texture2D = fe._tex("tsd/%s.png" % name)
	if src == null:
		return null
	sel_textures[name] = ImageTexture.create_from_image(Img.masked_sprite(src.get_image()))
	return sel_textures[name]


## A flight's route: numbered circles (r 10 px) in the flight colour, joined when > 20 px apart.
func _draw_route(n: int, s: float) -> void:
	var color: Color = FLIGHT_COLORS[n - 1]
	var pts: Array = flights[n].points
	var fs := int(round(11 * s))
	for i in pts.size():
		var c := _to_client(pts[i])
		if i > 0:
			var prev := _to_client(pts[i - 1])
			if prev.distance_to(c) > 20:
				overlay.draw_line(prev * s, c * s, color, 2 * s, true)
	for i in pts.size():
		var c := _to_client(pts[i])
		overlay.draw_circle(c * s, 10 * s, color)
		overlay.draw_string(fe.font_bold, (c + Vector2(0, 4)) * s - Vector2(20 * s, 0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 40 * s, fs, Color.WHITE)


# --- input ----------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var p: Vector2 = fe._to_menu(event.position)
	if _map_input(event, p - CLIENT.position):
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for axis in [1, 0]:
				if BARS[axis].has_point(p):
					_bar_press(p, axis)
					accept_event()
					break
		elif pressed_arrow != "" or dragging >= 0:
			pressed_arrow = ""
			dragging = -1
			accept_event()
	elif event is InputEventMouseMotion and dragging >= 0:
		var r := _thumb_range(dragging)
		scroll[dragging] = clampf(inverse_lerp(r.x, r.y, p[dragging] - drag_offset), 0, 1) * maxf(0, MAP_SIZE[dragging] - _view_size()[dragging])
		accept_event()


## Map clicks (client coordinates): drag a waypoint of the selected flight (within 10 px,
## FUN_00504dd0); double-click an own flight leader of a flyable type to fly it (FUN_00501ef0).
func _map_input(event: InputEvent, c: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, CLIENT.size).has_point(c) and drag_wp < 0:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if drag_wp >= 0:
				drag_wp = -1
				return true
			return false
		if event.double_click:
			for i in units.size():
				var u: Dictionary = units[i]
				if u.klass == 1 and u.leader and int(u.flight) in [1, 2, 3, 4] and flight_enabled(int(u.flight)) \
						and _to_client(u.pos).distance_to(c) <= 14:
					fe.tsd_fly_flight(int(u.flight))
					return true
		var n := default_flight()
		if layers.waypoint and flights.has(n):
			var pts: Array = flights[n].points
			for i in pts.size():
				if _to_client(pts[i]).distance_to(c) <= 10:
					drag_wp = i
					return true
	elif event is InputEventMouseMotion and drag_wp >= 0:
		var n := default_flight()
		if flights.has(n):
			flights[n].points[drag_wp] = (c.clamp(Vector2.ZERO, CLIENT.size) / zoom + scroll).clamp(Vector2.ZERO, MAP_SIZE)
		return true
	return false


func _bar_press(p: Vector2, axis: int) -> void:
	var bar: Rect2 = BARS[axis]
	var t := _thumb(axis)
	if p[axis] < bar.position[axis] + BAR_UP[axis]:
		pressed_arrow = BAR_ARROWS[axis][0]
		scroll[axis] -= ARROW_STEP / zoom
	elif p[axis] >= bar.end[axis] - BAR_DOWN[axis]:
		pressed_arrow = BAR_ARROWS[axis][1]
		scroll[axis] += ARROW_STEP / zoom
	elif p[axis] >= t and p[axis] < t + BAR_THUMB[axis]:
		dragging = axis
		drag_offset = p[axis] - t
	else:
		scroll[axis] += _view_size()[axis] * (1 if p[axis] > t else -1)
	_clamp_scroll()
