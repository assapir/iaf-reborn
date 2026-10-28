// Scenery roof clutter (terrain/scenery.gd roof_mesh, docs/scenery.md §3.3): solar water heaters, water tanks, stair
// heads and AC units on the flat roofs, MultiMesh instances in 500 m tiles. Each shrinks onto its roof by its own
// distance over the last `grow_m` before `far_m`. COLOR = the vertex colour times the instance's (linear albedo);
// its alpha 0 marks the collectors' glass.
shader_type spatial;
// Two-sided: the models' winding is not relied on, a back face turns its normal to the eye.
render_mode cull_disabled;

uniform float far_m = 700.0;
uniform float grow_m = 150.0;

void vertex() {
	// MODEL_MATRIX holds the instance's transform: its origin is the item's foot on the roof.
	float d = distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz);
	VERTEX *= 1.0 - smoothstep(far_m - grow_m, far_m, d);
}

void fragment() {
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(0.7, 0.85, COLOR.a);
	SPECULAR = mix(0.12, 0.2, COLOR.a);
}
