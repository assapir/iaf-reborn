# Modern IAF's instructor flies the player's jet (modern-iaf/docs/training-plan.md §2.3, modern-iaf/docs/training.md
# "The instructor flies"), headless: mission ramon_takeoff (the Sufa), the player's jet put in the air 12 km out on
# Ramon's centreline at 1,500 ft and 300 kt, then the dev hook flight/instructor.gd `demo`:
#   - "My controls." as a subtitle, in English and Hebrew;
#   - the player's autopilot flies the overhead pattern in order: the initial, the break, the downwind, the base turn,
#     the final, StopPlane (IafFlight ap_landing_step 3, 4, 7, 11, 13, 14);
#   - the stick the flight model takes swings past 0.2 left into the turns and back right to roll out, and the throttle
#     lever moves (the 3D cockpit's stick and throttle follow them: terrain_view.gd parts_in);
#   - the jet lands without a crash and stops on the runway, then "Your controls." and the autopilot off.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_instructor_demo.gd --log-file <temp>
extends "res://../modern-iaf/tests/instructor_base.gd"


func run() -> void:
	var tv: Node = await start_in_air("ramon_takeoff", "Ramon")
	if tv == null:
		return
	var ins = Instructor.of(tv)
	check(ins.demo(), "the demonstration starts")
	check(ins.said == ["my_controls"], "my controls said (%s)" % [ins.said])
	check(tv.addon.ui.band_texts().has("My controls."), "its subtitle shown")
	var pair = tv.radio.subtitles.get("My controls.")
	check(pair != null and pair[1] == Instructor.LINES.my_controls[1], "its Hebrew subtitle")
	var steps := []
	var stick := Vector2(INF, -INF)
	var thr := Vector2(INF, -INF)
	Engine.time_scale = TIME_SCALE
	var t0: float = tv._sim_time
	while ins.role == "demo" and tv._sim_time - t0 < 900.0:
		await process_frame
		var n: int = tv.flight.ap_landing_step()
		if n >= 0 and (steps.is_empty() or steps[-1] != n):
			steps.append(n)
		var fs: Dictionary = tv.flight.state()
		stick = Vector2(minf(stick.x, fs.roll_stick), maxf(stick.y, fs.roll_stick))
		thr = Vector2(minf(thr.x, tv.throttle), maxf(thr.y, tv.throttle))
		if fs.crashed:
			break
	Engine.time_scale = 1.0
	var fs: Dictionary = tv.flight.state()
	print("steps %s, roll stick %s, throttle %s, %.0f s, %s" % [steps, stick, thr, tv._sim_time - t0, ins.said])
	check(not fs.crashed, "no crash")
	check(in_order(steps, [3, 4, 7, 11, 13, 14]), "the overhead's steps in order (%s)" % [steps])
	check(stick.x < -0.2 and stick.y > 0.05, "the stick moves both ways (%s)" % stick)
	check(thr.y - thr.x > 0.3, "the throttle moves (%s)" % thr)
	check(fs.on_ground and float(fs.speed) < 2.0 and on_runway(tv), "stopped on the runway")
	check(ins.said == ["my_controls", "your_controls"], "your controls said (%s)" % [ins.said])
	check(tv.flight.ap_player() == 0, "the autopilot off")
