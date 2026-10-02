// Extras "Sky: Atmospheric" (render_options.gd, docs/rendering.md): a clear-day sky from the sun's direction
// and the camera's altitude. Single scattering in the form L = E · sun · [P_R(μ)·(1 − e^(−τ_R·m)) +
// P_M(μ)·(1 − e^(−τ_M·m))], m the air mass along the view (Kasten-Young, capped), τ_R the air's (Rayleigh)
// optical depth per channel and τ_M the haze's (Mie, Henyey-Greenstein phase), both thinning with altitude
// (scale heights 8 km / 1.5 km). The τ_R are tuned, not the λ⁻⁴ values: single scattering alone gives a pale
// cyan zenith and a white horizon 7× brighter, which the AgX tonemapper turns grey; these give the photographs'
// deep blue zenith (≈ the gradient sky's top colour), a pale horizon ≈ 2–3× brighter, and a darker zenith at
// altitude. Below the horizon the colour is the horizon's: the fog takes the sky's colour along the view
// (aerial perspective), so the haze over the ground is the horizon's. Directions: Godot's sky EYEDIR /
// LIGHT0_DIRECTION (towards the sun).
shader_type sky;

uniform float exposure = 1.3;
// Optical depths of a vertical path from sea level: air (per channel) and haze.
uniform vec3 air_depth = vec3(0.045, 0.13, 0.6);
uniform float haze_depth = 0.12;
uniform float haze_g = 0.75;
// The air mass along the view is capped here (keeps the horizon pale blue, not white).
uniform float max_air_mass = 6.0;
// The sunlight's reddening through its air mass (fraction of the view's depths).
uniform float sun_reddening = 0.06;
// The camera's altitude (m; render_options.gd sets it in steps, so the sky's radiance is not re-filtered
// every frame).
uniform float altitude = 0.0;
uniform float sun_disc_deg = 0.53;
uniform float sun_disc_energy = 30.0;

float air_mass(float cos_zenith) {
	float c = max(cos_zenith, 0.0);
	float z = degrees(acos(c));
	return 1.0 / (c + 0.50572 * pow(max(96.07995 - z, 0.001), -1.6364));
}

void sky() {
	vec3 s = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	// Below the horizon: the horizon's colour in the same azimuth.
	vec3 v = normalize(vec3(EYEDIR.x, max(EYEDIR.y, 0.0), EYEDIR.z));
	float mu = dot(v, s);
	float m = min(air_mass(v.y), max_air_mass);
	vec3 tau_air = air_depth * exp(-altitude / 8000.0);
	float tau_haze = haze_depth * exp(-altitude / 1500.0);
	vec3 sun = exp(-(air_depth + haze_depth) * sun_reddening * air_mass(s.y)) * smoothstep(-0.1, 0.05, s.y);
	float g2 = haze_g * haze_g;
	float phase_air = 0.75 * (1.0 + mu * mu);
	float phase_haze = 0.25 * (1.0 - g2) / pow(1.0 + g2 - 2.0 * haze_g * mu, 1.5);
	vec3 col = exposure * sun * (phase_air * (1.0 - exp(-tau_air * m)) + phase_haze * (1.0 - exp(-tau_haze * m)));
	// The sun's disc (crisp edge) and a narrow glare, dimmed by the air along the view; the disc only above the
	// horizon. The angle from the chord: acos / cos are too coarse in floats this close to 1.
	float ang = length(EYEDIR - s);
	float r = radians(sun_disc_deg * 0.5);
	float disc = (1.0 - smoothstep(r * 0.85, r * 1.15, ang)) * step(0.0, EYEDIR.y);
	col += (disc * sun_disc_energy + 0.6 * exp(-ang / radians(1.5))) * sun * exp(-(tau_air + tau_haze) * m);
	COLOR = col;
}
