// Ours ("Better cockpit" crisp_mfd, mfd.gd): the MFD's pixel art drawn as vectors at its original pixels, sharp at any
// scale. Each lit pixel's centre is joined to its lit neighbours by a stroke 1 original px wide (a diagonal only where
// no orthogonal step joins the two), so a 1-px line stays 1 px wide and a stair-step becomes a straight line. The
// opaque (black) ground is the pixels' bilinear coverage cut at one half: straight edges stay where they are, the
// rounded corners and the radar fans turn smooth. The colour keys (cyan) and alpha 0 are transparent. Textures of at most
// 4 × 4 texels (Godot's white texture under the untextured lines and fills) pass through.

const ivec2 IAF_DIRS[8] = {ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1), ivec2(1, 1), ivec2(-1, 1), ivec2(1, -1), ivec2(-1, -1)};

bool iaf_clear(vec4 t) {
	// The cockpit art's keys (iaf-tools gltf.rs COCKPIT_KEYS): RGB(0,255,255) and RGB(0,210,255).
	return t.a < 0.5 || (t.r < 0.02 && t.b > 0.98 && (t.g > 0.98 || abs(t.g - 0.8235) < 0.01));
}

bool iaf_lit(vec4 t) {
	return !iaf_clear(t) && max(t.r, max(t.g, t.b)) > 0.2;
}

// `shaded`: COLOR as Godot shades it (texture × modulate); `modulate`: the vertex colour alone.
vec4 iaf_crisp(sampler2D tex, vec2 uv, vec4 shaded, vec4 modulate) {
	ivec2 sz = textureSize(tex, 0);
	vec2 p = uv * vec2(sz);
	// Half a screen pixel, in texels: the antialiasing ramp.
	float w = max(max(fwidth(p.x), fwidth(p.y)) * 0.5, 1e-4);
	if (sz.x <= 4 && sz.y <= 4) {
		return shaded;
	}
	ivec2 c = ivec2(floor(p));
	vec4 t[25];
	bool lit[25];
	for (int j = 0; j < 5; j++) {
		for (int i = 0; i < 5; i++) {
			ivec2 q = c + ivec2(i - 2, j - 2);
			vec4 v = (q.x < 0 || q.y < 0 || q.x >= sz.x || q.y >= sz.y) ? vec4(0.0) : texelFetch(tex, q, 0);
			t[j * 5 + i] = v;
			lit[j * 5 + i] = iaf_lit(v);
		}
	}
	// The nearest stroke of the lit pixels around: from each pixel's centre half-way to each lit neighbour; a pixel on a
	// stair (one straight and one diagonal neighbour, opposite) joins the two half-way points instead, so the steps of
	// a shallow line or a curve smooth out while square corners stay square.
	float best = 1e3;
	vec3 col = vec3(0.0);
	for (int j = 1; j < 4; j++) {
		for (int i = 1; i < 4; i++) {
			int k = j * 5 + i;
			if (!lit[k]) {
				continue;
			}
			vec2 a = vec2(c + ivec2(i - 2, j - 2)) + 0.5;
			bool nb[8];
			int count = 0;
			ivec2 o1 = ivec2(0);
			ivec2 o2 = ivec2(0);
			for (int n = 0; n < 8; n++) {
				ivec2 o = IAF_DIRS[n];
				nb[n] = lit[(j + o.y) * 5 + i + o.x]
						&& !(o.x != 0 && o.y != 0 && (lit[j * 5 + i + o.x] || lit[(j + o.y) * 5 + i]));
				if (nb[n]) {
					count++;
					o2 = o1;
					o1 = o;
				}
			}
			if (count == 2 && abs(o1.x * o1.y) + abs(o2.x * o2.y) == 1 && o1.x * o2.x + o1.y * o2.y == -1) {
				vec2 e0 = a + vec2(o1) * 0.5;
				vec2 e1 = a + vec2(o2) * 0.5;
				vec2 pa = p - e0;
				vec2 ba = e1 - e0;
				float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
				float ds = length(pa - ba * h);
				if (ds < best) {
					best = ds;
					col = t[k].rgb;
				}
				continue;
			}
			float d = length(p - a);
			if (d < best) {
				best = d;
				col = t[k].rgb;
			}
			for (int n = 0; n < 8; n++) {
				if (!nb[n]) {
					continue;
				}
				ivec2 o = IAF_DIRS[n];
				vec2 pa = p - a;
				vec2 ba = vec2(o) * 0.5;
				float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
				float ds = length(pa - ba * h);
				if (ds < best) {
					best = ds;
					col = mix(t[k].rgb, t[(j + o.y) * 5 + i + o.x].rgb, h * 0.5);
				}
			}
		}
	}
	// The opaque and the lit pixels' bilinear coverage: the ground, and the lit areas' insides (where four lit pixels
	// meet, the strokes through their centres are half a pixel away).
	vec2 g = p - 0.5;
	ivec2 b0 = ivec2(floor(g)) - c + ivec2(2);
	vec2 f = fract(g);
	int i00 = b0.y * 5 + b0.x;
	vec4 o = vec4(iaf_clear(t[i00]) ? 0.0 : 1.0, iaf_clear(t[i00 + 1]) ? 0.0 : 1.0,
			iaf_clear(t[i00 + 5]) ? 0.0 : 1.0, iaf_clear(t[i00 + 6]) ? 0.0 : 1.0);
	vec4 l = vec4(lit[i00] ? 1.0 : 0.0, lit[i00 + 1] ? 1.0 : 0.0, lit[i00 + 5] ? 1.0 : 0.0, lit[i00 + 6] ? 1.0 : 0.0);
	float m = mix(mix(o.x, o.y, f.x), mix(o.z, o.w, f.x), f.y);
	float ml = mix(mix(l.x, l.y, f.x), mix(l.z, l.w, f.x), f.y);
	float cov = max(1.0 - smoothstep(0.5 - w, 0.5 + w, best), smoothstep(0.5 - w, 0.5 + w, ml));
	float ground = smoothstep(0.5 - w, 0.5 + w, m);
	float alpha = max(cov, ground);
	vec3 rgb = alpha > 0.0 ? col * cov / alpha : vec3(0.0);
	return vec4(rgb, alpha) * modulate;
}
