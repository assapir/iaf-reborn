// The buildings' colours, shared by scenery.gdshader (On) and scenery_detailed.gdshader (Detailed); docs/scenery.md
// §3.4. Include after hash() and srgb_to_linear().
// The photo's colour already holds the sun's light, and the scene lights it again: roofs take ROOF_GAIN of it, walls
// WALL_GAIN, both at most MAX_ALBEDO (linear), so a town reads as bright as the photo under it, not white.
// palette_colours (Building colours = Palette, Settings.building_palette): every wall keeps its own palette colour at
// any distance, plaster, stone and concrete warmed CREAM_MIX toward CREAM and lit at PALETTE_GAIN up to PALETTE_MAX
// (a low sun lights them cream, as the Epic Fury reference's towns: modern-iaf/docs/scenery.md §7), and the far
// roofs take the near roof's material: the white coating on a light flat roof, clay on a gabled one (alpha
// iaf_avionics::scenery::GABLED, the far mesh too). Off (Photo): the walls fade to the photo's colour far away.
// SCENERY_ORTHO (Modern IAF, scenery.gd building_shader(): On's and Detailed's shaders compiled with it): with
// palette_colours, the walls in the palette's own colours (no cream mix, no photo mix, chroma +20 %), a plaster wall's
// group picked by the air photo's colour in a 2 m ring around its footprint (the walls' COLOR in Modern IAF's data),
// gain ORTHO_GAIN up to ORTHO_MAX (modern-iaf/docs/scenery.md §7).
uniform bool palette_colours = false;
// The sun's side (terrain_view.gd _update_time_of_day): the toward-sun direction's level part (world), its length the
// cosine of the sun's height; zero at night.
global uniform vec3 scenery_sun;
// A wall's sky light (AO: the ambient only) on its side away from the sun: a Lambert-like term of the wall's level
// normal against the sun's level direction, 1 on the sunward side, 1 − WALL_SHADE on the side away from a low sun.
const float WALL_SHADE = 0.6;

const float ROOF_GAIN = 0.6;
const float WALL_GAIN = 0.5;
const float MAX_ALBEDO = 0.45;
const float PALETTE_GAIN = 0.7;
const float PALETTE_MAX = 0.7;
const vec3 CREAM = vec3(0.85, 0.69, 0.48);  // sRGB (0.93, 0.85, 0.72)
const float CREAM_MIX = 0.5;
// Each building's brightness: 100 % down to SPREAD of its palette colour, by its hash.
#ifdef SCENERY_ORTHO
const float SPREAD = 0.75;
const float ORTHO_GAIN = 0.85;
const float ORTHO_MAX = 0.82;
const float ORTHO_CHROMA = 1.2;
#else
const float SPREAD = 0.85;
#endif
// The near roofs' average materials (linear; scenery_detailed.gdshader): clay tiles, the white coating worn in patches.
const vec3 CLAY = vec3(0.28, 0.11, 0.06);
const vec3 COATING = vec3(0.36, 0.36, 0.345);

// The wall's ambient factor for its world normal `n` (in vertex(): a wall is flat, its normal one per face).
float wall_shade(vec3 n) {
	return 1.0 - WALL_SHADE * 0.5 * (length(scenery_sun) - dot(normalize(vec3(n.x, 0.0, n.z) + 1e-5), scenery_sun));
}

#ifdef SCENERY_ORTHO
vec3 linear_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
#endif

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// A building's wall colour (sRGB): Jerusalem stone, white / beige / pale plaster, grey concrete blocks.
vec3 palette(int w, float h) {
#ifdef SCENERY_ORTHO
	// The look study's reference walls (Lab C 9–27 at L 50–82), set above their rendered chroma (the AgX tone
	// mapper takes some).
	if (w == 1) {  // warm sand stone
		return h < 0.4 ? vec3(0.88, 0.72, 0.50) : (h < 0.75 ? vec3(0.80, 0.64, 0.44) : vec3(0.92, 0.80, 0.60));
	}
	if (w == 2) {  // warm grey concrete
		return h < 0.5 ? vec3(0.68, 0.64, 0.58) : vec3(0.58, 0.55, 0.50);
	}
	if (h < 0.3) {
		return vec3(0.94, 0.92, 0.88);  // the Bauhaus white (240, 235, 225)
	}
	if (h < 0.45) {
		return vec3(0.92, 0.82, 0.64);  // cream plaster
	}
	if (h < 0.58) {
		return vec3(0.90, 0.68, 0.50);  // peach / terracotta plaster
	}
	if (h < 0.7) {
		return vec3(0.88, 0.74, 0.46);  // ochre
	}
	if (h < 0.8) {
		return vec3(0.88, 0.70, 0.66);  // dusty pink
	}
	if (h < 0.92) {
		return vec3(0.74, 0.70, 0.64);  // weathered warm grey
	}
	return vec3(0.66, 0.70, 0.62);  // pale green-grey
#endif
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

#ifdef SCENERY_ORTHO
// A plaster wall's colour by its neighbourhood: the footprint ring's tone in the air photo (sRGB `ring`: the wall tops
// and the street) picks the group, the building's hash `h` the colour in it.
vec3 palette_ring(float h, vec3 ring) {
	float l = dot(ring, vec3(0.2126, 0.7152, 0.0722));
	float warm = ring.r - ring.b;
	if (warm > 0.09) {  // sand, ochre, peach streets: the warm plasters
		return h < 0.3 ? vec3(0.92, 0.82, 0.64) : (h < 0.55 ? vec3(0.90, 0.68, 0.50)
			: (h < 0.8 ? vec3(0.88, 0.74, 0.46) : vec3(0.94, 0.92, 0.88)));
	}
	if (l > 0.5) {  // light, neutral: the whites
		return h < 0.45 ? vec3(0.94, 0.92, 0.88) : (h < 0.7 ? vec3(0.92, 0.90, 0.84)
			: (h < 0.85 ? vec3(0.88, 0.70, 0.66) : vec3(0.92, 0.82, 0.64)));
	}
	// Dark, neutral: weathered greys and older plaster.
	return h < 0.4 ? vec3(0.74, 0.70, 0.64) : (h < 0.65 ? vec3(0.66, 0.70, 0.62)
		: (h < 0.85 ? vec3(0.86, 0.80, 0.70) : vec3(0.94, 0.92, 0.88)));
}
#endif

// Building `fb`'s wall colour (linear, before the gain): its palette colour with 20 % of the photo's (SCENERY_ORTHO:
// its own, a plaster wall's group by the ring's colour `photo`); corrugated sheds (w 3) the photo's.
vec3 wall_colour(int w, float fb, vec3 photo) {
	if (w == 3) {
		return photo;
	}
#ifdef SCENERY_ORTHO
	vec3 pick = w == 0 ? palette_ring(hash(vec2(fb, 1.7)), linear_to_srgb(photo)) : palette(w, hash(vec2(fb, 1.7)));
	vec3 own = srgb_to_linear(pick) * mix(1.0, SPREAD, hash(vec2(fb, 5.3)));
	return max(mix(vec3(luma(own)), own, ORTHO_CHROMA), vec3(0.0));
#else
	vec3 own = srgb_to_linear(palette(w, hash(vec2(fb, 1.7)))) * mix(1.0, SPREAD, hash(vec2(fb, 5.3)));
	return mix(own, photo, 0.2);
#endif
}

// A wall's highest albedo: brighter with palette_colours (not corrugated sheds, w 3).
float wall_cap(int w) {
	return palette_colours && w < 3 ? PALETTE_MAX : MAX_ALBEDO;
}

// A wall colour lit: with palette_colours warmer and brighter.
vec3 wall_lit(int w, vec3 c) {
	bool warm = palette_colours && w < 3;
#ifdef SCENERY_ORTHO
	return min(c * (warm ? ORTHO_GAIN : WALL_GAIN), vec3(warm ? ORTHO_MAX : MAX_ALBEDO));
#else
	return min((warm ? mix(c, CREAM, CREAM_MIX) : c) * (warm ? PALETTE_GAIN : WALL_GAIN), vec3(wall_cap(w)));
#endif
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
