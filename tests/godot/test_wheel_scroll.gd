# Mouse wheel (ours, docs/front-end.md §12.9): the wheel and a trackpad pan scroll the Preferences lists (Controls,
# Extras, Physics) by one row and the briefing text by one line, the step of their scroll arrows; Extras → Mouse
# wheel "natural" reverses the direction.
extends "res://../tests/godot/base.gd"


func wheel(down: bool, pos := Vector2.ZERO) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = pos
	return e


func pan(dy: float) -> InputEventPanGesture:
	var e := InputEventPanGesture.new()
	e.delta = Vector2(0, dy)
	return e


func run() -> void:
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	check(fe.screen == "pref", "Main -> Preferences")
	# The lists: [page, its first-row field, its scrollbar (page rect)].
	for l in [
		["Controls", "ctrl_top", fe.CTRL_BAR],
		["Extras", "extras_top", fe._extras_bar()],
		["Physics", "phys_top", fe._phys_bar()]
	]:
		settings().pref_page = l[0]
		fe.set(l[1], 0)
		click(fe, fe.CONTENT.position + Vector2(l[2].get_center().x, l[2].end.y - 2))  # the down arrow
		var arrow: int = fe.get(l[1])
		fe.set(l[1], 0)
		fe._gui_input(wheel(true))
		check(
			arrow == 1 and fe.get(l[1]) == 1, "%s: wheel down scrolls one row, as the down arrow (%d)" % [l[0], arrow]
		)
		fe._gui_input(wheel(true))
		fe._gui_input(wheel(false))
		check(fe.get(l[1]) == 1, "%s: wheel up scrolls one row back" % l[0])
		fe._gui_input(pan(0.6))
		fe._gui_input(pan(0.6))
		check(fe.get(l[1]) == 2, "%s: a trackpad pan of 1.2 scrolls one row down" % l[0])
		fe._gui_input(wheel(false))
		fe._gui_input(wheel(false))
		fe._gui_input(wheel(false))
		check(fe.get(l[1]) == 0, "%s: the wheel stops at the first row" % l[0])
	check(fe.EXTRAS.any(func(o): return o[0] == "wheel_scroll"), "Extras has the Mouse wheel row")
	settings().wheel_scroll = "natural"
	settings().pref_page = "Controls"
	fe.ctrl_top = 3
	fe._gui_input(wheel(true))
	check(fe.ctrl_top == 2, "natural: wheel down scrolls up")
	fe._gui_input(wheel(false))
	fe._gui_input(wheel(false))
	check(fe.ctrl_top == 4, "natural: wheel up scrolls down")
	settings().wheel_scroll = "regular"
	# The briefing text (TSD, mission 113).
	settings().mission_id = 113
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	await frames(3)
	fe.tsd.open_briefing(true)
	await frames(3)
	var w = fe.tsd.brief_window
	check(
		is_instance_valid(w) and w._max_scroll() > 3 * w.TEXT_PX,
		"the briefing text scrolls (%.0f px)" % w._max_scroll()
	)
	var body: Rect2 = w._body()
	var down_arrow: Vector2 = Vector2(body.end.x - w.SCROLL_W / 2.0, body.end.y - 4) * w._s()
	w._gui_input(mouse_button(down_arrow, true))
	w._gui_input(mouse_button(down_arrow, false))
	var step: float = w.scroll
	w.scroll = 0.0
	w._gui_input(wheel(true))
	check(
		step == w.TEXT_PX and w.scroll == step,
		"briefing: wheel down scrolls one line, as the down arrow (%.0f px)" % step
	)
	w._gui_input(wheel(true))
	w._gui_input(wheel(false))
	check(w.scroll == step, "briefing: wheel up scrolls one line back")
	w._gui_input(pan(1.0))
	check(w.scroll == 2 * step, "briefing: a trackpad pan scrolls down")
	settings().wheel_scroll = "natural"
	w._gui_input(wheel(true))
	check(w.scroll == step, "briefing, natural: wheel down scrolls up")
	w._gui_input(pan(1.0))
	check(w.scroll == 0.0, "briefing, natural: a pan down scrolls up")
	settings().wheel_scroll = "regular"
