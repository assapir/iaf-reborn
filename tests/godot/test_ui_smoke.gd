# UI smoke test: every front-end screen, every button on it (except ones that quit or start a flight),
# every Preferences tab (original + ours) and every way to leave Preferences, in English and Hebrew.
# It checks little itself: tools/test.sh fails on any GDScript error printed while this runs, which is
# the point (errors that only show on a path nobody tested).
extends "res://../tests/godot/base.gd"

const SKIP_LABELS := ["quit", "exit", "fly", "flytsd", "jumpin", "multiplayer", "missioncreator"]


func run() -> void:
	for lang in ["en", "he"]:
		if lang == "he" and not Settings().hebrew_available():
			continue
		Settings().language = lang
		var fe = load("res://menu/front_end.tscn").instantiate()
		root.add_child(fe)
		await frames(3)
		var screens: Array = fe.menus.keys().filter(func(k): return fe.menus[k].get("type", "") == "screen")
		var visited := 0
		for s in screens:
			if s in ["tsd", "flytsd", "mptsd", "mpflytsd", "arm", "ipx", "tcp", "netaow", "netmis", "mc", "jump"]:
				continue  # flight / multiplayer / mission creator screens have their own tests or are out of scope
			await _open(fe, s)
			visited += 1
			var panels: Array = fe._panels()
			for p in panels.size():
				for b in panels[p].buttons.size():
					var label := String(panels[p].buttons[b].label).to_lower().replace(" ", "").replace("_", "")
					if SKIP_LABELS.has(label):
						continue
					fe._on_button("%d/%d" % [p, b])
					await _settle(fe)
					_dismiss_box(fe)
					await _open(fe, s)
		check(visited > 10, "%s: visited %d screens and pressed their buttons" % [lang, visited])
		# Preferences: every tab, then leave by BACK (Yes / No / Cancel) and MAIN.
		for exit_path in ["yes", "no", "cancel", "main"]:
			await _open(fe, "pref")
			for page in ["Sound", "Graphics", "Controls", "Devices", "Gameplay"]:
				fe._on_button(fe._key_for_label(page if page != "Controls" else "Keyboard"))
				await frames(3)
			for tab in ["extras", "physics"]:
				fe._on_button(tab)
				await frames(3)
			# Extras "All keys on the Keyboard page": the longer list draws and scrolls to its end.
			fe._on_button("extras")
			await frames(2)
			for it in fe._extras_items():
				if it.key == "show_all_keys" and it.value == true:
					fe._gui_input(mouse_button(fe._to_screen(fe.CONTENT.position + it.rect.get_center()), true))
					fe._gui_input(mouse_button(fe._to_screen(fe.CONTENT.position + it.rect.get_center()), false))
			await frames(2)
			fe._on_button(fe._key_for_label("Keyboard"))
			fe._ctrl_scroll(fe._ctrl_max_top())
			await frames(3)
			check(fe._ctrl_rows().size() == 115, "%s: all keys listed with the Extras option" % lang)
			fe.pref_work["no_blackouts"] = not fe.pref_work.get("no_blackouts", false)  # a change -> Save changes?
			fe._on_button("main" if exit_path == "main" else "back")
			await _settle(fe)
			if fe.msgbox != null:
				var i: int = {"yes": 0, "no": 1, "cancel": 2, "main": 1}[exit_path]
				_click_box(fe.msgbox, i)
				await _settle(fe)
			await frames(10)
		Settings().no_blackouts = false
		check(true, "%s: Preferences tabs and exits" % lang)
		fe.queue_free()
		await frames(3)
	Settings().language = "en"


func _open(fe, s: String) -> void:
	_dismiss_box(fe)
	fe.screen = s
	fe._enter_screen()
	await frames(3)


func _settle(fe) -> void:
	await frames(2)
	var n := 0
	while fe.busy and n < 600:
		await process_frame
		n += 1


func _dismiss_box(fe) -> void:
	if fe.msgbox != null:
		_click_box(fe.msgbox, fe.msgbox.buttons.size() - 1)


func _click_box(box, i: int) -> void:
	var r: Rect2 = box.rects()[i]
	box._gui_input(mouse_button(r.get_center(), true))
	box._gui_input(mouse_button(r.get_center(), false))
