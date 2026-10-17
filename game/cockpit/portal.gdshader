// Ours (the F-35I's panoramic display, pcd.gd): an MFD page drawn as a portal. The original pages' black becomes the
// display's dark blue and their pure green the display's softer green; other colours (the map, the ADI) stay.
shader_type canvas_item;

uniform vec3 background = vec3(0.020, 0.035, 0.095);
uniform vec3 green = vec3(0.35, 1.0, 0.42);

void fragment() {
	vec4 c = COLOR;
	float lit = max(c.r, max(c.g, c.b));
	// Pure greens (r, b near 0) take the display's green at their brightness.
	float pure = smoothstep(0.25, 0.05, max(c.r, c.b) / max(c.g, 0.001));
	c.rgb = mix(c.rgb, green * c.g, pure);
	c.rgb += background * (1.0 - lit);
	COLOR = c;
}
