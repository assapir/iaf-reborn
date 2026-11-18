// The sharp layer's exposure grey as solid geometry (cockpit_origin.gd; cockpit_sharp.gdshader reads it): PROBE_PX
// pixels of the 3D scene square in the view's top left corner, at the near plane, standing still on the screen. Being
// opaque it writes the corner's depth and motion vectors (none), so a temporal upscaler (MetalFX temporal, FSR 2, TAA)
// keeps the corner's own history. The grey the composite draws alone (cockpit_composite.gdshader, a transparent quad)
// has the depth and motion of the world behind it: while the head turned, MetalFX temporal mixed the sky's history
// into it and the sharp layer read a wrong exposure (the white flashes of 17 Nov, docs/rendering.md §3.2).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

// As cockpit_composite.gdshader.
const float PROBE_L = 0.18;
const float PROBE_PX = 8.0;

void vertex() {
	// QuadMesh 1 × 1 -> the corner's square in clip space (y down), never culled (extra_cull_margin).
	vec2 size = 2.0 * PROBE_PX / VIEWPORT_SIZE;
	POSITION = vec4((VERTEX.xy + 0.5) * size - 1.0, 1.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(PROBE_L);
}
