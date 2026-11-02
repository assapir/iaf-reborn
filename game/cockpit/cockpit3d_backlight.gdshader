// The F-16 3D cockpit's backlit labels at night (cockpit3d.gd _backlight): each lit part drawn again over itself,
// adding `glow` where its texture sheet is near white: the panels' printed labels and the gauges' markings. FlightGear's
// implicit lightmap (panel-standard.eff, its ALS model shader): enhance = 1 − smoothstep(low, high, |texel − tag|),
// the texel as stored (sRGB values), its emit colour × enhance added. The rest (the paint, the ADI ball's sky and
// ground) keeps the flood alone. cull_back becomes the part's own cull mode; `clip` keeps an alpha-scissored part's
// cut-outs.
shader_type spatial;
render_mode blend_add, unshaded, fog_disabled, depth_draw_never, cull_back;

uniform sampler2D sheet : hint_default_black, filter_linear_mipmap_anisotropic;
uniform bool clip = false;
uniform vec3 glow = vec3(0.0);
uniform vec3 tag = vec3(0.87, 0.9, 0.91);
uniform float low = 0.1;
uniform float high = 0.7;

void fragment() {
	vec4 t = texture(sheet, UV);
	if (clip && t.a < 0.5) {
		discard;
	}
	ALBEDO = glow * (1.0 - smoothstep(low, high, length(t.rgb - tag)));
}
