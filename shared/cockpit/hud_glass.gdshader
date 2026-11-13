// Ours, the 3D cockpit (cockpit3d.gd): the HUD drawn only inside the combiner glass's outline seen from the eye
// (cockpit.gd hud_clip): a polygon in screen UV, its corners in order, up to 32 (the Sufa's plate follows its curved
// posts, so not convex: an even-odd test); `count` 0 draws everywhere (the helmet display), -1 nothing (the glass out
// of sight).
shader_type canvas_item;

uniform int count = 0;
uniform vec2 corners[32];

void fragment() {
	if (count < 0) {
		discard;
	}
	if (count >= 3) {
		bool inside = false;
		vec2 p = SCREEN_UV;
		for (int i = 0; i < count; i++) {
			vec2 a = corners[i];
			vec2 b = corners[(i + 1) % count];
			if ((a.y > p.y) != (b.y > p.y) && p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)) {
				inside = !inside;
			}
		}
		if (!inside) {
			discard;
		}
	}
}
