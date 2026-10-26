// Rain (ours, Graphics → MORE "Rain"; docs/rendering.md §10, terrain/weather.gd): drops on the canopy in the cockpit
// views. Drawn on a canvas layer over the 3D view and under the cockpit, so they show only through its window. Each
// drop is a small lens: it shows the scene around it, upside down, with a dark rim and a highlight. Two sizes in
// grid cells, one drop at most per cell; the airflow (`run`, the travel weather.gd integrates from the airspeed) drives
// them up the glass, each column at its own pace, stretched into streaks as they speed up; at rest they slide down.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
// Share of the cells holding a drop (Light / Heavy), less as the airflow blows them off.
uniform float amount = 0.0;
// The airflow's travel (screen heights) and its strength 0 (still) … 1 (fast).
uniform float run = 0.0;
uniform float flow = 0.0;
// The drops' clock (s): new drops land and old ones dry.
uniform float now = 0.0;

vec4 hash4(vec2 p) {
	vec4 q = vec4(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)), dot(p, vec2(419.2, 371.9)), dot(p, vec2(97.3, 157.1)));
	return fract(sin(q) * 43758.5453);
}

// The drop of the cell under `p` (screen heights, y down): its offset from the drop's centre over its radius in xy,
// z = how much there is of it (0 none), w = its radius.
vec4 drop(vec2 p, float cs, float speed, float seed) {
	float col = floor(p.x / cs);
	float pace = 0.6 + 0.8 * hash4(vec2(col, seed)).x;
	vec2 q = vec2(p.x, p.y + run * speed * pace);
	vec2 cell = floor(q / cs);
	vec4 h = hash4(cell + seed * 17.0);
	if (h.x > amount) {
		return vec4(0.0);
	}
	// Lands, stays, dries: a few seconds at rest, faster in the airflow.
	float life = fract(now * mix(0.1, 0.8, flow) * (0.7 + 0.6 * h.w) + h.y);
	float there = smoothstep(0.0, 0.03, life) * (1.0 - smoothstep(0.7, 1.0, life));
	float r = cs * (0.08 + 0.16 * h.z * h.z) * (1.0 - 0.6 * flow);
	vec2 c = (h.zw - 0.5) * (cs - 2.0 * r);
	vec2 d = q - (cell + 0.5) * cs - c;
	// Streaked along the airflow: the head up (where it runs), the tail below it; a drop at rest sags a little.
	d.y = d.y > 0.0 ? d.y / (1.0 + 10.0 * flow) : d.y * 1.15;
	d.x *= 1.0 + flow;
	return vec4(d / r, there, r);
}

void fragment() {
	vec2 px = 1.0 / SCREEN_PIXEL_SIZE;
	// Screen heights from the top (SCREEN_UV counts up from the bottom).
	vec2 p = vec2(SCREEN_UV.x * px.x / px.y, 1.0 - SCREEN_UV.y);
	vec4 a = drop(p, 0.09, 1.0, 1.0);
	vec4 b = drop(p, 0.04, 1.4, 2.0);
	vec4 d = dot(a.xy, a.xy) < 1.0 && a.z > 0.0 ? a : b;
	float r2 = dot(d.xy, d.xy);
	if (r2 >= 1.0 || d.z <= 0.0) {
		discard;
	}
	// The lens: the scene from about three radii around, inverted; a thin darker rim, below most; a small highlight.
	vec2 n = d.xy;
	float r = sqrt(r2);
	vec2 uv = SCREEN_UV - n * d.w * 3.0 * vec2(px.y / px.x, -1.0);
	vec3 c = texture(screen, uv).rgb * (1.0 - 0.35 * smoothstep(0.7, 1.0, r) * (0.4 + 0.6 * max(n.y, 0.0)));
	c += vec3(0.25) * smoothstep(0.25, 0.0, length(n - vec2(-0.3, -0.45))) * (1.0 - flow);
	COLOR = vec4(c, d.z * smoothstep(1.0, 0.8, r));
}
