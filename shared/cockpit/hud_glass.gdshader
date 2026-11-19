// Ours, the 3D cockpit (cockpit3d.gd): the HUD drawn only inside the combiner glass's outline seen from the eye
// (hud_glass.gdshaderinc).
shader_type canvas_item;

#include "res://shared/cockpit/hud_glass.gdshaderinc"

void fragment() {
	if (!on_glass(SCREEN_UV)) {
		discard;
	}
}
