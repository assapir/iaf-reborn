# Roads, Detailed (Preferences → Graphics → MORE → Roads; docs/rendering.md §1.8, docs/deviations.md §2):
# OpenStreetMap's roads (setup's road layer, docs/scenery.md §6) drawn on the ground near the camera, where the
# imagery is too coarse to show them, and with Night lights Detailed lamps along the lit roads (city_lights.gd,
# IafCityLights.set_road_lamps). The mask around the camera is made in Rust on a thread of its own
# (IafRoads.request_mask: a std thread, nothing for Godot's pool to wait for at quit); terrain.gdshader draws it.
# Ours: the original has only its imagery.
extends RefCounted

## A new mask is asked when the camera is this far (m) from the last one's centre. The mask is 4096 m across and
## the shader draws within FAR m of the camera: 2048 − MOVE ≥ FAR keeps the drawn disc on the mask.
const MOVE := 500.0
const FAR := 1500.0

static var _on := false
static var _asked := Vector2(INF, INF)
static var _pending := false
static var _tex: ImageTexture
## The marking mask (the lane markings and the rails): taken the frame after its road mask (one upload a frame), with
## its own rect: [north-west corner, side] (engine metres).
static var _marks: ImageTexture
static var _marks_rect := [Vector2(INF, INF), 0.0]
static var _marks_due := false
## The shown mask's north-west corner (engine metres), side (m), and the world origin its rect was set for.
static var _nw := Vector2(INF, INF)
static var _side := 0.0
static var _origin := Vector2(INF, INF)


static func dir() -> String:
	return Settings.assets_dir().path_join("converted/roads")


## Setup made the road layer.
static func available() -> bool:
	return FileAccess.file_exists(dir().path_join("main.bin"))


## Roads = Detailed with the road layer (opened once per process).
static func wanted() -> bool:
	return Settings.ground_roads == "detailed" and available() and IafRoads.open(dir())


## Roads = Detailed in this flight (apply): city_lights.gd follows it with the road lamps.
static func on() -> bool:
	return _on


## Applies Settings.ground_roads (a flight's start, or the Graphics page during a flight).
static func apply() -> void:
	_on = wanted()
	RenderingServer.global_shader_parameter_set("ground_roads", 1.0 if _on else 0.0)
	_asked = Vector2(INF, INF)
	_origin = Vector2(INF, INF)
	if not _on and _tex != null:
		RenderingServer.global_shader_parameter_set("road_mask", null)
		RenderingServer.global_shader_parameter_set("road_marks", null)
		_tex = null
		_marks = null
		_marks_due = false


## Per frame with the camera's position (scene frame): asks a mask when the camera moved MOVE m, shows a made one.
static func update_view(cam: Vector3, terrain: Node) -> void:
	if not _on or terrain == null:
		return
	var o: Vector2 = terrain.world_origin
	var here := o + Vector2(cam.x, -cam.z)
	if _marks_due:
		_marks_due = false
		_show_marks(IafRoads.take_marks())
	elif _pending:
		var m: Dictionary = IafRoads.take_mask()
		if not m.is_empty():
			_pending = false
			_marks_due = true
			_show(m)
	if not _pending and here.distance_to(_asked) > MOVE:
		_asked = here
		_pending = true
		IafRoads.request_mask(here)
	if o != _origin and _tex != null:
		_origin = o
		_set_rect("road_mask_rect", _nw, _side, o)
		if _marks != null:
			_set_rect("road_marks_rect", _marks_rect[0], _marks_rect[1], o)


## A mask's rect in the scene frame: Godot (x, z) from the world origin `o`: x = X − o.x, z = o.y − Y.
static func _set_rect(param: String, nw: Vector2, side: float, o: Vector2) -> void:
	RenderingServer.global_shader_parameter_set(param, Vector4(nw.x - o.x, o.y - nw.y, 1.0 / side, 0.0))


static func _show(m: Dictionary) -> void:
	var n := int(m.n)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RG8, m.bytes)
	if _tex == null or _tex.get_width() != n:
		_tex = ImageTexture.create_from_image(img)
		RenderingServer.global_shader_parameter_set("road_mask", _tex)
	else:
		_tex.update(img)
	_nw = Vector2(float(m.x0), float(m.y1))
	_side = n * float(m.m)
	_origin = Vector2(INF, INF)  # the rect is set by update_view


static func _show_marks(m: Dictionary) -> void:
	if m.is_empty():
		return
	var n := int(m.n)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, m.bytes)
	if _marks == null or _marks.get_width() != n:
		_marks = ImageTexture.create_from_image(img)
		RenderingServer.global_shader_parameter_set("road_marks", _marks)
	else:
		_marks.update(img)
	_marks_rect = [Vector2(float(m.x0), float(m.y1)), n * float(m.m)]
	_origin = Vector2(INF, INF)  # the rects are set by update_view
