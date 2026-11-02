// Night lights = Detailed at night (terrain/city_lights.gd, docs/rendering.md §5.1): a faint sodium haze over the
// dense lamp clusters only; the points carry the look and the unlit ground stays night-dark. city_glow R: the square
// root of the lamps' brightness per 125 m square, row 0 north; rect = (x0, z0 of its north-west corner, 1 / width m,
// 1 / height m), scene frame; k = 0: off (the original). Read per vertex (v_city_glow = city_glow_at(its x / z, its
// distance from the camera)): the haze is smooth and a texture read per pixel cost 0.6 ms; a surface adds
// city_glow_emission(ALBEDO) to its EMISSION. city_glow_fog: the part of the scene's fog density the haze undoes (a
// light seen through clear night air dims less than a surface fogs).
global uniform float city_glow_k;
global uniform sampler2D city_glow : filter_linear_mipmap, repeat_disable;
global uniform vec4 city_glow_rect;
global uniform float city_glow_fog;

varying float v_city_glow;

// Brightness g² to the power 1.5: a full square glows, a suburb's sparse lamps hardly. Far vertices are sparse: they
// read a coarser mip (a texel about a hundredth of the distance).
float city_glow_at(vec2 xz, float dist) {
	if (city_glow_k <= 0.0) {
		return 0.0;
	}
	float lod = max(log2(dist / 12500.0), 0.0);
	float g = textureLod(city_glow, (xz - city_glow_rect.xy) * city_glow_rect.zw, lod).r;
	return g * g * g * city_glow_k * exp(city_glow_fog * dist);
}

// Mostly flat (a haze), a little of it the surface's own colour, so the photo's daytime texture does not show through.
vec3 city_glow_emission(vec3 albedo) {
	return vec3(1.0, 0.45, 0.14) * v_city_glow * (0.06 + 0.2 * albedo);
}
