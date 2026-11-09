// The buildings' colours, shared by scenery.gdshader (On) and scenery_detailed.gdshader (Detailed); docs/scenery.md
// §3.4. Include after hash() and srgb_to_linear().
// The photo's colour already holds the sun's light, and the scene lights it again: roofs take ROOF_GAIN of it, walls
// WALL_GAIN, both at most MAX_ALBEDO (linear), so a town reads as bright as the photo under it, not white.
// palette_colours (Building colours = Palette, Settings.building_palette): every wall keeps its own palette colour at
// any distance, plaster, stone and concrete warmed CREAM_MIX toward CREAM and lit at PALETTE_GAIN up to PALETTE_MAX
// (a low sun lights them cream, as the Epic Fury reference's towns: iaf-2026/docs/scenery.md §7), and the far
// roofs take the near roof's material: the white coating on a light flat roof, clay on a gabled one (alpha
// iaf_avionics::scenery::GABLED, the far mesh too). Off (Photo): the walls fade to the photo's colour far away.
uniform bool palette_colours = false;

const float ROOF_GAIN = 0.6;
const float WALL_GAIN = 0.5;
const float MAX_ALBEDO = 0.45;
const float PALETTE_GAIN = 0.7;
const float PALETTE_MAX = 0.7;
const vec3 CREAM = vec3(0.85, 0.69, 0.48);  // sRGB (0.93, 0.85, 0.72)
const float CREAM_MIX = 0.5;
// The near roofs' average materials (linear; scenery_detailed.gdshader): clay tiles, the white coating worn in patches.
const vec3 CLAY = vec3(0.28, 0.11, 0.06);
const vec3 COATING = vec3(0.36, 0.36, 0.345);

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// A building's wall colour (sRGB): Jerusalem stone, white / beige / pale plaster, grey concrete blocks.
vec3 palette(int w, float h) {
	if (w == 1) {
		return h < 0.4 ? vec3(0.86, 0.79, 0.64) : (h < 0.75 ? vec3(0.82, 0.73, 0.57) : vec3(0.89, 0.84, 0.72));
	}
	if (w == 2) {
		return h < 0.45 ? vec3(0.66, 0.66, 0.64) : (h < 0.8 ? vec3(0.73, 0.72, 0.68) : vec3(0.70, 0.66, 0.6));
	}
	if (h < 0.35) {
		return vec3(0.9, 0.89, 0.86);
	}
	if (h < 0.6) {
		return vec3(0.87, 0.82, 0.72);
	}
	if (h < 0.8) {
		return vec3(0.84, 0.77, 0.66);
	}
	return h < 0.92 ? vec3(0.8, 0.8, 0.77) : vec3(0.86, 0.76, 0.7);
}

// Building `fb`'s wall colour (linear, before the gain): its palette colour with 20 % of the photo's; corrugated sheds
// (w 3) the photo's.
vec3 wall_colour(int w, float fb, vec3 photo) {
	vec3 own = w == 3 ? photo : srgb_to_linear(palette(w, hash(vec2(fb, 1.7)))) * mix(1.0, 0.85, hash(vec2(fb, 5.3)));
	return mix(own, photo, 0.2);
}

// A wall's highest albedo: brighter with palette_colours (not corrugated sheds, w 3).
float wall_cap(int w) {
	return palette_colours && w < 3 ? PALETTE_MAX : MAX_ALBEDO;
}

// A wall colour lit: with palette_colours warmer and brighter.
vec3 wall_lit(int w, vec3 c) {
	bool warm = palette_colours && w < 3;
	return min((warm ? mix(c, CREAM, CREAM_MIX) : c) * (warm ? PALETTE_GAIN : WALL_GAIN), vec3(wall_cap(w)));
}

// A roof's colour far away (linear albedo): the photo's; with palette_colours, as the near Detailed roof's average, a
// gabled roof's clay (alpha GABLED) and a light flat roof's white coating in the photo's hue, halfway to its
// brightness (`a` the roof's colour alpha, `hb` the building's seed). A Detailed dome (alpha 1) keeps the photo's.
vec3 roof_far(vec3 photo, float a, float hb) {
	vec3 far_c = min(photo * ROOF_GAIN, vec3(MAX_ALBEDO));
	if (!palette_colours || a > 0.99) {
		return far_c;
	}
	if (abs(a - 0.5) < 0.1) {
		return mix(CLAY, far_c, 0.3);
	}
	if (luma(photo) + (hb - 0.5) * 0.05 < 0.13) {
		return far_c;
	}
	vec3 hue = mix(vec3(1.0), clamp(far_c / max(luma(far_c), 0.01), vec3(0.6), vec3(1.6)), 0.5);
	return COATING * hue * mix(1.0, luma(far_c) / 0.45, 0.5);
}
