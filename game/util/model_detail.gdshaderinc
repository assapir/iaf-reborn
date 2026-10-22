// Model detail (ours, Graphics → MORE → Model detail; docs/rendering.md "Model detail", util/model_detail.gd).
// The original model's own look (its texture × colour, roughness, specular, alpha scissor: what its StandardMaterial3D
// drew) plus a CC0 detail pack mapped triplanar in the model's frame, in metres. Up close only: the detail fades out
// from fade_near to fade_far (view distance) and is not sampled beyond, so far models draw as before.
// The including shader sets render_mode (the cull mode: two variants in all). Alpha-tested like the originals' MASK
// materials (opaque ones have alpha 1). `gear` adds a second pack, rubber, on the dark texels of a landing gear: the
// tyres.
// Pack layout (iaf_tools::model_detail): R roughness, G normal Y, B brightness about its mean, A normal X.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool has_tex = false;
uniform float roughness = 0.85;
uniform float specular = 0.5;
uniform float alpha_scissor = 0.5;

uniform sampler2D pack : filter_linear_mipmap, repeat_enable;
uniform float tile_m = 1.0;  // metres per texture repeat
uniform float rough_mean = 0.5;  // the pack's mean roughness
uniform float rough_mid = 0.6;  // the surface's mean roughness with the detail
uniform float rough_var = 0.5;  // how much of the pack's roughness variation shows
uniform float metallic = 0.0;
uniform float normal_strength = 0.5;
uniform float tint_strength = 0.1;  // brightness modulation of the albedo (± this at ±2 σ)
uniform float fade_near = 40.0;
uniform float fade_far = 120.0;
uniform bool gear = false;
uniform sampler2D pack2 : filter_linear_mipmap, repeat_enable;
uniform float tile2_m = 0.3;
uniform float rough2_mean = 0.5;
uniform float rough2_mid = 0.9;
uniform float dark_below = 0.16;  // texel brightness below which the gear is rubber

varying vec3 obj_pos;
varying vec3 obj_n;

void vertex() {
	// The model's frame scaled to world metres (the model's scale and World scale included).
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	obj_pos = VERTEX * s;
	obj_n = NORMAL;
}

// Triplanar sample of `t` at `p` (metres / tile) with blend weights `w`: the blended pack and the detail normal in
// the model's frame (UDN blend on `n`).
vec4 tri(sampler2D t, vec3 p, vec3 w, vec3 n, float k, out vec3 dn) {
	vec4 x = texture(t, p.zy);
	vec4 y = texture(t, p.xz);
	vec4 z = texture(t, p.xy);
	vec2 nx = (x.ag * 2.0 - 1.0) * k;
	vec2 ny = (y.ag * 2.0 - 1.0) * k;
	vec2 nz = (z.ag * 2.0 - 1.0) * k;
	dn = normalize(
		vec3(n.x, n.y + nx.y, n.z + nx.x) * w.x + vec3(n.x + ny.x, n.y, n.z + ny.y) * w.y
		+ vec3(n.x + nz.x, n.y + nz.y, n.z) * w.z
	);
	return x * w.x + y * w.y + z * w.z;
}

void fragment() {
	vec4 c = (has_tex ? texture(albedo_tex, UV) : vec4(1.0)) * albedo * COLOR;
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	float f = 1.0 - smoothstep(fade_near, fade_far, length(VERTEX));
	if (f > 0.0) {
		vec3 n = normalize(obj_n);
		vec3 w = pow(abs(n), vec3(4.0));
		w /= w.x + w.y + w.z;
		vec3 dn;
		vec4 d = tri(pack, obj_pos / tile_m, w, n, normal_strength, dn);
		float r = clamp(rough_mid + (d.r - rough_mean) * rough_var, 0.05, 1.0);
		float m = metallic;
		float tint = 1.0 + (d.b - 0.5) * 2.0 * tint_strength;
		float rub = gear ? 1.0 - smoothstep(dark_below * 0.7, dark_below, dot(c.rgb, vec3(0.299, 0.587, 0.114))) : 0.0;
		if (rub > 0.0) {
			vec3 dn2;
			vec4 d2 = tri(pack2, obj_pos / tile2_m, w, n, 0.8, dn2);
			dn = normalize(mix(dn, dn2, rub));
			r = mix(r, clamp(rough2_mid + (d2.r - rough2_mean), 0.05, 1.0), rub);
			m *= 1.0 - rub;
			tint = mix(tint, 1.0 + (d2.b - 0.5) * 0.3, rub);
		}
		ALBEDO *= mix(1.0, tint, f);
		ROUGHNESS = mix(roughness, r, f);
		METALLIC = m * f;
		vec3 vn = normalize(mat3(VIEW_MATRIX) * normalize(MODEL_NORMAL_MATRIX * dn));
		vn = FRONT_FACING ? vn : -vn;
		NORMAL = normalize(mix(NORMAL, vn, f));
	}
}
