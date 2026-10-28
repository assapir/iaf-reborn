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
// Preferences "Airbases" (terrain/airbases.gd, docs/rendering.md §7): 0 = the original imagery; 1 = near the ground, a
// procedural runway, taxiway and apron surface with markings over the nearest base's paved surface. The mask: R = paved,
// G = apron (tinted concrete), B = the distance to the nearest taxi line / 10 m; rect = (x0, z0 of its north-west corner, 1 / width m, 1 / height m). The data: per runway
// three texels (centre x, z, unit direction x, z from end 0 to end 1), (half length, half width, number at end 0, at
// end 1), (threshold at end 0, at end 1: metres in from the end, letter at end 0, at end 1: 0 none, 1 L, 2 R, 3 C);
// info = (runways, the taxi lines' half width m, 0, 0).
global uniform float terrain_airbases;
global uniform sampler2D airbase_mask : filter_linear_mipmap, repeat_disable;
// The mask's uv = mat2(airbase_mask_xf.xy, airbase_mask_xf.zw) · world_xz + airbase_mask_rect.xy (a moved base's mask is
// turned and scaled, World scale Real).
global uniform vec4 airbase_mask_rect;
global uniform vec4 airbase_mask_xf;
global uniform sampler2D airbase_data : filter_nearest, repeat_disable;
global uniform vec4 airbase_info;
// Preferences "Ground textures" (terrain/ground_textures.gd, docs/rendering.md §1.4): 0 = off; 1 = where they resolve, CC0
// ambientCG textures in place of the close up's fine grain: their colour over its own mean modulates the photo's colour,
// with their normal and roughness. Layers (ground_scale_a / _b: 1 / metres per repeat): GT_* below.
// Rain (ours, Graphics → MORE "Rain", terrain/weather.gd; docs/rendering.md §10): how wet the ground is, 0 = dry.
global uniform float rain_wet;
global uniform float rain_spec;
global uniform float ground_tex;
global uniform sampler2DArray ground_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2DArray ground_nr : filter_linear_mipmap, repeat_enable;
global uniform vec4 ground_scale_a;
global uniform vec4 ground_scale_b;
const int GT_ASPHALT = 0;
const int GT_CONCRETE = 1;
const int GT_SAND = 2;
const int GT_GRAVEL = 3;
const int GT_GRASS = 4;
const int GT_SOIL = 5;
const int GT_ROCK = 6;
varying vec2 world_xz;
varying float sea;
varying float elev;
// The Survey 2 m modern photo (docs/imagery.md §5): its pale rock and soil in the hills are a neutral grey (its
// auto-levels keep a sheet's colour balance), where the real limestone, chalk and terra rossa are tan. 1 = warm the
// grey, pale land above 60–200 m toward tan (WARM); 0 for every other layer.
#include "res://terrain/city_glow.gdshaderinc"
global uniform float terrain_warm;
const vec3 WARM = vec3(1.2, 1.0, 0.76);

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
	elev = VERTEX.y;
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
// (amplitude · k): its slope, faded between 28 and 10 pixels per wavelength (closer to the pixel size the glint's
// sharp highlight on it aliases into stripes on the far water); the faded part's variance adds to lost.
vec2 wave(vec2 p, float t, float px, vec2 kd, float w, float phase, float s, float len, inout float lost) {
	float aa = 1.0 - smoothstep(0.035, 0.1, px / len);
	lost += 0.5 * s * s * (1.0 - aa);
	return kd * (len / 6.2832) * (s * aa * cos(dot(kd, p) - w * t + phase));
}

// The water's slope (d height / dx, dz) at world p (m), time t (s), with p's screen derivatives dx, dy: six waves,
// three swells and three wind waves (deep-water speed sqrt(g / k)), each fading out between 28 and 10 pixels per wavelength,
// then two scrolling ripple layers from the noise normal map, all scaled by wind patches (noise of ≈ 1.7 km tiles).
// `lost` returns the slope variance the faded waves no longer draw: it goes into the roughness, so the sun's glint
// spreads into a glitter path far away.
vec2 water_slope(vec2 p, vec2 dx, vec2 dy, float t, out float lost) {
	float px = max(length(dx), length(dy));
	float patch = 0.5 + 1.6 * textureGrad(terrain_water_warp, p / 1700.0 + WIND * t * 0.0015, dx / 1700.0, dy / 1700.0).r;
	patch = clamp(patch * patch - 0.2, 0.25, 1.8);
	vec2 slope = vec2(0.0);
	lost = 0.0;
	if (px < 0.3 * 41.3) {
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


// --- Ground textures -------------------------------------------------------------------------------------------------

// Layer l at world p (m), (dx, dy) its screen derivatives: the colour over the layer's mean colour (stored halved,
// iaf_tools::thirdparty), and (tangent normal x, y, roughness). Sampled with explicit gradients, so it may sit in a branch.
void gt_sample(int l, vec2 p, vec2 dx, vec2 dy, out vec3 detail, out vec3 nr) {
	float s = l < 4 ? ground_scale_a[l] : ground_scale_b[l - 4];
	vec3 uv = vec3(p * s, float(l));
	detail = clamp(2.0 * textureGrad(ground_albedo, uv, dx * s, dy * s).rgb, vec3(0.3), vec3(2.0));
	vec4 t = textureGrad(ground_nr, uv, dx * s, dy * s);
	nr = vec3(t.a * 2.0 - 1.0, t.g * 2.0 - 1.0, t.r);
}

// A tangent normal (x along world X, y toward north) in view space about the surface normal n.
vec3 gt_normal(vec3 n, vec2 nxy, mat4 view) {
	vec3 t = normalize((view * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	t = normalize(t - n * dot(n, t));
	vec3 b = cross(n, t);
	return normalize(t * nxy.x + b * nxy.y + n * sqrt(max(1.0 - dot(nxy, nxy), 0.01)));
}

// --- Airbases (Detailed) ---------------------------------------------------------------------------------------------
// The markings' sizes follow ICAO Annex 14 for a 60 m runway, scaled by the runway's width (the 1998 art's runways are
// 55–95 m wide): threshold stripes, designation numbers, centreline, touchdown zone and aiming point marks, edge lines.
// Every mark is box-filtered over the pixel's footprint (fw), so it fades to its average instead of shimmering far away.

// Coverage of the band |x| < hw by a pixel of footprint fw centred at x.
float ab_band(float x, float hw, float fw) {
	fw = max(fw, 1e-3);
	return (clamp(x + 0.5 * fw, -hw, hw) - clamp(x - 0.5 * fw, -hw, hw)) / fw;
}

// Coverage of the rectangle lo..hi.
float ab_box(vec2 p, vec2 lo, vec2 hi, vec2 fw) {
	vec2 c = 0.5 * (lo + hi);
	vec2 h = 0.5 * (hi - lo);
	return ab_band(p.x - c.x, h.x, fw.x) * ab_band(p.y - c.y, h.y, fw.y);
}

// The integral from 0 to x of a pulse train (on for `on` m of every `period` m from 0).
float ab_train_int(float x, float on, float period) {
	return floor(x / period) * on + min(mod(x, period), on);
}

// Coverage of the pulse train.
float ab_train(float x, float on, float period, float fw) {
	fw = max(fw, 1e-3);
	return (ab_train_int(x + 0.5 * fw, on, period) - ab_train_int(x - 0.5 * fw, on, period)) / fw;
}

float ab_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// A runway digit (0–9) as block strokes in a cell of w × h m: p = (across to the pilot's right, along away from the
// threshold) from the cell's lower left corner; t = stroke width. Segments a–g as a seven-segment digit; 1 is one
// centred bar.
float ab_digit(int d, vec2 p, float w, float h, float t, vec2 fw) {
	if (d == 1) {
		return ab_box(p, vec2(0.5 * (w - t), 0.0), vec2(0.5 * (w + t), h), fw);
	}
	// Bits: a b c d e f g (top, top right, bottom right, bottom, bottom left, top left, middle).
	int m = d == 0 ? 0x7E : d == 2 ? 0x6D : d == 3 ? 0x79 : d == 4 ? 0x33 : d == 5 ? 0x5B : d == 6 ? 0x5F
			: d == 7 ? 0x70 : d == 8 ? 0x7F : 0x7B;
	float c = 0.0;
	float hm = 0.5 * h;
	if ((m & 0x40) != 0) c = max(c, ab_box(p, vec2(0.0, h - t), vec2(w, h), fw));
	if ((m & 0x20) != 0) c = max(c, ab_box(p, vec2(w - t, hm), vec2(w, h), fw));
	if ((m & 0x10) != 0) c = max(c, ab_box(p, vec2(w - t, 0.0), vec2(w, hm), fw));
	if ((m & 0x08) != 0) c = max(c, ab_box(p, vec2(0.0, 0.0), vec2(w, t), fw));
	if ((m & 0x04) != 0) c = max(c, ab_box(p, vec2(0.0, 0.0), vec2(t, hm), fw));
	if ((m & 0x02) != 0) c = max(c, ab_box(p, vec2(0.0, hm), vec2(t, h), fw));
	if ((m & 0x01) != 0) c = max(c, ab_box(p, vec2(0.0, hm - 0.5 * t), vec2(w, hm + 0.5 * t), fw));
	return c;
}

// A runway designation's letter (1 L, 2 R, 3 C) as block strokes in a cell of w × h m, as ab_digit; R's leg a
// diagonal stroke.
float ab_letter(int l, vec2 p, float w, float h, float t, vec2 fw) {
	float hm = 0.5 * h;
	float c = ab_box(p, vec2(0.0, 0.0), vec2(t, h), fw);
	if (l != 2) {
		c = max(c, ab_box(p, vec2(0.0, 0.0), vec2(w, t), fw));
	}
	if (l != 1) {
		c = max(c, ab_box(p, vec2(0.0, h - t), vec2(w, h), fw));
	}
	if (l == 2) {
		c = max(c, ab_box(p, vec2(w - t, hm), vec2(w, h), fw));
		c = max(c, ab_box(p, vec2(0.0, hm - 0.5 * t), vec2(w, hm + 0.5 * t), fw));
		vec2 a = vec2(0.35 * w, hm);
		vec2 ab = vec2(w - 0.5 * t, 0.5 * t) - a;
		float u = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
		c = max(c, ab_band(length(p - a - ab * u), 0.5 * t, max(fw.x, fw.y)));
	}
	return c;
}

// The designation's extra length when it has a letter (m past the stripes): the letter's height and a 6 m gap.
float ab_letter_len(int letter, float sc) {
	return letter > 0 ? 15.0 * sc : 0.0;
}

// The paint at one runway end: s = metres past the threshold into the runway, x = metres to the right of the
// centreline for a pilot landing from this end, (fs, fx) their pixel footprints; sc = width / 60 m; len = the
// runway's length; num = its designation number at this end, letter its letter (ab_letter, 0: none). Returns (paint,
// rubber).
vec2 ab_end_marks(float s, float x, float fs, float fx, float sc, float hw, float len, int num, int letter) {
	vec2 f = vec2(fx, fs);
	vec2 p = vec2(x, s);
	float ax = abs(x);
	float paint = 0.0;
	// Threshold: 8 stripes each side of a 3.6 m gap, 1.8 m wide and apart, 30 m long, 6 m from the end.
	float t0 = 6.0;
	if (s < -1.0 || s > 1200.0) {
		return vec2(0.0);
	}
	if (s > t0 - 2.0 && s < t0 + 32.0) {
		float xa = ax - 1.8 * sc;
		paint = ab_train(xa, 1.8 * sc, 3.6 * sc, fx) * step(0.0, xa) * step(xa, 28.8 * sc) * ab_band(s - t0 - 15.0, 15.0, fs);
	}
	// Designation: two digits 9 m tall, 12 m past the stripes, upright to the landing pilot. A parallel runway's
	// letter stands between the stripes and the digits (World scale Real, docs/world-scale.md §4.3).
	float dh = 9.0 * sc;
	float dw = 3.6 * sc;
	float gap = 1.8 * sc;
	float n0 = t0 + 30.0 + 12.0;
	float nl = n0 + ab_letter_len(letter, sc);
	if (letter > 0 && s > n0 - 1.0 && s < n0 + dh + 1.0) {
		paint = max(paint, ab_letter(letter, p - vec2(-0.5 * dw, n0), dw, dh, 0.9 * sc, f));
	}
	if (s > nl - 1.0 && s < nl + dh + 1.0) {
		paint = max(paint, ab_digit(num / 10, p - vec2(-dw - 0.5 * gap, nl), dw, dh, 0.9 * sc, f));
		paint = max(paint, ab_digit(num % 10, p - vec2(0.5 * gap, nl), dw, dh, 0.9 * sc, f));
	}
	// Aiming point: two bars 45 m long, 8 m wide, inner edges 18 m apart, 400 m past the threshold.
	float aim = t0 + 400.0;
	if (len > 2400.0) {
		paint = max(paint, ab_box(vec2(ax, s), vec2(9.0 * sc, aim), vec2(17.0 * sc, aim + 45.0), f));
	}
	// Touchdown zone: bars 22.5 m long, 1.8 m wide, 1.5 m apart, in pairs of 3, 3, 2, 2, 1, 1 every 150 m (the aiming
	// point takes the 450 m pair's place).
	int k0 = clamp(int(floor((s - t0 + 1.0) / 150.0)), 1, 7);
	for (int k = k0; k <= min(k0, 6); k++) {
		float z = t0 + 150.0 * float(k);
		if (k == 3 && len > 2400.0) {
			continue;
		}
		int bars = k <= 2 ? 3 : k <= 4 ? 2 : 1;
		if (s > z - 1.0 && s < z + 24.0 && ax > 8.0 * sc && ax < 9.0 * sc + 3.3 * sc * float(bars)) {
			float xa = ax - 9.0 * sc;
			paint = max(paint, ab_train(xa, 1.8 * sc, 3.3 * sc, fx) * step(0.0, xa) * step(xa, 3.3 * sc * float(bars) - 1.5 * sc)
					* ab_band(s - z - 11.25, 11.25, fs));
		}
	}
	// Rubber: the main gears' tracks, 1–6 m off the centreline, from ≈ 150 m to ≈ 1100 m past the threshold.
	float rub = smoothstep(t0 + 80.0, t0 + 300.0, s) * (1.0 - smoothstep(t0 + 650.0, t0 + 1150.0, s))
			* smoothstep(0.5, 1.5, ax) * (1.0 - smoothstep(4.0, 7.0, ax));
	return vec2(paint, rub);
}

// Rain: water in the pores darkens the ground and its film smooths it, more on grey ground (pavement, rock); its
// specular is `rain_spec` (weather.gd: lower under the Atmospheric sky, whose reflections stay blue). On the Detailed
// airbases' flat pavement (`paved`) within 800 m the low spots of the detail noise hold puddles: flat, darker than the
// pavement around them, a dim reflection of the sky. Not on water.
void wet_ground(inout vec3 alb, inout float rough, inout float spec, inout vec3 nrm, vec3 n_geo, vec2 xz, float dist,
		float water, float paved, mat4 view) {
	float k = rain_wet * (1.0 - water);
	float hi = max(max(alb.r, alb.g), alb.b);
	float grey = 1.0 - smoothstep(0.15, 0.35, (hi - min(min(alb.r, alb.g), alb.b)) / max(hi, 1e-3));
	float lvl = smoothstep(0.985, 0.998, dot(n_geo, (view * vec4(0.0, 1.0, 0.0, 0.0)).xyz));
	float pud = 0.7 * k * paved * lvl * (1.0 - smoothstep(300.0, 800.0, dist))
			* smoothstep(0.66, 0.8, texture(terrain_detail_tex, xz / 13.0).r);
	alb *= mix(1.0, mix(0.75, 0.6, grey), k) * (1.0 - 0.45 * pud);
	rough = mix(mix(rough, mix(0.8, 0.65, grey), k), 0.3, pud);
	spec = mix(spec, rain_spec, k);
	nrm = normalize(mix(nrm, n_geo, pud));
}

void fragment() {
	ALBEDO = texture(colour_tex, UV).rgb;
	vec3 n_geo = NORMAL;
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
	if (terrain_warm > 0.0) {
		// Grey (chroma under ≈ 0.05 in ≈ sRGB) and pale (not asphalt, not snow), in the hills, not water.
		vec3 cs = sqrt(ALBEDO);
		float ls = dot(cs, vec3(0.2126, 0.7152, 0.0722));
		float cc = max(cs.r, max(cs.g, cs.b)) - min(cs.r, min(cs.g, cs.b));
		float kw = (1.0 - smoothstep(0.06, 0.12, cc)) * smoothstep(0.3, 0.42, ls) * (1.0 - smoothstep(0.75, 0.9, ls));
		kw *= smoothstep(60.0, 200.0, elev) * (1.0 - wm) * (1.0 - sea);
		ALBEDO *= mix(vec3(1.0), WARM, kw);
	}
	ROUGHNESS = 0.95;
	float dist = length(VERTEX);
	// Ground textures where they resolve: gm = the pixel's ground footprint (m, the geometric mean of its two axes, as
	// the anisotropic filter sees it); full up to 0.05 m, none past 0.12 m (a repeat of 2–3 m under ≈ 20 pixels, where
	// its tiling would show as a lattice on mottled layers such as the grass), so far and grazing pixels skip the
	// samples. tg = their share of the close up's fine grain: all of it up to 0.03 m, none past 0.1 m, where the grain
	// reads better.
	float gm = sqrt(length(wdx) * length(wdy));
	float tf = ground_tex * (1.0 - smoothstep(0.05, 0.12, gm));
	float tg = ground_tex * (1.0 - smoothstep(0.03, 0.1, gm));
	if (terrain_detail > 0.0 || tf > 0.0) {
		float k = terrain_detail * (1.0 - smoothstep(300.0, 1500.0, dist)) * (1.0 - sea);
		float kt = tf * (1.0 - sea);
		if (k > 0.0 || kt > 0.0) {
			vec3 c = ALBEDO;
			vec2 st = texture(terrain_surface, (world_xz - terrain_surface_rect.xy) * terrain_surface_rect.z).rg;
			float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
			float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
			// Coloured ground vs grey (in airbases the aprons' blue / purple tint is still pavement).
			float land = smoothstep(0.015, 0.05, chroma - 0.05 * st.g) * (1.0 - smoothstep(0.0, 0.03, c.b - max(c.r, c.g) - 0.1 * st.g));
			k *= 1.0 - st.r;
			kt *= 1.0 - st.r;
			// Three scales in world space (tiles of 420 / 90 / 16 m: patches of ≈ 40 m, clumps of ≈ 9 m, grain of
			// ≈ 1.6 m), rotated against each other so the tiling does not line up; the noise is centred (mean 0.5),
			// so its mipmaps fade to no change. The ground textures take the grain's place near the camera.
			mat2 rot1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
			mat2 rot2 = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
			vec2 p = world_xz;
			float n2 = textureGrad(terrain_detail_tex, rot2 * p / 90.0, rot2 * wdx / 90.0, rot2 * wdy / 90.0).r - 0.5;
			if (k > 0.0) {
				float n1 = texture(terrain_detail_tex, rot1 * p / 420.0).r - 0.5;
				float n3 = (texture(terrain_detail_tex, p / 16.0).r - 0.5) * (1.0 - tg);
				// Coloured ground: the patches go toward a deeper, more saturated version of the photo's colour (growth)
				// or a paler, drier one; then the grain.
				float patch = clamp(3.0 * n1 + 3.0 * n2, -1.0, 1.0);
				vec3 deep = c * c / max(lum, 0.01);
				// Drier: paler and a little less saturated, keeping its hue (halving the chroma turned pale rock
				// and soil white).
				vec3 dry = mix(vec3(lum), c, 0.8) * 1.2;
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
				NORMAL = normalize(mix(NORMAL, normalize(t * nd.x + b * nd.y + NORMAL * max(nd.z, 0.1)), k * mix(0.2, 1.0, land) * (1.0 - tg)));
			}
			// Under Detailed airbases the nearest base's pavement is drawn below (with its own textures).
			if (kt > 0.0 && !(terrain_airbases > 0.0 && st.g * (1.0 - land) > 0.5)) {
				// The layer weights from the photo's colour (compared in ≈ sRGB): in an airbase its grey is asphalt and
				// its blue / purple tint concrete; elsewhere green is grass, pale sand, saturated brown soil, the rest
				// gravel; slopes over ≈ 30° rock.
				vec3 cs = sqrt(c);
				float ls = dot(cs, vec3(0.2126, 0.7152, 0.0722));
				float cc = max(cs.r, max(cs.g, cs.b)) - min(cs.r, min(cs.g, cs.b));
				float ab = st.g * (1.0 - land);
				float tint = smoothstep(0.0, 0.03, c.b - max(c.r, c.g));
				float slope = 1.0 - (INV_VIEW_MATRIX * vec4(n_geo, 0.0)).y;
				float rock = smoothstep(0.1, 0.2, slope) * (1.0 - ab);
				float wgr = smoothstep(0.0, 0.04, cs.g - cs.r);
				float wsa = smoothstep(0.55, 0.7, ls) * (1.0 - wgr);
				float rest = (1.0 - wgr) * (1.0 - wsa);
				float wso = rest * smoothstep(0.1, 0.18, cc);
				float nat = (1.0 - ab) * (1.0 - rock);
				float w[7] = float[7](ab * (1.0 - tint), ab * tint, wsa * nat, (rest - wso) * nat, wgr * nat, wso * nat, rock);
				// The two strongest layers, blended by their weights.
				int l1 = 0;
				for (int i = 1; i < 7; i++) {
					if (w[i] > w[l1]) l1 = i;
				}
				int l2 = l1 == 0 ? 1 : 0;
				for (int i = 0; i < 7; i++) {
					if (i != l1 && w[i] > w[l2]) l2 = i;
				}
				float b2 = w[l2] / max(w[l1] + w[l2], 1e-4);
				vec3 d1, r1, d2, r2;
				gt_sample(l1, p, wdx, wdy, d1, r1);
				// A second layer only where it weighs a fifth or more (most pixels sample one).
				if (b2 > 0.2) {
					gt_sample(l2, p, wdx, wdy, d2, r2);
					float bl = (b2 - 0.2) / 0.6;
					d1 = mix(d1, d2, bl);
					r1 = mix(r1, r2, bl);
				}
				// Full strength on pavement and natural ground, less on grey ground outside an airbase (towns, roads);
				// varied over ≈ 9 m clumps (the 90 m noise), so the repeat does not line up into a grid.
				float ks = kt * mix(0.6, 1.0, max(land, ab)) * clamp(0.6 + 2.5 * n2, 0.25, 1.0);
				ALBEDO *= mix(vec3(1.0), d1, ks);
				NORMAL = normalize(mix(NORMAL, gt_normal(NORMAL, r1.xy, VIEW_MATRIX), ks));
				ROUGHNESS = mix(ROUGHNESS, mix(0.8, 1.0, r1.z), ks);
			}
		}
	}
	SPECULAR = 0.1;
	float paved_k = 0.0;  // Detailed airbases' paved surface (rain puddles)
	// Airbases (Preferences "Airbases"): within 6 km, on the nearest base's paved surface.
	float kab = terrain_airbases * (1.0 - smoothstep(2500.0, 6000.0, length(VERTEX))) * (1.0 - sea);
	vec2 muv = mat2(airbase_mask_xf.xy, airbase_mask_xf.zw) * world_xz + airbase_mask_rect.xy;
	if (kab > 0.0 && muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
		// R / G: paved coverage (straight anti-aliased edges) / concrete coverage (blurred over ≈ 5 m), so the bilinear
		// lookup has a smooth edge at 0.5, drawn one pixel wide (fwidth); mipmapped, the edges soften far away.
		vec2 pm = texture(airbase_mask, muv).rg;
		vec2 p = world_xz;
		vec2 pw = clamp(fwidth(pm) * 0.75, vec2(0.02), vec2(0.5));
		float paved = smoothstep(0.5 - pw.x, 0.5 + pw.x, pm.r);
		float runway = 0.0;
		float paint = 0.0;
		float rubber = 0.0;
		float yellow = 0.0;
		float seam = 0.0;
		float patchy = 0.0;
		float concrete_mask = smoothstep(0.5 - pw.y, 0.5 + pw.y, pm.g);
		for (int i = 0; i < int(airbase_info.x); i++) {
			vec4 a0 = texelFetch(airbase_data, ivec2(3 * i, 0), 0);
			vec4 a1 = texelFetch(airbase_data, ivec2(3 * i + 1, 0), 0);
			vec4 a2 = texelFetch(airbase_data, ivec2(3 * i + 2, 0), 0);
			vec2 d = a0.zw;
			vec2 r = vec2(-d.y, d.x);
			vec2 q = p - a0.xy;
			float al = dot(q, d);
			float ac = dot(q, r);
			float hl = a1.x;
			float hw = a1.y;
			if (abs(al) > hl + 2.0 || abs(ac) > hw + 2.0) {
				continue;
			}
			float fa = abs(dot(wdx, d)) + abs(dot(wdy, d));
			float fc = abs(dot(wdx, r)) + abs(dot(wdy, r));
			float inside = ab_band(al, hl, fa) * ab_band(ac, hw, fc);
			runway = max(runway, inside);
			float sc = clamp(2.0 * hw / 60.0, 0.75, 1.6);
			// Metres past each threshold (the thresholds stand a2.x / a2.y in from the ends).
			float s0 = al + hl - a2.x;
			float s1 = hl - al - a2.y;
			float len = 2.0 * hl - a2.x - a2.y;
			vec2 e0 = ab_end_marks(s0, ac, fa, fc, sc, hw, len, int(a1.z), int(a2.z));
			vec2 e1 = ab_end_marks(s1, -ac, fa, fc, sc, hw, len, int(a1.w), int(a2.w));
			float pt = max(e0.x, e1.x);
			float landing = step(0.0, s0) * step(0.0, s1);
			// Centreline: 30 m dashes, 20 m gaps, 0.9 m wide, between the designations.
			float cl0 = 30.0 + 12.0 + 9.0 * sc + 12.0;
			if (s0 > cl0 + ab_letter_len(int(a2.z), sc) && s1 > cl0 + ab_letter_len(int(a2.w), sc)) {
				pt = max(pt, ab_train(s0 - cl0, 30.0, 50.0, fa) * ab_band(ac, 0.45 * sc, fc));
			}
			// Edge lines: 0.9 m wide, 1.5 m inside the edge, past both thresholds.
			pt = max(pt, ab_band(abs(ac) - (hw - 1.5), 0.45 * sc, fc) * landing);
			// Before a threshold (blast pad, overrun): yellow chevrons pointing at it, 30 m apart.
			float chev = 0.0;
			float sb = min(s0, s1);
			if (sb < 0.0 && max(a2.x, a2.y) > 30.0) {
				float v = -sb - abs(ac) * 0.7;
				chev = ab_train(v, 1.2, 30.0, fa + 0.7 * fc) * step(abs(ac), hw - 3.0) * step(0.0, v);
			}
			paint = max(paint, pt * inside);
			yellow = max(yellow, chev * inside);
			// The paving: lanes 7.5 m wide with dark seams, and repaired patches (≈ 1 in 8 of 40 × 7.5 m cells).
			float ds = abs(fract((ac + hw) / 7.5 + 0.5) - 0.5) * 7.5;
			seam = max(seam, ab_band(ds, 0.06, fc) * inside);
			vec2 cell = floor(vec2(al / 40.0, (ac + hw) / 7.5));
			patchy = max(patchy, step(0.875, ab_hash(cell + float(i) * 17.0)) * inside);
			// The rubber in streaks along the runway (noise stretched 60×), sampled with the pixel's own gradients.
			float rub = max(e0.y, e1.y) * inside;
			if (rub > 0.0) {
				vec2 sq = vec2(ac / 0.6, al / 36.0);
				float streak = textureGrad(terrain_detail_tex, sq, vec2(dot(wdx, r) / 0.6, dot(wdx, d) / 36.0),
						vec2(dot(wdy, r) / 0.6, dot(wdy, d) / 36.0)).r;
				rubber = max(rubber, rub * smoothstep(0.45, 0.8, streak));
			}
		}
		// Taxi lines (iaf.ibx's taxi paths): yellow, airbase_info.y each side of the path (0.3 m wide; World scale Real
		// 1 m), on the paved surface off the runways, within 2 km; the mask's B channel holds the distance to the nearest
		// path (0–10 m).
		float fpx = max(length(wdx), length(wdy));
		float taxi = ab_band(textureLod(airbase_mask, muv, 0.0).b * 10.0, airbase_info.y, fpx) * paved * (1.0 - runway)
				* (1.0 - smoothstep(1500.0, 2000.0, length(VERTEX)));
		float surf = max(paved, runway) * kab;
		paved_k = surf;
		// Concrete slabs on the aprons only.
		float concrete = concrete_mask * (1.0 - runway);
		if (surf > 0.0) {
			// The base colour: the imagery blurred to ≈ 16 m (its markings and painted lines gone), so the surface keeps
			// the art's tone and fades into it far away.
			float texel_m = node_m / (float(textureSize(colour_tex, 0).x) * max(uv_scale, 1e-6));
			vec3 base = textureLod(colour_tex, UV, log2(max(16.0 / texel_m, 1.0))).rgb;
			float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
			// Asphalt: near-neutral grey of the art's brightness; concrete (aprons, the runways' first 300 m): lighter, warmer.
			// Toward real asphalt's brightness (the art's runways run from near black to light grey), so the paint stands
			// out on every base.
			vec3 asph = vec3(mix(lum, 0.1, 0.6)) * vec3(1.02, 1.0, 0.96);
			// Variation: patches (≈ 40 m), aggregate grain (≈ 1.5 m), repairs and slabs.
			mat2 rot1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
			float n1 = texture(terrain_detail_tex, rot1 * p / 260.0).r - 0.5;
			float n2 = texture(terrain_detail_tex, p / 37.0).r - 0.5;
			// Ground textures: asphalt (and concrete on the aprons) in place of the aggregate grain where they resolve.
			float kt = tf;
			float n3 = (texture(terrain_detail_tex, rot1 * p / 2.3).r - 0.5) * (1.0 - tg);
			vec3 c = asph * (1.0 + 0.45 * n1 + 0.25 * n2 + 0.12 * n3) * (1.0 - 0.18 * seam) * (1.0 - 0.1 * patchy);
			vec3 ta = vec3(1.0);
			vec3 tr = vec3(0.0, 0.0, 0.5);
			if (kt > 0.0) {
				gt_sample(GT_ASPHALT, p, wdx, wdy, ta, tr);
				// Varied over ≈ 4 m (the 37 m noise): worn and fresh patches, and no grid of repeats.
				kt *= clamp(0.55 + 2.5 * n2, 0.2, 0.9);
				c *= mix(vec3(1.0), ta, kt);
			}
			// Concrete slabs on the aprons: 5 m squares, each its own shade, dark joints.
			if (concrete > 0.0) {
				// The grid along the base's first runway.
				vec2 rd = airbase_info.x > 0.0 ? texelFetch(airbase_data, ivec2(0, 0), 0).zw : vec2(1.0, 0.0);
				vec2 g = vec2(dot(p, rd), dot(p, vec2(-rd.y, rd.x)));
				vec2 cell = floor(g / 5.0);
				vec2 fq = abs(fract(g / 5.0) - 0.5) * 5.0;
				float joint = max(ab_band(2.5 - fq.x, 0.06, fpx), ab_band(2.5 - fq.y, 0.06, fpx));
				vec3 slab = mix(vec3(lum), base, 0.4) * (1.08 + 0.12 * (ab_hash(cell) - 0.5) + 0.3 * n3);
				if (kt > 0.0) {
					vec3 cd, cr;
					gt_sample(GT_CONCRETE, p, wdx, wdy, cd, cr);
					slab *= mix(vec3(1.0), cd, kt);
					tr = mix(tr, cr, concrete);
				}
				c = mix(c, slab * (1.0 - 0.45 * joint), concrete);
			}
			c *= 1.0 - 0.5 * rubber;
			// Paint: worn white; taxi lines yellow.
			float wear = clamp(0.75 + 0.5 * (texture(terrain_detail_tex, p / 6.0).r - 0.5) - 0.5 * rubber, 0.0, 1.0);
			c = mix(c, vec3(0.62), paint * wear);
			c = mix(c, vec3(0.55, 0.36, 0.03), max(taxi, yellow) * 0.9 * wear);
			ALBEDO = mix(ALBEDO, c, surf);
			ROUGHNESS = mix(ROUGHNESS, mix(mix(0.88, mix(0.75, 1.0, tr.z), kt), 0.7, paint), surf);
			SPECULAR = mix(SPECULAR, 0.3, surf);
			// Micro relief: the aggregate (≈ 1.6 m tiles of the detail normal map), faded with the surface.
			vec3 nd = texture(terrain_detail_normal, p / 1.6).rgb * 2.0 - 1.0;
			vec3 tt = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
			tt = normalize(tt - NORMAL * dot(NORMAL, tt));
			vec3 bb = cross(NORMAL, tt);
			// The terrain close up's relief is the ground's, not the pavement's.
			vec3 nb = normalize(mix(NORMAL, n_geo, surf));
			NORMAL = normalize(mix(nb, normalize(tt * nd.x + bb * nd.y + nb * max(nd.z, 0.1)),
					0.12 * surf * (1.0 - paint) * (1.0 - smoothstep(30.0, 300.0, length(VERTEX))) * (1.0 - tg)));
			if (kt > 0.0) {
				NORMAL = normalize(mix(NORMAL, gt_normal(NORMAL, tr.xy, VIEW_MATRIX), kt * surf * (1.0 - 0.5 * paint)));
			}
		}
	}
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
	if (rain_wet > 0.0) {
		wet_ground(ALBEDO, ROUGHNESS, SPECULAR, NORMAL, n_geo, world_xz, dist, wm, paved_k, VIEW_MATRIX);
	}
	if (city_glow_k > 0.0) {
		// The ground lit by the lamps: its own colour under their light, so the streets and roofs keep their pattern.
		EMISSION = ALBEDO * city_glow_light(world_xz);
	}
}
