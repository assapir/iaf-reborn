# Streams exported terrain chunks (see `iaf-terrain export`) around a focus node.
# Image decoding runs on worker threads; nearer chunks get denser meshes.
extends Node3D

@export var data_dir := "../assets/converted/terrain/israel_l4"
## Chunks kept around the focus in each direction.
@export var radius := 3
## Vertex grid per chunk side by ring distance (0 = the chunk under the focus).
@export var ring_resolution: PackedInt32Array = [256, 128, 64, 32]
## Decode jobs running at once.
@export var max_jobs := 4

var focus: Node3D
var meta := {}
var chunks := {}  # Vector2i -> MeshInstance3D (null mesh while loading)
var jobs := {}  # Vector2i -> task id
var results := {}  # Vector2i -> [colour Image, height Image]
var results_mutex := Mutex.new()
var meshes: Array[PlaneMesh] = []
var shader := preload("res://terrain/terrain.gdshader")
var dir := ""
var _missing := 1


func _ready() -> void:
	dir = ProjectSettings.globalize_path("res://").path_join(data_dir).simplify_path()
	var text := FileAccess.get_file_as_string(dir.path_join("meta.json"))
	if text.is_empty():
		push_error("terrain: %s/meta.json not found — run iaf-terrain export" % dir)
		return
	meta = JSON.parse_string(text)
	var span: float = meta.chunk_span
	for res in ring_resolution:
		var m := PlaneMesh.new()
		m.size = Vector2(span, span)
		m.subdivide_width = res - 1
		m.subdivide_depth = res - 1
		# Heights are applied in the shader; give culling a generous box.
		m.custom_aabb = AABB(Vector3(-span / 2, -1000, -span / 2), Vector3(span, 6000, span))
		meshes.append(m)


func size_metres() -> Vector2:
	var r: Array = meta.rect
	return Vector2(r[2] - r[0], r[3] - r[1])


func _chunk_of(pos: Vector3) -> Vector2i:
	var span: float = meta.chunk_span
	return Vector2i(floori(pos.x / span), floori(pos.z / span))


func _mesh_for(ring: int) -> PlaneMesh:
	return meshes[min(ring, meshes.size() - 1)]


func _process(_delta: float) -> void:
	if meta.is_empty() or focus == null:
		return
	var centre := _chunk_of(focus.global_position)
	var wanted := {}
	var missing: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := centre + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= meta.chunks[0] or c.y >= meta.chunks[1]:
				continue
			wanted[c] = true
			if chunks.has(c):
				var mi: MeshInstance3D = chunks[c]
				if mi.material_override != null:
					mi.mesh = _mesh_for(max(abs(dx), abs(dy)))
			elif not jobs.has(c):
				missing.append(c)
	for c in chunks.keys():
		if not wanted.has(c):
			chunks[c].queue_free()
			chunks.erase(c)
	_missing = missing.size() + jobs.size()

	# Start decode jobs, nearest first.
	missing.sort_custom(func(a, b): return (a - centre).length_squared() < (b - centre).length_squared())
	for c in missing:
		if jobs.size() >= max_jobs:
			break
		jobs[c] = WorkerThreadPool.add_task(_decode.bind(c))

	# Finish completed jobs (texture upload happens here, on the main thread).
	for c in jobs.keys():
		if not WorkerThreadPool.is_task_completed(jobs[c]):
			continue
		WorkerThreadPool.wait_for_task_completion(jobs[c])
		jobs.erase(c)
		results_mutex.lock()
		var images: Array = results.get(c, [])
		results.erase(c)
		results_mutex.unlock()
		if wanted.has(c):
			_add_chunk(c, images, max(abs(c.x - centre.x), abs(c.y - centre.y)))


func _decode(c: Vector2i) -> void:
	var colour := Image.load_from_file(dir.path_join("c_%d_%d.jpg" % [c.x, c.y]))
	var height := Image.load_from_file(dir.path_join("h_%d_%d.png" % [c.x, c.y]))
	var images := []
	if colour != null and height != null:
		colour.generate_mipmaps()
		images = [colour, height]
	results_mutex.lock()
	results[c] = images
	results_mutex.unlock()


func _add_chunk(c: Vector2i, images: Array, ring: int) -> void:
	var mi := MeshInstance3D.new()
	chunks[c] = mi
	if images.is_empty():
		return  # outside the data: keep an empty placeholder so we don't retry
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("colour_tex", ImageTexture.create_from_image(images[0]))
	mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(images[1]))
	mat.set_shader_parameter("chunk_span", float(meta.chunk_span))
	mat.set_shader_parameter("chunk_pixels", float(meta.chunk_pixels))
	mat.set_shader_parameter("sea_level_raw", float(meta.sea_level_raw))
	mat.set_shader_parameter("height_scale", float(meta.height_scale))
	mi.mesh = _mesh_for(ring)
	mi.material_override = mat
	mi.set_meta("height", images[1])
	# Self-shadowing a 16 km chunk is not worth re-running the displacement per cascade.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var span: float = meta.chunk_span
	mi.position = Vector3((c.x + 0.5) * span, 0, (c.y + 0.5) * span)
	add_child(mi)


func loaded_count() -> int:
	return chunks.size()


## True while chunks in range are still waiting to load.
func missing_after_frame() -> bool:
	return _missing > 0


## Terrain height in metres at a world position (null while that chunk isn't loaded).
## Nearest-texel lookup; open sea is not flattened here.
func height_at(pos: Vector3) -> Variant:
	if meta.is_empty():
		return null
	var c := _chunk_of(pos)
	if not chunks.has(c) or not chunks[c].has_meta("height"):
		return null
	var img: Image = chunks[c].get_meta("height")
	var span: float = meta.chunk_span
	var px: float = meta.chunk_pixels
	var x := int(round((pos.x - c.x * span) / span * px))
	var y := int(round((pos.z - c.y * span) / span * px))
	var col := img.get_pixel(clampi(x, 0, int(px)), clampi(y, 0, int(px)))
	var raw := roundi(col.r * 255.0) * 256 + roundi(col.g * 255.0)
	return (raw - float(meta.sea_level_raw)) / float(meta.height_scale)
