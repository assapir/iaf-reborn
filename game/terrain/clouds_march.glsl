#[compute]
#version 450
// Clouds Volumetric (ours; docs/rendering.md §2.1, terrain/volumetric_clouds.gd): the clouds raymarched at half the
// 3D view's width and height, each frame's ray start jittered and blended into the last frames' (temporal
// reprojection), so a few dozen steps a pixel read as a smooth cloud. The cloud layer is flat, as the terrain is, from
// `base` to `top`: fair-weather cumulus when dry, the rain's deck in the rain. Density after
// Schneider 2015 (a Perlin-Worley shape, cut by the coverage and the height profile, its edges eroded by a Worley
// detail); light: the sun through the cloud toward it (Beer's law), a two-lobe Henyey-Greenstein phase with
// Wrenninge's multiple-scattering octaves, a powder term (the sunward edges darker), the sky's light from above and
// the ground's from below; the far clouds fade into the haze (the Atmospheric sky's colour along the view, else the
// fog colour) by the scene's fog density, as the terrain does.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler3D shape_tex;
layout(set = 0, binding = 1) uniform sampler3D detail_tex;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3) uniform sampler2D prev_color;
layout(set = 0, binding = 4) uniform sampler2D prev_dist;
layout(set = 0, binding = 5, rgba16f) uniform restrict writeonly image2D out_color;
layout(set = 0, binding = 6, rg32f) uniform restrict writeonly image2D out_dist;
layout(set = 0, binding = 7, std140) uniform Params {
	mat4 inv_proj;   // clip -> view
	mat4 cam;        // view -> world
	mat4 prev_vp;    // world -> the last frame's clip
	vec4 cam_frame;  // camera (world), frame number
	vec4 sun;        // direction to the sun, Atmospheric sky (1) for the haze colour
	vec4 sun_col;    // the sunlight (linear, its energy in), history valid (1)
	vec4 amb_top;    // the sky's light from above (linear), the Atmospheric sky's overcast
	vec4 amb_bottom; // the ground's light from below (linear), the sky's altitude (m)
	vec4 fog;        // fog colour (linear), fog density
	vec4 layer;      // base, top (m), coverage 0..1, extinction (1/m) at density 1
	vec4 shape;      // wind offset x, z (m), mode (0 cumulus, 1 deck), the farthest distance marched (m)
	vec4 sizes;      // this pass's width, height, the history blend (the new frame's share)
} p;

// The march: at most MAX_STEPS samples; a step is K x its distance, at least MIN m (BIG in clear air, FINE in cloud).
const int MAX_STEPS = 96;
const float K_BIG = 0.06;
const float MIN_BIG = 60.0;
const float K_FINE = 0.012;
const float MIN_FINE = 12.0;
// The noises' tile sizes (m): shape, detail, the coverage's field.
const float SHAPE_TILE = 9000.0;
const float DETAIL_TILE = 800.0;
const float COVER_TILE = 60000.0;
// The sunlight's gain on the phase function (isotropic = 1 / 4π), tuned against the sunlit terrain's brightness.
const float SUN_GAIN = 4.0 * 3.14159265 * 2.5;

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) / (b - a) * (d - c);
}

float density(vec3 pos, float hf, bool full) {
	if (hf <= 0.0 || hf >= 1.0) {
		return 0.0;
	}
	vec3 q = pos + vec3(p.shape.x, 0.0, p.shape.y);
	vec4 n = textureLod(shape_tex, q / SHAPE_TILE, 0.0);
	float wfbm = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
	float s = remap(n.r, wfbm - 1.0, 1.0, 0.0, 1.0);
	float cov = p.layer.z;
	float hp;
	if (p.shape.z < 0.5) {
		// Cumulus: fields of them and gaps (a slow coverage field), flat bases, rounded tops.
		float w = textureLod(shape_tex, vec3(q.xz / COVER_TILE, 0.37).xzy, 0.0).g;
		cov = clamp(cov + (w - 0.5) * 1.2, 0.0, 1.0);
		hp = smoothstep(0.0, 0.08, hf) * smoothstep(1.0, 0.35, hf);
		s *= hp;
		s = remap(s, 1.0 - cov, 1.0, 0.0, 1.0);
	} else {
		// The deck: all but closed; its top a field of lumps (the local top at 0.8..1 of the depth), its base ragged.
		// Cells (the Worley channel) of rounded tops with thinner cloud between them.
		float lump = smoothstep(0.35, 0.85, n.g * 0.7 + n.r * 0.3);
		float topline = 0.8 + 0.2 * lump;
		hp = smoothstep(0.0, 0.06 + 0.1 * (1.0 - lump), hf) * (1.0 - smoothstep(topline - 0.1, topline, hf));
		s = hp * (0.35 + 0.65 * lump) * (0.7 + 0.3 * n.r);
	}
	s = clamp(s, 0.0, 1.0) * cov;
	if (s <= 0.0 || !full) {
		return s;
	}
	vec3 dn = textureLod(detail_tex, q / DETAIL_TILE, 0.0).rgb;
	float dfbm = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
	// Wispy at the base, billowy higher up.
	float m = mix(1.0 - dfbm, dfbm, clamp(hf * 4.0, 0.0, 1.0));
	// The deck is eroded at its top only: deep inside it must stay cloud (a hole would show the ground through it).
	float erode = p.shape.z < 0.5 ? 0.5 : mix(0.15, 0.5, smoothstep(0.65, 0.9, hf));
	return clamp(remap(s, m * erode, 1.0, 0.0, 1.0), 0.0, 1.0);
}

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * 3.14159265 * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

float phase(float mu, float k) {
	return mix(hg(mu, 0.8 * k), hg(mu, -0.3 * k), 0.3);
}

// The optical depth toward the sun from `pos` (six steps, growing).
float sun_depth(vec3 pos) {
	float od = 0.0;
	float st = 60.0;
	float t = 0.5 * st;
	for (int i = 0; i < 6; i++) {
		vec3 x = pos + p.sun.xyz * t;
		float hf = (x.y - p.layer.x) / (p.layer.y - p.layer.x);
		od += density(x, hf, i < 3) * st;
		t += st;
		st *= 2.0;
		t += 0.5 * st;
	}
	return od * p.layer.w;
}

// The Atmospheric sky's colour in direction v (atmosphere.gdshader's single and multiple scattering, no sun disc):
// the haze the far clouds fade into, as Godot's aerial perspective fades the terrain into that sky.
float air_mass(float c) {
	c = max(c, 0.0);
	float z = degrees(acos(c));
	return 1.0 / (c + 0.50572 * pow(max(96.07995 - z, 0.001), -1.6364));
}

vec3 sky(vec3 eye) {
	vec3 s = p.sun.xyz;
	vec3 v = normalize(vec3(eye.x, max(eye.y, 0.0), eye.z));
	float mu = dot(eye, s);
	float m = min(air_mass(v.y), 6.0);
	float alt = p.amb_bottom.w;
	vec3 tau_air = vec3(0.045, 0.13, 0.6) * exp(-alt / 8000.0);
	float tau_haze = 0.12 * exp(-alt / 1500.0);
	float sun_path = (air_mass(s.y) - 1.0) * (1.0 - 0.6 * sqrt(v.y)) * (0.2 + 0.4 * (1.0 + mu));
	vec3 sun_t = exp(-vec3(0.08, 0.22, 0.4) * min(sun_path, 6.0));
	vec3 sun = sun_t / pow(sun_t.r, 0.7) * smoothstep(-0.1, 0.05, s.y);
	float g = 0.75;
	float ph_air = 0.75 * (1.0 + mu * mu);
	float ph_haze = 0.25 * (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);
	vec3 ext = 1.0 - exp(-tau_air * m);
	vec3 col = 1.3 * sun * (ph_air * ext + ph_haze * (1.0 - exp(-tau_haze * m)));
	col += 1.3 * sun * (1.0 - exp(-(tau_air + tau_haze) * 2.0)) * ext * clamp(0.25 + s.y, 0.0, 1.0);
	return mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), p.amb_top.w);
}

// Interleaved gradient noise (Jimenez 2014), shifted each frame by the golden ratio.
float jitter(vec2 px) {
	float n = fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
	return fract(n + p.cam_frame.w * 0.61803399);
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(p.sizes.xy);
	if (any(greaterThanEqual(id, size))) {
		return;
	}
	vec2 uv = (vec2(id) + 0.5) / vec2(size);
	float depth = textureLod(depth_tex, uv, 0.0).r;
	vec4 vp = p.inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);
	vp.xyz /= vp.w;
	float scene = depth <= 0.0 ? 1e9 : length(vp.xyz);
	vec3 o = p.cam_frame.xyz;
	vec3 d = normalize(mat3(p.cam) * normalize(vp.xyz));
	float alt = o.y;
	float base = p.layer.x;
	float top = p.layer.y;
	// The layer is flat, as the terrain is (no Earth curvature): the distances to its base and top planes.
	float dy = abs(d.y) < 1e-5 ? 1e-5 : d.y;
	float tb = (base - alt) / dy;
	float tt = (top - alt) / dy;
	float t0 = -1.0;
	float t1 = -1.0;
	if (alt > top && dy < 0.0) {
		t0 = tt;
		t1 = tb;
	} else if (alt > base && alt <= top) {
		t0 = 0.0;
		t1 = dy > 0.0 ? tt : tb;
	} else if (alt <= base && dy > 0.0) {
		t0 = tb;
		t1 = tt;
	}
	t1 = min(t1, min(scene, p.shape.w));
	vec3 scat = vec3(0.0);
	float tr = 1.0;
	float dsum = 0.0;
	float wsum = 0.0;
	if (t0 >= 0.0 && t1 > t0) {
		float mu = dot(d, p.sun.xyz);
		float hspan = top - base;
		// The light from above: the Atmospheric sky's own (its zenith and horizon), else the time of day's.
		vec3 amb_top = p.sun.w > 0.5 ? 0.35 * (sky(vec3(0.0, 1.0, 0.0)) + sky(normalize(vec3(-p.sun.x, 0.15, -p.sun.z) + 1e-4))) : p.amb_top.rgb;
		// Steps grow with the distance: long through clear air, short inside a cloud (from where the cheap density first
		// finds one, half a long step back, until 8 empty samples).
		float t = t0 + max(MIN_BIG, t0 * K_BIG) * jitter(vec2(id));
		// The light of the last cloud sample (at first a sunlit cloud top's), for the end of a ray in the deck.
		vec3 last = p.sun_col.rgb * phase(mu, 1.0) * SUN_GAIN * 0.5 + amb_top;
		bool fine = false;
		int empty = 0;
		for (int i = 0; i < MAX_STEPS; i++) {
			if (t > t1) {
				break;
			}
			float st = fine ? max(MIN_FINE, t * K_FINE) : max(MIN_BIG, t * K_BIG);
			vec3 x = o + d * t;
			float hf = (x.y - base) / hspan;
			float den = density(x, hf, false);
			if (!fine && den > 0.0) {
				fine = true;
				empty = 0;
				t = max(t - 0.5 * st, t0);
				continue;
			}
			if (den > 0.0) {
				den = density(x, hf, true);
			}
			if (den <= 0.002 && fine && ++empty > 8) {
				fine = false;
			}
			if (den > 0.002) {
				empty = 0;
				float sig = den * p.layer.w;
				float od = sun_depth(x);
				// Multiple scattering (Wrenninge 2013): octaves of weaker extinction and a wider phase.
				vec3 light = vec3(0.0);
				float a = 1.0;
				float b = 1.0;
				float c = 1.0;
				for (int k = 0; k < 3; k++) {
					light += a * exp(-od * b) * phase(mu, c);
					a *= 0.5;
					b *= 0.4;
					c *= 0.5;
				}
				// Powder: little cloud behind the sunward edge scatters little light back (darker), not toward the sun.
				float powder = 1.0 - exp(-2.0 * sig * 120.0);
				powder = mix(powder, 1.0, 0.5 + 0.5 * mu);
				vec3 sun = p.sun_col.rgb * light * powder * SUN_GAIN;
				vec3 amb = mix(p.amb_bottom.rgb, amb_top, clamp(hf, 0.0, 1.0)) * mix(0.55, 1.0, sqrt(clamp(hf, 0.0, 1.0)));
				float step_tr = exp(-sig * st);
				float w = tr * (1.0 - step_tr);
				scat += (sun + amb) * w;
				last = sun + amb;
				dsum += t * w;
				wsum += w;
				tr *= step_tr;
				if (tr < 0.01) {
					break;
				}
			}
			t += st;
		}
		// The deck hides what lies under it: a ray that ran out of steps (grazing the lumps' tops) ends there, opaque.
		if (p.shape.z > 0.5 && t < t1) {
			scat += last * tr;
			dsum += t * tr;
			wsum += tr;
			tr = 0.0;
		}
	}
	float dist = wsum > 0.0 ? dsum / wsum : min(t1 > 0.0 ? t1 : 1e5, 1e5);
	// The haze between the camera and the cloud (Godot's exponential fog: 1 − e^(−density · distance)).
	float f = wsum > 0.0 ? 1.0 - exp(-p.fog.w * dist) : 0.0;
	vec3 haze = p.sun.w > 0.5 ? sky(d) : p.fog.rgb;
	scat = mix(scat, haze * (1.0 - tr), f);
	vec4 cur = vec4(scat, tr);
	// Temporal reprojection: where the same cloud point was in the last frame; refused off screen or where the
	// scene's depth there changed (something moved in front, or out of the way).
	if (p.sun_col.w > 0.5) {
		vec3 wp = o + d * min(dist, scene);
		vec4 pc = p.prev_vp * vec4(wp, 1.0);
		vec2 puv = pc.xy / pc.w * 0.5 + 0.5;
		if (pc.w > 0.0 && all(greaterThanEqual(puv, vec2(0.0))) && all(lessThanEqual(puv, vec2(1.0)))) {
			vec2 hd = textureLod(prev_dist, puv, 0.0).rg;
			bool same = (scene > 5e8 && hd.g > 5e8) || abs(hd.g - scene) < 0.05 * scene;
			if (same) {
				cur = mix(textureLod(prev_color, puv, 0.0), cur, p.sizes.z);
			}
		}
	}
	imageStore(out_color, id, cur);
	imageStore(out_dist, id, vec4(dist, scene, 0.0, 0.0));
}
