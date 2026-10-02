# The Arming screen (screen 0x1f, docs/front-end.md §15): the flight leader's front view with its
# stations, CURRENT LOAD / MAX T.O.W., the weapon list (AA / AG / Misc) with drag and drop onto the
# stations, right-click to unload one, DEFAULT, and the checks and "Use weapon load?" question when
# leaving. The panels and their buttons are drawn by the front end, which forwards their presses here.
# The data (weapon list, allowed counts, loadout tables) is game/weapons/mission_weapons.gd, kept by
# the front end while the mission is loaded.
extends Control

## Content window (FUN_004e8d70).
const CLIENT := Rect2(155, 42, 453, 357)
## Station box (.rdata 0x608340) and its texts, box-relative (+1): "%dx%s" (0x608328) and "%g"
## (0x608350).
const BOX := Vector2(51, 32)
const COUNT_TEXT := Rect2(2, 23, 49, 9)
const WEIGHT_TEXT := Rect2(2, 33, 49, 9)
## Flight name TextOut (0x608348), Arial p11 weight 500.
const NAME_POS := Vector2(22, 18)
const NAME_PX := 12.0
## "%g Lb" boxes (0x655190 max take-off weight, 0x6551a0 current load), content-local.
const MAX_RECT := Rect2(377, 333, 54, 19)
const CUR_RECT := Rect2(126, 333, 56, 19)
## DEFAULT (arm/defbut_0..2, 0x608368), content-local.
const DEFAULT_RECT := Rect2(198, 330, 85, 23)
## Weapon list window (FUN_00518d80): frame at (17,168) (0x608338) = arm/weaponslb 106×261; inner
## list (0x60b0e8), 6 rows; scrollbar (0x60b0f8), arrows 15×18, thumb arm/slider 15×35.
const LIST_POS := Vector2(17, 168)
const LIST_INNER := Rect2(30, 4, 72, 252)
const ROWS := 6
const ROW_H := 42.0
const BAR := Rect2(2, 2, 15, 259)
const ARROW := Vector2(15, 18)
const THUMB := Vector2(15, 35)
## Row name, relative to the icon (box + 1) (0x60b0d8).
const ROW_TEXT := Rect2(1, 22, 49, 9)
const ICON := Vector2(49, 30)
const GREEN := Color8(0, 255, 0)
## The jet name in the originals' arming art (f-16.bmp "F-16"): right end and baseline, size, colour.
const TITLE_END := Vector2(446, 25)
const TITLE_PX := 13.0
const TITLE_GREEN := Color8(40, 205, 40)
const DIM_GREEN := Color8(0, 128, 0)
const RED := Color8(255, 0, 0)
const TAB_LABELS := ["AA", "AG", "Misc"]
const MissionWeapons := preload("res://weapons/mission_weapons.gd")
const Img := preload("res://util/img.gd")

var fe: Control
var data: RefCounted
## The flight shown (DAT_0083b8a4) and its jet (mission_weapons.gd jet()).
var flight := 0
var jet := {}
## Weapon list: the tab (+0x104), its weapons, the selected row, the first row shown.
var tab := 0
var rows: Array = []
var sel := -1
var top := 0
## A drag in progress: {w, count, from ("station" / "list"), off (cursor − image origin), pos}.
var drag := {}
var default_held := false
var arrow := ""
var thumb_drag := -1.0
## Cursor state (+0xf4 / list +0x1080): 0 arrow, 1 move.cur, 2 grab.cur.
var cursor := -1
var _cursors := {}
var key_font: Font
var name_font: Font
var title_font: Font


func setup(front_end: Control, mission_weapons: RefCounted, n: int) -> void:
	fe = front_end
	data = mission_weapons
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	key_font = load("res://cockpit/hud.gd").load_original_font("key")
	name_font = Img.arial(500)
	title_font = Img.arial(800)
	for c in ["move", "grab"]:
		_cursors[c] = Img.load_cursor(Settings.assets_dir().path_join("install/resource/menu/cur/%s.cur" % c))
	# FUN_00507400: the AA tab is checked on entry.
	tab = 0
	_check_tab()
	set_flight(n)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)


## FUN_00507750 (entry and each flight change): the flight's allowed counts, the list refiltered
## (row 0 selected), the jet art and its stations.
func set_flight(n: int) -> void:
	flight = n
	data.reset(n)
	set_tab(tab)
	jet = MissionWeapons.jet(int(data.flights.get(n, {}).get("type", -1)))
	queue_redraw()


## AA / AG / Misc (FUN_005070c0 / FUN_00519370): refilter in bdb order, select row 0, scroll to the top.
func set_tab(t: int) -> void:
	tab = t
	rows = data.tab_list(t)
	top = 0
	sel = 0 if not rows.is_empty() else -1


func _check_tab() -> void:
	for i in TAB_LABELS.size():
		var k: String = fe._key_for_label(TAB_LABELS[i])
		if k != "":
			fe.checked[k] = i == tab


func selected_weapon() -> Dictionary:
	return rows[sel] if sel >= 0 and sel < rows.size() else {}


func current_load() -> Array:
	return data.load_of(flight)


## The checks before any way out (FUN_00507480); shows the message and returns false on failure.
func validate() -> bool:
	var msg: int = data.check(flight, float(jet.get("base", 0.0)), float(jet.get("max", 0.0)))
	if msg != 0:
		fe._message(msg, [["ok", Callable()]])
		return false
	return true


## TacticalDisplay (1), Fly (2), BACK (3): the checks, then (FUN_005075c0) msg 0x23 "Use weapon
## load?" Yes / No / Cancel when the tables changed, else as No.
func leave(code: int) -> void:
	if not validate():
		return
	if data.changed():
		fe._message(0x23, [["yes", _answer.bind(code, "yes")], ["no", _answer.bind(code, "no")], ["can", Callable()]])
	else:
		_answer(code, "no")


## FUN_00507660: Yes saves the tables and puts every flight's load on its aircraft (single player),
## No reverts to the saved tables; then TSD (1, 3) or fly this flight (2).
func _answer(code: int, answer: String) -> void:
	if answer == "yes":
		data.commit()
		for n in data.flights:
			Settings.arm_loadouts[n] = data.saved[n].duplicate(true)
	else:
		data.revert()
	if code == 2:
		fe._fly()
	else:
		fe._go("tsd")


## A flight button (FUN_005070c0): the checks first; on failure the old flight stays checked.
func change_flight(n: int) -> bool:
	if not validate():
		return false
	if n != flight:
		set_flight(n)
	return true


## DEFAULT (FUN_00506790): the defaults for every flight, also put on the aircraft (single player);
## the saved tables are kept.
func use_defaults() -> void:
	data.use_defaults()
	for n in data.flights:
		Settings.arm_loadouts[n] = data.defaults[n].duplicate(true)
	queue_redraw()


# --- drawing ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()


func _art() -> String:
	return "arm/jets/%s.png" % jet.get("art", "")


func _icon(w: Dictionary) -> String:
	return "arm/weapons/%s.png" % w.get("icon", "")


func _draw() -> void:
	if fe == null or fe.loading or fe.screen != "arm":
		return
	var at := CLIENT.position
	if jet.is_empty():
		return
	_blit(_art(), at)
	# Ours: an extra plane's name (the originals have it in their art), top right like theirs.
	if jet.get("title", "") != "":
		var tfs := int(round(TITLE_PX * fe._scale()))
		var tp: Vector2 = fe._to_screen(at + TITLE_END)
		var tw := title_font.get_string_size(jet.title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		draw_string(title_font, tp + Vector2(-tw, 0), jet.title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, TITLE_GREEN)
	# The flight name (flight table +0x328), Arial p11 weight 500, green, transparent.
	if flight >= 1 and flight <= MissionWeapons.FLIGHT_NAMES.size():
		var fs := int(round(NAME_PX * fe._scale()))
		var p: Vector2 = fe._to_screen(at + NAME_POS)
		draw_string(name_font, p + Vector2(0, name_font.get_ascent(fs)), MissionWeapons.FLIGHT_NAMES[flight - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GREEN)
	# MAX T.O.W. then CURRENT LOAD (red when over), key.fnt, centred.
	var mx := float(jet.max)
	var cur: float = data.current_weight(flight, float(jet.base))
	_key_text(Rect2(at + MAX_RECT.position, MAX_RECT.size), "%s Lb" % g(mx), GREEN)
	_key_text(Rect2(at + CUR_RECT.position, CUR_RECT.size), "%s Lb" % g(cur), RED if mx < cur else GREEN)
	# Stations the selected weapon may go on: hibox, then the jet art over its inside (a frame).
	var w := selected_weapon()
	var st: Dictionary = jet.stations
	if not w.is_empty():
		var hb: Texture2D = fe._tex("arm/hibox.png")
		var hs: Vector2 = fe._art_size(hb) if hb != null else Vector2(53, 44)
		for i in st:
			if int(w.max[i]) > 0:
				var s: Vector2 = st[i]
				_blit("arm/hibox.png", at + s - Vector2.ONE)
				_region(_art(), Rect2(s + Vector2.ONE, hs - Vector2(4, 4)), at + s + Vector2.ONE)
	# Loaded stations: icon, "%dx%s", "%g" (count × weight), green.
	var ld := current_load()
	for i in st:
		if i >= ld.size() or int(ld[i][1]) == 0:
			continue
		var lw: Dictionary = data.weapon(int(ld[i][0]))
		if lw.is_empty():
			continue
		var s: Vector2 = at + st[i]
		_region(_icon(lw), Rect2(Vector2.ZERO, BOX - Vector2(2, 2)), s + Vector2.ONE)
		_key_text(Rect2(s + COUNT_TEXT.position, COUNT_TEXT.size), "%dx%s" % [int(ld[i][1]), lw.name], GREEN)
		_key_text(Rect2(s + WEIGHT_TEXT.position, WEIGHT_TEXT.size), g(float(int(ld[i][1])) * float(lw.weight)), GREEN)
	if fe.panel_shown >= 1.0:
		_draw_list()
	if default_held:
		_blit("arm/defbut_2.png", at + DEFAULT_RECT.position)
	else:
		_blit("arm/defbut_0.png", at + DEFAULT_RECT.position)
	_draw_drag()


func _draw_list() -> void:
	_blit("arm/weaponslb.png", LIST_POS)
	for r in ROWS:
		var idx := top + r
		if idx >= rows.size():
			break
		var w: Dictionary = rows[idx]
		var box := _row_box(r)
		_blit("arm/hiitem.png" if idx == sel else "arm/item.png", box)
		_region(_icon(w), Rect2(Vector2.ZERO, ICON), box + Vector2.ONE)
		_key_text(Rect2(box + Vector2.ONE + ROW_TEXT.position, ROW_TEXT.size), w.name, GREEN if idx == sel else DIM_GREEN)
	# Scrollbar (FUN_004f3700 layout): SlDownB at the top, SlUpB at the bottom, the thumb between.
	var bar := Rect2(LIST_POS + BAR.position, BAR.size)
	_blit("arm/sldownb_%d.png" % (2 if arrow == "up" else 0), bar.position)
	_blit("arm/slupb_%d.png" % (2 if arrow == "down" else 0), Vector2(bar.position.x, bar.end.y - ARROW.y))
	_blit("arm/slider.png", Vector2(bar.position.x, _thumb_y()))


## Row r's item box: item.bmp 51×32 centred in its 72×42 cell.
func _row_box(r: int) -> Vector2:
	return LIST_POS + LIST_INNER.position + Vector2(floorf((LIST_INNER.size.x - BOX.x) / 2.0), ROW_H * r + floorf((ROW_H - BOX.y) / 2.0))


## The drag image (506be0 / 5197f0): the icon under the cursor and "%dx%s" (from a station) or the
## name (from the list).
func _draw_drag() -> void:
	if drag.is_empty():
		return
	var o: Vector2 = drag.pos - drag.off
	var w: Dictionary = drag.w
	if drag.from == "station":
		_region(_icon(w), Rect2(Vector2.ZERO, BOX - Vector2(2, 2)), o + Vector2.ONE)
		_key_text(Rect2(o + COUNT_TEXT.position, COUNT_TEXT.size), "%dx%s" % [int(drag.count), w.name], GREEN)
	else:
		_region(_icon(w), Rect2(Vector2.ZERO, ICON), o)
		_key_text(Rect2(o + ROW_TEXT.position, ROW_TEXT.size), w.name, GREEN)


func _blit(path: String, pos: Vector2) -> void:
	var t: Texture2D = fe._tex(path)
	if t != null:
		draw_texture_rect(t, fe._rect(Rect2(pos, fe._art_size(t))), false)


func _region(path: String, src: Rect2, dest: Vector2) -> void:
	var t: Texture2D = fe._tex(path)
	if t == null:
		return
	var sz: Vector2 = fe._art_size(t)
	src = src.intersection(Rect2(Vector2.ZERO, sz))
	if src.size.x <= 0 or src.size.y <= 0:
		return
	draw_texture_rect_region(t, fe._rect(Rect2(dest, src.size)), Rect2(src.position * fe.art_scale, src.size * fe.art_scale))


## key.fnt (6×8 fixed pitch) with DT_CENTER | DT_VCENTER | DT_SINGLELINE, clipped to the box.
func _key_text(box: Rect2, text: String, color: Color) -> void:
	if key_font == null:
		return
	var fit := int(box.size.x / 6.0)
	if text.length() > fit:
		var cut := (text.length() - fit) / 2
		text = text.substr(cut, fit)
	var s: float = fe._scale()
	var x := box.position.x + floorf((box.size.x - 6.0 * text.length()) / 2.0)
	var y := box.position.y + floorf((box.size.y - 8.0) / 2.0)
	var p: Vector2 = fe._to_screen(Vector2(x, y))
	draw_string(key_font, p + Vector2(0, 7.0 * s), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(8.0 * s)), color)


## C's "%g" (6 significant digits, no trailing zeros).
static func g(v: float) -> String:
	if v == 0.0:
		return "0"
	var digits := 6 - int(floorf(log(absf(v)) / log(10.0))) - 1
	if digits >= 0 and absf(v) < 1e6:
		var s := String.num(v, maxi(digits, 0))
		if "." in s:
			s = s.rstrip("0").rstrip(".")
		return s
	return "%e" % v


# --- scrollbar ---------------------------------------------------------------------------------

func _max_top() -> int:
	return maxi(0, rows.size() - ROWS)


func _thumb_y() -> float:
	var bar := Rect2(LIST_POS + BAR.position, BAR.size)
	var lo := bar.position.y + ARROW.y
	var hi := bar.end.y - ARROW.y - THUMB.y
	var m := _max_top()
	return lo if m == 0 else lerpf(lo, hi, float(top) / m)


## Selects row idx and scrolls it into view (FUN_004f4700 / FUN_004f4810).
func select_row(idx: int) -> void:
	if idx < 0 or idx >= rows.size():
		return
	sel = idx
	if sel < top:
		top = sel
	elif sel > top + ROWS - 1:
		top = sel - ROWS + 1


# --- input -------------------------------------------------------------------------------------

func _station_at(p: Vector2, loaded_only: bool) -> int:
	var st: Dictionary = jet.get("stations", {})
	var ld := current_load()
	for i in st:
		if loaded_only and (i >= ld.size() or int(ld[i][1]) == 0):
			continue
		if Rect2(CLIENT.position + st[i], BOX).has_point(p):
			return i
	return -1


func _set_cursor(state: int) -> void:
	if state == cursor:
		return
	cursor = state
	var c: Array = _cursors.get(["", "move", "grab"][state], [])
	if state == 0 or c.is_empty():
		Input.set_custom_mouse_cursor(null)
	else:
		Input.set_custom_mouse_cursor(c[0], Input.CURSOR_ARROW, c[1])


func _gui_input(event: InputEvent) -> void:
	if fe == null or fe.busy or fe.msgbox != null or not (event is InputEventMouse) or jet.is_empty():
		return
	var p: Vector2 = fe._to_menu(event.position)
	if event is InputEventMouseMotion:
		_motion(p)
		if not drag.is_empty() or default_held or thumb_drag >= 0.0:
			accept_event()
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# FUN_00506fd0: one store less on the loaded station under the cursor.
		var i := _station_at(p, true)
		if i >= 0:
			data.decrement(flight, i)
			accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _press(p):
			accept_event()
	elif _release(p):
		accept_event()


func _press(p: Vector2) -> bool:
	if Rect2(CLIENT.position + DEFAULT_RECT.position, DEFAULT_RECT.size).has_point(p):
		default_held = true
		fe._play("buttonin")
		return true
	var lp := p - LIST_POS
	if Rect2(BAR.position, BAR.size).has_point(lp):
		_bar_press(lp)
		return true
	if Rect2(LIST_INNER.position, LIST_INNER.size).has_point(lp):
		var r := int((lp.y - LIST_INNER.position.y) / ROW_H)
		var idx := top + r
		if idx < rows.size():
			select_row(idx)
			# FUN_00519620: a press on the row's icon starts a drag.
			var icon_at := _row_box(r) + Vector2.ONE
			if Rect2(icon_at, ICON).has_point(p):
				drag = {"w": rows[idx], "count": 0, "from": "list", "off": p - icon_at, "pos": p}
				_set_cursor(2)
		return true
	# FUN_00506810: a press on a loaded station picks its weapon up and clears the station.
	var i := _station_at(p, true)
	if i >= 0:
		var s: Array = current_load()[i]
		var w: Dictionary = data.weapon(int(s[0]))
		if w.is_empty():
			return true
		if int(w.tab) != tab:
			tab = int(w.tab)
			_check_tab()
			set_tab(tab)
		# The weapon's row is looked for from row 1 on (row 0 is selected by a tab change).
		for idx in range(1, rows.size()):
			if rows[idx].name == w.name:
				select_row(idx)
				break
		drag = {"w": w, "count": int(s[1]), "from": "station", "off": p - (CLIENT.position + jet.stations[i]), "pos": p}
		data.put(flight, i, {})
		_set_cursor(2)
		return true
	return false


func _release(p: Vector2) -> bool:
	if default_held:
		default_held = false
		if Rect2(CLIENT.position + DEFAULT_RECT.position, DEFAULT_RECT.size).has_point(p):
			fe._play("buttonout")
			use_defaults()
		return true
	if arrow != "" or thumb_drag >= 0.0:
		arrow = ""
		thumb_drag = -1.0
		return true
	if drag.is_empty():
		return false
	# FUN_00507aa0: onto a station that allows it, with that station's maximum count.
	var st: Dictionary = jet.stations
	for i in st:
		if int(drag.w.max[i]) != 0 and Rect2(CLIENT.position + st[i], BOX).has_point(p):
			data.put(flight, i, drag.w)
			break
	drag = {}
	_set_cursor(1)
	return true


func _motion(p: Vector2) -> void:
	if not drag.is_empty():
		drag.pos = p
		return
	if thumb_drag >= 0.0:
		var bar := Rect2(LIST_POS + BAR.position, BAR.size)
		var lo := bar.position.y + ARROW.y
		var hi := bar.end.y - ARROW.y - THUMB.y
		top = int(round(clampf(inverse_lerp(lo, hi, p.y - thumb_drag), 0.0, 1.0) * _max_top())) if hi > lo else 0
		return
	# Hover: move.cur over a loaded station (506be0) or a list icon (5197f0), else the arrow.
	var over := _station_at(p, true) >= 0
	for r in ROWS:
		if top + r < rows.size() and Rect2(_row_box(r) + Vector2.ONE, ICON).has_point(p):
			over = true
	_set_cursor(1 if over else 0)


## Scrollbar press (list-local): the arrows one row, the track one page (UNCERTAIN: the page step,
## as the Controls page), the thumb drags.
func _bar_press(lp: Vector2) -> void:
	var y := lp.y + LIST_POS.y
	var bar := Rect2(LIST_POS + BAR.position, BAR.size)
	if y < bar.position.y + ARROW.y:
		arrow = "up"
		top = clampi(top - 1, 0, _max_top())
	elif y >= bar.end.y - ARROW.y:
		arrow = "down"
		top = clampi(top + 1, 0, _max_top())
	else:
		var t := _thumb_y()
		if y < t:
			top = clampi(top - ROWS, 0, _max_top())
		elif y >= t + THUMB.y:
			top = clampi(top + ROWS, 0, _max_top())
		else:
			thumb_drag = y - t
