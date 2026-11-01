// The rain's cloud deck seen from above (ours, Graphics → MORE "Rain"; docs/rendering.md §10.1, terrain/weather.gd):
// a flat opaque floor at the deck's top that hides the ground under it. Its lumps are the original's overcast cloud
// texture (Cloud256_5) read at three scales, no finer than its mip level 2 (the original's 256 texels,
// docs/rendering.md §2): the largest as broad swells, the two smaller folded about the art's mean into cells (rounded
// lumps with soft troughs along the mean's contours, as stratocumulus tops). Their slopes shade it by the scene's sun
// and ambient, so the time of day lights it (white by day, gold at sunset, dark at night) and the scene's fog fades it
// into the horizon; the troughs hold less light (darker, a touch bluer).
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
// The deck's drift with the wind (m, scene x / z).
uniform vec2 drift = vec2(0.0);
// The three scales (m per texture), their weights in the height, and the slopes' strength.
const vec3 SCALE = vec3(9000.0, 2200.0, 600.0);
const vec3 WEIGHT = vec3(0.3, 0.45, 0.25);
const float BUMP = 0.1;
// The art's mean alpha (Cloud256_5: 0.73, sd 0.135): the cells' troughs lie on its contour; FOLD scales the distance
// from it to the cell's height 0..1.
const float MEAN = 0.73;
const float FOLD = 2.5;
// The sunlight on a cloud top: much of it scatters back up whatever the slope (wrap), the rest by the slope; GAIN
// against a Lambert surface of albedo 1 (a cloud top scatters more back toward the sky; tuned to the volumetric deck).
const float WRAP = 0.55;
const float GAIN = 1.5;

varying vec3 wp;

// The art's alpha at level `lo` or coarser through four bilinear taps half a texel apart (a quadratic B-spline, as the
// 1998 layer's smoothing, §2). Its ARGB4444 alpha has 16 levels, flat terraces with steps between them: the cells'
// fold and the slopes read it coarser (LOD), where the terraces have blurred into slopes.
const vec2 LOD = vec2(3.5, 4.5);
float sample_h(vec2 uv, float lo) {
	float lod = max(textureQueryLod(tex, uv).y, lo);
	float h = 0.5 * exp2(lod) / float(textureSize(tex, 0).x);
	return 0.25 * (textureLod(tex, uv + vec2(h, h), lod).a + textureLod(tex, uv + vec2(-h, h), lod).a
			+ textureLod(tex, uv + vec2(h, -h), lod).a + textureLod(tex, uv + vec2(-h, -h), lod).a);
}

// A cell's height 0..1 from the art's alpha: 0 on the mean's contour (a soft trough), rising to a rounded top.
float cell(float a) {
	float x = clamp(abs(a - MEAN) * FOLD, 0.0, 1.0);
	x = sqrt(x * x + 0.01) - 0.1;
	return 1.0 - (1.0 - x) * (1.0 - x);
}

// The height (x) and the cells' share without the swells (y).
vec2 height(vec2 p, float lo) {
	float swell = sample_h(p / SCALE.x, lo);
	float c1 = cell(sample_h(p / SCALE.y + vec2(0.37, 0.71), lo));
	float c2 = cell(sample_h(p / SCALE.z + vec2(0.13, 0.52), lo));
	float cells = (WEIGHT.y * c1 + WEIGHT.z * c2) / (WEIGHT.y + WEIGHT.z);
	return vec2(WEIGHT.x * swell + WEIGHT.y * c1 + WEIGHT.z * c2, cells);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz - drift;
	// The slope from two more taps a step apart (m); the step grows with the distance, so far away the floor is smooth.
	float e = max(40.0, 0.01 * length(wp - CAMERA_POSITION_WORLD));
	vec2 h = height(p, LOD.x);
	float h0 = height(p, LOD.y).x;
	float hx = height(p + vec2(e, 0.0), LOD.y).x;
	float hz = height(p + vec2(0.0, e), LOD.y).x;
	// The height field as metres of relief: BUMP × the smallest scale per unit.
	float k = BUMP * SCALE.z / e;
	vec3 n = normalize(vec3((h0 - hx) * k * 10.0, 1.0, (h0 - hz) * k * 10.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// The troughs between the cells hold less light (darker, a touch bluer).
	ALBEDO = mix(vec3(0.78, 0.8, 0.86), vec3(1.0), smoothstep(0.0, 0.8, h.y));
	ROUGHNESS = 1.0;
}

void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + WRAP) / (1.0 + WRAP), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap * GAIN / PI;
}
