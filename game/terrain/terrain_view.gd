# Free-flight terrain viewer: fly over the original IAF terrain with the F-16 parked in view.
#   Right mouse: look around   W/S/A/D: move   Q/E: down/up   Shift: fast   Ctrl: slow
#   `godot --path game res://terrain/terrain_view.tscn -- --screenshot out.png [--at x z alt yaw pitch]`
extends Node3D

@onready var terrain: Node3D = $Terrain
@onready var camera: Camera3D = $Camera
@onready var hud: Label = $HUD

var speed := 250.0  # m/s
var yaw := 0.0
var pitch := -0.25
var looking := false


func _ready() -> void:
	terrain.focus = camera
	var size: Vector2 = terrain.size_metres()
	camera.position = Vector3(size.x * 0.5, 2500, size.y * 0.5)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--at")
	if at >= 0:
		camera.position = Vector3(float(args[at + 1]), float(args[at + 3]), float(args[at + 2]))
		yaw = float(args[at + 4])
		pitch = float(args[at + 5])
	_apply_look()
	_spawn_f16()
	var shot := args.find("--screenshot")
	var t0 := Time.get_ticks_msec()
	if shot >= 0:
		# Let the streamer load everything in range, then capture.
		while terrain.missing_after_frame():
			await get_tree().process_frame
		print("terrain loaded in %d ms" % (Time.get_ticks_msec() - t0))
		_keep_above_ground()
		var f0 := Engine.get_frames_drawn()
		var m0 := Time.get_ticks_msec()
		for i in 120:
			await get_tree().process_frame
		print("average %.1f fps over 120 frames" % (1000.0 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_msec() - m0)))
		get_viewport().get_texture().get_image().save_png(args[shot + 1])
		get_tree().quit()


func _spawn_f16() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/converted/planes/f16/f16_h.gltf").simplify_path()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return
	var f16 := doc.generate_scene(state) as Node3D
	add_child(f16)
	# 60 m ahead of the camera, facing away, slightly below eye level.
	var fwd := -camera.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	f16.global_position = camera.global_position + fwd * 60.0 + Vector3(0, -8, 0)
	# Converted models have the nose along -Z (Direct3D +Z mirrored), like Godot's default forward.
	f16.look_at(f16.global_position + fwd * 10.0, Vector3.UP)


## Lift the camera (and the parked F-16) if the terrain under it is too close.
func _keep_above_ground() -> void:
	var ground = terrain.height_at(camera.position)
	if ground != null and camera.position.y < ground + 150.0:
		var lift: float = ground + 150.0 - camera.position.y
		camera.position.y += lift
		for c in get_children():
			if c is Node3D and c != camera and c != terrain:
				c.position.y += lift


func _apply_look() -> void:
	camera.rotation = Vector3(pitch, yaw, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and looking:
		yaw -= event.relative.x * 0.003
		pitch = clamp(pitch - event.relative.y * 0.003, -1.5, 1.5)
		_apply_look()


func _process(delta: float) -> void:
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v -= camera.global_basis.z
	if Input.is_key_pressed(KEY_S): v += camera.global_basis.z
	if Input.is_key_pressed(KEY_A): v -= camera.global_basis.x
	if Input.is_key_pressed(KEY_D): v += camera.global_basis.x
	if Input.is_key_pressed(KEY_E): v += Vector3.UP
	if Input.is_key_pressed(KEY_Q): v -= Vector3.UP
	var s := speed
	if Input.is_key_pressed(KEY_SHIFT): s *= 8.0
	if Input.is_key_pressed(KEY_CTRL): s *= 0.1
	camera.position += v.normalized() * s * delta
	var p := camera.position
	var ground = terrain.height_at(p)
	var agl := "" if ground == null else "  (%.0f m above ground)" % (p.y - ground)
	hud.text = "x %.1f km  y %.1f km  alt %.0f m%s   chunks %d   %d fps\n[RMB] look  [WASD] move  [Q/E] down/up  [Shift] fast  [Ctrl] slow" % [
		p.x / 1000.0, p.z / 1000.0, p.y, agl, terrain.loaded_count(), Engine.get_frames_per_second()]
