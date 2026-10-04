# Controls page and key table (docs/controls.md, docs/front-end.md §12.7): 117 records from the exe,
# record i = keys.trx line i, 92 listed; a click on a row and a key press rebinds it, a taken key
# asks msg 36 (Yes takes it over), DEFAULT restores the table; in flight the rebound key drives the
# command and the old key no longer does.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var kt = load("res://controls/key_table.gd").load_table()
	check(kt.size() == 117, "117 records (%d)" % kt.size())
	check(kt.label(0) == "TSD and cockpit toggle" and kt.key_name(kt.default_key(0)) == "Esc", "record 0 = TSD toggle on Esc")
	check(kt.label(17) == "Eject (x3)" and kt.key_name(kt.default_key(17)) == "E" and kt.records[17].press[0] == 18, "record 17 = Eject on E, command 18")
	check(kt.key_name(kt.default_key(1)) == "Ctrl + Q" and kt.key_name(kt.default_key(40)) == "Shift + W", "modifier names")
	check(kt.button_name(kt.default_joystick(58)) == "Button 3", "joystick button names")
	check(kt.shown_records().size() == 92, "92 listed records (%d)" % kt.shown_records().size())

	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"  # the game starts on Pilot Records
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	fe._on_button(fe._key_for_label("Controls"))
	check(Settings().pref_page == "Controls", "Controls tab")
	check(fe.ctrl_sel == 0 and not fe.ctrl_focus, "first row selected, no keyboard yet")
	# Scroll down one row with the down arrow, then click the row of "Flaps up/down" (list row 16).
	var at: Vector2 = fe.CONTENT.position
	click(fe, at + Vector2(427, 320))
	check(fe.ctrl_top == 1, "down arrow scrolls one row")
	var rows: Array = fe._ctrl_rows()
	var flaps_row: int = rows.find(19)
	fe._ctrl_scroll(flaps_row - 2)
	click(fe, at + Vector2(100, 53 + 2 * 30 + 15))
	check(fe.ctrl_sel == flaps_row and fe.ctrl_focus, "click selects Flaps up/down")
	# A free key: assigned at once.
	key(fe, KEY_K)
	check(kt.key_name(kt.key_of(19, fe.pref_work.key_bindings)) == "K", "Flaps rebound to K")
	check(Settings().key_bindings.is_empty(), "only the working copy changed")
	# A taken key (G = gear): msg 36, Yes takes it from the gear.
	key(fe, KEY_G)
	check(fe.msgbox != null and fe.msgbox.text.begins_with("This key is already assigned"), "taken key asks msg 36")
	var box = fe.msgbox
	var yes: Rect2 = box.rects()[0]
	box._gui_input(mouse_button(yes.get_center(), true))
	box._gui_input(mouse_button(yes.get_center(), false))
	check(kt.key_of(19, fe.pref_work.key_bindings) == 0x22 and kt.key_of(20, fe.pref_work.key_bindings) == 0, "Yes: flaps on G, gear unbound")
	# Shift + key is a different key.
	key(fe, KEY_K, true)
	check(kt.key_name(kt.key_of(19, fe.pref_work.key_bindings)) == "Shift + K", "Shift + K")
	# DEFAULT restores the table.
	click(fe, at + fe.PREF_DEFAULT.get_center())
	check(fe.pref_work.key_bindings.is_empty(), "DEFAULT restores the original keys")
	if OS.get_environment("IAF_SHOT") != "":
		await frames(5)
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("IAF_SHOT"))
	fe.queue_free()
	await frames(2)

	# In flight: gear moved to K; G does nothing any more, K toggles the gear (in the air: mission
	# 311 starts on the ground, where the gear can't be raised, so use flaps instead).
	Settings().key_bindings = {19: [0x25, -1]}  # Flaps on K (DIK 0x25)
	var tv = await start_mission(311)
	var f0: float = tv.flaps
	key(tv, KEY_F)
	check(tv.flaps == f0, "old key F no longer moves the flaps")
	key(tv, KEY_K)
	check(tv.flaps != f0, "rebound key K moves the flaps")
	Settings().key_bindings = {}
	# Throttle presets from the table: key 2 = p1 10 -> 0.10.
	key(tv, KEY_2)
	check(is_equal_approx(tv.throttle, 0.10), "key 2 = throttle 0.10 (%.3f)" % tv.throttle)

	# Extras "All keys on the Keyboard page" (ours): the hidden records (stick, rudder, RPM ± 5, pans)
	# are listed too (cheats and screen capture included), except the two unlabelled records; they rebind like the rest.
	var all: Array = kt.shown_records(true)
	check(all.size() == 115 and 37 in all and 38 in all and 15 in all and 108 in all and 114 in all, "all keys: 115 records incl. rudder, RPM ± 5, cheats, capture (%d)" % all.size())
	check(not 115 in all and not 116 in all, "the two unlabelled records stay out")
	Settings().show_all_keys = true
	fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	fe._on_button(fe._key_for_label("Controls"))
	rows = fe._ctrl_rows()
	var rudder_row: int = rows.find(37)
	check(rudder_row >= 0 and rows.size() == 115, "Keyboard page lists Rudder left")
	fe._ctrl_scroll(rudder_row - 2)
	click(fe, at + Vector2(100, 53 + 2 * 30 + 15))
	check(fe.ctrl_sel == rudder_row and fe.ctrl_focus, "click selects Rudder left")
	key(fe, KEY_K)
	check(kt.key_name(kt.key_of(37, fe.pref_work.key_bindings)) == "K", "Rudder left rebound to K")
	fe.queue_free()
	await frames(2)
	Settings().key_bindings = {37: [0x25, -1]}
	tv = await start_mission(311)
	var e := InputEventKey.new()
	e.keycode = KEY_K
	e.physical_keycode = KEY_K
	e.pressed = true
	Input.parse_input_event(e)
	await frames(20)
	check(tv.rudder < -0.05, "held K deflects the rudder left (%.2f)" % tv.rudder)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	Settings().key_bindings = {}
	Settings().show_all_keys = false
