# The start-up lesson's steps said and checked as the player meets them (the user, 17 Nov: MAIN PWR "needs 2 clicks.
# the checklist isn't clear enough", "I also see align on the hud but no idea how to do that", "it takes to long after
# finishing the startup to get the mission accomplished screen"): MAIN PWR clicked one position at a time (at BATT the
# notebook says one more click and the JFS still rings), the RPM wait, the INS's STOR HDG, its alignment and NAV, and
# the pass within a few seconds of the last step. The take-off lesson rings the start-up's switches too.
extends "res://tests/test_mvp.gd"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-steps-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramon_startup")
	var kb: Node = tv.addon.kneeboard
	var hint := func() -> String: return String(kb.hint())
	await _call(tv, "startup")
	Engine.time_scale = 1.0
	await _click_control(tv, "MAIN_PWR")
	await frames(3)
	check(tv.flight.start_position("main_power") == 1, "one click: MAIN PWR at BATT")
	check(not "main_power" in tv.addon.done, "at BATT the main power step stays open")
	check(hint.call() == kb.s("nb_hint_batt"), "at BATT the notebook says one more click (%s)" % hint.call())
	check(_ring_text(kb) == hint.call(), "the ring's label says it too (%s)" % _ring_text(kb))
	await _click_control(tv, "MAIN_PWR")
	await frames(3)
	check("main_power" in tv.addon.done and hint.call() == "", "the second click: MAIN PWR, the step done")
	Engine.time_scale = TIME_SCALE
	tv._command([211, 0, 0])  # the JFS: START 2
	await fly(tv, 2.0)
	check(hint.call().begins_with(kb.s("nb_hint_rpm").split("%")[0]), "cranking: wait for 20 %% RPM (%s)" % hint.call())
	await _until(tv, func(): return float(tv.flight.state().rpm) >= 0.2, 60.0)
	_press(tv, KEY_1)  # the throttle to idle
	await _until(tv, func(): return float(tv.flight.state().rpm) >= 0.55, 60.0)
	tv._command([213, 0, 0])  # avionics
	await fly(tv, 1.0)
	tv._command([214, 0, 0])  # INS: STOR HDG
	await fly(tv, 1.0)
	check(tv.flight.ins_knob() == tv.addon.INS_STOR_HDG, "one INS press: STOR HDG")
	check(not "ins" in tv.addon.done, "aligning: the INS step open")
	check(
		hint.call().begins_with(kb.s("nb_hint_ins_wait").split("%")[0]), "aligning: the seconds left (%s)" % hint.call()
	)
	tv._command([215, 0, 0])  # the canopy: the last step until 17 Nov
	var t_canopy: float = tv._sim_time
	await _until(tv, func(): return bool(tv.flight.ins_status()[2]), 120.0)
	var t_aligned: float = tv._sim_time
	check(tv.addon.result.is_empty(), "aligned at STOR HDG: the lesson waits for NAV")
	check(hint.call() == kb.s("nb_hint_ins_nav"), "aligned: the knob to NAV (%s)" % hint.call())
	tv._command([214, 0, 0])
	tv._command([214, 0, 0])
	var t_nav: float = tv._sim_time
	await _until(tv, func(): return not tv.addon.result.is_empty(), 30.0)
	var t_end: float = tv._sim_time
	check(bool(tv.addon.result.get("pass", false)), "the start-up passes (%s)" % [tv.addon.result.get("reasons")])
	print(
		(
			"end delay: before %.1f s after the canopy (the silent alignment, scored every 3 s), now %.1f s after NAV"
			% [t_aligned - t_canopy, t_end - t_nav]
		)
	)
	check(t_end - t_nav <= SCORE_S, "the pass within %d s of the last step (%.1f s)" % [SCORE_S, t_end - t_nav])
	Engine.time_scale = 1.0
	# The take-off lesson rings MAIN PWR after the start-up's clearance (until 17 Nov nothing: the user could not find it).
	tv = await _start("ramon_takeoff")
	await _call(tv, "startup")
	Engine.time_scale = 1.0
	await frames(3)
	check(not tv.addon.kneeboard.marks.is_empty(), "the take-off lesson rings the start-up's first switch")


const SCORE_S := 4


func _ring_text(kb: Node) -> String:
	return String(kb.marks[0].get("text", "")) if not kb.marks.is_empty() else ""
