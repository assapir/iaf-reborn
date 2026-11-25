# The F-35I's panoramic display (avionics-plan.md §4 P1-P12, S13-S16; docs/f35i.md §4.3), headless: the Adir on its
# range mission (nevatim_range) set up as the front end's Fly does, with a SPICE 1000 in each bay, put in the air:
# - every MENU format opens by key (Home, Ctrl + F10, End) and by a tap on the MENU grid, and draws in a large portal
#   and in a small window;
# - the layout keys and taps: widen (Ctrl + End, the header's arrows), enlarge (Shift + Home), the function bar's SWAP
#   (Shift + End, its arrows), a window and a tab into their portal, the next window (Ctrl + Home), the five presets
#   (Alt + ,), DMS moving the cursor's portal, a function bar item's pop-up;
# - the CNI: COM1 preset 5 through its keypad, the navigation source to TACAN (the EFI's caret's station);
# - the SMS: the bays, DOORS (Ctrl + Delete) opening and closing them, the SPICE 1000 on 4 / 8, its release with the
#   doors open, the WPN-S's per-bomb rows.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_pcd.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const DEFAULT := ["TSD-1", "SMS", "SRCH", "TFLIR"]

var tv: Node
var p: Control


## A key with modifiers through the key table.
func _key(k: Key, mods := "", down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = "S" in mods
	e.ctrl_pressed = "C" in mods
	e.alt_pressed = "A" in mods
	e.pressed = down
	tv._unhandled_input(e)
	if down:
		_key(k, mods, false)


## Key-table record i's key pressed and released (base.gd record_key: the laptop map's on macOS).
func _rec(i: int) -> void:
	for down in [true, false]:
		tv._unhandled_input(record_key(tv.keys, i, down))


func _until(cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true


func run() -> void:
	await require_data()
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f35i.json")
	IafPilotLog.set_loadout(db, s.pilot(), "f35i", IafBriefing.put(rec, "", 4, "spice-1000", true))
	var id: int = sim_mission("nevatim_range")
	check(load("res://flight/fly.gd").prepare(id), "nevatim_range prepared as the front end's Fly")
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f35i", "")
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-pcd", false).get_current_dir()
	tv.addon.result = {"pass": true}
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 3000.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 220.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.75
	await frames(10)
	p = tv.cockpit.pcd
	check(p != null and p.modern and tv.cockpit.ufc != null, "the Adir's panoramic display, with its CNI's state")
	if p == null:
		return
	check(p.main == DEFAULT and p.windows().size() == 4, "the default layout (%s)" % [p.main])
	await formats()
	await layout()
	await cni()
	await stores()
	tv.queue_free()
	await frames(5)


## Every MENU format by key on the cursor's portal and by a tap on the grid, drawn large and in a window.
func formats() -> void:
	var list: Array = Array(ClassDB.class_call_static("IafPcd", "formats"))
	check(list.size() == 20 and "WPN-S" in list and "CNI" in list and "DAS" in list, "the MENU's 20 formats")
	var by_key := []
	var by_tap := []
	for f in list:
		var i := int(p.st.focus)
		_rec(241)  # MENU
		var steps := posmod(list.find(f) - int(p.st.menu_cur), list.size())
		for k in steps:
			_key(KEY_F10, "C")
		_rec(244)  # select
		await frames(2)
		if p.main[i] != f or p.menu_open[i]:
			by_key.append(f)
		# A tap: the header opens the grid, a tap on the format's button shows it (on portal 0, the large one).
		p.lay.show(0, "EFI" if f != "EFI" else "FUEL")
		p._refresh()
		await frames(1)
		var pr: Rect2 = p.portals()[0]
		p.click(pr.position + Vector2(15.0, p.HEAD_H / 2.0) * p._s())
		await frames(2)
		var b = p.menu_buttons.get(0, {}).get(f)
		if b == null or not p.click(b.get_center()):
			by_tap.append(f)
		await frames(2)
		if p.main[0] != f:
			by_tap.append(f)
	check(by_key.is_empty(), "every format opens from MENU by key (Home, Ctrl + F10, End): failed %s" % [by_key])
	check(by_tap.is_empty(), "every format opens by a tap on the MENU grid: failed %s" % [by_tap])
	# Each in a small window (preset 2, four portals over eight windows: the format cycled down into one).
	p.lay.apply(1)
	for f in list:
		p.lay.show(2, f)
		p.lay.cycle(2)
		p._refresh()
		await frames(1)
		check(p.tabs[2][1] == f, "%s draws in a window" % f)
	p.lay.apply(0)
	p._refresh()


func layout() -> void:
	# DMS right / left (Ctrl + ] / [): the cursor between the shown portals (0, 2, 3 by default).
	p.lay.set_focus(2)
	p._refresh()
	_key(KEY_BRACKETRIGHT, "C")
	check(int(p.st.focus) == 3, "DMS right: the cursor on portal 3")
	_key(KEY_BRACKETRIGHT, "C")
	check(int(p.st.focus) == 0, "DMS right again: past the hidden portal to 0")
	_key(KEY_BRACKETLEFT, "C")
	_key(KEY_BRACKETLEFT, "C")
	check(int(p.st.focus) == 2, "DMS left twice: back on 2 (SRCH)")
	check(tv.cockpit.soi_format() == "FCR", "the cursor on SRCH: the TMS keys act on the radar")
	# Widen (Ctrl + End): SRCH over the right half, the four windows kept; enlarge (Shift + Home): over them.
	_rec(246)  # widen
	await frames(1)
	check(bool(p.st.wide[1]) and not p.shown(3) and p.windows().size() == 4, "Ctrl + End widens SRCH over its half")
	_rec(247)  # enlarge
	await frames(1)
	check(p.windows().is_empty() and Array(p.st.tab_rows[2]).size() == 5, "Shift + Home enlarges it: its tabs")
	_rec(247)  # enlarge
	_rec(246)  # widen
	check(not bool(p.st.wide[1]) and p.windows().size() == 4, "and both back")
	# The header's widen arrows by a tap.
	var pr: Rect2 = p.portals()[3]
	await frames(1)
	p.click(pr.position + Vector2(pr.size.x / p._s() - 40.0, 4.0) * p._s())
	check(bool(p.st.wide[1]) and p.main[2] == "TFLIR", "a tap on the header's arrows widens TFLIR over its half")
	await frames(1)
	p.click(p.portals()[2].position + Vector2(p.portals()[2].size.x / p._s() - 40.0, 4.0) * p._s())
	check(not bool(p.st.wide[1]), "and a second tap splits it again")
	# SWAP: Shift + End trades the function bar's halves (the portals stay), then its arrows trade them back.
	var was: Array = p.main
	_rec(248)  # SWAP
	check(bool(p.st.bar_swapped) and p.main == was, "Shift + End swaps the bar's halves (%s)" % [p.main])
	await frames(1)
	var g: Rect2 = p.glass()
	p.click(Vector2(g.get_center().x, g.position.y + 7.0 * p._s()))
	check(not bool(p.st.bar_swapped), "the function bar's SWAP swaps them back")
	# A window and a tab into their portal; the next window by key.
	p.lay.apply(0)
	p._refresh()
	await frames(1)
	var w: Array = p.windows()[0]  # portal 2's first window (TWD)
	p.click(w[0].get_center())
	check(p.main[2] == "TWD" and p.tabs[2][0] == "SRCH", "a tap on a window swaps TWD into its portal")
	await frames(1)
	p.click(p.portals()[0].position + Vector2(14.0, p.portals()[0].size.y / p._s() - 5.0) * p._s())
	check(p.main[0] == "TSD-2", "a tap on the large portal's first tab shows TSD-2 (%s)" % p.main[0])
	p.lay.set_focus(3)
	p._refresh()
	_rec(245)  # the next window
	check(p.main[3] == "EFI", "Ctrl + Home: the next window into the portal (%s)" % p.main[3])
	# The presets (Alt + ,): 2 to 5 and back to 1, each its split.
	var want := [[4, 8], [2, 0], [3, 4], [4, 6], [3, 4]]
	for n in 5:
		_key(KEY_COMMA, "A")
		await frames(1)
		var portals: int = p.portals().filter(func(r): return r.size != Vector2.ZERO).size()
		check(
			int(p.st.preset) == (n + 1) % 5 and [portals, p.windows().size()] == want[n],
			"preset %d: %d portals over %d windows" % [(n + 1) % 5 + 1, portals, p.windows().size()]
		)
	check(p.main == DEFAULT, "preset 1 is the default layout")
	# A function bar item's pop-up: the radios open the CNI over the portal under them, again closes it.
	var cx: float = g.size.x / p._s() / 2.0
	var at: Vector2 = g.position + Vector2(cx + 20.0, 7.0) * p._s()
	p.click(at)
	check(p.main[2] == "CNI" and int(p.st.popup) == 2, "a tap on the radios pops the CNI up over SRCH")
	await frames(1)
	p.click(at)
	check(p.main[2] == "SRCH" and int(p.st.popup) == -1, "a second tap closes it")


func cni() -> void:
	var c: Control = tv.cockpit
	for b in ["COM1", "5", "ENTR"]:
		p._press("CNI", b)
	check(int(c.ufc.state().uhf_preset) == 5, "the CNI's COM1, 5, ENTR: UHF preset 5 (%s)" % [c.ufc.state()])
	var src: bool = c.ehsi_tcn
	p._press("CNI", "NAV")
	check(c.ehsi_tcn != src, "the CNI's NAV: the navigation source to TACAN")
	c.home_tacan()
	check(not p._tacan().is_empty(), "the TACAN near the home base: %s" % [p._tacan()])
	p._press("CNI", "IDENT")
	check(float(c.ufc.state().ident_until) > p._clock(), "the CNI's IDENT")
	p._press("CNI", "NAV")


func stores() -> void:
	var w = tv.weapons
	var wp: Dictionary = tv.cockpit.weapons
	check(Array(wp.internal) == [2, 3, 5, 6], "the SMS knows the bay stations C D F G (%s)" % [wp.internal])
	var names := [String(wp.stations[2].name), String(wp.stations[6].name)]
	check(
		int(wp.stations[2].count) == 1 and int(wp.stations[6].count) == 1 and names[0] == names[1] and names[0] != "",
		"a SPICE 1000 in each bay, stations 4 / 8 (%s)" % [names]
	)
	# DOORS (Ctrl + Delete): open and held, then shut.
	_rec(250)  # DOORS
	check(await _until(func(): return float(tv.cockpit.weapons.bay) >= 1.0, 3.0), "Ctrl + Delete opens the bay doors")
	await frames(30)
	check(float(tv.cockpit.weapons.bay) >= 1.0, "DOORS holds them open")
	_rec(250)  # DOORS
	check(await _until(func(): return float(tv.cockpit.weapons.bay) <= 0.0, 3.0), "and shuts them")
	# The SPICE 1000 selected: the WPN-S shows each bomb's row; released from its bay with the doors open.
	_key(KEY_BRACKETLEFT)
	await frames(3)
	wp = tv.cockpit.weapons
	check(String(wp.name) == names[0] and wp.gps_bombs.size() == 2, "'[': the SPICE 1000, two bombs on the WPN-S")
	p.lay.show(0, "WPN-S")
	p._refresh()
	await frames(2)
	_key(KEY_A, "S")
	var t: int = w.stores.current_type()
	var before: int = w.stores.total(t, w.stores.current_name())
	var doors_at_release := []
	var r0: int = w.stores.releases
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.physical_keycode = KEY_SPACE
	e.pressed = true
	tv._unhandled_input(e)
	var gone := await _until(
		func():
			if w.stores.releases != r0:
				doors_at_release.append(float(tv.cockpit.weapons.bay))
			return w.stores.total(t, w.stores.current_name()) < before,
		80.0
	)
	e.pressed = false
	tv._unhandled_input(e)
	check(gone, "Space releases a SPICE 1000 from its bay")
	check(w.bay_open(), "the doors commanded open for the release")
	check(
		doors_at_release.is_empty() or doors_at_release[0] >= 1.0,
		"it leaves only with the doors open (%s)" % [doors_at_release.slice(0, 1)]
	)
	await frames(2)
	var rows: Array = tv.cockpit.weapons.gps_bombs
	var left: int = w.stores.total(t, w.stores.current_name())
	check(
		rows.size() == 2 and rows.filter(func(b): return b.gone).size() == before - left,
		"the WPN-S greys each bomb gone (%d of 2 left: %s)" % [left, rows]
	)

	# The Adir's jammer (J; docs/ai.md §15.6): its definition's burn-through on, ECM ON on the ICAWS; off again.
	if tv.cockpit.indicators[6]:
		w.ecm_key()
	w.ecm_key()
	check(is_equal_approx(w.jam_share(), 0.3), "J: the Adir's jammer on (%.2f)" % w.jam_share())
	check(p.cautions().any(func(c): return c[0] == "ECM ON"), "the advisory ECM ON")
	w.ecm_key()
	check(w.jam_share() == 0.0 and not tv.cockpit.indicators[6], "J again: off")
