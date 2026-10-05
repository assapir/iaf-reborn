# The menus' 3D viewer (FUN_0050f50b, docs/front-end.md §11): one `_h` model loaded ×10 (FUN_00402370's 10.0) at
# the origin in front of the clear colour, the camera orbiting the look-at point (the model + the .cp height) on the
# keyboard only — arrows 2°, numpad +/− 2 units between the .cp distance and 4×; a click gives the focus — and the
# 3 px mv* bevel over the image edges. Geometry is set by the owner (frame_window.gd).
# The target window (§10, setup_target): the mission world around a named object — the terrain and the mission's
# units near it — from the camera of the view strip's tab under the image: SATELLITE (7000 m straight down), ZOOM
# (2500 m) or UAV (300 m up, 45° down).
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
## Target window (§10): the strip's tab (0 satellite, 1 zoom, 2 UAV); -1 = the 3D-model window.
var tab := -1
const STRIP_H := 15.0
## The tabs' x ranges in the 480-wide tvw_off / tvw_on art (.rdata 0x60bf18).
const TABS := [Vector2(113, 197), Vector2(197, 281), Vector2(282, 368)]
## Camera height over the object per tab (.rdata 0x609b68 / ca4 / ca8).
const TAB_HEIGHT := [7000.0, 2500.0, 300.0]
var _terrain: Node3D
var _snap: Array = []  # ground units waiting for the terrain under them: [node, Vector3 scene position]
var _ground_known := false  # the target window's look-at stands on the loaded terrain


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


## The target window: `world` = the object (engine X east, Y north, altitude); `units` = the mission's units to draw
## [{path (under converted/objects), scale, heading (deg), world: Vector3, ground: bool}].
func setup_target(front_end: Control, world: Vector3, units: Array) -> void:
	fe = front_end
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true  # the 480-wide strip art is centred and cropped (x0 = −42 at w = 396)
	tab = 0
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = CLEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 150, 0)
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 50.0
	_cam.near = 4.0
	_cam.far = 30000.0
	_vp.add_child(_cam)
	# The terrain streams around the camera, the scene origin at the object (terrain.gd's world_origin).
	_terrain = load("res://terrain/terrain.gd").new()  # load: this script is preloaded before the autoloads in tests
	_terrain.world_origin = Vector2(world.x, world.y)
	_terrain.focus = _cam
	_terrain.view_range = _cam.far
	_vp.add_child(_terrain)
	for u in units:
		var model = Gltf.object(u.path)
		if model == null:
			continue
		var node := Gltf.instance(model)
		# The airbases' flat underlays are not drawn (the imagery shows the base, terrain_view.gd UNDERLAY_MAX_HEIGHT).
		if Gltf.model_aabb(node, Gltf.MESH_SPACE).size.y * float(u.scale) < 0.05:
			node.free()
			continue
		var p := Vector3(u.world.x - world.x, u.world.z, -(u.world.y - world.y))
		node.position = p
		node.rotation.y = -deg_to_rad(float(u.heading))
		node.scale = Vector3.ONE * float(u.scale)
		_vp.add_child(node)
		if u.ground:
			_snap.append([node, p])
	height = world.z
	_place()


## Tab `t` (a strip click, FUN_00510057): the camera of that view.
func set_tab(t: int) -> void:
	tab = t
	_place()


## eye = look-at − (cos p · sin y, cos p · cos y) · d horizontally (east, north), + sin(−p) · d up (FUN_00510057).
func _place() -> void:
	if tab >= 0:
		# Satellite / zoom (camera 0x14, FUN_005814c0): (x, y − 10, z + h) looking straight down; UAV (camera 0x15,
		# FUN_00581390): 300 m above, 45° down (UNCERTAIN: the orbit's bearing, taken from the south).
		var at := Vector3(0, height, 0)
		var h: float = TAB_HEIGHT[tab]
		var eye := at + (Vector3(0, h, h) if tab == 2 else Vector3(0, h, 10))
		_cam.look_at_from_position(eye, at)
		return
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	var at := Vector3(0, height, 0)
	_cam.look_at_from_position(at + Vector3(-cos(p) * sin(y) * d, sin(-p) * d, cos(p) * cos(y) * d), at)  # Godot z = south


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
		accept_event()
		# The view strip (FUN_0051e020): the three tab rects, the art centred at x0 = (w − 480) / 2.
		var q: Vector2 = event.position / fe._scale()
		if tab >= 0 and event.button_index == MOUSE_BUTTON_LEFT and q.y >= size.y / fe._scale() - STRIP_H:
			var x := q.x - floorf((size.x / fe._scale() - 480.0) / 2.0)
			for i in TABS.size():
				if x >= TABS[i].x and x < TABS[i].y:
					fe._play("buttonin")
					set_tab(i)
	elif event is InputEventKey and event.pressed and has_focus() and tab < 0:
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


## The image, then the bevel (§11): mvBrdrL / T / R / B and the corners, 3 px over the image edges; the target
## window's view strip under it.
func _draw() -> void:
	var s: float = fe._scale()
	var a: float = fe.art_scale
	var w := size.x / s
	var h := size.y / s - (STRIP_H if tab >= 0 else 0.0)
	if _vp != null:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, Vector2(w, h) * s), false)
	if tab >= 0:
		var x0 := floorf((w - 480.0) / 2.0)
		var off: Texture2D = fe._tex("framewnd/tvw_off.png")
		var on: Texture2D = fe._tex("framewnd/tvw_on.png")
		if off != null:
			draw_texture_rect_region(off, Rect2(Vector2(x0, h) * s, Vector2(480, STRIP_H) * s), Rect2(Vector2.ZERO, Vector2(480, STRIP_H) * a))
		if on != null:
			var r: Vector2 = TABS[tab]
			draw_texture_rect_region(on, Rect2(Vector2(x0 + r.x, h) * s, Vector2(r.y - r.x, STRIP_H) * s),
					Rect2(Vector2(r.x, 0) * a, Vector2(r.y - r.x, STRIP_H) * a))
	for e in [["mvbrdrl", Rect2(0, 0, 3, h), Vector2.ZERO], ["mvbrdrt", Rect2(0, 0, w, 3), Vector2.ZERO],
			["mvbrdrr", Rect2(0, 0, 3, h), Vector2(w - 3, 0)], ["mvbrdrb", Rect2(0, 0, w, 3), Vector2(0, h - 3)],
			["mvcrnrlt", Rect2(0, 0, 3, 3), Vector2.ZERO], ["mvcrnrrt", Rect2(0, 0, 3, 3), Vector2(w - 3, 0)],
			["mvcrnrlb", Rect2(0, 0, 3, 3), Vector2(0, h - 3)], ["mvcrnrrb", Rect2(0, 0, 3, 3), Vector2(w - 3, h - 3)]]:
		var t: Texture2D = fe._tex("framewnd/%s.png" % e[0])
		if t != null:
			draw_texture_rect_region(t, Rect2(e[2] * s, e[1].size * s), Rect2(e[1].position * a, e[1].size * a))


func _process(_delta: float) -> void:
	var img := Vector2i(size - Vector2(0, STRIP_H * fe._scale() if tab >= 0 else 0.0))
	if _vp != null and img != _vp.size and img.x >= 1 and img.y >= 1:
		_vp.size = img
	if _terrain != null and not _ground_known:
		var g0 = _terrain.height_at(Vector3.ZERO)
		if g0 != null:
			_ground_known = true
			height = maxf(height, g0)
			_place()
	# Ground units stand on the terrain once it has loaded under them (the runtime's snap).
	for i in range(_snap.size() - 1, -1, -1):
		var g = _terrain.height_at(_snap[i][1])
		if g != null:
			_snap[i][0].position.y = g
			_snap.remove_at(i)
	queue_redraw()
