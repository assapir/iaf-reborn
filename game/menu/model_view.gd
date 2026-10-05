# The menus' 3D viewer (FUN_0050f50b, docs/front-end.md §11): one `_h` model loaded ×10 (FUN_00402370's 10.0) at
# the origin in front of the clear colour, the camera orbiting the look-at point (the model + the .cp height) on the
# keyboard only — arrows 2°, numpad +/− 2 units between the .cp distance and 4×; a click gives the focus — and the
# 3 px mv* bevel over the image edges. Geometry is set by the owner (frame_window.gd).
extends Control

const Gltf := preload("res://util/gltf.gd")
## Clear colour bytes c9 e4 e4 (FUN_00407ee0; RGB(201,228,228) taken, UNCERTAIN vs its BGR swap).
const CLEAR := Color8(201, 228, 228)
const SCALE := 10.0
const STEP_DEG := 2.0
const STEP_DIST := 2.0
const PITCH_MIN := -80.0
const PITCH_MAX := -10.0

var fe: Control
var pitch := -10.0
var yaw := 120.0
var d := 0.0
var dist := 0.0
var height := 0.0
var _cam: Camera3D
var _vp: SubViewport


## Loads `path` (under converted/objects) with the .cp `cp` = [dist, height] (null: from the model's bounds,
## dist = |extents|, height = the extents' z / 2, UNCERTAIN). False when the model is missing.
func setup(front_end: Control, path: String, cp) -> bool:
	fe = front_end
	var model = Gltf.object(path)
	if model == null:
		return false
	focus_mode = Control.FOCUS_CLICK
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	_vp = vp
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = CLEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.45)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	vp.add_child(sun)
	var node := Gltf.instance(model)
	node.scale = Vector3.ONE * SCALE
	vp.add_child(node)
	if cp is Array and cp.size() >= 2:
		dist = float(cp[0])
		height = float(cp[1])
	else:
		var box := Gltf.model_aabb(node, Gltf.MESH_SPACE)
		dist = box.size.length() * SCALE
		height = box.size.y * SCALE / 2.0
	d = 1.2 * dist
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 50.0
	_cam.near = 4.0
	_cam.far = 22000.0
	vp.add_child(_cam)
	_place()
	return true


## eye = look-at − (cos p · sin y, cos p · cos y) · d horizontally (east, north), + sin(−p) · d up (FUN_00510057).
func _place() -> void:
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	var at := Vector3(0, height, 0)
	_cam.look_at_from_position(at + Vector3(-cos(p) * sin(y) * d, sin(-p) * d, cos(p) * cos(y) * d), at)  # Godot z = south


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
		accept_event()
	elif event is InputEventKey and event.pressed and has_focus():
		match event.keycode:
			KEY_LEFT: yaw += STEP_DEG
			KEY_RIGHT: yaw -= STEP_DEG
			KEY_UP: if pitch > PITCH_MIN: pitch -= STEP_DEG
			KEY_DOWN: if pitch < PITCH_MAX: pitch += STEP_DEG
			KEY_KP_ADD: if d > dist: d -= STEP_DIST
			KEY_KP_SUBTRACT: if d < 4.0 * dist: d += STEP_DIST
			_: return
		_place()
		accept_event()


## The image, then the bevel (§11): mvBrdrL / T / R / B and the corners, 3 px over the image edges.
func _draw() -> void:
	if _vp != null:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	var s: float = fe._scale()
	var a: float = fe.art_scale
	var w := size.x / s
	var h := size.y / s
	for e in [["mvbrdrl", Rect2(0, 0, 3, h), Vector2.ZERO], ["mvbrdrt", Rect2(0, 0, w, 3), Vector2.ZERO],
			["mvbrdrr", Rect2(0, 0, 3, h), Vector2(w - 3, 0)], ["mvbrdrb", Rect2(0, 0, w, 3), Vector2(0, h - 3)],
			["mvcrnrlt", Rect2(0, 0, 3, 3), Vector2.ZERO], ["mvcrnrrt", Rect2(0, 0, 3, 3), Vector2(w - 3, 0)],
			["mvcrnrlb", Rect2(0, 0, 3, 3), Vector2(0, h - 3)], ["mvcrnrrb", Rect2(0, 0, 3, 3), Vector2(w - 3, h - 3)]]:
		var t: Texture2D = fe._tex("framewnd/%s.png" % e[0])
		if t != null:
			draw_texture_rect_region(t, Rect2(e[2] * s, e[1].size * s), Rect2(e[1].position * a, e[1].size * a))


func _process(_delta: float) -> void:
	if _vp != null and Vector2i(size) != _vp.size and size.x >= 1 and size.y >= 1:
		_vp.size = Vector2i(size)
	queue_redraw()
