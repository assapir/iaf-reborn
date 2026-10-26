// Rain (ours, Graphics → MORE "Rain"; docs/rendering.md §10, terrain/weather.gd): the falling drops around the camera.
// One MultiMesh quad per drop, placed here, not by the CPU: each drop has a fixed seed spot in a `box` m cube that
// wraps around a point ahead of the camera, so the drops stay put in the world while the camera flies through them.
// A drop is drawn as the streak it sweeps in `shutter` s at its speed seen from the camera: short and falling when
// still, near horizontal across the view at 300+ kt.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float box = 40.0;
// The rain's world velocity (m/s: its fall plus the wind) and its travel so far, wrapped by `box` (weather.gd).
uniform vec3 fall = vec3(0.0, -9.0, 0.0);
uniform vec3 drift = vec3(0.0);
// The camera's world velocity (m/s).
uniform vec3 cam_vel = vec3(0.0);
uniform float shutter = 0.025;
uniform float max_len = 1.5;
uniform vec3 tint : source_color = vec3(0.8);
uniform float opacity = 0.9;

varying float v_a;
varying vec2 v_l;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 seed = vec3(hash(id * 1.31 + 0.1), hash(id * 2.17 + 0.5), hash(id * 3.71 + 0.2));
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 centre = cam - INV_VIEW_MATRIX[2].xyz * box * 0.35;
	vec3 corner = centre - vec3(0.5 * box);
	vec3 p = corner + mod(seed * box + drift - corner, box);
	vec3 rel = fall - cam_vel;
	vec3 a = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	// At most `max_len` m long: a near drop's streak at speed would cross the screen (and cost its fill).
	vec3 b = (VIEW_MATRIX * vec4(p - rel * min(shutter, max_len / max(length(rel), 1e-3)), 1.0)).xyz;
	float d = -a.z;
	// Metres per pixel at 1 m: a drop is drawn 6 mm wide (its blur), at least a pixel and fades as it gets thinner than that.
	float px = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float w = max(0.006, d * px);
	vec3 side = cross(b - a, a);
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	v_l = UV * 2.0 - 1.0;
	// A long streak spreads the drop's light: somewhat fainter. Off near the camera (inside the canopy), faded at the box's edge.
	float len = min(length(rel) * shutter, max_len);
	v_a = opacity * clamp(0.006 / max(d * px, 1e-6), 0.25, 1.0) * clamp(1.0 / (len + 0.5), 0.6, 1.0)
			* smoothstep(3.0, 6.0, d) * (1.0 - smoothstep(0.3 * box, 0.5 * box, distance(p, centre)));
	vec3 v = mix(a, b, UV.y) + side * v_l.x * 0.5 * w;
	// A drop not drawn (too near, behind the camera, out of the cube) is moved out of the view: its streak would still
	// be rasterised, and near the camera it spans the screen.
	POSITION = v_a > 0.001 ? PROJECTION_MATRIX * vec4(v, 1.0) : vec4(2.0, 2.0, 2.0, 1.0);
}

void fragment() {
	// Clamped: with MSAA a pixel-thin streak's varyings are extrapolated past its edges.
	ALBEDO = tint;
	ALPHA = clamp(v_a * (1.0 - abs(v_l.x)) * (1.0 - v_l.y * v_l.y * 0.6), 0.0, 1.0);
}
