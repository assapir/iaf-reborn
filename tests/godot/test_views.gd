# Pause, On-The-Fly menu, FlyTSD, time compression and the views (docs/views.md, docs/front-end.md §16):
# Views: F1 cockpit / HUD only, F10 chase behind the jet, F9 fly-by gliding in, snaps and F2 back view while
# held, cockpit pans (free look), orbit pans / zoom in the external views, padlock, targets missing = no change,
# a followed object destroyed = wreck circle.
# Ctrl+P freezes the sim (sim time stops) and passes only Ctrl+P; Ctrl+O opens the menu (sim frozen),
# Esc closes it; Esc opens the FlyTSD over the frozen flight and Esc returns; C steps the time rate
# 1 → 2 → 4 → 1 (sim time runs at that rate), Ctrl+C back to 1; Ctrl+M flips Mute.
extends "res://../tests/godot/base.gd"


func press(tv: Node, k: Key, ctrl := false, shift := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = down
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

	# --- views ---
	var V = tv.Views
	check(tv.views.type == V.COCKPIT and tv.cockpit.view_mode == 0, "starts in the cockpit")
	press(tv, KEY_F1)
	await frames(1)
	check(tv.views.type == V.HUD_ONLY and tv.cockpit.view_mode == 1 and tv.in_cockpit, "F1: HUD only")
	press(tv, KEY_F1)
	check(tv.views.type == V.COCKPIT, "F1 again: cockpit")
	# Snap 90 left while Numpad 4 is held, back on release; F2 back view.
	press(tv, KEY_KP_4)
	await frames(2)
	check(tv.views.snap != null and is_equal_approx(tv.views.head_angles().x, -PI / 2), "Numpad 4: snap 90 left")
	check(tv.cockpit.position.x > 0.0, "the panel pans right off the view")
	press(tv, KEY_KP_4, false, false, false)
	check(tv.views.snap == null and tv.views.type == V.COCKPIT, "release: back to the cockpit")
	press(tv, KEY_F2)
	await frames(1)
	var h: Vector2 = tv.views.head_angles()
	check(is_equal_approx(h.x, PI) and is_equal_approx(h.y, 0.20944), "F2 held: back view (180°, 12° up)")
	var ldir: Vector3 = -tv.camera.global_basis.z
	check(ldir.dot(-tv.rig.global_basis.z) < -0.9, "the camera looks backwards")
	press(tv, KEY_F2, false, false, false)
	check(tv.views.snap == null, "F2 released")
	# Cockpit pan right: free look, accelerating; release stops.
	press(tv, KEY_KP_6, false, true)
	check(tv.views.type == V.FREE_LOOK, "Shift+Numpad 6: free look")
	await create_timer(1.0).timeout  # 2·t·(1 − 0.9^t)·45°/s: about 9° after 1 s
	var y1: float = tv.views.head_angles().x
	check(y1 > 0.0, "the head turns right (%.3f)" % y1)
	press(tv, KEY_KP_6, false, true, false)
	await frames(10)
	check(is_equal_approx(tv.views.head_angles().x, tv.views.head.x) and tv.views.head.x >= y1, "release: the head stays")
	press(tv, KEY_F1)
	check(tv.views.type == V.COCKPIT and not tv.views._ret.is_empty(), "F1: the head returns to straight ahead (45°/s)")
	await frames(120)
	check(tv.views.head_angles() == Vector2.ZERO, "head back to (0, 0)")
	# Views with a missing object do nothing (no radar target, threat, wingman, weapon here).
	for k in [KEY_F3, KEY_F4, KEY_F5, KEY_F7, KEY_F8, KEY_F11]:
		press(tv, k)
	check(tv.views.type == V.COCKPIT, "F3 F4 F5 F7 F8 F11 without their object: no change")
	# F10 chase: behind the jet along its path, 10° up, 3·dmin away.
	press(tv, KEY_F10)
	await frames(3)
	check(tv.views.type == V.CHASE and tv.chase.current and not tv.in_cockpit and tv.cockpit.view_mode == 2, "F10: chase, messages only")
	var rel: Vector3 = tv.chase.global_position - tv.rig.global_position
	var back: float = rel.dot(tv.rig.global_basis.z)
	check(back > 0.0 and absf(rel.length() - tv.views.dist) < 1.0 + 0.2 * tv.views.dist, "the camera is behind the jet at the rope length (%.0f m, dist %.0f)" % [rel.length(), tv.views.dist])
	check(tv.views.dist == 3.0 * tv.views.dmin, "start distance 3·dmin (%.1f)" % tv.views.dmin)
	var d0: float = tv.views.dist
	press(tv, KEY_KP_SUBTRACT)
	await frames(20)
	press(tv, KEY_KP_SUBTRACT, false, false, false)
	check(tv.views.dist > d0, "Numpad −: the orbit distance grows (60 m/s)")
	var hd: float = tv.views.orbit_heading
	press(tv, KEY_KP_6, false, true)
	await frames(10)
	press(tv, KEY_KP_6, false, true, false)
	check(tv.views.orbit_heading > hd, "Shift+Numpad 6: the orbit turns")
	# F9 fly-by: from a random offset point gliding into the chase position (0.3^t).
	press(tv, KEY_F9)
	check(tv.views.type == V.FOLLOW and not tv.views._swoop.is_empty(), "F9: fly-by (type 9) with the swoop")
	# F6 / padlock on an object: a test object in front of the jet.
	var obj := Node3D.new()
	tv.add_child(obj)
	obj.global_position = tv.rig.global_position - tv.rig.global_basis.z * 2000.0 + tv.rig.global_basis.x * 2000.0
	tv.padlock_target = obj
	press(tv, KEY_F1)
	press(tv, KEY_F3)
	check(tv.views.type == V.PADLOCK and tv.in_cockpit, "F3: padlock the stored target")
	await frames(60)
	check(tv.views.head_angles().x > 0.2, "the head follows the target to the right (%.2f)" % tv.views.head_angles().x)
	# A followed object destroyed: wreck circle.
	tv.views.set_orbit(obj, tv.CHASE_OFFS, 1.0, V.FLYBY, false)
	await frames(2)
	obj.free()
	await frames(2)
	check(tv.views.type == V.WRECK and tv.chase.current, "the followed object is gone: circle its last position")
	press(tv, KEY_F1)
	check(tv.views.type in [V.COCKPIT, V.HUD_ONLY], "F1 back")
