// Extras "Sky: Atmospheric" (render_options.gd, docs/rendering.md §1.2): a clear-day sky from the sun's direction
// and the camera's altitude, plus a fitted multiple-scattering term (below). Single scattering in the form L = E · sun · [P_R(μ)·(1 − e^(−τ_R·m)) +
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
// The sunlight's optical depths for its reddening (vertical, per channel), through its air mass beyond the
// zenith's: white at noon, orange by a low sun. Closer to λ⁻⁴ than air_depth (whose strong blue would turn the low
// sun olive through the view's blue-heavy scattering). Light scattered high up (looking up) crossed less air.
uniform vec3 sun_depth = vec3(0.08, 0.22, 0.4);
// Multiple scattering (Hillaire 2020's isotropic term, fitted): the air lit by the sky's own light, gain over
// single scattering.
uniform float ms_gain = 1.0;
// The camera's altitude (m; render_options.gd sets it in steps, so the sky's radiance is not re-filtered
// every frame).
uniform float altitude = 0.0;
uniform float sun_disc_deg = 0.53;
uniform float sun_disc_energy = 30.0;
// In the rain (render_options.gd, weather.gd's sky share): the sky turns toward its own grey, the sun's disc hidden.
uniform float overcast = 0.0;
// The ground's albedo seen from above (dry sand, limestone, fields; inferred).
uniform vec3 ground_albedo = vec3(0.36, 0.33, 0.27);

float air_mass(float cos_zenith) {
	float c = max(cos_zenith, 0.0);
	float z = degrees(acos(c));
	return 1.0 / (c + 0.50572 * pow(max(96.07995 - z, 0.001), -1.6364));
}

void sky() {
	vec3 s = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	// Below the horizon: the horizon's air path in the same azimuth, but the scattering angle of the true view, so
	// the haze over the ground glows warm only toward the sun (the phase functions' forward lobe) and is blue-grey
	// elsewhere.
	vec3 v = normalize(vec3(EYEDIR.x, max(EYEDIR.y, 0.0), EYEDIR.z));
	float mu = dot(EYEDIR, s);
	float m = min(air_mass(v.y), max_air_mass);
	// Looking down from altitude, the view goes down into the lower air and its haze: below the horizon the depths
	// fade to sea level's by 6° down.
	float alt = altitude * (1.0 - smoothstep(0.0, -0.1, EYEDIR.y));
	vec3 tau_air = air_depth * exp(-alt / 8000.0);
	float tau_haze = haze_depth * exp(-alt / 1500.0);
	// Away from a low sun the sky stays blue-grey (ozone's absorption of the orange light and the scattering near
	// the camera, fitted): the path is shorter there.
	float sun_path = (air_mass(s.y) - 1.0) * (1.0 - 0.6 * sqrt(v.y)) * (0.2 + 0.4 * (1.0 + mu));
	// Its hue, but only part of its dimming (the red's to the power 0.3): the air the low sun lights is the
	// near, lower part of a long path, and the horizon toward it stays bright.
	vec3 sun_t = exp(-sun_depth * min(sun_path, 6.0));
	vec3 sun = sun_t / pow(sun_t.r, 0.7) * smoothstep(-0.1, 0.05, s.y);
	float g2 = haze_g * haze_g;
	float phase_air = 0.75 * (1.0 + mu * mu);
	float phase_haze = 0.25 * (1.0 - g2) / pow(1.0 + g2 - 2.0 * haze_g * mu, 1.5);
	vec3 ext = 1.0 - exp(-tau_air * m);
	vec3 col = exposure * sun * (phase_air * ext + phase_haze * (1.0 - exp(-tau_haze * m)));
	// Multiple scattering: isotropic, from the light the air scatters on a slant path (air mass 2) and the
	// atmosphere's lighting by the sun's height (a lower sun lights less of it); it fills the 90° band the Rayleigh
	// phase leaves dark, and at sunset takes the reddened sun's colour (pink-violet away from the sun).
	vec3 ms = (1.0 - exp(-(tau_air + tau_haze) * 2.0)) * ext * clamp(0.25 + s.y, 0.0, 1.0);
	col += exposure * ms_gain * sun * ms;
	// The sun's disc (crisp edge) and a narrow glare, dimmed by the air along the view; the disc only above the
	// horizon. The angle from the chord: acos / cos are too coarse in floats this close to 1.
	float ang = length(EYEDIR - s);
	float r = radians(sun_disc_deg * 0.5);
	float disc = (1.0 - smoothstep(r * 0.85, r * 1.15, ang)) * step(0.0, EYEDIR.y);
	col += (disc * sun_disc_energy + 0.6 * exp(-ang / radians(1.5))) * sun * exp(-(tau_air + tau_haze) * m) * (1.0 - overcast);
	// Looking down, the light from below (ambient, reflections): from 6° to 30° down toward the sunlit ground's own
	// light (ground_albedo, the sun's colour and energy on level ground), except in the haze's forward glow toward
	// the sun. The horizon's blue-grey there lit the undersides blue. Down to 6° (the far ground and sea, whose fog
	// takes this colour) the haze's own. With a low sun (below 17°) the haze's own all the way down: gold toward the
	// sun, blue-grey away from it; Godot's fog takes a blurred level of this map, and the dim ground in it turned the
	// sea and the land a flat mauve-brown at sunset.
	float glow = pow(max(mu, 0.0), 4.0);
	vec3 ground = ground_albedo * LIGHT0_COLOR * LIGHT0_ENERGY * max(s.y, 0.0);
	col = mix(col, ground, smoothstep(-0.1, -0.5, EYEDIR.y) * (1.0 - glow) * smoothstep(0.05, 0.3, s.y));
	COLOR = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), overcast);
}
