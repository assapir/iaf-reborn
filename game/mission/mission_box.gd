# The original message box (CIAFMenuMsgBoxDlg, docs/front-end.md §3.3), in the menus and in flight:
# mbgback.bmp 320x140 centred on the 640x480 screen (scaled to fit), msgs.trx text (Arial bold,
# white, centred), buttons from the menu art: "yes" / "no" / "can" (Cancel), "ok", "deb" DEBRIEF,
# "fly" CONTINUE, "exit" EXIT. It covers its parent and takes every click until a button is chosen.
extends Control

signal chosen(button: String)

const Img := preload("res://util/img.gd")
const SIZE := Vector2(320, 140)
const BUTTON := Vector2(60, 30)

var text := ""
var buttons: Array = []
var pressed := -1
## Called with "buttonin" / "buttonout" on a button press / release (the menus play those sounds).
var on_click: Callable
var dir := ""
var textures := {}
var font: SystemFont


func setup(msg: int, button_names: Array) -> void:
	buttons = button_names
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	dir = Settings.assets_dir().path_join("converted/menu_he" if Settings.language == "he" else "converted/menu")
	var lines := Settings.msgs()
	text = lines[msg].strip_edges() if msg < lines.size() else ""
	font = Img.arial(700)


func _tex(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = Img.load_texture(dir.path_join("img").path_join(path), true)
	return textures[path]


## The 640x480 screen scaled to fit and centred, as the menus.
func _scale() -> float:
	return minf(size.x / 640.0, size.y / 480.0)


func _origin() -> Vector2:
	return size / 2 - SIZE / 2 * _scale()


## Button x in the box, top at H - 5/3 bh: one centred; two at W/2 - bw - bw/4 and W/2 + bw/4;
## Yes / No / Cancel (type 3, 4e4480) at W/2 - 2 bw, W/2 - bw/2 and W/2 + bw; the other three-button
## box (DEBRIEF / CONTINUE / EXIT) spread by a quarter button.
func button_xs() -> Array:
	var bw := BUTTON.x
	var cx := SIZE.x / 2
	match buttons.size():
		1:
			return [cx - bw / 2]
		2:
			return [cx - bw - bw / 4, cx + bw / 4]
	if buttons == ["yes", "no", "can"]:
		return [cx - 2 * bw, cx - bw / 2, cx + bw]
	return [cx - bw * 1.5 - bw / 4, cx - bw / 2, cx + bw / 2 + bw / 4]


## The button rects on screen (this control's coordinates).
func rects() -> Array:
	var s := _scale()
	var y := SIZE.y - BUTTON.y * 5.0 / 3.0
	var out := []
	for x in button_xs():
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
	var r := rects()
	for i in r.size():
		var t := _tex("misc/mbg%s_%d.png" % [buttons[i], 2 if pressed == i else 0])
		if t != null:
			draw_texture_rect(t, r[i], false)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var hit := -1
	var r := rects()
	for i in r.size():
		if r[i].has_point(event.position):
			hit = i
	if event.pressed:
		pressed = hit
		if hit >= 0 and on_click.is_valid():
			on_click.call("buttonin")
	elif hit >= 0 and hit == pressed:
		if on_click.is_valid():
			on_click.call("buttonout")
		chosen.emit(buttons[hit])
	else:
		pressed = -1
	accept_event()
