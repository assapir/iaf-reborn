// Ours, the 3D cockpit (cockpit3d.gd): the HUD drawn only inside the combiner glass's outline seen from the eye
// (cockpit.gd hud_clip): a convex polygon in screen UV, up to 16 corners; `count` 0 draws everywhere (the helmet
// display), -1 nothing (the glass out of sight).
shader_type canvas_item;

uniform int count = 0;
uniform vec2 corners[16];

void fragment() {
	if (count < 0) {
		discard;
	}
	if (count >= 3) {
		float side = 0.0;
		for (int i = 0; i < count; i++) {
			vec2 a = corners[i];
			vec2 b = corners[(i + 1) % count];
			float c = (b.x - a.x) * (SCREEN_UV.y - a.y) - (b.y - a.y) * (SCREEN_UV.x - a.x);
			if (side == 0.0) {
				side = sign(c);
			} else if (c * side < 0.0) {
				discard;
			}
		}
	}
}
