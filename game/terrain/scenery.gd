# Scenery (ours, Graphics → MORE, Settings.scenery; docs/scenery.md §3): the buildings and trees setup generates over
# the Survey of Israel 2 m photo, streamed around the terrain's focus. One cell per level-1 node of the mapi2015 layer
# (assets/converted/scenery/L1/s_<i>_<j>.bin, the layer's own keys); the cells within RANGE of the focus are loaded on
# worker threads (IafScenery parses the file and builds the mesh arrays in Rust, on the heights IafHeights has), then
# drawn as a near mesh (walls with windows, roofs; to NEAR m), a far mesh (bare prisms; NEAR to RANGE m) and one
# MultiMesh per tree kind (to TREES m). Owned by terrain.gd (its focus, its world origin, its layers). Rendering only:
# the queries (roof heights, the EO ray) are IafScenery's.
extends Node3D

const DIR := "converted/scenery"
## Cells are loaded within this distance (m) of the focus (horizontal, to the cell's square) and freed beyond
## RANGE + KEEP.
const RANGE := 8000.0
const KEEP := 1000.0
const NEAR := 3000.0
const TREES := 2000.0
## The visibility ranges' fade margins (m).
const FADE := 300.0
## The cells re-chosen when the focus moved this far (m) or after this long (ms).
const RESELECT_M := 200.0
const RESELECT_MS := 1000
## Workers at once (the terrain's decodes have priority: 4 of them).
const MAX_JOBS := 2
## Meshes built per frame (the upload runs on the main thread).
const BUILDS_PER_FRAME := 2
## Damage states read back this often (ms).
const DAMAGE_MS := 1000
## Wall materials (iaf_tools::thirdparty::SCENERY, the cell file's wall index): [ambientCG id, mean colour (linear)].
const WALLS := [
	["Plaster003", Color(0.80, 0.78, 0.72)],
	["Bricks084", Color(0.66, 0.55, 0.38)],
	["Concrete034", Color(0.45, 0.45, 0.43)],
	["CorrugatedSteel005", Color(0.40, 0.44, 0.46)],
]
const WALL_LIST := "scenery.json"
## Tree kinds (the cell file's TreeKind): trunk height, canopy [shape, bottom, top, radius] in metres for a 10 m tree,
## canopy colour (linear).
const KINDS := [
	[3.0, ["cone", 2.5, 10.0, 2.6], Color(0.05, 0.10, 0.04)],  # pine
	[3.0, ["ball", 2.5, 9.0, 3.6], Color(0.12, 0.15, 0.07)],  # broadleaf (olive, carob, oak)
	[9.0, ["ball", 8.4, 10.0, 3.0], Color(0.10, 0.16, 0.05)],  # palm
	[1.5, ["cone", 1.0, 10.0, 1.1], Color(0.04, 0.08, 0.03)],  # cypress
]
const TRUNK := Color(0.16, 0.11, 0.07)
const ImageryLayers := preload("res://terrain/imagery_layers.gd")
const GroundTextures := preload("res://terrain/ground_textures.gd")
const SHADER := preload("res://terrain/scenery.gdshader")

## The Rust side: IafScenery when the extension has it; tests put a script with the same static funcs here.
static var backend: Object = null
## The folder holding DIR ("" = Settings.assets_dir(); tests point it elsewhere).
static var base_dir := ""
## Detailed night lights at night: the windows lit (terrain_view.gd _night_detailed).
static var night := false
static var _walls: Texture2DArray
static var _walls_read := false
static var _tree_meshes: Array = []

var terrain: Node3D
## The Survey 2 m layer shown in Israel (mapi2015 = 1998 colours, mapi2015_modern = the photo's): the roofs' colours.
var modern := false
## false: load only (the front end's preload terrain); the flight's terrain adopts the loaded cells.
var draw := true
var _span := 0.0  # a cell's side (m)
var _cells := {}  # Vector2i -> {state: "wait" | "busy" | "retry" | "built" | "none", ...}
var _queue: Array = []  # [cell, loaded] to load, nearest first (under the mutex)
var _busy := {}  # cells a worker has (under the mutex)
var _results := {}  # Vector2i -> worker result (under the mutex)
var _mutex := Mutex.new()
var _jobs: Array[int] = []
var _last_focus := Vector3(INF, INF, INF)
var _last_select := 0
var _last_damage := 0
var _night_shown := false
var _materials: Array[ShaderMaterial] = []


## Calls the Rust side (IafScenery's static funcs, or the test's backend).
static func call_api(method: String, args: Array = []) -> Variant:
	if backend != null:
		return backend.callv(method, args)
	return ClassDB.class_call_static.callv(["IafScenery", method] + args)


static func dir() -> String:
	return (base_dir if base_dir != "" else Settings.assets_dir()).path_join(DIR)


static func manifest() -> Dictionary:
	return Settings.load_json(dir().path_join("manifest.json"))


## Setup made the scenery and the game can read it.
static func available() -> bool:
	return (backend != null or ClassDB.class_exists("IafScenery")) and not manifest().is_empty()


## The Survey 2 m layers (the only imagery scenery is shown over).
static func survey(id: String) -> bool:
	return id in ["mapi2015", "mapi2015_modern"]


## The render guard: Scenery on, the files there and a Survey 2 m layer among the terrain's `layers`.
static func wanted(layers: Array) -> bool:
	return Settings.scenery == "on" and available() and layers.any(func(l): return survey(String(l)))


## The cells (Vector2i -> true): the manifest's cells that the Survey layer `id` has a level-1 node for.
static func cells_for(id: String) -> Dictionary:
	var have := {}
	for ij in ImageryLayers.manifest(id).get("nodes", {}).get("1", []):
		have[Vector2i(int(ij[0]), int(ij[1]))] = true
	var out := {}
	for c in manifest().get("cells", []):
		var k := Vector2i.ZERO
		if c is String:
			var p := String(c).split("_")
			k = Vector2i(int(p[0]), int(p[1]))
		else:
			k = Vector2i(int(c[0]), int(c[1]))
		if have.has(k):
			out[k] = true
	return out


## The wall textures (the SCENERY list's colour over its mean, every mip level), read once; null when setup has
## not fetched them (the walls are then plain).
static func walls() -> Texture2DArray:
	if _walls_read:
		return _walls
	_walls_read = true
	var imgs: Array[Image] = []
	var mats: Array = Settings.load_json(GroundTextures.dir().path_join(WALL_LIST)).get("materials", [])
	if mats.size() != WALLS.size():
		return null
	for m in mats:
		var img := GroundTextures.mips(
			GroundTextures.dir().path_join(String(m.id)).path_join("albedo.bc1"), Image.FORMAT_DXT1, 8
		)
		if img == null:
			return null
		imgs.append(img)
	var t := Texture2DArray.new()
	if t.create_from_images(imgs) == OK:
		_walls = t
	return _walls


## Draws the building and tree materials once behind the loading screen (their shaders compile there, not at the
## first town), as Gltf.ModelDetail.warm_up; null when Scenery is off.
static func warm_up(camera: Camera3D, layers: Array) -> Node3D:
	if not wanted(layers):
		return null
	var n := Node3D.new()
	n.name = "SceneryWarmUp"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.001, 0.001)
	var mats: Array[Material] = [_building_material(PackedByteArray())]
	for kind in KINDS.size():
		var tm: ArrayMesh = tree_mesh(kind)
		for s in tm.get_surface_count():
			mats.append(tm.surface_get_material(s))
	for k in mats.size():
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0.0001 * k, 0.0, -0.5)
		n.add_child(mi)
	camera.add_child(n)
	return n


static func _building_material(damage: PackedByteArray) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var w := walls()
	m.set_shader_parameter("walls", w)
	m.set_shader_parameter("has_walls", w != null)
	m.set_shader_parameter("wall_mean", PackedColorArray(WALLS.map(func(x): return x[1])))
	m.set_shader_parameter("night", night)
	_set_damage(m, damage)
	return m


## The cell's damage states (a byte per building, 0 = intact) as a 256-wide R8 texture.
static func _set_damage(m: ShaderMaterial, damage: PackedByteArray) -> void:
	var rows := maxi(1, ceili(damage.size() / 256.0))
	var data := damage.duplicate()
	data.resize(256 * rows)
	var img := Image.create_from_data(256, rows, false, Image.FORMAT_R8, data)
	m.set_shader_parameter("damage", ImageTexture.create_from_image(img))
	m.set_meta("damage", damage)


## A 10 m tree of `kind` (KINDS): a six-sided trunk and a low-poly canopy, our own mesh; scaled per tree.
static func tree_mesh(kind: int) -> ArrayMesh:
	if _tree_meshes.is_empty():
		for k in KINDS.size():
			_tree_meshes.append(_make_tree(k))
	return _tree_meshes[clampi(kind, 0, KINDS.size() - 1)]


static func _make_tree(kind: int) -> ArrayMesh:
	var spec: Array = KINDS[kind]
	var trunk_h: float = spec[0]
	var c: Array = spec[1]
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12 if kind == 2 else 0.18
	trunk.bottom_radius = 0.22 if kind == 2 else 0.3
	trunk.height = trunk_h + 0.5
	trunk.radial_segments = 6
	trunk.rings = 1
	trunk.cap_top = false
	trunk.cap_bottom = false
	var canopy: PrimitiveMesh
	var h: float = c[2] - c[1]
	if c[0] == "cone":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = c[3]
		cone.height = h
		cone.radial_segments = 7
		cone.rings = 2
		cone.cap_top = false
		canopy = cone
	else:
		var ball := SphereMesh.new()
		ball.radius = c[3]
		ball.height = h
		ball.radial_segments = 8
		ball.rings = 4
		canopy = ball
	var parts := [
		[trunk, Transform3D(Basis(), Vector3(0, trunk.height / 2.0, 0)), TRUNK],
		[canopy, Transform3D(Basis(), Vector3(0, c[1] + h / 2.0, 0)), spec[2]],
	]
	for p in parts:
		var st := SurfaceTool.new()
		st.append_from(p[0], 0, p[1])
		st.commit(mesh)
		var m := StandardMaterial3D.new()
		m.albedo_color = p[2]
		m.roughness = 1.0
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	return mesh


func _ready() -> void:
	var id := ""
	for l in terrain.layers:
		if survey(String(l)):
			id = String(l)
			break
	modern = id == "mapi2015_modern"
	_span = terrain._span(1) * terrain.m_per_unit
	for k in cells_for(id):
		_cells[k] = {"state": "wait"}


## A cell's north-west corner (Godot x, z).
func _corner(k: Vector2i) -> Vector2:
	var p: Vector3 = terrain.terrain_to_godot(k.x * terrain._span(1), k.y * terrain._span(1))
	return Vector2(p.x, p.z)


func _dist(k: Vector2i, f: Vector3) -> float:
	var r := Rect2(_corner(k), Vector2(_span, _span))
	var q := Vector2(f.x, f.z)
	return q.distance_to(q.clamp(r.position, r.end))


func _process(_delta: float) -> void:
	if terrain.focus == null:
		return
	_finish_jobs()
	var fp: Vector3 = terrain.focus.global_position
	var now := Time.get_ticks_msec()
	if fp.distance_to(_last_focus) > RESELECT_M or now - _last_select > RESELECT_MS:
		_reselect(fp)
	if draw:
		_build_some(fp)
		if now - _last_damage > DAMAGE_MS:
			_last_damage = now
			_refresh_damage()
		if night != _night_shown:
			_night_shown = night
			for m in _materials:
				m.set_shader_parameter("night", night)


func _reselect(fp: Vector3) -> void:
	_last_focus = fp
	_last_select = Time.get_ticks_msec()
	var want := []
	_mutex.lock()
	var busy := _busy.merged(_results)  # cells whose result is not taken yet
	_mutex.unlock()
	for k in _cells:
		var c: Dictionary = _cells[k]
		var d := _dist(k, fp)
		if d > RANGE + KEEP and c.state in ["built", "retry"] and not busy.has(k):
			_drop(k)
		elif d <= RANGE and c.state in ["wait", "retry"]:
			want.append([d, k])
	want.sort()
	_mutex.lock()
	want = want.filter(func(w): return not busy.has(w[1]))
	_queue = want.map(func(w): return [w[1], _cells[w[1]].has("origin")])
	_mutex.unlock()
	for id in _jobs.filter(func(t): return WorkerThreadPool.is_task_completed(t)):
		WorkerThreadPool.wait_for_task_completion(id)
		_jobs.erase(id)
	while _jobs.size() < mini(MAX_JOBS, want.size()):
		_jobs.append(WorkerThreadPool.add_task(_work, false, "scenery"))


## Worker: loads queued cells and builds their arrays until the queue is empty.
func _work() -> void:
	while true:
		_mutex.lock()
		if _queue.is_empty():
			_mutex.unlock()
			return
		var q: Array = _queue.pop_front()
		var k: Vector2i = q[0]
		var loaded: bool = q[1]
		_busy[k] = true
		_mutex.unlock()
		var r := {}
		if loaded or call_api("load_cell", [dir().path_join("L1/s_%d_%d.bin" % [k.x, k.y]), k.x, k.y]):
			r = {
				"origin": call_api("cell_origin", [k.x, k.y]),
				"near": call_api("mesh_arrays", [k.x, k.y, true, modern]),
				"far": call_api("mesh_arrays", [k.x, k.y, false, modern]),
				"trees": call_api("trees", [k.x, k.y]),
			}
		_mutex.lock()
		_results[k] = r
		_busy.erase(k)
		_mutex.unlock()


func _finish_jobs() -> void:
	_mutex.lock()
	var done := _results
	_results = {}
	_mutex.unlock()
	for k in done:
		var r: Dictionary = done[k]
		var c: Dictionary = _cells[k]
		if r.is_empty():
			c.state = "none"  # no file for it (or unreadable): never retried
			continue
		c.origin = r.origin
		# No arrays: the heights under the cell are not loaded yet (or it has no buildings).
		var centre := _corner(k) + Vector2(_span, _span) / 2.0
		if (r.near as Array).is_empty() and terrain.height_at(Vector3(centre.x, 0, centre.y)) == null:
			c.state = "retry"
			continue
		c.near = r.near
		c.far = r.far
		c.trees = r.trees
		c.state = "built"


## Turns up to BUILDS_PER_FRAME loaded cells into nodes, nearest first.
func _build_some(fp: Vector3) -> void:
	var todo := []
	for k in _cells:
		if _cells[k].state == "built" and not _cells[k].has("node"):
			todo.append([_dist(k, fp), k])
	todo.sort()
	for t in todo.slice(0, BUILDS_PER_FRAME):
		_build(t[1])


func _build(k: Vector2i) -> void:
	var c: Dictionary = _cells[k]
	var root := Node3D.new()
	root.name = "Cell_%d_%d" % [k.x, k.y]
	var o: Vector3 = c.origin
	var wo: Vector2 = terrain.world_origin
	# World frame (X east, Y north, Z up) -> Godot (x east, y up, z south) relative to the terrain's origin.
	root.position = Vector3(o.x - wo.x, o.z, -(o.y - wo.y))
	add_child(root)
	c.node = root
	var mat: ShaderMaterial = null
	for near in [true, false]:
		var arrays: Array = c.near if near else c.far
		if arrays.is_empty():
			continue
		if mat == null:
			mat = _building_material(call_api("damage_index", [k.x, k.y]))
			_materials.append(mat)
			c.mat = mat
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.visibility_range_begin = 0.0 if near else NEAR
		mi.visibility_range_begin_margin = 0.0 if near else FADE
		mi.visibility_range_end = NEAR if near else RANGE
		mi.visibility_range_end_margin = FADE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not near:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var trees: Dictionary = c.trees
	for kind in trees:
		var rows: PackedFloat32Array = trees[kind]
		if rows.size() < 12:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tree_mesh(int(kind))
		mm.instance_count = rows.size() / 12
		mm.buffer = rows
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = TREES
		mmi.visibility_range_end_margin = FADE
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	# The arrays are uploaded; only the node keeps them.
	c.erase("near")
	c.erase("far")
	c.erase("trees")


## The damage states of the drawn cells, when they changed (a destroyed scenery target).
func _refresh_damage() -> void:
	for k in _cells:
		var c: Dictionary = _cells[k]
		if c.has("mat"):
			var d: PackedByteArray = call_api("damage_index", [k.x, k.y])
			if d != c.mat.get_meta("damage"):
				_set_damage(c.mat, d)


func _drop(k: Vector2i) -> void:
	var c: Dictionary = _cells[k]
	if c.has("node"):
		c.node.queue_free()
	if c.has("mat"):
		_materials.erase(c.mat)
	if c.has("origin"):
		call_api("drop_cell", [k.x, k.y])
	_cells[k] = {"state": "wait"}


## The near cells are drawn (ground_ready() waits for them): every cell within NEAR of the focus is built or has
## no file.
func ground_ready() -> bool:
	if terrain.focus == null:
		return false
	var fp: Vector3 = terrain.focus.global_position
	for k in _cells:
		if _dist(k, fp) <= NEAR:
			var c: Dictionary = _cells[k]
			if not (c.state == "none" or (c.state == "built" and (c.has("node") or not draw))):
				return false
	return true


## The cells loaded with the drawn cells (loaded cells, Vector2i keys).
func loaded() -> Array:
	return _cells.keys().filter(func(k): return _cells[k].has("origin"))


func drawn() -> Array:
	return _cells.keys().filter(func(k): return _cells[k].has("node"))


## Takes over the cells another scenery node loaded (the front end's preload terrain), when it shows the same look.
func adopt(other: Node) -> void:
	other._stop_jobs()
	other._finish_jobs()
	if other.modern != modern:
		return
	for k in other._cells:
		var c: Dictionary = other._cells[k]
		if _cells.has(k) and c.state in ["built", "retry", "none"] and not c.has("node"):
			_cells[k] = c
		other._cells[k] = {"state": "wait"}
	_last_focus = Vector3(INF, INF, INF)


func _stop_jobs() -> void:
	_mutex.lock()
	_queue.clear()
	_mutex.unlock()
	for id in _jobs:
		WorkerThreadPool.wait_for_task_completion(id)
	_jobs.clear()


func _exit_tree() -> void:
	_stop_jobs()
	_finish_jobs()
	for k in _cells:
		if _cells[k].has("origin"):
			call_api("drop_cell", [k.x, k.y])
