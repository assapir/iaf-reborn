// The turning compass card (compass.gd, docs/cockpit.md "Turning compass / HSI"): the card disc of the panel art
// turned by `angle` (the heading, clockwise), so the heading's mark sits at the top. Inside `hub` (a share of the
// radius) the panel's own art shows through; the edges blend over about one pixel.
shader_type canvas_item;

uniform float angle = 0.0; // rad
uniform float hub = 0.0; // inner radius / outer radius

// The vertex colour (the modulate: the night darkening); fragment's COLOR comes already multiplied by the texture.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float w = fwidth(r);
	float a = (1.0 - smoothstep(1.0 - w, 1.0, r)) * (hub > 0.0 ? smoothstep(hub, hub + w, r) : 1.0);
	if (a <= 0.0) {
		discard;
	}
	float c = cos(angle);
	float s = sin(angle);
	vec2 q = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	// Mipmaps against shimmer while it turns, one level sharper to match the still panel (drawn without mipmaps).
	vec4 col = texture(TEXTURE, q * 0.5 + 0.5, -1.0) * tint;
	COLOR = vec4(col.rgb, col.a * a);
}
