# Shown while the flight waits for its ground (terrain_view.gd `waiting_for_ground`): the front
# end's mission-load screen, scaled like the menus: the menu background with the progress window
# in the content window (FUN_004edec0 shows Mis\Wait.bmp, then the progress bar FUN_0053d040 /
# FUN_0053d1b0 paints Mis\PBBack.bmp over it with PBBar filled to the progress and the PBSlider
# knob at its end). Progress = terrain.gd ground_progress() (the ground_ready() work), smoothed
# and never going back.
extends Control

const W := 640.0
const H := 480.0
## The front end's content window (front_end.gd CONTENT).
const CONTENT_POS := Vector2(155, 42)
## The bar inside PBBack (0x60c5e0: x, y, width 400, height 15); the knob starts 6 px left of the
## fill's end.
const BAR_POS := Vector2(26, 172)
const BAR_SIZE := Vector2(400, 15)
const KNOB_BACK := 6.0
## Smoothing of the shown progress (per second, exponential).
const SMOOTH := 8.0

## Progress 0..1 (set by the flight every frame).
var progress := 0.0
var _shown := 0.0
var _target := 0.0
var _back: Texture2D
var _wait: Texture2D
var _pb_back: Texture2D
var _pb_bar: Texture2D
var _knob: Texture2D
var _art_scale := 1.0
## Ours: the credit lines the picked imagery layers require (CC BY, docs/imagery.md §6), at the bottom.
var _credits: Array[String] = []


func _ready() -> void:
	# Full-rect offsets too: anchors alone left the control 0 × 0 (nothing was drawn).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dir := Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var scale_file := dir.path_join("image_scale.txt")
	_art_scale = float(FileAccess.get_file_as_string(scale_file).strip_edges()) if FileAccess.file_exists(scale_file) else 1.0
	_credits = preload("res://terrain/imagery_layers.gd").attributions()
	var Img := preload("res://util/img.gd")
	_back = Img.load_texture(dir.path_join("img/back.png"), true)
	_wait = Img.load_texture(dir.path_join("img/mis/wait.png"), true)
	_pb_back = Img.load_texture(dir.path_join("img/mis/pbback.png"), true)
	_pb_bar = Img.load_texture(dir.path_join("img/mis/pbbar.png"), true)
	var knob := Image.load_from_file(dir.path_join("img/mis/pbslider.png")) if FileAccess.file_exists(dir.path_join("img/mis/pbslider.png")) else null
	if knob != null:
		# Top half the knob, bottom half its AND mask (SRCAND + SRCPAINT in FUN_0053d1b0).
		var k := Img.masked_sprite(knob)
		k.generate_mipmaps()
		_knob = ImageTexture.create_from_image(k)


func _process(delta: float) -> void:
	_target = maxf(_target, clampf(progress, 0.0, 1.0))
	var s := _shown + (_target - _shown) * (1.0 - exp(-SMOOTH * delta))
	if absf(s - _shown) > 0.0005 or _shown == 0.0:
		_shown = s
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var s := minf(size.x / W, size.y / H)
	var origin := (size - Vector2(W, H) * s) / 2.0
	var content := _pb_back if _pb_back != null else _wait
	for t in [[_back, Vector2.ZERO], [content, CONTENT_POS]]:
		if t[0] != null:
			draw_texture_rect(t[0], Rect2(origin + t[1] * s, t[0].get_size() / _art_scale * s), false)
	var fs := int(round(9.0 * s))
	for i in _credits.size():
		var y := origin.y + (H - 6.0 - 11.0 * (_credits.size() - 1 - i)) * s
		draw_string(ThemeDB.fallback_font, Vector2(origin.x + 8.0 * s, y), _credits[i], HORIZONTAL_ALIGNMENT_LEFT, (W - 16.0) * s, fs, Color8(0, 200, 0))
	if _pb_back == null or _pb_bar == null:
		return
	var bar := CONTENT_POS + BAR_POS
	var fill := roundf(BAR_SIZE.x * _shown)
	if fill > 0.0:
		var src := Rect2(Vector2.ZERO, Vector2(fill, BAR_SIZE.y) * _art_scale)
		draw_texture_rect_region(_pb_bar, Rect2(origin + bar * s, Vector2(fill, BAR_SIZE.y) * s), src)
	if _knob != null:
		# Clipped to the bar's left edge (the original composes bar and knob in a bitmap starting there).
		var ks := _knob.get_size() / _art_scale
		var cut := maxf(0.0, KNOB_BACK - fill)
		draw_texture_rect_region(_knob, Rect2(origin + (bar + Vector2(fill - KNOB_BACK + cut, 0)) * s,
				Vector2(ks.x - cut, ks.y) * s), Rect2(Vector2(cut, 0) * _art_scale, (ks - Vector2(cut, 0)) * _art_scale))
