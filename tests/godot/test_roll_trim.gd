# Roll trim from the keys (ours, docs/controls.md §2 / §5.2), end to end in the running flight scene: Alt + Right
# held 5 s trims 0.2 stick right; the air start's AP LVL ignores it and holds the wings level; with the autopilot
# off the jet banks right with the stick centred; Alt + Left trims back. The rocker path is in test_joystick.gd.
extends "res://../tests/godot/base.gd"


## The bank, degrees (right wing down +).
func bank(tv: Node) -> float:
	return rad_to_deg(asin(clampf(-float(tv.flight.state().right.y), -1.0, 1.0)))


## A key press / release through Input, Alt as the event's modifier while Alt is held.
func alt_key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.alt_pressed = down or k != KEY_ALT
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func trim(tv: Node, k: Key, s: float) -> void:
	alt_key(KEY_ALT, true)
	alt_key(k, true)
	await fly(tv, s)
	alt_key(k, false)
	alt_key(KEY_ALT, false)


func run() -> void:
	settings().player_flight = 0
	var tv = await start_mission(324)
	check(tv.autopilot.mode == 1, "air start: AP LVL")
	await fly(tv, 1.0)
	var b0 := bank(tv)
	await trim(tv, KEY_RIGHT, 5.0)
	var t: float = tv.flight.roll_trim()
	check(absf(t - 0.2) < 0.01, "Alt + Right 5 s → trim %.3f (≈ 0.2)" % t)
	await fly(tv, 1.0)
	var b1 := bank(tv)
	check(tv.autopilot.mode == 1, "the trim keys leave the autopilot on")
	check(absf(b1 - b0) < 5.0, "AP LVL ignores the trim: wings stay level (%.1f° → %.1f°)" % [b0, b1])
	tv.autopilot._engage(0)
	await fly(tv, 2.0)
	var b2 := bank(tv)
	check(b2 - b1 > 10.0, "AP off: the trim is back, the jet banks right (%.0f° → %.0f°)" % [b1, b2])
	await trim(tv, KEY_LEFT, 5.0)
	check(absf(tv.flight.roll_trim()) < 0.02, "Alt + Left 5 s → back to centre")
