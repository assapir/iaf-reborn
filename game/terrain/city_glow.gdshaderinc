// Night lights = Detailed at night (terrain/city_lights.gd, docs/rendering.md §5.1): a faint sodium haze over the
// dense lamp clusters only; the points carry the look and the unlit ground stays night-dark. city_glow R: the square
// root of the lamps' brightness per 125 m square, row 0 north; rect = (x0, z0 of its north-west corner, 1 / width m,
// 1 / height m), scene frame; k = 0: off (the original). Read per vertex (v_city_glow = city_glow_at(its x / z)): the
// haze is smooth and a texture read per pixel cost 0.6 ms; a surface adds city_glow_emission(ALBEDO) to its EMISSION.
global uniform float city_glow_k;
global uniform sampler2D city_glow : filter_linear_mipmap, repeat_disable;
global uniform vec4 city_glow_rect;

varying float v_city_glow;

// Brightness g² to the power 1.5: a full square glows, a suburb's sparse lamps hardly.
float city_glow_at(vec2 xz) {
	if (city_glow_k <= 0.0) {
		return 0.0;
	}
	float g = textureLod(city_glow, (xz - city_glow_rect.xy) * city_glow_rect.zw, 0.0).r;
	return g * g * g * city_glow_k;
}

// Mostly flat (a haze), a little of it the surface's own colour, so the photo's daytime texture does not show through.
vec3 city_glow_emission(vec3 albedo) {
	return vec3(1.0, 0.45, 0.14) * v_city_glow * (0.06 + 0.2 * albedo);
}
