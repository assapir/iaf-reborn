// Airbase underlay models (runways, taxiways, aprons: ul_rw*.x) lying exactly on the flattened
// terrain (util/gltf.gd make_underlay). Each vertex is moved towards the camera along its view ray by
// `bias_m` + `bias_per_m` × distance, so the model wins the depth test against the coplanar ground
// without moving on screen (a depth offset like D3D's z-bias; docs/deviations.md).
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform float bias_m = 0.03;
uniform float bias_per_m = 0.0005;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(v.xyz);
	v.xyz *= max(0.0, 1.0 - (bias_m + bias_per_m * d) / max(d, 1e-3));
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_tex, UV).rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
