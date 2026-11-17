// The 3D cockpit at the window's resolution while the 3D view is upscaled (Upscaling Quality / Balanced; cockpit_origin.gd,
// docs/cockpit.md "Cockpit at the origin"). The composite (cockpit_composite.gdshader) still lays the cockpit into the
// 3D view: the flight's auto exposure counts it there, and the view is then upscaled, the cockpit's labels with it. On a
// canvas layer under every other one, this shader lays the cockpit's own picture (native size, linear, premultiplied)
// over that, through a stand-in of the flight's tone map (AgX) at the flight's exposure of this frame. The exposure is
// measured: the composite draws a grey of known light (PROBE_L) in the view's top left corner (PROBE_PX pixels of the 3D
// scene), and the exposure that gives the grey seen there through the stand-in is read from a table (cockpit_origin.gd
// exposure_lut). The corner itself
// is filled with the view's colour next to it.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform sampler2D cockpit : filter_nearest;
// The 3D scene's scale (Viewport.scaling_3d_scale): the probe's size in the window's pixels.
uniform float scale = 1.0;
// The flight's adjustments after the tone map (Environment adjustment_*): brightness, contrast, saturation; off: 1, 1, 1.
uniform vec3 bcs = vec3(1.0);
// The exposure by the probe's grey as seen (cockpit_origin.gd exposure_lut: this tone map inverted for PROBE_L).
uniform sampler2D exposure_lut : filter_linear, repeat_disable;

// The probe's size (3D pixels), as cockpit_composite.gdshader draws it.
const float PROBE_PX = 4.0;
// The corner the probe changes (window pixels): the probe and the upscaler's ringing about it.
const float FILL = 12.0;

// A minimal AgX (Troy Sobotka's; the polynomial fit by Benjamin Wrensch), its output taken as gamma 2.2 and encoded as
// sRGB, then the adjustments: linear Rec. 709 -> display. A stand-in for the flight's tone map, fitted 2026-11-17 to 400
// cockpit pixels of a day render with Upscaling off: 0.015 rms.
vec3 tonemap(vec3 c) {
	const mat3 inset = mat3(
		vec3(0.842479062253094, 0.0423282422610123, 0.0423756549057051),
		vec3(0.0784335999999992, 0.878468636469772, 0.0784336),
		vec3(0.0792237451477643, 0.0791661274605434, 0.879142973793104));
	const mat3 outset = mat3(
		vec3(1.19687900512017, -0.0528968517574562, -0.0529716355144438),
		vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241),
		vec3(-0.0990297440797205, -0.0989611768448433, 1.15107367264116));
	const float lo = -12.47393;
	const float hi = 4.026069;
	vec3 x = clamp((log2(max(inset * c, vec3(1e-10))) - lo) / (hi - lo), 0.0, 1.0);
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	x = 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
	vec3 l = pow(clamp(outset * x, 0.0, 1.0), vec3(2.2));
	vec3 s = mix(12.92 * l, 1.055 * pow(l, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, l));
	s = mix(vec3(0.5), s * bcs.x, bcs.y);
	return mix(vec3(dot(s, vec3(1.0 / 3.0))), s, bcs.z);
}

void fragment() {
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec4 c = textureLod(cockpit, SCREEN_UV, 0.0);
	bool corner = px.x < FILL && px.y < FILL;
	if (c.a < 0.004 && !corner) {
		discard;  // the world: the view as it is
	}
	float seen = textureLod(screen, vec2(0.5 * PROBE_PX / scale) * SCREEN_PIXEL_SIZE, 0.0).g;
	float n = float(textureSize(exposure_lut, 0).x);
	float e = textureLod(exposure_lut, vec2((seen * (n - 1.0) + 0.5) / n, 0.5), 0.0).r;
	vec3 sharp = c.a > 0.0 ? tonemap(e * c.rgb / c.a) : vec3(0.0);
	if (corner) {
		vec3 next = textureLod(screen, vec2(FILL + 0.5) * SCREEN_PIXEL_SIZE, 0.0).rgb;
		COLOR = vec4(mix(next, sharp, c.a), 1.0);
	} else {
		COLOR = vec4(sharp, c.a);
	}
}
