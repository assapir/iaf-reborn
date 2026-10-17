# Night lights (docs/rendering.md §4 "Light points" and §5).
#
# The original: a model whose file name starts with "LT_" (FUN_0041ee60 sets object flag 0x4) is a set of light points.
# FUN_0041ac40 draws it as a point list (D3D FILLMODE POINT, DrawPrimitive POINTLIST of pre-lit vertices) at every
# hour: each vertex is one pixel in its material's colour, depth test on, depth write off, fogged. The sets are the
# airbase lights (lt_rmn_h, lt_tnf_h, lt_dvd_h), Damascus's streets (lt_dsk*), a chimney (lt_chmny) and a ship's
# navigation lights (lt_ossa).
#
# Extras > Night lights = Detailed (ours, docs/deviations.md): the points glow (size by distance, a soft halo), the
# home airbases get their light set at night, the jets carry navigation lights and a strobe, the night sky has stars
# and a moon, and the moon lights the ground.
extends RefCounted

## The original's point: one pixel of a 640×480 screen, scaled to the viewport's height.
const ORIGINAL_ROWS := 480.0

## The glow of a light point (Detailed). size_m: the glow's diameter in metres; the point keeps at least min_px and at
## most max_px pixels (at 1080 rows); gain: 1 at night; lift: metres above its spot (ground lights stand on the ground
## and the terrain between the spots would cut them). Far points dim with the fog.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float size_m = 4.0;
uniform float min_px = 2.5;
uniform float max_px = 28.0;
uniform float gain = 1.0;
uniform float fog_k = 0.00003;
uniform float vp_h = 1080.0;
uniform float lift = 1.5;
varying float fade;
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0) + VIEW_MATRIX * vec4(0.0, lift, 0.0, 0.0);
	float d = max(-v.z, 1.0);
	float rows = vp_h / 1080.0;
	float px = size_m * abs(PROJECTION_MATRIX[1][1]) * 0.5 * vp_h / d;
	fade = clamp(px / (min_px * rows), 0.25, 1.0) * exp(-fog_k * d) * gain;
	POINT_SIZE = clamp(px, min_px * rows, max_px * rows);
	// The sprite is flat at the light's depth: drawn size_m nearer, the ground or skin around the light hides none of it.
	POSITION = PROJECTION_MATRIX * vec4(v.xyz * max(d - size_m, 0.5) / d, 1.0);
}
void fragment() {
	vec2 c = POINT_COORD * 2.0 - 1.0;
	float r = length(c);
	float core = smoothstep(0.3, 0.0, r);
	float halo = pow(1.0 - smoothstep(0.0, 1.0, r), 2.0) * 0.7;
	ALBEDO = (COLOR.rgb * (core * 1.5 + halo) + vec3(core * 0.7)) * fade;
}
"""

## The night sky (Detailed): stars and the moon at the far plane, behind everything; the cloud layer draws over them.
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform float size_px = 2.0;
uniform bool moon = false;
uniform float gain = 1.0;
uniform float vp_h = 1080.0;
varying float fade;
void vertex() {
	vec3 dir = normalize((VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	POSITION = PROJECTION_MATRIX * vec4(dir * 10.0, 1.0);
	POSITION.z = POSITION.w * 1e-6;
	float rows = vp_h / 1080.0;
	POINT_SIZE = (moon ? size_px * abs(PROJECTION_MATRIX[1][1]) : size_px * (0.6 + COLOR.a)) * rows;
	fade = smoothstep(-0.01, 0.12, normalize(VERTEX).y) * gain;
}
void fragment() {
	vec2 c = POINT_COORD * 2.0 - 1.0;
	float r = length(c);
	float a = moon ? smoothstep(0.42, 0.36, r) + exp(-r * r * 6.0) * 0.12 : exp(-r * r * 5.0) * COLOR.a;
	ALBEDO = COLOR.rgb * a * fade;
}
"""

## Detailed: the light sets the home airbases get at night (the night base mission bmisrdvdn places lt_dvd_h on
## ul_rwdavid's spot, heading and scale; the other two sets fit their runway models the same way): runway model →
## [light set, the base's spot (world m)]. The runway models also stand in for foreign bases, so only these spots.
const BASE_LIGHTS := {
	"ul_rwramon.gltf": ["stationary/rw_ul_1/lt_rmn_h.gltf", Vector2(316188, 409580)],
	"ul_rwtelnof.gltf": ["stationary/rw_ul_1/lt_tnf_h.gltf", Vector2(314977, 499700)],
	"ul_rwdavid.gltf": ["stationary/rw_ul_1/lt_dvd_h.gltf", Vector2(355109, 602020)],
}

## Detailed: the moon (azimuth, elevation in degrees) and its light.
const MOON_AZ := 140.0
const MOON_EL := 38.0
const MOON_LIGHT := Color(0.20, 0.23, 0.33)
const MOON_AMBIENT := 0.3
const STARS := 2600

## Detailed: the jets' lights (aviation colours) and the strobe's flash.
const NAV_RED := Color(1.0, 0.12, 0.08)
const NAV_GREEN := Color(0.15, 1.0, 0.35)
const NAV_WHITE := Color(1.0, 0.95, 0.85)
const STROBE_PERIOD := 1.2
const STROBE_ON := 0.08

static var _glow: ShaderMaterial
static var _nav: ShaderMaterial


static func detailed() -> bool:
	var settings: Node = Engine.get_main_loop().root.get_node("Settings")
	return settings.night_lights == "detailed"


## True for an LT_ light set (by its file name, as FUN_0041ee60 tests the clump name).
static func is_light_set(path: String) -> bool:
	return path.get_file().to_lower().begins_with("lt_")


## The shared glow of the ground light points; `gain` follows the time of day (set_gain).
static func glow() -> ShaderMaterial:
	if _glow == null:
		_glow = _shader_material(GLOW_SHADER)
	return _glow


## The jets' lights: smaller glows that stay visible farther.
static func nav_glow() -> ShaderMaterial:
	if _nav == null:
		_nav = _shader_material(GLOW_SHADER)
		_nav.set_shader_parameter("size_m", 2.0)
		_nav.set_shader_parameter("min_px", 3.0)
		_nav.set_shader_parameter("max_px", 20.0)
		_nav.set_shader_parameter("lift", 0.0)
	return _nav


static func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## The glows' brightness: 1 at night, `day` by day (a lit runway light is a small spot in daylight).
## The viewport's rows: a shader's VIEWPORT_SIZE reads 0 in vertex() on Metal, so the glows get it as `vp_h`.
## (The projection is Y-flipped there: the shaders take the focal length as abs(PROJECTION_MATRIX[1][1]).)
static func set_gain(night: bool, fog_density: float, rows: float) -> void:
	for m in [glow(), nav_glow()]:
		m.set_shader_parameter("gain", 1.0 if night else 0.35)
		m.set_shader_parameter("fog_k", fog_density)
		m.set_shader_parameter("vp_h", rows)


## The original's material for a light set: unshaded points of `px` pixels, vertex colours, no depth write, fogged.
static func original_material(px: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.use_point_size = true
	m.point_size = px
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Turns every mesh under `node` into a point list of its vertices, each in its surface material's base colour
## (FUN_0041ac40), drawn with `material`.
static func to_points(node: Node3D, material: Material) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var col := mat.albedo_color if mat != null else Color.WHITE
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			verts.append_array(v)
			for i in v.size():
				cols.append(col)
		mi.mesh = point_mesh(verts, cols)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func point_mesh(verts: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh


## A light set ready to draw: the original's points, or (Detailed) glows.
static func dress(node: Node3D, viewport_rows: float) -> void:
	to_points(node, glow() if detailed() else original_material(maxf(1.0, roundf(viewport_rows / ORIGINAL_ROWS))))


## Detailed: the star field and the moon (child of the flight scene). Stars: a fixed random sky, brighter ones rarer.
static func sky() -> Node3D:
	var root := Node3D.new()
	root.name = "NightSky"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1998
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in STARS:
		var z := rng.randf_range(-0.1, 1.0)
		var a := rng.randf() * TAU
		var r := sqrt(1.0 - z * z)
		verts.append(Vector3(r * cos(a), z, r * sin(a)))
		var t := rng.randf()
		cols.append(Color(0.85 + 0.15 * t, 0.88, 1.0 - 0.15 * t, pow(rng.randf(), 4.0)))
	var stars := MeshInstance3D.new()
	stars.name = "Stars"
	stars.mesh = point_mesh(verts, cols)
	var sm := _shader_material(SKY_SHADER)
	sm.render_priority = -10
	stars.material_override = sm
	var moon := MeshInstance3D.new()
	moon.name = "Moon"
	moon.mesh = point_mesh(PackedVector3Array([moon_dir()]), PackedColorArray([Color(1.0, 0.97, 0.9, 1.0)]))
	var mm := _shader_material(SKY_SHADER)
	mm.set_shader_parameter("moon", true)
	mm.set_shader_parameter("size_px", 0.0175 * 1080.0 * 0.5 * 2.6)  # ≈ 1° wide with its glow
	mm.render_priority = -9
	moon.material_override = mm
	for m in [stars, moon]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.custom_aabb = AABB(Vector3.ONE * -1e7, Vector3.ONE * 2e7)  # drawn by direction: never culled
		root.add_child(m)
	return root


## The direction toward the moon (Godot frame: X east, Y up, Z south).
static func moon_dir() -> Vector3:
	var az := deg_to_rad(MOON_AZ)
	var el := deg_to_rad(MOON_EL)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


## Detailed: the jet's lights under `model` (an aircraft_model.gd): red on the left wingtip, green on the right, white
## at the tail, and a white strobe on top of the fin. Spots: the model's outermost vertices (left / right, rearmost
## near the centre line, highest; the EndWing helpers when the model has them at its tips), cached per model file. Returns the strobe node (blink with strobe_on).
static var _spots := {}


static func add_nav_lights(model: Node3D) -> Node3D:
	return add_lights_on(model.root_frame, str(model.desc.get("model", model.name)), model.desc.get("end_wing"))


## The same lights on `frame` (a model's root; cached as `key`), at its own outermost vertices or the EndWing helpers
## `ew` ({left, right} or null).
static func add_lights_on(frame: Node3D, key: String, ew) -> Node3D:
	if not _spots.has(key):
		_spots[key] = _light_spots(frame)
	var s: Array = _spots[key].duplicate()
	if s.is_empty():
		return null
	# The EndWing helpers when they sit at the tips (the F-16's are a third of the way out: the mesh's tips then).
	if ew is Dictionary and ew.get("left") is Array and ew.get("right") is Array \
			and float(ew.right[0]) - float(ew.left[0]) > 0.8 * (s[1].x - s[0].x):
		s[0] = Vector3(ew.left[0], ew.left[1], ew.left[2])
		s[1] = Vector3(ew.right[0], ew.right[1], ew.right[2])
	# Out of the skin: each light sits a little outside the surface it marks (2 % of the span).
	var out: float = (s[1].x - s[0].x) * 0.02
	s[0] += Vector3(-out, 0, 0)
	s[1] += Vector3(out, 0, 0)
	s[2] += Vector3(0, 0, out)
	s[3] += Vector3(0, out, 0)
	var nav := MeshInstance3D.new()
	nav.name = "NavLights"
	nav.mesh = point_mesh(PackedVector3Array([s[0], s[1], s[2]]), PackedColorArray([NAV_RED, NAV_GREEN, NAV_WHITE]))
	var strobe := MeshInstance3D.new()
	strobe.name = "Strobe"
	strobe.mesh = point_mesh(PackedVector3Array([s[3]]), PackedColorArray([Color.WHITE]))
	strobe.visible = false
	for m in [nav, strobe]:
		m.material_override = nav_glow()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(m)
	return strobe


## [left tip, right tip, tail, fin top] in `frame`'s space ([] without meshes). +X right, +Y up, +Z aft (the glTF).
static func _light_spots(frame: Node3D) -> Array:
	var verts := PackedVector3Array()
	for mi: MeshInstance3D in frame.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not _shown(frame, mi) or str(mi.name).begins_with("Afterburner") or str(mi.name) in ["NavLights", "Strobe"]:
			continue
		var t := _rel(frame, mi)
		for i in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				verts.append(t * v)
	if verts.is_empty():
		return []
	var l := verts[0]
	var r := verts[0]
	var top := verts[0]
	for v in verts:
		if v.x < l.x:
			l = v
		if v.x > r.x:
			r = v
		if v.y > top.y:
			top = v
	var half := (r.x - l.x) * 0.5
	var tail := Vector3(0, 0, -INF)
	for v in verts:
		if absf(v.x) < 0.1 * half and v.z > tail.z:
			tail = v
	return [l, r, tail if tail.z > -INF else top, top]


## True when `node` and its parents up to `frame` are visible (the loader hides helper frames).
static func _shown(frame: Node3D, node: Node3D) -> bool:
	var n: Node = node
	while n != null and n != frame:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## The transform of `node` relative to its ancestor `frame`.
static func _rel(frame: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != frame:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The strobe's flash at time `t` (s), each jet offset by `phase`.
static func strobe_on(t: float, phase: float) -> bool:
	return fposmod(t + phase, STROBE_PERIOD) < STROBE_ON
