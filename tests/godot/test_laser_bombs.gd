# Laser bombs (650; docs/weapons.md §9.3, §12): always the guided motion. With the FLIR pod's laser on, the
# designation (the FLIR camera's centre point) replaces the ripple aim when it lies within 60° of the line to the bomb's
# point and on the ground; else the bomb flies to the ripple aim. Mission 231 for every jet (the seven Jet list jets and
# the F-35I) with three MK-82L on station 0 and the FLIR pod on station 8: a designated ground unit 6 km ahead is hit;
# with the laser off the bomb aims at the impact point; a designation behind the jet is refused. The flight model is
# frozen; the weapons run on a scripted sim time.
extends "res://../tests/godot/base.gd"

const EoSensor := preload("res://weapons/eo_sensor.gd")
## [Jet list id, F-35I slot, type].
const CASES := [[-1, -1, 100], [0, -1, 110], [2, -1, 120], [3, -1, 200], [4, -1, 140], [5, -1, 130], [6, -1, 190], [4, 4, 1000]]
const MK82L := 16
const FLIR := 55


func run() -> void:
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


func _case(tv, name: String, shots: bool) -> void:
	var w = airborne_case(tv, [MK82L, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, FLIR, 1, 25, 235, 33, 90, 34, 60])
	var t := 1.0
	var site := _ground_unit(tv)
	check(not site.is_empty() and w.flir_pod, "%s: a ground unit, the FLIR pod fitted" % name)
	if site.is_empty():
		return
	var o: Dictionary = w.own()
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var p := _place(tv, w, site, o, 6000.0)
	w.update(t)
	w.nav_key(0)
	w.stores.cur = 0
	w.select_ag()
	w.ripple_qty = 1
	t += 0.05
	w.update(t)
	check(w.stores.current_type() == 650 and w.master == 5, "%s: %s selected: master 5" % [name, w.stores.current_name()])
	# Designated: the FLIR camera on the site, the laser on.
	w.eo.start(EoSensor.FLIR, true, p, t)
	w.eo.laser = true
	t += 0.05
	w.update(t)
	var dlz: Array = w.selected_dlz(w.own(), {})
	check(dlz.size() == 2 and float(dlz[0]) > 0.0, "%s: the laser bomb's DLZ %.0f m" % [name, float(dlz[0]) if dlz.size() == 2 else 0.0])
	_release(w, t)
	t += 0.1
	check(w.guided.size() == 1 and w.guided[0].aim.distance_to(p) < 30.0 and w.bombs.is_empty(),
		"%s: the guided bomb aims at the designation" % name)
	if shots:
		tv.views.set_cockpit(tv.views.COCKPIT)
		await frames(3)
		await _save("laser_release.png")
	for i in 2400:
		t += 0.05
		w.update(t)
		if shots and i == 300 and not w.guided.is_empty():
			tv.views.set_two(w.guided[0].get_meta("node"), site.node)
			await frames(3)
			await _save("laser_terminal.png")
		if w.guided.is_empty():
			break
	check(w.guided.is_empty() and int(site.state) != 1, "%s: the laser bomb hit the designated unit (state %d)" % [name, int(site.state)])
	if shots:
		tv.views.set_cockpit(tv.views.COCKPIT)
	# Laser off: the ripple aim (the impact point).
	w.eo.laser = false
	t += 0.5
	w.update(t)
	_release(w, t)
	check(w.guided.size() == 1 and w.guided[0].aim.distance_to(w.ag.impact) < 30.0, "%s: laser off: the bomb aims at the impact point" % name)
	# A designation behind the jet: refused (> 60° off the line to the bomb's point).
	var back: Vector3 = w.own().pos - flat * 4000.0
	var gb = tv.terrain.height_at(w.to_scene(Vector3(back.x, back.y, 0)))
	back.z = float(gb) if gb != null else 0.0
	w.eo.start(EoSensor.FLIR, true, back, t)
	w.eo.laser = true
	t += 0.5
	w.update(t)
	_release(w, t)
	check(w.guided.size() == 2 and w.guided[1].aim.distance_to(back) > 1000.0, "%s: a designation behind the jet is refused" % name)


## Space and its release: one bomb on the next ripple tick.
func _release(w, t: float) -> void:
	w.fire_selected()
	w.update(t + 0.01)
	w.release_selected()
