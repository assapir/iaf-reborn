// Extras "Sky: Atmospheric" (render_options.gd, docs/rendering.md): single scattering of the sun's light by air
// (Rayleigh, λ⁻⁴ coefficients at sea level) and haze (Mie, Henyey-Greenstein phase), with the optical depths of
// an exponential atmosphere approximated by the air mass along the view and the sun ray (Kasten-Young), the sun's
// disc dimmed by its own air mass. The fog takes its colour from this sky (aerial perspective), so the distance
// haze matches it. Directions: Godot's sky EYEDIR / LIGHT0_DIRECTION (towards the sun).
shader_type sky;

uniform float exposure = 30.0;
// Haze: Mie scattering at sea level (1/m), a little above clear air's 2.1e-5.
uniform float mie = 2.5e-5;
uniform float mie_g = 0.85;
uniform float sun_disc_deg = 0.55;
uniform vec3 ground = vec3(0.36, 0.34, 0.3);

const vec3 RAYLEIGH = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const float H_R = 8000.0;  // scale heights (m)
const float H_M = 1200.0;

float air_mass(float cos_zenith) {
	float c = max(cos_zenith, 0.0);
	float z = degrees(acos(c));
	return 1.0 / (c + 0.50572 * pow(max(96.07995 - z, 0.001), -1.6364));
}

void sky() {
	vec3 v = EYEDIR;
	vec3 s = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float mu = dot(v, s);
	// Below the horizon: the view ends on the ground; its air is the horizon's.
	float vy = max(v.y, 0.0);
	vec3 tau_sun = (RAYLEIGH * H_R + mie * H_M) * air_mass(s.y);
	vec3 sun_t = exp(-tau_sun);
	vec3 tau_view = (RAYLEIGH * H_R + mie * H_M) * air_mass(vy);
	float phase_r = 0.0596831 * (1.0 + mu * mu);
	float g2 = mie_g * mie_g;
	float phase_m = 0.0795775 * (1.0 - g2) / pow(1.0 + g2 - 2.0 * mie_g * mu, 1.5);
	vec3 beta = RAYLEIGH * H_R + mie * H_M;
	vec3 scatter = (RAYLEIGH * H_R * phase_r + mie * H_M * phase_m) / beta;
	vec3 col = exposure * scatter * (1.0 - exp(-tau_view)) * sun_t * max(s.y + 0.1, 0.0) / 1.1;
	// The sun's disc.
	float disc = smoothstep(cos(radians(sun_disc_deg * 0.5)), cos(radians(sun_disc_deg * 0.4)), mu);
	col += disc * sun_t * exp(-tau_view) * 40.0 * float(v.y > -0.01);
	if (v.y < 0.0) {
		col = mix(col, ground * max(s.y, 0.0) * sun_t * 1.5, smoothstep(0.0, -0.08, v.y));
	}
	COLOR = col;
}
