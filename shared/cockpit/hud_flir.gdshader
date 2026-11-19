// Ours, Modern IAF's F-16s: the navigation pod's FLIR picture on the HUD (shared/weapons/nav_pod.gd; modern-iaf/docs/
// weapons.md §7.4), drawn under the HUD's symbols in the HUD's green and inside the combiner glass
// (hud_glass.gdshaderinc). The heat is inferred from the view: the brightness, the sky's and the water's blue cold, the
// local contrast lifted as an infrared camera's automatic gain does; then the FLIR format's polarity, gain and level.
// `shift` (screen UV) is snap-look's and look-into-turn's: the picture of the ground beside the view.
shader_type canvas_item;

#include "res://shared/cockpit/hud_glass.gdshaderinc"

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float gain = 1.0;
uniform float level = 0.0;
uniform bool black_hot = false;
uniform vec2 shift = vec2(0.0);
// The picture's strength over the scene (the HUD's brightness).
uniform float strength = 0.8;
uniform vec3 colour : source_color = vec3(0.42, 1.0, 0.36);

float heat(vec3 c) {
	float cold = smoothstep(0.03, 0.2, c.b - max(c.r, c.g));
	return dot(c, vec3(0.3, 0.59, 0.11)) * (1.0 - 0.85 * cold);
}

void fragment() {
	if (!on_glass(SCREEN_UV)) {
		discard;
	}
	vec2 uv = clamp(SCREEN_UV + shift, vec2(0.0), vec2(1.0));
	float t = heat(textureLod(screen, uv, 0.0).rgb);
	float m = heat(textureLod(screen, uv, 5.0).rgb);
	t = 0.3 + 4.0 * (t - m) + 0.6 * (m - 0.35);
	t = clamp((t - level) * gain + 0.5 * (1.0 - gain), 0.0, 1.0);
	if (black_hot) {
		t = 1.0 - t;
	}
	COLOR = vec4(colour, t * strength);
}
