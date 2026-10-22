// Scenery buildings (terrain/scenery.gd, docs/scenery.md §3). The mesh arrays come from IafScenery:
//   UV   = wall coordinates in metres (x along the wall, y above the building's base);
//   UV2  = (building index in the cell, 0 = wall / 1 = roof);
//   COLOR.rgb = the roof colour on the active Survey 2 m look (sRGB), COLOR.a = the wall material / 255
//   (iaf_tools::thirdparty::SCENERY order: plaster, stone, concrete, corrugated steel).
// Walls: the ambientCG colour detail (colour over its mean) on the material's mean colour, tinted by the roof colour;
// our window mask (a row per 3 m level, a column every 3.2 m); a ground AO gradient. Damaged buildings: sooted.
shader_type spatial;
render_mode cull_back;

uniform sampler2DArray walls : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_walls = false;
// The four materials' mean colours (linear).
uniform vec4 wall_mean[4];
// The repeat of each material's texture (m).
uniform vec4 wall_size = vec4(2.0, 2.0, 1.1, 2.0);
// A byte per building, 256 per row: 0 = intact.
uniform sampler2D damage : filter_nearest;
// Detailed night lights at night: some windows lit.
uniform bool night = false;

const float LEVEL_M = 3.0;
const float BAY_M = 3.2;

varying flat float v_building;
varying flat float v_roof;
varying flat float v_wall;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	v_building = UV2.x;
	v_roof = UV2.y;
	v_wall = floor(COLOR.a * 255.0 + 0.5);
}

void fragment() {
	int b = int(v_building + 0.5);
	float dmg = texelFetch(damage, ivec2(b % 256, b / 256), 0).r;
	vec3 roof = srgb_to_linear(COLOR.rgb);
	vec3 albedo;
	float rough = 0.9;
	float emit = 0.0;
	if (v_roof > 0.5) {
		albedo = roof;
	} else {
		int w = clamp(int(v_wall), 0, 3);
		vec3 base = mix(wall_mean[w].rgb, roof, 0.3);
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
		if (night && win > 0.0) {
			float lit = step(hash(floor(g) + vec2(float(b) * 0.37, 0.0)), 0.12);
			emit = lit * win * (1.0 - dmg);
		}
	}
	albedo *= mix(1.0, 0.25, step(0.5 / 255.0, dmg));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	EMISSION = emit * vec3(1.0, 0.75, 0.45) * 0.6;
}
