# In-flight message box (CIAFMenuMsgBoxDlg, docs/front-end.md §3.3): mbgback.bmp 320x140 centred
# on the 640x480 screen, msgs.trx text (Arial bold, white, centred), buttons from the menu art:
# "deb" DEBRIEF, "fly" CONTINUE, "exit" EXIT, "yes"/"no".
extends Control

const Img := preload("res://util/img.gd")

signal chosen(button: String)

const SIZE := Vector2(320, 140)
const BUTTON := Vector2(60, 30)

var text := ""
var buttons: Array = []
var pressed := -1
var dir := ""
var textures := {}
var font: SystemFont


func setup(msg: int, button_names: Array) -> void:
	buttons = button_names
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	dir = Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var lines: PackedStringArray = String(Settings.load_json(dir.path_join("strings.json")).get("msgs", "")).split("\n")
	text = lines[msg].strip_edges() if msg < lines.size() else ""
	font = Img.arial(700)


func _tex(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = Img.load_texture(dir.path_join("img").path_join(path))
	return textures[path]


func _scale() -> float:
	return size.y / 480.0


func _origin() -> Vector2:
	var s := _scale()
	return Vector2(size.x / 2, size.y / 2) - SIZE / 2 * s


## Buttons: one centred, two at W/2 - bw - bw/4 and W/2 + bw/4, three spread; top at H - 5/3 bh.
func _rects() -> Array:
	var s := _scale()
	var y := SIZE.y - BUTTON.y * 5.0 / 3.0
	var xs: Array
	match buttons.size():
		1: xs = [SIZE.x / 2 - BUTTON.x / 2]
		2: xs = [SIZE.x / 2 - BUTTON.x - BUTTON.x / 4, SIZE.x / 2 + BUTTON.x / 4]
		_: xs = [SIZE.x / 2 - BUTTON.x * 1.5 - BUTTON.x / 4, SIZE.x / 2 - BUTTON.x / 2, SIZE.x / 2 + BUTTON.x / 2 + BUTTON.x / 4]
	var out := []
	for x in xs:
		out.append(Rect2(_origin() + Vector2(x, y) * s, BUTTON * s))
	return out


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := _scale()
	var o := _origin()
	var back := _tex("misc/mbgback.png")
	if back != null:
		draw_texture_rect(back, Rect2(o, SIZE * s), false)
	var fs := int(round(12 * s))
	draw_multiline_string(font, o + Vector2(10, 20) * s + Vector2(0, font.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_CENTER, (SIZE.x - 20) * s, fs, 4, Color.WHITE)
	var rects := _rects()
	for i in rects.size():
		var t := _tex("misc/mbg%s_%d.png" % [buttons[i], 2 if pressed == i else 0])
		if t != null:
			draw_texture_rect(t, rects[i], false)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var hit := -1
	var rects := _rects()
	for i in rects.size():
		if rects[i].has_point(event.position):
			hit = i
	if event.pressed:
		pressed = hit
	elif hit >= 0 and hit == pressed:
		chosen.emit(buttons[hit])
	else:
		pressed = -1
	accept_event()
