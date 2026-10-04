# The Login / Pilot Records screen (screen 0, docs/front-end.md §13): the pilot list box in the left panel,
# the tab strip and the Dossier / Records / Kills / Losses pages in the content window. The panel buttons
# (Login, New_Pilot, Remove_Pilot) are drawn and animated by the front end, which calls login(),
# new_pilot() and remove_pilot() on release. The data is game/menu/pilots.gd.
extends Control

const Pilots := preload("res://menu/pilots.gd")
const Img := preload("res://util/img.gd")
const CONTENT := Vector2(155, 42)
## Tab strip (0x608cf0) and pages (0x608ce8), content-local; tab hit x ranges (0x608cf8..0x608d34).
const STRIP := Vector2(26, 29)
const PAGE := Vector2(26, 55)
const TAB_X := [26, 142, 240, 311, 388]
const TAB_ART := ["dossier", "records", "kills", "losses"]
## List box (FUN_0051c750): screen (19,123), log/pilotslb 104×200; items (28,11)–(103,199), 11 rows of
## 17 px; scrollbar (1,1)–(16,199): arrows 15×18, thumb log/slider 15×35.
const LIST := Vector2(19, 123)
const ITEMS := Rect2(28, 11, 75, 188)
const ROWS := 11
const ROW_H := 17.0
const BAR := Rect2(1, 1, 15, 198)
const ARROW := Vector2(15, 18)
const THUMB := Vector2(15, 35)
## Dossier (page-local, 0x60bab8..0x60bafc): edit boxes, photo, rank / score / missions text (bottom-left).
const NAME_BOX := Rect2(106, 30, 170, 18)
const CALL_BOX := Rect2(106, 64, 170, 18)
const MAX_LEN := [10, 12]
const PHOTO := Rect2(288, 32, 69, 93)
const RANK_AT := Vector2(80, 156)
const SCORE_AT := Vector2(96, 188)
const MISSIONS_AT := Vector2(140, 220)
## Records stamps: x = 118 + (id mod 10 − 1)·36, y by id / 10 (0x60b970..d4).
const STAMP_Y := {31: 64, 32: 79, 11: 96, 12: 111, 13: 126, 21: 143, 22: 158, 23: 173, 40: 190}
## Kills / Losses icon slots per row (0x60b800..0x60b857) and the row totals' right edge / centre
## (0x60b858..0x60b86f).
const SLOTS := [[Vector2(75, 14), Vector2(165, 14), Vector2(255, 14), Vector2(120, 48), Vector2(210, 48)],
	[Vector2(75, 88), Vector2(165, 88), Vector2(255, 88), Vector2(120, 118), Vector2(210, 118)],
	[Vector2(75, 166)]]
const ICON_CELL := [0, 1, 5]
const TOTALS := [Vector2(378, 58), Vector2(378, 128), Vector2(378, 184)]
const CELL := Vector2(27, 17)
const TEXT_PX := 12.0  # Arial p11 (FUN_004eee10)
const GREEN := Color8(0, 255, 0)
const DIM_GREEN := Color8(0, 128, 0)
const RED := Color8(255, 0, 0)
## The edit boxes' accepted characters (WM_CHAR 4f1da0).
const CHARS := " .0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

var fe: Control
var data := Pilots.new()
## The selected pilot's history (FUN_004f66b0) and its totals (FUN_004f66d0).
var missions: Array = []
var totals := {}
var tab := 0
var top := 0
## Edit boxes: texts, caret positions, the box with the keyboard (-1 none) and the last focused box
## (page +0x68, -1 none); the caret blinks every 200 ms.
var edit := ["", ""]
var caret := [0, 0]
var focus := -1
var last_focus := -1
var caret_on := true
var _blink := 0.0
var photo := 0
var font: SystemFont
var key_font: Font
var hud_font: Font


func setup(front_end: Control) -> void:
	fe = front_end
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	font = Img.arial(400)
	var hud = load("res://cockpit/hud.gd")
	key_font = hud.load_original_font("key")
	hud_font = hud.load_original_font("hud")
	data.load_list()
	_select(data.selected)
	_scroll_to_selection()


## The list is written when it is destroyed (FUN_0051ce30), i.e. when the screen is left.
func _exit_tree() -> void:
	data.save_list()


func _process(delta: float) -> void:
	_blink += delta
	if _blink >= 0.2:
		_blink = 0.0
		caret_on = not caret_on
	queue_redraw()


# --- selection, pages ---------------------------------------------------------------------------

## A new selection (FUN_0051d220 after the checks): its history, totals and the Dossier.
func _select(i: int) -> void:
	data.selected = i
	var p := data.current()
	missions = Pilots.history(p.id) if not p.is_empty() else []
	totals = Pilots.totals(missions)
	_show(0)


## FUN_0050b230: shows page t; the Dossier reloads its boxes and photo from the record.
func _show(t: int) -> void:
	tab = t
	focus = -1
	last_focus = -1
	var p := data.current()
	edit = [p.get("name", ""), p.get("callsign", "")]
	caret = [edit[0].length(), edit[1].length()]
	photo = int(p.get("photo", 0))


## FUN_0050b190(1): leaving the Dossier checks the name and the callsign (FUN_0051c2b0) and keeps the photo.
func validate() -> bool:
	if tab != 0:
		return true
	if not _check(0) or not _check(1):
		return false
	data.current().photo = photo
	return true


## FUN_0051c200 / FUN_0051c250: an empty name (msg 0x1c), an empty callsign (0x1a) or one another pilot
## has (0x1b, case-sensitive) shows an OK box and gives the box the keyboard again; else the record takes it.
func _check(box: int) -> bool:
	var text: String = edit[box]
	var msg := 0
	if text == "":
		msg = 0x1c if box == 0 else 0x1a
	elif box == 1:
		for i in data.pilots.size():
			if i != data.selected and data.pilots[i].callsign == text:
				msg = 0x1b
	if msg != 0:
		fe._message(msg, [["ok", Callable()]])
		focus = box
		last_focus = box
		return false
	data.current()["name" if box == 0 else "callsign"] = text
	return true


## Login (FUN_0051d940): the checks, then the pilot (DAT_0083b814 / b834 / b848) and the rank of its score
## (DAT_0083b820, set by the Dossier).
func login() -> bool:
	var p := data.current()
	if p.is_empty():
		return true
	if not validate():
		return false
	Settings.pilot_id = p.id
	Settings.pilot_name = p.name
	Settings.pilot_callsign = p.callsign
	Settings.pilot_rank = Pilots.rank(totals.score)
	return true


## New_Pilot (FUN_0051d580).
func new_pilot() -> void:
	if not validate():
		return
	data.add()
	_select(data.selected)
	_scroll_to_selection()


## Remove_Pilot (FUN_0051d690): never the last pilot; msg 0x1d (Yes / No) unless name and callsign are empty.
func remove_pilot() -> void:
	if data.pilots.size() < 2:
		return
	var p := data.current()
	if p.name == "" and p.callsign == "":
		_remove()
	else:
		fe._message(0x1d, [["yes", _remove], ["no", Callable()]])


func _remove() -> void:
	data.remove(data.selected)
	_select(data.selected)
	top = clampi(top, 0, _max_top())


# --- list box -----------------------------------------------------------------------------------

func _max_top() -> int:
	return maxi(0, data.pilots.size() - ROWS)


func _scroll_to_selection() -> void:
	if data.selected < top:
		top = data.selected
	elif data.selected > top + ROWS - 1:
		top = data.selected - ROWS + 1
	top = clampi(top, 0, _max_top())


## The scrollbar in menu coordinates; front_end.gd's _bar_* helpers drive it.
func _bar() -> Rect2:
	return Rect2(LIST + BAR.position, BAR.size)


func _thumb_y() -> float:
	return fe._bar_thumb_y(_bar(), top, _max_top(), THUMB)


# --- input --------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if fe == null or fe.busy or fe.msgbox != null or not _shown() or not (event is InputEventMouse):
		return
	var p: Vector2 = fe._to_menu(event.position)
	if event is InputEventMouseMotion:
		if fe.ctrl_drag >= 0.0:
			top = fe._bar_drag_top(p.y, _bar(), _max_top(), THUMB)
			accept_event()
		return
	if not (event is InputEventMouseButton):
		return
	var q := p - CONTENT - PAGE
	if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and tab == 0 and PHOTO.has_point(q):
		_pick_photo()
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if fe.ctrl_arrow != "" or fe.ctrl_drag >= 0.0:
			fe.ctrl_arrow = ""
			fe.ctrl_drag = -1.0
			accept_event()
		return
	if _press(p, event.double_click):
		accept_event()


func _press(p: Vector2, double: bool) -> bool:
	var lp := p - LIST
	if BAR.has_point(lp):
		# As the Arming list: arrows one row, the track one page (UNCERTAIN: the page step), the thumb
		# drags.
		top = clampi(fe._bar_press(p, _bar(), top, _max_top(), ROWS, THUMB), 0, _max_top())
		return true
	if ITEMS.has_point(lp):
		var i := top + int((lp.y - ITEMS.position.y) / ROW_H)
		if i < data.pilots.size():
			if i != data.selected:
				# FUN_0051d220: the checks first; on failure the old selection stays.
				if not validate():
					return true
				_select(i)
			elif double and login():
				# FUN_0051d9b0: a double-click logs in and goes to Main.
				fe._go("main")
		return true
	var c := p - CONTENT
	# Tabs (FUN_0050af50, mouse down): ButtonIn, the checks, the page; the current tab is not hit-tested.
	if c.y >= STRIP.y and c.y < PAGE.y:
		for t in 4:
			if t != tab and c.x >= TAB_X[t] and c.x < TAB_X[t + 1]:
				fe._play("buttonin")
				if validate():
					_show(t)
				return true
	if tab != 0:
		return false
	var q := c - PAGE
	for b in 2:
		var box: Rect2 = [NAME_BOX, CALL_BOX][b]
		if box.has_point(q):
			_focus(b)
			# FUN_004f24f0: the caret goes to the nearest character boundary.
			var best := 0
			for k in edit[b].length() + 1:
				if absf(_text_width(edit[b].left(k)) - (q.x - box.position.x)) < absf(_text_width(edit[b].left(best)) - (q.x - box.position.x)):
					best = k
			caret[b] = best
			return true
	if PHOTO.has_point(q):
		_next_photo()
		return true
	return false


## A box gains the keyboard (notification 0xb, FUN_0051c3f0): the box that had it is checked first.
func _focus(b: int) -> void:
	if last_focus >= 0 and last_focus != b and not _check(last_focus):
		return
	focus = b
	last_focus = b
	caret_on = true
	_blink = 0.0


## Left click on the photo (FUN_0051c470): 0 → 1 … → 13 → 14 (the pilot's own picture, skipped when it
## has none) → 0.
func _next_photo() -> void:
	photo = photo + 1 if photo < 14 else 0
	if photo == 14 and Pilots.photo_path(data.current().id) == "":
		photo = 0
	data.current().photo = photo


## Right button up on the photo (FUN_0051c4f0): a file dialog for a .bmp, copied as the pilot's picture;
## the photo index becomes the pilot id.
func _pick_photo() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		return
	var id: int = data.current().id
	DisplayServer.file_dialog_show("", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.bmp;Bmp Files"]), func(ok: bool, paths: PackedStringArray, _filter: int):
			if not ok or paths.is_empty():
				return
			var img := Image.load_from_file(paths[0])
			if img != null and img.save_png(Pilots.dir().path_join("%d.png" % id)) == OK and data.current().id == id:
				photo = id
				data.current().photo = id)


func _unhandled_input(event: InputEvent) -> void:
	if focus < 0 or fe.msgbox != null or tab != 0 or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	var b := focus
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			_focus(1 - b)
			return
		KEY_ESCAPE:
			return
		KEY_BACKSPACE:
			if caret[b] > 0:
				edit[b] = edit[b].left(caret[b] - 1) + edit[b].substr(caret[b])
				caret[b] -= 1
			return
	var ch := char(event.unicode) if event.unicode > 0 else ""
	if ch == "" or not ch in CHARS:
		return
	var t: String = edit[b].left(caret[b]) + ch + edit[b].substr(caret[b])
	var box: Rect2 = [NAME_BOX, CALL_BOX][b]
	if t.length() > MAX_LEN[b] or _text_width(t) > box.size.x:
		return
	edit[b] = t
	caret[b] += 1


# --- drawing ------------------------------------------------------------------------------------

func _shown() -> bool:
	return fe.screen == "log" and not fe.loading


func _draw() -> void:
	if fe == null or not _shown():
		return
	var c := CONTENT
	fe._blit("log/%sb.png" % TAB_ART[tab], c + STRIP, self)
	fe._blit("log/%s.png" % TAB_ART[tab], c + PAGE, self)
	if not data.current().is_empty():
		match tab:
			0:
				_draw_dossier(c + PAGE)
			1:
				_draw_records(c + PAGE)
			2, 3:
				_draw_kills(c + PAGE, tab == 2)
	# The list box belongs to the frame and appears once the panel is in (FUN_004ea2a0 sends 0x549 after it).
	if fe.panel_shown >= 1.0:
		_draw_list()


func _draw_list() -> void:
	fe._blit("log/pilotslb.png", LIST, self)
	for r in ROWS:
		var i := top + r
		if i >= data.pilots.size():
			break
		var box := Rect2(LIST + ITEMS.position + Vector2(0, ROW_H * r), Vector2(ITEMS.size.x, ROW_H))
		var s: String = data.pilots[i].name
		var w := _text_width(s)
		_text(Vector2(box.position.x + (box.size.x - w) / 2.0, box.end.y - (ROW_H - _line_h()) / 2.0), s, GREEN if i == data.selected else DIM_GREEN)
	# Scrollbar (FUN_004f3700 layout, as Arming): sldownb at the top, slupb at the bottom, the thumb between.
	var bar := _bar()
	fe._blit("log/sldownb_%d.png" % (2 if fe.ctrl_arrow == "up" else 0), bar.position, self)
	fe._blit("log/slupb_%d.png" % (2 if fe.ctrl_arrow == "down" else 0), Vector2(bar.position.x, bar.end.y - ARROW.y), self)
	fe._blit("log/slider.png", Vector2(bar.position.x, _thumb_y()), self)


func _draw_dossier(at: Vector2) -> void:
	for b in 2:
		var box: Rect2 = [NAME_BOX, CALL_BOX][b]
		_text(at + Vector2(box.position.x, box.end.y), edit[b], GREEN)
		if focus == b and caret_on:
			fe._blit("misc/logincaret.png", at + Vector2(box.position.x + _text_width(edit[b].left(caret[b])), box.end.y - 16), self)
	var path := ""
	if photo < 14:
		path = "log/pilots/%d.png" % photo
		var t: Texture2D = fe._tex(path)
		if t != null:
			draw_texture_rect(t, fe._rect(Rect2(at + PHOTO.position, PHOTO.size)), false)
	else:
		var own := Pilots.photo_path(data.current().id)
		if own != "":
			if not _own_photo.has(own):
				_own_photo[own] = Img.load_texture(own)
			var t: Texture2D = _own_photo[own]
			if t != null:
				draw_texture_rect(t, fe._rect(Rect2(at + PHOTO.position, PHOTO.size)), false)
	_text(at + RANK_AT, Pilots.rank(totals.score), GREEN)
	_text(at + SCORE_AT, "%d" % totals.score, GREEN)
	_text(at + MISSIONS_AT, "%d" % totals.completed, GREEN)


var _own_photo := {}


## FUN_0051b730: passed.bmp for a mission with a pass, else failed.bmp for one with a failure.
func _draw_records(at: Vector2) -> void:
	for m in missions:
		var id := int(m.id)
		if not STAMP_Y.has(id / 10) or id % 10 == 0:
			continue
		var stamp := ""
		if Pilots.passes(missions, id) > 0:
			stamp = "log/passed.png"
		elif Pilots.failures(missions, id) > 0:
			stamp = "log/failed.png"
		if stamp != "":
			fe._blit(stamp, at + Vector2(118 + (id % 10 - 1) * 36, STAMP_Y[id / 10]), self)


## FUN_0051b050: per display group with a count, its icon cell in the next slot of its row and the name
## ("%sX%d" from 2 on) under it in key.fnt; the row totals in hud.fnt, right-aligned (kills green, losses
## negative and red), drawn when non-zero or the row has icons.
func _draw_kills(at: Vector2, kills: bool) -> void:
	var icons := "log/enemyic.png" if kills else "log/iafic.png"
	var counts: Array = totals.kill_groups if kills else totals.loss_groups
	var used := [0, 0, 0]
	for g in Pilots.GROUPS.size():
		var n := int(counts[g])
		var row: int = Pilots.GROUPS[g][1]
		if n == 0 or used[row] >= SLOTS[row].size():
			continue
		var slot: Vector2 = SLOTS[row][used[row]]
		used[row] += 1
		fe._blit_region(icons, Rect2(Vector2(ICON_CELL[row] * CELL.x, 0), CELL), at + slot, self)
		var label: String = Pilots.GROUPS[g][0] if n < 2 else "%sX%d" % [Pilots.GROUPS[g][0], n]
		_raster(key_font, at + slot + Vector2(13 - 3 * label.length(), 17), label, GREEN)
	for r in 3:
		var v: int = totals.k[r] if kills else -totals.l[r]
		if v == 0 and used[r] == 0:
			continue
		var s := "%d" % v
		_raster(hud_font, at + TOTALS[r] - Vector2(6 * s.length(), 4), s, GREEN if kills else RED)


func _line_h() -> float:
	return font.get_height(int(TEXT_PX))


func _text_width(s: String) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(TEXT_PX)).x


## Arial p11, TA_BOTTOM | TA_LEFT at `at` (menu coordinates), left to right in both languages.
func _text(at: Vector2, s: String, color: Color) -> void:
	var fs := int(round(TEXT_PX * fe._scale()))
	var p: Vector2 = fe._to_screen(at)
	draw_string(font, Vector2(p.x, p.y - font.get_descent(fs)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## A 6×8 raster font (key.fnt / hud.fnt), top-left at `at`.
func _raster(f: Font, at: Vector2, s: String, color: Color) -> void:
	if f == null:
		return
	var p: Vector2 = fe._to_screen(at)
	draw_string(f, p + Vector2(0, 7.0 * fe._scale()), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(8.0 * fe._scale())), color)
