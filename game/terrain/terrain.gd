# The whole map.ptt theatre (converted by `iaf-terrain theatre`, docs/formats/ptt.md "Converted
# layout" and "Rendering") streamed around a focus node as a quadtree of nodes: level L covers
# 1024·2^L terrain units with a 1024² colour texture at 2^L units per pixel. Near the focus the
# tree splits into finer nodes (down to the airbase insets at 1 unit per pixel), far away it stays
# coarse; every node is a grid of quads plus a skirt that hides the cracks between nodes of
# different levels. Heights are the level-6 elevation (interpolated over
# triangles like the original's inset heights, FUN_004281e0) for every node of level <= 6, a
# coarser node's own level above that. A node without its own imagery shows the part of its nearest ancestor's texture.
# Decoding (JPEG, mipmaps, BC1) runs on worker threads.
#
# Placement uses the original engine's world frame (metres; X east, Y north) with the
# georeference from meta.json, relative to `world_origin` (engine X/Y at the scene origin):
#   Godot x = X − origin.x,  Godot z = −(Y − origin.y),  Godot y = metres above sea level.
extends Node3D

## Under assets/.
@export var data_dir := "converted/terrain/theatre"
## Quads per node side of the nodes coarser than GEOM_MIN_LEVEL (finer nodes have one vertex per
## level-6 height texel, which draws the triangle-interpolated surface of height_at() exactly).
@export var far_quads := 32
## A node splits while the focus is nearer than `split_factor` × its side (at the default terrain
## detail; the Graphics page's TERRAIN DETAIL slider scales it).
@export var split_factor := 1.5
## Nothing farther than this is loaded or drawn (metres; the camera's far plane).
@export var view_range := 200000.0
## Decode workers running at once. Each takes the next wanted key itself when it finishes one, so
## loading does not wait for frames (a hidden / throttled window runs at ~1 fps).
@export var max_jobs := 6
## "Near" for `ground_ready()`: nodes within this distance (m) must be at their full detail.
@export var near_range := 8000.0
## Geometry splits down to this level everywhere; finer only where finer imagery exists.
const GEOM_MIN_LEVEL := 2
## Loaded textures unused for this long (ms) are dropped.
const EVICT_MS := 20000
## The quadtree is re-chosen when the focus has moved this far (m), after this long (ms), or when
## data arrived.
const RESELECT_M := 100.0
const RESELECT_MS := 500

## terraintype.dat surface flags (docs/formats/ptt.md "Terrain types", FUN_004024b0).
const SURFACE_LAND := 0x1
const SURFACE_INLAND_WATER := 0x2
const SURFACE_SEA := 0x4
const SURFACE_ISLAND := 0x8
const SURFACE_RUNWAY := 0x10
## The flight model's tests (FUN_005bb9f0): water, runway, rough (off-runway land).
const SURFACE_WATER := 0x6
const SURFACE_ANY_RUNWAY := 0x30
const SURFACE_ROUGH := 0x9

var focus: Node3D
## Engine world X/Y (metres) placed at the Godot origin (keeps float precision near the player).
var world_origin := Vector2.ZERO
var meta := {}
var m_per_unit := 1.0
var dir := ""
var _span0 := 1024.0  # node side of level 0 in terrain units
var _theatre := PackedFloat64Array([0, 0, 0, 0])  # x0, y0, x1, y1 (terrain units)
var _height_level := 6
var _root_level := 11
var _colour_nodes := {}  # Vector3i(i, j, level) -> true (nodes with their own texture)
## Imagery layers (docs/imagery.md): nodes whose colour texture comes from a layer -> its directory
## (else the original's). Set from the Graphics page choice at _ready (or `layers` before it).
var _layer_dir := {}
var layers: Array[String] = []
var _layers_set := false
const ImageryLayers := preload("res://terrain/imagery_layers.gd")
var _finest := {}  # Vector3i -> finest level with its own texture in the node's subtree
var _meshes: Array[ArrayMesh] = []
var shader := preload("res://terrain/terrain.gdshader")

# Resources (colour texture per textured node, height texture + image per theatre node), keyed by
# Vector4i(kind, i, j, level) with kind 0 = colour, 1 = height.
var _res := {}  # key -> {"tex": Texture2D, "img": Image, "used": msec}
var _jobs: Array[int] = []  # worker task ids
var _queue: Array = []  # keys to decode, nearest first (main thread fills, workers take; under the mutex)
var _busy := {}  # keys being decoded (under the mutex)
var _results := {}  # key -> Image (from the workers; under the mutex)
var _results_mutex := Mutex.new()
var _wanted := {}  # key -> distance (this frame's requests)
var _drawn := {}  # Vector3i -> MeshInstance3D
var _blocked := 1  # splits waiting for data this frame
var _blocked_near := 1
## The resources ground_ready() waits for in this selection (the nodes within `near_range` at full
## detail, every drawn node, the heights under the focus): key -> loaded (ground_progress()).
var _near := {}
## false: load only, draw nothing (the front end's preload, terrain_preload.gd).
var draw_nodes := true
var _eye := Vector3.ZERO  # focus in terrain units (x, y) and height above the ground (z, metres)
var _last_focus := Vector3(INF, INF, INF)
var _last_select := 0

# terraintype.dat main BSP tree (docs/formats/ptt.md "Terrain types"): per node the split line
# (a, b, c, d), children (-1 = none) and the leaf's surface mask.
var _bsp_plane := PackedFloat64Array()
var _bsp_child0 := PackedInt32Array()
var _bsp_child1 := PackedInt32Array()
var _bsp_mask := PackedInt32Array()


func _ready() -> void:
	dir = Settings.assets_dir().path_join(data_dir)
	meta = Settings.load_json(dir.path_join("meta.json"))
	if meta.is_empty():
		push_error("terrain: %s/meta.json not found — run tools/setup.sh (iaf-terrain theatre)" % dir)
		return
	m_per_unit = float(meta.get("units_to_metres", 1.0))
	_span0 = float(meta.node_pixels)
	_theatre = PackedFloat64Array(meta.theatre)
	_height_level = int(meta.height_level)
	_root_level = int(meta.root_level)
	for l in meta.nodes:
		for ij in meta.nodes[l]:
			_add_colour_node(Vector3i(int(ij[0]), int(ij[1]), int(l)))
	if not _layers_set:
		layers = ImageryLayers.selected()
	# Later layers do not override earlier ones (Israel's first).
	for id in layers:
		var m := ImageryLayers.manifest(id)
		var ldir := ImageryLayers.layer_dir(id)
		for l in m.get("nodes", {}):
			for ij in m.nodes[l]:
				var n := Vector3i(int(ij[0]), int(ij[1]), int(l))
				if not _layer_dir.has(n):
					_layer_dir[n] = ldir
					_add_colour_node(n)
	for l in _root_level + 1:
		_meshes.append(_grid_mesh(_span_m(l), _quads(l)))
	_load_terrain_types(Settings.assets_dir().path_join("install/terraintype.dat"))


func _add_colour_node(n: Vector3i) -> void:
	_colour_nodes[n] = true
	var a := n
	while a.z <= _root_level and _finest.get(a, 99) > n.z:
		_finest[a] = n.z
		a = _parent(a)


## Picks the imagery layers before _ready (tests, the preload); default: the Graphics page choice.
func set_layers(ids: Array[String]) -> void:
	layers = ids
	_layers_set = true


## The directory a node's colour texture is read from: its layer's, else the original's.
func colour_dir(n: Vector3i) -> String:
	return _layer_dir.get(n, dir)


## Terrain units (as in map.ptt) -> Godot position (y = 0).
func terrain_to_godot(tx: float, ty: float) -> Vector3:
	return Vector3(tx * m_per_unit + float(meta.get("x_shift", 0)) - world_origin.x, 0.0,
			ty * m_per_unit - float(meta.get("y_shift", 0)) + world_origin.y)


## Godot position -> terrain units.
func godot_to_terrain(p: Vector3) -> Vector2:
	return Vector2((p.x + world_origin.x - float(meta.get("x_shift", 0))) / m_per_unit,
			(p.z - world_origin.y + float(meta.get("y_shift", 0))) / m_per_unit)


## Engine world coordinates (metres, X east, Y north) at the centre of the theatre.
func centre_world() -> Vector2:
	var tx := (_theatre[0] + _theatre[2]) / 2.0
	var ty := (_theatre[1] + _theatre[3]) / 2.0
	return Vector2(tx * m_per_unit + float(meta.get("x_shift", 0)), float(meta.get("y_shift", 0)) - ty * m_per_unit)


# --- quadtree ------------------------------------------------------------------------------------

func _span(level: int) -> float:
	return _span0 * float(1 << level)


func _span_m(level: int) -> float:
	return _span(level) * m_per_unit


func _quads(level: int) -> int:
	if level > GEOM_MIN_LEVEL:
		return far_quads
	return int(meta.node_pixels) >> (_height_level - level)


func _parent(n: Vector3i) -> Vector3i:
	return Vector3i(n.x >> 1, n.y >> 1, n.z + 1)


func _inside(n: Vector3i) -> bool:
	var s := _span(n.z)
	return n.x * s < _theatre[2] and n.y * s < _theatre[3]


func _children(n: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dy in 2:
		for dx in 2:
			var c := Vector3i(n.x * 2 + dx, n.y * 2 + dy, n.z - 1)
			if _inside(c):
				out.append(c)
	return out


## Distance (m) from the focus to the node: horizontal distance to its square, the focus' height
## above the ground vertically.
func _dist(n: Vector3i) -> float:
	var s := _span(n.z)
	var dx := maxf(0.0, maxf(n.x * s - _eye.x, _eye.x - (n.x + 1) * s))
	var dy := maxf(0.0, maxf(n.y * s - _eye.y, _eye.y - (n.y + 1) * s))
	return Vector3(dx * m_per_unit, dy * m_per_unit, _eye.z).length()


## The original's LOD distances per terrain detail 1..5 relative to detail 4 (FUN_00408ea0 tables,
## the level-3 limit 2200 / 2500 / 2900 / 3200 / 3300 m); detail = 1 + 4 × the TERRAIN DETAIL
## slider (0.25 steps, default 0.75 -> 4).
const DETAIL_SCALE := [0.69, 0.78, 0.91, 1.0, 1.03]


func _detail_factor() -> float:
	var detail := clampi(roundi(4.0 * float(Settings.terrain_detail)), 0, 4)
	return split_factor * DETAIL_SCALE[detail]


func _should_split(n: Vector3i, d: float) -> bool:
	if n.z == 0 or d >= _detail_factor() * _span_m(n.z):
		return false
	return n.z > GEOM_MIN_LEVEL or _finest.get(n, 99) < n.z


## The node whose texture colours `n`: itself or its nearest ancestor with imagery.
func _colour_source(n: Vector3i) -> Vector3i:
	while not _colour_nodes.has(n) and n.z < _root_level:
		n = _parent(n)
	return n


## The node whose height texture `n` samples: its level-6 ancestor, or itself above level 6.
func _height_source(n: Vector3i) -> Vector3i:
	if n.z >= _height_level:
		return n
	var k := _height_level - n.z
	return Vector3i(n.x >> k, n.y >> k, _height_level)


func _key(kind: int, n: Vector3i) -> Vector4i:
	return Vector4i(kind, n.x, n.y, n.z)


## True when the node's textures are loaded; requests the missing ones (and marks them used).
func _ready_node(n: Vector3i, d: float, counts := false) -> bool:
	var ok := true
	for key in [_key(0, _colour_source(n)), _key(1, _height_source(n))]:
		var have := _res.has(key)
		if have:
			_res[key].used = Time.get_ticks_msec()
		else:
			ok = false
			_wanted[key] = minf(_wanted.get(key, INF), d)
		if counts or d < near_range:
			_near[key] = have
	return ok


func _select(n: Vector3i, d: float, draw: bool, selected: Dictionary) -> void:
	if _should_split(n, d):
		var kids := _children(n)
		var dists: Array[float] = []
		var all := true
		for c in kids:
			dists.append(_dist(c))
			if dists[-1] <= view_range and not _ready_node(c, dists[-1]):
				all = false
		if not all and draw:
			_blocked += 1
			if d < near_range:
				_blocked_near += 1
		for k in kids.size():
			if dists[k] <= view_range:
				_select(kids[k], dists[k], draw and all, selected)
		if all:
			return
	if draw:
		# ground_ready() waits for every drawn node, near or far: all count for ground_progress().
		if _ready_node(n, d, true):
			selected[n] = true
		else:
			_blocked += 1
			_blocked_near += 1


func _process(_delta: float) -> void:
	if meta.is_empty() or focus == null:
		return
	var loaded := _finish_jobs()
	# The tree is re-chosen when data arrived, the focus moved or every RESELECT_MS.
	var fp := focus.global_position
	if loaded or fp.distance_to(_last_focus) > RESELECT_M or Time.get_ticks_msec() - _last_select > RESELECT_MS:
		_reselect(fp)
	_start_jobs()


func _reselect(fp: Vector3) -> void:
	_last_focus = fp
	_last_select = Time.get_ticks_msec()
	var t := godot_to_terrain(fp)
	var g = height_at(fp)
	_eye = Vector3(t.x, t.y, maxf(0.0, fp.y - (g if g != null else 0.0)))
	_wanted.clear()
	_near.clear()
	_blocked = 0
	_blocked_near = 0
	var selected := {}
	var rs := _span(_root_level)
	for j in ceili(_theatre[3] / rs):
		for i in ceili(_theatre[2] / rs):
			var r := Vector3i(i, j, _root_level)
			var d := _dist(r)
			if d <= view_range:
				_select(r, d, true, selected)
	# The heights under the focus (for height_at) are always wanted.
	var under := _height_source(Vector3i(floori(t.x / _span0), floori(t.y / _span0), 0))
	if _inside(under):
		_ready_node(under, 0.0)
	if draw_nodes:
		_update_drawn(selected)
	_evict()


func _update_drawn(selected: Dictionary) -> void:
	for n in _drawn.keys():
		if not selected.has(n):
			_drawn[n].queue_free()
			_drawn.erase(n)
	for n in selected:
		if not _drawn.has(n):
			_drawn[n] = _add_node(n)


func _add_node(n: Vector3i) -> MeshInstance3D:
	var cs := _colour_source(n)
	var hs := _height_source(n)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("colour_tex", _res[_key(0, cs)].tex)
	mat.set_shader_parameter("height_tex", _res[_key(1, hs)].tex)
	var k := cs.z - n.z
	mat.set_shader_parameter("uv_origin", Vector2(n.x - (cs.x << k), n.y - (cs.y << k)) / float(1 << k))
	mat.set_shader_parameter("uv_scale", 1.0 / float(1 << k))
	# Height texels: 1024 per theatre node of level hs.z, i.e. 1024 >> (hs.z - n.z) per node.
	var hk := hs.z - n.z
	var h_span := float(meta.node_pixels) / float(1 << hk)
	mat.set_shader_parameter("h_origin", Vector2(n.x - (hs.x << hk), n.y - (hs.y << hk)) * h_span)
	mat.set_shader_parameter("h_span", h_span)
	mat.set_shader_parameter("h_texel_m", _span_m(n.z) / h_span)
	mat.set_shader_parameter("units_to_metres", m_per_unit)
	mat.set_shader_parameter("sea_level_raw", float(meta.sea_level_raw))
	mat.set_shader_parameter("height_scale", float(meta.height_scale))
	mat.set_shader_parameter("node_m", _span_m(n.z))
	# Skirt: deep enough to cover the height difference to a coarser neighbour's edge.
	mat.set_shader_parameter("skirt", 10.0 + 0.5 * _span_m(n.z) / _quads(n.z))
	# The part of the node inside the theatre (levels 7+ overhang its east / south edge).
	var s := _span(n.z)
	mat.set_shader_parameter("valid_uv", Vector2(clampf((_theatre[2] - n.x * s) / s, 0.0, 1.0),
			clampf((_theatre[3] - n.y * s) / s, 0.0, 1.0)))
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[n.z]
	mi.material_override = mat
	# Self-shadowing kilometre-sized nodes is not worth re-running the displacement per cascade.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = terrain_to_godot((n.x + 0.5) * s, (n.y + 0.5) * s)
	add_child(mi)
	return mi


## A `span`-metre square of `quads`² quads (UV 0..1, v southwards) and a skirt around it (UV2.x =
## 1 on the skirt's lower edge, lowered in the shader); heights are applied in the shader.
static func _grid_mesh(span: float, quads: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var row := quads + 1
	for y in row:
		for x in row:
			var uv := Vector2(x, y) / quads
			verts.append(Vector3((uv.x - 0.5) * span, 0.0, (uv.y - 0.5) * span))
			uvs.append(uv)
			uv2s.append(Vector2.ZERO)
	for y in quads:
		for x in quads:
			var a := y * row + x
			idx.append_array([a, a + 1, a + row + 1, a, a + row + 1, a + row])
	# Skirt: the border ring (clockwise) duplicated below, both windings so it shows from either side.
	var ring: Array[int] = []
	for x in quads:
		ring.append(x)
	for y in quads:
		ring.append(y * row + quads)
	for x in range(quads, 0, -1):
		ring.append(quads * row + x)
	for y in range(quads, 0, -1):
		ring.append(y * row)
	var base := verts.size()
	for v in ring:
		verts.append(verts[v])
		uvs.append(uvs[v])
		uv2s.append(Vector2(1, 0))
	for k in ring.size():
		var a: int = ring[k]
		var b: int = ring[(k + 1) % ring.size()]
		var la := base + k
		var lb := base + (k + 1) % ring.size()
		idx.append_array([a, b, lb, a, lb, la, a, lb, b, a, la, lb])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-span / 2, -2000, -span / 2), Vector3(span, 7000, span))
	return m


# --- loading -------------------------------------------------------------------------------------

## Hands this frame's wanted keys (nearest first) to the workers and starts workers up to max_jobs.
func _start_jobs() -> void:
	_results_mutex.lock()
	var keys := _wanted.keys().filter(func(k): return not _res.has(k) and not _busy.has(k) and not _results.has(k))
	keys.sort_custom(func(a, b): return _wanted[a] < _wanted[b])
	_queue = keys
	_results_mutex.unlock()
	for id in _jobs.filter(func(t): return WorkerThreadPool.is_task_completed(t)):
		WorkerThreadPool.wait_for_task_completion(id)
		_jobs.erase(id)
	while _jobs.size() < mini(max_jobs, keys.size()):
		_jobs.append(WorkerThreadPool.add_task(_work))


func _path(key: Vector4i) -> String:
	var base: String = _layer_dir.get(Vector3i(key.y, key.z, key.w), dir) if key.x == 0 else dir
	return base.path_join("L%d/%s_%d_%d.%s" % [key.w, "c" if key.x == 0 else "h", key.y, key.z, "jpg" if key.x == 0 else "png"])


## Worker: decodes queued keys until the queue is empty.
func _work() -> void:
	while true:
		_results_mutex.lock()
		if _queue.is_empty():
			_results_mutex.unlock()
			return
		var key: Vector4i = _queue.pop_front()
		_busy[key] = true
		_results_mutex.unlock()
		var img := _decode(key)
		_results_mutex.lock()
		_results[key] = img
		_busy.erase(key)
		_results_mutex.unlock()


## Colour -> mipmapped BC1; heights -> RG8 (R = high byte, G = low byte of the raw u16).
func _decode(key: Vector4i) -> Image:
	var img := Image.load_from_file(_path(key))
	if img != null:
		if key.x == 0:
			img.generate_mipmaps()
			img.compress(Image.COMPRESS_S3TC)
		else:
			img.convert(Image.FORMAT_RG8)
	return img


## Takes the decoded images (texture upload on the main thread); true if any. `block`: stops the
## queue and waits for the running decodes too.
func _finish_jobs(block := false) -> bool:
	if block:
		_stop_jobs()
	_results_mutex.lock()
	var done := _results
	_results = {}
	_results_mutex.unlock()
	var any := false
	for key in done:
		var img: Image = done[key]
		if img == null:
			push_error("terrain: cannot load %s" % _path(key))
			img = Image.create(1, 1, false, Image.FORMAT_RG8 if key.x == 1 else Image.FORMAT_RGB8)
		_res[key] = {"tex": ImageTexture.create_from_image(img), "img": img if key.x == 1 else null,
				"used": Time.get_ticks_msec()}
		any = true
	return any


func _evict() -> void:
	var now := Time.get_ticks_msec()
	var in_use := {}
	for n in _drawn:
		in_use[_key(0, _colour_source(n))] = true
		in_use[_key(1, _height_source(n))] = true
	for key in _res.keys():
		if now - int(_res[key].used) > EVICT_MS and not in_use.has(key):
			_res.erase(key)


## True while any node in range is still waiting for its data (full detail everywhere).
func missing_after_frame() -> bool:
	_results_mutex.lock()
	var pending := not (_queue.is_empty() and _busy.is_empty() and _results.is_empty())
	_results_mutex.unlock()
	return _blocked > 0 or pending


## Empties the queue and waits for the running decodes (their images stay in _results).
func _stop_jobs() -> void:
	_results_mutex.lock()
	_queue.clear()
	_results_mutex.unlock()
	for id in _jobs:
		WorkerThreadPool.wait_for_task_completion(id)
	_jobs.clear()


## How much of the ground_ready() work is done (0..1): the loaded share of the resources it waits
## for (the loading screen keeps its maximum).
func ground_progress() -> float:
	if ground_ready():
		return 1.0
	if _near.is_empty():
		return 0.0
	var n := 0
	for k in _near:
		if _near[k]:
			n += 1
	return float(n) / float(_near.size())


## Takes over the textures another terrain node has loaded (the front end's preload of the start
## area, terrain_preload.gd): its running decodes finish first. The next frame re-chooses the tree.
func adopt(other: Node) -> void:
	other._finish_jobs(true)
	if other.layers != layers:
		return  # loaded with other imagery (the Graphics page changed since)
	var now := Time.get_ticks_msec()
	for k in other._res:
		if not _res.has(k):
			_res[k] = other._res[k]
			_res[k].used = now
	_last_select = 0
	_last_focus = Vector3(INF, INF, INF)


## True once the ground around the focus is at full detail (nodes within `near_range`) and its
## heights are loaded: the flight can start.
func ground_ready() -> bool:
	return not meta.is_empty() and focus != null and _blocked_near == 0 and height_at(focus.global_position) != null


# --- heights and surface types -------------------------------------------------------------------

## Terrain height in metres at a Godot position (null while its heights aren't loaded): the
## level-6 elevation interpolated over triangles split along the north-west -> south-east diagonal
## (the original's inset heights, FUN_004281e0) — the surface the nodes of level <= 2 draw (one
## vertex per texel or finer). The sea is at its data height, as drawn.
func height_at(pos: Vector3) -> Variant:
	if meta.is_empty():
		return null
	var t := godot_to_terrain(pos)
	var s6 := _span(_height_level)
	var n := Vector3i(floori(t.x / s6), floori(t.y / s6), _height_level)
	var r = _res.get(_key(1, n))
	if r == null:
		return null
	var img: Image = r.img
	var upp := s6 / float(meta.node_pixels)
	var gx := clampf((t.x - n.x * s6) / upp, 0.0, float(meta.node_pixels))
	var gy := clampf((t.y - n.y * s6) / upp, 0.0, float(meta.node_pixels))
	var x0 := mini(floori(gx), int(meta.node_pixels) - 1)
	var y0 := mini(floori(gy), int(meta.node_pixels) - 1)
	var raw := _triangle(_raw(img, x0, y0), _raw(img, x0 + 1, y0), _raw(img, x0, y0 + 1),
			_raw(img, x0 + 1, y0 + 1), gx - x0, gy - y0)
	return (raw - float(meta.sea_level_raw)) / float(meta.height_scale) * m_per_unit


## Height inside a texel from its corners (a north-west, b north-east, c south-west, d south-east)
## at (fx, fy): the triangle a-b-d when fx >= fy, else a-c-d (terrain.gdshader does the same).
static func _triangle(a: float, b: float, c: float, d: float, fx: float, fy: float) -> float:
	if fx >= fy:
		return a + (b - a) * fx + (d - b) * fy
	return a + (d - c) * fx + (c - a) * fy


static func _raw(img: Image, x: int, y: int) -> float:
	var c := img.get_pixel(x, y)
	return float(roundi(c.r * 255.0) * 256 + roundi(c.g * 255.0))


## Parses the main BSP tree of terraintype.dat (pre-order nodes: i32 count, mask, has1, has0,
## then the split line as 4 f64 when has1, then the child1 subtree, then the child0 subtree).
func _load_terrain_types(path: String) -> void:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		push_error("terrain: %s not found — surface types unknown" % path)
		return
	var pos := 0
	var stack: Array[Vector2i] = [Vector2i(-1, 0)]  # (parent, child slot)
	while not stack.is_empty():
		var slot: Vector2i = stack.pop_back()
		var k := _bsp_mask.size()
		_bsp_mask.append(data.decode_s32(pos + 4))
		var has1 := data.decode_s32(pos + 8) == 1
		var has0 := data.decode_s32(pos + 12) == 1
		pos += 16
		for i in 4:
			_bsp_plane.append(data.decode_double(pos + 8 * i) if has1 else 0.0)
		if has1:
			pos += 32
		_bsp_child0.append(-1)
		_bsp_child1.append(-1)
		if slot.x >= 0:
			if slot.y == 1:
				_bsp_child1[slot.x] = k
			else:
				_bsp_child0[slot.x] = k
		if has0:
			stack.push_back(Vector2i(k, 0))
		if has1:
			stack.push_back(Vector2i(k, 1))


## Surface flags at a Godot position (terraintype.dat through FUN_004024b0: world metres truncated,
## shifted by (+0x151, −0x19a)): SURFACE_* bits; 0 when the file is missing.
func surface_at(pos: Vector3) -> int:
	if _bsp_mask.is_empty():
		return 0
	var x := float(int(world_origin.x + pos.x) + 0x151)
	var y := float(int(world_origin.y - pos.z) - 0x19a)
	var k := 0
	while _bsp_child0[k] >= 0 or _bsp_child1[k] >= 0:
		var p := k * 4
		var below := _bsp_plane[p] * x + _bsp_plane[p + 1] * y < _bsp_plane[p + 2] - _bsp_plane[p + 3]
		var next := _bsp_child0[k] if below else _bsp_child1[k]
		if next < 0:
			break
		k = next
	return _bsp_mask[k]


## Let running decode jobs finish before the node (and its mutex) goes away.
func _exit_tree() -> void:
	_stop_jobs()
