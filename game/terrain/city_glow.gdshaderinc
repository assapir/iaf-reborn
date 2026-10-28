// Night lights = Detailed at night (terrain/city_lights.gd, docs/rendering.md §5.1): the towns' glow, the light of the
// street lamps on the ground and the buildings. city_glow R: the square root of the lamps' brightness per 125 m square,
// row 0 north; rect = (x0, z0 of its north-west corner, 1 / width m, 1 / height m), scene frame; k = 0: off (the
// original). A surface adds ALBEDO × city_glow_light(its x / z) to its EMISSION: its own colour under sodium light.
global uniform float city_glow_k;
global uniform sampler2D city_glow : filter_linear_mipmap, repeat_disable;
global uniform vec4 city_glow_rect;

vec3 city_glow_light(vec2 xz) {
	float g = texture(city_glow, (xz - city_glow_rect.xy) * city_glow_rect.zw).r;
	return vec3(1.0, 0.45, 0.14) * g * g * city_glow_k;
}
