# Roll trim from the keys (ours, docs/controls.md §2 / §5.2), end to end in the running flight scene: Alt + Right
# does nothing under the air start's AP LVL (the wings stay level); with the autopilot off, held 2 s it trims 0.2
# stick right and the jet banks right with the stick centred; Alt + Left trims back. The rocker: test_joystick.gd.
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
	await trim(tv, KEY_RIGHT, 2.0)
	check(tv.flight.roll_trim() == 0.0, "AP LVL: the trim keys don't move the trim (%.3f)" % tv.flight.roll_trim())
	check(tv.autopilot.mode == 1, "the trim keys leave the autopilot on")
	check(absf(bank(tv) - b0) < 5.0, "AP LVL: wings stay level (%.1f° → %.1f°)" % [b0, bank(tv)])
	tv.autopilot._engage(0)
	await fly(tv, 1.0)
	var b1 := bank(tv)
	check(absf(b1 - b0) < 2.0, "AP off, untrimmed: no roll (%.1f° → %.1f°)" % [b0, b1])
	await trim(tv, KEY_RIGHT, 2.0)
	var t: float = tv.flight.roll_trim()
	check(absf(t - 0.2) < 0.01, "Alt + Right 2 s → trim %.3f (≈ 0.2)" % t)
	await fly(tv, 1.0)
	check(bank(tv) - b1 > 10.0, "trimmed, the jet banks right (%.0f° → %.0f°)" % [b1, bank(tv)])
	await trim(tv, KEY_LEFT, 2.0)
	check(absf(tv.flight.roll_trim()) < 0.02, "Alt + Left 2 s → back to centre")
