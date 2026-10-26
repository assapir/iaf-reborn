# Scenery (ours, Graphics → MORE, Settings.scenery; docs/scenery.md §3): the buildings and trees setup generates over
# the Survey of Israel 2 m photo, streamed around the terrain's focus. One cell per level-1 node of the mapi2015 layer
# (assets/converted/scenery/L1/s_<i>_<j>.bin, the layer's own keys); the cells within RANGE of the focus are loaded on
# worker threads (IafScenery parses the file), their meshes made on IafScenery's own threads (on the heights
# IafHeights has) and uploaded a chunk per frame, drawn as a near mesh (walls with windows, roofs; to NEAR m), a far
# mesh (bare prisms; NEAR to RANGE m) and one MultiMesh per tree kind (to TREES m). Owned by terrain.gd (its focus,
# its world origin, its layers). Rendering only: the queries (roof heights, the EO ray) are IafScenery's.
extends Node3D

const DIR := "converted/scenery"
## Buildings are drawn to RANGE (m). Cells are loaded within RANGE + AHEAD of the focus (horizontal, to the cell's
## square), so a cell is made and uploaded before it comes into view (1.5 km: 6 s at 250 m/s), and freed beyond
## RANGE + KEEP.
const RANGE := 4500.0
const AHEAD := 1500.0
const KEEP := 2500.0
const NEAR := 2500.0
const TREES := 2000.0
## Trees draw their full model to this distance (m), the far one beyond; they grow in over the last TREES_GROW m
## before TREES. Buildings: the near model to NEAR, the far one to RANGE, rising from the ground over the last GROW m.
## Each tree and building by its own distance (scenery_tree.gdshader, scenery.gdshader); a 500 m tile's mesh is drawn
## while any of its trees or buildings may be (TILE_REACH: half a tile's diagonal).
const TREES_NEAR := 700.0
const TREES_GROW := 300.0
const TILE_REACH := 360.0
const GROW := 400.0
## The cells re-chosen when the focus moved this far (m) or after this long (ms).
const RESELECT_M := 200.0
const RESELECT_MS := 1000
## Workers at once (the terrain's decodes have priority: 4 of them).
const MAX_JOBS := 2
## Cells drawn per frame (IafScenery makes their arrays on its threads; the main thread copies and uploads them).
const BUILDS_PER_FRAME := 1
## Damage states read back this often (ms).
const DAMAGE_MS := 1000
## Wall materials (iaf_tools::thirdparty::SCENERY_WALLS, in the cell file's wall index order: plaster, stone, concrete,
## corrugated steel), listed by setup in this file.
const WALL_LIST := "scenery.json"
const WALL_COUNT := 4
## Tree kinds (the cell file's TreeKind): trunk height, canopy [shape, bottom, top, radius] in metres for a 10 m tree,
## canopy colour (linear).
const KINDS := [
	[3.0, ["cone", 2.5, 10.0, 2.6], Color(0.05, 0.10, 0.04)],  # pine
	[3.0, ["ball", 2.5, 9.0, 3.6], Color(0.12, 0.15, 0.07)],  # broadleaf (olive, carob, oak)
	[8.5, ["fan", 8.8, 10.0, 3.8], Color(0.12, 0.17, 0.06)],  # palm: fronds arching from the trunk top
	[1.5, ["cone", 1.0, 10.0, 1.1], Color(0.04, 0.08, 0.03)],  # cypress
]
const TRUNK := Color(0.16, 0.11, 0.07)
const ImageryLayers := preload("res://terrain/imagery_layers.gd")
const GroundTextures := preload("res://terrain/ground_textures.gd")
const SHADER := preload("res://terrain/scenery.gdshader")
const TREE_SHADER := preload("res://terrain/scenery_tree.gdshader")
const FOLIAGE_SHADER := preload("res://terrain/scenery_foliage.gdshader")
const FOLIAGE_FAR_SHADER := preload("res://terrain/scenery_foliage_far.gdshader")
## The foliage textures setup composes (iaf_tools::foliage, under GroundTextures.dir()), the texture array's layers.
const FOLIAGE_LAYERS := ["broadleaf", "conifer", "palm", "bark"]
## Per tree kind with the foliage textures: its layer, leaf colour and trunk colour (linear albedo), crown sway (m).
const FOLIAGE := [
	[1, Color(0.12, 0.15, 0.085), Color(0.12, 0.09, 0.07)],  # pine (Aleppo pine: dark, grey-green)
	[0, Color(0.15, 0.18, 0.1), Color(0.11, 0.1, 0.09)],  # broadleaf (olive, carob: grey-green)
	[2, Color(0.15, 0.18, 0.08), Color(0.15, 0.13, 0.1)],  # palm
	[1, Color(0.09, 0.12, 0.07), Color(0.11, 0.085, 0.065)],  # cypress (dark green)
]
## With the foliage textures: the full model to FOLIAGE_NEAR m (its leaf cards cost more to fill than the plain
## canopy), cross-faded to the light one over TREES_BAND m each side.
const FOLIAGE_NEAR := 250.0
const TREES_BAND := 50.0

## The folder holding DIR ("" = Settings.assets_dir(); tests point it elsewhere).
static var base_dir := ""
## Detailed night lights at night: the windows lit (terrain_view.gd _night_detailed).
static var night := false
static var _walls: Texture2DArray
static var _walls_read := false
static var _tree_meshes: Array = []
static var _foliage: Texture2DArray
static var _foliage_read := false

var terrain: Node3D
## The Survey 2 m layer shown in Israel (mapi2015 = 1998 colours, mapi2015_modern = the photo's): the roofs' colours.
var modern := false
## false: load only (the front end's preload terrain); the flight's terrain adopts the loaded cells.
var draw := true
var _span := 0.0  # a cell's side (m)
## Vector2i -> {state: "wait" (not loaded) | "loaded" (in IafScenery, origin) | "preparing" (IafScenery making its
## meshes) | "prepared" (made, waiting in IafScenery) | "uploading" (node, mat; pieces arriving) | "built" (drawn) |
## "none" (no file)}.
var _cells := {}
var _live: Array = []  # the cells within RANGE + KEEP of the focus at the last reselect (the per-frame work's list)
var _view := Vector3.ZERO  # the camera away from the focus (terrain.away_view), else the focus
var _last_view := Vector3(INF, INF, INF)
var _queue: Array = []  # cells to load, nearest first (under the mutex)
var _busy := {}  # cells a worker has (under the mutex)
var _results := {}  # Vector2i -> worker result (under the mutex)
var _mutex := Mutex.new()
var _jobs: Array[int] = []
var _last_focus := Vector3(INF, INF, INF)
var _last_select := 0
var _last_damage := 0
var _night_shown := false
var _materials: Array[ShaderMaterial] = []


static func dir() -> String:
	return (base_dir if base_dir != "" else Settings.assets_dir()).path_join(DIR)


static func manifest() -> Dictionary:
	return Settings.load_json(dir().path_join("manifest.json"))


## Setup made the scenery and the game can read it.
static func available() -> bool:
	return not manifest().is_empty()


## The Survey 2 m layers (the only imagery scenery is shown over).
static func survey(id: String) -> bool:
	return id in ["mapi2015", "mapi2015_modern"]


## The render guard: Scenery on, the files there and a Survey 2 m layer among the terrain's `layers`.
static func wanted(layers: Array) -> bool:
	return Settings.scenery == "on" and available() and layers.any(func(l): return survey(String(l)))


## The cells (Vector2i -> true): the level-1 nodes of the Survey layer `id` (scenery stands only over its photo).
## Setup writes a file only for the nodes with a building or tree; the others read as "none" once.
static func cells_for(id: String) -> Dictionary:
	var out := {}
	for ij in ImageryLayers.manifest(id).get("nodes", {}).get("1", []):
		out[Vector2i(int(ij[0]), int(ij[1]))] = true
	return out


## The wall textures (the SCENERY list's colour over its mean, every mip level), read once; null when setup has
## not fetched them (the walls are then plain).
static func walls() -> Texture2DArray:
	if _walls_read:
		return _walls
	_walls_read = true
	var imgs: Array[Image] = []
	var mats: Array = Settings.load_json(GroundTextures.dir().path_join(WALL_LIST)).get("materials", [])
	if mats.size() != WALL_COUNT:
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


# --- scenery targets (docs/scenery.md §5) ---------------------------------------------------------------------------

## The original models a scenery target's marker draws when its building is not in the flight: an office block, or a
## factory from STAND_IN_AREA m² of footprint (inferred).
const STAND_INS := ["stationary/ofice/ofice1_h.gltf", "stationary/fctry/fctry1_h.gltf"]
const STAND_IN_AREA := 1500.0
const STAND_IN_NAMES := [["office block", "בניין משרדים"], ["factory", "מפעל"]]
const REASONS := {
	"off": ["Scenery is off", "התפאורה כבויה"],
	"release": ["the mission was made with another scenery", "המשימה נבנתה עם תפאורה אחרת"],
	"missing": ["the building is not in this scenery", "הבניין אינו בתפאורה הזו"],
}


## Why a scenery target's building (entity field `scenery` = "<i>_<j>:<index>") is not in this flight: "off" (Scenery
## off or not over the Survey 2 m layer), "release" (the mission's `scenery_release` is another setup's), "missing"
## (no such building); "" when it stands.
static func target_reason(e: Dictionary, release: String) -> String:
	if not wanted([Settings.imagery_israel]):
		return "off"
	if String(manifest().get("release", "")) != release:
		return "release"
	var id := String(e.get("scenery", "")).split(":")
	if id.size() != 2:
		return "missing"
	# The cell file's header: "IAFS", version, building count (crates/iaf-avionics/src/scenery.rs).
	var f := FileAccess.open(dir().path_join("L1/s_%s.bin" % id[0]), FileAccess.READ)
	if f == null or f.get_length() < 16:
		return "missing"
	f.seek(8)
	return "" if int(id[1]) < f.get_32() else "missing"


## The original model a scenery target stands in with (by its footprint, `scenery_area`).
static func stand_in(e: Dictionary) -> int:
	return 1 if float(e.get("scenery_area", 0.0)) >= STAND_IN_AREA else 0


## The briefing's lines on the mission's scenery targets (`lang` "en" / "he"): the building, the buildings around
## it, and the original model it is drawn as when its building is not in the flight.
static func target_lines(main: Dictionary, lang: String) -> Array:
	var he := 1 if lang == "he" else 0
	var out := []
	for e in main.get("entities", {}).get("items", []):
		if not (e is Dictionary and e.has("scenery") and int(e.get("0x14", 0)) == 0):
			continue
		var h := roundi(float(e.get("scenery_height", 0.0)))
		var n := int(e.get("scenery_count", 0))
		var line := (
			(
				"%s: בניין בגובה %d מ'; %d בניינים בטווח ק״מ."
				if he
				else "%s: a building %d m high; %d building%s within 1 km."
			)
			% ([String(e.get("0x2bc", "")), h, n] + ([] if he else ["" if n == 1 else "s"]))
		)
		var why := target_reason(e, String(main.get("scenery_release", "")))
		if why != "":
			line += (
				(" מוצג כ%s מקורי (%s)." if he else " Shown as an original %s (%s).")
				% [STAND_IN_NAMES[stand_in(e)][he], REASONS[why][he]]
			)
		out.append(line)
	return out


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
	m.set_shader_parameter("night", night)
	m.set_shader_parameter("near_m", NEAR)
	m.set_shader_parameter("far_m", RANGE)
	m.set_shader_parameter("grow_m", GROW)
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


## A 10 m tree of `kind` (KINDS), our own mesh, scaled per tree: with the foliage textures (foliage()) leaf cards
## round a solid core on a barked trunk (_foliage_tree); without them a six-sided trunk and a low-poly canopy in one
## colour. A tree kind's model: the full one, or `far` the light one for TREES_NEAR..TREES.
static func tree_mesh(kind: int, far := false) -> ArrayMesh:
	if _tree_meshes.is_empty():
		var tex := foliage()
		for f in [false, true]:
			for k in KINDS.size():
				if tex != null and f:
					_tree_meshes.append(_make_far_tree(k, _far_foliage_material(k)))
				elif tex != null:
					_tree_meshes.append(_foliage_tree(k, tex))
				elif f:
					_tree_meshes.append(_make_far_tree(k, _tree_material(KINDS[k][2], true)))
				else:
					_tree_meshes.append(_make_tree(k))
	return _tree_meshes[clampi(kind, 0, KINDS.size() - 1) + (KINDS.size() if far else 0)]


## The foliage textures (FOLIAGE_LAYERS, every mip level), read once; null when setup has not made them (the trees
## are then plain).
static func foliage() -> Texture2DArray:
	if _foliage_read:
		return _foliage
	_foliage_read = true
	var imgs: Array[Image] = []
	for l in FOLIAGE_LAYERS:
		var path := GroundTextures.dir().path_join("trees/%s.bc3" % l)
		var img := GroundTextures.mips(path, Image.FORMAT_DXT5, 16) if FileAccess.file_exists(path) else null
		if img == null:
			return null
		imgs.append(img)
	var t := Texture2DArray.new()
	if t.create_from_images(imgs) == OK:
		_foliage = t
	return _foliage


## Forgets the read textures and the made models (tests switch the folders).
static func reset_trees() -> void:
	_tree_meshes = []
	_foliage = null
	_foliage_read = false


## A textured tree of `kind` in one surface (scenery_foliage.gdshader: its vertex colour holds the occlusion, the sway,
## the solid core and the trunk): 16–30 leaf cards round a core, the trunk. The far model is the plain canopy
## (_make_far_tree, _far_foliage_material). A seeded generator: the same model every time.
static func _foliage_tree(kind: int, tex: Texture2DArray) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + kind
	var spec: Array = KINDS[kind]
	var c: Array = spec[1]
	match kind:
		0:
			_conifer(st, rng, c[1], c[2], c[3], 6, 5, -0.35)
		1:
			_broadleaf(st, rng, c[1], c[2], c[3], 16)
		2:
			_palm(st, rng, c[1], c[3], 10)
		3:
			_conifer(st, rng, c[1], c[2], c[3], 7, 3, 2.2)
	_trunk(st, 0.12 if kind == 2 else 0.18, 0.22 if kind == 2 else 0.3, spec[0] + 0.5, 6)
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("foliage", tex)
	m.set_shader_parameter("layer", float(FOLIAGE[kind][0]))
	m.set_shader_parameter("albedo", FOLIAGE[kind][1])
	m.set_shader_parameter("trunk", FOLIAGE[kind][2])
	m.set_shader_parameter("near_m", FOLIAGE_NEAR)
	m.set_shader_parameter("band_m", TREES_BAND)
	mesh.surface_set_material(0, m)
	return mesh


## The far model's material with the foliage textures (scenery_foliage_far.gdshader): the plain canopy shapes, solid
## (cut-out cards cost too much to fill over a forest), in the near model's colour, each tree its own shade.
static func _far_foliage_material(kind: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_FAR_SHADER
	m.set_shader_parameter("albedo", FOLIAGE[kind][1])
	m.set_shader_parameter("near_m", FOLIAGE_NEAR)
	m.set_shader_parameter("band_m", TREES_BAND)
	m.set_shader_parameter("far_m", TREES)
	m.set_shader_parameter("grow_m", TREES_GROW)
	return m


## One vertex: colour r = occlusion, g = sway, b = solid core, a = trunk (scenery_foliage.gdshader).
static func _vert(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.set_color(col)
	st.add_vertex(p)


## A leaf card: the texture's square centred at `at`, spanning `right` and `up` (the texture's u and −v); its corners
## take the crown's round normal about `centre` (radii `r`), dark toward the heart and the underside.
static func _card(st: SurfaceTool, at: Vector3, right: Vector3, up: Vector3, centre: Vector3, r: Vector3) -> void:
	var corners := [[-1, 1, Vector2(0, 0)], [1, 1, Vector2(1, 0)], [1, -1, Vector2(1, 1)], [-1, -1, Vector2(0, 1)]]
	var v := []
	for k in corners:
		var p: Vector3 = at + right * 0.5 * k[0] + up * 0.5 * k[1]
		var q := (p - centre) / r
		var n := q.normalized() if q.length() > 0.01 else Vector3.UP
		var ao := lerpf(0.4, 1.0, smoothstep(-1.0, 1.0, n.y)) * lerpf(0.65, 1.0, clampf(q.length(), 0.0, 1.0))
		v.append([p, n, k[2], Color(ao, clampf(q.length(), 0.0, 1.0), 0.0, 0.0)])
	for i in [0, 1, 2, 0, 2, 3]:
		_vert(st, v[i][0], v[i][1], v[i][2], v[i][3])


## A solid core: an ellipsoid (`c`, radii `r`) of `seg` × 3 faces, the clump texture tiled on it, dark (inside).
static func _core(st: SurfaceTool, c: Vector3, r: Vector3, seg: int, cone := false) -> void:
	var rings := 1 if cone else 3
	var pts := []
	for i in rings + 1:
		var lat := PI * i / rings
		var row := []
		for j in seg + 1:
			var lon := TAU * j / seg
			var y := cos(lat) if not cone else 1.0 - 2.0 * i
			var rad := sin(lat) if not cone else float(i)
			var d := Vector3(rad * cos(lon), y, rad * sin(lon))
			row.append([c + d * r, d.normalized(), Vector2(2.0 * j / seg, 1.5 * i / rings)])
		pts.append(row)
	for i in rings:
		for j in seg:
			var quad := [pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j]]
			for k in [0, 1, 2, 0, 2, 3]:
				var e: Array = quad[k]
				var ao := lerpf(0.3, 0.55, smoothstep(-1.0, 1.0, e[1].y))
				_vert(st, e[0], e[1], e[2], Color(ao, 0.3, 1.0, 0.0))


## A round crown (broadleaf): `n` cards spread over an ellipsoid from `bottom` to `top`, radius `r`, each facing out.
static func _broadleaf(
	st: SurfaceTool, rng: RandomNumberGenerator, bottom: float, top: float, r: float, n: int
) -> void:
	var c := Vector3(0, (bottom + top) / 2.0, 0)
	var radii := Vector3(r, (top - bottom) / 2.0, r)
	_core(st, c, radii * 0.78, 6)
	var size := 3.8
	for i in n:
		# A Fibonacci spiral over the sphere, nudged.
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var a := i * 2.39996 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(sqrt(1.0 - y * y) * cos(a), y, sqrt(1.0 - y * y) * sin(a)).normalized()
		# Out to the old canopy's size: the cards' leaves reach its surface (a smaller crown left gaps where a tree
		# had stood).
		var at := c + d * radii * rng.randf_range(0.68, 0.82)
		var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		t = t.rotated(d, rng.randf_range(0.0, TAU))
		var s := size * rng.randf_range(0.85, 1.15)
		_card(st, at, t * s, d.cross(t) * s, c, radii)


## A cone crown (pine, cypress): `tiers` rings of `per` cards from `bottom` to `top`, radius `r` at the bottom; each
## card reaches out from the axis, `rise` its slope (negative: drooping like a pine's branches, large: upright as a
## cypress's).
static func _conifer(
	st: SurfaceTool, rng: RandomNumberGenerator, bottom: float, top: float, r: float, tiers: int, per: int, rise: float
) -> void:
	var h := top - bottom
	var c := Vector3(0, bottom + h * 0.4, 0)
	var radii := Vector3(r, h * 0.6, r)
	_core(st, Vector3(0, bottom + h * 0.45, 0), Vector3(r * 0.6, h * 0.55, r * 0.6), 6, true)
	for i in tiers:
		var y := bottom + h * (i + 0.5) / tiers * 0.92
		var rad := r * (1.0 - (y - bottom) / h) + 0.25
		for j in per:
			var a := TAU * (j + rng.randf_range(-0.2, 0.2)) / per + i * 0.9
			var out := Vector3(cos(a), rise, sin(a)).normalized()
			var t := Vector3(-sin(a), 0, cos(a))
			var s := (rad * 1.5 + 0.6) * rng.randf_range(0.85, 1.15)
			var at := Vector3(cos(a) * rad * 0.45, y, sin(a) * rad * 0.45) + out * s * 0.3
			_card(st, at, t * s, out * s, c, radii)
	# The leader at the top: two crossed upright cards.
	var tip := Vector3(0, top - 0.9, 0)
	for k in 2:
		var t := Vector3(cos(k * PI / 2.0), 0, sin(k * PI / 2.0))
		_card(st, tip, t * 1.4, Vector3.UP * 1.8, c, radii)


## A palm's crown at `top` (the trunk's top): `n` fronds, each a strip arching out to `reach` and drooping, the frond
## texture along it (its base at v = 1); the young ones upright, the old ones hanging.
static func _palm(st: SurfaceTool, rng: RandomNumberGenerator, top: float, reach: float, n: int) -> void:
	var segs := 3
	for i in n:
		var a := TAU * (i + rng.randf_range(-0.25, 0.25)) / n
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x)
		var lift := rng.randf_range(-0.6, 1.0)  # >0 upright, <0 hanging
		var length := reach * rng.randf_range(0.95, 1.25)
		var rows := []
		for k in segs + 1:
			var t := float(k) / segs
			# Out along d, up then down: a parabola, its peak by the lift.
			var y := length * (0.55 + 0.35 * lift) * t - length * (0.75 - 0.2 * lift) * t * t
			var p := Vector3(0, top, 0) + d * length * t * (0.95 - 0.15 * maxf(lift, 0.0)) + Vector3(0, y, 0)
			var w := 2.5 * sin(PI * (0.08 + 0.84 * t)) if k > 0 else 0.3
			var ao := lerpf(0.55, 1.0, (lift + 0.6) / 1.6)
			var nrm := (Vector3.UP + d * 0.4).normalized()
			# A shallow V across: the leaflets fold up from the rib.
			var v := 0.97 - 0.94 * t
			(
				rows
				. append(
					[
						[p - side * w * 0.5 + Vector3(0, 0.12 * w, 0), nrm, Vector2(0, v), Color(ao, t, 0, 0)],
						[p, nrm, Vector2(0.5, v), Color(ao * 0.9, t, 0, 0)],
						[p + side * w * 0.5 + Vector3(0, 0.12 * w, 0), nrm, Vector2(1, v), Color(ao, t, 0, 0)],
					]
				)
			)
		for k in segs:
			for half in 2:
				var q := [rows[k][half], rows[k][half + 1], rows[k + 1][half + 1], rows[k + 1][half]]
				for m in [0, 1, 2, 0, 2, 3]:
					_vert(st, q[m][0], q[m][1], q[m][2], q[m][3])


## The trunk: `seg` sides, radius `r_top` / `r_foot`, `h` m high, the bark tiled about every 1.5 m.
static func _trunk(st: SurfaceTool, r_top: float, r_foot: float, h: float, seg: int) -> void:
	for j in seg:
		var q := []
		for e in [[j, 0.0], [j + 1, 0.0], [j + 1, h], [j, h]]:
			var a: float = TAU * e[0] / seg
			var rad := lerpf(r_foot, r_top, e[1] / h)
			var d := Vector3(cos(a), 0, sin(a))
			var ao := lerpf(0.55, 0.85, e[1] / h)
			q.append([d * rad + Vector3(0, e[1], 0), d, Vector2(float(e[0]) / seg, e[1] / 1.5), Color(ao, 0, 0, 1)])
		for m in [0, 2, 1, 0, 3, 2]:
			_vert(st, q[m][0], q[m][1], q[m][2], q[m][3])


## A tree surface's material: its colour, the model it belongs to (scenery_tree.gdshader picks per tree by distance).
static func _tree_material(colour: Color, far: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TREE_SHADER
	m.set_shader_parameter("albedo", colour)
	m.set_shader_parameter("far_model", far)
	m.set_shader_parameter("near_m", TREES_NEAR)
	m.set_shader_parameter("far_m", TREES)
	m.set_shader_parameter("grow_m", TREES_GROW)
	return m


## A palm's crown: `n` fronds from the trunk top (y 0), each rising to `h` at 40 % of its length and drooping to the
## tip at `radius`, 1.5 h below the top; both faces drawn (each triangle twice, wound both ways).
static func _fronds(n: int, radius: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.3
	for i in n:
		var a := TAU * (i + 0.5 * (i % 2)) / n
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * w
		var mid := d * radius * 0.4 + Vector3(0, h, 0)
		var tip := d * radius + Vector3(0, -1.5 * h, 0)
		for t in [[Vector3.ZERO, mid + side, mid - side], [mid + side, tip, mid - side]]:
			for tri in [t, [t[0], t[2], t[1]]]:
				for v in tri:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
	return st.commit()


static func _make_far_tree(kind: int, mat: Material) -> ArrayMesh:
	var c: Array = KINDS[kind][1]
	var h: float = c[2] - c[1]
	var canopy: Mesh
	if c[0] == "fan":
		canopy = _fronds(5, c[3], h)
	elif c[0] == "cone":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = c[3]
		cone.height = h
		cone.radial_segments = 6
		cone.rings = 0
		cone.cap_top = false
		cone.cap_bottom = false
		canopy = cone
	else:
		var ball := SphereMesh.new()
		ball.radius = c[3]
		ball.height = h
		ball.radial_segments = 6
		ball.rings = 2
		canopy = ball
	var st := SurfaceTool.new()
	# The canopy reaches down to the ground: no trunk to draw at this distance.
	st.append_from(canopy, 0, Transform3D(Basis(), Vector3(0, c[1] if c[0] == "fan" else c[1] + h / 2.0, 0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


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
	var canopy: Mesh
	var h: float = c[2] - c[1]
	if c[0] == "fan":
		canopy = _fronds(8, c[3], h)
	elif c[0] == "cone":
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
		[canopy, Transform3D(Basis(), Vector3(0, c[1] if c[0] == "fan" else c[1] + h / 2.0, 0)), spec[2]],
	]
	for p in parts:
		var st := SurfaceTool.new()
		st.append_from(p[0], 0, p[1])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _tree_material(p[2], false))
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
	# An F-key view on a far unit: the cells around that camera too (the jet's stay: its roofs and trees are solid).
	var away = terrain.away_view()
	_view = away if away != null else fp
	var now := Time.get_ticks_msec()
	if (
		fp.distance_to(_last_focus) > RESELECT_M
		or _view.distance_to(_last_view) > RESELECT_M
		or now - _last_select > RESELECT_MS
	):
		_reselect(fp)
	_build_some(fp)
	if draw:
		if now - _last_damage > DAMAGE_MS:
			_last_damage = now
			_refresh_damage()
		if night != _night_shown:
			_night_shown = night
			for m in _materials:
				m.set_shader_parameter("night", night)


func _reselect(fp: Vector3) -> void:
	_last_focus = fp
	_last_view = _view
	_last_select = Time.get_ticks_msec()
	var want := []
	_mutex.lock()
	var busy := _busy.merged(_results)  # cells whose result is not taken yet
	_mutex.unlock()
	# Only the cells around the focus (the grid is linear in Godot x / z) and the ones held before: a pass over every
	# cell of the layer (≈ 4 000) took 8–19 ms.
	var o := _corner(Vector2i.ZERO)
	var r := ceili((RANGE + KEEP) / _span)
	var around: Array = _live.duplicate()
	for at in [fp, _view]:
		var c := Vector2i(floori((at.x - o.x) / _span), floori((at.z - o.y) / _span))
		for i in range(c.x - r, c.x + r + 1):
			for j in range(c.y - r, c.y + r + 1):
				var k := Vector2i(i, j)
				if _cells.has(k) and not k in around:
					around.append(k)
	_live = []
	for k in around:
		var d := minf(_dist(k, fp), _dist(k, _view))
		if d <= RANGE + KEEP:
			_live.append(k)
		if d > RANGE + KEEP and _cells[k].state in ["loaded", "preparing", "prepared", "uploading", "built"]:
			_drop(k)
		elif d <= RANGE + AHEAD and _cells[k].state == "wait" and not busy.has(k):
			want.append([d, k])
	want.sort()
	_mutex.lock()
	_queue = want.map(func(w): return w[1])
	_mutex.unlock()
	for id in _jobs.filter(func(t): return WorkerThreadPool.is_task_completed(t)):
		WorkerThreadPool.wait_for_task_completion(id)
		_jobs.erase(id)
	while _jobs.size() < mini(MAX_JOBS, want.size()):
		_jobs.append(WorkerThreadPool.add_task(_work, false, "scenery"))


## Worker: reads the queued cells' files into IafScenery until the queue is empty. (IafScenery.prepare makes their
## meshes on its own threads: godot-rust builds Godot arrays on the main thread only.)
func _work() -> void:
	while true:
		_mutex.lock()
		if _queue.is_empty():
			_mutex.unlock()
			return
		var k: Vector2i = _queue.pop_front()
		_busy[k] = true
		_mutex.unlock()
		var ok: bool = IafScenery.load_cell(dir().path_join("L1/s_%d_%d.bin" % [k.x, k.y]), k.x, k.y)
		var r = IafScenery.cell_origin(k.x, k.y) if ok else null
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
		if done[k] == null:
			_cells[k] = {"state": "none"}  # no file for it (or unreadable): never retried
		else:
			_cells[k] = {"state": "loaded", "origin": done[k]}


## Starts IafScenery making the nearest loaded cells' meshes on its threads (MAX_JOBS at once), and uploads up to
## BUILDS_PER_FRAME made pieces (a mesh chunk or a cell's trees), nearest cell first. The front end's preload
## (draw false) only has them made, for the flight's scenery to adopt.
func _build_some(fp: Vector3) -> void:
	var ready := []
	var waiting := []
	var preparing := 0
	for k in _live:
		var c: Dictionary = _cells[k]
		if c.state == "preparing":
			preparing += 1
			var r: int = IafScenery.prepared(k.x, k.y)
			if r == 1:
				c.state = "prepared"
			elif r == -1:
				c.state = "loaded"  # the heights under it are not loaded yet: made again later
		if c.state == "prepared" and draw:
			_start_cell(k)
		if c.state == "uploading":
			ready.append([minf(_dist(k, fp), _dist(k, _view)), k])
		elif c.state == "loaded":
			waiting.append([minf(_dist(k, fp), _dist(k, _view)), k])
	ready.sort()
	var pieces := 0
	for t in ready:
		while pieces < BUILDS_PER_FRAME and _cells[t[1]].state == "uploading":
			_upload(t[1])
			pieces += 1
	waiting.sort()
	for t in waiting.slice(0, maxi(0, MAX_JOBS - preparing)):
		_cells[t[1]].state = "preparing"
		IafScenery.prepare(t[1].x, t[1].y, modern)


## A made cell's node and material; its pieces follow (_upload).
func _start_cell(k: Vector2i) -> void:
	var c: Dictionary = _cells[k]
	c.state = "uploading"
	var root := Node3D.new()
	root.name = "Cell_%d_%d" % [k.x, k.y]
	var o: Vector3 = c.origin
	var wo: Vector2 = terrain.world_origin
	# World frame (X east, Y north, Z up) -> Godot (x east, y up, z south) relative to the terrain's origin.
	root.position = Vector3(o.x - wo.x, o.z, -(o.y - wo.y))
	add_child(root)
	c.node = root
	var mat := _building_material(IafScenery.damage_index(k.x, k.y))
	_materials.append(mat)
	c.mat = mat


## One piece of a made cell: a chunk of its near or far buildings, or its trees; the cell is drawn when none is left.
func _upload(k: Vector2i) -> void:
	var c: Dictionary = _cells[k]
	var piece: Dictionary = IafScenery.take_next(k.x, k.y)
	if piece.is_empty():
		c.state = "built"
	elif piece.has("arrays"):
		var near: bool = piece.near
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			piece.arrays,
			[],
			{},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = c.mat
		# The ranges only cull whole tiles; the shader swaps and raises each building by its own distance.
		mi.set_instance_shader_parameter("far_model", not near)
		mi.visibility_range_begin = 0.0 if near else NEAR - TILE_REACH
		mi.visibility_range_end = (NEAR if near else RANGE) + TILE_REACH
		# The photo under it already holds the buildings' shadows.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(mi)
	else:
		for tile in piece.trees:
			var rows: PackedFloat32Array = tile[1]
			for far in [false, true]:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = tree_mesh(int(tile[0]), far)
				mm.instance_count = rows.size() / 12
				mm.buffer = rows
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				# The ranges only cull whole tiles; the shader cuts each tree at its own distance.
				var near_m := FOLIAGE_NEAR if foliage() != null else TREES_NEAR
				mmi.visibility_range_begin = maxf(0.0, near_m - TILE_REACH) if far else 0.0
				mmi.visibility_range_end = (TREES if far else near_m) + TILE_REACH
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				c.node.add_child(mmi)


## The damage states of the drawn cells, when they changed (a destroyed scenery target).
func _refresh_damage() -> void:
	for k in _live:
		var c: Dictionary = _cells[k]
		if c.has("mat"):
			var d: PackedByteArray = IafScenery.damage_index(k.x, k.y)
			if d != c.mat.get_meta("damage"):
				_set_damage(c.mat, d)


func _drop(k: Vector2i) -> void:
	var c: Dictionary = _cells[k]
	if c.has("node"):
		c.node.queue_free()
	if c.has("mat"):
		_materials.erase(c.mat)
	if c.has("origin"):
		IafScenery.drop_cell(k.x, k.y)
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
			if not (c.state in ["none", "built"] or (c.state in ["loaded", "preparing", "prepared"] and not draw)):
				return false
	return true


## The cells in IafScenery (Vector2i), drawn or not.
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
		if _cells.has(k) and c.state in ["loaded", "preparing", "prepared", "none"]:
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
			IafScenery.drop_cell(k.x, k.y)
