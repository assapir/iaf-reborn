# The F-16's DRIFT C/O switch and display knobs work (modern-iaf/docs/cockpit.md §5.8), on the Barak's take-off mission
# (a ground start, the engine started by the Start engine command), by their commands (the keys' and the clicks'):
#   - DRIFT C/O (252 p1 6): -1 flips NORM and DRIFT C/O, the switch shown there and the Real HUD's panel input with it;
#     0, WARN RESET, puts the HUD's flashing FUEL cue out (fuel under the bingo) and the repeating Altitude call,
#     and leaves the switch at NORM;
#   - HUD CONT (271 p1 0): a step down at a time, round from the bottom to the top; the HUD's contrast follows;
#   - the left MFD's CON (271 p1 1) lifts that screen's black, the right one's stays; its GAIN (271 p1 3) sets the left
#     display's picture gain, the right one's stays.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_display_knobs.gd --log-file <temp>
extends "res://tests/test_mvp.gd"

const DRIFT := "f16/avionics/hud-drift"
const CONT := "f16/avionics/hud-cont"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-display-knobs-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramat_david_takeoff")
	tv.addon.rules = {}  # unscored
	var c3d = tv.cockpit_3d
	var ck = tv.cockpit
	await frames(5)
	check(c3d != null, "the 3D cockpit")
	if c3d == null:
		return
	tv._command([200, 0, 0])  # Start engine: the HUD powered
	check(await _until(tv, func(): return tv.flight.state().engine_on, 120.0), "the engine runs")
	# DRIFT C/O.
	check(int(ck.hud_panel.drift) == 1 and float(c3d.switches.get(DRIFT, -1.0)) == 1.0, "DRIFT C/O starts at NORM")
	tv._command([252, 6, -1])
	await frames(2)
	check(
		ck.hud_panel_input().drift_co and float(c3d.switches.get(DRIFT)) == 2.0,
		"the key: DRIFT C/O, the switch shown there (%s)" % c3d.switches.get(DRIFT)
	)
	tv._command([252, 6, -1])
	await frames(2)
	check(not ck.hud_panel_input().drift_co and float(c3d.switches.get(DRIFT)) == 1.0, "the key again: NORM")
	# WARN RESET puts the FUEL cue out.
	var s := settings()
	var bingo: int = s.bingo_lbs
	s.bingo_lbs = 99000
	check(await _fuel_cue(tv), "fuel under the bingo: the HUD's FUEL cue flashes")
	tv._command([252, 6, 2])
	tv._command([252, 6, 0])
	check(int(ck.hud_panel.drift) == 1, "WARN RESET from DRIFT C/O: the switch at NORM")
	check(not await _fuel_cue(tv), "WARN RESET: the FUEL cue out")
	s.bingo_lbs = bingo
	tv.sounds._alt_timer = 1.0  # the "Altitude" call repeating (flight_sounds.gd _real_warning)
	tv._command([252, 6, 0])
	check(tv.sounds._alt_reset, "WARN RESET: the repeating Altitude call silenced")
	tv.sounds._alt_timer = -1.0
	tv.sounds._alt_reset = false
	# HUD CONT.
	check(is_equal_approx(ck.hud.contrast, 1.0), "HUD CONT at full")
	tv._command([271, 0, 0])
	await frames(2)
	check(is_equal_approx(ck.hud.contrast, 0.75), "HUD CONT a step down: the contrast 0.75 (%s)" % ck.hud.contrast)
	for i in 4:  # 0.5, 0.25, 0, round to 1
		tv._command([271, 0, 0])
	await frames(2)
	check(is_equal_approx(ck.hud.contrast, 1.0), "HUD CONT round from the bottom to the top (%s)" % ck.hud.contrast)
	# The MFDs' CON and GAIN, each display its own.
	var left: StandardMaterial3D = c3d._screens.filter(func(e): return e[0].index == 0)[0][2].material_override
	var right: StandardMaterial3D = c3d._screens.filter(func(e): return e[0].index == 1)[0][2].material_override
	check(left.emission.r == 0.0 and right.emission.r == 0.0, "both MFDs' black black at full contrast")
	tv._command([271, 1, 0])
	await frames(2)
	check(
		is_equal_approx(left.emission.r, 0.0625) and right.emission.r == 0.0,
		"left CON a step down: its black lifted, the right MFD's not (%s, %s)" % [left.emission.r, right.emission.r]
	)
	var mfds: Array = [ck.mfds.filter(func(m): return m.index == 0)[0], ck.mfds.filter(func(m): return m.index == 1)[0]]
	check(is_equal_approx(mfds[0].gain, 1.0) and is_equal_approx(mfds[1].gain, 1.0), "both GAINs at rest: gain 1")
	tv._command([271, 3, 0])
	await frames(2)
	check(
		is_equal_approx(mfds[0].gain, 1.25 / 1.5) and is_equal_approx(mfds[1].gain, 1.0),
		"left GAIN a step down: its picture's gain, the right one's not (%s, %s)" % [mfds[0].gain, mfds[1].gain]
	)
	Engine.time_scale = 1.0


## Whether the Real HUD shows FUEL in any frame over 2 s (it flashes).
func _fuel_cue(tv: Node) -> bool:
	var seen := false
	for i in 120:
		await frames(1)
		for p in tv.cockpit.hud._real.get("outer", []):
			seen = seen or (p.k == "text" and p.text == "FUEL")
	return seen
