// The combiner glass's outline seen from the eye (cockpit.gd hud_clip): a polygon in screen UV, its corners in order,
// up to 32 (the Sufa's plate follows its curved posts, so not convex: an even-odd test); `count` 0 everywhere (the
// helmet display), -1 nowhere (the glass out of sight). hud_glass.gdshader and hud_flir.gdshader.
uniform int count = 0;
uniform vec2 corners[32];

bool on_glass(vec2 p) {
	if (count < 0) {
		return false;
	}
	if (count < 3) {
		return true;
	}
	bool inside = false;
	for (int i = 0; i < count; i++) {
		vec2 a = corners[i];
		vec2 b = corners[(i + 1) % count];
		if ((a.y > p.y) != (b.y > p.y) && p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)) {
			inside = !inside;
		}
	}
	return inside;
}
