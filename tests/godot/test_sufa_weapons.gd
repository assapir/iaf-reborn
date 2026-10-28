# The F-16I Sufa's weapons (ours; docs/weapons.md §13): with Settings.f16_variant "sufa" the F-16's Arming list has
# the AIM-9X, Python 5, the JDAMs and the GBU-39 (the Barak's has none). Mission 231, the F-16 frozen 3000 m up: an
# AIM-9X locks a MiG 70° off the nose through the helmet (padlock view), launches and kills it; a GBU-31 released at a
# radar-designated ground unit 6 km ahead, inside its launch acceptability region, flies to the point and destroys it.
extends "res://../tests/godot/base.gd"

const AIM9X := 1001
const GBU31 := 1003


func run() -> void:
	await require_data()
	var MissionWeapons = load("res://weapons/mission_weapons.gd")
	var names := func(variant: String) -> Array:
		settings().f16_variant = variant
		var mw = MissionWeapons.create(231)
		var out := []
		for n in mw.flights:
			if int(mw.flights[n].type) == 100:
				mw.reset(n)
				for t in [0, 1]:
					out.append_array(mw.tab_list(t).map(func(w): return w.name))
				break
		return out
	var barak: Array = names.call("barak")
	var sufa: Array = names.call("sufa")
	check(not barak.has("AIM-9X") and not barak.has("GBU-31"), "Barak: no Sufa weapons on the Arming list")
	var want := ["AIM-9X", "PYTH-5", "GBU-31", "GBU-31V3", "GBU-32", "GBU-38", "GBU-39"]
	check(want.all(func(n): return sufa.has(n)), "Sufa: the Arming list has %s (%s)" % [want, sufa])

	var tv = await start_mission(231)
	await frames(3)
	check(tv.player.type == 100, "the F-16 flies mission 231")
	var w = airborne_case(tv, [AIM9X, 1, 0, 0, GBU31, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 25, 235, 33, 90, 34, 60])
	await _aim9x(tv, w)
	await _jdam(tv, w)
	settings().f16_variant = "barak"


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


func _jdam(tv, w) -> void:
	var site := _ground_unit(tv)
	check(not site.is_empty(), "a ground unit")
	if site.is_empty():
		return
	var o: Dictionary = w.own()
	var p := _place(tv, w, site, o, 6000.0)
	var t := 40.0
	w.update(t)
	w.nav_key(0)
	w.stores.cur = 2
	w.select_ag()
	w.radar.designate(p.x, p.y, p.z, t)
	t += 0.05
	w.update(t)
	var gps: Dictionary = w.ag.get("gps", {})
	check(
		w.hud_mode in [5, 6] and not gps.is_empty() and gps.designated and gps.aim.distance_to(p) < 1.0,
		"GBU-31 selected: the aim is the TD point"
	)
	check(gps.get("in_range", false), "6 km out from 3000 m: in range (the HUD's IN RNG)")
	var far: bool = ClassDB.class_call_static(
		"IafGpsBomb", "in_range", w.stores.station(2).w.gps, o.pos, o.vel, p + (p - o.pos) * 3.0
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
