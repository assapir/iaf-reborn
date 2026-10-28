// Scenery roof clutter (terrain/scenery.gd roof_mesh, docs/scenery.md §3.3): solar water heaters, water tanks, stair
// heads and AC units on the flat roofs, MultiMesh instances in 500 m tiles. Each shrinks onto its roof by its own
// distance over the last `grow_m` before `far_m`. COLOR = the vertex colour times the instance's (sRGB); its alpha
// picks the material: 0 the collectors' glass, 0.25 galvanised steel, 0.5 the shade under an item, 1 paint.
// Paint takes the walls' light (roughness 0.9, specular 0.3); every item is darker and occluded at its foot.
shader_type spatial;
// Two-sided: the models' winding is not relied on, a back face turns its normal to the eye.
render_mode cull_disabled;

uniform float far_m = 700.0;
uniform float grow_m = 150.0;

// Height above the item's foot (m).
varying float v_up;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	// MODEL_MATRIX holds the instance's transform: its origin is the item's foot on the roof.
	float d = distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz);
	VERTEX *= 1.0 - smoothstep(far_m - grow_m, far_m, d);
	v_up = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
}

void fragment() {
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	float m = COLOR.a;
	float foot = smoothstep(0.0, 0.5, v_up);
	vec3 albedo = srgb_to_linear(COLOR.rgb) * mix(0.7, 1.0, foot);
	float rough = 0.9;
	float spec = 0.3;
	float metal = 0.0;
	if (m < 0.1) {
		// Collector glass over a black absorber: dark blue-black, a glint at a low angle.
		albedo = vec3(0.012, 0.016, 0.03);
		rough = 0.45;
		spec = 0.12;
	} else if (m < 0.4) {
		metal = 0.55;
		rough = 0.5;
	} else if (m < 0.75) {
		albedo = vec3(0.03, 0.03, 0.028);
		rough = 1.0;
		spec = 0.0;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	AO = mix(0.45, 1.0, foot);
}
