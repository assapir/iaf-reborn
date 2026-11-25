// Scenery buildings, Scenery = On (terrain/scenery.gd, docs/scenery.md §3; Detailed: scenery_detailed.gdshader). The
// mesh arrays come from IafScenery:
//   UV   = wall coordinates in metres (x along the wall, y above the building's base);
//   UV2  = (building index in the cell, the building's height on walls / −1 on roofs);
//   COLOR.rgb = the roof colour on the active Survey 2 m look (sRGB), lightened here toward plaster on walls;
//   COLOR.a = the wall material / 255 (iaf_tools::thirdparty::SCENERY_WALLS: plaster, stone, concrete, corrugated).
// The gains, the palette and the roofs' colour: scenery_palette.gdshaderinc (Building colours = Palette: the walls in
// Detailed's palette, the light flat and gabled roofs lifted out of the photo's grey).
// Walls: that colour times the ambientCG material's colour detail (its colour over its mean);
// our window mask (a row per 3 m level, a column every 3.2 m); a ground AO gradient. Damaged buildings: sooted.
// SCENERY_ORTHO (Modern IAF: Settings.scenery_ortho(); scenery.gd building_shader() compiles a copy with it): the
// roofs in the air photo's own colour (the footprint's median, iaf-sim scenery) with solar heaters, the walls by the
// colour of a 2 m ring around the footprint (COLOR.rgb on walls), ribbon windows, a parapet line, a sun / shade step and
// a darker street level (modern-iaf/docs/scenery.md §7, look study A20).
shader_type spatial;
// Lit per vertex: every face is flat (one normal), so the sun's light there is the light per pixel; the shadows stay
// per pixel. A near point light (a flash, a landing light) spreads over a wall's corners instead. 0.6 ms less over
// Tel Aviv on the Iris Xe (modern-iaf/docs/scenery.md §6).
render_mode cull_back, vertex_lighting;

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
// Beyond this distance a near flat roof's parapet is under 1.5 pixels tall (scenery.gd sets it from the camera):
// its inner faces are left out (their feet lifted to their tops: no triangle to draw).
uniform float parapet_m = 2500.0;
// A byte per building, 256 per row: 0 = intact.
uniform sampler2D damage : filter_nearest;
// Detailed night lights at night: some windows lit.
uniform bool night = false;
#include "res://shared/terrain/city_glow.gdshaderinc"

const float LEVEL_M = 3.0;
// The plaster the walls' colour lightens toward (sRGB), and how far.
const vec3 PLASTER = vec3(0.86, 0.83, 0.76);
const float PLASTER_MIX = 0.6;
const float BAY_M = 3.2;
const float PARAPET = 0.8;  // m, iaf_avionics::scenery::PARAPET

// The face's values, packed in three varyings (each varying takes a slot the GPU sets up per triangle; ten single ones
// cost 0.06 ms more over Tel Aviv, modern-iaf/docs/scenery.md §6). All are constant over a face, so flat.
// v_face: rgb = the face's colour before its texture and windows (linear; one per building and face kind, so made per
// vertex), a = a wall's shade by the sun.
varying flat vec4 v_face;
// v_kind: x = the building's index in the cell, y = 1 on a roof, z = the wall material, w = a wall's building height (m).
varying flat vec4 v_kind;
#ifdef SCENERY_ORTHO
// x = 1 on a flat roof, y = a wall: 1 facing the sun, 0 away (level).
varying flat vec2 v_ortho;
#endif

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

#include "res://shared/terrain/scenery_palette.gdshaderinc"

void vertex() {
	vec3 c = CUSTOM0.xyz;
	float d = distance((MODEL_MATRIX * vec4(c, 1.0)).xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	float g = far_model ? step(near_m, d) * (1.0 - smoothstep(far_m - grow_m, far_m, d)) : 1.0 - step(near_m, d);
	// Shown: raised to g of its height; not shown: collapsed to its centre (no triangles to draw).
	// A parapet's inner face: a wall vertex at the roof, the parapet's height under the building's top.
	if (!far_model && d > parapet_m && UV2.y > 0.0 && abs(UV.y - (UV2.y - PARAPET)) < 0.001) {
		VERTEX.y += PARAPET;
	}
	VERTEX = g > 0.001 ? vec3(VERTEX.x, c.y + (VERTEX.y - c.y) * g, VERTEX.z) : c;
	v_city_glow = city_glow_at((MODEL_MATRIX * vec4(c, 1.0)).xz, d);  // at the building's centre
	float v_building = UV2.x;
	float v_roof = UV2.y < -0.5 ? 1.0 : 0.0;
	float v_wall = floor(COLOR.a * 255.0 + 0.5);
	float v_shade = wall_shade(mat3(MODEL_MATRIX) * NORMAL);
	float fb = float(int(v_building + 0.5));
	vec3 photo = srgb_to_linear(COLOR.rgb);
	vec3 v_base;
	int w = clamp(int(v_wall), 0, 3);
	// Photo: the photo's colour lightened toward plaster; Palette: the building's own (as Detailed).
#ifdef SCENERY_ORTHO
	float v_flat = v_roof > 0.5 && abs(COLOR.a - 0.5) > 0.1 && COLOR.a < 0.99 ? 1.0 : 0.0;
	vec3 nw = mat3(MODEL_MATRIX) * NORMAL;
	float sl = length(scenery_sun);
	float v_sunward = sl > 0.01 ? 0.5 + 0.5 * dot(normalize(vec3(nw.x, 0.0, nw.z) + 1e-5), scenery_sun / sl) : 0.5;
	if (v_flat > 0.5) {
		// A flat roof: the air photo's median over its footprint, lit to an albedo (gabled: clay, roof_far).
		v_base = min(photo * 0.85, vec3(0.75));
	} else
#endif
	v_base = v_roof > 0.5 ? roof_far(photo, COLOR.a, hash(vec2(fb, 7.7)))
		: (palette_colours ? wall_lit(w, wall_colour(w, fb, photo))
			: min(srgb_to_linear(mix(COLOR.rgb, PLASTER, PLASTER_MIX)) * WALL_GAIN, vec3(MAX_ALBEDO)));
	v_face = vec4(v_base, v_shade);
	v_kind = vec4(v_building, v_roof, v_wall, UV2.y);
#ifdef SCENERY_ORTHO
	v_ortho = vec2(v_flat, v_sunward);
#endif
}

void fragment() {
	vec3 v_base = v_face.rgb;
	float v_roof = v_kind.y;
	int b = int(v_kind.x + 0.5);
	float damaged = step(0.5 / 255.0, texelFetch(damage, ivec2(b % 256, b / 256), 0).r);
	vec3 albedo;
	float rough = 0.9;
	float emit = 0.0;
	float ao = 1.0;
	if (v_roof > 0.5) {
		albedo = v_base;
#ifdef SCENERY_ORTHO
		if (v_ortho.x > 0.5) {
			// Solar water heaters: a dark panel (2.1 × 1.4 m) and its white tank in some 3.5 m cells, a density
			// per building; under ~2 pixels they fade to their mean.
			vec2 q = UV * 32.0 / 3.5;
			vec2 fq = fract(q);
			float on = step(hash(floor(q) + float(b) * 0.13), mix(0.15, 0.5, hash(vec2(float(b), 2.9))));
			float ra = max(fwidth(q).x, fwidth(q).y);
			// Under 0.6 cells a pixel: their means (a far roof), the shapes not worked out.
			float panel = 0.24;
			float tank = 0.042;
			if (ra < 0.6) {
				float k = smoothstep(0.3, 0.6, ra);
				panel = mix(step(0.15, fq.x) * step(fq.x, 0.75) * step(0.2, fq.y) * step(fq.y, 0.6), panel, k);
				tank = mix(step(0.78, fq.x) * step(fq.x, 0.92) * step(0.25, fq.y) * step(fq.y, 0.55), tank, k);
			}
			albedo = mix(albedo, vec3(0.03, 0.035, 0.05), on * panel * 0.9);
			albedo = mix(albedo, vec3(0.6), on * tank);
		}
#endif
	} else {
		int w = clamp(int(v_kind.z), 0, 3);
		vec3 base = v_base;
		if (has_walls) {
			base *= 2.0 * texture(walls, vec3(UV / wall_size[w], float(w))).rgb;
		}
		// Windows (not on corrugated sheds), faded out where a window is under ~2 pixels (no shimmer far away).
		vec2 g = vec2(UV.x / BAY_M, UV.y / LEVEL_M);
		vec2 f = fract(g);
		vec2 px = fwidth(g);
		float aa = max(px.x, px.y);
#ifdef SCENERY_ORTHO
		// Ribbon windows: each axis fades to its mean as it shrinks under ~2 pixels, the rows to a full-width band, so
		// far walls keep their window bands instead of turning flat.
		// Both axes under half a window's period a pixel (a far wall): their means, 0.5 × 0.85, worked out.
		float win = 0.425;
		if (min(px.x, px.y) < 0.5) {
			float wx = smoothstep(0.22 - px.x, 0.22 + px.x, f.x) * (1.0 - smoothstep(0.78 - px.x, 0.78 + px.x, f.x));
			float wy = smoothstep(0.30 - px.y, 0.30 + px.y, f.y) * (1.0 - smoothstep(0.80 - px.y, 0.80 + px.y, f.y));
			wx = mix(wx, 0.56, smoothstep(0.25, 0.5, px.x));
			wy = mix(wy, 0.5, smoothstep(0.25, 0.5, px.y));
			win = wy * mix(wx, 0.85, smoothstep(0.25, 0.5, px.x));
		}
		win *= w == 3 ? 0.0 : 1.0;
		albedo = mix(base, vec3(0.02, 0.025, 0.035), win * 0.9);
		rough = mix(0.9, 0.15, win * (1.0 - smoothstep(0.25, 0.5, aa)));
		// The parapet line: the top 0.5 m of every wall (outer and the parapet's inner face) dark.
		float top = v_kind.w - UV.y;
		float tw = fwidth(UV.y);
		float line = 1.0 - smoothstep(0.5 - tw, 0.5 + tw, top);
		line = mix(line, 0.5 * (1.0 - smoothstep(0.0, 2.0, top)), smoothstep(0.3, 0.6, tw));
		albedo *= 1.0 - 0.55 * line * (w == 3 ? 0.0 : 1.0);
#else
		float win = smoothstep(0.22 - aa, 0.22 + aa, f.x) * (1.0 - smoothstep(0.78 - aa, 0.78 + aa, f.x))
			* smoothstep(0.30 - aa, 0.30 + aa, f.y) * (1.0 - smoothstep(0.80 - aa, 0.80 + aa, f.y));
		win *= (w == 3 ? 0.0 : 1.0) * (1.0 - smoothstep(0.25, 0.5, aa));
		albedo = mix(base, vec3(0.03, 0.04, 0.05), win * 0.85);
		rough = mix(0.9, 0.15, win);
#endif
		// Ground AO: darker at the foot of the wall.
		albedo *= mix(0.55, 1.0, smoothstep(0.0, 2.5, UV.y));
		ao = v_face.a;  // the side away from the sun darker
#ifdef SCENERY_ORTHO
		// The sun's side lit warm at full albedo, the side away a real step darker.
		albedo *= mix(vec3(0.55), vec3(1.06, 1.0, 0.9), smoothstep(0.25, 0.75, v_ortho.y));
		// The street's sky light: the lower floors see less sky between close buildings (a canyon term on the ambient
		// only, no neighbour lookup: inferred, every wall the same), and the street level a shade darker.
		ao *= mix(0.45, 1.0, smoothstep(0.0, 12.0, UV.y));
		albedo *= mix(0.7, 1.0, smoothstep(0.0, 10.0, UV.y));
#endif
		if (night && win > 0.0) {
			float lit = step(hash(floor(g) + vec2(float(b) * 0.37, 0.0)), 0.12);
			emit = lit * win * (1.0 - damaged);
		}
	}
	albedo *= mix(1.0, 0.25, damaged);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	AO = ao;
	EMISSION = emit * vec3(1.0, 0.75, 0.45) * 0.6;
	if (city_glow_k > 0.0) {
		EMISSION += city_glow_emission(ALBEDO);
	}
}
