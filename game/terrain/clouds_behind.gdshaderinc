// Clouds Volumetric (terrain/volumetric_clouds.gd, docs/rendering.md §2.1): how much of a transparent thing behind a
// cloud shows. The effects, the sparks and the light points draw after the clouds' quad, so each reads the march's
// half-size image (a: the light the clouds let through), the clouds' mean distance along each pixel's view and the
// 3D view size they were made for. clouds_on 0: no Volumetric clouds.
global uniform float clouds_on;
global uniform sampler2D clouds_light : filter_linear;
global uniform sampler2D clouds_dist : filter_nearest;
global uniform vec2 clouds_full;

// The share of a thing's light that reaches the eye at screen point `suv`, the thing `dist` m from the camera: all of
// it in front of the clouds, the light they let through behind them (softly at their thin edges), a ramp across the
// clouds' mean distance (±10 %, at least ±100 m: inside a cloud its distance is the mean of a few jittered steps). The
// distance is the mean of the four nearest cloud pixels (each frame marches one of each 2 × 2 block). Another viewport
// of the same world (the EO sensor's, a screenshot's) sees all of it.
float clouds_through(vec2 suv, vec2 vp_size, float dist) {
	if (clouds_on < 0.5 || any(greaterThan(abs(vp_size - clouds_full), vec2(1.5)))) {
		return 1.0;
	}
	float cd = dot(textureGather(clouds_dist, suv, 0), vec4(0.25));
	float w = max(0.1 * cd, 100.0);
	return mix(1.0, textureLod(clouds_light, suv, 0.0).a, smoothstep(cd - w, cd + w, dist));
}
