// Scenery trees with the foliage textures, the far model (terrain/scenery.gd, docs/scenery.md §3.2): the plain
// low-poly canopy, solid (cut-out cards over a whole forest cost too much to fill), in the full model's leaf colour and
// each tree's own shade (the same hash as scenery_foliage.gdshader), darker below. Drawn by each tree's own distance
// from `near_m` - `band_m` (under the full model fading out) to `far_m`, shrinking to nothing over the last `grow_m`.
shader_type spatial;
render_mode cull_back;

uniform vec3 albedo = vec3(0.1, 0.13, 0.06);
uniform float near_m = 450.0;
uniform float band_m = 50.0;
uniform float far_m = 2000.0;
uniform float grow_m = 300.0;
// The full model's mean brightness: its leaf texture's visible leaves and its occlusion.
const float GAIN = 0.9;

varying vec3 v_colour;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 foot = MODEL_MATRIX[3].xyz;
	float d = distance(foot, INV_VIEW_MATRIX[3].xyz);
	float seed = hash(foot.xz);
	float b = 0.82 + 0.36 * seed;
	float h = hash(foot.zx + 17.0) - 0.5;
	// Darker toward the underside, as the full model's occlusion.
	float ao = mix(0.55, 1.0, smoothstep(-0.8, 0.8, NORMAL.y));
	v_colour = albedo * GAIN * b * vec3(1.0 + 0.25 * h, 1.0, 1.0 - 0.3 * h) * ao;
	float s = 1.0 - smoothstep(far_m - grow_m, far_m, d);
	VERTEX *= d < near_m - band_m ? 0.0 : s;
}

void fragment() {
	ALBEDO = v_colour;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
