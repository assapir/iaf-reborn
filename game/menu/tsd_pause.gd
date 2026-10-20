# The FlyTSD's Ctrl+P pause (docs/front-end.md §16.1, FUN_004edbc0 / FUN_004e92b0): a snapshot of the window
# dithered with menu/bmp/misc/pat1.bmp (SRCAND) and pat2.bmp (SRCPAINT), and over it "II  PAUSE" blinking 500 ms
# on / 500 ms off. It covers the window and takes every mouse event (the frame window is disabled while paused).
extends Control

const Gdi := preload("res://util/gdi.gd")
const Overlay := preload("res://terrain/flight_overlay.gd")

## Per channel in the original's 640×480 pixels: (snapshot AND pat1) OR pat2.
const SHADER := """
shader_type canvas_item;
uniform sampler2D snap : filter_nearest;
uniform sampler2D pat1 : filter_nearest;
uniform sampler2D pat2 : filter_nearest;
uniform vec2 view_size;
uniform vec2 origin;
uniform float scale;
uniform float art_scale;
void fragment() {
	vec2 px = floor((UV * view_size - origin) / scale);
	ivec2 cell = ivec2(mod(px, vec2(640.0, 480.0)));
	ivec2 at = cell * int(art_scale) + ivec2(int(art_scale) / 2);
	uvec3 s = uvec3(round(texture(snap, UV).rgb * 255.0));
	uvec3 a = uvec3(round(texelFetch(pat1, at, 0).rgb * 255.0));
	uvec3 o = uvec3(round(texelFetch(pat2, at, 0).rgb * 255.0));
	COLOR = vec4(vec3((s & a) | o) / 255.0, 1.0);
}
"""

var fe: Control
var _font: SystemFont
var _picture: ColorRect
var _text: Control


func setup(front_end: Control, snapshot: Image) -> void:
	fe = front_end
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = Gdi.arial(Overlay.PAUSE_WEIGHT)
	if snapshot == null or snapshot.is_empty():
		snapshot = Image.create(640, 480, false, Image.FORMAT_RGB8)  # a headless run renders nothing
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	mat.set_shader_parameter("snap", ImageTexture.create_from_image(snapshot))
	mat.set_shader_parameter("pat1", fe._tex("misc/pat1.png"))
	mat.set_shader_parameter("pat2", fe._tex("misc/pat2.png"))
	mat.set_shader_parameter("art_scale", float(fe.art_scale))
	_picture = ColorRect.new()
	_picture.material = mat
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)
	_text = Control.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text.draw.connect(_draw_text)
	add_child(_text)


func _process(_delta: float) -> void:
	var mat := _picture.material as ShaderMaterial
	mat.set_shader_parameter("view_size", size)
	mat.set_shader_parameter("origin", fe._origin())
	mat.set_shader_parameter("scale", fe._scale())
	_text.queue_redraw()


## Whether "II  PAUSE" shows now (the 500 ms blink).
static func text_on() -> bool:
	return (Time.get_ticks_msec() / Overlay.PAUSE_BLINK_MS) % 2 == 0


## "II  PAUSE" with TA_BOTTOM|TA_LEFT at (30, 450) of the 640×480 frame.
func _draw_text() -> void:
	if text_on():
		_text.draw_set_transform(fe._origin())
		Gdi.text_out(
			_text,
			_font,
			Overlay.PAUSE_WEIGHT,
			Overlay.PAUSE_TEXT,
			Gdi.ppem(50, Overlay.PAUSE_WEIGHT),
			Overlay.PAUSE_POS.x,
			Overlay.PAUSE_POS.y,
			fe._scale(),
			Overlay.PAUSE_COLOUR,
			false,
			true
		)
