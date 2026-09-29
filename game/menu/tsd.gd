# The pre-flight Tactical Situation Display (screen 0x1e, docs/front-end.md §6, §8): the EMF
# vector map with grid / text overlays, units and waypoints, zoom and scrollbars, and the
# briefing window with its link windows. Panels and buttons are drawn by the front end, which
# forwards TSD button presses here.
extends Control

## Content window (TSD client) in 640x480 space.
const CLIENT := Rect2(155, 42, 453, 357)
## Map extent at zoom 1 (0x6040e0/e4).
const MAP_SIZE := Vector2(454, 590)
const ZOOM_STEP := 1.5
const ZOOM_MAX := 32.0
## Scrollbars (screen coordinates) and their art sizes.
const VBAR := Rect2(608, 42, 10, 356)
const HBAR := Rect2(146, 399, 462, 10)
const V_UP := Vector2(10, 23)
const V_DOWN := Vector2(10, 21)
const V_THUMB := Vector2(10, 75)
const H_UP := Vector2(24, 10)
const H_DOWN := Vector2(21, 10)
const H_THUMB := Vector2(74, 10)
## Scroll arrow step: 5 map units (round(5·z) px).
const ARROW_STEP := 5.0
## World -> map (FUN_004ff5a0): X shift = DataXShiftPR, Y shift, width / height of the world.
const WORLD_X_SHIFT := 166850.0
const WORLD_Y_SHIFT := 21144.0
const WORLD_W := 819200.0
const WORLD_H := 1064960.0
const MAP_X_FACTOR := 1.0071394
## Flight colours 1..4 (Alpha..Delta), 5-6 white.
const FLIGHT_COLORS := [Color8(226, 0, 180), Color8(4, 178, 39), Color8(0, 82, 250), Color8(215, 134, 1), Color.WHITE, Color.WHITE]
const FLIGHT_NAMES := ["alpha", "bravo", "charlie", "delta"]
## Flyable type codes (FUN_00503e50).
const FLYABLE_TYPES := [100, 110, 120, 130, 140, 160, 180, 190, 200]
## bdb object class (0x5aa) -> icon class: 1 aircraft, 2 ship, 3 structure, 4 vehicle, 5 SAM, 6 AAA.
const ICON_CLASS := {2: 1, 3: 1, 0x1c: 1, 0xf: 2, 0x10: 2, 0xc: 3, 0xd: 3, 0x1d: 3, 0x1e: 3, 5: 4, 6: 4, 8: 5, 9: 5, 10: 6}
const ICON_ART := {1: "icair", 2: "icshp", 3: "icstr", 4: "icveh", 5: "icsam", 6: "icaaa"}
const FILTERS := {1: "aircrafts", 2: "ships", 3: "structures", 4: "vehicles", 5: "samsites", 6: "aaasites"}
## SAM ring radius (world units) by type code (class 8).
const SAM_RING := {290: 37080.0, 340: 37080.0, 300: 16686.0, 320: 22248.0}

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
var pressed_arrow := ""
var dragging := ""  # "v" / "h" while a thumb is dragged
var drag_offset := 0.0


func setup(front_end: Control, mission: int) -> void:
	fe = front_end
	mission_id = mission
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Missions 110–119 use the 1967 map, 120–129 the 1973 map (FUN_004fe280).
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


## World (mission) coordinates -> TSD map units (FUN_004ff5a0).
static func world_to_map(x: float, y: float) -> Vector2:
	return Vector2((x + WORLD_X_SHIFT) * MAP_SIZE.x * MAP_X_FACTOR / WORLD_W, MAP_SIZE.y - (y + WORLD_Y_SHIFT) * MAP_SIZE.y / WORLD_H)


## What the spawner creates from the mission and its base missions (docs/front-end.md §8.1):
## entities whose bdb class has an icon, placed in the world (the unused player slots sit at -1).
func _load_units() -> void:
	var dir := Settings.assets_dir().path_join("converted/missions")
	var list = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("missionlist.json")))
	if not (list is Dictionary) or not list.has(str(mission_id)):
		return
	var bdbs := {}
	var player_unit := -1
	var first := true
	for name in list[str(mission_id)]:
		var m = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(String(name) + ".json")))
		if not (m is Dictionary):
			continue
		var bdb_name := String(m.get("bdb", "")).to_lower()
		if not bdbs.has(bdb_name):
			var b = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(bdb_name + ".json")))
			var objects := {}
			if b is Dictionary:
				for o in b.objects.items:
					objects[int(o["0x1e"])] = o
			bdbs[bdb_name] = objects
		var objects: Dictionary = bdbs[bdb_name]
		if first:
			var misc: Dictionary = m.misc.items[0]
			mission_title = misc.get("0x44c", "")
			var t := int(misc.get("0x460", 0.0))
			mission_clock = "%02d:%02d:%02d" % [t / 3600, t / 60 % 60, t % 60]
		var by_id := {}
		for e in m.entities.items:
			if not (e is Dictionary) or int(e.get("0x2e4", -1)) < 0 or int(e.get("0x2ee", -1)) < 0:
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
			if first and String(e.get("0x2bc", "")) == "Player1":
				player_unit = units.size()
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
	# The player's flight (the formation holding Player1) is the default selection.
	if player_unit >= 0 and units[player_unit].flight > 0:
		select_flight(units[player_unit].flight)


## Flight number the player starts in (0 = none).
func default_flight() -> int:
	return int(units[selected].flight) if selected >= 0 else 0


## Alpha..Delta enable rule (FUN_00503f40).
func flight_enabled(n: int) -> bool:
	if not flights.has(n) or n > 4:
		return false
	var leader: Dictionary = units[flights[n].leader]
	return int(leader.type) in FLYABLE_TYPES and int(leader.side) == 1


func flight_exists(n: int) -> bool:
	return flights.has(n)


## Selects a flight: its leader becomes the selected unit and the view centres on it.
func select_flight(n: int) -> void:
	if not flights.has(n):
		return
	selected = flights[n].leader
	centre_on(units[selected].pos)


func _map(name: String) -> Dictionary:
	if not _map_cache.has(name):
		var path: String = fe.dir.path_join("emf/%s.json" % name)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		_map_cache[name] = data if data is Dictionary else {}
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


## Zoom, then centre the selected unit, or keep the view centre (5019b0).
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


## Briefing text in the current language; "<header>" becomes "<rank> <callsign>".
func _text_of(entry: Dictionary) -> String:
	var lang := "he" if fe._he() else "en"
	var text: String = entry.get("text", {}).get(lang, "")
	if text == "":
		text = entry.get("text", {}).get("en", "")
	var re := RegEx.create_from_string("(?i)<header>")
	return re.sub(text, fe.pilot_header(), false)


func _link_names(entry: Dictionary) -> Array:
	var lang := "he" if fe._he() else "en"
	var names := []
	for e in entry.get("entries", []):
		var t = e.title.get(lang)
		names.append(String(t if t != null else e.title.en).to_lower())
	return names


## A link opens a window by its .brl type (FUN_005013b0); an open slot is reused.
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
	# Vertical bar: track, arrows at the ends, thumb between them.
	var vt := _v_thumb()
	fe_blit("tsd/vscroll.png", VBAR.position)
	fe_blit("tsd/vslupb_%d.png" % (1 if pressed_arrow == "up" else 0), VBAR.position)
	fe_blit("tsd/vsldownb_%d.png" % (1 if pressed_arrow == "down" else 0), Vector2(VBAR.position.x, VBAR.end.y - V_DOWN.y))
	fe_blit("tsd/vslider.png", Vector2(VBAR.position.x, vt))
	var ht := _h_thumb()
	fe_blit("tsd/hscroll.png", HBAR.position)
	fe_blit("tsd/hslupb_%d.png" % (1 if pressed_arrow == "left" else 0), HBAR.position)
	fe_blit("tsd/hsldownb_%d.png" % (1 if pressed_arrow == "right" else 0), Vector2(HBAR.end.x - H_DOWN.x, HBAR.position.y))
	fe_blit("tsd/hslider.png", Vector2(ht, HBAR.position.y))


func fe_blit(path: String, pos: Vector2) -> void:
	var t: Texture2D = fe._tex(path)
	if t != null:
		draw_texture_rect(t, fe._rect(Rect2(pos, fe._art_size(t))), false)


func _v_thumb() -> float:
	var lo := VBAR.position.y + V_UP.y
	var hi := VBAR.end.y - V_DOWN.y - V_THUMB.y
	var room := MAP_SIZE.y - _view_size().y
	return lo if room <= 0.0 else lerpf(lo, hi, scroll.y / room)


func _h_thumb() -> float:
	var lo := HBAR.position.x + H_UP.x
	var hi := HBAR.end.x - H_DOWN.x - H_THUMB.x
	var room := MAP_SIZE.x - _view_size().x
	return lo if room <= 0.0 else lerpf(lo, hi, scroll.x / room)


## Labels of text.emf: re-issued at their map position without scaling (4ff740); then units,
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


## Unit icons (FUN_005035c0), centred on the unit; plain copies of the icon cell.
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


## Selection art: top half is the sprite, bottom half its AND mask (black = sprite).
func _selection_texture(name: String) -> Texture2D:
	if sel_textures.has(name):
		return sel_textures[name]
	var src: Texture2D = fe._tex("tsd/%s.png" % name)
	if src == null:
		return null
	var img := src.get_image()
	img.decompress()
	var h := img.get_height() / 2
	var out := Image.create(img.get_width(), h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var m := img.get_pixel(x, y + h)
			out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0 - m.get_luminance()))
	sel_textures[name] = ImageTexture.create_from_image(out)
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if VBAR.has_point(p):
				_bar_press(p, true)
				accept_event()
			elif HBAR.has_point(p):
				_bar_press(p, false)
				accept_event()
		elif pressed_arrow != "" or dragging != "":
			pressed_arrow = ""
			dragging = ""
			accept_event()
	elif event is InputEventMouseMotion and dragging != "":
		if dragging == "v":
			var lo := VBAR.position.y + V_UP.y
			var hi := VBAR.end.y - V_DOWN.y - V_THUMB.y
			scroll.y = clampf(inverse_lerp(lo, hi, p.y - drag_offset), 0, 1) * maxf(0, MAP_SIZE.y - _view_size().y)
		else:
			var lo := HBAR.position.x + H_UP.x
			var hi := HBAR.end.x - H_DOWN.x - H_THUMB.x
			scroll.x = clampf(inverse_lerp(lo, hi, p.x - drag_offset), 0, 1) * maxf(0, MAP_SIZE.x - _view_size().x)
		accept_event()


func _bar_press(p: Vector2, vertical: bool) -> void:
	if vertical:
		var t := _v_thumb()
		if p.y < VBAR.position.y + V_UP.y:
			pressed_arrow = "up"
			scroll.y -= ARROW_STEP / zoom
		elif p.y >= VBAR.end.y - V_DOWN.y:
			pressed_arrow = "down"
			scroll.y += ARROW_STEP / zoom
		elif p.y >= t and p.y < t + V_THUMB.y:
			dragging = "v"
			drag_offset = p.y - t
		else:
			scroll.y += _view_size().y * (1 if p.y > t else -1)
	else:
		var t := _h_thumb()
		if p.x < HBAR.position.x + H_UP.x:
			pressed_arrow = "left"
			scroll.x -= ARROW_STEP / zoom
		elif p.x >= HBAR.end.x - H_DOWN.x:
			pressed_arrow = "right"
			scroll.x += ARROW_STEP / zoom
		elif p.x >= t and p.x < t + H_THUMB.x:
			dragging = "h"
			drag_offset = p.x - t
		else:
			scroll.x += _view_size().x * (1 if p.x > t else -1)
	_clamp_scroll()
