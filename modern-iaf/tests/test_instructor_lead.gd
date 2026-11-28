# Modern IAF's F-35I instructor in a second F-35I (modern-iaf/docs/training-plan.md §2.3, §4;
# modern-iaf/docs/training.md "The instructor flies"), headless: mission nevatim_takeoff (the Adir), the player's jet
# put in the air 12 km out on Nevatim's centreline at 1,500 ft and 300 kt on its autopilot's level mode, then the dev
# hooks of flight/instructor.gd:
#   - `chase`: the instructor's F-35I joins the player's flight as Kidon 1-2 (IafAi) and holds within 400 m of the
#     player after 60 s;
#   - `lead`: "Follow me." as a subtitle; it leaves the flight and flies the overhead pattern in order (the initial,
#     the break, the downwind, the base turn, the final, StopPlane), lands at Nevatim without a crash and stops.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_instructor_lead.gd --log-file <temp>
extends "res://../modern-iaf/tests/instructor_base.gd"


func run() -> void:
	var tv: Node = await start_in_air("nevatim_takeoff", "Nevatim")
	if tv == null:
		return
	tv.flight.ap_engage(1, 0)  # the player's jet on level
	tv.autopilot._lamp()
	var ins = Instructor.of(tv)
	check(ins.chase(), "the instructor's F-35I in the player's flight")
	check(tv.ai.flight_ai != null and tv.ai._ai_members.size() == 2, "Kidon 1-1 and 1-2")
	Engine.time_scale = TIME_SCALE
	await fly(tv, 60.0)
	var gap: float = ins.jet.world.distance_to(tv.player_world())
	check(gap < 400.0, "the chase within 400 m of the player after 60 s (%.0f m)" % gap)
	check(ins.lead(), "the lead starts")
	check(ins.said == ["follow_me"], "follow me said (%s)" % [ins.said])
	check(tv.addon.ui.band_texts().has("Follow me."), "its subtitle shown")
	check(tv.ai.flight_ai == null, "the instructor out of the flight")
	var f = ins.jet.pilot.flight
	var steps := []
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 900.0 and int(ins.jet.state) < 3 and not f.ap_landed():
		await process_frame
		var n: int = f.ap_landing_step()
		if n >= 0 and (steps.is_empty() or steps[-1] != n):
			steps.append(n)
	Engine.time_scale = 1.0
	var off: float = Vector2(ins.jet.world.x - lineup.x, ins.jet.world.y - lineup.y).length()
	print(
		(
			"lead: steps %s, %s, landed %s, %.0f m from the lineup, %.0f s"
			% [steps, f.ap_stage(), f.ap_landed(), off, tv._sim_time - t0]
		)
	)
	check(int(ins.jet.state) < 3 and not f.state().crashed, "no crash")
	check(in_order(steps, [3, 4, 7, 11, 13, 14]), "the overhead's steps in order (%s)" % [steps])
	check(f.ap_landed() and off < 5000.0, "landed at Nevatim")
