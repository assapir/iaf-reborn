// Ours (Graphics → MORE "Night vision", docs/rendering.md §8): the 3D view through image-intensifier goggles of the
// mission's year (terrain_view.gd TUBES). Drawn on a canvas layer under the cockpit, so the panel stays as seen under
// the goggles. Modern IAF's F-16s (terrain_view.gd _goggles_frame): the tubes' round field only, where the 3D cockpit
// outside it stays as the naked eye sees it.
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
// Modern IAF: the scene's light (lux; terrain_view.gd scene_lux). The tube's photon noise follows it: grain_k at
// GRAIN_LUX, as 1 / √light (fewer photons, more scintillation), within the clamp's limits (inferred); < 0 (the 1998
// game, the F-35I's DAS video): the noise by the gain alone.
uniform float lux = -1.0;
const float GRAIN_LUX = 0.01;

// The picture's colour: the tubes' P43 phosphor green; the F-35I's DAS video grey (terrain_view.gd DAS_VIDEO).
uniform vec3 tint = vec3(0.42, 1.0, 0.36);
// The tube's brightness control in bright light (0 for the DAS's camera, which has none; inferred), and its dark edge.
uniform float protect = 0.6;
uniform float vignette = 0.7;
// The brightness curve's exponent: 0.5 (the square root) keeps the dim ground's detail beside the sky; the DAS's 1.0
// keeps the picture's contrast by day (inferred).
uniform float curve = 0.5;
// The tubes' round field (Modern IAF's F-16s): its radius (rad) around `field_axis` (camera space, the head's forward
// line); 0 = the whole view (the 1998 game's goggles, the F-35I's helmet). The camera's axis meets the screen at
// `field_centre` (UV), its focal length `field_focal` screen heights.
uniform float field = 0.0;
uniform vec3 field_axis = vec3(0.0, 0.0, -1.0);
uniform vec2 field_centre = vec2(0.5);
uniform float field_focal = 1.0;


// The view's light as the tubes see it (linear, through the photocathode's weights): the gain's mean, and the
// daylight wash-out where no scene lux is set.
float scene_light(vec3 avg) {
	return dot(avg, cathode);
}


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// The tubes' mean comes from what they see: the whole view, or the field around its centre (a mip about the
	// field's radius per texel).
	vec2 mean_at = vec2(0.5);
	float mean_lod = 12.0;
	float edge = 0.0;  // the place in the field: 0 its axis, 1 its rim
	float down = SCREEN_UV.y;  // 0 the picture's top, 1 its bottom (the glare's veil)
	if (field > 0.0) {
		vec3 ray = normalize(vec3((SCREEN_UV - field_centre) * vec2(aspect, -1.0) / field_focal, -1.0));
		edge = acos(clamp(dot(ray, field_axis), -1.0, 1.0)) / field;
		down = 0.5 - 0.5 * (asin(ray.y) - asin(field_axis.y)) / field;
		mean_at = field_centre - vec2(0.0, field_axis.y / -field_axis.z * field_focal);
		mean_lod = log2(tan(field) * field_focal / SCREEN_PIXEL_SIZE.y);
	}
	if (edge >= 1.0) {
		COLOR = textureLod(screen, SCREEN_UV, 0.0);  // outside the field: the naked eye's view
	} else {
		// On the square root of the brightness: the dim ground keeps its detail beside the sky (inferred).
		vec3 avg = textureLod(screen, mean_at, mean_lod).rgb;
		float light = scene_light(avg);
		float mean = pow(light, curve) + glare;
		float gain = clamp(target / max(mean, 1e-3), 1.0, max_gain);
		float l = pow(dot(textureLod(screen, SCREEN_UV, blur).rgb, cathode), curve) * gain;
		// Halos: a light far brighter than the scene blooms into a disc around itself.
		float halo = 0.0;
		for (float lod = 2.0; lod <= 5.0; lod += 1.0) {
			halo += max(pow(dot(textureLod(screen, SCREEN_UV, lod).rgb, cathode), curve) * gain - 0.9, 0.0);
		}
		l += halo_k * halo;
		// Scintillation: the more gain, the more grain (photon noise), changing every frame.
		float grain = hash(floor(FRAGCOORD.xy) + fract(TIME * 61.0) * 917.0) - 0.5;
		float noise = lux < 0.0 ? sqrt(gain / 2.0) : clamp(sqrt(GRAIN_LUX / max(lux, 1e-4)), 0.3, 3.0);
		l += grain * grain_k * noise;
		l += glare * gain * smoothstep(0.3, 1.0, down);
		// The bright end saturates softly; the tube's edge darkens.
		l = 1.0 - exp(-1.6 * max(l, 0.0));
		// Bright light (daylight, a close blast): the brightness control holds the screen at its top brightness and the
		// picture loses detail, so it washes out to a bright, soft, low-contrast green (rendering.md §8.3; limits
		// inferred). ponytail: no hold time, the picture comes back as soon as the light goes; a CPU-side timer if it
		// should linger.
		// Modern IAF reads the scene's lux (none from 10 lux, deep in civil twilight, all from 400 lux, sunset); the 1998
		// game and lux < 0 the view's light through the tube (0.35 to 0.6).
		float bright = lux < 0.0 ? smoothstep(0.35, 0.6, light) : smoothstep(1.0, 2.6, log(max(lux, 1e-4)) / log(10.0));
		float wash = protect * bright;
		float soft = 1.0 - exp(-1.6 * pow(scene_light(textureLod(screen, SCREEN_UV, 3.0).rgb), curve));
		l = mix(l, 0.8 + 0.2 * soft, wash);
		if (field > 0.0) {
			// The field's rim darkens, then the naked eye's view around it (inferred).
			l *= 1.0 - vignette * smoothstep(0.8, 1.0, edge);
			COLOR = mix(vec4(tint * l, 1.0), textureLod(screen, SCREEN_UV, 0.0), smoothstep(0.98, 1.0, edge));
		} else {
			vec2 d = SCREEN_UV - 0.5;
			l *= 1.0 - vignette * smoothstep(0.4, 0.85, length(d * vec2(aspect, 1.0)));
			COLOR = vec4(tint * l, 1.0);
		}
	}
}
