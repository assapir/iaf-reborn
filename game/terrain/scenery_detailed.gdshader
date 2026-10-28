// Scenery buildings, Scenery = Detailed (terrain/scenery.gd, docs/scenery.md §3.3; On: scenery.gdshader). The mesh
// arrays come from IafScenery:
//   UV   = wall coordinates in metres (x along the wall, y above the building's base);
//   UV2  = (building index in the cell, the building's height in metres on walls / −1 on roofs);
//   COLOR.rgb = the roof colour on the active Survey 2 m look (sRGB), on walls too;
//   COLOR.a = the wall material / 255 (iaf_tools::thirdparty::SCENERY_WALLS: plaster, stone, concrete, corrugated);
//   CUSTOM0 = the building's centre at its base (mesh frame) and, on walls, the street in front of the wall:
//     w = the facing building's height (m, whole) × 1024 + its distance (decimetres, at most 1000 = open);
//     −1 on the parapet's inner face.
// The photo's colour already holds the sun's light, and the scene lights it again: roofs take ROOF_GAIN of it, at most
// MAX_ALBEDO (linear), so a town reads as bright as the photo under it, not white.
// Flat roofs: a material picked by the photo's brightness (bitumen, grey concrete or gravel, white coating) in the
// photo's hue, with stains; pitched roofs: clay tiles. Both fade to the photo's colour with distance, as walls do.
// Walls: a per-building colour from a palette of the material's (Jerusalem stone, white / beige plaster, grey
// concrete), tinted by the photo, times the ambientCG material's colour detail (its colour over its mean); windows
// (a row per level, a column per bay, each building its own sizes) recessed by parallax, with frames, roller
// shutters, glass that reflects the sky (each pane tilted and rough by its own seed), streaks under the sills, AC
// units; loggias on blocks of flats; occlusion at the foot and in narrow streets (AO: the ambient light only). Far
// away the walls fade to the photo's colour. Damaged buildings: sooted.
shader_type spatial;
render_mode cull_back;

uniform sampler2DArray walls : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_walls = false;
// The repeat of each material's texture (m).
uniform vec4 wall_size = vec4(2.0, 2.0, 1.1, 2.0);
// The model by each building's own distance (CUSTOM0.xyz: its centre at its base, mesh frame): the near mesh to
// `near_m`, the far mesh beyond, rising from the ground over the last `grow_m` before `far_m` (scenery.gd sets these).
instance uniform bool far_model = false;
uniform float near_m = 2500.0;
uniform float far_m = 4500.0;
uniform float grow_m = 400.0;
// A byte per building, 256 per row: 0 = intact.
uniform sampler2D damage : filter_nearest;
// Detailed night lights at night: some windows lit.
uniform bool night = false;

const float ROOF_GAIN = 0.6;
const float WALL_GAIN = 0.5;
const float MAX_ALBEDO = 0.45;
// The walls take the photo's colour from FADE_NEAR to FADE_FAR (m).
const float FADE_NEAR = 700.0;
const float FADE_FAR = 2200.0;
// Window recess and loggia depth (m).
const float RECESS = 0.22;
const float LOGGIA = 1.4;
// The roof UVs' tile (m) and the parapet's height (iaf_avionics::scenery ROOF_TILE, PARAPET).
const float ROOF_TILE = 32.0;
const float PARAPET = 0.8;

varying flat float v_building;
varying flat float v_height;
varying flat float v_wall;
varying flat vec2 v_street;
varying flat float v_parapet;
varying flat vec3 v_normal;
varying float v_dist;
varying vec3 v_tangent;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A hash without sin, steady for the large coordinates of the roofs' metres.
float hash_p(vec2 p) {
	vec3 q = fract(p.xyx * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Value noise, 0–1, a cell per unit.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_p(i), hash_p(i + vec2(1.0, 0.0)), f.x), mix(hash_p(i + vec2(0.0, 1.0)), hash_p(i + 1.0), f.x),
		f.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// A building's wall colour (sRGB): Jerusalem stone, white / beige / pale plaster, grey concrete blocks.
vec3 palette(int w, float h) {
	if (w == 1) {
		return h < 0.4 ? vec3(0.86, 0.79, 0.64) : (h < 0.75 ? vec3(0.82, 0.73, 0.57) : vec3(0.89, 0.84, 0.72));
	}
	if (w == 2) {
		return h < 0.45 ? vec3(0.66, 0.66, 0.64) : (h < 0.8 ? vec3(0.73, 0.72, 0.68) : vec3(0.70, 0.66, 0.6));
	}
	if (h < 0.35) {
		return vec3(0.9, 0.89, 0.86);
	}
	if (h < 0.6) {
		return vec3(0.87, 0.82, 0.72);
	}
	if (h < 0.8) {
		return vec3(0.84, 0.77, 0.66);
	}
	return h < 0.92 ? vec3(0.8, 0.8, 0.77) : vec3(0.86, 0.76, 0.7);
}

// 1 inside [a, b] of x, edges `aa` wide.
float band(float x, float a, float b, float aa) {
	aa = max(aa, 1e-4);  // smoothstep's edges must differ
	return smoothstep(a - aa, a + aa, x) * (1.0 - smoothstep(b - aa, b + aa, x));
}

#include "res://terrain/city_glow.gdshaderinc"

void vertex() {
	vec3 c = CUSTOM0.xyz;
	float d = distance((MODEL_MATRIX * vec4(c, 1.0)).xyz, INV_VIEW_MATRIX[3].xyz);
	float g = far_model ? step(near_m, d) * (1.0 - smoothstep(far_m - grow_m, far_m, d)) : 1.0 - step(near_m, d);
	// Shown: raised to g of its height; not shown: collapsed to its centre (no triangles to draw).
	VERTEX = g > 0.001 ? vec3(VERTEX.x, c.y + (VERTEX.y - c.y) * g, VERTEX.z) : c;
	v_city_glow = city_glow_at((MODEL_MATRIX * vec4(c, 1.0)).xz);  // at the building's centre
	v_building = UV2.x;
	v_height = UV2.y;
	v_wall = floor(COLOR.a * 255.0 + 0.5);
	float s = CUSTOM0.w;
	v_parapet = step(s, -0.5);
	v_normal = NORMAL;
	v_street = vec2(floor(s / 1024.0), mod(s, 1024.0) / 10.0);
	v_dist = d;
	// Walls are upright and their UV.x runs along them: the tangent is up × the outward normal (view space).
	v_tangent = (MODELVIEW_MATRIX * vec4(cross(vec3(0.0, 1.0, 0.0), NORMAL), 0.0)).xyz;
}

void fragment() {
	int b = int(v_building + 0.5);
	float damaged = step(0.5 / 255.0, texelFetch(damage, ivec2(b % 256, b / 256), 0).r);
	vec3 photo = srgb_to_linear(COLOR.rgb);
	vec3 albedo;
	float rough = 0.9;
	float spec = 0.3;
	float ao = 1.0;
	vec3 emit = vec3(0.0);
	if (v_height < -0.5) {
		vec3 far_c = min(photo * ROOF_GAIN, vec3(MAX_ALBEDO));
		float fade = smoothstep(FADE_NEAR, FADE_FAR, v_dist);
		albedo = far_c;
		if (fade < 1.0 && COLOR.a < 0.99) {
			// Flat roofs: metres along and across the building from its centre; pitched: world metres (X east, Z south;
			// repeating every 4 km for the precision). And metres per pixel.
			bool pitched = v_normal.y < 0.97;
			float fb = float(b);
			vec2 p = pitched ? fract(UV / 128.0) * 128.0 * ROOF_TILE : UV + fb * 17.3;
			float aa = max(fwidth(p).x, fwidth(p).y);
			float hb = hash(vec2(fb, 7.7));
			// The photo's hue: its colour over its brightness, at half strength.
			vec3 hue = mix(vec3(1.0), clamp(far_c / max(luma(far_c), 0.01), vec3(0.6), vec3(1.6)), 0.5);
			// Stains: blotches of 4 m and 1 m (the small ones fade out under ~2 pixels).
			float stain = mix(0.5, vnoise(p * 0.9 + fb), 1.0 - smoothstep(0.25, 0.6, aa)) * 0.4 + vnoise(p * 0.25 + 0.5) * 0.6;
			// Darker patches where water stands (a few metres across).
			float pool = smoothstep(0.6, 0.8, vnoise(p * 0.16 + fb * 3.1)) * (0.4 + hash(vec2(fb, 8.8)));
			vec3 own;
			if (pitched) {
				// Clay tiles: courses every 0.33 m down the slope, 0.24 m tiles, each course's lower lip shaded.
				vec2 d = normalize(v_normal.xz + 1e-5);
				float course = dot(p, d) / max(v_normal.y, 0.3) / 0.33;
				float row = floor(course);
				float tile = floor(dot(p, vec2(-d.y, d.x)) / 0.24 + 0.5 * mod(row, 2.0));
				float k = 1.0 - smoothstep(0.08, 0.16, aa);
				float lip = mix(0.62, 1.05, smoothstep(0.0, 0.85, fract(course)))
					* (0.86 + 0.28 * hash_p(vec2(row, tile) + fb));
				own = vec3(0.3, 0.12, 0.065) * (0.85 + 0.3 * hb) * mix(0.9, lip, k) * mix(0.85, 1.05, stain);
				own = mix(own, far_c, 0.3);
			} else {
				// Flat roofs, by the photo's brightness (a seed per building moves the line): bitumen (some painted
				// silver in patches), grey concrete or gravel, white reflective coating.
				float l = luma(photo) + (hb - 0.5) * 0.05;
				// Membrane strips 1 m wide along the building, concrete's joints every 6 m (fade under ~2 pixels).
				float fine = 1.0 - smoothstep(0.02, 0.05, aa);
				float seam = band(fract(p.y), 0.0, 0.035, 0.0) * fine;
				float joint = max(band(fract(p.x / 6.0), 0.0, 0.004, 0.0), band(fract(p.y / 6.0), 0.0, 0.004, 0.0)) * fine;
				float mat_l;
				if (l < 0.06) {
					mat_l = 0.07;
					own = vec3(0.07) * mix(0.8, 1.0 + 3.0 * step(0.6, hash(vec2(fb, 2.2))), smoothstep(0.35, 0.75, stain));
					own *= 1.0 - 0.3 * seam;
				} else if (l < 0.13) {
					mat_l = 0.22;
					bool gravel = hash(vec2(fb, 4.4)) < 0.35;
					own = gravel ? vec3(0.22, 0.2, 0.17) : vec3(0.26, 0.255, 0.24);
					float grit = hash_p(floor(p * 8.0));
					own *= mix(1.0, 0.7 + 0.6 * grit, (gravel ? 1.0 : 0.25) * (1.0 - smoothstep(0.06, 0.12, aa)));
					own *= mix(0.62, 1.12, stain) * (1.0 - (gravel ? 0.0 : 0.35) * joint);
				} else {
					// The coating worn through to grey concrete in patches.
					float worn = smoothstep(0.72, 0.78, vnoise(p * 0.45 + fb * 1.7) + 0.12 * stain + 0.25 * hash(vec2(fb, 6.6)));
					mat_l = 0.45;
					own = mix(vec3(0.5, 0.5, 0.48) * mix(0.55, 1.05, stain * stain), vec3(0.3, 0.295, 0.28), worn);
					own *= 1.0 - 0.15 * seam;
					rough = 0.75;
				}
				own *= 1.0 - 0.3 * pool;
				// Patches re-coated or re-laid at other times: 4 × 2 m sheets, each its own shade.
				own *= mix(0.9, 1.1, hash_p(floor(p / vec2(4.0, 2.0)) + fb));
				// Halfway to the photo's brightness, in its hue: the near roof keeps the far one's tone.
				own *= hue * mix(1.0, luma(far_c) / mat_l, 0.5);
			}
			albedo = mix(own, far_c, fade);
		}
	} else if (v_parapet > 0.5) {
		// The parapet's inner face: plain wall colour, a light coping on top, grime and shade at its foot.
		float fb = float(b);
		int w = clamp(int(v_wall), 0, 3);
		vec3 own = w == 3 ? photo : srgb_to_linear(palette(w, hash(vec2(fb, 1.7)))) * mix(1.0, 0.85, hash(vec2(fb, 5.3)));
		vec3 base = min(mix(own, photo, 0.2) * WALL_GAIN, vec3(MAX_ALBEDO));
		float y = UV.y - (v_height - PARAPET);
		albedo = base * mix(0.55, 1.0, smoothstep(0.0, 0.35, y)) * mix(1.0, 1.3, step(PARAPET - 0.1, y));
		ao = mix(0.5, 1.0, smoothstep(0.0, 0.6, y));
	} else {
		int w = clamp(int(v_wall), 0, 3);
		float fb = float(b);
		float h1 = hash(vec2(fb, 1.7));
		float h2 = hash(vec2(fb, 5.3));
		float h3 = hash(vec2(fb, 9.1));
		vec3 own = w == 3 ? photo : srgb_to_linear(palette(w, h1)) * mix(1.0, 0.85, h2);
		vec3 base = min(mix(own, photo, 0.2) * WALL_GAIN, vec3(MAX_ALBEDO));
		if (has_walls) {
			base *= 2.0 * texture(walls, vec3(UV / wall_size[w], float(w))).rgb;
		}
		// Each building's grid: bays 2.9–4.1 m, levels 2.9–3.3 m; windows 40–62 % of a bay, sills at 0.9 m.
		float bay = 2.9 + 1.2 * h2;
		float level = 2.9 + 0.4 * h3;
		vec2 g = vec2(UV.x / bay, UV.y / level);
		vec2 cell = floor(g);
		vec2 f = fract(g);
		vec2 px = fwidth(g);
		float aa = max(px.x, px.y);
		// Detail where a window is over ~2 pixels: fades to its average beyond (no shimmer far away).
		float detail = (w == 3 ? 0.0 : 1.0) * (1.0 - smoothstep(0.25, 0.5, aa));
		float half_w = 0.2 + 0.11 * hash(vec2(fb, 3.3));
		float y0 = 0.9 / level;
		float y1 = min(y0 + (1.25 + 0.4 * h1) / level, 0.9);
		float h_win = hash(cell + vec2(fb * 0.37, 0.0));
		float h_win2 = hash(cell.yx + vec2(3.1, fb * 0.11));
		// Blocks of flats (3 levels and more, plaster or concrete): loggias on some bays above the ground floor.
		bool flats = v_height >= 8.5 && w != 1 && w != 3;
		bool loggia = flats && cell.y >= 1.0 && cell.y < floor(v_height / level) && h3 > 0.3
			&& mod(cell.x + floor(h1 * 2.0), 2.0) < 1.0;
		// Some loggias closed in (sgirat mirpeset): sliding glass above the balustrade, near the facade.
		float h_cell = hash(cell + vec2(fb * 0.53, 5.0));
		bool closed = loggia && h_cell < 0.3;
		float rail_top = 1.1 / level;
		vec2 lo = loggia ? vec2(0.1, closed ? rail_top : 0.0) : vec2(0.5 - half_w, y0);
		vec2 hi = loggia ? vec2(0.9, 0.93) : vec2(0.5 + half_w, y1);
		float open = band(f.x, lo.x, hi.x, aa) * band(f.y, lo.y, hi.y, aa) * detail;
		vec3 wall = base;
		// The eye in the wall's frame (along, up, out): parallax into the recess.
		vec3 n = normalize(NORMAL);
		vec3 t = normalize(v_tangent - n * dot(v_tangent, n));
		vec3 bt = cross(n, t);
		vec3 e = vec3(dot(VIEW, t), dot(VIEW, bt), max(dot(VIEW, n), 0.05));
		float depth = closed ? 0.12 : (loggia ? LOGGIA : RECESS);
		vec2 back = f - e.xy / e.z * depth / vec2(bay, level);
		bool hits_back = back.x > lo.x && back.x < hi.x && back.y > lo.y && back.y < hi.y;
		// The back: glass (a window, or the loggia's door); the reveal (sides, sill, soffit) where the eye sees it.
		vec3 inner;
		float glass = 0.0;
		float lit = 0.0;
		if (hits_back) {
			bool door = loggia && !closed;
			vec2 q = door ? vec2((back.x - 0.3) / 0.4, (back.y - 0.02) / 0.75) : (back - lo) / (hi - lo);
			// Frames 6 cm, a sliding window's meeting rail in the middle.
			vec2 fr = vec2(0.06 / ((hi.x - lo.x) * bay), 0.06 / ((hi.y - lo.y) * level));
			float pane = band(q.x, fr.x, 1.0 - fr.x, 0.0) * band(q.y, fr.y, 1.0 - fr.y, 0.0)
				* (1.0 - band(q.x, 0.5 - fr.x * 0.6, 0.5 + fr.x * 0.6, 0.0));
			// Roller shutters (trisim): down by a share per window, slats every 6 cm.
			float down = h_win < 0.35 ? 0.0 : (h_win < 0.7 ? 0.35 : (h_win < 0.9 ? 0.7 : 1.0));
			float shut = step(1.0 - down, q.y) * step(0.0, q.y) * step(q.y, 1.0) * step(0.0, q.x) * step(q.x, 1.0);
			vec3 frame_c = h2 < 0.5 ? vec3(0.4) : vec3(0.12, 0.115, 0.11);
			vec3 shutter_c = (h3 < 0.6 ? vec3(0.36, 0.36, 0.35) : vec3(0.3, 0.28, 0.24))
				* (0.85 + 0.15 * step(0.5, fract(q.y * (hi.y - lo.y) * level / 0.06)));
			vec3 room = mix(vec3(0.015, 0.018, 0.02), vec3(0.22, 0.2, 0.17), step(0.75, h_win2) * 0.6);
			bool in_door = !door || (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0);
			glass = in_door ? pane * (1.0 - shut) : 0.0;
			// The loggia's back wall, out of the sun: darker toward the slab above.
			inner = in_door ? mix(mix(frame_c, shutter_c, shut), room, glass) : base * 0.42;
			lit = glass * step(h_win2, 0.12);
		} else {
			// The reveal: lit from the side the eye looks into, the soffit darker.
			// A loggia's floor (light tiles, under the sky) where the eye looks down into it.
			inner = base * (back.y > hi.y ? 0.3 : 0.55);
			inner = loggia && !closed && back.y < lo.y ? vec3(0.3, 0.27, 0.22) * 0.8 : inner;
		}
		// Loggias: a balustrade to 1.1 m, per building solid (its top a lit coping), glass (the loggia seen through,
		// a dark handrail) or bars; the recess darker under the ceiling slab (its shadow).
		float rail_in = loggia ? step(f.y, rail_top) * step(lo.x, f.x) * step(f.x, hi.x) : 0.0;
		float h4 = hash(vec2(fb, 11.3));
		float see = h4 < 0.55 ? 0.0 : (h4 < 0.8 ? 0.65 : 0.8 * (1.0 - band(fract(UV.x / 0.12), 0.0, 0.2, px.x * bay / 0.12)));
		float rail = rail_in * (1.0 - see * detail);
		// Inside an open loggia: out of the sun and most of the sky, darker still under the slab above.
		inner *= loggia && !closed ? 0.55 * mix(1.0, 0.45, smoothstep(hi.y - 0.7, hi.y, back.y)) : 1.0;
		inner *= mix(vec3(1.0), vec3(0.85, 0.95, 0.92), rail_in * step(0.55, h4) * step(h4, 0.8));
		glass *= open * (1.0 - rail_in);
		lit *= open * (1.0 - rail_in);
		vec3 face = mix(wall, inner, open * (1.0 - rail));
		float recess = loggia && !closed ? open * (1.0 - rail) : 0.0;
		float cope = rail_in * detail * band(f.y, rail_top - 0.1 / level, rail_top, aa);
		face = mix(face, h4 < 0.55 ? min(base * 1.35, vec3(MAX_ALBEDO)) : vec3(0.05), cope);
		// Streaks under the sills (dust washed down), and an AC unit under some windows with its drip.
		float under = (1.0 - step(lo.y, f.y)) * band(f.x, lo.x, hi.x, aa) * (loggia ? 0.0 : 1.0);
		float streak = hash(vec2(floor(UV.x * 5.0), fb)) * f.y / max(lo.y, 0.01);
		face *= 1.0 - 0.22 * under * streak * detail;
		float ac = (h_win2 > 0.6 && !loggia && cell.y >= 1.0) ? 1.0 : 0.0;
		float acx = 0.5 + (h_win - 0.5) * 0.3;
		float ac_box = ac * band(f.x, acx - 0.42 / bay, acx + 0.42 / bay, aa) * band(f.y, 0.08 / level, 0.62 / level, aa);
		float grille = step(length(vec2((f.x - acx - 0.12 / bay) * bay, (f.y - 0.35 / level) * level)), 0.2);
		face = mix(face, vec3(0.42, 0.42, 0.4) * (1.0 - 0.45 * grille), ac_box * detail);
		face *= 1.0 - 0.35 * ac * band(f.x, acx - 0.42 / bay, acx + 0.42 / bay, aa)
			* band(f.y, 0.0, 0.08 / level, aa) * detail;
		// Far away: the windows' average, then the photo's colour.
		// A loggia keeps a darker cell while it is over a pixel.
		face = mix(base * mix(loggia && !closed ? 0.6 : 0.8, 0.76, smoothstep(0.5, 1.0, aa)), face, detail);
		// The parapet's coping: a lit edge at the top of the wall.
		float fy = fwidth(UV.y);
		face = mix(face, min(base * 1.3, vec3(MAX_ALBEDO)), smoothstep(v_height - 0.1 - fy, v_height - 0.1 + fy, UV.y));
		float fade = smoothstep(FADE_NEAR, FADE_FAR, v_dist);
		albedo = mix(face, min(photo * WALL_GAIN, vec3(MAX_ALBEDO)), fade);
		glass *= 1.0 - fade;
		// Glass reflects the sky: each pane tilted and rough by its own seed.
		rough = mix(0.9, 0.08 + 0.3 * h_win2, glass);
		spec = mix(0.3, 0.4, glass);
		NORMAL = normalize(n + glass * 0.06 * (t * (h_win - 0.5) + bt * (h_win2 - 0.5)));
		// Occlusion: the foot of the wall, and the street in front: the sky hidden up to the facing building's top.
		float y = UV.y;
		float block = atan(max(v_street.x - y, 0.0), max(v_street.y, 0.5));
		ao = mix(1.0, 0.35, sin(block) * (1.0 - fade)) * mix(0.55, 1.0, smoothstep(0.0, 3.0, y));
		ao *= mix(0.8, 1.0, fade) * (1.0 - 0.5 * recess * (1.0 - fade));
		albedo *= mix(0.7, 1.0, smoothstep(0.0, 1.2, y));
		if (night) {
			emit = vec3(1.0, 0.75, 0.45) * 0.6 * lit * (1.0 - damaged);
		}
	}
	albedo *= mix(1.0, 0.25, damaged);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = ao;
	EMISSION = emit;
	if (city_glow_k > 0.0) {
		EMISSION += city_glow_emission(ALBEDO);
	}
}
