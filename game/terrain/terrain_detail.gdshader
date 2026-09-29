// High-detail terrain tile (airbase insets, `iaf-terrain details`): its own colour at 1 unit per
// pixel, draped on the base chunk's height texture with exactly the base mesh's vertex lattice
// (so both surfaces coincide), lifted a few centimetres to sit on top.
shader_type spatial;
render_mode cull_back;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D colour_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sea_level_raw = 20342.0;
uniform float height_scale = 9.2575;
uniform float units_to_metres = 1.0;
uniform float chunk_pixels = 1024.0;
// Tile origin inside the base chunk's height texture, and texels per tile side.
uniform vec2 texel_origin = vec2(0.0);
uniform float tile_texels = 128.0;
uniform float texel_metres = 19.858;
uniform float lift = 0.15;

float height_at(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(int(chunk_pixels)));
	vec2 rg = texelFetch(height_tex, p, 0).rg;
	float raw = rg.r * 65280.0 + rg.g * 255.0;
	return (raw - sea_level_raw) / height_scale * units_to_metres;
}

void vertex() {
	ivec2 p = ivec2(round(texel_origin + UV * tile_texels));
	VERTEX.y = height_at(p) + lift;
	int s = 2;
	float dx = height_at(p + ivec2(s, 0)) - height_at(p - ivec2(s, 0));
	float dz = height_at(p + ivec2(0, s)) - height_at(p - ivec2(0, s));
	NORMAL = normalize(vec3(-dx, 2.0 * float(s) * texel_metres, -dz));
}

void fragment() {
	ALBEDO = texture(colour_tex, UV).rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
