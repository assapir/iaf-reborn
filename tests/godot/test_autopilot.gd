# The player's autopilot (docs/autopilot.md): an airborne start begins in level mode (lamp 8, HUD "AP LVL"),
# A cycles level → NAV → off, a stick key beyond ±51 % disengages, the throttle keys are dropped in NAV, and
# level mode holds wings level and heading. Mission 312 "Eagle Baby" (Landing): NAV on its only waypoint
# (action 7, land) is the go-home / landing circuit the instructor demonstrates: it touches down on the runway
# centreline and StopPlane's A key turns the autopilot off.
extends "res://../tests/godot/base.gd"


func set_key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func fly(tv: Node, seconds: float) -> void:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < seconds:
		await process_frame


func run() -> void:
	var tv = await start_mission(312)
	await frames(3)
	check(tv.autopilot != null and tv.autopilot.mode == 1, "airborne start: autopilot on in level mode")
	check(tv.cockpit.indicators[8], "AP lamp lit")
	check(int(tv.cockpit.state.get("ap_mode", 0)) == 1, "HUD shows AP LVL")
	Engine.time_scale = 4.0
	await fly(tv, 20.0)
	var st: Dictionary = tv.flight.state()
	print("  level: ", tv.flight.ap_stage(), " roll %.1f heading %.1f alt %.0f" % [st.roll, st.heading, st.alt_ft])
	check(absf(st.roll) < 3.0 and absf(st.heading - 270.0) < 3.0, "level mode: wings level, heading held")
	# Stick key: Right arrow sends +100 → the autopilot goes off, the lamp too, the stick moves.
	set_key(KEY_RIGHT, true)
	await frames(2)
	check(tv.autopilot.mode == 0 and not tv.cockpit.indicators[8] and tv.stick.x > 0.9, "stick key beyond ±51 %: autopilot off")
	set_key(KEY_RIGHT, false)
	await frames(2)
	# A: off → level → NAV.
	key(tv, KEY_A)
	check(tv.autopilot.mode == 1 and tv.cockpit.indicators[8], "A: level")
	check(not tv.autopilot.stick_event(Vector2(0.3, 0.0)) and tv.autopilot.mode == 1, "a small stick event is dropped")
	key(tv, KEY_A)
	await frames(1)
	check(tv.autopilot.mode == 2 and int(tv.cockpit.state.get("ap_mode", 0)) == 2, "A: NAV (HUD AP NAV)")
	var thr: float = tv.throttle
	key(tv, KEY_1)
	check(is_equal_approx(tv.throttle, thr), "NAV: throttle keys dropped")
	await fly(tv, 5.0)
	check(tv.flight.ap_stage().begins_with("go home"), "NAV to the landing waypoint: go home (%s)" % tv.flight.ap_stage())
	# The demonstration circuit: crosswind, downwind (gear and flaps), base.
	var stage := ""
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 260.0 and not tv.flight.ap_stage().ends_with("step 8"):
		await process_frame
	Engine.time_scale = 1.0
	stage = tv.flight.ap_stage()
	st = tv.flight.state()
	print("  after %.0f s: %s alt %.0f ft speed %.0f kt gear %s flaps %.1f" % [tv._sim_time - t0, stage, st.alt_ft, st.speed_kt, tv.gear_down, tv.flaps])
	check(stage == "landing step 8", "the circuit: downwind flown, base turn next (%s)" % stage)
	check(tv.gear_down and tv.flaps > 0.0, "gear and flaps lowered by the autopilot (on the levers)")
	check(not st.crashed, "no crash")
	# Base, the turn onto final, the 6° final and the roll-out: StopPlane then posts the A key (autopilot off).
	Engine.time_scale = 4.0
	var touch := Vector2.INF
	t0 = tv._sim_time
	while tv._sim_time - t0 < 300.0 and tv.autopilot.mode != 0 and not tv.flight.state().crashed:
		st = tv.flight.state()
		if touch == Vector2.INF and st.on_ground:
			touch = Vector2(st.position.x + tv.terrain.world_origin.x, -st.position.z + tv.terrain.world_origin.y)
			var surf: int = tv.terrain.surface_at(st.position)
			print("  touchdown at %.0f %.0f (%.1f m off the centreline), surface %x" % [touch.x, touch.y, touch.y - 602383.0, surf])
			check((surf & tv.terrain.SURFACE_ANY_RUNWAY) != 0, "touchdown on the runway surface (%x)" % surf)
		await process_frame
	Engine.time_scale = 1.0
	st = tv.flight.state()
	check(not st.crashed, "landed without a crash (%s)" % st.crash_reason)
	check(touch != Vector2.INF and absf(touch.y - 602383.0) < 30.0, "touchdown on the centreline ±30 m (%s)" % touch)
	check(tv.autopilot.mode == 0 and not tv.cockpit.indicators[8], "stopped: StopPlane's A key turns the autopilot off")
	check(st.speed < 2.0, "stopped on the runway (%.1f m/s)" % st.speed)
