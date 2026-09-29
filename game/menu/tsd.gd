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
## Scroll arrow step in map pixels (UNCERTAIN until decoded).
const ARROW_STEP := 20.0

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


## Zoom keeping a map point fixed on screen (the selected unit, or the view centre; 5019b0).
func zoom_by(factor: float) -> void:
	var fixed := scroll + _view_size() / 2
	var new_zoom := clampf(zoom * factor, 1.0, ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom):
		return
	var screen_offset := (fixed - scroll) * zoom
	zoom = new_zoom
	scroll = fixed - screen_offset / zoom
	_clamp_scroll()
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


## Labels of text.emf: re-issued at their map position without scaling (4ff740).
func _draw_overlay() -> void:
	var s: float = fe._scale()
	if layers.text:
		for op in map_canvas.text_ops:
			var pos: Vector2 = (op.pos - scroll) * zoom * s
			var px := int(round(op.px * s))
			if px < 1:
				continue
			overlay.draw_string(fe.font, pos, op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, op.color)


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
