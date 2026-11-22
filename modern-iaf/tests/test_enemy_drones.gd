# Modern IAF's one-way attack drones (docs/ai.md §16; shared/ai/drones.gd over the Rust salvo in
# crates/iaf-ai/src/drone.rs) on the Sufa's weapons range, headless, with the range's own load (the gun, four
# AIM-9Ms): a salvo of three spawned near the jet (no mission launches one) flies its route at its height, launched one
# after another; the radar finds one by its small cross-section (not at 30 km, where a jet would be found, but at 4 km)
# and lists it, and the data link, as a hostile air contact; a gun pass brings the first down and an AIM-9M the second
# (the existing damage path); the third reaches its end point and is removed. A fourth, 60 m over the terrain, is lost
# in the ground's clutter on the beam in look-down and found from behind at MTR LO only (docs/radar.md §9.8).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_enemy_drones.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var w


func _press(k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false) -> void:
	_press(k, true, shift)
	_press(k, false, shift)


## The jet level at world `at` on `heading` (degrees) at `speed` m/s.
func _put(at: Vector3, heading: float, speed: float) -> void:
	var h := deg_to_rad(heading)
	var sp: Vector3 = tv.world_to_scene(at)
	var v: Vector3 = w.Terrain.dir_to_scene(Vector3(sin(h), cos(h), 0)) * speed
	tv.rig.position = sp
	tv.flight.start(settings().own_dir(), tv.player.fm_section, sp, Vector3(0, 0, heading), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


## The jet `dist` m behind drone `e` on its course at `speed` m/s.
func _behind(e: Dictionary, dist: float, speed: float) -> void:
	var h := deg_to_rad(float(e.heading))
	_put(tv.runtime._world_of(e) - Vector3(sin(h), cos(h), 0) * dist, float(e.heading), speed)


## Flies until `f` holds, at most `s` s; whether it held. With a drone `keep`, the jet is put back 2.5 km behind it
## every 5 s (nobody flies the jet while the test waits).
func _until(f: Callable, s: float, keep = null) -> bool:
	var t0: float = tv._sim_time
	var put := t0
	while tv._sim_time - t0 < s and not f.call():
		if keep != null and tv._sim_time - put > 5.0 and int(keep.state) < 3:
			put = tv._sim_time
			_behind(keep, 2500.0, 150.0)
		await fly(tv, 0.1)
	return f.call()


func _listed(e: Dictionary) -> bool:
	return w.radar.contacts.any(func(c): return String(c.get("key", "")) == e.key)


## Each second for `secs` s: the jet put at drone `e` + `off`, 300 m above it, on `heading` at 150 m/s; whether the
## radar listed the drone.
func _near(e: Dictionary, off: Vector3, heading: float, secs: int) -> Array:
	var seen := []
	for i in secs:
		_put(tv.runtime._world_of(e) + off + Vector3(0, 0, 300), heading, 150.0)
		await fly(tv, 1.0)
		seen.append(_listed(e))
	return seen


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	check(load("res://flight/fly.gd").prepare(id), "mission %d prepared as the front end's Fly" % id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-drones", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	s.invulnerable = true  # a pass through a drone's wreck goes on
	w = tv.weapons
	var rt: Node = tv.runtime
	var dr: Node = load("res://shared/ai/drones.gd").of(tv)
	var j: Vector3 = tv.player_world()
	_put(j + Vector3(0, -6000, 1500), 0.0, 150.0)
	# North 4 km, then east 2 km to the end point; three drones 5 s apart.
	var route := [j, j + Vector3(0, 4000, 0), j + Vector3(2000, 4000, 0)]
	var salvo: Dictionary = dr.spawn(route, 3, 0.0, 5.0)
	check(not salvo.is_empty(), "a salvo spawned")
	check(await _until(func(): return salvo.ents.all(func(e): return e != null), 12.0), "launched one after another")
	var d: Array = salvo.ents.duplicate()
	var placed := func(e): return e.node is Node3D and e.node.is_inside_tree() and rt.entities.has(e.key)
	check(d.all(placed), "each a mission entity with its stand-in shape")
	var gap: float = rt._world_of(d[0]).distance_to(rt._world_of(d[1]))
	check(absf(gap - 250.0) < 30.0, "5 s apart at 50 m/s along the route: %.0f m" % gap)
	var g = tv.mission_ground(rt._world_of(d[0]))
	var agl: float = rt._world_of(d[0]).z - float(g if g != null else 0.0)
	check(agl > 400.0 and agl < 700.0, "about its 500 m above the terrain: %.0f m" % agl)
	check(
		absf(wrapf(float(d[0].heading), -180.0, 180.0)) < 2.0 and absf(Vector3(d[0].vel).length() - 50.0) < 0.5,
		"north at 50 m/s on the first leg (%.1f°, %.1f m/s)" % [d[0].heading, Vector3(d[0].vel).length()]
	)

	# The radar by its cross-section: 30 km behind the first drone, 500 m above it, in sight, inside the table's 58 NM
	# but beyond the drone's 12 NM, the radar on (Q): not listed; 4 km behind it: listed. DL on.
	var h := deg_to_rad(float(d[0].heading))
	var far: Vector3 = rt._world_of(d[0]) - Vector3(sin(h), cos(h), 0) * 30000.0 + Vector3(0, 0, 500)
	_put(far, float(d[0].heading), 150.0)
	check(IafRadar.line_of_sight(far, rt._world_of(d[0]), tv.mission_ground), "30 km out: the drone in sight")
	_tap(KEY_Q)
	await fly(tv, 1.0)
	check(int(w.radar.mode) >= 2 and not _listed(d[0]), "30 km out: not found (mode %d)" % w.radar.mode)
	_behind(d[0], 4000.0, 150.0)
	w.ews.link_power(true)
	check(await _until(_listed.bind(d[0]), 20.0), "4 km out: the radar lists it (%s)" % [w.radar.contacts])
	var c: Array = w.radar.contacts.filter(func(x): return String(x.get("key", "")) == d[0].key)
	check(not c.is_empty() and bool(c[0].hostile), "a hostile contact")
	var linked := func():
		return w.ews.state.get("link", []).any(func(t): return t.key == d[0].key and t.kind == "hostile")
	check(await _until(linked, 5.0), "the data link lists it as hostile (%s)" % [w.ews.state.get("link", [])])

	# The gun: 200 m behind at 200 m/s, the shot line (IafRounds.shot_dir) on it all through the burst (the jet put
	# back each 0.05 s: nobody flies it, and its nose would rise off the slow drone), the trigger.
	_tap(KEY_A, true)
	w.safety_off = true
	check(w.master_arm, "Shift+A arms")
	for attempt in 3:
		_press(KEY_TAB)
		for k in 12:
			_behind(d[0], 200.0, 200.0)
			await frames(1)
			var o: Dictionary = w.own()
			_put(rt._world_of(d[0]) - w.GunRounds.shot_dir(o.fwd, o.up) * 200.0, float(d[0].heading), 200.0)
			await fly(tv, 0.05)
		_press(KEY_TAB, false)
		await fly(tv, 1.0)
		if int(d[0].state) >= 3:
			break
	check(int(d[0].state) >= 3, "a gun pass brings the first down (state %d)" % d[0].state)

	# The AIM-9M: from 2.5 km behind the second, selected, locked, uncaged, Space.
	_behind(d[1], 2500.0, 150.0)
	for i in 8:
		if w.stores.current_name() == "AIM-9M" and w.hud_mode == 1:
			break
		_tap(KEY_BRACKETRIGHT)
		await frames(2)
	check(w.stores.current_name() == "AIM-9M", "']' selects the AIM-9M (%s)" % w.stores.current_name())
	await fly(tv, 1.0)
	w.radar.lock_key(String(d[1].key))
	await fly(tv, 0.5)
	check(String(w.radar.locked().get("key", "")) == d[1].key, "the radar locks it (%s)" % [w.radar.locked()])
	_behind(d[1], 2500.0, 150.0)
	check(await _until(func(): return w.seeker.lock and w.seeker.target_key == d[1].key, 3.0), "the seeker hears it")
	_tap(KEY_M, true)
	await fly(tv, 0.3)
	var before: int = w.missiles.size()
	_press(KEY_SPACE)
	var gone := await _until(func(): return w.missiles.size() > before, 3.0)
	_press(KEY_SPACE, false)
	check(gone and String(w.missiles.back().target_key) == d[1].key, "Space launches at it")
	check(await _until(func(): return int(d[1].state) >= 3, 30.0, d[1]), "the AIM-9M brings it down")

	# The third flies on: the turn east, the dive, the end point; it is removed.
	_put(j + Vector3(0, -6000, 1500), 0.0, 150.0)
	check(await _until(func(): return absf(float(d[2].heading) - 90.0) < 2.0, 120.0), "the turn east")
	var end: Vector3 = route[2]
	check(await _until(func(): return not rt.entities.has(d[2].key), 120.0), "the end point reached, removed")
	var at := Vector2(d[2].world.x, d[2].world.y)
	check(
		at.distance_to(Vector2(end.x, end.y)) < 2.0,
		"on the end point (%.0f m off)" % at.distance_to(Vector2(end.x, end.y))
	)
	check(d[2].node == null and not d[2].visible, "its shape gone")

	# Ground clutter (docs/radar.md §9.8): a drone 60 m over the terrain, the jet 300 m above it 5 km out (look-down,
	# RWS). Crossing its track (the beam): in the ground's band, never found; behind it (97 kt along the line of sight):
	# found at MTR LO (60 kt), lost at MTR HI (100 kt).
	var low: Dictionary = dr.spawn([j + Vector3(-10000, 15000, 0), j + Vector3(15000, 15000, 0)], 1, 60.0)
	check(await _until(func(): return low.ents.all(func(e): return e != null), 12.0), "a drone launched at 60 m")
	var e: Dictionary = low.ents[0]
	w.radar.set_mode(4, tv._sim_time)
	var beam: Array = await _near(e, Vector3(0, -5000, 0), 0.0, 12)
	var lg = tv.mission_ground(rt._world_of(e))
	var low_agl: float = rt._world_of(e).z - float(lg if lg != null else 0.0)
	check(low_agl > 40.0 and low_agl < 150.0, "about 60 m above the terrain: %.0f m" % low_agl)
	var eye: Vector3 = rt._world_of(e) + Vector3(0, -5000, 300)
	check(IafRadar.line_of_sight(eye, rt._world_of(e), tv.mission_ground), "5 km out: the drone in sight")
	check(int(w.radar.mode) == 4 and not beam.has(true), "on the beam in look-down: not found (%s)" % [beam])
	# Behind it along its own heading (the drone's cross-section is the same all round, so this leg is the beam's
	# control: same range, same height).
	var eh := deg_to_rad(float(e.heading))
	var back := -Vector3(sin(eh), cos(eh), 0) * 5000.0
	check(
		IafRadar.line_of_sight(rt._world_of(e) + back + Vector3(0, 0, 300), rt._world_of(e), tv.mission_ground),
		"5 km behind: the drone in sight"
	)
	var behind: Array = await _near(e, back, float(e.heading), 12)
	check(behind.has(true), "behind it at MTR LO: found (%s)" % [behind])
	w.radar.cntl_press(20)
	var hi: Array = await _near(e, back, float(e.heading), 20)
	check(not hi.slice(10).has(true), "MTR HI: lost (%s)" % [hi])
