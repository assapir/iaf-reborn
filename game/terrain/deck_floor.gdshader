// The rain's cloud deck seen from above (ours, Graphics → MORE "Rain"; docs/rendering.md §10.1, terrain/weather.gd):
// a flat opaque floor at the deck's top that hides the ground under it. Its lumps are the original's overcast cloud
// texture (Cloud256_5) read as a height field at three scales, no finer than its mip level 2 (the original's 256
// texels, docs/rendering.md §2): their slopes shade it by the scene's sun and ambient, so the time of day lights it
// (white by day, gold at sunset, dark at night) and the scene's fog fades it into the horizon.
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
// The deck's drift with the wind (m, scene x / z).
uniform vec2 drift = vec2(0.0);
// The three scales (m per texture), their weights, and the slopes' strength.
const vec3 SCALE = vec3(9000.0, 2200.0, 600.0);
const vec3 WEIGHT = vec3(0.45, 0.35, 0.2);
const float BUMP = 0.12;
// The sunlight on a cloud top: much of it scatters back up whatever the slope (wrap), the rest by the slope; GAIN
// against a Lambert surface of albedo 1 (a cloud top scatters more back toward the sky; tuned to the volumetric deck).
const float WRAP = 0.6;
const float GAIN = 1.5;

varying vec3 wp;

float sample_h(vec2 uv) {
	return textureLod(tex, uv, max(textureQueryLod(tex, uv).y, 2.0)).a;
}

float height(vec2 p) {
	return WEIGHT.x * sample_h(p / SCALE.x) + WEIGHT.y * sample_h(p / SCALE.y + vec2(0.37, 0.71))
			+ WEIGHT.z * sample_h(p / SCALE.z + vec2(0.13, 0.52));
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz - drift;
	// The slope from two more taps a step apart (m); the step grows with the distance, so far away the floor is smooth.
	float e = max(40.0, 0.01 * length(wp - CAMERA_POSITION_WORLD));
	float h = height(p);
	float hx = height(p + vec2(e, 0.0));
	float hz = height(p + vec2(0.0, e));
	// The height field as metres of relief: BUMP × the smallest scale per unit.
	float k = BUMP * SCALE.z / e;
	vec3 n = normalize(vec3((h - hx) * k * 10.0, 1.0, (h - hz) * k * 10.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// The dips between the lumps hold less light (darker, a touch bluer).
	ALBEDO = mix(vec3(0.55, 0.58, 0.64), vec3(1.0), smoothstep(0.3, 0.62, h));
	ROUGHNESS = 1.0;
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + WRAP) / (1.0 + WRAP), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap * GAIN / PI;
}
