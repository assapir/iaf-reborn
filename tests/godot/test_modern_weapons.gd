# The modern weapons (ours; docs/weapons.md §13): the Arming lists per jet. Extras "Weapons" on Original: the Barak's
# and the F-15's lists are the original's, the Sufa has all seven, the F-35I its AIM-9X, GBU-31, GBU-32, GBU-39 with a
# GBU-31 in each bay by default. On Modern: the jets a source shows carrying them list them (modern_weapons.gd LOADS),
# the others none. Mission 231 flown in the F-15, frozen 3000 m up: an AIM-9X locks a MiG 70° off the nose through the
# helmet (padlock view), launches and kills it; a GBU-31 in VIS released at a radar-designated ground unit 6 km ahead,
# inside its launch acceptability region, flies to the point and destroys it. PRE (docs/weapons.md §13.2): a target
# clicked for station 5 on the briefing TSD is stored; in flight the unit stands there, 50° off the nose with the
# radar designating elsewhere: 20 km out the HUD shows the time to max range, 6 km out IN RNG, and the bomb flies to
# the briefing's point and destroys the unit. With Bomb release Real a pair leaves at once, each bomb to its own
# station's target.
extends "res://../tests/godot/base.gd"

const AIM9X := 1001
const GBU31 := 1003
const MODERN := ["AIM-9X", "PYTH-5", "GBU-31", "GBU-31V3", "GBU-32", "GBU-38", "GBU-39"]
## [Jet list id, F-35I slot, F-16 version, type, the modern weapons listed with Weapons on Modern].
const JETS := [
	[-1, -1, "barak", 100, ["AIM-9X", "PYTH-5", "GBU-31", "GBU-38", "GBU-39"]],
	[-1, -1, "sufa", 100, MODERN],
	[0, -1, "barak", 110, ["AIM-9X", "GBU-31"]],
	[2, -1, "barak", 120, []],
	[3, -1, "barak", 200, []],
	[4, -1, "barak", 140, []],
	[5, -1, "barak", 130, []],
	[6, -1, "barak", 190, []],
	[4, 4, "barak", 1000, ["AIM-9X", "GBU-31", "GBU-32", "GBU-39"]],
]


func run() -> void:
	await require_data()
	for c in JETS:
		settings().jet_id = c[0]
		settings().f35i_slot = c[1]
		settings().f16_variant = c[2]
		for modern in [false, true]:
			settings().modern_weapons = modern
			var mw := _arming(c[3])
			var have: Array = MODERN.filter(func(n): return mw.names.has(n))
			# The Sufa and the F-35I keep theirs with the switch off; every other jet lists none.
			var want: Array = c[4] if modern or c[2] == "sufa" or c[3] == 1000 else []
			check(
				not mw.is_empty() and have == want,
				"type %d (%s), Weapons %s: modern %s (want %s)" % [c[3], c[2], modern, have, want]
			)
			if c[3] == 1000 and not mw.is_empty():
				var d: Array = mw.defaults
				check(
					int(d[2][0]) == GBU31 and int(d[6][0]) == GBU31 and not mw.names.has("MK-84L"),
					"F-35I: a GBU-31 in each bay by default, no MK-84L stand-in (%s)" % [d]
				)
	settings().modern_weapons = false
	settings().f35i_slot = -1
	settings().f16_variant = "barak"

	var n: int = await _briefing_target()
	settings().jet_id = 0
	var tv = await start_mission(231)
	await frames(3)
	check(tv.player.type == 110, "the F-15 flies mission 231")
	var w = airborne_case(tv, [AIM9X, 1, 0, 0, 0, 0, 0, 0, GBU31, 1, 0, 0, 0, 0, 0, 0, 0, 0, 25, 235, 33, 120, 34, 60])
	await _aim9x(tv, w)
	await _jdam(tv, w, 4)
	await _jdam_pre(tv, n)
	_pair(tv, n)
	settings().jet_id = -1
	settings().bomb_release = "original"


## The player's flight of mission 231 flying jet `type`: {names (AA + AG lists), defaults}; {} when none.
func _arming(type: int) -> Dictionary:
	var mw = load("res://weapons/mission_weapons.gd").create(231)
	for n in mw.flights:
		if int(mw.flights[n].type) == type:
			mw.reset(n)
			var names := []
			for t in [0, 1]:
				names.append_array(mw.tab_list(t).map(func(x): return x.name))
			return {"names": names, "defaults": mw.defaults[n]}
	return {}


func _aim9x(tv, w) -> void:
	var mig := {}
	for e in tv.runtime.entities.values():
		if not e.player and e.has("pilot") and e.node != null and mig.is_empty():
			mig = e
		elif not e.player:
			e.visible = false
	check(not mig.is_empty(), "an AI jet")
	if mig.is_empty():
		return
	var o: Dictionary = w.own()
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var dir := flat.rotated(Vector3(0, 0, 1), deg_to_rad(-70.0))  # 70° right
	var p: Vector3 = o.pos + dir * 3000.0
	mig.world = p
	mig.alt = p.z
	mig.vel = Vector3.ZERO
	mig.visible = true
	tv.mission_entity_moved(mig)
	var t := 1.0
	w.nav_key(0)
	w.stores.cur = 0
	w.select_aa()
	w.update(t)
	check(w.hud_mode == 1 and w.stores.current_name() == "AIM-9X", "AIM-9X selected: SRM HUD")
	tv.views.set_padlock(mig.node)
	# The padlock turns the head toward the MiG at its own rate (views.gd).
	for i in 1200:
		await process_frame
		t += 0.05
		w.update(t)
		if w.seeker.lock:
			break
	var off := rad_to_deg(flat.angle_to(Vector3(p.x - o.pos.x, p.y - o.pos.y, 0)))
	check(
		w.own().get("helmet", false) and w.seeker.lock and w.seeker.target_key == String(mig.key),
		(
			"padlock: the helmet cues the seeker onto the MiG %.0f° off the nose (helmet %s, lock %s, target %s)"
			% [off, w.own().get("helmet", false), w.seeker.lock, w.seeker.target_key]
		)
	)
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
	check(
		w.missiles.size() == 1 and w.missiles[0].target_key == String(mig.key),
		"the AIM-9X leaves at the MiG off boresight"
	)
	for i in 600:
		t += 0.05
		w.update(t)
		if w.missiles.is_empty():
			break
	check(int(mig.state) != 1, "the AIM-9X turned and killed the MiG (state %d)" % int(mig.state))
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(2)


func _jdam(tv, w, station: int) -> void:
	var site := _ground_unit(tv)
	check(not site.is_empty(), "a ground unit")
	if site.is_empty():
		return
	var o: Dictionary = w.own()
	var p := _place(tv, w, site, o, 6000.0)
	var t := 40.0
	w.update(t)
	w.nav_key(0)
	w.stores.cur = station
	w.select_ag()
	w.radar.designate(p.x, p.y, p.z, t)
	w.gps_modes["GBU-31"] = true  # VIS: the sensors' point
	t += 0.05
	w.update(t)
	var gps: Dictionary = w.ag.get("gps", {})
	check(
		w.hud_mode in [5, 6] and not gps.is_empty() and gps.designated and gps.aim.distance_to(p) < 1.0,
		"GBU-31 selected: the aim is the TD point"
	)
	check(gps.get("in_range", false), "6 km out from 3000 m: in range (the HUD's IN RNG)")
	var far: bool = ClassDB.class_call_static(
		"IafGpsBomb", "in_range", w.stores.station(station).w.gps, o.pos, o.vel, p + (p - o.pos) * 3.0
	)
	check(not far, "four times as far: out of range")
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
	check(w.gps_bombs.size() == 1 and w.gps_bombs[0].g.aim().distance_to(p) < 1.0, "the GBU-31 flies to the point")
	for i in 2400:
		t += 0.05
		w.update(t)
		if w.gps_bombs.is_empty():
			break
	check(w.gps_bombs.is_empty() and int(site.state) != 1, "the GBU-31 destroyed the unit (state %d)" % int(site.state))


## The briefing TSD of mission 231 (the F-15 with a GBU-31 on stations 2, 5, 8): a click on station 5's row of the GPS
## panel, then on the map, stores that point as its PRE target. Returns the flight number.
func _briefing_target() -> int:
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
	settings().mission_id = 231
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	await frames(3)
	var tsd = fe.tsd
	var n: int = tsd.default_flight()
	var load := []
	for i in 9:
		load.append([GBU31, 1] if i in [1, 4, 7] else [0, 0])
	settings().arm_loadouts[n] = load
	var rows: Array = tsd.gps._rows(tsd.gps.stations())
	check(rows.size() == 4, "the GPS panel lists stations 2, 5, 8 (%d rows)" % rows.size())
	var row: Rect2 = rows[2][0]
	var click: Vector2 = tsd.area.size * Vector2(0.6, 0.4)
	for c in [row.get_center(), click]:
		tsd._gui_input(mouse_button(fe._to_screen(tsd.area.position + c), true))
		tsd._gui_input(mouse_button(fe._to_screen(tsd.area.position + c), false))
	var xy = settings().gps_targets.get(n, {}).get(4)
	var want: Vector2 = tsd.map_to_world(Vector2(int(click.x), int(click.y)) / tsd.zoom + tsd.scroll)
	check(
		xy != null and Vector2(xy[0], xy[1]).distance_to(want) < 3700.0 and tsd.gps.target(4).set,
		"station 5's PRE target is the clicked point, within two map units (%s, want %s)" % [xy, want]
	)
	settings().arm_loadouts = {}  # the flight takes the test's own loads (airborne_case)
	fe.queue_free()
	await frames(2)
	return n


## PRE: the briefing's point, out of the radar's and the pod's view, is the aim; the LAR cues as the jet closes.
func _jdam_pre(tv, n: int) -> void:
	var w = airborne_case(tv, [0, 0, 0, 0, 0, 0, 0, 0, GBU31, 1, 0, 0, 0, 0, 0, 0, 0, 0, 25, 235, 33, 120, 34, 60])
	check(tv.player_flight_number == n, "in flight the TSD's flight (%d, %d)" % [tv.player_flight_number, n])
	var xy = settings().gps_targets.get(n, {}).get(4)
	var site := _ground_unit(tv)
	if xy == null or site.is_empty():
		check(false, "a PRE target and a ground unit")
		return
	var p: Vector3 = w._on_ground(Vector2(xy[0], xy[1]))
	site.world = p
	site.alt = p.z
	tv.mission_entity_moved(site)
	var t := 80.0
	w.gps_modes.erase("GBU-31")  # PRE, the default
	var off := Vector3(0, 1, 0).rotated(Vector3(0, 0, 1), deg_to_rad(50.0))  # the track 50° left of the target
	var lars := []
	for d in [20000.0, 6000.0]:
		start_over(
			tv,
			w,
			p - Vector3(0, d, 0),
			tv.world_to_scene(off * 250.0) - tv.world_to_scene(Vector3.ZERO),
			tv.player.fm_section,
			3000.0
		)
		t += 0.05
		w.update(t)
		w.nav_key(0)
		w.stores.cur = 4
		w.select_ag()
		w.radar.designate(p.x + 3000.0, p.y, p.z, t)  # VIS would go here
		t += 0.05
		w.update(t)
		lars.append(w.ag.get("gps", {}))
	var far: Dictionary = lars[0]
	var near: Dictionary = lars[1]
	check(
		far.get("pre", false) and far.get("designated", false) and far.aim.distance_to(p) < 1.0,
		"PRE: the aim is the briefing's point, not the TD point (%s)" % far.get("aim")
	)
	check(
		not far.lar.in_range and far.lar.tmr != null and far.lar.tmr > 0.0,
		"20 km out: out of range, TMR %s s" % far.lar.get("tmr")
	)
	check(near.lar.in_range and near.lar.tmr == null, "6 km out: IN RNG (%s)" % near.lar)
	var real: Dictionary = tv.cockpit.hud.real_hud()
	check(
		real.is_empty() or real.outer.any(func(q): return q.k == "text" and q.text == "IN RNG"), "the Real HUD's IN RNG"
	)
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
	check(w.gps_bombs.size() == 1 and w.gps_bombs[0].g.aim().distance_to(p) < 1.0, "the bomb takes the PRE point")
	for i in 2400:
		t += 0.05
		w.update(t)
		if w.gps_bombs.is_empty():
			break
	check(
		w.gps_bombs.is_empty() and int(site.state) != 1,
		"PRE: the GBU-31 destroyed the unit (state %d)" % int(site.state)
	)


## Bomb release Real, PAIRS: stations 2 and 8 leave together, each bomb to its own station's PRE target.
func _pair(tv, n: int) -> void:
	settings().bomb_release = "real"
	var w = airborne_case(tv, [0, 0, GBU31, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, GBU31, 1, 0, 0, 25, 235, 33, 120, 34, 60])
	var o: Dictionary = w.own()
	var a: Vector3 = w._on_ground(Vector2(o.pos.x + 1500.0, o.pos.y + 5000.0))
	var b: Vector3 = w._on_ground(Vector2(o.pos.x - 1500.0, o.pos.y + 5000.0))
	settings().gps_targets[n] = {1: [a.x, a.y, "A"], 7: [b.x, b.y, "B"]}
	w.release_pairs = true
	w.stores.cur = 1
	w.select_ag()
	w.update(200.0)
	w.fire_selected()
	w.update(200.01)
	w.release_selected()
	var aims: Array = w.gps_bombs.map(func(bm): return bm.g.aim())
	check(
		(
			aims.size() == 2
			and aims.any(func(q): return q.distance_to(a) < 1.0)
			and aims.any(func(q): return q.distance_to(b) < 1.0)
		),
		"a pair: each bomb to its own station's target (%s)" % [aims]
	)
