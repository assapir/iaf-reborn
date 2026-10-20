# World scale (docs/world-scale.md steps 1–4): Settings.world_scale "original" draws every model at its bdb Present
# scale (0x65e); "real" at true size (1), the ground models (underlays, light sets, > 200 m, ships) kept. Mission
# 311 (a ground start at Ramat David) and 214 (AI jets, SAM sites) in both modes: the mission models' scales and collision radii, the same units
# hidden, the player's jet (model, cockpit model offset, gear clearance, gun), its stores on the pylons at their
# launch points; then in Real a take-off from 311 and the autopilot's landing in 312 with the halved clearance.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var S := Settings()
	# --- step 1: the setting and the helper ---
	check(S.world_scale == "original", "default: Original")
	check(S.model_scale(2.0) == 2.0 and S.model_scale(3.0, true) == 3.0, "Original: the Present scale")
	S.world_scale = "real"
	check(S.model_scale(2.0) == 1.0 and S.model_scale(2.0, true) == 2.0, "Real: 1, a kept model its Present scale")
	var cfg: ConfigFile = S.write_config()
	S.world_scale = "original"
	S.read_config(cfg)
	check(S.world_scale == "real", "settings.cfg round trip")
	var flat := AABB(Vector3(-500, 0, -100), Vector3(1000, 0, 200))
	check(S.keeps_present("x/ul_rw1.gltf", flat, 2.0, 13, 0.05), "a flat underlay keeps its scale")
	check(
		S.keeps_present("x/lt_dvd_h.gltf", AABB(Vector3.ZERO, Vector3.ONE), 2.0, 14, 0.05),
		"a light set keeps its scale"
	)
	check(
		not S.keeps_present("x/t72_h.gltf", AABB(Vector3.ZERO, Vector3(3, 2, 9)), 3.0, 5, 0.05), "a tank is an object"
	)
	# Ships at their real hull length (the Osa model's box is 126.4 m long, the real Osa 38.6 m).
	var osa := AABB(Vector3(-14.3, 0, -46.8), Vector3(29.0, 24.8, 126.4))
	S.world_scale = "real"
	check(
		absf(S.ship_scale("x/enmysp_h.gltf", osa) * 126.4 - 38.6) < 0.01 and S.ship_scale("x/t72_h.gltf", osa) == 0.0,
		"Real: the Osa 38.6 m long"
	)
	S.world_scale = "original"
	check(S.ship_scale("x/enmysp_h.gltf", osa) == 0.0, "Original: the ships at their Present scale")

	# --- steps 2–4 in both modes ---
	S.world_scale = "original"
	var o := await _sample(311)
	var o2 := await _sample(214)
	S.world_scale = "real"
	var r := await _sample(311)
	var r2 := await _sample(214)
	check(
		o.player_scale == 2.0 and r.player_scale == 1.0,
		"player's jet: ×2 / ×1 (%s / %s)" % [o.player_scale, r.player_scale]
	)
	check(
		absf(o.clearance - 3.38) < 0.05 and absf(r.clearance - 1.69) < 0.05,
		"on its wheels: origin 3.38 / 1.69 m above the ground (%.2f / %.2f)" % [o.clearance, r.clearance]
	)
	check(
		r.eye.is_equal_approx(o.eye * 0.5) and o.eye.length() > 1.0,
		"cockpit model offset halves (%s / %s)" % [o.eye, r.eye]
	)
	check(r.gun.is_equal_approx(o.gun * 0.5) and o.gun.length() > 1.0, "gun muzzle halves (%s / %s)" % [o.gun, r.gun])
	check(
		o.store_err > 0.5 and r.store_err < 0.01,
		(
			"stores: drawn at their launch points in Real (%.2f m off in Original, %.3f in Real)"
			% [o.store_err, r.store_err]
		)
	)
	check(o.weapon_scale == 2.0 and r.weapon_scale == 1.0, "weapon models ×2 / ×1")
	check(
		o.hidden == r.hidden and not o.hidden.is_empty(), "the same units hidden in both modes (%d)" % o.hidden.size()
	)
	check(o2.hidden == r2.hidden, "214: the same units hidden in both modes (%d)" % o2.hidden.size())
	# 311 has the base's buildings only; 214 adds AI jets (some parked) and SAM sites (Present 3).
	var kinds := {"ai jet": 0, "ground unit": 0, "building": 0, "kept": 0}
	var bad := []
	var units: Dictionary = o.units.merged(o2.units)
	var units_r: Dictionary = r.units.merged(r2.units)
	for id in units:
		var a: Array = units[id]
		var b: Array = units_r.get(id, [])
		if b.is_empty():
			bad.append([id, a])
			continue
		# A kept layout on a moved base (World scale Real, docs/world-scale.md §3.2) takes the base's scale too.
		if absf(b[0] - a[0] * b[4]) < 1e-3:
			kinds.kept += 1
			if absf(a[0] - 1.0) > 1e-3 and not absf(b[1] - a[1] * b[4]) < 0.01:
				bad.append([id, a, b])
		elif absf(b[0] - 1.0) > 1e-3 or absf(b[1] - a[1] / a[0]) > 0.01:
			bad.append([id, a, b])
		elif a[2] in [5, 6, 8, 9, 10] and a[0] >= 3.0:
			kinds["ground unit"] += 1
		elif a[3]:
			kinds["ai jet"] += 1
		elif a[2] in [12, 13]:
			kinds.building += 1
	check(bad.is_empty(), "every unit at 1 (radius / its Present scale) or kept (bad: %s)" % [bad])
	check(
		kinds["ai jet"] > 0 and kinds["ground unit"] > 0 and kinds.building > 0,
		"AI jets, ground units, buildings at 1 (%s)" % kinds
	)
	check(absf(r.underlay - 2.0) < 1e-4, "Ramat David's underlay keeps ×2 (× its base's k: %s)" % r.underlay)

	# --- take-off in Real: wheels on the runway until it lifts off, no crash. 315 starts on Ramon's lineup (311's
	# start is 0.7 km from the moved runway's end at Ramat David, too short for a straight take-off at k 0.69). ---
	var tv = await start_mission(315)
	key(tv, KEY_1)
	key(tv, KEY_B)
	key(tv, KEY_8)
	var t0 := Time.get_ticks_msec()
	var airborne := false
	var worst := 0.0
	await frames(30)
	var h0 := _height(tv)
	while Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		if not is_instance_valid(tv):
			print("the flight ended at %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
			break
		var st: Dictionary = tv.flight.state()
		tv.scripted_stick = Vector2(0.0, 0.5 if st.speed_kt > 150.0 else 0.0)
		if st.on_ground:
			worst = maxf(worst, absf(_height(tv) - h0))
		elif st.speed_kt > 120.0:
			airborne = true
			break
	check(airborne and not tv.flight.state().crashed, "Real: takes off (%.0f kt)" % tv.flight.state().speed_kt)
	check(worst < 0.3, "Real: on the wheels during the roll (worst %.2f m off %.2f)" % [worst, h0])

	# --- the autopilot's landing in Real (312, as test_autopilot.gd) ---
	tv = await start_mission(312)
	await frames(3)
	key(tv, KEY_A)  # level → NAV: the landing waypoint
	Engine.time_scale = 4.0
	var touch := false
	var on_runway := false
	var t1: float = tv._sim_time
	while tv._sim_time - t1 < 600.0 and tv.autopilot.mode != 0 and not tv.flight.state().crashed:
		var st: Dictionary = tv.flight.state()
		if not touch and st.on_ground:
			touch = true
			on_runway = (tv.terrain.surface_at(st.position) & tv.terrain.SURFACE_ANY_RUNWAY) != 0
		await process_frame
	Engine.time_scale = 1.0
	var st: Dictionary = tv.flight.state()
	check(touch and on_runway, "Real: the autopilot touches down on the runway")
	check(not st.crashed and st.speed < 2.0, "Real: landed and stopped (%s, %.1f m/s)" % [st.crash_reason, st.speed])
	check(absf(_height(tv) - 1.69) < 0.1, "Real: stopped on its wheels (%.2f m)" % _height(tv))
	S.world_scale = "original"


func _height(tv) -> float:
	return tv.rig.position.y - float(tv.terrain.height_at(tv.rig.position))


## Mission `id`'s sizes in the current mode.
func _sample(id: int) -> Dictionary:
	var tv = await start_mission(id)
	await frames(5)
	var out := {"units": {}, "hidden": [], "underlay": 0.0}
	for ent in tv.runtime.entities.values():
		if ent.player or ent.get("node") == null or not ent.has("coll_radius"):
			continue
		out.units[ent.key] = [
			ent.node.scale.x, ent.coll_radius, ent.klass, ent.has("pilot"), float(ent.get("base_scale", 1.0))
		]
		if not ent.get("drawn", true):
			out.hidden.append(ent.key)
		if ent.name == "Ramat David":
			out.underlay = ent.node.scale.x / float(ent.get("base_scale", 1.0))
	out.hidden.sort()
	if id != 311:
		return out
	out["player_scale"] = tv.aircraft.scale.x
	await frames(30)  # the first flight-model steps put the wheels on the ground
	out["clearance"] = _height(tv)
	out["eye"] = tv.own_bc.position
	out["gun"] = tv.weapons._gun_offset()
	# A drawn store's position in the jet's frame against its slot (the launch point, body_to_world(slot)).
	var err := 0.0
	for i in tv.weapons._store_nodes:
		var st: Dictionary = tv.weapons.stores.stations[i]
		for j in tv.weapons._store_nodes[i].size():
			var drawn: Vector3 = (
				tv.rig.global_transform.affine_inverse() * tv.weapons._store_nodes[i][j].global_position
			)
			err = maxf(err, drawn.distance_to(st.slots[j]))
	out["store_err"] = err
	out["weapon_scale"] = float(tv.weapons.db.weapons.values()[0].scale)
	return out
