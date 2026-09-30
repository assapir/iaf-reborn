# Shown while the flight waits for its ground (terrain_view.gd `waiting_for_ground`): the front
# end's mission wait screen (menu background with wait.bmp in the content window, as during the
# mission load, FUN_004edec0), scaled like the menus.
extends Control

const W := 640.0
const H := 480.0
## The front end's content window (front_end.gd CONTENT).
const CONTENT_POS := Vector2(155, 42)

var _back: Texture2D
var _wait: Texture2D
var _art_scale := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dir := Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var scale_file := dir.path_join("image_scale.txt")
	_art_scale = float(FileAccess.get_file_as_string(scale_file).strip_edges()) if FileAccess.file_exists(scale_file) else 1.0
	var Img := preload("res://util/img.gd")
	_back = Img.load_texture(dir.path_join("img/back.png"), true)
	_wait = Img.load_texture(dir.path_join("img/mis/wait.png"), true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var s := minf(size.x / W, size.y / H)
	var origin := (size - Vector2(W, H) * s) / 2.0
	for t in [[_back, Vector2.ZERO], [_wait, CONTENT_POS]]:
		if t[0] != null:
			draw_texture_rect(t[0], Rect2(origin + t[1] * s, t[0].get_size() / _art_scale * s), false)
