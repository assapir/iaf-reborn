# Pause, On-The-Fly menu, FlyTSD, time compression and the views (docs/views.md, docs/front-end.md §16):
# Ctrl+P freezes the sim (sim time stops) and passes only Ctrl+P; Ctrl+O opens the menu (sim frozen),
# Esc closes it; Esc opens the FlyTSD over the frozen flight and Esc returns; C steps the time rate
# 1 → 2 → 4 → 1 (sim time runs at that rate), Ctrl+C back to 1; Ctrl+M flips Mute.
extends "res://../tests/godot/base.gd"


func press(tv: Node, k: Key, ctrl := false, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	# While the tree is paused the flight's handler sleeps: the overlay takes the keys (as in the game).
	if paused:
		tv.overlay._unhandled_input(e)
	else:
		tv._unhandled_input(e)


func run() -> void:
	var tv = await start_mission(311)
	await frames(5)
	# --- pause ---
	var t0: float = tv._sim_time
	press(tv, KEY_P, true)
	check(tv.paused and paused, "Ctrl+P pauses (scene tree paused)")
	await frames(10)
	check(tv._sim_time == t0, "sim time stops while paused")
	press(tv, KEY_G)
	press(tv, KEY_O, true)
	check(not tv.menu_open and tv.gear_down, "paused: other keys are ignored (menu, gear)")
	press(tv, KEY_P, true)
	check(not tv.paused and not paused, "Ctrl+P again resumes")
	await frames(5)
	check(tv._sim_time > t0, "sim time runs again")
	# --- On-The-Fly menu ---
	press(tv, KEY_O, true)
	check(tv.menu_open and paused, "Ctrl+O opens the menu, sim frozen")
	check(tv.overlay.labels == ["RESUME MISSION", "END MISSION", "RESTART MISSION", "NEW MISSION", "PREFERENCES", "QUIT GAME"],
			"six items (msgs 18-22, 24) %s" % [tv.overlay.labels])
	press(tv, KEY_P, true)
	check(not tv.paused, "Ctrl+P ignored while the menu is open")
	tv.menu_choice("end")
	check(tv._msgbox != null and tv._msgbox.text.begins_with("Are you sure you want to quit the mission"), "End mission asks msg 8")
	tv._on_box_choice("no", func(): pass)
	check(tv._msgbox == null and tv.menu_open, "NO closes the box, the menu stays")
	tv.menu_choice("prefs")
	await frames(3)
	check(tv.fe_overlay != null and tv.fe_overlay.screen == "pref" and not tv.fe_overlay._button_enabled("Gameplay"),
			"Preferences over the flight, Gameplay disabled")
	tv.fe_overlay._on_button("back")
	await frames(2)
	check(tv.fe_overlay == null and tv.menu_open and paused, "BACK returns to the menu, still paused")
	press(tv, KEY_ESCAPE)
	check(not tv.menu_open and not paused, "Esc closes the menu")
	# --- FlyTSD (Esc) ---
	press(tv, KEY_ESCAPE)
	await frames(3)
	check(tv.fe_overlay != null and tv.fe_overlay.screen == "flytsd" and tv.fe_overlay.tsd != null and paused,
			"Esc: FlyTSD over the frozen flight")
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	tv.fe_overlay._unhandled_input(e)
	await frames(2)
	check(tv.fe_overlay == null and not paused, "Esc on the FlyTSD returns to the flight")
	# --- time compression ---
	press(tv, KEY_C)
	check(tv.time_factor == 2 and Engine.time_scale == 2.0, "C: x2")
	await frames(2)
	var s0: float = tv._sim_time
	var r0 := Time.get_ticks_usec()
	await frames(20)
	var ratio: float = (tv._sim_time - s0) / ((Time.get_ticks_usec() - r0) * 1e-6)
	check(ratio > 1.5 and ratio < 2.5, "sim time runs at x2 (%.2f)" % ratio)
	press(tv, KEY_C)
	check(tv.time_factor == 4 and tv.cockpit.time_factor == 4, "C: x4 (shown)")
	press(tv, KEY_C)
	check(tv.time_factor == 1 and Engine.time_scale == 1.0, "C: back to x1")
	press(tv, KEY_C)
	press(tv, KEY_C, true)
	check(tv.time_factor == 1, "Ctrl+C: normal time")
	# Not refused or reset on the ground (no such rule in the original).
	check(tv.flight.state().on_ground, "on the ground")
	press(tv, KEY_C)
	await frames(3)
	check(tv.time_factor == 2, "compression on the ground is allowed and stays")
	press(tv, KEY_C, true)
	# --- mute ---
	var m: bool = Settings().mute
	press(tv, KEY_M, true)
	check(Settings().mute != m, "Ctrl+M flips Mute")
	press(tv, KEY_M, true)
	# --- our keys moved to Ctrl + F-keys ---
	press(tv, KEY_F2, true)
	await frames(1)
	check(not tv.in_cockpit, "Ctrl+F2: external")
	press(tv, KEY_F2, true)
	await frames(1)
	check(tv.in_cockpit, "Ctrl+F2: cockpit")
