#[compute]
#version 450
// Clouds Volumetric (ours; docs/rendering.md §2.1, terrain/volumetric_clouds.gd): the tileable 3D noises the clouds
// are made of, computed once when the clouds are made. Shape (128³): R Perlin-Worley (Perlin fBm remapped by a Worley
// fBm, the billows' puffy shapes), G B A Worley fBm at 4, 8, 16 cells (Schneider 2015). Detail (32³): R G B Worley fBm
// at 2, 4, 8 cells, to erode the edges. Every lattice wraps at the texture's edge, so the noises tile.

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

layout(set = 0, binding = 0, rgba8) uniform restrict writeonly image3D out_tex;

layout(push_constant, std430) uniform Params {
	vec4 mode;  // x: 0 shape, 1 detail; y: size
} p;

uvec3 pcg3(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v;
}

vec3 hash3(ivec3 c, int seed) {
	return vec3(pcg3(uvec3(c + ivec3(seed * 131, seed * 71, seed * 37)))) / 4294967295.0;
}

// Worley: 1 − the distance to the nearest feature point (one per cell), `f` cells per tile.
float worley(vec3 x, int f, int seed) {
	vec3 q = x * float(f);
	ivec3 c = ivec3(floor(q));
	vec3 r = fract(q);
	float d = 1.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				ivec3 o = ivec3(i, j, k);
				ivec3 cell = (c + o + f) % f;
				vec3 fp = vec3(o) + hash3(cell, seed) - r;
				d = min(d, dot(fp, fp));
			}
		}
	}
	return 1.0 - clamp(sqrt(d), 0.0, 1.0);
}

float worley_fbm(vec3 x, int f, int seed) {
	return worley(x, f, seed) * 0.625 + worley(x, f * 2, seed + 1) * 0.25 + worley(x, f * 4, seed + 2) * 0.125;
}

// Gradient (Perlin) noise, `f` cells per tile, −1..1.
float perlin(vec3 x, int f) {
	vec3 q = x * float(f);
	ivec3 c = ivec3(floor(q));
	vec3 r = fract(q);
	vec3 u = r * r * r * (r * (r * 6.0 - 15.0) + 10.0);
	float v[8];
	for (int n = 0; n < 8; n++) {
		ivec3 o = ivec3(n & 1, (n >> 1) & 1, (n >> 2) & 1);
		vec3 g = normalize(hash3((c + o + f) % f, 7) * 2.0 - 1.0);
		v[n] = dot(g, r - vec3(o));
	}
	return mix(mix(mix(v[0], v[1], u.x), mix(v[2], v[3], u.x), u.y),
			mix(mix(v[4], v[5], u.x), mix(v[6], v[7], u.x), u.y), u.z);
}

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) / (b - a) * (d - c);
}

void main() {
	int size = int(p.mode.y);
	ivec3 id = ivec3(gl_GlobalInvocationID);
	if (any(greaterThanEqual(id, ivec3(size)))) {
		return;
	}
	vec3 x = (vec3(id) + 0.5) / float(size);
	vec4 o;
	if (p.mode.x < 0.5) {
		float pf = 0.0;
		float a = 1.0;
		float s = 0.0;
		for (int i = 0; i < 4; i++) {
			pf += perlin(x, 4 << i) * a;
			s += a;
			a *= 0.5;
		}
		pf = clamp(0.5 + 0.7 * pf / s, 0.0, 1.0);
		float w = worley_fbm(x, 4, 1);
		o.r = clamp(remap(pf, 0.0, 1.0, w, 1.0), 0.0, 1.0);
		o.g = worley_fbm(x, 4, 11);
		o.b = worley_fbm(x, 8, 21);
		o.a = worley_fbm(x, 16, 31);
	} else {
		o = vec4(worley_fbm(x, 2, 41), worley_fbm(x, 4, 51), worley_fbm(x, 8, 61), 1.0);
	}
	imageStore(out_tex, id, o);
}
