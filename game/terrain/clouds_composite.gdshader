// Clouds Volumetric (ours; docs/rendering.md §2.1, terrain/volumetric_clouds.gd): the half-size cloud image
// (clouds_march.glsl, rgb the light the clouds send, a the light they let through) laid over the 3D view as the first
// transparent thing drawn: after the terrain, the models and the sky, before the smoke, the rain and the effects, and
// under the 2D cockpit and HUD (canvas layers, drawn after the 3D view). Upsampled by the depth: of the four nearest
// cloud pixels the ones whose scene depth matches this pixel's count, so a cloud does not bleed over a hill's edge.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, blend_premul_alpha, cull_disabled, shadows_disabled;

uniform sampler2D clouds : filter_nearest;
uniform sampler2D cloud_dist : filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	// A full-screen triangle pair at the far plane (reverse Z: 0), never culled (extra_cull_margin).
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene = depth <= 0.0 ? 1e9 : length(v.xyz / v.w);
	vec2 lo = vec2(textureSize(clouds, 0));
	vec2 lp = SCREEN_UV * lo - 0.5;
	ivec2 b = ivec2(floor(lp));
	vec2 f = fract(lp);
	vec4 sum = vec4(0.0);
	float ws = 0.0;
	vec4 near = vec4(0.0, 0.0, 0.0, 1.0);
	float best = 1e30;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		ivec2 q = clamp(b + o, ivec2(0), ivec2(lo) - 1);
		vec4 c = texelFetch(clouds, q, 0);
		float s = texelFetch(cloud_dist, q, 0).g;
		float bw = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		float rel = abs(s - scene) / max(min(s, scene), 1.0);
		float w = bw * (scene > 5e8 && s > 5e8 ? 1.0 : exp(-rel * 20.0));
		sum += c * w;
		ws += w;
		if (rel < best) {
			best = rel;
			near = c;
		}
	}
	vec4 c = ws > 1e-4 ? sum / ws : near;
	ALBEDO = c.rgb;
	ALPHA = 1.0 - c.a;
}
