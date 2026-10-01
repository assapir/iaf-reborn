// The lens ADI ball ([LENHORIZON], docs/cockpit.md "Attitude indicators"): the lookup FUN_00532fc0 and the
// sampler FUN_00532ad4 / FUN_005276f0 mode 1, per pixel of the 2R x 2R square (continuous instead of per original
// pixel, so it stays smooth at any window size). The 128 x 128 ball bitmap wraps vertically: its 128 rows are 360°
// of pitch, the horizon at row 62.
shader_type canvas_item;

uniform sampler2D ball : repeat_enable, filter_linear;
uniform float radius = 34.0; // [LENHORIZON] Radius, original px
uniform float factor = 15.0; // [LENHORIZON] Factor: the lens depth
uniform float roll = 0.0; // rad
uniform float pitch = 0.0; // deg

void fragment() {
	vec2 p = UV * 2.0 * radius - radius;
	float d = dot(p, p) - radius * radius;
	// Outside the disc the table holds 2·(x, y) (hidden under the panel).
	vec2 uv = 2.0 * p;
	if (d < 0.0) {
		float z = sqrt(factor * factor - d) + 1.0;
		uv = p + p * 2.0 * factor / (z + factor);
	}
	// sin / cos in 16-bit fixed point (· 32766) and >> 16: half scale.
	float k = 32766.0 / 65536.0;
	float s = sin(roll);
	float c = cos(roll);
	float col = (uv.x * c - uv.y * s) * k + 64.0;
	float row = (uv.y * c + uv.x * s) * k + 62.0 - mod(pitch, 360.0) / 360.0 * 128.0;
	COLOR = texture(ball, vec2(col, row) / 128.0);
}
