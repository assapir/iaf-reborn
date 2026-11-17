# A jet on show in the menus (Modern IAF's Hangar, modern-iaf/docs/front-end.md §12): the flight's own model
# (AircraftModel.create: the same file, descriptor and gear-down ground pose) with its stores hung as the flight hangs
# them (PlayerWeapons' store models, IafStores' slots, the lugged stores by their top), lit in a world of its own. It
# stands still; the player looks at it from any side: a mouse drag orbits the camera (all the way round, and from above
# and below within PITCH_MIN..PITCH_MAX), the wheel, a trackpad's scroll or pinch zoom (ZOOM_MIN..ZOOM_MAX), a gamepad's
# right stick orbits and its triggers zoom; with the focus the arrows (and the D-pad) orbit, + / − zoom; a double click,
# 0, Home or the right stick's click go back to the start view. A caller sets the start view through the static `yaw`,
# `pitch` and `zoom` before show_jet() (they carry over between pages, so the next jet is seen as the last one was).
#
# The SubViewport renders at the window's pixel size of this control (the front end lays out on a 1080-high canvas
# scaled to the window, so a SubViewportContainer would render at the canvas size and blur on a large screen), and only
# while this control is visible in the tree and the window is not minimised: hidden, freed or minimised, it draws
# nothing. `failed` after show_jet() when the model would not load: the caller shows a still picture instead.
#
# `below` (Modern IAF's Loadout screen, front-end.md §10.1): the jet seen straight from beneath, the nose up the
# screen, fixed (no orbit, no focus), lit from below, its weapon bays open with their stores in view; `points()` gives
# each station's place on the control.
extends TextureRect

const AircraftModel := preload("res://shared/aircraft/aircraft_model.gd")
const PlayerWeapons := preload("res://shared/weapons/player_weapons.gd")
const Stores := preload("res://shared/weapons/stores.gd")
const Gltf := preload("res://shared/util/gltf.gd")

## The orbit by hand: degrees per pixel dragged, per arrow key press, and a second at the gamepad stick's full push.
const DRAG := 0.35
const KEY_STEP := 6.0
const STICK_SPEED := 120.0
const STICK_DEAD := 0.2
## The camera: its field of view and its direction from the jet's centre (a three-quarter view from the front, a
## little above), the distance in the jet's half-diagonals.
const FOV := 28.0
const VIEW := Vector3(-1.0, 0.42, -1.05)
const DISTANCE := 3.0
## The camera's height over the jet's level, degrees: the start view's (VIEW's), and the limits (from beneath the
## belly to almost straight down on the jet; the camera's up never flips).
const PITCH_START := 16.15
const PITCH_MIN := -45.0
const PITCH_MAX := 80.0
## The distance's factor: the limits (the jet filling the view to well inside the frame; at ZOOM_MIN the camera stays
## out of the jet's bounding sphere), a wheel step's factor, and a second's at a full trigger.
const ZOOM_MIN := 0.6
const ZOOM_MAX := 1.6
const ZOOM_STEP := 1.1
const ZOOM_SPEED := 1.5
## The turn a first showing starts at: the nose toward the screen's left and a little toward the viewer (the menus'
## mock-ups: toward the jets' list), and in a right-to-left layout toward the right.
const START := -20.0
const START_RTL := 107.0

## The view now: the jet's turn and the camera's height (degrees), the distance's factor. Kept between pages, so a jet
## picked next is seen as the last one was (yaw NAN: not shown yet, the start view on the first showing).
static var yaw := NAN
static var pitch := PITCH_START
static var zoom := 1.0
## The layout `yaw` was set in: a switch of language turns the jet to the new layout's start (its nose toward the list).
static var _yaw_rtl := false

var failed := false
## Seen from beneath, fixed, the bays open (set before show_jet).
var below := false
## Renders in a minimised window too (tests).
var ignore_minimised := false
var vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
## The jet's half-diagonal with its stores, metres (the camera's distance unit).
var _radius := 1.0
## The model shown, the sun and the stations' attach points (pylon 0..8 → model metres).
var _model: Node3D
var _sun: DirectionalLight3D
var _stations := {}


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
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
	_sun = DirectionalLight3D.new()
	var sun := _sun
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
	resized.connect(fit)
	visibility_changed.connect(_update_mode)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _ready() -> void:
	# The window's size (a resize keeps the canvas size under its scaling, so `resized` stays quiet) and minimising.
	get_viewport().size_changed.connect(fit)
	get_viewport().size_changed.connect(_update_mode)
	fit()
	_update_mode()


## Shows plane folder `plane` (AircraftModel.plane_file's) with `stores`: {pylon 0..8 (A..I): {path (the weapon record's
## model), count, lugged (a bomb, tank or pod, hung by its top from the station's lugs), bomb (a bomb's rack layout),
## racked (on a rack: Stores.place)}}. The stores of the descriptor's `internal_stations` stay out of sight, in the
## shut bays, as in flight. False (and `failed`) when the model would not load.
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
	var internal := "" if below else str(desc.get("internal_stations", ""))
	_model = m
	_stations.clear()
	for i in Stores.PYLONS:
		var at = desc.get("stations", {}).get(Stores.FRAMES[i])
		if at is Array:
			_stations[i] = Vector3(at[0], at[1], at[2])
	if below and m.has_method("update"):
		# The weapon bays open (their doors' ramp at its end), as the flight opens them to release.
		m.update({"bay_open": true, "on_ground": true}, 0.0)
		m.settle()
	for i in stores:
		if Stores.LETTERS[i] in internal:
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
		var n := int(st.count)
		var at := {"index": i, "w": {"model_path": path}}
		at.merge(Stores.place(i, attach, n, st.bomb, path, PlayerWeapons._pilon_of(path), st.get("racked", false)))
		var nodes: Array = PlayerWeapons.hang(at, m).nodes
		for k in nodes.size():
			nodes[k].visible = k < n  # as the flight shows them (PlayerWeapons._update_store_nodes)
		# A model's own pylon for the station shows while the station is loaded.
		var pylon := PlayerWeapons.station_pylon(m, i)
		if pylon != null:
			pylon.visible = true
	# The navigation lights and strobe (Night lights Detailed: billboards made for a sky behind them) would draw as dark
	# squares on the clear ground: off, as on a parked jet.
	for n in m._lights:
		n.visible = false
	# The camera frames the jet with its stores, centred on the turn's axis.
	var box := Gltf.model_aabb(m)
	m.position = -Vector3(box.get_center().x, box.get_center().y, box.get_center().z)
	_radius = box.size.length() * 0.5
	if below:
		# Straight up from beneath, the nose (−Z) up the screen, the jet filling the frame: the left wing shows on the
		# right, as seen from under it. The shared view (yaw, pitch, zoom) stays the Hangar's.
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pivot.rotation_degrees.y = 0.0
		_sun.rotation_degrees = Vector3(60, 25, 0)  # the light from beneath, on the side seen
		var span := maxf(box.size.x, box.size.z)
		_cam.position = Vector3(0, -span * 0.5 / tan(deg_to_rad(FOV) * 0.5) - box.size.y * 0.5, 0)
		_cam.look_at(Vector3.ZERO, Vector3.FORWARD)
		_update_mode()
		return true
	if is_nan(yaw) or _yaw_rtl != is_layout_rtl():
		yaw = START_RTL if is_layout_rtl() else START  # a caller's pitch and zoom kept
	_yaw_rtl = is_layout_rtl()
	_apply()
	_update_mode()
	return true


## Each station's place on this control (pylon 0..8 → px), from the camera; {} before a model shows.
func points() -> Dictionary:
	var out := {}
	if _model == null or not _cam.is_inside_tree():
		return out
	var k := size / Vector2(vp.size)
	for i in _stations:
		# The stores' frame: they sit on the oleos with the airframe (PlayerWeapons.mount).
		var w: Vector3 = _pivot.transform * (_model.transform * (PlayerWeapons.mount(_model).transform * _stations[i]))
		out[i] = _cam.unproject_position(w) * k
	return out


## Back to the start view: the nose toward the inline start (START, START_RTL), PITCH_START, the jet's own distance.
func reset_view() -> void:
	yaw = START_RTL if is_layout_rtl() else START
	pitch = PITCH_START
	zoom = 1.0
	_apply()


## Orbits by `d_yaw` / `d_pitch` degrees and zooms by `factor` (above 1 farther), within the limits.
func orbit(d_yaw: float, d_pitch: float, factor := 1.0) -> void:
	yaw = fmod((0.0 if is_nan(yaw) else yaw) + d_yaw, 360.0)
	pitch += d_pitch
	zoom *= factor
	_apply()


## The view's statics on the scene: the jet turned by `yaw`, the camera at `pitch` over its level in VIEW's direction.
func _apply() -> void:
	pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	zoom = clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	if not is_nan(yaw):
		_pivot.rotation_degrees.y = yaw
	var flat := Vector3(VIEW.x, 0.0, VIEW.z).normalized()
	var p := deg_to_rad(pitch)
	_cam.position = (flat * cos(p) + Vector3.UP * sin(p)) * _radius * DISTANCE * zoom
	_cam.look_at_from_position(_cam.position, Vector3.ZERO)


## A gamepad (the first known one: a flight stick's axes 2 / 3 are often a throttle or rudder resting off centre,
## f331da69): its right stick orbits, its triggers zoom (right in, left out). Tests (Settings.isolated()) read none.
func _process(delta: float) -> void:
	if below:
		return
	var pads := [] if Settings.isolated() else Input.get_connected_joypads().filter(Input.is_joy_known)
	if pads.is_empty():
		return
	var d: int = pads[0]
	var sx := Input.get_joy_axis(d, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)
	var tz := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT)
	sx = sx if absf(sx) > STICK_DEAD else 0.0
	sy = sy if absf(sy) > STICK_DEAD else 0.0
	tz = tz if absf(tz) > STICK_DEAD else 0.0
	if sx != 0.0 or sy != 0.0 or tz != 0.0:
		orbit(sx * STICK_SPEED * delta, sy * STICK_SPEED * delta, pow(ZOOM_SPEED, tz * delta))


func _gui_input(event: InputEvent) -> void:
	if below:
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		# Dragging down raises the camera: the jet's top turns toward the viewer, as if held and tilted.
		orbit(event.relative.x * DRAG, event.relative.y * DRAG)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus(true)  # its keys orbit now; no ring under the pointer (the user, 15 Nov: no border while dragging)
		if event.double_click:
			reset_view()
	elif event is InputEventMouseButton or event is InputEventPanGesture:
		# The wheel and a trackpad's two-finger scroll, one way per scroll (Settings.zoom_steps: a Mac's bounce dropped).
		var n: int = Settings.zoom_steps(event)
		if n == 0 and not (event is InputEventPanGesture):
			return
		orbit(0.0, 0.0, pow(ZOOM_STEP, -n))
	elif event is InputEventMagnifyGesture:
		orbit(0.0, 0.0, 1.0 / event.factor)
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK:
		reset_view()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_0, KEY_KP_0, KEY_HOME]:
		reset_view()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
		orbit(0.0, 0.0, 1.0 / ZOOM_STEP)
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		orbit(0.0, 0.0, ZOOM_STEP)
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
		orbit(KEY_STEP * (1.0 if event.is_action("ui_left") else -1.0), 0.0)
	elif event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true):
		orbit(0.0, KEY_STEP * (1.0 if event.is_action("ui_up") else -1.0))
	else:
		return
	accept_event()


## The focus ring round the view while it holds the focus from the keyboard or a gamepad (a click's focus is hidden):
## the theme's "Turntable" focus box, none when the theme has no such box (Godot's default would draw a white frame).
func _draw() -> void:
	if has_focus(true) and has_theme_stylebox("focus", "Turntable"):
		draw_style_box(get_theme_stylebox("focus", "Turntable"), Rect2(Vector2.ZERO, size))


## The SubViewport at this control's size in window pixels.
func fit() -> void:
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
