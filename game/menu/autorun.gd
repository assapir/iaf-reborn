# The CD's autorun launcher (ours, Extras → CD launcher; docs/front-end.md §18.1): Jauto.exe's poster dialog drawn
# from the CD's own files (assets/install/autorun, copied by iaf-extract). The exe's dialog 102 is a captionless
# WS_POPUP the poster's size, centred; here the poster sits centred in the 640x480 frame on a plain black background.
# Its eight owner-drawn buttons (ids 0x3e8..0x3ef) sit on the poster.rgn slots B1..B8; each state's art is the
# buttons.rgn cell <state><language><n>: N normal, F focused, P pressed, D disabled (WM_DRAWITEM FUN_00404629).
# "Active" (F) is the keyboard focus, as in a Win32 dialog: hover changes nothing.
extends Control

signal play
signal quit
signal install
signal uninstall

const W := 640.0
const H := 480.0
## Button order = control ids 0x3e8.. = slots B1..B8 = cells 1..8.
const NAMES := ["HELP", "INSTALL", "PLAY", "JANE'S ONLINE", "REGISTER ONLINE", "PREVIEWS", "UNINSTALL", "QUIT"]
const INSTALL := 1
const PLAY := 2
const UNINSTALL := 6
const QUIT := 7
## Enabled buttons. The exe enables all but PLAY and UNINSTALL, and those two when the game is installed
## (FUN_00404e3e). Ours: PLAY and QUIT; INSTALL opens the setup wizard and UNINSTALL removes the setup's data (the
## exe runs the Windows installer / uninstaller); HELP / PREVIEWS (WinHelp .hlp files), REGISTER ONLINE (a Windows
## program) and JANE'S ONLINE (a dead URL) show their disabled art.
const ENABLED := [false, true, true, false, false, false, true, true]
## The art's language set: the exe picks E / F / G from the Windows locale (FUN_004047d0); the Hebrew CD has the
## same art, so English always.
const LANG := "E"
## The startup sound: WAVE resource 131 in Jauto.exe, played asynchronously before the dialog shows (FUN_00404191).
const WAVE_ID := 131

var poster: Texture2D
var buttons: Texture2D
var slots := {}  # "B1".. -> Rect2i in the poster
var cells := {}  # "NE1".. -> Rect2i in buttons.bmp
var focus := -1
## The button held down by the mouse or Space (-1 none); `inside` = the pointer is still on it (ODS_SELECTED).
var held := -1
var inside := false
var by_key := false
var sound: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dir := Settings.assets_dir().path_join("install/autorun")
	poster = _texture(dir.path_join("poster.bmp"))
	buttons = _texture(dir.path_join("buttons.bmp"))
	slots = IafAutorun.rects(dir.path_join("poster.rgn"))
	cells = IafAutorun.rects(dir.path_join("buttons.rgn"))
	var wav := IafAutorun.wave(dir.path_join("jauto.exe"), WAVE_ID)
	if not wav.is_empty():
		sound = AudioStreamPlayer.new()
		sound.stream = AudioStreamWAV.load_from_buffer(wav)
		add_child(sound)
		sound.play()
	# Ours: PLAY takes the focus (the exe's first enabled tab stop, with INSTALL enabled here before it).
	focus = PLAY
	focus_mode = Control.FOCUS_ALL
	grab_focus()


## False when the CD files are missing (setup-cli.sh / iaf-extract --autorun not run): the start-up then goes on.
func available() -> bool:
	return poster != null and buttons != null and slots.size() == 8


static func _texture(path: String) -> Texture2D:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	return ImageTexture.create_from_image(img) if img != null else null


func _scale() -> float:
	return min(size.x / W, size.y / H)


## The poster's top-left in window pixels (centred).
func _poster_origin() -> Vector2:
	return (size - Vector2(poster.get_size()) * _scale()) / 2.0


## Button `i`'s rect in poster pixels (slot B<i+1>).
func slot(i: int) -> Rect2i:
	return slots.get("B%d" % (i + 1), Rect2i())


## The art cell drawn for button `i` now.
func cell_name(i: int) -> String:
	var st := "N"
	if held == i and inside:
		st = "P"
	elif focus == i:
		st = "F"
	elif not ENABLED[i]:
		st = "D"
	return "%s%s%d" % [st, LANG, i + 1]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if not available():
		return
	var o := _poster_origin()
	var s := _scale()
	draw_texture_rect(poster, Rect2(o, Vector2(poster.get_size()) * s), false)
	for i in NAMES.size():
		var r := slot(i)
		var c: Rect2i = cells.get(cell_name(i), Rect2i())
		draw_texture_rect_region(buttons, Rect2(o + Vector2(r.position) * s, Vector2(r.size) * s), Rect2(c))


## The button under a window point, -1 none.
func button_at(p: Vector2) -> int:
	if not available():
		return -1
	var q := (p - _poster_origin()) / _scale()
	for i in NAMES.size():
		if Rect2(slot(i)).has_point(q):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var b := button_at(e.position)
		if e.pressed and b >= 0 and ENABLED[b]:
			focus = b
			held = b
			inside = true
			by_key = false
		elif not e.pressed and held >= 0 and not by_key:
			var hit := held if inside else -1
			held = -1
			if hit >= 0:
				press(hit)
		queue_redraw()
	elif e is InputEventMouseMotion and held >= 0 and not by_key:
		var now := button_at(e.position) == held
		if now != inside:
			inside = now
			queue_redraw()
	elif e is InputEventKey and not e.echo:
		_key(e)


func _key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_SPACE:
			if e.pressed and held < 0 and focus >= 0:
				held = focus
				inside = true
				by_key = true
			elif not e.pressed and by_key and held >= 0:
				var b := held
				held = -1
				press(b)
		KEY_ENTER, KEY_KP_ENTER:
			# The focused button is the default one (DM_SETDEFID on its focused draw).
			if e.pressed and focus >= 0:
				press(focus)
		KEY_ESCAPE:
			# IDCANCEL: CDialog::OnCancel ends the dialog, as QUIT.
			if e.pressed:
				quit.emit()
		KEY_TAB, KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_UP:
			if e.pressed and held < 0:
				var back := e.keycode in [KEY_LEFT, KEY_UP] or (e.keycode == KEY_TAB and e.shift_pressed)
				move_focus(-1 if back else 1)
	accept_event()
	queue_redraw()


## Next / previous enabled button, wrapping (the dialog manager's tab and group order).
func move_focus(step: int) -> void:
	for k in range(1, NAMES.size() + 1):
		var i := posmod(focus + step * k, NAMES.size())
		if ENABLED[i]:
			focus = i
			return


## A click (BN_CLICKED) on button `i`: PLAY ends the launcher into the start-up (the exe runs IAFJets.EXE and
## closes, FUN_0040499f), QUIT ends it (EndDialog, FUN_00404e36); INSTALL / UNINSTALL (ours) go to startup.gd.
func press(i: int) -> void:
	if not ENABLED[i]:
		return
	if sound != null:
		sound.stop()
	if i == PLAY:
		play.emit()
	elif i == QUIT:
		quit.emit()
	elif i == INSTALL:
		install.emit()
	elif i == UNINSTALL:
		uninstall.emit()
