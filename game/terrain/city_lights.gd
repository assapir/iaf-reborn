# Night lights = Detailed (docs/rendering.md §5.1, docs/deviations.md §2): the towns' lights at night, placed from the
# scenery's building footprints (setup's scenery, docs/scenery.md; any Scenery switch) by IafCityLights
# (crates/iaf-avionics/src/city_lights.rs): street lamps along the facades, lit windows, porch lights, red
# obstruction lights on the towers, with Roads Detailed lamps along the lit roads (also beyond the buildings, outside
# Israel), and a faint haze over the dense centres (terrain/city_glow.gdshaderinc). Ours: the original's only town
# lights are its LT_ sets (Damascus).
# Blocks of 4 × 4 scenery cells (≈ 10 km): within FAR_RANGE a block draws its far points (a tenth of its lights);
# within NEAR_RANGE also its near points (the rest). The shader keeps all lights near the camera and thins them to
# the far tenth with distance; a light under its minimum size keeps its energy, so a far town reads as an even
# carpet of the same brightness instead of a white blaze. The lights thread lives in Rust (a std thread: no Godot pool
# task to wait for at quit).
extends Node3D

const Scenery := preload("res://terrain/scenery.gd")
const GroundRoads := preload("res://terrain/ground_roads.gd")

## A block's far points are drawn within this (its square's distance, m); its near points within NEAR_RANGE; both
## are dropped KEEP farther.
const FAR_RANGE := 60000.0
const NEAR_RANGE := 8000.0
const KEEP := 3000.0
## The share of a block's lights in its far points (IafCityLights FAR_SHARE).
const FAR_SHARE := 0.1
const POLL := 1.0
## Made blocks taken per frame.
const TAKES := 3

## A city light: a small bright core and a soft halo, size_m wide in the world, at least min_px wide on screen (at
## 1080 rows), smaller the dimmer it is. COLOR: colour × brightness in RGB, the light's rank in A. Within keep_near
## every light shows; by keep_far only those of rank below far_share. Drawn larger than its glow (its minimum size), a
## light keeps the glow's energy × glare, the kept far ones the dropped ones' too. A light is pulled
## toward the eye by its size and 1 % of its distance, so the coarser far terrain does not hide it. Far points dim with
## half the fog and fade out over the last 20 % of `range`.
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
uniform float range = 60000.0;
uniform float glare = 3.0;
uniform float bright = 5.0;
varying vec3 col;
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = max(-v.z, 1.0);
	float keep = mix(1.0, far_share, smoothstep(keep_near, keep_far, d));
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
	float fade = exp(-0.5 * fog_k * d) * on * e;
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

var _tv: Node
var _mat: ShaderMaterial
var _glow: ImageTexture
var _glow_asked := false
## The glow's strength now (terrain.gdshader city_glow_k).
var glow_k := 0.0
## Vector2i block -> {far: MeshInstance3D or null, near: MeshInstance3D or null, asking: bool, stale: bool (to be
## made again: the road lamps switched; its points shown until then)}
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


## The scene's fog and the 3D render's rows (night_lights.gd set_gain).
func set_view(fog_density: float, rows: float) -> void:
	_mat.set_shader_parameter("fog_k", fog_density)
	_mat.set_shader_parameter("vp_h", rows)


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
			_blocks[key] = {"far": null, "near": null, "asking": false, "stale": false}
		var b: Dictionary = _blocks[key]
		if b.asking:
			continue
		if b.stale:
			b.stale = false
			if b.far != null:
				IafCityLights.request(key.x, key.y, b.near != null)
				b.asking = true
				continue
		if (b.far == null and d <= FAR_RANGE) or (b.near == null and d <= NEAR_RANGE):
			IafCityLights.request(key.x, key.y, d <= NEAR_RANGE)
			b.asking = true
		elif b.near != null and d > NEAR_RANGE + KEEP:
			b.near.queue_free()
			b.near = null
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
	var wo: Vector2 = _tv.terrain.world_origin
	var span := Vector2(float(g.w), float(g.h)) * float(g.m)
	RenderingServer.global_shader_parameter_set("city_glow", _glow)
	RenderingServer.global_shader_parameter_set(
		"city_glow_rect", Vector4(float(g.x0) - wo.x, -(float(g.y1) - wo.y), 1.0 / span.x, 1.0 / span.y)
	)
	_glow_on()


func _glow_on() -> void:
	glow_k = GLOW_K if _glow != null and is_visible_in_tree() else 0.0
	RenderingServer.global_shader_parameter_set("city_glow_k", glow_k)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_glow_on()


## The glow is a global: off for whatever draws the terrain next (the front end, a day mission).
func _exit_tree() -> void:
	glow_k = 0.0
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
	# A block made again (the near points added, the road lamps switched) replaces its meshes.
	if b.far != null:
		b.far.queue_free()
	b.far = _mesh(r.origin, r.far)
	if r.has("near"):
		if b.near != null:
			b.near.queue_free()
		b.near = _mesh(r.origin, r.near)
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
	for m in [b.far, b.near]:
		if m != null:
			m.queue_free()
	_blocks.erase(key)
