# A jet turning slowly on a turntable, for the menus (Modern IAF's Hangar, modern-iaf/docs/front-end.md §12): the
# flight's own model (AircraftModel.create: the same file, descriptor and gear-down ground pose) with its stores hung
# as the flight hangs them (PlayerWeapons' store models, IafStores' slots, the lugged stores by their top), lit in a
# world of its own. A mouse drag turns it by hand; the stick never does (the menus read no joypad axis, f331da69).
#
# The SubViewport renders at the window's pixel size of this control (the front end lays out on a 1080-high canvas
# scaled to the window, so a SubViewportContainer would render at the canvas size and blur on a large screen), and only
# while this control is visible in the tree and the window is not minimised: hidden, freed or minimised, it draws
# nothing. `failed` after show_jet() when the model would not load: the caller shows a still picture instead.
extends TextureRect

const AircraftModel := preload("res://shared/aircraft/aircraft_model.gd")
const PlayerWeapons := preload("res://shared/weapons/player_weapons.gd")
const Stores := preload("res://shared/weapons/stores.gd")
const Gltf := preload("res://shared/util/gltf.gd")

## The slow turn, degrees a second, and the turn by hand, degrees per pixel dragged.
const SPEED := 8.0
const DRAG := 0.35
## The camera: its field of view and its direction from the jet's centre (a three-quarter view from the front, a
## little above), the distance in the jet's half-diagonals.
const FOV := 28.0
const VIEW := Vector3(-1.0, 0.42, -1.05)
const DISTANCE := 3.0
## The turn a first showing starts at: the nose toward the screen's left and a little toward the viewer (the menus'
## mock-ups: toward the jets' list), and in a right-to-left layout toward the right.
const START := -20.0
const START_RTL := 107.0

## The turn now, degrees: kept between pages, so a jet picked next picks up where the last one stood (NAN: not shown
## yet).
static var yaw := NAN

var failed := false
## Turns by itself (off: a still angle, the pictures' tests).
var turning := true
## Renders in a minimised window too (tests).
var ignore_minimised := false
var vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	vp.add_child(sun)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = FOV
	vp.add_child(_cam)
	texture = vp.get_texture()
	resized.connect(_fit)
	visibility_changed.connect(_update_mode)


func _ready() -> void:
	# The window's size (a resize keeps the canvas size under its scaling, so `resized` stays quiet) and minimising.
	get_viewport().size_changed.connect(_fit)
	get_viewport().size_changed.connect(_update_mode)
	_fit()
	_update_mode()


## Shows plane folder `plane` (AircraftModel.plane_file's) with `stores`: {pylon 0..8 (A..I): {path (the weapon
## record's model), count, lugged (a bomb or tank, hung by its top from the station's lugs), bomb (a bomb's rack
## layout)}}. The stores of the descriptor's `internal_stations` stay out of sight, in the shut bays, as in flight.
## False (and `failed`) when the model would not load.
func show_jet(plane: String, stores: Dictionary) -> bool:
	for c in _pivot.get_children():
		c.queue_free()
	var m := AircraftModel.create(plane, -1, true)
	failed = m == null
	if failed:
		_update_mode()
		return false
	_pivot.add_child(m)
	var desc: Dictionary = m.desc
	var internal := str(desc.get("internal_stations", ""))
	for i in stores:
		if "ABCDEFGHI"[i] in internal:
			continue
		var st: Dictionary = stores[i]
		var path := str(st.path)
		var p = desc.get("stations", {}).get(Stores.FRAMES[i])
		if not p is Array:
			continue
		var attach := Vector3(p[0], p[1], p[2])
		var lug = desc.get("lugs", {}).get(Stores.FRAMES[i])
		var top := Stores._top(path) if lug is Array and st.lugged else 0.0
		if top > 0.0:
			attach = Vector3(lug[0], lug[1] - top, lug[2])
		var slots: Array = ClassDB.class_call_static(
			"IafStores", "slots", i, attach, int(st.count), st.bomb, PlayerWeapons._pilon_of(path)
		)
		for s in slots:
			var n := PlayerWeapons._instance(path)
			if n == null:
				break
			m.add_child(n)
			n.position = s
		# A model's own pylon for the station (Pylon<letter>, the F-35I's) shows while the station is loaded.
		var pylon := m.find_child("Pylon" + "ABCDEFGHI"[i], true, false) as Node3D
		if pylon != null:
			pylon.visible = true
	# The navigation lights and strobe (Night lights Detailed: billboards made for a sky behind them) would draw as dark
	# squares on the clear ground: off, as on a parked jet.
	for n in m._lights:
		n.visible = false
	# The camera frames the jet with its stores, centred on the turn's axis.
	var box := Gltf.model_aabb(m)
	m.position = -Vector3(box.get_center().x, box.get_center().y, box.get_center().z)
	var r := box.size.length() * 0.5
	_cam.position = VIEW.normalized() * r * DISTANCE
	_cam.look_at(Vector3.ZERO)
	if is_nan(yaw):
		yaw = START_RTL if is_layout_rtl() else START
	_pivot.rotation_degrees.y = yaw
	_update_mode()
	return true


func _process(delta: float) -> void:
	if turning:
		yaw = fmod(yaw + SPEED * delta, 360.0)
	_pivot.rotation_degrees.y = yaw


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw = fmod(yaw + event.relative.x * DRAG, 360.0)
		accept_event()


## The SubViewport at this control's size in window pixels.
func _fit() -> void:
	if not is_inside_tree():
		return
	var k := get_viewport().get_final_transform().get_scale().y if get_viewport() != null else 1.0
	vp.size = Vector2i(maxi(int(size.x * k), 2), maxi(int(size.y * k), 2))


## Renders only while it can be seen: in the tree, visible, a model shown, the window not minimised (unless
## `ignore_minimised`: a headless test's window reports itself minimised).
func _update_mode() -> void:
	var on := (
		is_inside_tree()
		and is_visible_in_tree()
		and not failed
		and _pivot.get_child_count() > 0
		and (ignore_minimised or get_window().mode != Window.MODE_MINIMIZED)
	)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
