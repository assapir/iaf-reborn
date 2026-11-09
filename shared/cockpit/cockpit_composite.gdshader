// The cockpit's own world (cockpit_origin.gd), drawn at the origin into a linear, untonemapped picture with its alpha,
// laid over the flight's 3D view as its last transparent thing: after the terrain, the models, the clouds, the rain and
// the effects, which all lie outside the canopy. In the 3D pass, so the flight's exposure (the auto exposure, which
// counts the cockpit's pixels again), its tonemap and its anti-aliasing apply to the cockpit as when it hung in the
// flight's world. The picture's colours are premultiplied by their alpha (an alpha blend over a transparent ground).
shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, blend_premul_alpha, cull_disabled, shadows_disabled;

uniform sampler2D cockpit : filter_linear;

void vertex() {
	// A full-screen quad (QuadMesh 1 × 1), never culled (extra_cull_margin).
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

void fragment() {
	vec4 c = textureLod(cockpit, SCREEN_UV, 0.0);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
