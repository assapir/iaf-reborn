# Model viewer for converted IAF assets.
# Loads glTF files from ../assets/converted at runtime and hot-reloads them
# whenever the converter rewrites them.
extends Node3D

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
var reloading := false


func _ready() -> void:
	models = _find_models(Settings.assets_dir().path_join("converted"))
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
		var dist := args.find("--distance")
		if dist >= 0:
			distance = float(args[dist + 1])
		var ang := args.find("--yaw")
		if ang >= 0:
			yaw = float(args[ang + 1])
		preload("res://util/img.gd").screenshot_and_quit(self, args[shot + 1], 10)


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
		status = "No models found in %s — run iaf-convert first." % Settings.assets_dir().path_join("converted")
		_update_hud()
		return
	var path := models[index]
	var model = preload("res://util/gltf.gd").open(path)
	if model == null:
		status = "Failed to load %s" % path
		_update_hud()
		return
	var scene := preload("res://util/gltf.gd").instance(model)
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
	const Gltf := preload("res://util/gltf.gd")
	var aabb := Gltf.model_aabb(model_root, Gltf.GLOBAL_SPACE)
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
	if poll >= POLL_SECONDS and not models.is_empty() and not reloading:
		poll = 0.0
		if FileAccess.get_modified_time(models[index]) != loaded_mtime:
			_reload_when_settled()


func _reload_when_settled() -> void:
	# The converter rewrites .gltf, .bin and textures; wait until nothing in the
	# model's folder has changed for a second, then reload once.
	reloading = true
	var dir := models[index].get_base_dir()
	var last := -1
	while true:
		var newest := 0
		for f in DirAccess.get_files_at(dir):
			newest = max(newest, FileAccess.get_modified_time(dir.path_join(f)))
		if newest == last:
			break
		last = newest
		await get_tree().create_timer(1.0).timeout
	_load()
	reloading = false


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
