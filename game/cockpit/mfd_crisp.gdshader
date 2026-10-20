// Ours ("Better cockpit" crisp_mfd): an MFD page with its pixel art drawn sharp (mfd_crisp.gdshaderinc).
shader_type canvas_item;

#include "res://cockpit/mfd_crisp.gdshaderinc"

varying vec4 modulate;


void vertex() {
	modulate = COLOR;
}


void fragment() {
	COLOR = iaf_crisp(TEXTURE, UV, COLOR, modulate);
}
