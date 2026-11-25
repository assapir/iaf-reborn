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
## and the terrain between the spots would cut them). Far points dim with half the fog; behind a Volumetric cloud a
## point shows by the light the cloud lets through (clouds_behind.gdshaderinc). A vertex colour's alpha below 1 marks a
## one-way fixture (airbase_lights.gd): it shines one way only, and a PAPI unit turns white or red by the
## viewer's angle above it.
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float size_m = 4.0;
uniform float min_px = 4.5;
uniform float max_px = 28.0;
uniform float gain = 1.0;
uniform float fog_k = 0.00003;
uniform float vp_h = 1080.0;
uniform float lift = 1.5;
uniform float pull = -1.0;
// A jet's lamp (lamp_cd > 0, its intensity in candela): a point whose brightness follows the illuminance cd / d² as a
// star's magnitude does (14.2 magnitudes above 1 lux): full at Sirius's (-1.46) and brighter, below it the square
// root of its share (as the night sky's stars are drawn compressed; inferred), its size growing slowly with it
// (LAMP_PX at Sirius's: a star's point; the night sky's brightest star is 3.8 px with a fainter falloff).
uniform float lamp_cd = 0.0;
const float LAMP_PX = 2.2;
#include "res://shared/terrain/clouds_behind.gdshaderinc"
varying float fade;
varying vec3 col;
varying float v_dist;
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0) + VIEW_MATRIX * vec4(0.0, lift, 0.0, 0.0);
	float d = max(-v.z, 1.0);
	v_dist = length(v.xyz);
	float rows = vp_h / 1080.0;
	float px = size_m * abs(PROJECTION_MATRIX[1][1]) * 0.5 * vp_h / d;
	// A lamp outshines the haze: half the scene's fog, and a far point keeps 60 % of its light.
	fade = clamp(px / (min_px * rows), 0.6, 1.0) * exp(-0.5 * fog_k * d) * gain;
	if (lamp_cd > 0.0) {
		float mag = -14.2 - 2.5 * log(lamp_cd / (d * d)) / log(10.0);
		float b = pow(10.0, -0.4 * (mag + 1.46));
		fade = min(sqrt(b), 1.0) * exp(-0.5 * fog_k * d) * gain;
		px = LAMP_PX * pow(b, 0.2) * rows;
	}
	col = COLOR.rgb;
	if (COLOR.a < 0.995) {
		// A one-way fixture (airbase_lights.gd): COLOR.a = the way it shines (angle from Godot +X toward +Z / 360°).
		float h = COLOR.a * TAU;
		vec3 f = normalize((MODELVIEW_MATRIX * vec4(cos(h), 0.0, sin(h), 0.0)).xyz);
		vec3 to_cam = normalize(-v.xyz);
		fade *= smoothstep(-0.05, 0.25, dot(to_cam, f));
		if (COLOR.r + COLOR.g < 0.01) {
			// A PAPI unit: white seen from above its angle (COLOR.b · 10°), red below.
			vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			float el = degrees(asin(clamp(dot(to_cam, up), -1.0, 1.0)));
			col = el > COLOR.b * 10.0 ? vec3(1.0, 0.95, 0.85) : vec3(1.0, 0.1, 0.06);
		}
	}
	POINT_SIZE = clamp(px, min_px * rows, max_px * rows);
	// The sprite is flat at the light's depth: drawn size_m nearer, the ground or skin around the light hides none of it
	// (`pull` nearer when set: the F-16 panel's lights, which the jet's own skin hides from its far side).
	POSITION = PROJECTION_MATRIX * vec4(v.xyz * max(d - (pull < 0.0 ? size_m : pull), 0.5) / d, 1.0);
}
void fragment() {
	vec2 c = POINT_COORD * 2.0 - 1.0;
	float r = length(c);
	float core = smoothstep(0.6, 0.0, r);
	float halo = pow(1.0 - smoothstep(0.0, 1.0, r), 2.0) * 1.5;
	ALBEDO = (col * (core * 3.0 + halo) + vec3(core * 1.2)) * fade * clouds_through(SCREEN_UV, VIEWPORT_SIZE, v_dist);
}
"""

## The night sky (Detailed): stars and the moon at the far plane, behind everything; the cloud layer draws over them,
## the Volumetric clouds hide them by their light let through (clouds_behind.gdshaderinc).
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform float size_px = 2.4;
uniform bool moon = false;
uniform float gain = 1.0;
uniform float vp_h = 1080.0;
#include "res://shared/terrain/clouds_behind.gdshaderinc"
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
	ALBEDO = COLOR.rgb * a * fade * clouds_through(SCREEN_UV, VIEWPORT_SIZE, 1e9);
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
const MOON_LIGHT := Color(0.24, 0.27, 0.34)
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


## The jets' lights: points as bright as their lamps at the distance (the shader's `lamp_cd`): the navigation lights
## NAV_CD, the strobe STROBE_CD. The F-16 panel's lights (panel_glow) keep the glow sized in metres (`lamp_cd` 0).
## FAA minimums (14 CFR 25.1391, 25.1401): 40 cd ahead for the red and green, 5 cd beside, 20 cd aft for the white;
## 400 cd for the anti-collision light. NAV_CD is between ahead and beside (inferred).
const NAV_CD := 20.0
const STROBE_CD := 400.0
static var _strobe: ShaderMaterial


static func nav_glow() -> ShaderMaterial:
	if _nav == null:
		_nav = _shader_material(GLOW_SHADER)
		_nav.set_shader_parameter("size_m", 2.0)
		_nav.set_shader_parameter("min_px", 1.5)
		_nav.set_shader_parameter("max_px", 14.0)
		_nav.set_shader_parameter("lift", 0.0)
		_nav.set_shader_parameter("lamp_cd", NAV_CD)
	return _nav


## The strobe's point: the navigation lights' at STROBE_CD.
static func strobe_glow() -> ShaderMaterial:
	if _strobe == null:
		_strobe = nav_glow().duplicate()
		_strobe.set_shader_parameter("lamp_cd", STROBE_CD)
	return _strobe


static func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## The glows' brightness: 1 at night; by day 0.35 for the ground lights (a lit runway light is a small spot in
## daylight) and 0.12 for the jets' lights.
## The viewport's rows: a shader's VIEWPORT_SIZE reads 0 in vertex() on Metal, so the glows get it as `vp_h`.
## (The projection is Y-flipped there: the shaders take the focal length as abs(PROJECTION_MATRIX[1][1]).)
static func set_gain(night: bool, fog_density: float, rows: float) -> void:
	for m in [glow(), nav_glow(), strobe_glow()]:
		# By day a jet's position lights are small dim dots next to a runway light (its glow is 2 m, not 4 m).
		m.set_shader_parameter("gain", 1.0 if night else (0.35 if m == glow() else 0.12))
		m.set_shader_parameter("fog_k", fog_density)
		m.set_shader_parameter("vp_h", rows)
	for level in _navs:
		_dimmed(level)


## The F-16 panel's lights (aircraft_model.gd panel_lights) at `level` of their brightness (DIM, the FORM knob; in
## steps of a twentieth), drawn PANEL_PULL nearer than they are: the jet's skin hides those on its far side (the
## inlets', the landing light's seen from above).
const PANEL_PULL := 0.3
static var _navs := {}


static func panel_glow(level: float) -> ShaderMaterial:
	var k := snappedf(clampf(level, 0.05, 1.0), 0.05)
	if not _navs.has(k):
		_navs[k] = nav_glow().duplicate()
		_navs[k].set_shader_parameter("pull", PANEL_PULL)
		_navs[k].set_shader_parameter("lamp_cd", 0.0)
		_navs[k].set_shader_parameter("min_px", 3.0)
		_navs[k].set_shader_parameter("max_px", 20.0)
		_dimmed(k)
	return _navs[k]


static func _dimmed(level: float) -> void:
	for p in ["fog_k", "vp_h"]:
		if nav_glow().get_shader_parameter(p) != null:
			_navs[level].set_shader_parameter(p, nav_glow().get_shader_parameter(p))
	var g = nav_glow().get_shader_parameter("gain")
	_navs[level].set_shader_parameter("gain", (1.0 if g == null else float(g)) * level)


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
			col.a = 1.0  # every way (an alpha below 1 marks a one-way fixture in the glow)
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
		cols.append(Color(0.85 + 0.15 * t, 0.88, 1.0 - 0.15 * t, pow(rng.randf(), 2.5)))
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
## near the centre line, highest; the EndWing helpers when the model has them at its tips), cached per model file.
## Returns the strobe node (blink with strobe_on).
static var _spots := {}


static func add_nav_lights(model: Node3D) -> Node3D:
	# Cached per file drawn: the Detailed model or the Sufa replaces the original's under the same descriptor.
	var f := str(model.desc.get("model", model.name))
	var hd: String = preload("res://shared/util/gltf.gd").detailed(f)
	return add_lights_on(model.root_frame, hd if hd != "" else f, model.desc.get("end_wing"))


## The same lights on `frame` (a model's root; cached as `key`), at its own outermost vertices or the EndWing helpers
## `ew` ({left, right} or null).
static func add_lights_on(frame: Node3D, key: String, ew) -> Node3D:
	if not _spots.has(key):
		_spots[key] = _light_spots(frame)
	var s: Array = _spots[key].duplicate()
	if s.is_empty():
		return null
	# The EndWing helpers when they sit at the tips, within the mesh (the F-16's are a third of the way out, the
	# F-15's 0.1 m past its wingtips: the mesh's tips then).
	if (
		ew is Dictionary
		and ew.get("left") is Array
		and ew.get("right") is Array
		and float(ew.right[0]) - float(ew.left[0]) > 0.8 * (s[1].x - s[0].x)
		and float(ew.right[0]) - float(ew.left[0]) <= s[1].x - s[0].x
	):
		s[0] = Vector3(ew.left[0], ew.left[1], ew.left[2])
		s[1] = Vector3(ew.right[0], ew.right[1], ew.right[2])
	# Out of the skin: each light sits just outside the surface it marks (0.5 % of the span, 5–7 cm).
	var out: float = (s[1].x - s[0].x) * 0.005
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
		m.material_override = nav_glow() if m == nav else strobe_glow()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(m)
	return strobe


## The F-16's exterior lights besides the navigation lights and the strobe, which its exterior lights panel works
## (cockpit3d.gd ext_lights; aircraft_model.gd panel_lights): group -> [[FlightGear's spot (its frame: x aft, y right,
## z up), colour (alpha below 1: one way, as the glow shader's), outward (FlightGear's frame)]]. The inlets' position
## lights, the fuselage lights and the landing / taxi light at FlightGear's F-16.xml spots; the formation strips (the
## forward fuselage's sides, the aft fuselage's, the fin's: the F-16's electroluminescent strips, their pale green;
## inferred from photographs) and the air refuelling receptacle's light (on the spine behind the canopy; inferred),
## which FlightGear does not place, at our spots. Each moves onto the model's skin (_on_skin). Our detailed F-16s are
## on FlightGear's frame (tools/f16/base.py), placed by the fin top (FlightGear's strobe, FG_FIN).
const FG_FIN := Vector3(5.3, 0.0, 3.2)
const FORM_GREEN := Color(0.55, 1.0, 0.4)
const PANEL_LIGHTS := {
	"inlet":
	[
		[Vector3(-3.36687, -0.748387, -0.555937), NAV_RED, Vector3(0, -1, 0)],
		[Vector3(-3.36687, 0.748387, -0.555937), NAV_GREEN, Vector3(0, 1, 0)]
	],
	"fuselage":
	[
		[Vector3(3.45, -0.95, 0.22), NAV_WHITE, Vector3(0, -1, 0)],
		[Vector3(3.45, 0.95, 0.22), NAV_WHITE, Vector3(0, 1, 0)]
	],
	"form":
	[
		[Vector3(-5.0, -0.5, 0.2), FORM_GREEN, Vector3(0, -1, 0)],
		[Vector3(-5.0, 0.5, 0.2), FORM_GREEN, Vector3(0, 1, 0)],
		[Vector3(4.0, -0.85, 0.3), FORM_GREEN, Vector3(0, -1, 0)],
		[Vector3(4.0, 0.85, 0.3), FORM_GREEN, Vector3(0, 1, 0)],
		[Vector3(5.6, -0.05, 2.6), FORM_GREEN, Vector3(0, -1, 0)],
		[Vector3(5.6, 0.05, 2.6), FORM_GREEN, Vector3(0, 1, 0)]
	],
	"ar": [[Vector3(-1.2, 0.0, 1.0), NAV_WHITE, Vector3(0, 0, 1)]],
	"land": [[Vector3(-3.13064, 0.307693, -1.23477), Color(1.0, 0.97, 0.9, 0.75), Vector3(0, 0, -1)]],
}


## The panel's lights on `frame` (an F-16's root, its spots cached as `key`): group -> its MeshInstance3D (hidden),
## and "tips" (the wingtips' red and green as formation lights) and "land_at" (the landing light's spot, `frame`'s).
static func add_panel_lights(frame: Node3D, key: String) -> Dictionary:
	if not _spots.has(key):
		_spots[key] = _light_spots(frame)
	if _spots[key].is_empty():
		return {}
	var s: Array = _spots[key]
	if not _panel_spots.has(key):
		_panel_spots[key] = _on_skin(_skin(frame), s[3])
	var out := {}
	for group in PANEL_LIGHTS:
		var cols := PackedColorArray()
		for e in PANEL_LIGHTS[group]:
			cols.append(e[1])
		out[group] = _points(frame, "Panel_" + group, _panel_spots[key][group], cols)
	out.tips = _points(frame, "Panel_tips", PackedVector3Array([s[0], s[1]]), PackedColorArray([NAV_RED, NAV_GREEN]))
	out.land_at = _panel_spots[key].land[0]
	return out


static var _panel_spots := {}

## PANEL_LIGHTS' spots in our frame (the fin top at `fin`), each the outermost point of `skin` (along its outward)
## within PANEL_REACH of it across, 3 cm out: group -> spots.
const PANEL_REACH := 0.2


static func _on_skin(skin: PackedVector3Array, fin: Vector3) -> Dictionary:
	var out := {}
	for group in PANEL_LIGHTS:
		var pts := PackedVector3Array()
		for e in PANEL_LIGHTS[group]:
			var p: Vector3 = e[0]
			var at := fin + Vector3(p.y, p.z - FG_FIN.z, p.x - FG_FIN.x)
			var o := Vector3(e[2].y, e[2].z, e[2].x)
			var best := at
			var far := -INF
			for v in skin:
				var r := v - at
				if (r - o * r.dot(o)).length_squared() < PANEL_REACH * PANEL_REACH and r.dot(o) > far:
					far = r.dot(o)
					best = v
			pts.append(best + o * 0.03)
		out[group] = pts
	return out


static func _points(frame: Node3D, name: String, pts: PackedVector3Array, cols: PackedColorArray) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = name
	m.mesh = point_mesh(pts, cols)
	m.material_override = panel_glow(1.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	frame.add_child(m)
	return m


## The vertices of `frame`'s shown meshes in its space, but the gear's, the hook's and the panel's own.
static func _skin(frame: Node3D) -> PackedVector3Array:
	var verts := PackedVector3Array()
	for mi: MeshInstance3D in frame.find_children("*", "MeshInstance3D", true, false):
		var n := str(mi.name)
		if mi.mesh == null or not _shown(frame, mi) or n == "Hook" or n.begins_with("Ldg") or n.begins_with("Panel_"):
			continue
		if n.begins_with("Afterburner") or n in ["NavLights", "Strobe"]:
			continue
		var t := _rel(frame, mi)
		for i in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				verts.append(t * v)
	return verts


## [left tip, right tip, tail, fin top] in `frame`'s space ([] without meshes). +X right, +Y up, +Z aft (the glTF).
static func _light_spots(frame: Node3D) -> Array:
	var verts := PackedVector3Array()
	# The frame itself counts: a model's root is often its main mesh (the F-15's fuselage and wings). A helicopter's
	# rotors (rotora, rotorb) do not: their blade tips turn; the lights sit on the airframe.
	var meshes: Array = frame.find_children("*", "MeshInstance3D", true, false)
	if frame is MeshInstance3D:
		meshes.push_front(frame)
	# The tail light: the rearmost of the body, not the hook or a gear leg (they would hang it below the jet).
	var tail_verts := PackedVector3Array()
	var heli := false
	for mi: MeshInstance3D in meshes:
		if (
			mi.mesh == null
			or not _shown(frame, mi)
			or str(mi.name).begins_with("Afterburner")
			or str(mi.name) in ["NavLights", "Strobe"]
		):
			continue
		if str(mi.name).to_lower().begins_with("rotor"):
			heli = true
			continue
		var t := _rel(frame, mi)
		var body := not (str(mi.name) == "Hook" or str(mi.name).begins_with("Ldg"))
		for i in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				verts.append(t * v)
				if body:
					tail_verts.append(t * v)
	if verts.is_empty():
		return []
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var l := Vector3(INF, 0, 0)
	var r := Vector3(-INF, 0, 0)
	var top := verts[0]
	for v in verts:
		if v.y > top.y:
			top = v
		# A helicopter's red and green lights: the cabin's sides (its front 60 %, above the gear's lowest quarter), not
		# the gear, the stub tail planes or the stabilizer.
		if heli and (v.z > lo.z + 0.6 * (hi.z - lo.z) or v.y < lo.y + 0.25 * (hi.y - lo.y)):
			continue
		if v.x < l.x:
			l = v
		if v.x > r.x:
			r = v
	# A helicopter's pair faces across: the side that reaches farther, mirrored (a cabin's sides are not one vertex).
	if heli and l.x < INF:
		var w := l if -l.x > r.x else r
		l = Vector3(-absf(w.x), w.y, w.z)
		r = Vector3(absf(w.x), w.y, w.z)
	var half := (r.x - l.x) * 0.5
	var tail := Vector3(0, 0, -INF)
	# Twin fins (the top off the centre line, the F-15): the white light on that fin's trailing edge, in its upper
	# half; one fin: the rearmost of the body on the centre line.
	var twin := absf(top.x) >= 0.1 * half
	for v in tail_verts:
		var on_it := absf(v.x - top.x) < 0.1 * half and v.y > 0.5 * top.y if twin else absf(v.x) < 0.1 * half
		if on_it and v.z > tail.z:
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
