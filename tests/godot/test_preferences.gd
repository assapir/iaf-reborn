# Preferences (docs/front-end.md §12): the first visit opens Sound; Gameplay's NO BLACKOUTS toggles in
# the working copy only; leaving asks "Save changes?" (Yes / No / Cancel) and Yes commits; the
# scoring strip shows frame 4 (100 %) for the defaults.
extends "res://../tests/godot/base.gd"


## Clicks message box button `i`.
func click_box(box: Control, i: int) -> void:
	var r: Rect2 = box.rects()[i]
	box._gui_input(mouse_button(r.get_center(), true))
	box._gui_input(mouse_button(r.get_center(), false))


func run() -> void:
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"  # the game starts on Pilot Records
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	check(fe.screen == "pref", "Main -> Preferences")
	check(Settings().pref_page == "Sound", "first visit opens Sound")
	check(fe.checked.get(fe._key_for_label("Sound"), false), "Sound tab lit")
	check(fe._score_frame(fe.pref_work) == 4, "defaults score 100 % (frame 4)")
	check(fe.pref_work.easy_landing and fe.pref_work.ai_level == 1, "defaults: Easy Landing on, Normal AI")
	fe._on_button(fe._key_for_label("Gameplay"))
	check(Settings().pref_page == "Gameplay", "Gameplay tab")
	# NO BLACKOUTS: page rect (24,78)-(154,113).
	click(fe, fe.CONTENT.position + Vector2(60, 95))
	check(fe.pref_work.no_blackouts and not Settings().no_blackouts, "NO BLACKOUTS toggled in the working copy only")
	check(fe._score_frame(fe.pref_work) == 6, "NO BLACKOUTS costs 10 % (frame 6)")
	# Expert AI adds 20 %.
	click(fe, fe.CONTENT.position + Vector2(200, 130))
	check(fe.pref_work.ai_level == 2 and fe._score_frame(fe.pref_work) == 2, "Expert AI: 110 % (frame 2)")
	click(fe, fe.CONTENT.position + Vector2(200, 95))
	fe._on_button("back")
	await settle(fe)
	check(fe.msgbox != null and fe.msgbox.text == "Save changes?", "leaving asks Save changes?")
	check(fe.msgbox.buttons == ["yes", "no", "can"] and fe.msgbox.button_xs() == [40.0, 130.0, 220.0], "Yes / No / Cancel at 40 / 130 / 220")
	# Cancel stays on the screen.
	click_box(fe.msgbox, 2)
	await settle(fe)
	check(fe.screen == "pref" and fe.msgbox == null and fe.pref_work.no_blackouts, "Cancel stays with the edits")
	fe._on_button("back")
	click_box(fe.msgbox, 0)
	await settle(fe)
	check(Settings().no_blackouts, "Yes commits NO BLACKOUTS")
	check(fe.screen == "main", "then goes back to Main")
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	check(Settings().pref_page == "Gameplay", "Preferences reopens the last page")
	fe._on_button("back")
	await settle(fe)
	check(fe.msgbox == null and fe.screen == "main", "no changes: no question")
	# Physics tab (ours): one check per "Better physics" option, ALL ON / ALL OFF.
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	fe._on_button("physics")
	check(Settings().pref_page == "Physics", "Physics tab")
	var items: Array = fe._physics_items()
	click(fe, fe.CONTENT.position + items[7].rect.get_center())
	check(fe.pref_work.better.fbw_departure and not fe.pref_work.better.ground_effect, "one option toggles alone")
	var by_key := func(k): return items.filter(func(i): return i.key == k)[0]
	click(fe, fe.CONTENT.position + by_key.call("all").rect.get_center())
	check(Settings().BETTER.keys().all(func(id): return fe.pref_work.better[id]), "ALL ON sets every option")
	if OS.get_environment("IAF_SHOT") != "":
		await frames(5)
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("IAF_SHOT"))
	click(fe, fe.CONTENT.position + by_key.call("none").rect.get_center())
	check(not Settings().BETTER.keys().any(func(id): return fe.pref_work.better[id]), "ALL OFF clears them")
	# Leaving from the Physics page (Save changes? -> Yes) draws the page while the working copy is gone.
	click(fe, fe.CONTENT.position + items[0].rect.get_center())
	fe._on_button("back")
	await settle(fe)
	click_box(fe.msgbox, 0)
	await settle(fe)
	await frames(10)
	check(fe.screen == "main" and Settings().better.flight_path_hold, "leaving from Physics commits without errors")
	Settings().better.flight_path_hold = false
	# Extras DEFAULT (ours): every Extras option back to its default, the language kept.
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	fe._on_button("extras")
	fe.pref_work["blackbox"] = false
	fe.pref_work["flight_data"] = "real"
	click(fe, fe.CONTENT.position + fe.PREF_DEFAULT.get_center())
	check(fe.pref_work.blackbox and fe.pref_work.flight_data == "original", "Extras DEFAULT restores the defaults")
	fe._on_button("back")
	await settle(fe)
	if fe.msgbox != null:
		click_box(fe.msgbox, 1)
		await settle(fe)
	# Devices DETENT = MIL (ours): the click edits the working copy; Back -> No keeps the stored value,
	# Back -> Yes stores it.
	Settings().throttle_detent = 60
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	fe._on_button(fe._key_for_label("Devices"))
	click(fe, fe.CONTENT.position + fe.PREF_DETENT.off.get_center())
	check(fe.pref_work.throttle_detent == -1 and Settings().throttle_detent == 60, "DETENT OFF in the working copy only")
	fe._on_button("back")
	await settle(fe)
	click_box(fe.msgbox, 1)
	await settle(fe)
	check(Settings().throttle_detent == 60, "Back -> No keeps the detent")
	fe._on_button(fe._key_for_label("Preferences"))
	await settle(fe)
	click(fe, fe.CONTENT.position + fe.PREF_DETENT.off.get_center())
	fe._on_button("back")
	await settle(fe)
	click_box(fe.msgbox, 0)
	await settle(fe)
	check(Settings().throttle_detent == -1, "Back -> Yes stores the detent")
