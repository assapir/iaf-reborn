// Ours (Graphics → MORE "Night vision", docs/rendering.md §8): the 3D view through image-intensifier goggles of the
// mission's year (terrain_view.gd TUBES). Drawn on a canvas layer under the cockpit, so the panel stays as seen under
// the goggles.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
// The tube's automatic gain control aims the mean image at this level, at most max_gain times brighter.
uniform float target = 0.55;
uniform float max_gain = 8.0;
// The tube (terrain_view.gd TUBES): the photocathode's weights for R, G, B, the grain at ×2 gain, the blur (screen
// mip level) and the halo's strength.
uniform vec3 cathode = vec3(0.6, 0.4, 0.0);
uniform float grain_k = 0.047;
uniform float blur = 0.0;
uniform float halo_k = 0.4;
// The cockpit's own light in the tubes where its lighting does not suit goggles (terrain_view.gd goggles_lit): it
// lowers the gain and veils the picture, most toward the panel below.
uniform float glare = 0.0;

// P43 phosphor green.
const vec3 PHOSPHOR = vec3(0.42, 1.0, 0.36);


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	// On the square root of the brightness: the dim ground keeps its detail beside the sky (inferred).
	vec3 avg = textureLod(screen, vec2(0.5), 12.0).rgb;
	float mean = sqrt(dot(avg, cathode)) + glare;
	float gain = clamp(target / max(mean, 1e-3), 1.0, max_gain);
	float l = sqrt(dot(textureLod(screen, SCREEN_UV, blur).rgb, cathode)) * gain;
	// Halos: a light far brighter than the scene blooms into a disc around itself.
	float halo = 0.0;
	for (float lod = 2.0; lod <= 5.0; lod += 1.0) {
		halo += max(sqrt(dot(textureLod(screen, SCREEN_UV, lod).rgb, cathode)) * gain - 0.9, 0.0);
	}
	l += halo_k * halo;
	// Scintillation: the more gain, the more grain (photon noise), changing every frame.
	float grain = hash(floor(FRAGCOORD.xy) + fract(TIME * 61.0) * 917.0) - 0.5;
	l += grain * grain_k * sqrt(gain / 2.0);
	l += glare * gain * smoothstep(0.3, 1.0, SCREEN_UV.y);
	// The bright end saturates softly; the tube's edge darkens.
	l = 1.0 - exp(-1.6 * max(l, 0.0));
	// Bright-source protection: a view full of light (a close blast, daylight) darkens the tube (inferred limits).
	// ponytail: no hold time, the picture comes back as soon as the light goes; a CPU-side timer if it should linger.
	l *= 1.0 - 0.9 * smoothstep(0.35, 0.6, dot(avg, cathode));
	vec2 d = SCREEN_UV - 0.5;
	l *= 1.0 - 0.7 * smoothstep(0.4, 0.85, length(d * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0)));
	COLOR = vec4(PHOSPHOR * l, 1.0);
}
