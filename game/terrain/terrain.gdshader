// Terrain chunk: displaces a subdivided plane by the original IAF elevation data.
shader_type spatial;
render_mode cull_back;

// Raw u16 heights packed as R = high byte, G = low byte; 1 texel wider than the chunk.
uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D colour_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sea_level_raw = 20342.0;
uniform float height_scale = 9.2575;
uniform float chunk_span = 16384.0;
uniform float chunk_pixels = 1024.0;
// Terrain units are 1.2411389 m (the original engine's PlaneScalePR), heights included.
uniform float units_to_metres = 1.0;
// The generated sea colour in the imagery (open water only, not the Dead Sea / lakes).
uniform vec3 sea_colour = vec3(0.035, 0.059, 0.302);

varying vec3 world_normal;

float height_at(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(int(chunk_pixels)));
	vec2 rg = texelFetch(height_tex, p, 0).rg;
	float raw = rg.r * 65280.0 + rg.g * 255.0;
	return (raw - sea_level_raw) / height_scale * units_to_metres;
}

bool is_open_sea(vec2 uv) {
	vec3 c = textureLod(colour_tex, uv, 3.0).rgb;
	return distance(c, sea_colour) < 0.06;
}

void vertex() {
	// PlaneMesh UVs run 0..1 across the chunk; vertices land exactly on texels.
	ivec2 p = ivec2(round(UV * chunk_pixels));
	float h = height_at(p);
	// Keep open sea flat at sea level (the data carries bathymetry).
	if (h < 0.0 && is_open_sea(UV)) {
		h = 0.0;
	}
	VERTEX.y = h;
	float texel = chunk_span / chunk_pixels;
	int s = 2;
	float dx = height_at(p + ivec2(s, 0)) - height_at(p - ivec2(s, 0));
	float dz = height_at(p + ivec2(0, s)) - height_at(p - ivec2(0, s));
	NORMAL = normalize(vec3(-dx, 2.0 * float(s) * texel, -dz));
}

void fragment() {
	ALBEDO = texture(colour_tex, UV).rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
