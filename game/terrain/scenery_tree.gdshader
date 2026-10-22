// Scenery trees (terrain/scenery.gd, docs/scenery.md §3): MultiMesh instances in 500 m tiles. Each tree picks its
// model and grows in by its own distance, not its tile's: the full model (`far_model` false) to `near_m`, the light
// one beyond, both shrunk to nothing over the last `grow_m` before `far_m`. No transparency.
shader_type spatial;
render_mode cull_back;

uniform vec3 albedo : source_color;
uniform bool far_model = false;
uniform float near_m = 700.0;
uniform float far_m = 2000.0;
uniform float grow_m = 300.0;

void vertex() {
	// MODEL_MATRIX holds the instance's transform: its origin is the tree's foot.
	float d = distance(MODEL_MATRIX[3].xyz, INV_VIEW_MATRIX[3].xyz);
	float s = 1.0 - smoothstep(far_m - grow_m, far_m, d);
	s *= far_model ? step(near_m, d) : 1.0 - step(near_m, d);
	VERTEX *= s;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
