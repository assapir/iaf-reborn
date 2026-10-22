// Ours (Graphics → MORE "Night vision", docs/rendering.md §8): the 3D view through Gen III image-intensifier
// goggles. Drawn on a canvas layer under the cockpit, so the panel stays as seen under the goggles.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
// The tube's automatic brightness control aims the mean image at this level, at most max_gain times brighter.
uniform float target = 0.55;
uniform float max_gain = 8.0;

// The photocathode reaches into the red / near infrared: red counts more than for the eye.
const vec3 CATHODE = vec3(0.5, 0.35, 0.15);
// P43 phosphor green.
const vec3 PHOSPHOR = vec3(0.42, 1.0, 0.36);


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	// On the square root of the brightness: the dim ground keeps its detail beside the sky (inferred).
	float mean = sqrt(dot(textureLod(screen, vec2(0.5), 12.0).rgb, CATHODE));
	float gain = clamp(target / max(mean, 1e-3), 1.0, max_gain);
	float l = sqrt(dot(textureLod(screen, SCREEN_UV, 0.0).rgb, CATHODE)) * gain;
	// Halos: a light far brighter than the scene blooms into a disc around itself.
	float halo = 0.0;
	for (float lod = 2.0; lod <= 5.0; lod += 1.0) {
		halo += max(sqrt(dot(textureLod(screen, SCREEN_UV, lod).rgb, CATHODE)) * gain - 0.9, 0.0);
	}
	l += 0.5 * halo;
	// Scintillation: the more gain, the more grain (photon noise), changing every frame.
	float grain = hash(floor(FRAGCOORD.xy) + fract(TIME * 61.0) * 917.0) - 0.5;
	l += grain * 0.07 * sqrt(gain / 2.0);
	// The bright end saturates softly; the tube's edge darkens.
	l = 1.0 - exp(-1.6 * max(l, 0.0));
	vec2 d = SCREEN_UV - 0.5;
	l *= 1.0 - 0.9 * smoothstep(0.3, 0.75, length(d * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0)));
	COLOR = vec4(PHOSPHOR * l, 1.0);
}
