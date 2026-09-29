# Terrain fly-over with the original 2D F-16 cockpit and an external view of your jet.
#   F1: cockpit   F2: external   C: toggle   V: panel up/down   PgUp/PgDn: slide panel   +/- or wheel: zoom
#   Arrows: stick (sprung: hold to deflect, release to centre)   Z/X: rudder
#   W/S: throttle   1..8: idle / 65 / 70 / 80 / 90 % / military / AB1 / AB2   G: gear   F: flaps   B: speed brake
#   External: RMB-drag orbits the camera, wheel zooms.
#   `godot --path game res://terrain/terrain_view.tscn -- [--real] [--screenshot out.png] [--at x z alt heading pitch [roll]] [--external]`
#   --real: fly the corrected real-world F-16 data instead of the original 1998 numbers.
#   (angles in degrees for --at)
# The aircraft is the original IAF F-16 flight model (Rust, crates/iaf-flight) via the IafFlight class.
extends Node3D

const FOV := 55.0
## Screenshot runs give up waiting for terrain after this long.
const SCREENSHOT_TIMEOUT_MS := 20000

@onready var terrain: Node3D = $Terrain
@onready var rig: Node3D = $Rig
@onready var camera: Camera3D = $Rig/Camera
@onready var hud_label: Label = $HUD
@onready var cockpit: Control = $CockpitLayer/Cockpit
@onready var chase: Camera3D = $Chase

var looking := false
var flight = null  # IafFlight
var real_data := false
var stick := Vector2.ZERO  # x roll right+, y pull+
var rudder := 0.0
var throttle := 0.74
var flaps := 0.0
var gear_down := false
var brakes := false
## Original throttle presets (keys.trx order): idle, 65%, 70%, 80%, 90%, military, AB1, AB2.
const THROTTLE_PRESETS := [0.0, 0.0925, 0.185, 0.37, 0.555, 0.74, 0.8, 1.0]
const STICK_RATE := 2.5  # full deflection per second while a key is held
const STICK_RETURN := 4.0
var in_cockpit := true
var aircraft: Node3D
var orbit_yaw := PI  # external camera, relative to the aircraft heading (PI = behind)
var orbit_pitch := -0.15
var orbit_dist := 35.0


func _ready() -> void:
	terrain.focus = rig
	camera.fov = FOV
	chase.fov = 60.0
	var size: Vector2 = terrain.size_metres()
	rig.position = Vector3(size.x * 0.5, 2500, size.y * 0.5)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--at")
	if at >= 0:
		rig.position = Vector3(float(args[at + 1]), float(args[at + 3]), float(args[at + 2]))
		var roll_deg := float(args[at + 6]) if args.size() > at + 6 and args[at + 6].is_valid_float() else 0.0
		# Heading is clockwise from north (-Z); Godot's yaw is counter-clockwise.
		rig.basis = Basis.from_euler(Vector3(deg_to_rad(float(args[at + 5])), deg_to_rad(-float(args[at + 4])), deg_to_rad(-roll_deg)), EULER_ORDER_YXZ)
	if args.has("--external"):
		in_cockpit = false
	var st_arg := args.find("--stick")
	if st_arg >= 0:
		scripted_stick = Vector2(float(args[st_arg + 1]), float(args[st_arg + 2]))
	# Test poses: --orbit yaw pitch dist (degrees, metres), --rudder r, --gear, --flaps, --brakes.
	var orb := args.find("--orbit")
	if orb >= 0:
		orbit_yaw = deg_to_rad(float(args[orb + 1]))
		orbit_pitch = deg_to_rad(float(args[orb + 2]))
		orbit_dist = float(args[orb + 3])
	var rud := args.find("--rudder")
	if rud >= 0:
		scripted_rudder = float(args[rud + 1])
	gear_down = args.has("--gear")
	flaps = 1.0 if args.has("--flaps") else 0.0
	brakes = args.has("--brakes")
	frozen = args.has("--freeze")
	cockpit.hud.camera = camera
	_start_flight()
	_apply_view()
	_spawn_f16()
	var shot := args.find("--screenshot")
	if shot >= 0:
		_screenshot(args[shot + 1])


## Waits for the terrain in range (bounded), measures fps, saves a PNG and quits.
func _screenshot(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	while terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < SCREENSHOT_TIMEOUT_MS:
		await get_tree().process_frame
	print("terrain loaded in %d ms" % (Time.get_ticks_msec() - t0))
	_keep_above_ground()
	var f0 := Engine.get_frames_drawn()
	var m0 := Time.get_ticks_msec()
	for i in 120:
		await get_tree().process_frame
	print("average %.1f fps over 120 frames" % (1000.0 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_msec() - m0)))
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _start_flight() -> void:
	if not ClassDB.class_exists("IafFlight"):
		push_error("IafFlight missing: build the extension (cargo build -p iaf-godot)")
		return
	flight = ClassDB.instantiate("IafFlight")
	var install := ProjectSettings.globalize_path("res://").path_join("../assets/install").simplify_path()
	var fwd := -rig.global_basis.z
	var heading := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	real_data = Settings.real_data() or OS.get_cmdline_user_args().has("--real")
	var err: String = flight.start(install, "F-16", rig.position, heading, 180.0, real_data)
	if err != "":
		push_error("flight model: " + err)
		flight = null


func _spawn_f16() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/converted/planes/f16/f16_h.gltf").simplify_path()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return
	# Your own jet rides on the rig; converted models face -Z like Godot, so no rotation needed.
	aircraft = preload("res://aircraft/aircraft_model.gd").new()
	aircraft.setup(doc.generate_scene(state) as Node3D, gear_down)
	rig.add_child(aircraft)


## Lift the rig (and the parked F-16) if the terrain under it is too close.
func _keep_above_ground() -> void:
	var ground = terrain.height_at(rig.position)
	if ground != null and rig.position.y < ground + 150.0:
		var lift: float = ground + 150.0 - rig.position.y
		rig.position.y += lift


func _apply_view() -> void:
	cockpit.visible = in_cockpit
	if aircraft != null:
		aircraft.visible = not in_cockpit
	camera.current = in_cockpit
	chase.current = not in_cockpit
	# In the cockpit the camera looks slightly down so the nose axis sits on the HUD boresight.
	camera.fov = cockpit.world_fov(FOV)
	camera.rotation = Vector3(-cockpit.camera_pitch_offset(camera.fov), 0, 0)
	# External: orbit around the jet, relative to its heading, horizon kept level.
	var fwd := -rig.global_basis.z
	var heading_yaw := atan2(-fwd.x, -fwd.z)
	var offset := Vector3(0, 0, orbit_dist).rotated(Vector3.RIGHT, orbit_pitch).rotated(Vector3.UP, heading_yaw + orbit_yaw + PI)
	chase.global_position = rig.global_position + offset
	chase.look_at(rig.global_position, Vector3.UP)


func _zoom_cockpit(step: float) -> void:
	cockpit.zoom = clamp(cockpit.zoom + step, cockpit.ZOOM_MIN, cockpit.ZOOM_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var closer: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
		if in_cockpit:
			_zoom_cockpit(0.05 if closer else -0.05)
		else:
			orbit_dist = clamp(orbit_dist * (0.9 if closer else 1.1), 12.0, 400.0)
	elif event is InputEventMouseMotion and looking and not in_cockpit:
		orbit_yaw -= event.relative.x * 0.005
		orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.005, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://menu/front_end.tscn")
			KEY_C:
				in_cockpit = not in_cockpit
			KEY_F1:
				in_cockpit = true
			KEY_F2:
				in_cockpit = false
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				throttle = THROTTLE_PRESETS[event.keycode - KEY_1]
			KEY_G:
				gear_down = not gear_down
			KEY_F:
				flaps = 0.0 if flaps > 0.0 else 1.0
			KEY_B:
				brakes = not brakes
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_zoom_cockpit(0.05)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_cockpit(-0.05)
			KEY_V:
				cockpit.toggle_panel()


func _process(delta: float) -> void:
	_read_controls(delta)
	if flight != null:
		var ground = terrain.height_at(rig.position)
		flight.set_ground_height(ground if ground != null else -1.0e9)
		flight.set_controls(stick.x, stick.y, rudder, throttle, flaps, gear_down, brakes)
		if not frozen:
			flight.step(delta)
		var st: Dictionary = flight.state()
		rig.position = st.position
		rig.basis = Basis(st.right, st.up, -st.forward)
		for k in ["speed_kt", "mach", "alt_ft", "vs_fpm", "pitch", "roll", "heading", "aoa", "g", "rpm", "throttle", "fuel_lbs"]:
			cockpit.state[k] = st[k]
		cockpit.hud.velocity_dir = st.velocity.normalized() if st.velocity.length() > 1.0 else null
	if aircraft != null:
		aircraft.animate(stick, rudder, flaps, gear_down, brakes, delta)
	_apply_view()
	var p := rig.position
	var ground_h = terrain.height_at(p)
	var agl := "" if ground_h == null else "  (%.0f m above ground)" % (p.y - ground_h)
	var st2: Dictionary = cockpit.state
	hud_label.text = "%s   x %.1f km  y %.1f km  alt %.0f m%s   %d kt  %.1f g  thr %d%%%s%s%s   %d fps\n[F1] cockpit  [F2] external  [C] toggle  [V/PgUp/PgDn] panel  [+/-] zoom  [arrows] stick  [Z/X] rudder  [W/S, 1-8] throttle  [G] gear  [F] flaps  [B] brake" % [
		"REAL DATA" if real_data else "ORIGINAL 1998 DATA", p.x / 1000.0, p.z / 1000.0, p.y, agl, st2.speed_kt, st2.g, int(throttle * 100),
		"  GEAR" if gear_down else "", "  FLAPS" if flaps > 0 else "", "  BRAKE" if brakes else "", Engine.get_frames_per_second()]


## Scripted stick for test captures: `--stick x y` (held for the whole run).
var scripted_stick = null
var scripted_rudder = null
## --freeze: don't advance the flight model (for posed test captures).
var frozen := false


## Keyboard as a sprung joystick: held keys deflect the stick progressively, release centres it.
func _read_controls(delta: float) -> void:
	if scripted_stick != null:
		stick = scripted_stick
		if scripted_rudder != null:
			rudder = scripted_rudder
		return
	var want := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))  # down = pull
	for i in 2:
		if want[i] != 0.0:
			stick[i] = move_toward(stick[i], want[i], STICK_RATE * delta)
		else:
			stick[i] = move_toward(stick[i], 0.0, STICK_RETURN * delta)
	var want_rudder := float(Input.is_key_pressed(KEY_X)) - float(Input.is_key_pressed(KEY_Z))
	rudder = move_toward(rudder, want_rudder, (STICK_RATE if want_rudder != 0.0 else STICK_RETURN) * delta)
	if Input.is_key_pressed(KEY_W): throttle = min(throttle + 0.3 * delta, 1.0)
	if Input.is_key_pressed(KEY_S): throttle = max(throttle - 0.3 * delta, 0.0)
	# PgUp looks up (panel slides away), PgDn looks down at more of the panel.
	if Input.is_key_pressed(KEY_PAGEUP): cockpit.slide_panel(-cockpit.PANEL_SLIDE_SPEED * delta)
	if Input.is_key_pressed(KEY_PAGEDOWN): cockpit.slide_panel(cockpit.PANEL_SLIDE_SPEED * delta)

