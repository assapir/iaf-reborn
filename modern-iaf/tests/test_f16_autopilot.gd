# The F-16's own autopilot (modern-iaf/docs/research/f16-autopilot.md) flies each mode, on the Barak placed airborne
# over its take-off mission's base (10,000 ft, 350 kt, heading north), by its keys and its 3D cockpit switches:
#   - the PITCH switch clicked to ATT HOLD with ROLL at ATT HOLD: the pitch and bank held for 15 s;
#   - ALT HOLD with HDG SEL, the EHSI's heading marker at 090: the jet turns onto 090 at no more than 30° of bank and
#     holds its altitude within 100 ft;
#   - STRG SEL: the jet turns onto the steerpoint's bearing;
#   - TRIM/AP DISC (its key and its 3D switch) and the gear handle drop the PITCH switch to A/P OFF and refuse it;
#   - autopilot damage: A/P FAIL, the FLCS FAULT caution and the fault list's line; FLCS RESET (its 3D switch)
#     clears it;
#   - none of it puts a line in the band (front-end.md §8).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_f16_autopilot.gd --log-file <temp>
extends "res://tests/test_mvp.gd"

const ALT_M := 3048.0


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-autopilot-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramat_david_takeoff")
	tv.addon.rules = {}  # unscored
	var c3d = tv.cockpit_3d
	await frames(5)
	check(c3d != null and c3d.switches.has(c3d.AP_PITCH), "the 3D cockpit with the autopilot's switches")
	if c3d == null:
		return
	var f = tv.flight
	var pos := Vector3(tv.rig.position.x, ALT_M, tv.rig.position.z)
	tv.rig.position = pos
	f.start(settings().own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 0, -180.0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.7
	Engine.time_scale = 2.0
	await fly(tv, 2.0)
	var ctl = c3d.clickable

	# ATT HOLD in both axes, the PITCH switch clicked.
	ctl.put(ctl._controls.filter(func(e): return e[0].name == "roll-hold-switch")[0][1], -1.0)
	await frames(2)
	var ap: Dictionary = f.ap_state()
	check(int(ap.pitch) == -1 and int(ap.roll) == 0, "PITCH clicked to ATT HOLD, ROLL at ATT HOLD (%s)" % ap)
	var s0: Dictionary = f.state()
	await fly(tv, 15.0)
	var s1: Dictionary = f.state()
	check(
		absf(s1.pitch - s0.pitch) < 1.5 and absf(s1.roll - s0.roll) < 2.0,
		"ATT HOLD 15 s: pitch %.1f -> %.1f, bank %.1f -> %.1f" % [s0.pitch, s1.pitch, s0.roll, s1.roll]
	)

	# ALT HOLD with HDG SEL to the marker at 090: the keys (PITCH up twice, ROLL up).
	tv._command([292, 0, 1])
	tv._command([292, 0, 1])
	c3d.switches[c3d.Display.HDG_BUG] = 90.0
	tv._command([292, 1, 1])
	await frames(2)
	ap = f.ap_state()
	check(int(ap.pitch) == 1 and int(ap.roll) == 1, "the keys: ALT HOLD and HDG SEL (%s)" % ap)
	var alt0 := float(f.state().alt_ft)
	var bank := 0.0
	var dz := 0.0
	var t0: float = tv._sim_time
	# Turned onto 090 and settled (the frame's flight time can run short of the scene's at the test's time scale).
	var settled := 0.0
	while tv._sim_time - t0 < 240.0 and settled < 10.0:
		await process_frame
		bank = maxf(bank, absf(float(f.state().roll)))
		dz = maxf(dz, absf(float(f.state().alt_ft) - alt0))
		settled = settled + tv.get_process_delta_time() if absf(float(f.state().heading) - 90.0) < 3.0 else 0.0
	var hdg := float(f.state().heading)
	check(
		absf(hdg - 90.0) < 5.0 and bank < 32.0 and dz < 100.0,
		"ALT HOLD + HDG SEL: heading %.1f, bank <= %.1f, altitude +-%.0f ft" % [hdg, bank, dz]
	)
	check(c3d.clickable.value(_row(c3d, "roll-hold-switch")) == 1.0, "the PITCH switch shown at ALT HOLD")

	# STRG SEL: toward the steerpoint (ROLL down twice).
	tv._command([292, 1, -1])
	tv._command([292, 1, -1])
	var cp = tv.cockpit
	check(cp.ins_nav() and not cp.steer_route().is_empty(), "STRG SEL: the INS navigates a route")
	var off := func() -> float:
		var b: float = c3d.Display.Hud.nav_cues(cp.state, cp.steer_route(), cp.steer_index()).bearing_deg
		return fposmod(float(f.state().heading) - b + 180.0, 360.0) - 180.0
	var on: bool = await _until(tv, func(): return absf(off.call()) < 5.0, 300.0)
	check(int(f.ap_state().roll) == -1 and on, "STRG SEL: onto the steerpoint's bearing (%.1f off)" % off.call())

	# TRIM/AP DISC drops it and refuses it; NORM again, it engages; the gear handle down drops it.
	tv._command([294, 0, 0])
	await frames(2)
	check(int(f.ap_state().pitch) == 0, "TRIM/AP DISC: A/P OFF")
	tv._command([292, 0, 1])
	await frames(2)
	check(
		int(f.ap_state().pitch) == 0 and c3d.clickable.value(_row(c3d, "roll-hold-switch")) == 0.0,
		"at DISC the PITCH switch springs back to A/P OFF"
	)
	check(c3d.clickable.value(_row(c3d, "SW_TRIM_DISC_50")) == 1.0, "the key moves the 3D TRIM/AP DISC switch to DISC")
	ctl.put(_row(c3d, "SW_TRIM_DISC_50"), 0.0)  # clicked back to NORM
	await frames(2)
	check(not tv.ap_disc, "TRIM/AP DISC clicked to NORM")
	tv._command([292, 0, 1])
	await frames(2)
	check(int(f.ap_state().pitch) == 1, "TRIM/AP DISC at NORM: ALT HOLD engages")
	tv.gear_down = true
	await frames(3)
	check(int(f.ap_state().pitch) == 0, "the gear handle down: A/P OFF")
	tv.gear_down = false

	# Autopilot damage: A/P FAIL, FLCS FAULT and the fault list; repaired, FLCS RESET clears it.
	tv.player_damage.flags[6] = true
	await frames(3)
	tv._command([292, 0, 1])
	await frames(3)
	var lines: Array = c3d.Display.pfl_lines(cp.pfl_flags(), cp.pfl_acked)
	check(
		bool(f.ap_state().fail) and int(f.ap_state().pitch) == 0 and c3d._lamp_on("caution_flt_cont_sys"),
		"A/P FAIL: refused, FLCS FAULT lit (%s)" % [lines]
	)
	check(lines.any(func(l): return str(l).contains("A/P  FAIL")), "the fault list: FLCS A/P FAIL")
	tv.player_damage.flags[6] = false
	await frames(3)
	ctl.put(_row(c3d, "SW_FLCS-RESET"), 1.0)  # the 3D FLCS RESET switch clicked to RESET and let go
	ctl.put(_row(c3d, "SW_FLCS-RESET"), 0.0)
	await frames(2)
	lines = c3d.Display.pfl_lines(cp.pfl_flags(), cp.pfl_acked)
	check(
		not lines.any(func(l): return str(l).contains("A/P  FAIL")),
		"FLCS RESET clicked: A/P FAIL off the list (%s)" % [lines]
	)
	tv._command([292, 0, 1])
	await frames(3)
	check(not bool(f.ap_state().fail) and int(f.ap_state().pitch) == 1, "FLCS RESET: cleared, ALT HOLD engages")
	# No line in the band for any of it: the switches and the caution show it (the user, 25 Nov: "why the fuck there is
	# still notes on a/p, I thought we removed them all?"; modern-iaf/docs/front-end.md §8).
	var band: Array = tv.addon.ui._lines.map(func(e): return str(e[0].get_child(0).text))
	for t in ["A/P OFF", "TRIM/AP DISC", "FLCS RESET", "PITCH ", "ROLL "]:
		check(not band.any(func(l): return l.contains(t)), 'no "%s" line in the band (%s)' % [t, band])


func _row(c3d: Node, node: String) -> Dictionary:
	return c3d.clickable._controls.filter(func(e): return e[0].name == node)[0][1]
