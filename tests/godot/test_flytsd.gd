# The in-flight TSD (FlyTSD, docs/views.md §1, docs/front-end.md §8): the live map (current positions, downed
# formations leave it and their buttons close, the clock runs), the ruler (right-drag: "%.2f NM", "%03d T"), the map
# keys (arrows, Page Up / Down, Numpad + / −, Insert), no waypoint drag in flight, the selected-unit label, Ctrl+P's
# pause, Visit (the camera follows a unit, Esc gives the TSD again) and Fly into another formation's jet: the same
# type, the wingman's seat when the leader is down, back again, and another type (cockpit, model, weapons).
extends "res://../tests/godot/base.gd"


func key_event(k: Key, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e


func right(at: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = down
	e.position = at
	return e


func motion(at: Vector2, mask: int) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = mask
	return e


func open_tsd(tv: Node) -> Control:
	tv._esc_key()
	await frames(3)
	return tv.fe_overlay


## Window position of a TSD client point.
func screen_of(fe: Control, c: Vector2) -> Vector2:
	return fe._to_screen(fe.tsd.CLIENT.position + c)


func run() -> void:
	var tv = await start_mission(221)  # Back to the Wall: Alpha and Bravo, two F-16s each
	await frames(10)
	var rt = tv.runtime
	var fe: Control = await open_tsd(tv)
	var tsd = fe.tsd
	check(fe.screen == "flytsd" and tsd != null and paused, "Esc: the FlyTSD over the frozen flight")
	var t := int(float(rt.misc.get("0x460", 0.0)) + rt.now)
	check(
		tsd.mission_clock == "%02d:%02d:%02d" % [t / 3600 % 24, t / 60 % 60, t % 60], "the clock is the time of day now"
	)
	var me: Dictionary = rt.player_entity()
	var mine: Array = tsd.units.filter(func(u): return u.key == me.key)
	var w: Vector3 = tv.player_world()
	check(
		mine.size() == 1 and mine[0].pos.distance_to(tsd.world_to_map(w.x, w.y)) < 0.001,
		"the own jet at its live position"
	)
	check(tsd.default_flight() == 1 and tsd.units[tsd.selected].key == me.key, "the player's flight and jet selected")

	# --- the selected-unit label ---
	check(tsd.unit_label(tsd.units[tsd.selected]) == "F-16", "label line 1: the type (F-16)")
	check(tsd.unit_label({"type": 450, "cls": 12, "name": "Ramon RW"}) == "Ramon RW", "a runway shows its own name")
	check(tsd.unit_label({"type": 999, "cls": 9, "name": ""}) == "IR-SAM", "an unlisted type falls back to its class")

	# --- keys (WM_KEYDOWN 5023e0) ---
	for i in 3:
		tsd.zoom_by(tsd.ZOOM_STEP)
	tsd.centre_on(tsd.MAP_SIZE / 2)
	var s0: Vector2 = tsd.scroll
	fe._unhandled_input(key_event(KEY_RIGHT))
	fe._unhandled_input(key_event(KEY_DOWN))
	check(tsd.scroll.is_equal_approx(s0 + Vector2(5, 5)), "arrows scroll 5 map units")
	fe._unhandled_input(key_event(KEY_PAGEUP))
	check(is_equal_approx(tsd.scroll.y, s0.y + 5 - tsd.CLIENT.size.y / tsd.zoom), "Page Up: one page up")
	var z0: float = tsd.zoom
	fe._unhandled_input(key_event(KEY_KP_ADD))
	check(is_equal_approx(tsd.zoom, z0 * 1.5), "Numpad +: zoom in ×1.5")
	fe._unhandled_input(key_event(KEY_KP_SUBTRACT))
	fe._unhandled_input(key_event(KEY_INSERT))
	check(is_equal_approx(tsd.zoom, z0 / 1.5), "Numpad − and Insert: zoom out")

	# --- the ruler (5022d0 / 501cb0 / 502380, paint 501300) ---
	check(tsd.ruler_distance(Vector2.ZERO, Vector2(18520, 0)) == "10.00 NM", '10 NM east: "10.00 NM"')
	check(tsd.ruler_bearing(Vector2.ZERO, Vector2(18520, 0)) == "090 T", 'east: "090 T"')
	check(
		(
			tsd.ruler_bearing(Vector2.ZERO, Vector2(0, 1000)) == "000 T"
			and tsd.ruler_bearing(Vector2.ZERO, Vector2(0, -1000)) == "180 T"
			and tsd.ruler_bearing(Vector2.ZERO, Vector2(-1000, -1)) == "269 T"
		),
		"north 000, south 180, west-south-west 269 (truncated)"
	)
	var c1: Vector2 = tsd.CLIENT.size / 2 - Vector2(60, 0)
	var c2: Vector2 = c1 + Vector2(120, 0)
	tsd._gui_input(right(screen_of(fe, c1), true))
	check(tsd.ruler_on and tsd.ruler_a == tsd.ruler_b, "right press starts the ruler")
	tsd._gui_input(motion(screen_of(fe, c2), MOUSE_BUTTON_MASK_RIGHT))
	tsd._gui_input(right(screen_of(fe, c2), false))
	var expect: float = 120.0 / tsd.zoom * tsd.WORLD_W / (tsd.MAP_SIZE.x * tsd.MAP_X_FACTOR)
	check(
		(
			tsd.ruler_kept
			and not tsd.ruler_on
			and absf(tsd.ruler_a.distance_to(tsd.ruler_b) - expect) < 2.0 * expect / 120.0
			and tsd.ruler_bearing(tsd.ruler_a, tsd.ruler_b) == "090 T"
		),
		"right drag measures (kept after the release)"
	)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the cursor is back after the drag")

	# --- no waypoint drag in flight (501cb0 moves it only before the flight) ---
	var pts: Array = tsd.flights[1].points
	var wi := -1
	for i in pts.size():
		if tsd.unit_at(tsd._to_client(pts[i])) < 0:
			wi = i
	if wi >= 0:
		tsd.centre_on(pts[wi])
		var before: Vector2 = pts[wi]
		var at := screen_of(fe, tsd._to_client(pts[wi]))
		tsd._gui_input(mouse_button(at, true))
		tsd._gui_input(motion(at + Vector2(30, 0), MOUSE_BUTTON_MASK_LEFT))
		tsd._gui_input(mouse_button(at + Vector2(30, 0), false))
		check(tsd.flights[1].points[wi] == before, "in flight a waypoint does not move")
	else:
		check(false, "a waypoint off the icons to drag")

	# --- Ctrl+P (FUN_004edbc0 / FUN_004ede30) ---
	fe._unhandled_input(key_event(KEY_P, true))
	check(fe.tsd_pause != null, "Ctrl+P on the FlyTSD pauses (dithered snapshot)")
	var s1: Vector2 = tsd.scroll
	fe._unhandled_input(key_event(KEY_LEFT))
	fe._unhandled_input(key_event(KEY_ESCAPE))
	await frames(2)
	check(tsd.scroll == s1 and tv.fe_overlay != null, "paused: the other keys are ignored (arrows, Esc)")
	check(fe.tsd_pause.mouse_filter == Control.MOUSE_FILTER_STOP, "paused: the window takes no clicks")
	fe._unhandled_input(key_event(KEY_P, true))
	await frames(1)
	check(fe.tsd_pause == null, "Ctrl+P again resumes the FlyTSD")

	# --- Visit (FUN_005046b0 → FUN_004d3450) ---
	var vi := -1
	for i in tsd.units.size():
		var ent: Dictionary = rt.entities.get(tsd.units[i].key, {})
		if tsd.units[i].klass != 1 and ent.get("node") is Node3D:
			vi = i
			break
	check(vi >= 0, "a ground unit to visit")
	var visited: Node3D = rt.entities[tsd.units[vi].key].node
	tsd.selected = vi
	fe._on_button(fe._key_for_label("Visit"))
	await frames(3)
	check(tv.fe_overlay == null and not paused, "Visit returns to the flight")
	check(
		tv.views.type == tv.Views.FOLLOW and tv.views.target == visited, "the camera follows the visited unit (type 9)"
	)
	check(rt.player_entity() == me, "Visit keeps the player in the own jet")
	fe = await open_tsd(tv)
	tsd = fe.tsd
	check(fe != null and fe.screen == "flytsd", "Esc while visiting: the FlyTSD again")

	# --- double-click: a unit you cannot fly is visited ---
	tsd.select_flight(1)
	while tsd.can_zoom_in():
		tsd.zoom_by(tsd.ZOOM_STEP)
	var gi := -1
	for i in tsd.units.size():
		if tsd.units[i].klass != 1 and tsd.units[i].key != tsd.units[vi].key:
			tsd.centre_on(tsd.units[i].pos)
			if tsd.unit_at(tsd._to_client(tsd.units[i].pos)) == i:
				gi = i
				break
	if gi >= 0:
		var gkey: String = tsd.units[gi].key
		tsd._gui_input(mouse_button(screen_of(fe, tsd._to_client(tsd.units[gi].pos)), true, true))
		await frames(3)
		check(
			(
				tv.fe_overlay == null
				and tv.views.type == tv.Views.FOLLOW
				and tv.views.target == rt.entities[gkey].get("node")
			),
			"double-clicking a ground unit visits it"
		)
		fe = await open_tsd(tv)
		tsd = fe.tsd
	else:
		check(false, "a ground unit to double-click")

	# --- live: a unit's current position, a downed formation, the leader down ---
	var bravo: Dictionary = tv.ai._formations.filter(func(f): return int(f.kind) == 2)[0]
	var b0: Dictionary = bravo.members[0]
	var b1: Dictionary = bravo.members[1]
	var moved: Dictionary = {}
	for u in tsd.units:
		var ent: Dictionary = rt.entities[u.key]
		if not ent.player and not ent.has("pilot") and u.klass != 1:
			moved = ent
			break
	fe._on_button("back")
	await frames(2)
	check(tv.fe_overlay == null, "BACK returns to the flight")
	b0.state = 4  # Bravo's leader is down
	var mw: Vector3 = moved.world
	moved.world = mw + Vector3(20000, 0, 0)
	fe = await open_tsd(tv)
	tsd = fe.tsd
	var mu: Array = tsd.units.filter(func(u): return u.key == moved.key)
	check(
		mu.size() == 1 and mu[0].pos.distance_to(tsd.world_to_map(mw.x + 20000, mw.y)) < 0.001, "a unit's live position"
	)
	moved.world = mw
	check(tsd.units.filter(func(u): return u.key == b0.key).is_empty(), "a downed jet leaves the map")
	check(
		(
			tsd.flights.has(2)
			and tsd.units[tsd.flights[2].leader].key == b1.key
			and tsd.units[tsd.flights[2].leader].leader
		),
		"Bravo's leader is down: its wingman leads (record [0x18])"
	)

	# --- a unit unknown to the player (entity 0x35c = 0) shows once the player's radar records it (@4afae6) ---
	var hidden: Dictionary = {}
	var files: Array = load("res://mission/mission_runtime.gd").mission_files(221)
	for fi in files.size():
		for e in files[fi].data.get("entities", {}).get("items", []):
			var ent: Dictionary = rt.entities.get("%d:%d" % [fi, int(e.get("0x1e", -1))], {}) if e is Dictionary else {}
			if (
				not ent.is_empty()
				and int(e.get("0x35c", 0)) == 0
				and int(ent.klass) in tsd.ICON_CLASS
				and int(ent.state) < 4
				and int(ent.control) != 0
				and (float(e.get("0x2e4", -1)) >= 0 or float(e.get("0x2ee", -1)) >= 0)
			):
				hidden = ent
	if hidden.is_empty():
		tv.weapons.radar.detected.call(moved.key)
		check(moved.get("known", false), "a radar record makes the unit known")
	else:
		check(tsd.units.filter(func(u): return u.key == hidden.key).is_empty(), "an unknown unit is off the map")
		tv.weapons.radar.detected.call(hidden.key)
		fe._on_button("back")
		await frames(2)
		fe = await open_tsd(tv)
		tsd = fe.tsd
		check(
			not tsd.units.filter(func(u): return u.key == hidden.key).is_empty(),
			"after a radar record it is on the map"
		)

	# --- Fly: Bravo's current leader, the wingman (FUN_005045b0 → FUN_004d3250) ---
	tv.views.set_orbit(tv.rig, tv.CHASE_OFFS, 1.0, tv.Views.FLYBY, false)
	var old_world: Vector3 = tv.player_world()
	var old_speed: float = tv.flight.state().speed
	var t_fly := Time.get_ticks_usec()
	fe._on_button(fe._key_for_label("Bravo"))
	fe._on_button(fe._key_for_label("Fly"))
	await frames(3)
	# Where it was, plus the way it flew since Fly: the three frames' sim time is at most their real time, which a
	# loaded machine stretches (at ~250 m/s, 3 frames of 70 ms are ~50 m).
	var flown := 2.0 * old_speed * (Time.get_ticks_usec() - t_fly) / 1e6
	check(tv.fe_overlay == null and not paused, "Fly returns to the flight")
	check(rt.player_entity() == b1 and b1.control == 3 and not b1.has("pilot"), "Bravo's wingman is the player's jet")
	check(
		not me.player and me.control == 1 and me.get("pilot") != null and tv.ai.pilots.has(me.pilot),
		"the old jet goes to the AI"
	)
	var off: float = me.node.global_position.distance_to(tv.world_to_scene(old_world)) if me.node is Node3D else INF
	check(
		me.pilot.flight != tv.flight and off < 50.0 + flown,
		(
			"the old jet flies on where it was, with its own flight model (%.0f m from there, %.0f m allowed)"
			% [off, 50.0 + flown]
		)
	)
	check(
		(
			tv.player_world().distance_to(rt._world_of(b1)) < 1.0
			and tv.rig.position.distance_to(tv.world_to_scene(b1.world)) < 50.0
		),
		"the rig is at the new jet"
	)
	check(tv.views.type == tv.Views.COCKPIT, "the cockpit view on the new jet")
	check(
		tv.player_flight_number == 2 and tv.weapons.stores != null and tv.autopilot != null,
		"flight 2's route, stores and autopilot"
	)
	check(tv.flight.ap_mode() == 0, "the new jet's brain mode ends (FM mode 0: the player's rules)")
	await seconds(3.0)
	check(tv.flight.state().speed_kt > 50.0 or tv.flight.state().on_ground, "the new jet flies under the player")
	check(
		me.pilot.flight.ap_mode() != 0, "the old jet's brain flies it (autopilot mode %d)" % me.pilot.flight.ap_mode()
	)

	# --- Fly back to Alpha: the old jet, now AI, is the player's again ---
	fe = await open_tsd(tv)
	fe._on_button(fe._key_for_label("Alpha"))
	fe._on_button(fe._key_for_label("Fly"))
	await frames(3)
	check(rt.player_entity() == me and b1.get("pilot") != null, "Fly Alpha: back in the first jet, Bravo to the AI")

	# --- a whole formation down: off the map, its button disabled (EN 3.3) ---
	b1.state = 4
	fe = await open_tsd(tv)
	tsd = fe.tsd
	check(
		not tsd.flights.has(2) and tsd.units.filter(func(u): return u.key == b1.key).is_empty(),
		"Bravo down: off the map"
	)
	check(not fe._button_enabled("Bravo") and fe._button_enabled("Alpha"), "Bravo's button is disabled, Alpha's is not")
	fe._on_button("back")
	await frames(2)

	# --- Fly another type: Be a Sport, F-4E (Alpha) → F-15 (Bravo) ---
	tv = await start_mission(133)
	await frames(10)
	check(tv.player.type == 120, "Be a Sport starts in the F-4E")
	fe = await open_tsd(tv)
	fe._on_button(fe._key_for_label("Bravo"))
	fe._on_button(fe._key_for_label("Fly"))
	await frames(5)
	check(
		tv.player.type == 110 and tv.cockpit.cockpit_dir == tv.player.cockpit_dir and tv.aircraft != null,
		"Fly into an F-15: its type, cockpit and model"
	)
	check(tv.weapons.jet_type == 110 and tv.sounds != null, "the F-15's weapons and sounds")
