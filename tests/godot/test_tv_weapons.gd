# The TV weapons (docs/weapons.md §12): the TV missile 640 flies the guided motion to the TV camera's centre point
# and steers to it while it flies (the camera rides the weapon, the TV page shows TRA / TER and the time left);
# the Maverick 635 flies the homing motion at the camera's point. Mission 231 for every jet (the seven Jet list
# jets and the F-35I) with an AGM-62 on station 0 and an AGM-65 on station 8: a ground unit 8 km ahead, the camera
# on it, launch, hit. Also the guided motion's DLZ and its end rules. The flight model is frozen; the weapons run
# on a scripted sim time.
extends "res://../tests/godot/base.gd"

const Guided := preload("res://weapons/guided.gd")
const EoSensor := preload("res://weapons/eo_sensor.gd")
## [Jet list id, F-35I slot, type].
const CASES := [[-1, -1, 100], [0, -1, 110], [2, -1, 120], [3, -1, 200], [4, -1, 140], [5, -1, 130], [6, -1, 190], [4, 4, 1000]]
const AGM62 := 6
const AGM65 := 7


func run() -> void:
	_motion_rules()
	for c in (CASES if DisplayServer.get_name() == "headless" else CASES.slice(0, 1)):
		Settings().f35i_slot = c[1]
		Settings().jet_id = c[0]
		var tv = await start_mission(231)
		await frames(3)
		var name := "type %d" % c[2]
		check(tv.player.type == c[2], "%s flies mission 231" % name)
		await _case(tv, name, c[2] == 100)
	Settings().jet_id = -1
	Settings().f35i_slot = -1


## The guided motion alone: the DLZ formula (a = 1 for the 640's 20 m/s² up accel), mode switching by the squared
## horizontal distance, the burst snapped to the aim within 200 m.
func _motion_rules() -> void:
	var m := {"_absAcceleration": 10.0, "_timeAcceleration": 2.0, "_timeConstVel": 3.0e7, "_absDeceleration": 150.0,
		"_timeDecceleration": 20.0, "_spiralAccelBeta": 70.0, "_spiralAccel": 420.0, "_absReleaseAcceleration": 300.0,
		"_timeRelease": 8.0, "_timeConstOrientation": 2.0, "_rollRate": 0.0179065}
	var dbg := func(i: int, d: float) -> float: return {11: 70.0, 13: 200.0, 14: 200.0}.get(i, d)
	# Level at 1000 m, 250 m/s: t = √(2000)/2 = 22.36 s; d1 = 2·250 = 500 (the glide's "speed"); 500 + 20 + 20.36·300.
	var r: Array = Guided.dlz(m, 1000.0, Vector3(0, 250, 0), dbg)
	check(absf(float(r[0]) - (520.0 + (sqrt(2000.0) / 2.0 - 2.0) * 300.0)) < 1.0 and r[0] == r[1], "guided DLZ: %.0f m" % float(r[0]))
	var g := Guided.new()
	g.launch({"type": 640}, m, 0.0, Vector3(0, 0, 1000), Vector3(0, 250, 0), Vector3(0, 8000, 0), dbg)
	check(g.mode == 0 and g.status() == 2, "guided: starts in mode 0 (TRA)")
	var flat := func(_p) -> float: return 0.0
	var t := 0.0
	var gone := false
	while not gone and t < 120.0:
		t = g.next_update
		gone = g.update(t, flat)
		if not gone and g.mode == 2:
			check(g.status() == 3, "guided: terminal is TER")
	check(gone and g.last_pos.distance_to(Vector3(0, 8000, 0)) < 1.0, "guided: bursts at the aim point (%.0f m off, %.1f s)" % [g.last_pos.distance_to(Vector3(0, 8000, 0)), t])


func _case(tv, name: String, shots: bool) -> void:
	var w = airborne_case(tv, [AGM62, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, AGM65, 1, 25, 235, 33, 90, 34, 60])
	var t := 1.0
	var site := _ground_unit(tv)
	check(not site.is_empty(), "%s: a ground unit to be the target" % name)
	if site.is_empty():
		return
	var p := _place(tv, w, site, w.own(), 8000.0)
	w.update(t)
	w.nav_key(0)
	w.stores.cur = 0
	w.select_ag()  # '['
	t += 0.05
	w.update(t)
	check(w.stores.current_type() == 640 and w.master == 6 and w.hud_mode == 7 and tv.cockpit.mfds.any(func(m): return m.page == 5),
		"%s: %s selected: master 6, HUD mode 7, the TV page" % [name, w.stores.current_name()])
	w.eo.start(EoSensor.TV, false, p, t)  # the camera tracking the site
	t += 0.05
	w.update(t)
	check(w.eo_centre.distance_to(p) < 30.0 and w.tv_status() == 1 and tv.cockpit.weapons.get("tv_point") != null,
		"%s: the camera on the site, RDY, the HUD diamond" % name)
	var dlz: Array = w.selected_dlz(w.own(), {})
	check(dlz.size() == 2 and float(dlz[0]) > 8000.0, "%s: the TV missile's DLZ %.0f m" % [name, float(dlz[0]) if dlz.size() == 2 else 0.0])
	if shots:
		tv.views.set_cockpit(tv.views.COCKPIT)
		await frames(3)
		await _save("tv_ready.png")
	w.fire_selected()
	w.release_selected()
	t += 0.05
	w.update(t)
	check(w.guided.size() == 1 and w.tv_flying() and w.tv_status() == 2 and w.eo_eye != null and tv.cockpit.eo.tv_time > 0,
		"%s: the TV missile flies (TRA, %d s left), the camera rides it" % [name, int(tv.cockpit.eo.get("tv_time", 0))])
	for i in 2400:
		t += 0.05
		w.update(t)
		if shots and i == 200:
			await frames(2)
			await _save("tv_flight.png")
		if w.guided.is_empty():
			break
	check(w.guided.is_empty() and int(site.state) != 1, "%s: the TV missile hit the site (state %d)" % [name, int(site.state)])
	check(w.tv_status() == 0 and w.eo_eye == null, "%s: after the burst the camera is back on the jet; no rounds left: NO SOURCE" % name)
	# The Maverick (635): the camera not started on a unit, so it flies the homing motion at the camera's point.
	var site2 := _ground_unit(tv)
	if site2.is_empty():
		return
	var p2 := _place(tv, w, site2, w.own(), 6000.0)
	w.stores.cur = 8
	w.select_station(8)
	t += 0.05
	w.update(t)
	w.eo.start(EoSensor.TV, false, p2, t)
	w.eo_on_unit = false
	t += 0.05
	w.update(t)
	check(w.stores.current_type() == 635 and w.tv_status() == 1, "%s: %s: RDY" % [name, w.stores.current_name()])
	w.fire_selected()
	w.release_selected()
	check(w.missiles.size() == 1 and not w.missiles[0].has_target and w.missiles[0].aim_point.distance_to(p2) < 30.0 and w.tv_status() == 0,
		"%s: the Maverick flies at the camera's point (its last round: NO SOURCE)" % name)
	for i in 1200:
		t += 0.05
		w.update(t)
		if w.missiles.is_empty():
			break
	check(w.missiles.is_empty() and int(site2.state) != 1, "%s: the Maverick hit (state %d)" % [name, int(site2.state)])
