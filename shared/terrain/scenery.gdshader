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
#include "res://shared/terrain/city_glow.gdshaderinc"

const float LEVEL_M = 3.0;
// The plaster the walls' colour lightens toward (sRGB), and how far.
const vec3 PLASTER = vec3(0.86, 0.83, 0.76);
const float PLASTER_MIX = 0.6;
const float BAY_M = 3.2;

varying flat float v_building;
varying flat float v_roof;
varying flat float v_wall;
varying float v_shade;

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
	VERTEX = g > 0.001 ? vec3(VERTEX.x, c.y + (VERTEX.y - c.y) * g, VERTEX.z) : c;
	v_city_glow = city_glow_at((MODEL_MATRIX * vec4(c, 1.0)).xz, d);  // at the building's centre
	v_building = UV2.x;
	v_roof = UV2.y < -0.5 ? 1.0 : 0.0;
	v_wall = floor(COLOR.a * 255.0 + 0.5);
	v_shade = wall_shade(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	int b = int(v_building + 0.5);
	float damaged = step(0.5 / 255.0, texelFetch(damage, ivec2(b % 256, b / 256), 0).r);
	vec3 photo = srgb_to_linear(COLOR.rgb);
	vec3 albedo;
	float rough = 0.9;
	float emit = 0.0;
	float ao = 1.0;
	if (v_roof > 0.5) {
		albedo = roof_far(photo, COLOR.a, hash(vec2(float(b), 7.7)));
	} else {
		int w = clamp(int(v_wall), 0, 3);
		// Photo: the photo's colour lightened toward plaster; Palette: the building's own (as Detailed).
		vec3 base = palette_colours ? wall_lit(w, wall_colour(w, float(b), photo))
			: min(srgb_to_linear(mix(COLOR.rgb, PLASTER, PLASTER_MIX)) * WALL_GAIN, vec3(MAX_ALBEDO));
		if (has_walls) {
			base *= 2.0 * texture(walls, vec3(UV / wall_size[w], float(w))).rgb;
		}
		// Windows (not on corrugated sheds), faded out where a window is under ~2 pixels (no shimmer far away).
		vec2 g = vec2(UV.x / BAY_M, UV.y / LEVEL_M);
		vec2 f = fract(g);
		vec2 px = fwidth(g);
		float aa = max(px.x, px.y);
		float win = smoothstep(0.22 - aa, 0.22 + aa, f.x) * (1.0 - smoothstep(0.78 - aa, 0.78 + aa, f.x))
			* smoothstep(0.30 - aa, 0.30 + aa, f.y) * (1.0 - smoothstep(0.80 - aa, 0.80 + aa, f.y));
		win *= (w == 3 ? 0.0 : 1.0) * (1.0 - smoothstep(0.25, 0.5, aa));
		albedo = mix(base, vec3(0.03, 0.04, 0.05), win * 0.85);
		rough = mix(0.9, 0.15, win);
		// Ground AO: darker at the foot of the wall.
		albedo *= mix(0.55, 1.0, smoothstep(0.0, 2.5, UV.y));
		ao = v_shade;  // the side away from the sun darker
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
