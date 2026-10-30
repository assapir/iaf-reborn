# Night lights = Detailed (docs/rendering.md §5.1, docs/deviations.md §2): the towns' lights at night, placed from the
# scenery's building footprints (setup's scenery, docs/scenery.md; any Scenery switch) by IafCityLights
# (crates/iaf-avionics/src/city_lights.rs): street lamps along the facades, lit windows, porch lights, red
# obstruction lights on the towers, with Roads Detailed lamps along the lit roads (also beyond the buildings, outside
# Israel), and a faint haze over the dense centres (terrain/city_glow.gdshaderinc). Ours: the original's only town
# lights are its LT_ sets (Damascus).
# Blocks of 4 × 4 scenery cells (≈ 10 km), three point meshes each by the lights' rank: within FAR_RANGE a block
# draws its farthest points (a fiftieth of its lights), within MID_RANGE also its far points (to a tenth), within
# NEAR_RANGE also its near points (the rest). The shader keeps all lights near the camera and thins them to the tenth
# by 6 km and to the fiftieth by 40 km; a light under its minimum size keeps its energy, so a far town reads as an even
# carpet of the same brightness instead of a white blaze. The lights are emitters seen through clear night air: they
# dim and redden by a thin share of the fog (EXT), and the haze's fog is undone to the same share, so the far coast
# stays a lit carpet. The lights thread lives in Rust (a std thread: no Godot pool task to wait for at quit).
extends Node3D

const Scenery := preload("res://terrain/scenery.gd")
const GroundRoads := preload("res://terrain/ground_roads.gd")

## A block's mesh k (0: its farthest points, 1: its far points, 2: its near points) is drawn within RANGES[k] (its
## square's distance, m) and dropped KEEP farther.
const FAR_RANGE := 120000.0
const MID_RANGE := 45000.0
const NEAR_RANGE := 8000.0
const RANGES := [FAR_RANGE, MID_RANGE, NEAR_RANGE]
const KEEP := 3000.0
## The share of a block's lights in its mesh 0, and in its meshes 0 and 1 (IafCityLights SHARES).
const XFAR_SHARE := 0.02
const FAR_SHARE := 0.1
## The lights' extinction: this share of the scene's fog (lights seen through clear night air).
const EXT := 0.35
const POLL := 1.0
## Made blocks taken per frame.
const TAKES := 3

## A city light: a small bright core and a soft halo, size_m wide in the world, at least min_px wide on screen (at
## 1080 rows), smaller the dimmer it is. COLOR: colour × brightness in RGB, the light's rank in A. Within keep_near
## every light shows; by keep_far only those of rank below far_share, by xkeep_far below xfar_share. Drawn larger than
## its glow (its minimum size), a light keeps the glow's energy × glare, the kept far ones the dropped ones' too. A
## light is pulled toward the eye by its size and 1 % of its distance, so the coarser far terrain does not hide it.
## Far points dim and redden by `ext` of the fog (blue twice as fast as red) and fade out over the last 20 % of
## `range`.
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float size_m = 5.0;
uniform float min_px = 1.0;
uniform float min_px_near = 1.5;
uniform float max_px = 18.0;
uniform float fog_k = 0.00003;
uniform float vp_h = 1080.0;
uniform float keep_near = 1500.0;
uniform float keep_far = 6000.0;
uniform float far_share = 0.1;
uniform float xkeep_near = 25000.0;
uniform float xkeep_far = 40000.0;
uniform float xfar_share = 0.02;
uniform float ext = 0.35;
uniform float range = 120000.0;
uniform float glare = 3.0;
uniform float bright = 5.0;
varying vec3 col;
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = max(-v.z, 1.0);
	float keep = mix(1.0, far_share, smoothstep(keep_near, keep_far, d));
	keep = mix(keep, xfar_share, smoothstep(xkeep_near, xkeep_far, d));
	float on = 1.0 - smoothstep(keep * 0.8, keep, COLOR.a);
	float b = max(COLOR.r, max(COLOR.g, COLOR.b));
	float rows = vp_h / 1080.0;
	float px = size_m * (0.35 + 0.65 * b) * abs(PROJECTION_MATRIX[1][1]) * 0.5 * vp_h / d;
	// Near lights a little larger (a 1-pixel point fades under TAA's blend); far ones 1 pixel (the fill is the cost).
	float lo = mix(min_px_near, min_px, smoothstep(3000.0, 10000.0, d)) * rows;
	// Under its minimum size a light keeps its energy (its glow's area): a far town is as bright on average as a near
	// one, a carpet instead of a white blaze. The kept far lights carry the dropped ones' energy; a floor keeps a
	// faint sparkle.
	float e = clamp(glare * px * px / (lo * lo) / keep, 0.1, 3.0);
	vec3 fade = exp(-ext * fog_k * d * vec3(0.75, 1.0, 1.5)) * on * e;
	fade *= 1.0 - smoothstep(range * 0.8, range, d);
	col = COLOR.rgb * fade * bright;
	POINT_SIZE = on > 0.0 ? clamp(px, lo, max_px * rows) : 0.0;
	float pull = size_m + 0.01 * d;
	POSITION = on > 0.0 ? PROJECTION_MATRIX * vec4(v.xyz * max(d - pull, 0.5) / d, 1.0) : vec4(2.0, 2.0, 2.0, 1.0);
}
void fragment() {
	vec2 c = POINT_COORD * 2.0 - 1.0;
	float r = length(c);
	float core = smoothstep(0.45, 0.0, r);
	float halo = pow(max(1.0 - r, 0.0), 3.0);
	ALBEDO = col * (core * 3.0 + halo * 0.9);
}
"""

## The haze over the dense lamp clusters (terrain/city_glow.gdshaderinc): its strength at a full square.
const GLOW_K := 0.12
## The glow texture, its rect and strength now, for the clouds' light from below (cloud_layer.gd, volumetric_clouds.gd;
## the RenderingServer does not read global shader parameters back at run time).
static var glow_texture: Texture2D
static var glow_rect := Vector4.ZERO
static var glow_strength := 0.0

var _tv: Node
var _mat: ShaderMaterial
var _glow: ImageTexture
var _glow_asked := false
## The glow's strength now (terrain.gdshader city_glow_k).
var glow_k := 0.0
## Vector2i block -> {meshes: [MeshInstance3D or null] × 3 (RANGES), asking: bool, stale: bool (to be made again: the
## road lamps switched; its points shown until then)}
var _blocks := {}
## The blocks are made with the road lamps (IafCityLights.set_road_lamps).
var _road_lamps := false
var _poll := 0.0


## Setup made the scenery (its buildings place the lights).
static func available() -> bool:
	return Scenery.available()


## The town lights for the flight scene `tv` (terrain_view.gd).
func setup(tv: Node) -> void:
	_tv = tv
	name = "CityLights"
	IafCityLights.open(Scenery.dir())
	# Roads = Detailed: lamps along the lit roads too, and the road layer's blocks beyond the buildings' (_process
	# follows a change during the flight).
	_road_lamps = GroundRoads.wanted()
	IafCityLights.set_road_lamps(_road_lamps)
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("range", FAR_RANGE)
	_mat.set_shader_parameter("far_share", FAR_SHARE)
	_mat.set_shader_parameter("xfar_share", XFAR_SHARE)
	_mat.set_shader_parameter("ext", EXT)


## The scene's fog and the 3D render's rows (night_lights.gd set_gain). The haze's fog is undone to EXT of it.
func set_view(fog_density: float, rows: float) -> void:
	_mat.set_shader_parameter("fog_k", fog_density)
	_mat.set_shader_parameter("vp_h", rows)
	RenderingServer.global_shader_parameter_set("city_glow_fog", fog_density * (1.0 - EXT))


func _process(delta: float) -> void:
	_poll -= delta
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_visible_in_tree():
		return
	# Roads switched during the flight: every block made again now (the road-only blocks come or go at this poll).
	if GroundRoads.on() != _road_lamps:
		_road_lamps = GroundRoads.on()
		IafCityLights.set_road_lamps(_road_lamps)
		for b: Dictionary in _blocks.values():
			b.stale = true
		_poll = 0.0
	# Made blocks reach the GPU a few per frame (a dense block is ≈ 130 000 points).
	var taken := 0
	for key: Vector2i in _blocks:
		if taken < TAKES and _blocks[key].asking:
			taken += int(_take(key, _blocks[key]))
	if _poll > 0.0:
		return
	_poll = POLL
	if _glow_asked and _glow == null:
		_take_glow()
	var w: Vector3 = _tv.scene_to_world(cam.global_position)
	var near: PackedInt32Array = IafCityLights.blocks_near(w.x, w.y, FAR_RANGE + KEEP)
	var seen := {}
	for k in range(0, near.size(), 3):
		var key := Vector2i(near[k], near[k + 1])
		var d := float(near[k + 2])
		seen[key] = true
		if not _blocks.has(key):
			_blocks[key] = {"meshes": [null, null, null], "asking": false, "stale": false}
		var b: Dictionary = _blocks[key]
		if b.asking:
			continue
		var has: int = b.meshes.rfind_custom(func(m): return m != null)
		if b.stale:
			b.stale = false
			if has >= 0:
				IafCityLights.request(key.x, key.y, has)
				b.asking = true
				continue
		var want: int = RANGES.rfind_custom(func(r): return d <= r)
		if want > has:
			IafCityLights.request(key.x, key.y, want)
			b.asking = true
		elif has > 0 and d > RANGES[has] + KEEP:
			b.meshes[has].queue_free()
			b.meshes[has] = null
	for key in _blocks.keys():
		if not seen.has(key):
			_drop(key)
	if not _glow_asked:
		IafCityLights.request_glow()  # after the first blocks
		_glow_asked = true


## The towns' glow once made: the terrain shader's city_glow (scene frame), lit while the lights show.
func _take_glow() -> void:
	var g: Dictionary = IafCityLights.glow()
	if g.is_empty():
		return
	var img := Image.create_from_data(int(g.w), int(g.h), false, Image.FORMAT_R8, g.bytes)
	img.generate_mipmaps()  # far ground reads it minified
	_glow = ImageTexture.create_from_image(img)
	glow_texture = _glow
	var wo: Vector2 = _tv.terrain.world_origin
	var span := Vector2(float(g.w), float(g.h)) * float(g.m)
	RenderingServer.global_shader_parameter_set("city_glow", _glow)
	glow_rect = Vector4(float(g.x0) - wo.x, -(float(g.y1) - wo.y), 1.0 / span.x, 1.0 / span.y)
	RenderingServer.global_shader_parameter_set("city_glow_rect", glow_rect)
	_glow_on()


func _glow_on() -> void:
	glow_k = GLOW_K if _glow != null and is_visible_in_tree() else 0.0
	glow_strength = glow_k
	RenderingServer.global_shader_parameter_set("city_glow_k", glow_k)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_glow_on()


## The glow is a global: off for whatever draws the terrain next (the front end, a day mission).
func _exit_tree() -> void:
	glow_k = 0.0
	glow_strength = 0.0
	RenderingServer.global_shader_parameter_set("city_glow_k", 0.0)


## A requested block's points, when made (asked again at the next poll when the terrain under it was not loaded);
## true when it got them.
func _take(key: Vector2i, b: Dictionary) -> bool:
	var r: Dictionary = IafCityLights.take(key.x, key.y)
	if r.is_empty():
		return false
	b.asking = false
	if r.has("retry"):
		return false
	# A block made again (a nearer mesh added, the road lamps switched) replaces its meshes.
	for k in r.meshes.size():
		if b.meshes[k] != null:
			b.meshes[k].queue_free()
		b.meshes[k] = _mesh(r.origin, r.meshes[k])
	return true


func _mesh(o: Vector3, pts: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var v: PackedVector3Array = pts[0]
	if not v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_COLOR] = pts[1]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wo: Vector2 = _tv.terrain.world_origin
	mi.position = Vector3(o.x - wo.x, 0.0, -(o.y - wo.y))
	add_child(mi)
	return mi


func _drop(key: Vector2i) -> void:
	var b: Dictionary = _blocks[key]
	if b.asking:
		IafCityLights.take(key.x, key.y)  # a result made after the drop is taken (or replaced) later
	for m in b.meshes:
		if m != null:
			m.queue_free()
	_blocks.erase(key)
