# Modern IAF's MiG-29A (modern-iaf/docs/ai-plan.md K2, X2, X5): an AI jet of its own aircraft definition
# (shared/extra/planes/mig29a, type 1020), put at Ramon's lineup by the dev hook ai_flights.gd `spawn` (no mission
# places one yet) on the Sufa's weapons range mission. It flies on its 6-DoF set (modern-iaf/docs/flight-model.md
# §9.21), drawn with our model (shared/extra/models/mig29/mig29.glb): it takes off, flies its route through the
# autopilot's loops (take-off, the waypoints, the landing as the 1998 brain's rules would set them), lands and stops on
# the runway. The CPU per AI jet per frame at time scale 1 is printed (X5).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_mig29.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 6.0


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	check(load("res://flight/fly.gd").prepare(id), "mission %d prepared as the front end's Fly" % id)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-mig29", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	var b: Dictionary = s.load_ibx(s.own_dir().path_join("iaf.ibx"))["Ramon"]
	var l := Vector3(float(b.LineupLocX), float(b.LineupLocY), float(b.LineupLocZ))
	var hdg := float(b.RunwayNumber)
	var h := deg_to_rad(hdg)
	var along := Vector3(sin(h), cos(h), 0)
	var right := Vector3(cos(h), -sin(h), 0)
	var at := func(a: float, r: float, up: float) -> Vector3: return l + along * a + right * r + Vector3(0, 0, up)
	# The Rust ground run's route (crates/iaf-ai/tests/four_ship.rs): the take-off point, a turn, the landing
	# waypoint 15 km out on the approach (action 7).
	var route := []
	for q in [[15000.0, 0.0, 1500.0, 2], [30000.0, -30000.0, 2500.0, 3], [-35000.0, -10000.0, 2500.0, 3]]:
		var p: Vector3 = at.call(q[0], q[1], q[2])
		route.append([p.x, p.y, p.z, q[3]])
	var fin: Vector3 = at.call(-15000.0, 0.0, 1500.0)
	route.append([fin.x, fin.y, fin.z, 7])
	var ent: Dictionary = tv.ai.spawn("mig29a", l, hdg, route)
	check(not ent.is_empty(), "the MiG-29A spawned at Ramon's lineup")
	if ent.is_empty():
		return
	var p = ent.pilot
	var st: Dictionary = p.flight.state()
	check(p.plane == "mig29a" and ent.type_code == 1020, "its plane and type: %s, %d" % [p.plane, ent.type_code])
	check(bool(st.engine_on) and bool(st.on_ground), "on the runway, its engine running (start rule)")
	# The 6-DoF's state has the flaps' droop; its mass is the MiG-29A's 11,000 kg empty + 3,500 kg fuel and its
	# record's 2 R-27R (253 kg) + 4 R-73 (105 kg) in kg (the stores weight fix): 15,426 kg (flight-model.md §9.21).
	check(st.has("tef") and absf(float(st.mass_kg) - 15426.0) < 50.0, "on its 6-DoF set (%.0f kg)" % st.mass_kg)
	var model: Node3D = ent.node
	check(model != null and model.find_child("LdgL", true, false) != null, "drawn with its model, gear and all")
	check(int(ent.side) != int(tv.runtime.player_entity().get("side", 2)), "on the player's enemy side")
	Engine.time_scale = TIME_SCALE
	p.set_mode(9)  # take-off
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 300.0 and not p.flight.ap_airborne():
		await process_frame
	var up: float = tv._sim_time - t0
	check(p.flight.ap_airborne(), "airborne %.0f s after the take-off order" % up)
	# The waypoints from the take-off point on (the 1998 brain's order), then the landing at the last.
	p.set_waypoint_index(1)
	p.set_mode(7)
	# The CPU per AI jet per frame at time scale 1 (X5), 20 s on the route.
	Engine.time_scale = 1.0
	tv.ai.cost_us = 0
	tv.ai.cost_frames = 0
	await fly(tv, 20.0)
	var ms: float = tv.ai.cost_us / 1000.0 / maxi(tv.ai.cost_frames, 1) / maxi(tv.ai.pilots.size(), 1)
	print(
		(
			"X5: %.3f ms per AI jet per frame (CPU: flight model, autopilot, model and sound; %d jets, %d frames)"
			% [ms, tv.ai.pilots.size(), tv.ai.cost_frames]
		)
	)
	Engine.time_scale = TIME_SCALE
	var top := 0.0
	t0 = tv._sim_time
	while tv._sim_time - t0 < 1500.0 and p.flight.ap_waypoint_index() < 3 and int(ent.state) < 3:
		top = maxf(top, float(ent.world.z) - l.z)
		await process_frame
	check(p.flight.ap_waypoint_index() == 3, "flew the route to the landing waypoint (up to %.0f m)" % top)
	p.set_mode(8)  # home: the landing
	t0 = tv._sim_time
	while tv._sim_time - t0 < 900.0 and not p.flight.ap_landed() and int(ent.state) < 3:
		await process_frame
	st = p.flight.state()
	var off: float = Vector2(ent.world.x - l.x, ent.world.y - l.y).length()
	check(
		p.flight.ap_landed() and not st.crashed and int(ent.state) < 3,
		"landed at Ramon (%.0f m from the lineup, crash %s)" % [off, st.crashed]
	)
	check(off < 5000.0, "on Ramon's runway (%.0f m from the lineup)" % off)
	Engine.time_scale = 1.0
