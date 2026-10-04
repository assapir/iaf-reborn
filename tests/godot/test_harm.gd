# The HARM (590; docs/weapons.md §11.6): the anti-radiation missile flies the homing motion at the HARM page's
# selected emitter. Mission 231 for every jet (the seven Jet list jets and the F-35I) with an AGM-88 on station 0
# and a Shrike on station 8: a ground unit 15 km ahead becomes an emitter (its radar's lock notification to the
# RWR), the HARM page lists and preselects it, HUD mode 8 shows the diamond and "In Range", the launch goes at it and
# the hit destroys it. The flight model is frozen; the weapons run on a scripted sim time.
extends "res://../tests/godot/base.gd"

## [Jet list id, F-35I slot, type].
const CASES := [[-1, -1, 100], [0, -1, 110], [2, -1, 120], [3, -1, 200], [4, -1, 140], [5, -1, 130], [6, -1, 190], [4, 4, 1000]]
const HARM := 30
const SHRIKE := 59


func run() -> void:
	# A real-render run (the screenshots) takes the F-16 only.
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
	var w = airborne_case(tv, [HARM, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, SHRIKE, 1, 25, 235, 33, 90, 34, 60])
	var t := 1.0
	# A ground unit (a radar's class) 15 km ahead on the terrain; every other unit hidden.
	var site := _ground_unit(tv)
	check(not site.is_empty(), "%s: a ground unit to be the emitter" % name)
	if site.is_empty():
		return
	var p := _place(tv, w, site, w.own(), 15000.0)
	w.update(t)
	w.rwr.lock(site.key)  # the site's radar locks the jet: an active emitter
	w.nav_key(0)
	w.stores.cur = 0
	w.select_ag()  # '['
	t += 0.05
	w.update(t)
	check(w.master == 4 and w.hud_mode == 8 and tv.cockpit.mfds.any(func(m): return m.page == 10),
		"%s: AGM88 selected: master 4, HUD mode 8, the HARM page" % name)
	var cp = tv.cockpit
	check(cp.harm.list.size() == 1 and cp.harm.list[0].selected and w.harm.selected == site.key,
		"%s: the HARM page lists the emitter, preselected" % name)
	var wp: Dictionary = cp.weapons
	check(wp.get("harm_point") != null and cp.harm.in_range, "%s: the HUD diamond on the emitter, In Range" % name)
	if shots:
		await frames(2)
		tv.views.set_cockpit(tv.views.COCKPIT)
		await frames(2)
		await _save("harm_hud.png")
	w.fire_selected()
	w.release_selected()
	check(w.missiles.size() == 1 and w.missiles[0].target_key == site.key and int(w.missiles[0].weapon.type) == 590,
		"%s: the HARM launched at the emitter" % name)
	var terminal := false
	var site_scene: Vector3 = site.node.global_position
	for i in 1200:
		t += 0.05
		w.update(t)
		if shots and i == 40:
			await frames(2)
			await _save("harm_flight.png")
		if shots and not terminal and not w.missiles.is_empty() and (w.missiles[0].position(t) - p).length() < 1200.0:
			terminal = true
			tv.views.set_two(w.missiles[0].get_meta("node"), site.node)
			await frames(3)
			await _save("harm_terminal.png")
		if w.missiles.is_empty():
			break
	check(w.missiles.is_empty() and int(site.state) != 1, "%s: the HARM hit the emitter (state %d)" % [name, int(site.state)])
	if shots:
		var mark := Node3D.new()
		tv.add_child(mark)
		mark.global_position = site_scene
		tv.views.set_circle(mark, 120.0, tv.views.WRECK)
		await frames(6)
		await _save("harm_hit.png")
		tv.views.set_cockpit(tv.views.COCKPIT)
		mark.queue_free()
	# The Shrike (590 too): no emitter left in the list, it flies at the point 7 km ahead (_fireEndVec).
	w.select_ag()  # '[': the next AG store
	t += 2.1
	w.update(t)
	check(w.stores.current_name() == "SHRIKE" and w.hud_mode == 8, "%s: SHRIKE: HUD mode 8" % name)
	w.fire_selected()
	w.release_selected()
	check(w.missiles.size() == 1 and not w.missiles[0].has_target, "%s: no emitter: the SHRIKE flies at its end point" % name)
