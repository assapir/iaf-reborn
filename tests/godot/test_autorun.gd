# The CD launcher (ours, Extras → CD launcher; docs/front-end.md §18.1): Jauto.exe's poster and buttons from the
# CD's files: slot rects B1..B8 from poster.rgn, art cells <state>E<n> from buttons.rgn, PLAY / QUIT / INSTALL /
# UNINSTALL enabled (INSTALL and UNINSTALL emit their signals),
# the focus (active art) on PLAY first, Tab / arrows move it, mouse down shows the pressed cell and dragging off
# releases it, a release inside clicks, Enter presses the focused button, Esc quits; the startup sound loads.
extends "res://../tests/godot/base.gd"

var played := 0
var quitted := 0


func centre(a: Control, i: int) -> Vector2:
	var r: Rect2i = a.slot(i)
	return a._poster_origin() + (Vector2(r.position) + Vector2(r.size) / 2.0) * a._scale()


func motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	return e


func key_ev(a: Control, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = down
	e.shift_pressed = shift
	a._gui_input(e)


func run() -> void:
	var a: Control = load("res://menu/autorun.gd").new()
	root.add_child(a)
	await frames(2)
	if not a.available():
		check(false, "autorun files in assets/install/autorun (iaf-extract --autorun)")
		return
	a.play.connect(func(): played += 1)
	a.quit.connect(func(): quitted += 1)
	check(a.poster.get_size() == Vector2(468, 451), "poster.bmp 468x451")
	check(a.buttons.get_size() == Vector2(1500, 456), "buttons.bmp 1500x456 (8-bit BMP loads)")
	var want := [
		Rect2i(0, 328, 128, 38),
		Rect2i(128, 328, 212, 38),
		Rect2i(340, 328, 128, 38),
		Rect2i(0, 366, 234, 38),
		Rect2i(234, 366, 234, 38),
		Rect2i(0, 404, 128, 38),
		Rect2i(128, 404, 212, 38),
		Rect2i(340, 404, 128, 38)
	]
	var rects_ok := true
	var cells_ok := true
	for i in 8:
		rects_ok = rects_ok and a.slot(i) == want[i]
		for st in ["N", "F", "P", "D"]:
			var c: Rect2i = a.cells.get("%sE%d" % [st, i + 1], Rect2i())
			cells_ok = cells_ok and c.size == want[i].size
	check(rects_ok, "slots B1..B8 = poster.rgn rows of 3, 2, 3")
	check(cells_ok, "every state cell N/F/P/D E1..E8 has its slot's size")
	check(
		a.cells.get("NE1") == Rect2i(0, 0, 128, 38) and a.cells.get("DE4") == Rect2i(468, 114, 234, 38),
		"cells: NE1 at (0,0), DE4 at (468,114)"
	)
	check(a.sound != null and a.sound.stream != null, "startup sound: WAVE 131 from jauto.exe")
	check(a.focus == a.PLAY, "focus starts on PLAY (first enabled tab stop)")
	check(
		a.cell_name(2) == "FE3" and a.cell_name(7) == "NE8" and a.cell_name(0) == "DE1" and a.cell_name(6) == "NE7",
		"art: PLAY active, QUIT / UNINSTALL normal, HELP disabled"
	)
	check(a.button_at(centre(a, 7)) == 7 and a.button_at(a._poster_origin() - Vector2(5, 5)) == -1, "hit test")
	# A click on a disabled button does nothing.
	a._gui_input(mouse_button(centre(a, 0), true))
	a._gui_input(mouse_button(centre(a, 0), false))
	check(a.focus == a.PLAY and played == 0 and quitted == 0, "disabled HELP: no focus, no action")
	# Tab / arrows move the focus between the enabled buttons.
	key_ev(a, KEY_TAB)
	check(a.focus == a.UNINSTALL and a.cell_name(6) == "FE7" and a.cell_name(2) == "NE3", "Tab: focus to UNINSTALL")
	key_ev(a, KEY_LEFT)
	check(a.focus == a.PLAY, "Left: back to PLAY")
	# INSTALL / UNINSTALL emit their signals (startup.gd opens the setup wizard / asks and uninstalls).
	var got := []
	a.install.connect(func(): got.append("install"))
	a.uninstall.connect(func(): got.append("uninstall"))
	for i in [a.INSTALL, a.UNINSTALL]:
		a._gui_input(mouse_button(centre(a, i), true))
		a._gui_input(mouse_button(centre(a, i), false))
	check(got == ["install", "uninstall"], "click INSTALL / UNINSTALL: their signals")
	key_ev(a, KEY_LEFT)
	check(a.focus == a.PLAY, "Left from UNINSTALL: PLAY")
	# Mouse down on QUIT: focus + pressed art; drag off: not pressed; release outside: nothing.
	a._gui_input(mouse_button(centre(a, 7), true))
	check(a.focus == a.QUIT and a.cell_name(7) == "PE8", "mouse down on QUIT: pressed art")
	a._gui_input(motion(centre(a, 2)))
	check(a.cell_name(7) == "FE8", "dragged off: focused, not pressed")
	a._gui_input(mouse_button(centre(a, 2), false))
	check(quitted == 0 and played == 0, "release outside: no click")
	# Enter presses the focused (default) button.
	key_ev(a, KEY_RIGHT)
	check(a.focus == a.INSTALL, "Right wraps to INSTALL")
	key_ev(a, KEY_RIGHT)
	check(a.focus == a.PLAY, "Right: PLAY")
	key_ev(a, KEY_ENTER)
	check(played == 1, "Enter: PLAY")
	a._gui_input(mouse_button(centre(a, 7), true))
	a._gui_input(mouse_button(centre(a, 7), false))
	check(quitted == 1, "click QUIT: quit")
	key_ev(a, KEY_ESCAPE)
	check(quitted == 2, "Esc: quit (IDCANCEL)")
	a.queue_free()
