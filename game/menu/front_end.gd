# The original Jane's IAF front end (docs/front-end.md), rebuilt from the converted menu data
# (`iaf-convert menu`): screens, panels and lists from menus.json, text from strings.json,
# original art and sounds. Everything is laid out in the original 640x480 space, scaled to the
# window height and centred (pillarboxed on wide screens).
extends Control

const W := 640.0
const H := 480.0
## Content window (FUN_004e7560).
const CONTENT := Rect2(155, 42, 453, 357)
## Fixed frame pieces (docs/front-end.md §2, §3.2).
const TITLE_POS := Vector2(485, 16)
const UPCLIP_POS := Vector2(17, 18)
const LOWCLIP_POS := Vector2(17, 433)
const BACK_POS := Vector2(0, 458)
const MAIN_POS := Vector2(605, 421)
## Title tab frames are 50 ms apart.
const TITLE_FRAME := 0.05

## Arial sizes (FUN_004ed600: em = cy * p / 100 with cy = 112 for Arial) and list colours
## (FUN_00508590).
const LIST_TITLE_PX := 12.0
const LIST_DESC_PX := 11.0
const LIST_TITLE := Color8(0, 255, 0)
const LIST_DESC := Color8(0, 128, 0)
const LIST_DESC_LIT := Color8(0, 255, 0)
## Our preference page (not in the original) uses the same text style.
const PREF_TEXT := LIST_DESC_LIT
const PREF_DIM := LIST_DESC

## Button-release dispatcher FUN_004eaf50: screen -> {button label -> next screen}.
## Basic/Combat mission buttons go to the Jet list; Jet and campaign mission buttons load the
## mission (-> TSD).
const FORWARD := {
	"main": {"training": "training", "campaigns": "camp", "preferences": "pref",
		"missioncreator": "mc", "pilotrecords": "log", "reference": "ref", "multiplayer": "ctype"},
	"training": {"basiccourse": "basic", "combatcourse": "combat"},
	"camp": {"historical": "his", "future": "fut"},
	"his": {"sixdaywar": "his1mis", "yomkipurwar": "his2mis", "lebanonwar": "his3mis"},
	"fut": {"syrianfront": "fut1mis", "iraqifront": "fut2mis", "lebanesefront": "fut3mis"},
}
const TO_JET := ["basic", "combat"]
const LOADS_MISSION := ["jet", "his1mis", "his2mis", "his3mis", "fut1mis", "fut2mis", "fut3mis"]
## BACK (FUN_004eb990). The Jet list goes back to where it came from (screen 9 / 10).
const BACK := {"pref": "main", "ref": "main", "training": "main", "ctype": "main",
	"basic": "training", "combat": "training", "camp": "main", "mc": "main",
	"his": "camp", "fut": "camp", "his1mis": "his", "his2mis": "his", "his3mis": "his",
	"fut1mis": "fut", "fut2mis": "fut", "fut3mis": "fut", "tcp": "ctype", "ipx": "ctype"}
## BACK shows its disabled plate here; QUIT replaces MAIN on these (FUN_004e8a80).
const NO_BACK := ["log", "main", "deb", "jump"]
const QUIT_SCREENS := ["log", "main"]
## Screens with the blank lower clip plate (lowclipc).
const BLANK_CLIP := ["log", "main", "deb", "jump"]

## Jet buttons -> aircraft id (FUN_00508470, DAT_00836c90).
const JET_IDS := {"mirage": 6, "kfir": 5, "f4": 2, "f42000": 3, "f15": 0, "f16": 1, "lavi": 4}
## Jets the original disables per mission (FUN_005082b0), by aircraft id.
const JETS_DISABLED := {314: [6, 5], 322: [6, 5, 0], 323: [6, 5, 2, 0], 325: [6, 5, 2, 1, 4]}
## Aircraft this engine can fly so far (cockpit + flight model converted): F-16 only.
const FLYABLE_JETS := [1]

var menus := {}
var strings := {}
## Labels for our own settings page in Hebrew.
var hebrew := {}
var textures := {}
var dir := ""
## Converted art is stored at this multiple of the original pixel size.
var art_scale := 1.0
var font: SystemFont
var font_bold: SystemFont

var screen := "main"
## Where TSD and the Jet list return to.
var jet_parent := "basic"
## Transition state: left/bottom panels 0 = hidden .. 1 = shown; title tab frame 0..2.
var panel_shown := 1.0
var title_frame := 2
var busy := false
var loading := false
## Button animation frames by key "panel/button" (0 normal, 1 anim, 2 pressed, 3 disabled).
var frames := {}
var checked := {}
var held := ""  # key of the button the mouse is holding down
var hover_key := ""
var pref_page := "Gameplay"
var pref_hotspots: Array = []  # [Rect2 (menu coordinates), setting, value]

## TSD (screen 0x1e): the map/briefing node, where BACK returns to, and its check buttons,
## which persist while the mission is loaded (DAT_00836cd4..d1c, defaults FUN_004efc60).
var tsd: Control
var tsd_return := "jet"
var tsd_checks := {}
var briefings := {}
## Modal message box (§3.3): {text, buttons: [[art, Callable]], pressed: index}.
var msgbox := {}
var top_layer: Control

var music: AudioStreamPlayer
var sfx: AudioStreamPlayer
var sounds := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_menu_data()
	font = _arial(400)
	font_bold = _arial(700)
	music = AudioStreamPlayer.new()
	sfx = AudioStreamPlayer.new()
	add_child(music)
	add_child(sfx)
	top_layer = Control.new()
	top_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.draw.connect(_draw_msgbox)
	top_layer.gui_input.connect(_msgbox_input)
	add_child(top_layer)
	briefings = JSON.parse_string(FileAccess.get_file_as_string(Settings.assets_dir().path_join("converted/briefings/briefings.json")))
	if not (briefings is Dictionary):
		briefings = {}
	var args := OS.get_cmdline_user_args()
	var at := args.find("--menu")
	if at >= 0:
		screen = args[at + 1]
	# Back from a flight with a debrief (docs/mission-runtime.md §5.3).
	if not Settings.debrief.is_empty():
		screen = "deb"
	at = args.find("--mission")
	if at >= 0:
		Settings.mission_id = int(args[at + 1])
		_reset_tsd_checks()
	_enter_screen()
	_start_music()
	at = args.find("--hover")
	if at >= 0:
		hover_key = _key_for_label(args[at + 1])
	var shot := args.find("--screenshot")
	if shot >= 0:
		for i in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args[shot + 1])
		get_tree().quit()


## (Re)load screens, strings and art for the current language. Hebrew uses the Hebrew menu
## pack (assets/converted/menu_he, see docs/packs.md) when it is installed.
func _load_menu_data() -> void:
	dir = Settings.assets_dir().path_join("converted/menu_he" if _he() else "converted/menu")
	textures.clear()
	menus = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("menus.json")))
	strings = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("strings.json")))
	if menus == null:
		push_error("front end: run tools/setup.sh (menus not converted)")
		menus = {}
		strings = {}
	hebrew = JSON.parse_string(FileAccess.get_file_as_string("res://menu/strings_he.json"))
	var scale_file := dir.path_join("image_scale.txt")
	art_scale = float(FileAccess.get_file_as_string(scale_file).strip_edges()) if FileAccess.file_exists(scale_file) else 1.0
	sounds.clear()


## All menu text is Arial (docs/front-end.md §4); Liberation Sans is metric-compatible.
func _arial(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial", "Liberation Sans"])
	f.font_weight = weight
	return f


func _he() -> bool:
	return Settings.language == "he"


func _t(english: String) -> String:
	return hebrew.get("labels", {}).get(english, english) if _he() else english


func _string(key: String) -> String:
	return strings.get(key.to_lower(), "")


## Labels are compared without case, spaces or underscores ("Jump In" = "Jump_In").
static func _norm(label: String) -> String:
	return label.to_lower().replace(" ", "").replace("_", "")


# --- assets -----------------------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	if not textures.has(path):
		var img := Image.load_from_file(dir.path_join("img").path_join(path)) if FileAccess.file_exists(dir.path_join("img").path_join(path)) else null
		if img != null:
			img.generate_mipmaps()
		textures[path] = ImageTexture.create_from_image(img) if img != null else null
	return textures[path]


func _sound(name: String) -> AudioStreamWAV:
	if not sounds.has(name):
		var path := dir.path_join("wav/%s.wav" % name)
		sounds[name] = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	return sounds[name]


func _sound_length(name: String) -> float:
	var s := _sound(name)
	return s.get_length() if s != null else 0.15


func _play(name: String) -> void:
	var s := _sound(name)
	if s != null:
		sfx.stream = s
		sfx.play()


## Menu_M.wav loops on every screen except TSD / Arm (FUN_004e8a80).
func _start_music() -> void:
	if screen in ["tsd", "arm"] or music.playing:
		return
	var s := _sound("menu_m")
	if s == null:
		return
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	music.stream = s
	music.volume_db = 0.0
	music.play()


# --- screen model -----------------------------------------------------------------------

func _def() -> Dictionary:
	return menus.get(screen, {})


## The list shown in the content window: dat/<sName>.trx.
func _list() -> Dictionary:
	var l: Dictionary = menus.get(String(_def().get("name", "")).to_lower(), {})
	return l if l.get("type", "") == "list" else {}


func _panels() -> Array:
	return _def().get("panels", [])


func _button(key: String) -> Dictionary:
	var parts := key.split("/")
	if parts.size() != 2:
		return {}
	var panels := _panels()
	var p := int(parts[0])
	var b := int(parts[1])
	if p >= panels.size() or b >= panels[p].buttons.size():
		return {}
	return panels[p].buttons[b]


func _key_for_label(label: String) -> String:
	var panels := _panels()
	for p in panels.size():
		for b in panels[p].buttons.size():
			if _norm(panels[p].buttons[b].label) == _norm(label):
				return "%d/%d" % [p, b]
	return ""


func _enter_screen() -> void:
	frames.clear()
	checked.clear()
	if screen == "pref":
		checked[_key_for_label(pref_page)] = true
	if screen in ["tsd", "arm"]:
		_restore_tsd_checks()
	if screen == "tsd" and tsd == null:
		tsd = preload("res://menu/tsd.gd").new()
		add_child(tsd)
		move_child(top_layer, -1)
		tsd.setup(self, Settings.mission_id)
		if tsd_checks.get("player_flight", false):
			tsd_checks.erase("player_flight")
			var n: int = tsd.default_flight()
			if n >= 1 and n <= 4:
				tsd_checks[["alpha", "bravo", "charlie", "delta"][n - 1]] = true
			_restore_tsd_checks()
		else:
			var n := _flight_number(_selected_flight())
			if n > 0:
				tsd.select_flight(n)
		# Briefing only when its file exists.
		tsd_checks["briefing"] = tsd_checks.get("briefing", false) and tsd.has_briefing()
		tsd.open_briefing(tsd_checks.briefing)
	elif screen != "tsd" and tsd != null:
		tsd.queue_free()
		tsd = null


## TSD defaults on mission load (FUN_004efc60): every unit filter, Text, Waypoint, Grid and
## Briefing on; the flight holding the player is selected when the TSD opens.
func _reset_tsd_checks() -> void:
	tsd_checks = {"waypoint": true, "text": true, "grid": true, "briefing": true, "player_flight": true}
	for kind in ["aircrafts", "vehicles", "ships", "samsites", "aaasites", "structures", "airports"]:
		for side in [1, 2]:
			tsd_checks["%s%d" % [kind, side]] = true


func _restore_tsd_checks() -> void:
	var panels := _panels()
	for p in panels.size():
		for b in panels[p].buttons.size():
			var btn: Dictionary = panels[p].buttons[b]
			if tsd_checks.get(_norm(btn.label), false) and btn.kind in ["Check", "CheckGroup"]:
				checked["%d/%d" % [p, b]] = true


func _button_enabled(label: String) -> bool:
	if screen == "jet":
		var id: int = JET_IDS.get(_norm(label), -1)
		if id in JETS_DISABLED.get(Settings.mission_id, []):
			return false
		return id in FLYABLE_JETS
	if screen == "tsd" and tsd != null:
		match _norm(label):
			"briefing":
				return tsd.has_briefing()
			"zoomin":
				return tsd.can_zoom_in()
			"zoomout":
				return tsd.can_zoom_out()
			"arm":
				return _selected_flight() != "" and tsd.flight_exists(_flight_number(_selected_flight()))
			"alpha", "bravo", "charlie", "delta":
				return tsd.flight_enabled(_flight_number(_norm(label)))
	return true


func _flight_number(name: String) -> int:
	return ["alpha", "bravo", "charlie", "delta"].find(name) + 1


func _selected_flight() -> String:
	for f in ["alpha", "bravo", "charlie", "delta"]:
		if tsd_checks.get(f, false):
			return f
	return ""


## Visible frame of a button: animation first, then checked / disabled.
func _frame(key: String, label: String) -> int:
	if not _button_enabled(label):
		return 3
	if frames.has(key):
		return frames[key]
	return 2 if checked.get(key, false) else 0


# --- drawing ----------------------------------------------------------------------------

func _scale() -> float:
	return min(size.x / W, size.y / H)


func _origin() -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) / 2.0, (size.y - H * s) / 2.0)


## Original 640x480 coordinates -> window pixels.
func _to_screen(p: Vector2) -> Vector2:
	return _origin() + p * _scale()


func _to_menu(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


func _rect(r: Rect2) -> Rect2:
	return Rect2(_to_screen(r.position), r.size * _scale())


func _art_size(t: Texture2D) -> Vector2:
	return Vector2(t.get_width(), t.get_height()) / art_scale


## Draw a whole image at its original size.
func _blit(path: String, pos: Vector2) -> void:
	var t := _tex(path)
	if t != null:
		draw_texture_rect(t, _rect(Rect2(pos, _art_size(t))), false)


## Draw part of an image (source in original pixels) at `dest` (original coordinates).
func _blit_region(path: String, src: Rect2, dest: Vector2) -> void:
	var t := _tex(path)
	if t != null:
		draw_texture_rect_region(t, _rect(Rect2(dest, src.size)), Rect2(src.position * art_scale, src.size * art_scale))


func _process(_delta: float) -> void:
	queue_redraw()
	top_layer.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	_blit("back.png", Vector2.ZERO)
	var def := _def()
	if def.is_empty():
		return
	_draw_content(def)
	_draw_panels()
	_draw_frame_pieces()
	# Pillarbox: hide sliding panels outside the 640x480 frame.
	var o := _origin()
	var sz := Vector2(W, H) * _scale()
	draw_rect(Rect2(0, 0, o.x, size.y), Color.BLACK)
	draw_rect(Rect2(o.x + sz.x, 0, size.x - o.x - sz.x, size.y), Color.BLACK)
	draw_rect(Rect2(0, o.y + sz.y, size.x, size.y), Color.BLACK)


func _draw_frame_pieces() -> void:
	var def := _def()
	var title := String(def.get("title", "")).to_lower()
	if title != "":
		_blit("titles/%s_%d.png" % [title, title_frame], TITLE_POS)
	var clip := 1 + int(round(panel_shown * 4.0))
	_blit("misc/upclip%d.png" % clip, UPCLIP_POS)
	_blit("misc/%s%d.png" % ["lowclipc" if screen in BLANK_CLIP else "lowclip", clip], LOWCLIP_POS)
	var back_frame: int = frames.get("back", 3 if screen in NO_BACK else 0)
	_blit("misc/backbut_%d.png" % back_frame, BACK_POS)
	var main_art := "quitbut" if screen in QUIT_SCREENS else "mainbut"
	_blit("misc/%s_%d.png" % [main_art, frames.get("main", 0)], MAIN_POS)


func _draw_panels() -> void:
	var panels := _panels()
	for p in panels.size():
		var panel: Dictionary = panels[p]
		var name := String(panel.name).to_lower()
		var base := _tex("palettes/%s_0.png" % name)
		if base == null:
			continue
		var pos := Vector2(panel.pos[0], panel.pos[1])
		var art := _art_size(base)
		# Left panels slide in from the left, bottom panels up from the bottom (§2).
		var hidden := 1.0 - panel_shown
		if panel.side == "left":
			pos.x -= art.x * hidden
		else:
			pos.y += art.y * hidden
		_blit("palettes/%s_0.png" % name, pos)
		var delta := pos - Vector2(panel.pos[0], panel.pos[1])
		for b in panel.buttons.size():
			var btn: Dictionary = panel.buttons[b]
			var f := _frame("%d/%d" % [p, b], btn.label)
			if f == 0:
				continue
			var path := "palettes/%s_%d.png" % [name, f]
			if _tex(path) == null:
				continue
			var r: Array = btn.rect
			var src := Rect2(r[0] - panel.pos[0], r[1] - panel.pos[1], r[2], r[3])
			_blit_region(path, src, Vector2(r[0], r[1]) + delta)


func _draw_content(def: Dictionary) -> void:
	if loading:
		_blit("mis/wait.png", CONTENT.position)
		return
	if screen == "tsd":
		return
	if screen == "deb":
		_draw_debrief()
		return
	var list := _list()
	if not list.is_empty():
		_draw_list(list)
	elif screen == "main":
		# Hovering an enabled main button shows main_N (FUN_004faa70).
		var hb := _button(hover_key)
		if not hb.is_empty() and _button_enabled(hb.label):
			_blit("main/main_%d.png" % (int(hover_key.split("/")[1]) + 1), CONTENT.position)
		else:
			_blit("screens/smain.png", CONTENT.position)
	else:
		var bg := "screens/%s.png" % String(def.name).to_lower()
		if _tex(bg) != null:
			_blit(bg, CONTENT.position)
		if screen == "pref":
			_draw_prefs()


## List screens (FUN_00508590): rows copied from mis_1, the row of the hovered same-named
## button from mis_2; Arial title and description drawn over them.
func _draw_list(list: Dictionary) -> void:
	var prefix := "mis/mismp" if screen == "netaow" else "mis/mis"
	_blit(prefix + "_0.png", CONTENT.position)
	var hb := _button(hover_key)
	var lit_name := _norm(hb.label) if not hb.is_empty() and _button_enabled(hb.label) else ""
	for row in list.rows:
		var rr: Array = row.rect
		var lit := _norm(row.name) == lit_name
		var src := Rect2(rr[0], rr[1], rr[2], rr[3])
		_blit_region(prefix + ("_2.png" if lit else "_1.png"), src, CONTENT.position + src.position)
		var tb: Array = row.title_box
		var db: Array = row.desc_box
		var title := _string(row.title_key)
		if title == "":
			title = row.name
		_text_line(Rect2(CONTENT.position + Vector2(tb[0], tb[1]), Vector2(tb[2] - tb[0], tb[3] - tb[1])), title, LIST_TITLE_PX, LIST_TITLE)
		_text_block(Rect2(CONTENT.position + Vector2(db[0], db[1]), Vector2(db[2] - db[0], db[3] - db[1])), _string(row.desc_key), LIST_DESC_PX, LIST_DESC_LIT if lit else LIST_DESC)


## Single line, bottom-aligned (DT_SINGLELINE|DT_BOTTOM); right-aligned in Hebrew.
func _text_line(box: Rect2, text: String, px: float, color: Color, f: Font = null) -> void:
	f = f if f != null else font
	var r := _rect(box)
	var fs := int(round(px * _scale()))
	var align := HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(f, Vector2(r.position.x, r.end.y - f.get_descent(fs)), text, align, r.size.x, fs, color)


## Word-wrapped block from the top (DT_WORDBREAK).
func _text_block(box: Rect2, text: String, px: float, color: Color) -> void:
	var r := _rect(box)
	var fs := int(round(px * _scale()))
	var align := HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	var lines := maxi(1, int(r.size.y / font.get_height(fs)) + 1)
	draw_multiline_string(font, r.position + Vector2(0, font.get_ascent(fs)), text, align, r.size.x, fs, lines, color)


## Our own settings on the Preferences "Gameplay" page (the original's pages are not built).
func _draw_prefs() -> void:
	pref_hotspots.clear()
	var x := CONTENT.position.x + 30
	var y := CONTENT.position.y + 60
	var width := CONTENT.size.x - 60
	_text_line(Rect2(x, y - 34, width, 20), _t(pref_page).to_upper(), LIST_TITLE_PX + 3, LIST_TITLE, font_bold)
	if pref_page != "Gameplay":
		_text_line(Rect2(x, y, width, 16), _t("(not available yet)"), LIST_TITLE_PX, PREF_DIM)
		return
	var options := [
		["Flight data", [["Original (Jane's IAF 1998)", "original"], ["Real F-16", "real"]], "flight_data"],
		["Language", [["English", "en"], ["Hebrew", "he"]], "language"],
		["No blackouts", [["Off", false], ["On", true]], "no_blackouts"],
		["Better physics", [["Off", false], ["On", true]], "better_physics"],
		["Flight info (F12)", [["Hide", false], ["Show", true]], "show_info"],
	]
	var rtl := _he()
	var fs := int(round(LIST_TITLE_PX * _scale()))
	for opt in options:
		_text_line(Rect2(x, y, width, 16), _t(opt[0]), LIST_TITLE_PX, LIST_TITLE)
		var ox := x + width - 130 if rtl else x + 130
		for choice in opt[1]:
			var value = choice[1]
			var label := _t(choice[0])
			var available: bool = not (typeof(value) == TYPE_STRING and value == "he" and not Settings.hebrew_available())
			var current: bool = Settings.get(opt[2]) == value
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / _scale() + 12
			var r := Rect2(ox - w if rtl else ox, y, w, 18)
			if current:
				draw_rect(_rect(r), Color(LIST_DESC, 0.6))
			var color := LIST_DESC_LIT if current else (PREF_TEXT if available else PREF_DIM)
			_text_line(Rect2(r.position + Vector2(6, 0), r.size - Vector2(6, 2)), label, LIST_TITLE_PX, color if available else PREF_DIM)
			if available:
				pref_hotspots.append([r, opt[2], value])
			ox += -(w + 8) if rtl else w + 8
		y += 34


# --- input ------------------------------------------------------------------------------

## Button under a point (menu coordinates): "panel/button", "back", "main" or "".
func _hit(p: Vector2) -> String:
	if Rect2(BACK_POS, Vector2(114, 22)).has_point(p):
		return "" if screen in NO_BACK else "back"
	if Rect2(MAIN_POS, Vector2(35, 59)).has_point(p):
		return "main"
	var panels := _panels()
	for pi in panels.size():
		for bi in panels[pi].buttons.size():
			var btn: Dictionary = panels[pi].buttons[bi]
			var r: Array = btn.rect
			if Rect2(r[0], r[1], r[2], r[3]).has_point(p) and _button_enabled(btn.label):
				return "%d/%d" % [pi, bi]
	return ""


func _gui_input(event: InputEvent) -> void:
	if busy:
		return
	if event is InputEventMouseMotion:
		var k := _hit(_to_menu(event.position))
		hover_key = k if "/" in k else ""
		# Dragging out of a held button releases it; back in presses it again (§3.1).
		if held != "":
			var inside := k == held
			if inside and frames.get(held, 0) != 2:
				frames[held] = 2
			elif not inside and frames.get(held, 0) == 2:
				frames.erase(held)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _to_menu(event.position)
		if event.pressed:
			if screen == "pref" and _pref_click(p):
				return
			held = _hit(p)
			if held != "":
				_animate_press(held)
		elif held != "":
			var key := held
			held = ""
			_animate_release(key, _hit(p) == key)


func _pref_click(p: Vector2) -> bool:
	for h in pref_hotspots:
		if h[0].has_point(p):
			Settings.set(h[1], h[2])
			Settings.save()
			if h[1] == "language":
				_load_menu_data()
			return true
	return false


## Press: frames _1, _2 with ButtonIn.wav, each held for half the sound (FUN_004e7f40).
func _animate_press(key: String) -> void:
	_play("buttonin")
	var step := _sound_length("buttonin") / 2.0
	frames[key] = 1
	await get_tree().create_timer(step).timeout
	if held == key:
		frames[key] = 2


## Release: _2, _1, _0 with ButtonOut.wav, then the action if still inside the button.
func _animate_release(key: String, inside: bool) -> void:
	if not inside:
		frames.erase(key)
		return
	busy = true
	_play("buttonout")
	var step := _sound_length("buttonout") / 3.0
	for f in [2, 1]:
		frames[key] = f
		await get_tree().create_timer(step).timeout
	frames.erase(key)
	busy = false
	_on_button(key)


func _on_button(key: String) -> void:
	if key == "back":
		if screen == "tsd":
			_message(8, [["yes", _go.bind(tsd_return)], ["no", Callable()]])
		elif screen != "arm":  # BACK has no case on Arm (FUN_004eb990)
			_go(_back_target())
		return
	if key == "main":
		if screen in QUIT_SCREENS:
			get_tree().quit()
		elif screen in ["tsd", "arm"]:
			_message(8, [["yes", _go.bind("main")], ["no", Callable()]])
		else:
			_go("main")
		return
	var btn := _button(key)
	if btn.is_empty():
		return
	match btn.kind:
		"Check":
			checked[key] = not checked.get(key, false)
		"CheckGroup":
			for k in checked.keys():
				checked[k] = false
			checked[key] = true
	var label: String = btn.label
	if screen == "pref":
		pref_page = label
		return
	if screen in ["tsd", "arm"]:
		_tsd_button(key, _norm(label), btn)
		return
	if screen == "deb":
		_debrief_button(_norm(label))
		return
	var target: String = FORWARD.get(screen, {}).get(_norm(label), "")
	if target != "":
		_go(target)
		return
	var row := _row_for(label)
	if screen in TO_JET and not row.is_empty():
		Settings.mission_id = int(row.id)
		jet_parent = screen
		_go("jet")
	elif screen in LOADS_MISSION:
		if screen == "jet":
			Settings.jet_id = JET_IDS.get(_norm(label), 1)
		elif not row.is_empty():
			Settings.mission_id = int(row.id)
		_load_mission()


## Debrief buttons: Replay (the same mission again), New Mission (its list), Next Mission (the next
## row of that list). Mapping UNCERTAIN (not traced in the exe).
func _debrief_button(label: String) -> void:
	var list_screen: String = Settings.last_list if Settings.last_list != "" else "main"
	if list_screen in TO_JET:
		jet_parent = list_screen
	Settings.debrief = {}
	match label:
		"replaymission":
			screen = "jet" if list_screen in TO_JET else list_screen
			_load_mission()
		"newmission":
			_go(list_screen)
		"nextmission":
			var parent := list_screen
			var rows: Array = menus.get(String(menus.get(parent, {}).get("name", "")).to_lower(), {}).get("rows", [])
			for i in rows.size() - 1:
				if int(rows[i].id) == Settings.mission_id:
					Settings.mission_id = int(rows[i + 1].id)
					screen = parent
					if parent in TO_JET:
						jet_parent = parent
						_go("jet")
					else:
						_load_mission()
					return
			_go(parent)


## TSD / Arming buttons (§8; Fly FUN_00502c90, Arming FUN_005057e0).
func _tsd_button(key: String, label: String, btn: Dictionary) -> void:
	if btn.kind in ["Check", "CheckGroup"]:
		if btn.kind == "CheckGroup":
			for f in ["alpha", "bravo", "charlie", "delta"]:
				tsd_checks[f] = false
		tsd_checks[label] = checked.get(key, false)
	if label in ["alpha", "bravo", "charlie", "delta"]:
		tsd.select_flight(_flight_number(label))
	match label:
		"fly":
			if _selected_flight() == "":
				_message(25, [["ok", Callable()]])
			else:
				_fly()
		"arm":
			_go("arm")
		"tacticaldisplay":
			_go("tsd")
		"zoomin":
			tsd.zoom_by(tsd.ZOOM_STEP)
		"zoomout":
			tsd.zoom_by(1.0 / tsd.ZOOM_STEP)
		"briefing":
			tsd.open_briefing(tsd_checks.briefing)
		"waypoint", "text", "grid":
			tsd.set_layer(label, tsd_checks[label])


## The briefing window's close button unchecks Briefing.
func tsd_briefing_closed() -> void:
	tsd_checks["briefing"] = false
	checked.erase(_key_for_label("Briefing"))


## "<rank> <callsign>" for the briefing's <header> (DAT_00836c98 / DAT_00836cac).
## No pilot records yet: a new pilot's rank.
func pilot_header() -> String:
	return "Second Lieutenant"


## A briefing diagram / card, from the Hebrew pack when the language is Hebrew.
func briefing_image(stem: String) -> Texture2D:
	var base := Settings.assets_dir().path_join("converted/briefings")
	for sub in (["img_he", "img"] if _he() else ["img"]):
		var path := base.path_join(sub).path_join(stem + ".png")
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null


## Double-click on a flight leader in the TSD: select that flight and fly.
func tsd_fly_flight(n: int) -> void:
	for f in ["alpha", "bravo", "charlie", "delta"]:
		tsd_checks[f] = false
	tsd_checks[["alpha", "bravo", "charlie", "delta"][n - 1]] = true
	tsd.select_flight(n)
	_fly()


## Debrief: the mission's headline (misc 0x47e / 0x492) and the notes of the events that fired.
## (Where the original draws them on the Deb screen is UNCERTAIN; shown in the content window.)
func _draw_debrief() -> void:
	_blit("screens/sgeneral.png", CONTENT.position)
	var d: Dictionary = Settings.debrief
	var box := Rect2(CONTENT.position + Vector2(20, 20), CONTENT.size - Vector2(40, 40))
	_text_line(Rect2(box.position, Vector2(box.size.x, 16)), String(d.get("headline", "")), LIST_TITLE_PX, LIST_TITLE, font_bold)
	_text_block(Rect2(box.position + Vector2(0, 30), box.size - Vector2(0, 30)), String(d.get("notes", "")), LIST_DESC_PX + 1, LIST_DESC_LIT)


func _fly() -> void:
	Settings.last_list = jet_parent if tsd_return == "jet" else tsd_return
	# The route as left on the TSD (waypoints may have been dragged).
	if tsd != null:
		Settings.route_override = tsd.selected_route()
	busy = true
	get_tree().change_scene_to_file("res://terrain/terrain_view.tscn")


func _row_for(label: String) -> Dictionary:
	for row in _list().get("rows", []):
		if _norm(row.name) == _norm(label):
			return row
	return {}


func _back_target() -> String:
	if screen == "jet":
		return jet_parent
	return BACK.get(screen, "main")


## Screen change (FUN_004e9f40): title tab and panels out, new screen, panels and title in.
func _go(to: String) -> void:
	if not menus.has(to) or busy:
		return
	busy = true
	hover_key = ""
	var old_panels := _panel_names()
	for f in [1, 0]:
		title_frame = f
		await get_tree().create_timer(TITLE_FRAME).timeout
	var new_panels: Array = []
	for p in menus[to].get("panels", []):
		new_panels.append(String(p.name).to_lower())
	var slide := old_panels != new_panels
	if slide:
		await _slide(0.0, "palettein")
	screen = to
	_enter_screen()
	_start_music()
	if slide:
		await _slide(1.0, "paletteout")
	for f in [0, 1, 2]:
		title_frame = f
		await get_tree().create_timer(TITLE_FRAME).timeout
	busy = false


func _panel_names() -> Array:
	var names: Array = []
	for p in _panels():
		names.append(String(p.name).to_lower())
	return names


## Panels slide for the length of the wav that plays with them (§2).
func _slide(to: float, wav: String) -> void:
	_play(wav)
	var t := create_tween()
	t.tween_property(self, "panel_shown", to, _sound_length(wav))
	await t.finished


## Mission load (FUN_004ec6a0): wait.bmp in the content window, music fades out over 6 s,
## then the TSD.
func _load_mission() -> void:
	busy = true
	loading = true
	tsd_return = screen
	_reset_tsd_checks()
	var fade := create_tween()
	fade.tween_property(music, "volume_db", -60.0, 6.0)
	fade.tween_callback(music.stop)
	for i in 3:
		await get_tree().process_frame
	busy = false
	await _go("tsd")
	loading = false


func _unhandled_input(event: InputEvent) -> void:
	if busy or not (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		return
	if screen in QUIT_SCREENS:
		get_tree().quit()
	elif not screen in NO_BACK:
		_go(_back_target())


# --- message box (§3.3) ---------------------------------------------------------------------

const MSGBOX_SIZE := Vector2(320, 140)
const MSGBOX_BUTTON := Vector2(60, 30)


## Shows txt/msgs.trx line `msg` with buttons [[art, action]] ("yes", "no", "ok", ...).
func _message(msg: int, buttons: Array) -> void:
	var lines: PackedStringArray = _string("msgs").split("\n")
	msgbox = {"text": lines[msg].strip_edges() if msg < lines.size() else "", "buttons": buttons, "pressed": -1}
	top_layer.mouse_filter = Control.MOUSE_FILTER_STOP


func _msgbox_origin() -> Vector2:
	return ((Vector2(W, H) - MSGBOX_SIZE) / 2).floor()


## Button rects (menu coordinates): 1 centred, 2 at W/2 - bw - bw/4 and W/2 + bw/4, top H - 5/3 bh.
func _msgbox_buttons() -> Array:
	var o := _msgbox_origin()
	var bw := MSGBOX_BUTTON.x
	var y := MSGBOX_SIZE.y - MSGBOX_BUTTON.y * 5.0 / 3.0
	var xs: Array = [MSGBOX_SIZE.x / 2 - bw / 2] if msgbox.buttons.size() == 1 else [MSGBOX_SIZE.x / 2 - bw - bw / 4, MSGBOX_SIZE.x / 2 + bw / 4]
	var out := []
	for i in mini(xs.size(), msgbox.buttons.size()):
		out.append(Rect2(o + Vector2(xs[i], y), MSGBOX_BUTTON))
	return out


func _draw_msgbox() -> void:
	if msgbox.is_empty():
		return
	var o := _msgbox_origin()
	var t := _tex("misc/mbgback.png")
	if t != null:
		top_layer.draw_texture_rect(t, _rect(Rect2(o, MSGBOX_SIZE)), false)
	var box := _rect(Rect2(o + Vector2(10, 20), MSGBOX_SIZE - Vector2(20, 70)))
	var fs := int(round(12 * _scale()))
	top_layer.draw_multiline_string(font_bold, box.position + Vector2(0, font_bold.get_ascent(fs)), msgbox.text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs, 4, Color.WHITE)
	var rects := _msgbox_buttons()
	for i in rects.size():
		var art := _tex("misc/mbg%s_%d.png" % [msgbox.buttons[i][0], 2 if msgbox.pressed == i else 0])
		if art != null:
			top_layer.draw_texture_rect(art, _rect(rects[i]), false)


func _msgbox_input(event: InputEvent) -> void:
	if msgbox.is_empty() or not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := _to_menu(event.position)
	var rects := _msgbox_buttons()
	var hit := -1
	for i in rects.size():
		if rects[i].has_point(p):
			hit = i
	if event.pressed:
		msgbox.pressed = hit
		if hit >= 0:
			_play("buttonin")
	else:
		if hit >= 0 and hit == msgbox.pressed:
			_play("buttonout")
			var action: Callable = msgbox.buttons[hit][1]
			msgbox = {}
			top_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if action.is_valid():
				action.call()
		elif not msgbox.is_empty():
			msgbox.pressed = -1
	top_layer.queue_redraw()
	top_layer.accept_event()
