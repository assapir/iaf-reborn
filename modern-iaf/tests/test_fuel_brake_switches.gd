# The F-16's fuel and brake switches work (modern-iaf/docs/cockpit.md §5.7), on the Barak's take-off mission (a ground
# start, the engine started by the Start engine command), by their command 270 (the keys' and the clicks'):
#   - PARKING BRAKE: set on the ground start (the switch shown at PARKING BRAKE, no brake key held); the jet stays put
#     above idle; released (the key's next position), it rolls;
#   - ENG FEED to OFF, then MASTER FUEL to OFF: each cuts the fuel, the engine flames out and winds down, the switch
#     shown there; the idle step is refused (no_fuel) until the fuel feeds again;
#   - FUEL QTY SEL: NORM shows half the internal fuel on each pointer and the total on the totalizer; TEST 2,000 /
#     2,000 / 6,000; EXT CTR none; the key steps it round.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_fuel_brake_switches.gd --log-file <temp>
extends "res://tests/test_mvp.gd"

const PARKING := "controls/gear/brake-parking"
const MASTER := "fdm/jsbsim/elec/switches/master-fuel-cmd"
const FEED := "f16/engine/feed"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-fuel-brake-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramat_david_takeoff")
	tv.addon.rules = {}  # unscored
	var f = tv.flight
	var c3d = tv.cockpit_3d
	await frames(5)
	check(c3d != null, "the 3D cockpit")
	if c3d == null:
		return
	# The parking brake holds the jet.
	check(
		int(f.switch("parking_brake")) == 1 and not tv.brakes and float(c3d.switches.get(PARKING, -1.0)) == 1.0,
		"ground start: the parking brake set, shown at PARKING BRAKE, no brake key (%s)" % c3d.switches.get(PARKING)
	)
	tv._command([200, 0, 0])  # Start engine
	check(await _until(tv, func(): return f.state().engine_on, 120.0), "the engine runs")
	tv.throttle = 0.3
	await fly(tv, 5.0)
	var kt := float(f.state().get("speed_kt", 0.0))
	check(kt < 0.5, "parking brake set, throttle 0.3 for 5 s: the jet stays (%.1f kt)" % kt)
	tv._command([270, 0, -1])  # the key: the next position, off
	await fly(tv, 5.0)
	kt = float(f.state().get("speed_kt", 0.0))
	check(
		int(f.switch("parking_brake")) == 0 and float(c3d.switches.get(PARKING)) == 0.0 and kt > 3.0,
		"parking brake off: the jet rolls (%.1f kt)" % kt
	)
	tv.throttle = 0.0
	tv.brakes = true
	await fly(tv, 5.0)
	# ENG FEED OFF, then MASTER FUEL OFF: the engine flames out each time.
	for sw in [[2, FEED, "ENG FEED"], [1, MASTER, "MASTER FUEL"]]:
		tv._command([270, sw[0], 0])
		await fly(tv, 30.0)
		var st: Dictionary = f.state()
		check(
			(
				not st.engine_on
				and String(st.start_phase) in ["rundown", "off"]
				and float(c3d.switches.get(sw[1], -1.0)) == 0.0
			),
			(
				"%s OFF: the engine flamed out (%s, %.0f %% RPM), the switch shown at OFF"
				% [sw[2], st.start_phase, 100.0 * float(st.rpm)]
			)
		)
		check(f.start_step("engine") == "no_fuel", "%s OFF: the idle step refused (no_fuel)" % sw[2])
		tv._command([270, sw[0], 1])
		tv._command([200, 0, 0])
		check(await _until(tv, func(): return f.state().engine_on, 120.0), "%s back on: the engine starts again" % sw[2])
	# FUEL QTY SEL.
	check(int(c3d.switches.get(c3d.FQS, -1)) == 1, "FUEL QTY SEL starts at NORM")
	var cs: Dictionary = c3d.cockpit.state
	var fuel := float(cs.fuel_lbs)
	var inside := minf(fuel, float(cs.internal_fuel_kg) / 0.45359)
	var q: Vector3 = c3d._fuel_qty()
	check(
		absf(q.x - inside / 2.0) < 1.0 and absf(q.y - inside / 2.0) < 1.0 and absf(q.z - fuel) < 1.0,
		"NORM: half the internal fuel on each pointer, the total on the totalizer (%s)" % q
	)
	for i in 5:  # NORM -> RSVR -> INT WING -> EXT WING -> EXT CTR -> TEST
		tv._command([270, 3, -1])
	check(c3d._fuel_qty() == Vector3(2000, 2000, 6000), "TEST: 2,000 / 2,000 / 6,000 (%s)" % c3d._fuel_qty())
	tv._command([270, 3, 5])
	q = c3d._fuel_qty()
	check(q.x == 0.0 and q.y == 0.0, "EXT CTR: no centreline tank (%s)" % q)
	check(absf(c3d._prop("f16/fuel/hand-fwd-lag") - q.x) < 1e-3, "the FWD pointer reads the selection")
	Engine.time_scale = 1.0
