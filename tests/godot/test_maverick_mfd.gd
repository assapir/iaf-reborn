# The TV page after a Maverick launch (docs/mfd.md "FLIR (6), TV (5)", docs/weapons.md §12.3): the camera rides the
# flying weapon (FUN_004604c0) with the page on RDY (FUN_00460940) until the hit, then it is back on the jet; the last
# Maverick launched gives NO SOURCE and no picture. With Models: Detailed (double-sided store models) the weapon's own
# model stays out of the EO picture (EoSensor.SELF_LAYER). Mission 231, the F-16, two AGM-65 on stations 0 and 8.
# Real-render (SHOT_DIR): maverick_mfd_flight.png mid-flight in the cockpit.
extends "res://../tests/godot/base.gd"

const EoSensor := preload("res://weapons/eo_sensor.gd")
const AGM65 := 7


func run() -> void:
	settings().models = "detailed"
	var tv = await start_mission(231)
	await frames(3)
	var w = airborne_case(tv, [AGM65, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, AGM65, 1, 25, 235, 33, 90, 34, 60])
	var t := 1.0
	var site := _ground_unit(tv)
	check(not site.is_empty(), "a ground unit to be the target")
	if site.is_empty():
		return
	var p := _place(tv, w, site, w.own(), 6000.0)
	w.update(t)
	w.nav_key(0)
	w.stores.cur = 0
	w.select_ag()  # '['
	t += 0.05
	w.update(t)
	w.eo.start(EoSensor.TV, false, p, t)  # the camera tracking the site
	t += 0.05
	w.update(t)
	tv.views.set_cockpit(tv.views.COCKPIT)
	await frames(3)
	check(
		w.stores.current_type() == 635 and w.tv_status() == 1 and tv.cockpit.mfds.any(func(m): return m.page == 5),
		"AGM-65 selected: the TV page, RDY"
	)
	# The first Maverick: the camera rides it, RDY (rounds left), the picture shown, without the weapon's own model.
	w.fire_selected()
	w.release_selected()
	var mis = w.tv_weapon
	var node: Node3D = mis.get_meta("node") if mis != null else null
	var meshes: Array = node.find_children("*", "VisualInstance3D", true, false) if node != null else []
	var self_bit := 1 << (EoSensor.SELF_LAYER - 1)
	check(
		not meshes.is_empty() and meshes.all(func(g): return g.layers == self_bit),
		"the flying Maverick's model (%d meshes) is on the EO self layer" % meshes.size()
	)
	var rode := 0
	var steps := 0
	var shown := true
	for i in 1200:
		t += 0.05
		w.update(t)
		await frames(1)
		if not w.tv_flying():
			break
		steps += 1
		if w.eo_eye != null and (w.eo_eye as Vector3).distance_to(mis.position(t)) < 1.0:
			rode += 1
		var pg: Dictionary = tv.cockpit.eo.get("tv", {})
		shown = (
			shown
			and int(pg.get("status", 0)) == 1
			and tv.eo_viewport != null
			and tv.eo_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
		)
		if i == 150:
			await _save("maverick_mfd_flight.png")
	check(steps > 20 and rode == steps, "the camera rides the Maverick all the way (%d / %d updates)" % [rode, steps])
	check(shown, "the TV page stays RDY with the picture while it flies")
	check(
		tv.eo_camera != null and tv.eo_camera.cull_mask & self_bit == 0,
		"the EO camera leaves the self layer out of its picture"
	)
	check(int(site.state) != 1 and w.missiles.is_empty(), "the Maverick hit (state %d)" % int(site.state))
	t += 0.05
	w.update(t)
	check(w.eo_eye == null and w.tv_status() == 1, "after the hit: the camera back on the jet, RDY (one round left)")
	# The last Maverick: FUN_00460940 gives 0 (no round left and a Maverick flies): NO SOURCE, no picture.
	w.fire_selected()
	w.release_selected()
	t += 0.05
	w.update(t)
	await frames(1)
	check(
		w.tv_flying() and w.tv_status() == 0 and int(tv.cockpit.eo.get("tv", {}).get("status", -1)) == 0,
		"the last Maverick launched: NO SOURCE"
	)
	settings().models = "original"
