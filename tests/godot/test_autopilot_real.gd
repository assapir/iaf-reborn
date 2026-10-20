# Mission 312 "Eagle Baby" in World scale Real 1:1 (docs/world-scale.md §3.3): the start, the markers and the route
# move with Ramat David, so NAV from the airborne start flies straight down the moved centreline (no turn), and the
# autopilot's circuit passes the moved markers: the instructor's base turn, final turn, final and touch-and-go call.
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().world_scale = "real"
	var tv = await start_mission(312)
	var rec := record_mission(tv)
	await frames(3)
	key(tv, KEY_A)
	await frames(1)
	check(tv.autopilot.mode == 2, "A: NAV")
	Engine.time_scale = 4.0
	var bank := 0.0
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 30.0:
		bank = maxf(bank, absf(tv.flight.state().roll))
		await process_frame
	check(bank < 5.0, "NAV from the start: straight toward the moved approach waypoint (bank ≤ %.1f°)" % bank)
	t0 = tv._sim_time
	while tv._sim_time - t0 < 600.0 and tv.autopilot.mode != 0 and not tv.flight.state().crashed:
		await process_frame
	Engine.time_scale = 1.0
	var st: Dictionary = tv.flight.state()
	print("  events %s, stage %s, speed %.1f" % [rec.events, tv.flight.ap_stage(), st.speed])
	check(not st.crashed and st.on_ground and st.speed < 2.0, "landed and stopped (%s)" % st.crash_reason)
	check_instructor_312(tv, rec)
