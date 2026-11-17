# The pilot's checklist notebook (modern-iaf/docs/training.md §11), headless: the start-up mission opens it raised at
# START-UP with the first step current and no key named on it; the Checklist notebook key (K) stows and raises it; a
# step taken ticks it and marks the next; the tabs, the wheel, PgUp / PgDn and the page's ‹ › turn it, past a
# section's end into the next; every section has a page; the RADIO page holds the base's frequencies; Hebrew mirrors
# it (tabs on the left); the training ring finds the current step's switch; a take-off mission starts it stowed with
# the jet's start-up checklist on its START-UP page.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_notebook.gd --log-file <temp>
extends "res://tests/test_mvp.gd"


func run() -> void:
	if not ClassDB.class_exists("IafFlight"):
		check(false, "the extension is loaded (cargo build --release -p iaf-godot)")
		return
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("iaf2026-notebook-%d" % OS.get_process_id())
	settings().notebook_help_seen = false
	var tv := await _start("ramon_startup")
	Engine.time_scale = 1.0
	await frames(3)
	var kb: Node = tv.addon.kneeboard
	var nb: Control = kb.board
	check(kb.raised and nb.is_visible_in_tree(), "start-up: the notebook is raised")
	var now := func() -> String: return String(tv.addon.card.current().get("id", ""))
	check(
		nb.current_id() == "startup" and now.call() == "batt", "start-up: at CHECKLIST, BATT current (%s)" % now.call()
	)
	check(kb._help != null, "the first start-up: the help line shows")
	check(settings().notebook_help_seen, "the help line is marked seen")
	var text: String = nb.page_text()
	check("MAIN PWR" in text and not "Ctrl" in text, "START-UP names the switch, no key: %s" % text.left(80))
	# The tower's start-up call first (training.md §3.3): current, no switch ringed until the tower clears the start.
	check(kb.call_pending() and "Call the tower" in text, "START-UP: the tower's start-up call first")
	check(kb._marks().is_empty(), "START-UP: no switch ringed before the clearance")
	var ids: Array = nb.sections.map(func(x): return String(x.id))
	check(ids == ["startup", "taxi", "radio", "landing", "weapons", "emergency", "data"], "the sections %s" % [ids])
	for i in nb.sections.size():
		check(nb._pages[i].size() >= 1 and not nb.sections[i].blocks.is_empty(), "%s has a page" % ids[i])
	# H stows it (into the thigh's texture) and raises it again; K (the GPS bomb's PRE / VIS) leaves it.
	_key(tv, KEY_H)
	check(not kb.raised and nb.get_parent() == kb._vp, "H stows the notebook")
	_key(tv, KEY_K)
	check(not kb.raised, "K leaves the notebook stowed")
	_key(tv, KEY_H)
	check(kb.raised and nb.get_parent() == kb._holder, "H raises it")
	_key(tv, KEY_K)
	check(kb.raised, "K leaves the notebook raised")
	# A step taken: ticked, the next current.
	tv._command([210, 0, 0])
	await frames(2)
	check(now.call() == "flcs_pwr_test" and "✓" in nb.page_text(), "main power taken: ticked, FLCS PWR TEST current")
	# The switch back off undoes its step (cockpit.md "Both ways"): the tick gone, main power current again.
	tv._command([210, -1, 0])
	await frames(2)
	check(
		now.call() == "batt" and not tv.addon.card.done.has("main_power"), "main power back off: unticked, BATT current"
	)
	tv._command([210, 1, 0])
	await frames(2)
	check(now.call() == "flcs_pwr_test", "main power on again: FLCS PWR TEST current")
	tv.addon.pick("startup")
	await frames(2)
	check(not kb.call_pending() and "✓" in nb.page_text(), "the tower's clearance: the call ticked")
	# Turning: a tab click, the wheel, PgDn / PgUp and the footer's ›.
	var radio := ids.find("radio")
	_tap(nb, nb.tab_rect(radio).get_center())
	check(nb.current_id() == "radio", "a click on the RADIO tab opens it")
	check("120.900" in nb.page_text() and "275.800" in nb.page_text(), "RADIO: Ramon's frequencies")
	_wheel(nb, MOUSE_BUTTON_WHEEL_DOWN)
	check(nb.current_id() == "landing", "the wheel turns past RADIO's last page into LANDING")
	_key(tv, KEY_PAGEUP)
	check(nb.current_id() == "radio", "PgUp turns back")
	_tap(nb, nb.arrow_rects()[1].get_center())
	check(nb.current_id() == "landing", "the page's › turns on")
	_tap(nb, nb.arrow_rects()[0].get_center())
	check(nb.current_id() == "radio", "the page's ‹ turns back")
	# The board at the inline-end side, never the centre.
	var ui: Control = tv.addon.ui
	await frames(2)
	var right: float = kb._holder.position.x + nb.W
	check(absf(ui.size.x - right - kb.MARGIN.x) < 1.0, "raised at the right edge (%d of %d)" % [right, ui.size.x])
	# The training ring: on the current step's switch (the JFS), in the view or as an edge pointer.
	nb.open("startup")
	await frames(2)
	check(kb.marks.size() >= 1, "the training mark of the current item (%d)" % kb.marks.size())
	# Hebrew: mirrored, the tabs down the left edge, the board still at the right side.
	settings().language = "he"
	await frames(3)
	check(nb.rtl and nb.tab_rect(0).position.x < nb.paper_rect().position.x, "Hebrew: the tabs on the left")
	check("MAIN PWR" in nb.page_text() and "מתג" in nb.page_text(), "Hebrew: the START-UP page in Hebrew")
	settings().language = "en"
	await frames(3)
	# A take-off mission: stowed, with the jet's start-up checklist.
	tv = await _start("ramon_takeoff")
	Engine.time_scale = 1.0
	await frames(3)
	kb = tv.addon.kneeboard
	check(not kb.raised, "take-off: the notebook starts stowed")
	check(kb.checklist().size() > 40 and kb._help == null, "take-off: the Sufa's checklist card, no help line")
	_key(tv, KEY_H)
	check(kb.raised and kb.board.current_id() == "startup", "take-off: H raises it")
	kb.board.open("taxi")
	check("25R" in kb.board.page_text(), "TAXI / T-O: runway 25R")


func _key(tv: Node, k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	tv._unhandled_input(e)


func _tap(nb: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	nb._gui_input(e)


func _wheel(nb: Control, b: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = true
	nb._gui_input(e)
