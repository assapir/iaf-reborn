// Scenery trees with the foliage textures, the full model (terrain/scenery.gd, docs/scenery.md §3.2): MultiMesh
// instances in 500 m tiles. A tree is one surface: alpha-cut leaf cards round a solid core, and the trunk. The mesh's
// vertex colour:
//   r = ambient occlusion (dark at the crown's heart and underside), g = how far the wind moves it (0 at the foot),
//   b = 1 on the core (solid, the clump texture's gaps filled), a = 1 on the trunk (the bark layer, `trunk` colour).
// NORMAL is the crown's own round normal on the cards, so a crown is lit as one volume, not card by card.
// Each tree is drawn to `near_m` + `band_m` by its own distance, fading out over the band (a screen dither) above its
// far model (scenery_foliage_far.gdshader), which starts at `near_m` - `band_m`.
shader_type spatial;
render_mode cull_disabled;

// The layers (iaf_tools::foliage::LAYERS): broadleaf, conifer, palm, bark; colour over its mean, halved.
uniform sampler2DArray foliage : filter_linear_mipmap, repeat_enable;
uniform float layer = 0.0;
uniform vec3 albedo = vec3(0.1, 0.13, 0.06);
uniform vec3 trunk = vec3(0.1, 0.07, 0.05);
uniform float near_m = 450.0;
uniform float band_m = 50.0;

const float BARK = 3.0;

varying vec3 v_tint;
varying float v_fade;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// MODEL_MATRIX holds the instance's transform: its origin is the tree's foot.
	vec3 foot = MODEL_MATRIX[3].xyz;
	float d = distance(foot, INV_VIEW_MATRIX[3].xyz);
	float seed = hash(foot.xz);
	// Each tree its own shade and hue: ±18 % brightness, a little yellower or bluer (scenery_foliage_far.gdshader too).
	float b = 0.82 + 0.36 * seed;
	float h = hash(foot.zx + 17.0) - 0.5;
	v_tint = b * vec3(1.0 + 0.25 * h, 1.0, 1.0 - 0.3 * h);
	v_fade = clamp((d - (near_m - band_m)) / (2.0 * band_m), 0.0, 1.0);
	if (d > near_m + band_m) {
		VERTEX = vec3(0.0);  // not shown: no triangles to draw
	} else {
		// A gentle sway, the tips most.
		float t = TIME * 1.3 + seed * 6.283;
		VERTEX.xz += COLOR.g * 0.06 * vec2(sin(t), cos(t * 0.77));
	}
}

void fragment() {
	if (hash(floor(FRAGCOORD.xy)) < v_fade) {
		discard;  // fading out over the band
	}
	bool bark = COLOR.a > 0.5;
	vec4 t = texture(foliage, vec3(UV, bark ? BARK : layer));
	float ao = COLOR.r;
	vec3 base = bark ? trunk : albedo * v_tint;
	// The occlusion darkens the colour itself (sun and sky alike); Godot's AO, on the sky light only, made a crown a
	// dark blob under an overcast sky.
	ALBEDO = base * 2.0 * t.rgb * mix(0.55, 1.0, ao);
	ALPHA = max(t.a, max(COLOR.b, COLOR.a));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	// The crown's round normal on both faces of a card (the back face would get it flipped).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Matte: a leaf's sheen at grazing angles (Fresnel) rimmed every crown in sky blue.
	ROUGHNESS = 0.95;
	SPECULAR = COLOR.b > 0.5 ? 0.0 : 0.1;
	// Sun through the leaves.
	BACKLIGHT = bark ? vec3(0.0) : ALBEDO * 0.8 * ao;
}
