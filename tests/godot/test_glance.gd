# The V key (ours, docs/controls.md "Own keys"): a tap shows the whole panel (from there, none); held 0.3 s or more,
# its release returns the panel to where it was (a glance down). Mission 311, cockpit.
extends "res://../tests/godot/base.gd"


func v(tv, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_V
	e.physical_keycode = KEY_V
	e.pressed = down
	tv._unhandled_input(e)


func run() -> void:
	var tv = await start_mission(311)
	await frames(3)
	var c = tv.cockpit
	var start: float = c.panel_target
	v(tv, true)
	v(tv, false)
	check(is_equal_approx(c.panel_target, 1.0), "tap V: the whole panel (%.2f)" % c.panel_target)
	v(tv, true)
	v(tv, false)
	check(is_equal_approx(c.panel_target, 0.0), "tap V again: no panel")
	c.panel_target = start
	v(tv, true)
	check(is_equal_approx(c.panel_target, 1.0), "hold V: the whole panel")
	await seconds(0.4)
	v(tv, false)
	check(is_equal_approx(c.panel_target, start), "release after 0.4 s: back to %.2f (a glance)" % start)
