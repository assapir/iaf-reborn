# Model viewer for converted IAF assets.
# Loads glTF files from ../assets/converted at runtime and hot-reloads them
# whenever the converter rewrites them.
extends Node3D

const ASSETS := "../assets/converted"
const POLL_SECONDS := 0.5

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera
@onready var model_root: Node3D = $Model
@onready var hud: Label = $HUD

var models: PackedStringArray = []
var index := 0
var loaded_mtime := 0
var poll := 0.0
var yaw := -2.4
var pitch := -0.2
var distance := 12.0
var dragging := false
var show_helpers := false
var auto_rotate := true
var status := ""


func _ready() -> void:
	models = _find_models(ProjectSettings.globalize_path("res://").path_join(ASSETS).simplify_path())
	var start := models.find(_path_for("f16_h.gltf"))
	index = max(start, 0)
	_load()
	# `godot --path game -- --screenshot out.png [model.gltf]` renders one frame and quits (for testing).
	var args := OS.get_cmdline_user_args()
	var shot := args.find("--screenshot")
	if shot >= 0:
		auto_rotate = false
		if args.size() > shot + 2:
			index = max(models.find(_path_for(args[shot + 2])), 0)
			_load()
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args[shot + 1])
		get_tree().quit()


func _path_for(file: String) -> String:
	for m in models:
		if m.ends_with("/" + file):
			return m
	return ""


func _find_models(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_find_models(dir.path_join(sub)))
	for f in d.get_files():
		if f.ends_with(".gltf"):
			out.append(dir.path_join(f))
	out.sort()
	return out


func _load() -> void:
	for c in model_root.get_children():
		c.queue_free()
	if models.is_empty():
		status = "No models found in %s — run iaf-convert first." % ASSETS
		_update_hud()
		return
	var path := models[index]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		status = "Failed to load %s (error %d)" % [path, err]
		_update_hud()
		return
	var scene := doc.generate_scene(state)
	model_root.add_child(scene)
	loaded_mtime = FileAccess.get_modified_time(path)
	_apply_helpers()
	_frame_camera()
	status = "loaded %s" % Time.get_time_string_from_system()
	_update_hud()


func _apply_helpers() -> void:
	# Helper nodes (hinges, stations, camera) carry no mesh; show them as small markers on demand.
	for n in model_root.find_children("*", "Node3D", true, false):
		if n.has_meta("extras") and n.get_meta("extras").get("iaf_helper", false):
			for c in n.get_children():
				if c.name == "_marker":
					c.queue_free()
			if show_helpers:
				var m := MeshInstance3D.new()
				m.name = "_marker"
				var s := SphereMesh.new()
				s.radius = 0.06
				s.height = 0.12
				m.mesh = s
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(1, 0.2, 0.1)
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.material_override = mat
				n.add_child(m)


func _frame_camera() -> void:
	var aabb := AABB()
	var first := true
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	pivot.position = aabb.get_center()
	distance = max(aabb.get_longest_axis_size() * 1.15, 2.0)


func _update_hud() -> void:
	var name := models[index].get_file() if not models.is_empty() else "-"
	hud.text = "%s  (%d/%d)   %s\n[←/→] model  [H] helpers %s  [R] auto-rotate  [drag] orbit  [wheel] zoom\nhot reload: re-run iaf-convert and the model refreshes" % [
		name, index + 1, models.size(), status, "on" if show_helpers else "off"]


func _process(delta: float) -> void:
	if auto_rotate and not dragging:
		yaw += delta * 0.3
	pivot.rotation = Vector3(pitch, yaw, 0)
	camera.position = Vector3(0, 0, distance)
	poll += delta
	if poll >= POLL_SECONDS and not models.is_empty():
		poll = 0.0
		var mtime := FileAccess.get_modified_time(models[index])
		if mtime != loaded_mtime:
			# Give the converter a moment to finish writing .bin / textures.
			await get_tree().create_timer(0.3).timeout
			_load()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance *= 0.9
			MOUSE_BUTTON_WHEEL_DOWN:
				distance *= 1.1
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008
		pitch = clamp(pitch - event.relative.y * 0.008, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT:
				index = (index + 1) % models.size()
				_load()
			KEY_LEFT:
				index = (index - 1 + models.size()) % models.size()
				_load()
			KEY_H:
				show_helpers = not show_helpers
				_apply_helpers()
				_update_hud()
			KEY_R:
				auto_rotate = not auto_rotate
