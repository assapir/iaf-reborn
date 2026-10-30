# The textured sky (Preferences > Graphics TEXTURED SKY, docs/front-end.md §12.4): the original's cloud layer
# at 7000 m (FUN_0041d3d0) and the whiteout near it (FUN_0041da60). Off: neither (our gradient sky stays).
# The layer is 15 rings × 64 segments around the camera: from below a dome on a circular arc from the zenith
# at H down to height 0 at R0 = 0.73·far, from above the same radii flat at H. Texture Cloud256_<rand()%6>
# (picked per mission), its alpha used; ring colours step from the cloud colour (white) toward the fog colour by
# 1/16; UVs u = (0.25·j·r·cos φ + S − C) / (1.2·far) with S scrolling at −15·dt·wind (90°, 6). Scene coordinates
# (Y up = altitude).
extends Node3D

const H := 7000.0
## The far plane the original draws it against (0x6284cc, 30000 static).
const FAR := 30000.0
const RINGS := 15
const SEGMENTS := 64
## The layer's scroll: −15 · dt · (sin, cos)(direction) · speed per second, direction 90°, speed 6 (775a74 / 78).
const WIND_DIR := deg_to_rad(90.0)
const WIND_SPEED := 6.0
## Whiteout within 1000 m of the layer: alpha = clamp(j + 255 − ftol(0.255·|Δ|), 0, 255), j a random walk
## (rand % 9 − 4 per frame), reset outside the band.
const WHITEOUT_BAND := 1000.0
## The night colour with the atmospheric sky (Extras): lighter than its night sky, neutral.
const NIGHT_ATMO := Color(0.045, 0.055, 0.095)
## Night lights Detailed at night (city_lights.gd's glow): the towns' light on the layer's base (light pollution;
## tuned so a big town's sky glows a dim orange) and, seen from above, the alpha range that opens it into broken
## cloud, so the lit towns show through the gaps.
const GLOW_GAIN := 10.0
const NIGHT_GAPS := Vector2(0.6, 1.0)

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mix;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 offset;  // S − C
uniform float scale;  // 1 / (1.2 · far)
uniform bool at_far;  // the dome (from below)
// The texture's alpha mapped from this range to 0..1: (0, 1) = the original's; the atmospheric sky's (0.3, 0.9)
// separates the clouds with clear sky between them instead of a grey veil over the whole sky.
uniform vec2 alpha_range = vec2(0.0, 1.0);
uniform vec3 tint = vec3(1.0);  // the cloud-layer colour (renderer +0x54): 0xFF14143C at night
// The texture's finest mip level read: 2 = the original's 256 texels (bilinear, as its D3D renderer drew it), not
// the 4× upscale's sharp steps between the ARGB4444 source's 16 alpha levels; 3 with the atmospheric sky, whose
// stretched alpha shows those steps as contours. `detail` adds the texture at 4.37× its scale for the edges.
uniform float min_lod = 2.0;
uniform float detail = 0.0;
// Under the rain's overcast (weather.gd grey()) the layer fades out: 1 = as drawn.
uniform float fade = 1.0;
// Night lights Detailed at night: the towns' light from below (light pollution, city_glow.gdshaderinc's map read 2 km
// wide), orange on the cloud's base; 0 = none (the original).
global uniform float city_glow_k;
global uniform sampler2D city_glow : filter_linear_mipmap, repeat_disable;
global uniform vec4 city_glow_rect;
uniform float glow_gain = 0.0;
// Lit by the sun (the atmospheric sky by day): sun_dir points to the sun (scene axes).
uniform bool lit = false;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
// The sunlight's reddening by its air mass (atmosphere.gdshader's sun_depth), thinner at the layer's height.
const vec3 SUN_DEPTH = vec3(0.08, 0.22, 0.4) * 0.8;
void vertex() {
	// The dome at the far plane (reverse Z: depth 0): behind every terrain point, as the original cuts it at
	// the terrain's far horizon (FUN_0041dc30 → +0x1098, v1.1) and fills the gap up to it at the dome's depth.
	// The flat layer seen from above stays in front of the ground.
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (at_far) {
		POSITION.z = 0.0;
	}
}
float air_mass(float cos_zenith) {
	float c = max(cos_zenith, 0.0);
	float z = degrees(acos(c));
	return 1.0 / (c + 0.50572 * pow(max(96.07995 - z, 0.001), -1.6364));
}
void fragment() {
	vec2 uv = (UV2.x * UV + offset) * scale;
	vec2 g = max(abs(dFdx(uv)), abs(dFdy(uv))) * float(textureSize(tex, 0).x);
	// Four bilinear taps half a texel apart (a quadratic B-spline): bilinear alone leaves creases at the texel edges
	// that the stretched alpha shows as contours.
	float lod = max(log2(max(g.x, g.y)), min_lod);
	float h = 0.5 * exp2(lod) / float(textureSize(tex, 0).x);
	vec4 t = 0.25 * (textureLod(tex, uv + vec2(h, h), lod) + textureLod(tex, uv + vec2(-h, h), lod)
			+ textureLod(tex, uv + vec2(h, -h), lod) + textureLod(tex, uv + vec2(-h, -h), lod));
	t.a += detail * (texture(tex, uv * 4.37 + vec2(0.31, 0.77)).a - 0.5);
	float d = clamp((t.a - alpha_range.x) / (alpha_range.y - alpha_range.x), 0.0, 1.0);
	// With the smoothing, an S-curve keeps the gaps between the clouds clear (no creases: smooth).
	if (detail > 0.0) {
		d = smoothstep(0.0, 1.0, d);
	}
	// A dither of ± half an 8-bit step against banding in the smooth gradients.
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) - 0.5;
	ALPHA = clamp(d + dither / 255.0, 0.0, 1.0) * fade;
	if (!lit) {
		ALBEDO = COLOR.rgb * t.rgb * tint;
	} else {
		// d is the cloud's thickness. The light: the sky's (blue-grey, dimmer with a low sun) on the cloud's base,
		// thick parts darker; the sun's, reddened by its air mass, through the thin parts (forward scattering
		// toward the sun) and, with a low sun, on the bases from the side (warm toward the sun, dim away).
		vec3 s = normalize(sun_dir);
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
		float mu = dot(v, s);
		vec3 sun_t = exp(-SUN_DEPTH * min(air_mass(s.y) - 1.0, 12.0));
		vec3 sun = sun_t / pow(sun_t.r, 0.7) * smoothstep(-0.1, 0.05, s.y);
		float low = 1.0 - smoothstep(0.05, 0.4, s.y);
		float fwd = pow(max(mu, 0.0), 6.0);
		vec3 sky = vec3(0.45, 0.52, 0.7) * mix(1.0, 0.6, low);
		vec3 c = sky * (1.0 - 0.4 * d);
		c += sun * (1.0 - low) * (0.85 - 0.3 * d + 1.2 * fwd * (1.0 - d));
		float side = 0.5 + 0.5 * mu;
		c += sun * low * (0.1 + 0.9 * side * side + 2.0 * fwd) * (1.0 - 0.85 * d);
		ALBEDO = c * t.rgb;
		// Toward the horizon (the lower rings) the clouds thin, so the sky's horizon and a low sun show between them.
		ALPHA *= 1.0 - 0.6 * smoothstep(0.4, 1.0, (UV2.x * 4.0 - 1.0) / 16.0);
	}
	if (glow_gain > 0.0 && city_glow_k > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 g_uv = (wp.xz - city_glow_rect.xy) * city_glow_rect.zw;
		if (all(greaterThanEqual(g_uv, vec2(0.0))) && all(lessThanEqual(g_uv, vec2(1.0)))) {
			float g = textureLod(city_glow, g_uv, 4.0).r;
			ALBEDO += vec3(1.0, 0.45, 0.14) * g * g * city_glow_k * glow_gain;
		}
	}
}
"""

const Img := preload("res://util/img.gd")
const CityLights := preload("res://terrain/city_lights.gd")

var fog_color := Color(0.72, 0.78, 0.86)
var texture_index := 0
## The next layer's texture, chosen and decoded ahead by prefetch() (-1: chosen in _ready).
static var _next := -1
var _dome: MeshInstance3D
var _flat: MeshInstance3D
var _mat: ShaderMaterial
var _scroll := Vector2.ZERO
var _white: ColorRect
var _walk := 0
var whiteout_alpha := 0.0
var _atmo := false
var _night := false
var _tint := Color.WHITE
var _sun: Node3D
var _glow := false
var _gaps := false
var _fade := 1.0


## Picks the next layer's texture and decodes it on a worker thread (the mission screens, terrain_preload.gd).
static func prefetch() -> void:
	if _next < 0:
		_next = randi() % 6
	Img.prefetch(path(_next), true)


static func path(i: int) -> String:
	return Settings.assets_dir().path_join("converted/objects/cloud256_%d.png" % i)


func _ready() -> void:
	texture_index = _next if _next >= 0 else randi() % 6
	_next = -1
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	# The layer is the farthest transparent thing (sky): drawn before the other transparent objects, whose
	# depth-sorted order would otherwise put the camera-centred dome last, over the explosions and smoke.
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	var tex := Img.load_texture(path(texture_index), true)
	if tex != null:
		_mat.set_shader_parameter("tex", tex)
	_mat.set_shader_parameter("scale", 1.0 / (1.2 * FAR))
	var edges := ring_edges()
	_dome = _ring_mesh(edges, false)
	_flat = _ring_mesh(edges, true)
	add_child(_dome)
	add_child(_flat)
	var cl := CanvasLayer.new()
	cl.layer = -1  # over the 3D view, under the cockpit and the menus
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_white)
	add_child(cl)


## The ring edges (r, height) from the zenith to R0, 16 of them: points on the arc through (0, H) and (R0, 0)
## whose centre lies `far` below the chord's midpoint (radius √(far² + (c/2)²), c = the chord), in 15 equal
## angle steps.
static func ring_edges() -> Array:
	var r0 := 0.73 * FAR
	var c := sqrt(H * H + r0 * r0)
	var a := atan2(H, r0)
	var centre := Vector2(0.5 * r0 - sin(a) * FAR, 0.5 * H - cos(a) * FAR)
	var rho := sqrt(FAR * FAR + 0.25 * c * c)
	var t0 := (Vector2(0.0, H) - centre).angle()
	var t1 := (Vector2(r0, 0.0) - centre).angle()
	var out := []
	for j in RINGS + 1:
		var t := lerpf(t0, t1, float(j) / RINGS)
		var p := centre + Vector2(cos(t), sin(t)) * rho
		out.append(Vector2(maxf(p.x, 0.0), p.y))
	out[0] = Vector2(0.0, H)
	return out


func _ring_mesh(edges: Array, flat: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RINGS:
		var col := Color.WHITE.lerp(fog_color, float(j) / 16.0)
		var e0: Vector2 = edges[j]
		var e1: Vector2 = edges[j + 1]
		for k in SEGMENTS:
			var quad := []
			for corner in [[e0, j + 1, k], [e1, j + 2, k], [e1, j + 2, k + 1], [e0, j + 1, k + 1]]:
				var e: Vector2 = corner[0]
				var phi := TAU * float(corner[2]) / SEGMENTS
				var local := Vector2(cos(phi), sin(phi)) * e.x  # (east, north) from the camera
				quad.append([Vector3(local.x, H if flat else e.y, -local.y), local, 0.25 * corner[1]])
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_uv(quad[idx][1])
				st.set_uv2(Vector2(quad[idx][2], 0))
				st.add_vertex(quad[idx][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


## The cloud layer's colour (FUN_00407920 → renderer +0x54): (20, 20, 60) at night; by day white (its day value is
## not traced: UNCERTAIN).
func set_tint(c: Color) -> void:
	_night = c != Color.WHITE
	_tint = c
	_refresh()


## The rain's overcast hides the layer: `f` 1 = as drawn, 0 = gone (Weather.grey(), docs/rendering.md §10.1).
func set_fade(f: float) -> void:
	if f != _fade:
		_fade = f
		_mat.set_shader_parameter("fade", f)


## Extras Sky: Atmospheric (render_options.gd): the clouds separated, clear sky between them, smoothed, and by day lit
## by the sun.
func set_atmospheric(on: bool) -> void:
	_atmo = on
	_refresh()


func _refresh() -> void:
	var r := Vector2(0.3, 0.9) if _atmo else Vector2(0.0, 1.0)
	_mat.set_shader_parameter("alpha_range", NIGHT_GAPS if _gaps else r)
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN if _glow else 0.0)
	_mat.set_shader_parameter("min_lod", 2.5 if _atmo else 2.0)
	_mat.set_shader_parameter("detail", 0.2 if _atmo else 0.0)
	_mat.set_shader_parameter("lit", _atmo and not _night)
	# At night a dark blue-grey: the original's (20, 20, 60) turns violet under the tonemapper.
	var c := NIGHT_ATMO if _atmo and _night else _tint
	_mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))


## Per frame with the camera's scene position: follow it horizontally (heights are absolute), the dome from
## below / the flat layer from above, the scroll and the whiteout.
func update_view(cam: Vector3, dt: float) -> void:
	position = Vector3(cam.x, 0.0, cam.z)
	var below := cam.y < H
	var glow := _night and CityLights.glow_strength > 0.0
	if glow != _glow or (glow and not below) != _gaps:
		_glow = glow
		_gaps = glow and not below
		_refresh()
	_dome.visible = below
	_flat.visible = not below
	_mat.set_shader_parameter("at_far", below)
	_scroll += -15.0 * dt * Vector2(sin(WIND_DIR), cos(WIND_DIR)) * WIND_SPEED
	_mat.set_shader_parameter("offset", _scroll - Vector2(cam.x, -cam.z))
	if _atmo and not _night:
		if _sun == null:
			_sun = get_parent().get_node_or_null("Sun")
		if _sun != null:
			_mat.set_shader_parameter("sun_dir", _sun.global_basis.z)
	var d := absf(H - cam.y)
	if d < WHITEOUT_BAND:
		_walk += randi() % 9 - 4
		whiteout_alpha = clampf(_walk + 255 - int(0.255 * d), 0, 255) / 255.0
	else:
		_walk = 0
		whiteout_alpha = 0.0
	_white.color = Color(1, 1, 1, whiteout_alpha)
	_white.visible = whiteout_alpha > 0.0
