# The Mission Creator screen (screen 0x14 "MC", docs/front-end.md §19; content ctor FUN_004f8f90, OnCreate
# FUN_004f9320): MC/SPBack.bmp with the MISSION NAME and NOTES edit boxes and the 20 single-player combo boxes over
# it. The state is the exe's global record DAT_0083ca10 (Settings.mc, docs/formats/mcr.md; IafMcr), zeroed each
# time the screen opens (the ctor's FUN_004f64a0). The panel buttons (Random, Load, Save, Fly) are drawn and
# animated by the front end, which calls button() on release. Geometry is content-local (the content at (155, 42)).
extends Control

const Img := preload("res://util/img.gd")
const CONTENT := Vector2(155, 42)
const CONTENT_H := 357.0
## The edit boxes (FUN_004f1890; .data 0x6076a8 / 0x607698): their lines as [text bottom-left, width].
const NAME_BOX := Rect2(126, 14, 314, 13)
const NOTES_BOX := Rect2(227, 251, 227, 105)
const NAME_LINES := [[Vector2(0, 13), 314.0]]
const NOTES_LINES := [
	[Vector2(54, 20), 162.0], [Vector2(8, 40), 208.0], [Vector2(8, 60), 208.0], [Vector2(8, 80), 208.0]
]
## The name's max length (+0x4c = 0x40); the notes have none (−1), only their four lines.
const NAME_MAX := 0x40
## The edit class's accepted characters (WM_CHAR FUN_004f1da0, as the Pilot Records boxes).
const CHARS := " .0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const TEXT_PX := 10.0  # Arial −10 (FUN_004eee10(9, …, 400, "Arial"))
const GREEN := Color8(0, 255, 0)  # SetTextColor(0xff00)
const ROW_TEXT := Color8(0, 200, 0)
## Ours: a combo that does not apply (Better's FROM with a calm wind).
const OFF_TEXT := Color8(0, 90, 0)
const SEPARATOR := Color8(0, 210, 0)
## The combo lists (FUN_004fa450, .data 0x652648..0x6528d0). The exe's English in both languages.
const TYPES := [
	"F-15",
	"F-16",
	"F-4 E",
	"F-42000",
	"Lavi",
	"Kfir",
	"Mirage",
	"MiG-23",
	"MiG-29",
	"A-4 N",
	"MiG-17",
	"MiG-21",
	"MiG-25",
	"Su-22",
	"Su-24",
	"Tu-22"
]
const COUNTS := ["0", "1", "2", "3"]
const LISTS := {
	"count": ["0", "1", "2"],
	"type_a": ["F-15", "F-16", "F-4 E", "F-42000", "Lavi", "Kfir", "Mirage", "MiG-23", "MiG-29"],
	"type": TYPES,
	"ai_blue": ["Aggressors", "Defenders", "Bombers", "Kamikaze"],
	"ai_red": ["Aggressors", "Defenders"],
	"base": ["Tel Nof", "Ramat David", "Ramon"],
	"time": ["Noon", "Dawn", "Sunset", "Night"],
	"alt": ["Runway", "5000ft", "10000ft", "15000ft"],
	"target": ["No Target", "Bunker", "Armored Column", "Radar Station", "Terrorists Camp"],
	"sams": COUNTS,
	"aaa": COUNTS,
	"weapons": ["Guns Only", "Multipurpose", "Air To Air"],
	"victory": ["By Kills", "By Target"],
	"wind_kt": ["Calm", "10 kt", "15 kt", "20 kt"],
	"wind_from": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
	"weather": ["Default", "Clear", "Light rain", "Heavy rain", "Random"],
}
## Ours, Extras "Mission Creator: Better" (docs/front-end.md §19.4): WIND, FROM and WEATHER in the Blue Force panel's
## free row under Bravo, in the BASE / TIME / ALT columns. The state keeps the values (knots, degrees from, the weather
## 0 Default (the Graphics Rain level), 1 Clear .. 4 Random), not the item index.
const WIND_COMBOS := [
	["wind_kt", -1, "wind_kt", Rect2(6, 170, 52, 19)],
	["wind_from", -1, "wind_from", Rect2(91, 170, 52, 19)],
	["weather", -1, "weather", Rect2(158, 170, 52, 19)],
]
const WIND_LABELS := ["WIND", "FROM", "WEATHER"]
const WIND_VALUES := {
	"wind_kt": [0, 10, 15, 20], "wind_from": [0, 45, 90, 135, 180, 225, 270, 315], "weather": [0, 1, 2, 3, 4]
}
## The template's wind (mission.mis misc 0x46a / 0x474), what the original's mission 0x29a flies; no weather.
const WIND_DEFAULT := {"wind_kt": 10, "wind_from": 270, "weather": 0}
## The art the wind combos' boxes are copied from: TIME's box with its frame and arrow column.
const WIND_BOX_ART := Rect2(90, 223, 64, 21)
const LABEL_PX := 11.0
## The 20 single-player combos (FUN_004f9320, rects .data 0x6076b8..0x6077f0): [state key, formation index or -1,
## list, rect of the text box]. The arrow button (MC/but_0..2, 9×19) sits right of the rect.
const COMBOS := [
	["count", 0, "count", Rect2(63, 95, 27, 19)],
	["count", 1, "count", Rect2(63, 125, 27, 19)],
	["count", 2, "count", Rect2(289, 95, 27, 19)],
	["count", 3, "count", Rect2(289, 125, 27, 19)],
	["type", 0, "type_a", Rect2(103, 95, 42, 19)],
	["type", 1, "type", Rect2(103, 125, 42, 19)],
	["type", 2, "type", Rect2(329, 95, 42, 19)],
	["type", 3, "type", Rect2(329, 125, 42, 19)],
	["ai", 0, "ai_blue", Rect2(158, 95, 55, 19)],
	["ai", 1, "ai_blue", Rect2(158, 125, 55, 19)],
	["ai", 2, "ai_red", Rect2(384, 95, 55, 19)],
	["ai", 3, "ai_red", Rect2(384, 125, 55, 19)],
	["base", -1, "base", Rect2(6, 224, 71, 19)],
	["time", -1, "time", Rect2(91, 224, 52, 19)],
	["alt", -1, "alt", Rect2(158, 224, 52, 19)],
	["target", -1, "target", Rect2(232, 224, 101, 19)],
	["sams", -1, "sams", Rect2(346, 224, 40, 19)],
	["aaa", -1, "aaa", Rect2(399, 224, 40, 19)],
	["weapons", -1, "weapons", Rect2(6, 313, 92, 19)],
	["victory", -1, "victory", Rect2(118, 313, 92, 19)],
]
const ARROW := Vector2(9, 19)
## TIME's index in COMBOS.
const TIME := 13
## A list row: tmHeight − leadings + 2 for Arial −10 (FUN_004f4470; inferred from the font metrics).
const ROW_H := 12.0
## The Type lists of Bravo..Delta (the derived list class FUN_004f6080): rows from FLYABLE_ROWS on in italic, 2 px
## lower, under a separator at y 108.
const FLYABLE_ROWS := 9
const SEPARATOR_Y := 108.0

var fe: Control
## The combos on the screen: COMBOS, then WIND_COMBOS with the switch on.
var combos: Array = COMBOS
var font: SystemFont
var font_bold: SystemFont
var font_italic: SystemFont
## The open combo (index into combos, -1 none), its current row (-1 none; the list keeps it between openings, the
## exe's quirk: FUN_004f5ac0 sets only the text), and whether a press happened while it was open.
var open := -1
var current := {}
var pressed_open := false
## The arrow held down (combo index, -1 none): but_2 while held.
var held_arrow := -1
## The edit box with the keyboard: 0 name, 1 notes, -1 none; carets; blink.
var focus := 0
var caret := [0, 0]
var caret_on := true
var _blink := 0.0


func setup(front_end: Control) -> void:
	fe = front_end
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	font = Img.arial(400)
	font_italic = Img.arial(400, true)
	font_bold = Img.arial(700)
	combos = COMBOS + WIND_COMBOS if Settings.better_mc else COMBOS
	# The ctor zeroes the global record (FUN_004f64a0 with ECX = 0x83ca10); OnCreate focuses the name box.
	_set_state(ClassDB.class_call_static("IafMcr", "blank"))
	_focus(0)


## A new state: with the switch on it has a wind (the template's when it has none), with it off none, so FLY and
## SAVE are the original's.
func _set_state(d: Dictionary) -> void:
	for k in WIND_DEFAULT:
		if not Settings.better_mc:
			d.erase(k)
		elif not d.has(k):
			d[k] = WIND_DEFAULT[k]
	Settings.mc = d


func mc() -> Dictionary:
	return Settings.mc


func _process(delta: float) -> void:
	_blink += delta
	if _blink >= 0.2:
		_blink = 0.0
		caret_on = not caret_on
	queue_redraw()


# --- the state ------------------------------------------------------------------------------------


## The combo's item index in the state.
func value(c: int) -> int:
	var spec: Array = combos[c]
	if WIND_VALUES.has(spec[0]):
		return WIND_VALUES[spec[0]].find(int(mc()[spec[0]]))
	return int(mc()[spec[0]][spec[1]]) if spec[1] >= 0 else int(mc()[spec[0]])


## A choice (FUN_004fb180): the item index into the state; BASE also into every formation record.
func choose(c: int, i: int) -> void:
	var spec: Array = combos[c]
	if WIND_VALUES.has(spec[0]):
		mc()[spec[0]] = WIND_VALUES[spec[0]][i]
	elif spec[1] >= 0:
		mc()[spec[0]][spec[1]] = i
	else:
		mc()[spec[0]] = i
	if spec[0] == "base":
		for k in 8:
			mc().fbase[k] = i


func items(c: int) -> Array:
	return LISTS[combos[c][2]]


## The text a combo shows: its item, nothing for an index past its list (RANDOM can draw AI 4 and SAMs / AAA 4).
func shown_text(c: int) -> String:
	var i := value(c)
	return items(c)[i] if i >= 0 and i < items(c).size() else ""


## Panel buttons (FUN_004faad0).
func button(label: String) -> void:
	_close_list()
	match label:
		"random":
			_set_state(ClassDB.class_call_static("IafMcr", "random", mc(), Time.get_ticks_msec()))
			_focus(0)
		"load":
			load_dialog()
		"save":
			save()
		"fly":
			fly()


# --- LOAD / SAVE (docs/formats/mcr.md) ---------------------------------------------------------------

## Where the files live: user://mcr (the exe: <exe dir>\MCR), or a temporary folder for tests.
static var _temp: DirAccess


static func folder() -> String:
	if OS.get_environment("IAF_DEFAULT_SETTINGS") == "1":
		if _temp == null:
			_temp = DirAccess.create_temp("iaf_mcr", false)
		return _temp.get_current_dir()
	DirAccess.make_dir_recursive_absolute("user://mcr")
	return ProjectSettings.globalize_path("user://mcr")


## SAVE (FUN_004fae70): msg 49 without a name; msg 46 (Yes / No) before replacing a file; then the 0x5ac bytes.
func save() -> void:
	if String(mc().name) == "":
		fe._message(49, [["ok", Callable()]])
		return
	var path := folder().path_join(mc().name)
	if FileAccess.file_exists(path):
		fe._message(46, [["yes", write.bind(path)], ["no", Callable()]])
	else:
		write(path)


func write(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(ClassDB.class_call_static("IafMcr", "to_bytes", mc()))
	return true


## LOAD (FUN_004facb0): the open-file dialog "Open Mission" on the folder, any file (ours: the system's dialog).
func load_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.use_native_dialog = true
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.title = "Open Mission"
	dlg.current_dir = folder()
	dlg.file_selected.connect(
		func(path: String) -> void:
			dlg.queue_free()
			read(path)
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## A file into the state, then the name box gets the keyboard. A file shorter than 0x5ac bytes shows "Bad misison
## file" and the state stays as it was (the exe keeps the bytes it read).
func read(path: String) -> bool:
	var d: Dictionary = ClassDB.class_call_static("IafMcr", "parse", FileAccess.get_file_as_bytes(path))
	if d.is_empty():
		fe._message(0, [["ok", Callable()]], "Bad misison file")
		return false
	_set_state(d)
	_focus(0)
	return true


# --- FLY ------------------------------------------------------------------------------------------------


## FLY (FUN_004faad0): the checks (msgs 44, 47, 48), then mission 0x29a loads (FUN_004edec0).
func fly() -> void:
	var msg: int = ClassDB.class_call_static("IafMcr", "fly_check", mc())
	if msg != 0:
		fe._message(msg, [["ok", Callable()]])
		return
	Settings.mission_id = 0x29a
	Settings.jet_id = -1
	Settings.mc_files = build(mc())
	fe._load_mission()


## Mission 0x29a's files for a state (IafMcr.build: docs/front-end.md §19.3).
static func build(state: Dictionary) -> Array:
	var json = JSON.parse_string(ClassDB.class_call_static("IafMcr", "build", state, Settings.assets_dir()))
	return json if json is Array else []


# --- combos ---------------------------------------------------------------------------------------------


func _shown() -> bool:
	return fe != null and fe.screen == "mc" and not fe.loading


func arrow_rect(c: int) -> Rect2:
	var r: Rect2 = combos[c][3]
	return Rect2(r.end.x, r.position.y, ARROW.x, ARROW.y)


## The list's height: a row per item (the visible rows are the item count), +1 for the derived class.
func list_h(c: int) -> float:
	return ROW_H * items(c).size() + (1.0 if combos[c][2] == "type" else 0.0)


## The list opens up when it would reach the content's bottom (FUN_004f5570: 357 ≤ y + 19 + listH).
func opens_up(c: int) -> bool:
	return CONTENT_H <= combos[c][3].position.y + 19.0 + list_h(c)


## The open list's rows area: (w + 7) × listH at (1, 19) of the combo, or above the box when it opens up.
func list_rect(c := open) -> Rect2:
	var r: Rect2 = combos[c][3]
	var h := list_h(c)
	var y := r.position.y - h if opens_up(c) else r.end.y
	return Rect2(r.position.x + 1, y, r.size.x + 7, h)


## The whole open combo window, its 1 px combBack frame included.
func frame_rect(c := open) -> Rect2:
	var lr := list_rect(c)
	var r: Rect2 = combos[c][3]
	var top := minf(lr.position.y - 1.0, r.position.y)
	var bottom := maxf(lr.end.y + 1.0, r.end.y)
	return Rect2(r.position.x, top, r.size.x + ARROW.x, bottom - top)


func row_at(q: Vector2) -> int:
	var lr := list_rect()
	if not Rect2(lr.position, lr.size + Vector2.ONE).has_point(q):  # FUN_004f0680 counts the right / bottom edge
		return -1
	return mini(int((q.y - lr.position.y) / ROW_H), items(open).size() - 1)


func _open_list(c: int) -> void:
	open = c
	pressed_open = false


func _close_list() -> void:
	open = -1


## 0xd / 0xe (FUN_004f5a60): the current row into the state, the list closes. No sound.
func _commit() -> void:
	var c := open
	_close_list()
	var i: int = current.get(c, -1)
	if i >= 0:
		choose(c, i)


func _gui_input(event: InputEvent) -> void:
	if fe == null or fe.busy or fe.msgbox != null or not _shown() or not (event is InputEventMouse):
		return
	var q: Vector2 = fe._to_menu(event.position) - CONTENT
	if event is InputEventMouseMotion:
		if open >= 0 and row_at(q) >= 0:
			current[open] = row_at(q)  # FUN_004f4700
		if held_arrow >= 0 and not arrow_rect(held_arrow).has_point(q):
			_arrow_up(false)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		# Only a press on our own controls stops here; the rest reaches the frame's buttons (RANDOM, FLY, BACK …).
		if press(q):
			accept_event()
	else:
		release(q)


## A left press: on an open list it commits on a row (0xd, already on the press) and cancels elsewhere (0xc, the
## list holds the capture, so the press goes no further); on an arrow it animates and opens (0x11, ButtonIn); on a
## box's text it opens at once without a sound (the edit's SETFOCUS, 0xb); on an edit box it gives it the keyboard.
func press(q: Vector2) -> bool:
	if open >= 0:
		pressed_open = true
		if row_at(q) >= 0:
			current[open] = row_at(q)
			_commit()
		else:
			_close_list()
		return true
	for c in combos.size():
		if combo_off(c):
			continue
		if arrow_rect(c).has_point(q):
			held_arrow = c
			fe._play("buttonin")
			_open_list(c)
			return true
		if combos[c][3].has_point(q):
			_open_list(c)
			return true
	for b in 2:
		if [NAME_BOX, NOTES_BOX][b].has_point(q):
			_focus(b)
			caret[b] = _caret_at(b, q - [NAME_BOX, NOTES_BOX][b].position)
			return true
	return false


## A left release: an arrow animates back (ButtonOut, 0x12 / 0x13); on the open list's row it commits; the
## release of the opening click leaves the list open.
func release(q: Vector2) -> void:
	if held_arrow >= 0:
		_arrow_up(arrow_rect(held_arrow).has_point(q))
		return
	if open >= 0 and row_at(q) >= 0 and current.get(open, -1) >= 0:
		_commit()
	elif open >= 0 and pressed_open:
		_close_list()


func _arrow_up(_inside: bool) -> void:
	held_arrow = -1
	fe._play("buttonout")


# --- keyboard -------------------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not _shown() or fe.msgbox != null or not (event is InputEventKey) or not event.pressed:
		return
	if open >= 0:
		_list_key(event.keycode)
		get_viewport().set_input_as_handled()
		return
	if focus < 0 or event.keycode == KEY_ESCAPE:
		return  # Esc: 0xf, ignored by the content; the front end's BACK
	get_viewport().set_input_as_handled()
	_edit_key(event)


## The open list's keys (FUN_004f48e0); Esc is not handled.
func _list_key(k: Key) -> void:
	var n := items(open).size()
	var i: int = current.get(open, -1)
	match k:
		KEY_DOWN:
			i = mini(i + 1, n - 1)
		KEY_UP:
			i = i - 1 if i > 0 else i
		KEY_PAGEDOWN:
			i = mini(i + n, n - 1)
		KEY_PAGEUP:
			i = maxi(i - n, 0)
		KEY_HOME:
			i = 0
		KEY_END:
			i = n - 1
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			_commit()
			return
	current[open] = i


## The edit class's keys (KEYDOWN 4f20b0, CHAR FUN_004f1da0). Enter / Tab (0xd / 0xe) only copy the text into the
## record (the state here is always current).
func _edit_key(event: InputEventKey) -> void:
	var key: String = ["name", "notes"][focus]
	var t := String(mc()[key])
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			return
		KEY_BACKSPACE:
			if caret[focus] > 0:
				mc()[key] = t.left(caret[focus] - 1) + t.substr(caret[focus])
				caret[focus] -= 1
			return
		KEY_DELETE:
			mc()[key] = t.left(caret[focus]) + t.substr(caret[focus] + 1)
			return
		KEY_LEFT, KEY_UP:
			caret[focus] = maxi(0, caret[focus] - 1)
			return
		KEY_RIGHT, KEY_DOWN:
			caret[focus] = mini(t.length(), caret[focus] + 1)
			return
		KEY_HOME:
			caret[focus] = 0
			return
		KEY_END:
			caret[focus] = t.length()
			return
	var ch := char(event.unicode) if event.unicode > 0 else ""
	if ch == "" or not ch in CHARS:
		return
	var nt := t.left(caret[focus]) + ch + t.substr(caret[focus])
	if (focus == 0 and nt.length() > NAME_MAX) or lines(focus, nt).size() > _box_lines(focus).size():
		return
	mc()[key] = nt
	caret[focus] += 1


## SETFOCUS (4f1c10): the caret at the start of line 0.
func _focus(b: int) -> void:
	focus = b
	caret = [0, 0]
	caret_on = true
	_blink = 0.0


func _box_lines(b: int) -> Array:
	return NAME_LINES if b == 0 else NOTES_LINES


## The text broken as FUN_004f2660 does, per character: a line ends before the character that would pass its width.
func lines(b: int, t: String) -> Array:
	var spec := _box_lines(b)
	var out := []
	var start := 0
	for k in t.length():
		var w: float = spec[mini(out.size(), spec.size() - 1)][1]
		if _text_width(t.substr(start, k - start + 1)) > w:
			out.append(t.substr(start, k - start))
			start = k
	out.append(t.substr(start))
	return out


## The caret index nearest a box-local point (FUN_004f24f0 / FUN_004f23e0): the line under it, then the character.
func _caret_at(b: int, p: Vector2) -> int:
	var spec := _box_lines(b)
	var ls := lines(b, String(mc()[["name", "notes"][b]]))
	var line := 0
	for i in mini(ls.size(), spec.size()):
		if p.y > spec[i][0].y - 20.0:
			line = i
	var used := 0
	for i in line:
		used += String(ls[i]).length()
	var s := String(ls[line]) if line < ls.size() else ""
	var best := 0
	for k in s.length() + 1:
		if (
			absf(_text_width(s.left(k)) - (p.x - spec[line][0].x))
			< absf(_text_width(s.left(best)) - (p.x - spec[line][0].x))
		):
			best = k
	return used + best


# --- drawing -----------------------------------------------------------------------------------------


func _draw() -> void:
	if not _shown():
		return
	fe._blit("mc/spback.png", CONTENT, self)
	for c in range(COMBOS.size(), combos.size()):
		var r: Rect2 = combos[c][3]
		var at := r.position + WIND_BOX_ART.position - COMBOS[TIME][3].position
		fe._blit_region("mc/spback.png", WIND_BOX_ART, CONTENT + at, self)
		_text(CONTENT + r.position + Vector2(1, -3), WIND_LABELS[c - COMBOS.size()], GREEN, font_bold, LABEL_PX)
	for c in combos.size():
		if c != open:
			_draw_combo(c)
	_draw_edit(0)
	_draw_edit(1)
	if open >= 0:
		_draw_open()


func _draw_combo(c: int) -> void:
	var r: Rect2 = combos[c][3]
	var col := OFF_TEXT if combo_off(c) else GREEN
	_text(CONTENT + Vector2(r.position.x + 2, r.position.y + 17), shown_text(c), col, font)
	fe._blit("mc/but_%d.png" % (2 if held_arrow == c else 0), CONTENT + arrow_rect(c).position, self)


## Ours (Better): FROM means nothing with a calm wind, so it is greyed and does not open.
func combo_off(c: int) -> bool:
	return combos[c][0] == "wind_from" and int(mc().get("wind_kt", 0)) == 0


## The open combo window: combBack under all of it (the 1 px frame), the box and arrow, the list's rows from
## listBack / listHi (the same top strip for every row).
func _draw_open() -> void:
	var fr := frame_rect()
	fe._blit_region("mc/combback.png", Rect2(Vector2.ZERO, fr.size), CONTENT + fr.position, self)
	var r: Rect2 = combos[open][3]
	fe._blit_region("mc/spback.png", Rect2(_art_at(open), Vector2(r.size.x, 19)), CONTENT + r.position, self)
	_draw_combo(open)
	var lr := list_rect()
	fe._blit_region("mc/listback.png", Rect2(Vector2.ZERO, lr.size), CONTENT + lr.position, self)
	var derived: bool = combos[open][2] == "type"
	var strip := Vector2(lr.size.x, ROW_H)
	for i in items(open).size():
		var at := lr.position + Vector2(0, ROW_H * i)
		var lit: bool = current.get(open, -1) == i
		fe._blit_region("mc/listhi.png" if lit else "mc/listback.png", Rect2(Vector2.ZERO, strip), CONTENT + at, self)
		var col := GREEN if lit else ROW_TEXT
		if derived:
			# DT_BOTTOM; the non-flyable rows in italic, 2 px lower.
			var low := i >= FLYABLE_ROWS
			_text(
				CONTENT + at + Vector2(3, ROW_H + (2.0 if low else 0.0)),
				items(open)[i],
				col,
				font_italic if low else font
			)
		else:
			_text(CONTENT + at + Vector2(3, (ROW_H + _line_h()) / 2.0), items(open)[i], col, font)
	if derived:
		var y := lr.position.y + SEPARATOR_Y
		draw_line(
			fe._to_screen(CONTENT + Vector2(lr.position.x, y)),
			fe._to_screen(CONTENT + Vector2(lr.end.x, y)),
			SEPARATOR,
			fe._scale()
		)


## Where combo c's box is in SPBack: its own place, TIME's for the wind combos (copied there).
func _art_at(c: int) -> Vector2:
	return COMBOS[TIME][3].position if c >= COMBOS.size() else combos[c][3].position


func _draw_edit(b: int) -> void:
	var t := String(mc()[["name", "notes"][b]])
	var box: Rect2 = [NAME_BOX, NOTES_BOX][b]
	var spec := _box_lines(b)
	var ls := lines(b, t)
	var used := 0
	var caret_drawn := false
	for i in mini(ls.size(), spec.size()):
		var at: Vector2 = box.position + spec[i][0]
		_text(CONTENT + at, ls[i], GREEN, font)
		var n := String(ls[i]).length()
		if focus == b and caret_on and not caret_drawn and caret[b] >= used and caret[b] <= used + n:
			var x: float = at.x + _text_width(String(ls[i]).left(caret[b] - used))
			var r := caret_rect(b, x, at.y)
			fe._blit_region(
				"misc/logincaret.png", Rect2(0, r.position.y - (at.y - 16), 1, r.size.y), CONTENT + r.position, self
			)
			caret_drawn = true
		used += n


## The caret's visible part (box-local x, line bottom y → content rect): LoginCaret.bmp (1×16) drawn at (x, bottom −
## 16) in the edit's child window (FUN_004f1890), which clips it to the box: 13 px in the 13 px high MISSION NAME box.
static func caret_rect(b: int, x: float, bottom: float) -> Rect2:
	var box: Rect2 = [NAME_BOX, NOTES_BOX][b]
	return Rect2(x, bottom - 16, 1, 16).intersection(box)


func _line_h() -> float:
	return font.get_height(int(TEXT_PX))


func _text_width(s: String) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(TEXT_PX)).x


## Arial −10, TA_BOTTOM | TA_LEFT at `at` (menu coordinates), left to right in both languages.
func _text(at: Vector2, s: String, color: Color, f: Font, px := TEXT_PX) -> void:
	var fs := int(round(px * fe._scale()))
	var p: Vector2 = fe._to_screen(at)
	draw_string(f, Vector2(p.x, p.y - f.get_descent(fs)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
