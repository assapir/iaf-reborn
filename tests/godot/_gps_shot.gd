# Dev helper (not run by tools/test.sh): real-render captures of the GPS bombs' PRE / VIS targeting (docs/weapons.md
# §13.2–§13.3) into SHOT_DIR: the briefing TSD of mission 231 with the GPS panel and three assigned targets
# (tsd_gps.png); the F-16I's Real HUD in PRE with the LAR staple and the time to max range (hud_f16_tmr.png), then in
# range (hud_f16_inrng.png); the original-style HUD at the same point (hud_original.png); the F-35I's helmet display in
# PRE (hud_f35_pre.png). Every look switch on (Models Detailed, particle effects). With GPS_SHOT=rack only the TSD with
# four GBU-39s on stations 3 and 7, station 3's rack opened: bombs 3-1, 3-2 on a unit, 3-3, 3-4 on a point
# (tsd_gps_rack.png). With GPS_SHOT=tti only the F-16I's Real HUD 5 s after a GBU-31's release 6 km out, the time to
# impact counting down (hud_f16_tti.png).
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=$PWD/.shots -- \
#     --log-file /tmp/s.log --path game -s ../tests/godot/_gps_shot.gd
extends "res://../tests/godot/base.gd"

const GBU31 := 1003
const GBU39 := 1007


func run() -> void:
	await require_data()
	settings().f16_variant = "sufa"
	settings().models = "detailed"
	settings().particle_effects = true
	if OS.get_environment("GPS_SHOT") == "rack":
		await _tsd(true)
		return
	if OS.get_environment("GPS_SHOT") == "tti":
		settings().hud_style = "real"
		await _flight("hud_f16_tti", [2, 4, 6], false, true)
		return
	await _tsd()
	settings().hud_style = "real"
	await _flight("hud_f16", [2, 4, 6])
	settings().hud_style = "original"
	await _flight("hud_original", [2, 4, 6], false)
	settings().hud_style = "real"
	settings().jet_id = 4
	settings().f35i_slot = 4
	await _flight("hud_f35", [2, 6], false)
	settings().jet_id = -1
	settings().f35i_slot = -1


func _load(stations: Array) -> Array:
	var out := []
	for i in 9:
		out.append_array([GBU31, 1] if i in stations else [0, 0])
	return out


## The briefing TSD: a GBU-31 on stations 3, 5, 7; station 3 on a unit, station 7 on a map point, station 5 the
## route's target waypoint (the default). `rack`: the GBU-39 racks of tsd_gps_rack.png instead.
func _tsd(rack := false) -> void:
	settings().mission_id = 231
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	await frames(5)
	fe.tsd_checks["briefing"] = false
	fe.tsd.open_briefing(false)
	var tsd = fe.tsd
	var n: int = tsd.default_flight()
	var load := []
	for i in 9:
		load.append([GBU31, 1] if i in [2, 4, 6] else [0, 0])
		if rack:
			load[i] = [GBU39, 4] if i in [2, 6] else [0, 0]
	settings().arm_loadouts[n] = load
	for i in 2:
		tsd.zoom_by(tsd.ZOOM_STEP)
	var route: Array = tsd.flights[n].points
	var centre: Vector2 = route[route.size() / 2]
	tsd.centre_on(centre)
	await frames(2)
	# An enemy ground unit near the view's centre for station 3.
	var best := -1
	for k in tsd.units.size():
		var u: Dictionary = tsd.units[k]
		if int(u.klass) != 1 and int(u.side) == 2 and tsd._unit_visible(u):
			if best < 0 or u.pos.distance_to(centre) < tsd.units[best].pos.distance_to(centre):
				best = k
	if rack:
		if best >= 0:
			tsd.gps._assign(2, tsd._to_client(tsd.units[best].pos))
		for b in [2, 3]:
			tsd.gps._assign(2, tsd._to_client(centre) + Vector2(40, 30), b)
		tsd.gps.opened[2] = true
		for i in 30:
			await process_frame
		await _save("tsd_gps_rack.png")
		print("shot: tsd rack %s" % [settings().gps_targets])
		settings().arm_loadouts = {}
		fe.queue_free()
		await frames(2)
		return
	if best >= 0:
		tsd.gps._assign(2, tsd._to_client(tsd.units[best].pos))
	tsd.gps._assign(6, tsd._to_client(centre) + Vector2(40, 30))
	tsd.gps.armed = 4
	for i in 30:
		await process_frame
	await _save("tsd_gps.png")
	print("shot: tsd %s" % [settings().gps_targets])
	settings().arm_loadouts = {}
	fe.queue_free()
	await frames(2)


## Mission 231 3,000 m up with GBU-31s on `stations`; a ground unit 4° right of the track is every station's PRE
## target. 18 km out (outside the LAR: TMR) and 6 km out (IN RNG), the nose down at the target.
func _flight(prefix: String, stations: Array, both := true, release := false) -> void:
	var tv = await start_mission(231)
	await frames(10)
	var w = airborne_case(tv, _load(stations) + [25, 235, 33, 90, 34, 60])
	var site := _ground_unit(tv)
	var o: Dictionary = w.own()
	var flat := Vector3(o.fwd.x, o.fwd.y, 0).normalized()
	var t := 100.0
	var b0: Basis = tv.rig.basis
	var dists: Array = [18000.0, 6000.0] if both else [6000.0]
	for d in dists:
		var p: Vector3 = o.pos + flat.rotated(Vector3(0, 0, 1), deg_to_rad(-4.0)) * d
		var g = tv.terrain.height_at(w.to_scene(Vector3(p.x, p.y, 0)))
		p.z = float(g) if g != null else 0.0
		site.world = p
		site.alt = p.z
		tv.mission_entity_moved(site)
		var targets := {}
		for s in stations:
			targets[s] = [p.x, p.y, "T"]
		settings().gps_targets[tv.player_flight_number] = targets
		var dive := rad_to_deg(atan2(o.pos.z - p.z, d)) - 1.0
		tv.rig.basis = b0
		tv.rig.rotate_object_local(Vector3.RIGHT, deg_to_rad(-dive))
		var st: Dictionary = tv.flight.state()
		tv.flight.start(
			settings().assets_dir().path_join("install"),
			tv.player.fm_section,
			tv.rig.position,
			Vector3(-dive, 0.0, st.heading),
			-tv.rig.global_basis.z * 250.0,
			{"airborne": true, "engine_on": true, "real_data": false}
		)
		w.nav_key(0)
		w.stores.cur = stations[0]
		w.select_ag()
		for i in 40:
			await process_frame
			t += 0.05
			w.update(t)
		if release:
			w.fire_selected()
			t += 0.01
			w.update(t)
			w.release_selected()
			for i in 100:
				await process_frame
				t += 0.05
				w.update(t)
			await _save(prefix + ".png")
			print("shot: %s tti %s" % [prefix, tv.cockpit.weapons.get("gps_tti")])
			return
		print("shot: %s %d m %s" % [prefix, d, w.ag.get("gps", {})])
		var file: String = prefix + ("" if not both else ("_tmr" if d > 10000.0 else "_inrng")) + ".png"
		if prefix == "hud_f35":
			file = "hud_f35_pre.png"
		await _save(file)
