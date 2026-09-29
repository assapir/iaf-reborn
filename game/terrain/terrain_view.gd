# Terrain fly-over with the original 2D F-16 cockpit and an external view of your jet.
#   F1: cockpit   F2: external   C: toggle   V: panel down view
#   Arrows / RMB-drag (cockpit): steer   Z/X: roll   W/S/A/D: move   Q/E: down/up   Shift: fast   Ctrl: slow
#   External: RMB-drag orbits the camera, wheel zooms.
#   `godot --path game res://terrain/terrain_view.tscn -- --screenshot out.png [--at x z alt yaw pitch] [--external]`
# Until the flight model is wired in, the "aircraft" is this rig moved by the keys.
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

var speed := 250.0  # m/s
var yaw := 0.0
var pitch := -0.05
var roll := 0.0
var looking := false
var in_cockpit := true
var aircraft: Node3D
var orbit_yaw := PI  # external camera, relative to the aircraft heading (PI = behind)
var orbit_pitch := -0.15
var orbit_dist := 35.0
var last_pos := Vector3.ZERO
var ground_speed := 0.0


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
		yaw = float(args[at + 4])
		pitch = float(args[at + 5])
	if args.has("--external"):
		in_cockpit = false
	last_pos = rig.position
	cockpit.hud.camera = camera
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


func _spawn_f16() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/converted/planes/f16/f16_h.gltf").simplify_path()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return
	# Your own jet rides on the rig; converted models face -Z like Godot, so no rotation needed.
	aircraft = doc.generate_scene(state) as Node3D
	rig.add_child(aircraft)


## Lift the rig (and the parked F-16) if the terrain under it is too close.
func _keep_above_ground() -> void:
	var ground = terrain.height_at(rig.position)
	if ground != null and rig.position.y < ground + 150.0:
		var lift: float = ground + 150.0 - rig.position.y
		rig.position.y += lift
		last_pos.y += lift


func _apply_view() -> void:
	rig.rotation = Vector3(pitch, yaw, roll)
	cockpit.visible = in_cockpit
	if aircraft != null:
		aircraft.visible = not in_cockpit
	camera.current = in_cockpit
	chase.current = not in_cockpit
	# In the cockpit the camera looks slightly down so the nose axis sits on the HUD boresight.
	camera.rotation = Vector3(-cockpit.camera_pitch_offset(FOV), 0, 0)
	# External: orbit around the jet, relative to its heading, horizon kept level.
	var offset := Vector3(0, 0, orbit_dist).rotated(Vector3.RIGHT, orbit_pitch).rotated(Vector3.UP, yaw + orbit_yaw + PI)
	chase.global_position = rig.global_position + offset
	chase.look_at(rig.global_position, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and not in_cockpit and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_dist = max(12.0, orbit_dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_dist = min(400.0, orbit_dist * 1.1)
	elif event is InputEventMouseMotion and looking:
		if in_cockpit:
			yaw -= event.relative.x * 0.003
			pitch = clamp(pitch - event.relative.y * 0.003, -1.5, 1.5)
		else:
			orbit_yaw -= event.relative.x * 0.005
			orbit_pitch = clamp(orbit_pitch - event.relative.y * 0.005, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				in_cockpit = not in_cockpit
			KEY_F1:
				in_cockpit = true
			KEY_F2:
				in_cockpit = false
			KEY_V:
				cockpit.view_down = not cockpit.view_down


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_Z): roll += delta * 1.5
	if Input.is_key_pressed(KEY_X): roll -= delta * 1.5
	if Input.is_key_pressed(KEY_LEFT): yaw += delta * 0.8
	if Input.is_key_pressed(KEY_RIGHT): yaw -= delta * 0.8
	if Input.is_key_pressed(KEY_UP): pitch = clamp(pitch - delta * 0.6, -1.5, 1.5)
	if Input.is_key_pressed(KEY_DOWN): pitch = clamp(pitch + delta * 0.6, -1.5, 1.5)
	_apply_view()
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v -= rig.global_basis.z
	if Input.is_key_pressed(KEY_S): v += rig.global_basis.z
	if Input.is_key_pressed(KEY_A): v -= rig.global_basis.x
	if Input.is_key_pressed(KEY_D): v += rig.global_basis.x
	if Input.is_key_pressed(KEY_E): v += Vector3.UP
	if Input.is_key_pressed(KEY_Q): v -= Vector3.UP
	var s := speed
	if Input.is_key_pressed(KEY_SHIFT): s *= 8.0
	if Input.is_key_pressed(KEY_CTRL): s *= 0.1
	rig.position += v.normalized() * s * delta
	var moved := rig.position - last_pos
	last_pos = rig.position
	if delta > 0:
		ground_speed = lerp(ground_speed, moved.length() / delta, 0.1)
	_update_instruments(moved, delta)

	var p := rig.position
	var ground = terrain.height_at(p)
	var agl := "" if ground == null else "  (%.0f m above ground)" % (p.y - ground)
	hud_label.text = "x %.1f km  y %.1f km  alt %.0f m%s   chunks %d   %d fps\n[F1] cockpit  [F2] external  [C] toggle  [V] panel down  [arrows/RMB] steer or orbit  [Z/X] roll  [WASD] move  [Q/E] down/up  [Shift] fast  [Wheel] zoom" % [
		p.x / 1000.0, p.z / 1000.0, p.y, agl, terrain.loaded_count(), Engine.get_frames_per_second()]


func _update_instruments(moved: Vector3, delta: float) -> void:
	var fwd := -rig.global_basis.z
	var st: Dictionary = cockpit.state
	st.speed_kt = ground_speed * 1.943844
	st.mach = ground_speed / 340.3
	st.alt_ft = rig.position.y * 3.28084
	st.vs_fpm = (moved.y / delta * 196.85) if delta > 0 else 0.0
	st.pitch = rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))
	st.roll = rad_to_deg(roll)
	st.heading = fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	st.g = 1.0
	st.throttle = clamp(ground_speed / 600.0, 0.0, 1.0)
	st.rpm = lerp(0.7, 1.0, st.throttle)
	st.fuel_lbs = 7000.0
	cockpit.hud.velocity_dir = moved.normalized() if moved.length() > 0.01 else null
