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
// Extras "Terrain close up" (render_options.gd, docs/rendering.md): 0 = off (the original look). Detail that
// follows the imagery: on coloured ground (fields, scrub, soil) patches that deepen or dry its own colour and a
// fine grain, with normal detail; on grey ground (asphalt, concrete, rock) a faint grain only; none on water
// (the generated sea, and inland water from terraintype.dat). Airbases (terraintype.dat) count their tinted
// aprons as grey. All of it fades out by 1.5 km, so the colours from afar stay the imagery's own.
global uniform float terrain_detail;
global uniform sampler2D terrain_detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D terrain_detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// terraintype.dat around the camera (render_options.gd): R = water, G = airbase; rect = (x0, z0, 1 / side).
global uniform sampler2D terrain_surface : filter_linear, repeat_disable;
global uniform vec4 terrain_surface_rect;
varying vec2 world_xz;
varying float sea;

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
	bool open_sea = is_open_sea(cuv);
	if (open_sea) {
		NORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		float dx = height_at(t + vec2(1.0, 0.0)) - height_at(t - vec2(1.0, 0.0));
		float dz = height_at(t + vec2(0.0, 1.0)) - height_at(t - vec2(0.0, 1.0));
		NORMAL = normalize(vec3(-dx, 2.0 * h_texel_m, -dz));
	}
	VERTEX.y -= UV2.x * skirt;
	UV = cuv;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	sea = open_sea ? 1.0 : 0.0;
}

void fragment() {
	ALBEDO = texture(colour_tex, UV).rgb;
	if (terrain_detail > 0.0) {
		float k = terrain_detail * (1.0 - smoothstep(300.0, 1500.0, length(VERTEX))) * (1.0 - sea);
		if (k > 0.0) {
			vec3 c = ALBEDO;
			vec2 st = texture(terrain_surface, (world_xz - terrain_surface_rect.xy) * terrain_surface_rect.z).rg;
			float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
			float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
			// Coloured ground vs grey (in airbases the aprons' blue / purple tint is still pavement).
			float land = smoothstep(0.015, 0.05, chroma - 0.05 * st.g) * (1.0 - smoothstep(0.0, 0.03, c.b - max(c.r, c.g) - 0.1 * st.g));
			k *= 1.0 - st.r;
			// Three scales in world space (tiles of 420 / 90 / 16 m: patches of ≈ 40 m, clumps of ≈ 9 m, grain of
			// ≈ 1.6 m), rotated against each other so the tiling does not line up; the noise is centred (mean 0.5),
			// so its mipmaps fade to no change.
			mat2 rot1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
			mat2 rot2 = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
			vec2 p = world_xz;
			float n1 = texture(terrain_detail_tex, rot1 * p / 420.0).r - 0.5;
			float n2 = texture(terrain_detail_tex, rot2 * p / 90.0).r - 0.5;
			float n3 = texture(terrain_detail_tex, p / 16.0).r - 0.5;
			// Coloured ground: the patches go toward a deeper, more saturated version of the photo's colour (growth)
			// or a paler, drier one; then the grain.
			float patch = clamp(3.0 * n1 + 3.0 * n2, -1.0, 1.0);
			vec3 deep = c * c / max(lum, 0.01);
			vec3 dry = mix(vec3(lum), c, 0.55) * 1.3;
			vec3 lc = patch < 0.0 ? mix(c, deep, -0.8 * patch) : mix(c, dry, 0.5 * patch);
			lc *= 1.0 + 1.3 * n3 + 0.5 * n2;
			// Grey ground: a faint grain.
			vec3 gc = c * (1.0 + 0.35 * n3 + 0.15 * n2);
			ALBEDO = mix(c, mix(gc, lc, land), k);
			// Normal detail (tangent space: x along the world X, y along Z), built here as the terrain mesh has no
			// tangents.
			vec3 nd = texture(terrain_detail_normal, p / 16.0).rgb * 2.0 - 1.0;
			vec3 t = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
			t = normalize(t - NORMAL * dot(NORMAL, t));
			vec3 b = cross(NORMAL, t);
			NORMAL = normalize(mix(NORMAL, normalize(t * nd.x + b * nd.y + NORMAL * max(nd.z, 0.1)), k * mix(0.2, 1.0, land)));
		}
	}
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
