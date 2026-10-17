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
// Preferences "Water" (render_options.gd, docs/rendering.md §1.3): 0 = the original flat-shaded water. 1 = waves (six
// waves plus two ripple layers), sun glint and the sky's reflection with Fresnel on the generated sea and on the
// photo's water inside terraintype.dat's water within ≈ 12 km of the camera.
global uniform float terrain_water;
// The water's noise, trilinear (anisotropic taps at grazing angles doubled the water's cost): the ripples from the
// detail normal map, the wind patches and the crests' warp from the detail noise.
global uniform sampler2D terrain_water_noise : filter_linear_mipmap, repeat_enable;
global uniform sampler2D terrain_water_warp : filter_linear_mipmap, repeat_enable;
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

// sea_colour is in sRGB, the sampled colour linear: compared in sRGB (as in fragment()).
bool is_open_sea(vec2 uv) {
	vec3 c = pow(textureLod(colour_tex, uv, 3.0).rgb, vec3(1.0 / 2.2));
	return distance(c, sea_colour) < 0.08;
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

// The direction the waves travel (Godot X east, Z south): toward the east-north-east, from the Mediterranean's
// prevailing westerly.
const vec2 WIND = vec2(0.96, -0.28);

vec2 rot(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

// One wave of wavelength len (m), wave vector kd (k · its direction), angular speed w = sqrt(g · k), steepness s
// (amplitude · k): its slope, faded between 16 and 5 pixels per wavelength; the faded part's variance adds to lost.
vec2 wave(vec2 p, float t, float px, vec2 kd, float w, float phase, float s, float len, inout float lost) {
	float aa = 1.0 - smoothstep(0.06, 0.2, px / len);
	lost += 0.5 * s * s * (1.0 - aa);
	return kd * (len / 6.2832) * (s * aa * cos(dot(kd, p) - w * t + phase));
}

// The water's slope (d height / dx, dz) at world p (m), time t (s), with p's screen derivatives dx, dy: six waves,
// three swells and three wind waves (deep-water speed sqrt(g / k)), each fading out between 16 and 5 pixels per wavelength,
// then two scrolling ripple layers from the noise normal map, all scaled by wind patches (noise of ≈ 1.7 km tiles).
// `lost` returns the slope variance the faded waves no longer draw: it goes into the roughness, so the sun's glint
// spreads into a glitter path far away.
vec2 water_slope(vec2 p, vec2 dx, vec2 dy, float t, out float lost) {
	float px = max(length(dx), length(dy));
	float patch = 0.5 + 1.6 * textureGrad(terrain_water_warp, p / 1700.0 + WIND * t * 0.0015, dx / 1700.0, dy / 1700.0).r;
	patch = clamp(patch * patch - 0.2, 0.25, 1.8);
	vec2 slope = vec2(0.0);
	lost = 0.0;
	if (px < 0.2 * 97.0) {
		// The crests bent by a domain warp of up to ± 9 m (noise of 260 / 330 m tiles), so they do not line up into a lattice.
		vec2 wp = p + 18.0 * vec2(textureGrad(terrain_water_warp, p / 260.0, dx / 260.0, dy / 260.0).r,
				textureGrad(terrain_water_warp, rot(p, 1.3) / 330.0, rot(dx, 1.3) / 330.0, rot(dy, 1.3) / 330.0).r) - 9.0;
		// Wavelengths 97, 53, 31 m (swell) and 17, 11.3, 6.1 m (wind waves), within ± 0.9 rad of the wind; the wave
		// vectors written out.
		slope += wave(wp, t, px, vec2(0.06218, -0.01814), 0.7971, 0.0, 0.03, 97.0, lost);
		slope += wave(wp, t, px, vec2(0.11579, 0.02543), 1.0784, 1.7, 0.035, 53.0, lost);
		slope += wave(wp, t, px, vec2(0.15712, -0.12804), 1.4101, 4.1, 0.035, 31.0, lost);
		slope += wave(wp, t, px, vec2(0.13949, -0.34227), 1.9041, 2.9, 0.04, 17.0, lost);
		slope += wave(wp, t, px, vec2(0.50857, 0.22480), 2.3355, 5.3, 0.035, 11.3, lost);
		slope += wave(wp, t, px, vec2(1.02642, -0.08621), 3.1788, 0.8, 0.03, 6.1, lost);
		// Ripple tiles of 41.3 and 8.9 m (no simple ratio to each other or to the waves), faded like the waves.
		const float R1 = 41.3;
		const float R2 = 8.9;
		vec2 r1 = textureGrad(terrain_water_noise, rot(p, 0.5) / R1 + WIND * t * 0.04, rot(dx, 0.5) / R1, rot(dy, 0.5) / R1).xy * 2.0 - 1.0;
		vec2 r2 = textureGrad(terrain_water_noise, rot(p, -1.1) / R2 + rot(WIND, 0.8) * t * 0.11, rot(dx, -1.1) / R2, rot(dy, -1.1) / R2).xy * 2.0 - 1.0;
		float ra1 = 1.0 - smoothstep(0.05, 0.3, px / R1);
		float ra2 = 1.0 - smoothstep(0.1, 0.5, px / R2);
		slope += 0.18 * (r1 * ra1 + r2 * ra2);
		lost += 0.004 * (2.0 - ra1 - ra2);
	} else {
		// Far away every wave and ripple has faded: only their slope variance is left.
		lost = 0.5 * (0.03 * 0.03 * 2.0 + 0.035 * 0.035 * 3.0 + 0.04 * 0.04) + 0.008;
	}
	lost *= patch * patch;
	return slope * patch;
}

void fragment() {
	ALBEDO = texture(colour_tex, UV).rgb;
	// Screen derivatives taken here, outside any branch that varies per pixel (they are undefined inside one).
	vec2 wdx = dFdx(world_xz);
	vec2 wdy = dFdy(world_xz);
	// Water (Preferences "Water"): the generated sea by its colour, and near the camera the photo's blue-green pixels inside
	// terraintype.dat's water (the beaches stay land).
	float wm = 0.0;
	if (terrain_water > 0.0) {
		// sea_colour is in sRGB, the sampled colour linear: compared in sRGB.
		vec3 c = pow(ALBEDO, vec3(1.0 / 2.2));
		float open = 1.0 - smoothstep(0.04, 0.08, distance(c, sea_colour));
		vec2 suv = (world_xz - terrain_surface_rect.xy) * terrain_surface_rect.z;
		float inside = smoothstep(0.0, 0.1, min(min(suv.x, suv.y), min(1.0 - suv.x, 1.0 - suv.y)));
		float tw = texture(terrain_surface, suv).r * inside;
		float bluish = smoothstep(0.02, 0.07, max(c.g, c.b) - c.r) * (1.0 - smoothstep(0.55, 0.7, dot(c, vec3(0.2126, 0.7152, 0.0722))));
		wm = max(open, tw * bluish);
	}
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
	if (wm > 0.0) {
		float lost;
		vec2 sl = water_slope(world_xz, wdx, wdy, TIME, lost);
		vec3 n = normalize((VIEW_MATRIX * vec4(normalize(vec3(-sl.x, 1.0, -sl.y)), 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, n, wm));
		// GGX alpha from the ripples below a pixel plus the faded waves' slope variance; Godot's roughness = sqrt(alpha).
		float alpha = sqrt(0.0016 + 2.0 * lost);
		ROUGHNESS = mix(ROUGHNESS, sqrt(alpha), wm);
		// F0 ≈ 0.0125 (Godot: 0.16 · specular², which also scales the grazing reflection by 50 · F0): the sea keeps its
		// blue up to a few degrees below the horizon. The body colour a little darker, as the sky's reflection adds to it.
		SPECULAR = mix(SPECULAR, 0.28, wm);
		ALBEDO *= mix(1.0, 0.75, wm);
	}
}
