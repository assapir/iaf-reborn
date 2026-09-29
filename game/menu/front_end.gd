# The original Jane's IAF front end, rebuilt from the converted menu data
# (`iaf-convert menu`): screens and lists from menus.json, strings from strings.json,
# original art and TrueType fonts. Laid out in the original 640x480 space, scaled to the
# window height and centred (pillarboxed on wide screens).
extends Control

const W := 640.0
const H := 480.0
const TEXT := Color(0.62, 0.95, 0.62)
const TEXT_HOVER := Color(1.0, 1.0, 0.75)
const TEXT_DISABLED := Color(0.35, 0.45, 0.35)
const BOX := Color(0.5, 1.0, 0.5, 0.18)
## Font sizes in the original 640x480 space (scaled with the window).
const SIZE_BUTTON := 17.0
const SIZE_TITLE := 16.0
const SIZE_TEXT := 13.0
const SIZE_HEADING := 20.0

## Where each main-menu entry goes; missing entries are shown disabled for now.
const MAIN_TARGETS := {"Training": "training", "Preferences": "pref"}
## Our own settings, shown on the Preferences screen's "Gameplay" page.
const PREF_PAGES := ["Graphics", "Sound", "Controls", "Devices", "Gameplay"]

var menus := {}
var strings := {}
## Our Hebrew translation (used when Settings.language == "he").
var hebrew := {}
var textures := {}
var font_button: FontFile
var font_text: FontFile
var dir := ""

var screen := "main"
var history: Array[String] = []
var hover := -1  # left button under the mouse
var hover_row := -1
var selected_row := -1
var pref_page := "Gameplay"
var pressed: Callable  # hotspot under a held mouse button (for pressed-state art)
var hotspots: Array = []  # [Rect2 (screen px), Callable]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	dir = Settings.assets_dir().path_join("converted/menu")
	menus = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("menus.json")))
	strings = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("strings.json")))
	if menus == null:
		push_error("front end: run `iaf-convert --upscale menu assets/install assets/converted/menu`")
		menus = {}
		strings = {}
	hebrew = JSON.parse_string(FileAccess.get_file_as_string("res://menu/strings_he.json"))
	font_button = _font("cr1.ttf")
	font_text = _font("cr0.ttf")
	var args := OS.get_cmdline_user_args()
	var at := args.find("--menu")
	if at >= 0:
		screen = args[at + 1]
	var shot := args.find("--screenshot")
	if shot >= 0:
		for i in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args[shot + 1])
		get_tree().quit()


func _font(file: String) -> FontFile:
	var f := FontFile.new()
	f.load_dynamic_font(dir.path_join(file))
	# The original fonts have no Hebrew letters: fall back to a system Hebrew font.
	var hebrew_font := SystemFont.new()
	hebrew_font.font_names = PackedStringArray(["Noto Sans Hebrew", "Arial Hebrew", "Arial", "DejaVu Sans"])
	f.fallbacks = [hebrew_font]
	return f


func _he() -> bool:
	return Settings.language == "he"


## A UI label in the current language.
func _t(english: String) -> String:
	return hebrew.get("labels", {}).get(english, english) if _he() else english


func _tex(path: String) -> Texture2D:
	if not textures.has(path):
		var img := Image.load_from_file(dir.path_join("img").path_join(path))
		if img != null:
			img.generate_mipmaps()
		textures[path] = ImageTexture.create_from_image(img) if img != null else null
	return textures[path]


func _scale() -> float:
	return min(size.x / W, size.y / H)


## Original 640x480 coordinates -> window pixels.
func _to_screen(p: Vector2) -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) / 2.0, (size.y - H * s) / 2.0) + p * s


func _rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(_to_screen(Vector2(x, y)), Vector2(w, h) * _scale())


func _string(key: String) -> String:
	var k := key.to_lower()
	if _he() and hebrew.get("strings", {}).has(k):
		return hebrew.strings[k]
	return strings.get(k, "")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	hotspots.clear()
	var s := _scale()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.06))
	var back := _tex("back0.png")
	if back != null:
		draw_texture_rect(back, _rect(0, 0, W, H), false)
	var def: Dictionary = menus.get(screen, {})
	if def.is_empty():
		return
	var win: Array = def.window
	var content := _rect(win[0], win[1], win[2] - win[0], win[3] - win[1])
	var bg := _content_background()
	if bg != null:
		draw_texture_rect(bg, content, false)

	# Left column buttons.
	var i := 0
	for panel in def.panels:
		for b in panel.buttons:
			var r: Array = b.rect
			var rect := _rect(panel.pos[0] + r[0], panel.pos[1] + r[1], r[2], r[3])
			var enabled := _button_enabled(b.label)
			var color := TEXT_DISABLED if not enabled else (TEXT_HOVER if i == hover or _is_current(b.label) else TEXT)
			_text_in(rect, _t(b.label), font_button, int(SIZE_BUTTON * s), color, HORIZONTAL_ALIGNMENT_CENTER)
			if enabled:
				hotspots.append([rect, _on_button.bind(b.label)])
			i += 1

	# Content: list rows, or our preference page.
	if screen == "pref":
		_draw_prefs(content, s)
	else:
		_draw_list(def, win, s)

	# Bottom bar: the original BACK tab and CONTINUE button art (normal / hover / pressed).
	var mouse := get_local_mouse_position()
	if screen != "main":
		var back_rect := _rect(10, 446, 114, 22)
		var state := 2 if pressed == _go_back else (1 if back_rect.has_point(mouse) else 0)
		_draw_art("misc/backbut_%d.png" % state, back_rect)
		hotspots.append([back_rect, _go_back])
	if _mission_selected() >= 0:
		var fly_rect := _rect(530, 441, 60, 30)
		var state := 2 if pressed == _fly or fly_rect.has_point(mouse) else 0
		_draw_art("misc/mbgfly_%d.png" % state, fly_rect)
		hotspots.append([fly_rect, _fly])


func _draw_art(path: String, rect: Rect2) -> void:
	var t := _tex(path)
	if t != null:
		draw_texture_rect(t, rect, false)


func _content_background() -> Texture2D:
	if screen == "main":
		return _tex("main/main_%d.png" % clampi(hover + 1, 1, 8))
	if screen == "pref":
		return _tex("screens/sgeneral.png")
	return _tex("mis/mis_0.png")


func _draw_list(_def: Dictionary, win: Array, s: float) -> void:
	var list: Dictionary = menus.get("s" + screen, {})
	if list.get("type", "") != "list":
		return
	var rows: Array = list.rows
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var rr: Array = row.rect
		var rect := _rect(win[0] + rr[0], win[1] + rr[1], rr[2], rr[3])
		if ri == selected_row or ri == hover_row:
			draw_rect(rect, BOX if ri == selected_row else Color(BOX, 0.08))
		var tb: Array = row.title_box
		var db: Array = row.desc_box
		var title := _string(row.title_key)
		if title == "":
			title = _t(row.name)
		_text_in(_rect(win[0] + tb[0], win[1] + tb[1], tb[2] - tb[0], tb[3] - tb[1]), title, font_button, int(SIZE_TITLE * s), TEXT_HOVER)
		_text_block(_rect(win[0] + db[0], win[1] + db[1], db[2] - db[0], db[3] - db[1]), _string(row.desc_key), int(SIZE_TEXT * s), TEXT)
		hotspots.append([rect, _on_row.bind(ri, row)])


func _draw_prefs(content: Rect2, s: float) -> void:
	var fs := int(SIZE_TEXT * s)
	var x := content.position.x + 30 * s
	var y := content.position.y + 50 * s
	var width := content.size.x - 60 * s
	var start := HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	_text_in(Rect2(x, y - 30 * s, width, 20 * s), _t(pref_page).to_upper(), font_button, int(SIZE_HEADING * s), TEXT_HOVER, start)
	if pref_page != "Gameplay":
		_text_in(Rect2(x, y, width, 20 * s), _t("(not available yet)"), font_text, fs, TEXT_DISABLED, start)
		return
	var options := [
		["Flight data", [["Original (Jane's IAF 1998)", "original"], ["Real F-16", "real"]], "flight_data"],
		["Language", [["English", "en"], ["Hebrew", "he"]], "language"],
	]
	# Hebrew mirrors the page: labels on the right, choices flowing leftwards.
	var rtl := _he()
	for opt in options:
		_text_in(Rect2(x, y, width, 20 * s), _t(opt[0]), font_text, fs, TEXT, start)
		var ox := x + width - 150 * s if rtl else x + 150 * s
		for choice in opt[1]:
			var value: String = choice[1]
			var label := _t(choice[0])
			var available: bool = not (value == "he" and not Settings.hebrew_available())
			var current: bool = Settings.get(opt[2]) == value
			var w: float = font_text.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16 * s
			var r := Rect2(ox - w if rtl else ox, y - 2 * s, w, 22 * s)
			if current:
				draw_rect(r, BOX)
			_text_in(r, label, font_text, fs, TEXT_HOVER if current else (TEXT if available else TEXT_DISABLED))
			if available:
				hotspots.append([r, _set_pref.bind(opt[2], value)])
			ox += -(w + 10 * s) if rtl else w + 10 * s
		y += 36 * s


func _text_in(rect: Rect2, text: String, font: Font, fs: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	# Shrink to fit (long labels, Hebrew) instead of clipping.
	while fs > 6 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x:
		fs -= 1
	var asc := font.get_ascent(fs)
	var h := font.get_height(fs)
	var pos := Vector2(rect.position.x + (0.0 if align != HORIZONTAL_ALIGNMENT_CENTER else 0.0), rect.position.y + (rect.size.y - h) / 2.0 + asc)
	draw_string(font, pos, text, align, rect.size.x, fs, color)


func _text_block(rect: Rect2, text: String, fs: int, color: Color) -> void:
	var align := HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	draw_multiline_string(font_text, rect.position + Vector2(0, font_text.get_ascent(fs)), text, align, rect.size.x, fs, 3, color)


func _button_enabled(label: String) -> bool:
	match screen:
		"main":
			return MAIN_TARGETS.has(label)
		"pref":
			return true
		_:
			return true


func _is_current(label: String) -> bool:
	return screen == "pref" and label == pref_page


func _mission_selected() -> int:
	var list: Dictionary = menus.get("s" + screen, {})
	if selected_row < 0 or list.get("type", "") != "list":
		return -1
	return int(list.rows[selected_row].id)


func _navigate(to: String) -> void:
	if not menus.has(to):
		return
	history.append(screen)
	screen = to
	selected_row = -1
	hover = -1


func _go_back() -> void:
	if not history.is_empty():
		screen = history.pop_back()
		selected_row = -1


func _on_button(label: String) -> void:
	match screen:
		"main":
			_navigate(MAIN_TARGETS.get(label, ""))
		"pref":
			pref_page = label
		_:
			# A left button mirrors a list row: pick that row (or open its screen).
			var list: Dictionary = menus.get("s" + screen, {})
			for ri in list.get("rows", []).size():
				if list.rows[ri].name.to_lower() == label.to_lower():
					_on_row(ri, list.rows[ri])
					return


func _on_row(index: int, row: Dictionary) -> void:
	if int(row.id) >= 0:
		selected_row = index
		return
	# Rows without a mission id open a sub-screen named after their first word ("Basic Course" -> basic).
	var target: String = String(row.name).split(" ")[0].to_lower()
	_navigate(target)


func _set_pref(key: String, value: String) -> void:
	Settings.set(key, value)
	Settings.save()


func _fly() -> void:
	Settings.mission_id = _mission_selected()
	get_tree().change_scene_to_file("res://terrain/terrain_view.tscn")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = -1
		hover_row = -1
		var i := 0
		var def: Dictionary = menus.get(screen, {})
		for panel in def.get("panels", []):
			for b in panel.buttons:
				var r: Array = b.rect
				if _rect(panel.pos[0] + r[0], panel.pos[1] + r[1], r[2], r[3]).has_point(event.position):
					hover = i
				i += 1
		var list: Dictionary = menus.get("s" + screen, {})
		if list.get("type", "") == "list" and def.has("window"):
			var win: Array = def.window
			for ri in list.rows.size():
				var rr: Array = list.rows[ri].rect
				if _rect(win[0] + rr[0], win[1] + rr[1], rr[2], rr[3]).has_point(event.position):
					hover_row = ri
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Act on release, like the original buttons; remember the press for pressed-state art.
		for h in hotspots:
			if h[0].has_point(event.position):
				if event.pressed:
					pressed = h[1]
				elif pressed == h[1]:
					pressed = Callable()
					h[1].call()
					return
		if not event.pressed:
			pressed = Callable()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if history.is_empty():
			get_tree().quit()
		else:
			_go_back()
