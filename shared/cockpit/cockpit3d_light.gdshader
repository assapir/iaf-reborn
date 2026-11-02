// The 3D cockpit's baked light and relief (cockpit3d.gd _setup_baked_light): each opaque part drawn again over
// itself, the framebuffer multiplied by
//   - the ambient occlusion baked on its UV2 (tools/f16d/cockpit3d.py bake_light), `strength` of it;
//   - the relief of its texture sheet: the sheet's brightness taken as height (the white labels and screw heads stand
//     up, the dark seams sink), lit from above and behind the pilot (the canopy), up to `relief` brighter or darker.
// cull_back becomes the part's own cull mode; `clip` keeps an alpha-scissored part's cut-outs.
shader_type spatial;
render_mode blend_mul, unshaded, fog_disabled, depth_draw_never, cull_back;

uniform sampler2D light : hint_default_white, filter_linear_mipmap;
uniform sampler2D sheet : hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool clip = false;
uniform float strength = 0.85;
uniform float relief = 0.0;

varying vec3 sky;  // the light's direction, view space

void vertex() {
	sky = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.5, 0.0)).xyz);  // up and aft (the model's +z)
}

float height(vec2 uv) {
	return dot(texture(sheet, uv).rgb, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	if (clip && texture(sheet, UV).a < 0.5) {
		discard;
	}
	float k = mix(1.0, texture(light, UV2).r, strength);
	if (relief > 0.0) {
		// The sheet's u and v directions on the surface (view space), from the screen derivatives.
		vec3 dp1 = dFdx(VERTEX);
		vec3 dp2 = dFdy(VERTEX);
		vec2 duv1 = dFdx(UV);
		vec2 duv2 = dFdy(UV);
		vec3 n = normalize(NORMAL);
		vec3 t = cross(dp2, n) * duv1.x + cross(n, dp1) * duv2.x;
		vec3 b = cross(dp2, n) * duv1.y + cross(n, dp1) * duv2.y;
		float m = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-20));
		// One screen pixel's step on the sheet (at least a texel): the relief at the size it is drawn.
		vec2 texel = max(1.0 / vec2(textureSize(sheet, 0)), fwidth(UV));
		vec2 g = vec2(height(UV + vec2(texel.x, 0.0)) - height(UV - vec2(texel.x, 0.0)),
				height(UV + vec2(0.0, texel.y)) - height(UV - vec2(0.0, texel.y)));
		// The slope tilts the normal against the height's rise: the faces toward the light brighten.
		float lit = -(g.x * dot(t * m, sky) + g.y * dot(b * m, sky));
		k *= clamp(1.0 + relief * lit, 1.0 - relief, 1.0 + relief);
	}
	ALBEDO = vec3(k);
}
