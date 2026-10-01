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
		await _log_screen(fe, lang)
		# TSD and Arming: a mission with two flights (231) and (English) one with four (136).
		for id in ([231, 136] if lang == "en" else [231]):
			await _tsd_and_arm(fe, id, lang)
		await _extras_imagery(fe, lang)
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
			# Extras "Weapon data: Real" and Physics "Stores weight fix" (their rows fit the page).
			for it in fe._extras_items():
				if it.key == "weapon_data" and it.value == "real":
					fe._gui_input(mouse_button(fe._to_screen(fe.CONTENT.position + it.rect.get_center()), true))
					fe._gui_input(mouse_button(fe._to_screen(fe.CONTENT.position + it.rect.get_center()), false))
			await frames(2)
			check(fe.pref_work.get("weapon_data") == "real", "%s: Extras Weapon data set to Real" % lang)
			fe._on_button("physics")
			fe.phys_top = fe._phys_max_top()  # the last rows (scrolled to the end)
			await frames(2)
			var rows: Array = fe._physics_items().filter(func(i): return i.key == "fix_stores_weight")
			check(rows.size() == 1 and rows[0].rect.end.y <= fe.CONTENT.size.y, "%s: Physics lists Stores weight fix inside the page" % lang)
			fe._on_button("extras")
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


## Extras page (scrolls like Physics): one terrain-imagery row per region, Original first; a layer that is not converted is greyed
## and a click on it keeps the choice; every row fits the page.
func _extras_imagery(fe, lang: String) -> void:
	await _open(fe, "pref")
	fe._on_button("extras")
	await frames(2)
	var click := func(q: Vector2):
		fe._gui_input(mouse_button(fe._to_screen(fe.CONTENT.position + q), true))
		fe._gui_input(mouse_button(fe._to_screen(fe.CONTENT.position + q), false))
	check(fe._extras_max_top() > 0 and fe._extras_items().all(func(i): return i.rect.end.y <= fe.PREF_DEFAULT.position.y),
			"%s: Extras scrolls; the shown rows end above DEFAULT" % lang)
	fe._extras_scroll(fe._extras_max_top())  # the imagery rows are the last ones
	await frames(2)
	var items: Array = fe._extras_items()
	check(items.all(func(i): return i.rect.end.y <= fe.CONTENT.size.y and i.rect.position.x >= 0.0 and i.rect.end.x <= fe.CONTENT.size.x),
			"%s: every Extras choice inside the page" % lang)
	for key in ["imagery_israel", "imagery_outside"]:
		var row: Array = items.filter(func(i): return i.key == key)
		check(row.size() >= 2 and row[0].value == "original" and row[0].available, "%s: %s row, Original first" % [lang, key])
		var missing: Array = row.filter(func(i): return not i.available)
		if not missing.is_empty():
			click.call(missing[0].rect.get_center())
			check(fe.pref_work[key] == "original", "%s: %s: %s is not converted -> greyed, not picked" % [lang, key, missing[0].value])
		click.call(row[0].rect.get_center())
		check(fe.pref_work[key] == "original", "%s: %s set to Original" % [lang, key])
	await frames(2)


## The TSD's buttons (all but Fly), then Arming: every flight and tab button, a drag from one station
## to another, a right-click, DEFAULT, a failed check, TacticalDisplay / BACK with "Use weapon load?".
func _tsd_and_arm(fe, id: int, lang: String) -> void:
	Settings().mission_id = id
	fe._reset_tsd_checks()
	fe.tsd_return = "jet"
	await _open(fe, "tsd")
	var flights := ["alpha", "bravo", "charlie", "delta"]
	var exist: Array = flights.filter(func(f): return fe.tsd.flights.has(flights.find(f) + 1))
	for p in fe._panels().size():
		for b in fe._panels()[p].buttons.size():
			var label := String(fe._panels()[p].buttons[b].label).to_lower()
			if label in ["fly", "arm"] or not fe._button_enabled(label):
				continue
			fe._on_button("%d/%d" % [p, b])
			await _settle(fe)
			_dismiss_box(fe)
	check(fe.screen == "tsd", "%s %d: TSD buttons pressed" % [lang, id])
	fe._on_button(fe._key_for_label(exist[0].capitalize()))
	await _settle(fe)
	fe._on_button(fe._key_for_label("Arm"))
	await _settle(fe)
	check(fe.screen == "arm" and fe.arm != null, "%s %d: Arming opened from the TSD" % [lang, id])
	var enabled: Array = flights.filter(func(f): return fe._button_enabled(f.capitalize()))
	check(enabled == exist.filter(func(f): return fe.tsd.flight_enabled(flights.find(f) + 1)) and enabled.size() <= exist.size(),
		"%s %d: Arming flight buttons enabled only for the mission's flights %s" % [lang, id, enabled])
	if id == 231:
		check(not fe._button_enabled("Charlie") and not fe._button_enabled("Delta"), "%s 231: no Charlie / Delta flight -> disabled" % lang)
	for f in enabled + [enabled[0]]:
		fe._on_button(fe._key_for_label(f.capitalize()))
		await _settle(fe)
		_dismiss_box(fe)
		check(fe.arm.flight == flights.find(f) + 1 and fe.tsd_checks.get(f, false), "%s %d: Arming shows %s" % [lang, id, f])
	for t in ["AG", "Misc", "AA"]:
		fe._on_button(fe._key_for_label(t))
		await frames(2)
	check(fe.arm.tab == 0 and fe.checked.get(fe._key_for_label(enabled[0].capitalize()), false), "%s %d: tabs keep the flight checked" % [lang, id])
	var arm = fe.arm
	var st: Dictionary = arm.jet.get("stations", {})
	var ld: Array = arm.current_load()
	var from := -1
	for i in st:
		if int(ld[i][1]) > 0:
			from = i
			break
	if from >= 0:
		# Drag the store to the mirror station, right-click it, then DEFAULT.
		var to := 8 - from if st.has(8 - from) else from
		var box = func(i): return fe._to_screen(arm.CLIENT.position + st[i] + Vector2(10, 10))
		arm._gui_input(mouse_button(box.call(from), true))
		var mv := InputEventMouseMotion.new()
		mv.position = box.call(to)
		arm._gui_input(mv)
		await frames(2)
		arm._gui_input(mouse_button(box.call(to), false))
		check(int(arm.current_load()[to][1]) > 0, "%s %d: dragged station %d to %d" % [lang, id, from + 1, to + 1])
		var rc := InputEventMouseButton.new()
		rc.button_index = MOUSE_BUTTON_RIGHT
		rc.pressed = true
		rc.position = box.call(to)
		arm._gui_input(rc)
		var def: Vector2 = fe._to_screen(arm.CLIENT.position + arm.DEFAULT_RECT.get_center())
		arm._gui_input(mouse_button(def, true))
		arm._gui_input(mouse_button(def, false))
		check(arm.current_load() == fe.mission_weapons.defaults[arm.flight], "%s %d: DEFAULT restores the loads" % [lang, id])
	# A list row: select it and drag its icon onto a station.
	var row: Vector2 = fe._to_screen(arm._row_box(0) + Vector2(20, 12))
	arm._gui_input(mouse_button(row, true))
	arm._gui_input(mouse_button(row, false))
	await frames(2)
	# A load that fails the checks: TacticalDisplay shows the warning and stays.
	for i in st:
		fe.mission_weapons.put(arm.flight, i, {})
	var heavy := {}
	for w in fe.mission_weapons.weapons:
		if w.max[0] > 0 and w.weight > heavy.get("weight", 0.0):
			heavy = w
	if not heavy.is_empty():
		fe.mission_weapons.put(arm.flight, 0, heavy)
		fe._on_button(fe._key_for_label("TacticalDisplay"))
		await _settle(fe)
		check(fe.msgbox != null and fe.screen == "arm", "%s %d: unbalanced load -> warning, stays on Arming" % [lang, id])
		_dismiss_box(fe)
		fe.mission_weapons.put(arm.flight, 0, {})
	# Changed load: TacticalDisplay asks "Use weapon load?"; No reverts.
	fe._on_button(fe._key_for_label("TacticalDisplay"))
	await _settle(fe)
	check(fe.msgbox != null, "%s %d: Use weapon load? asked" % [lang, id])
	if fe.msgbox != null:
		_click_box(fe.msgbox, 1)
		await _settle(fe)
	check(fe.screen == "tsd" and not fe.mission_weapons.changed(), "%s %d: No -> TSD, load reverted" % [lang, id])
	# Arming again, change and leave by BACK with Yes: the load goes on the aircraft.
	fe._on_button(fe._key_for_label("Arm"))
	await _settle(fe)
	var n: int = fe.arm.flight
	fe.mission_weapons.put(n, 0, {})
	fe.mission_weapons.put(n, 8, {})
	fe._on_button("back")
	await _settle(fe)
	if fe.msgbox != null:
		_click_box(fe.msgbox, 0)
		await _settle(fe)
	check(fe.screen == "tsd" and Settings().arm_loadouts.get(n, []) == fe.mission_weapons.saved[n], "%s %d: BACK + Yes -> TSD, load on the aircraft" % [lang, id])
	fe._on_button("main")
	await _settle(fe)
	_dismiss_box(fe)
	await _settle(fe)
	Settings().arm_loadouts = {}


## Pilot Records (screen 0): a dozen pilots (the list scrolls), every tab by mouse with a recorded history
## (Kills / Losses icons and totals), the list's rows, arrows, track and thumb, both edit boxes, the photo.
func _log_screen(fe, lang: String) -> void:
	var Pilots = load("res://menu/pilots.gd")
	await _open(fe, "log")
	var rec = fe.records
	var kills := [[110, 28], [150, 28], [220, 3], [230, 3], [0, 2], [250, 5], [260, 6], [270, 5], [290, 8], [380, 15], [400, 12], [410, 12]]
	Pilots.record(rec.data.current().id, 111, {"result": 1, "bonus": 1500, "kills": kills + kills, "losses": [[100, 28], [250, 5], [400, 12]]}, 1.0)
	Pilots.record(rec.data.current().id, 112, {"result": 0, "bonus": -750, "kills": [], "losses": []}, 1.0)
	rec._select(rec.data.selected)
	while rec.data.pilots.size() < 13:
		rec.new_pilot()
		rec.edit = ["P%d" % rec.data.pilots.size(), "C%d" % rec.data.pilots.size()]
		await frames(1)
	var at = func(p: Vector2) -> Vector2: return fe._to_screen(p)
	var press = func(p: Vector2, double := false):
		rec._gui_input(mouse_button(at.call(p), true, double))
		rec._gui_input(mouse_button(at.call(p), false))
	var bar: Rect2 = Rect2(rec.LIST + rec.BAR.position, rec.BAR.size)
	for y in [bar.position.y + 5, bar.end.y - 5, bar.end.y - 25, bar.position.y + 25]:
		press.call(Vector2(bar.get_center().x, y))
		await frames(2)
	var thumb := Vector2(bar.get_center().x, rec._thumb_y() + 10)
	rec._gui_input(mouse_button(at.call(thumb), true))
	var mv := InputEventMouseMotion.new()
	mv.position = at.call(thumb + Vector2(0, 100))
	rec._gui_input(mv)
	rec._gui_input(mouse_button(mv.position, false))
	check(rec.top == rec._max_top(), "%s: Pilot Records list scrolled to the end by the thumb" % lang)
	press.call(rec.LIST + rec.ITEMS.position + Vector2(20, 3))
	rec._select(0)
	for t in [1, 2, 3, 0]:
		press.call(rec.CONTENT + Vector2(rec.TAB_X[t] + 10, rec.STRIP.y + 10))
		await frames(3)
		check(rec.tab == t, "%s: Pilot Records tab %s" % [lang, rec.TAB_ART[t]])
	var page: Vector2 = rec.CONTENT + rec.PAGE
	for box in [rec.NAME_BOX, rec.CALL_BOX]:
		press.call(page + box.get_center())
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = "x".unicode_at(0)
		rec._unhandled_input(e)
		await frames(2)
	press.call(page + rec.PHOTO.get_center())
	await frames(2)
	_dismiss_box(fe)
	check(rec.totals.score > 0 and rec.totals.kill_groups.max() > 0, "%s: Pilot Records shows a history" % lang)


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
