// Terrain node (terrain.gd): a grid displaced by the original IAF elevation, coloured by the
// node's texture or the matching part of an ancestor's.
shader_type spatial;
render_mode cull_back;

// Raw u16 heights packed as R = high byte, G = low byte (RG8), 1025² per theatre node.
uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D colour_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sea_level_raw = 20342.0;
uniform float height_scale = 9.2575;
// Terrain units are 1.2411389 m (the original engine's PlaneScalePR), heights included.
uniform float units_to_metres = 1.0;
// Height texel of the node's (0, 0) corner, texels across the node, metres per texel.
uniform vec2 h_origin = vec2(0.0);
uniform float h_span = 1024.0;
uniform float h_texel_m = 79.4;
// Node UV -> colour texture UV.
uniform vec2 uv_origin = vec2(0.0);
uniform float uv_scale = 1.0;
// Node side (m), skirt depth (m), and the part of the node inside the theatre (node UV).
uniform float node_m = 1271.0;
uniform float skirt = 20.0;
uniform vec2 valid_uv = vec2(1.0);
// The generated sea colour in the imagery (open water only, not the Dead Sea / lakes).
uniform vec3 sea_colour = vec3(0.035, 0.059, 0.302);

float raw_at(ivec2 p) {
	p = clamp(p, ivec2(0), textureSize(height_tex, 0) - 1);
	vec2 rg = texelFetch(height_tex, p, 0).rg;
	return rg.r * 65280.0 + rg.g * 255.0;
}

// Height (m) at a height-texture position in texels: linear over the triangles of each texel
// square split along the north-west -> south-east diagonal (FUN_004281e0; terrain.gd _triangle).
float height_at(vec2 t) {
	vec2 f = floor(t);
	vec2 w = t - f;
	ivec2 p = ivec2(f);
	float a = raw_at(p);
	float d = raw_at(p + ivec2(1, 1));
	float raw = w.x >= w.y ? a + (raw_at(p + ivec2(1, 0)) - a) * w.x + (d - raw_at(p + ivec2(1, 0))) * w.y
			: a + (d - raw_at(p + ivec2(0, 1))) * w.x + (raw_at(p + ivec2(0, 1)) - a) * w.y;
	return (raw - sea_level_raw) / height_scale * units_to_metres;
}

bool is_open_sea(vec2 uv) {
	vec3 c = textureLod(colour_tex, uv, 3.0).rgb;
	return distance(c, sea_colour) < 0.06;
}

void vertex() {
	// Levels 7+ overhang the theatre: their outer vertices fold onto its edge.
	vec2 uv = min(UV, valid_uv);
	VERTEX.xz = (uv - 0.5) * node_m;
	vec2 t = h_origin + uv * h_span;
	vec2 cuv = uv_origin + uv * uv_scale;
	// The data surface everywhere, sea included (the original draws it and places ships on it:
	// bathymetry off Israel, the flat -557 m plane over Egypt west of Suez); open sea is only
	// shaded flat so the sea-bed relief does not show through the water colour.
	VERTEX.y = height_at(t);
	if (is_open_sea(cuv)) {
		NORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		float dx = height_at(t + vec2(1.0, 0.0)) - height_at(t - vec2(1.0, 0.0));
		float dz = height_at(t + vec2(0.0, 1.0)) - height_at(t - vec2(0.0, 1.0));
		NORMAL = normalize(vec3(-dx, 2.0 * h_texel_m, -dz));
	}
	VERTEX.y -= UV2.x * skirt;
	UV = cuv;
}

void fragment() {
	ALBEDO = texture(colour_tex, UV).rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
