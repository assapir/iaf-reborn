// Clouds Volumetric (terrain/volumetric_clouds.gd, docs/rendering.md §2.1): how much of a transparent thing behind a
// cloud shows. The effects, the sparks and the light points draw after the clouds' quad, so each reads the march's
// half-size image (rgb: the light the clouds send, a: the light they let through), the clouds' mean distance along
// each pixel's view and the 3D view size they were made for. clouds_on 0: no Volumetric clouds.
global uniform float clouds_on;
global uniform sampler2D clouds_light : filter_linear;
global uniform sampler2D clouds_dist : filter_nearest;
global uniform vec2 clouds_full;

// The share of a thing at screen point `suv`, `dist` m from the camera, that lies behind the clouds: 0 in front of
// them, 1 behind, a ramp across their mean distance (±10 %, at least ±100 m: inside a cloud its distance is the mean of
// a few jittered steps). The distance is the mean of the four nearest cloud pixels (each frame marches one of each
// 2 × 2 block). Another viewport of the same world (the EO sensor's, a screenshot's) has none behind.
float clouds_behind(vec2 suv, vec2 vp_size, float dist) {
	if (clouds_on < 0.5 || any(greaterThan(abs(vp_size - clouds_full), vec2(1.5)))) {
		return 0.0;
	}
	float cd = dot(textureGather(clouds_dist, suv, 0), vec4(0.25));
	float w = max(0.1 * cd, 100.0);
	return smoothstep(cd - w, cd + w, dist);
}

// An added (blend_add) thing's share of its light that reaches the eye: all of it in front of the clouds, the light
// they let through behind them (softly at their thin edges).
float clouds_through(vec2 suv, vec2 vp_size, float dist) {
	float s = clouds_behind(suv, vp_size, dist);
	return s <= 0.0 ? 1.0 : mix(1.0, textureLod(clouds_light, suv, 0.0).a, s);
}

// A blended (blend_mix) thing's colour, drawn with its own alpha: behind the clouds, its colour by the light they let
// through plus their own light. Such a layer then replaces only what lies behind the clouds (the picture is the scene
// × their light through + their light), so a stack of layers behind a cloud (a smoke trail's puffs) shows no more
// than one opaque thing there would; fading each layer's alpha instead let a dense stack show nearly whole.
vec3 clouds_mix(vec2 suv, vec2 vp_size, float dist, vec3 col) {
	float s = clouds_behind(suv, vp_size, dist);
	if (s <= 0.0) {
		return col;
	}
	vec4 c = textureLod(clouds_light, suv, 0.0);
	return mix(col, c.rgb + c.a * col, s);
}
