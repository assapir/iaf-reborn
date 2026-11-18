# The F-16's fuel and brake switches work (modern-iaf/docs/cockpit.md §5.7), on the Barak's take-off mission (a ground
# start, the engine started by the Start engine command), by their command 270 (the keys' and the clicks'):
#   - PARKING BRAKE: set on the ground start (the switch shown at PARKING BRAKE, no brake key held); the jet stays put
#     above idle; released (the key's next position), it rolls;
#   - ENG FEED to OFF: the engine runs on (the proportioner feeds it); MASTER FUEL to OFF cuts the fuel, the engine
#     flames out and winds down, the switch shown there; the idle step is refused (no_fuel) until the fuel feeds again;
#   - ENG FEED at FWD: the forward fuselage fuel falls and the aft rises;
#   - FUEL QTY SEL: NORM the aft and forward fuselage fuel, RSVR the reservoirs, INT WING the wing tanks, TEST 2,000 /
#     2,000 / 6,000 with both FUEL LOW lights; EXT CTR none; the key steps it round, the knob shown there;
#   - the STORES CONFIG light: on exactly while the switch is off the load's category.
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
	# ENG FEED OFF: the engine runs on.
	tv._command([270, 2, 0])
	await fly(tv, 30.0)
	check(
		f.state().engine_on and float(c3d.switches.get(FEED, -1.0)) == 0.0,
		"ENG FEED OFF: the engine runs on, shown at OFF (%s)" % f.state().start_phase
	)
	# ENG FEED FWD: fuel moves from the forward system to the aft.
	f.set_fuel(3000.0 * 0.45359)
	var fwd0: float = c3d._fuel_qty().x
	var aft0: float = c3d._fuel_qty().y
	tv._command([270, 2, 3])
	tv.throttle = 0.3
	await fly(tv, 30.0)
	var q: Vector3 = c3d._fuel_qty()
	check(
		q.x < fwd0 - 20.0 and q.y > aft0,
		"ENG FEED FWD: forward %.0f -> %.0f, aft %.0f -> %.0f" % [fwd0, q.x, aft0, q.y]
	)
	tv._command([270, 2, 1])
	tv.throttle = 0.0
	# MASTER FUEL OFF: the engine flames out.
	tv._command([270, 1, 0])
	await fly(tv, 30.0)
	var st: Dictionary = f.state()
	var off := float(c3d.switches.get(MASTER, -1.0)) == 0.0
	var flamed: bool = not st.engine_on and String(st.start_phase) in ["rundown", "off"]
	var rpm := 100.0 * float(st.rpm)
	check(flamed and off, "MASTER FUEL OFF: flamed out (%s, %.0f %% RPM), shown at OFF" % [st.start_phase, rpm])
	check(f.start_step("engine") == "no_fuel", "MASTER FUEL OFF: the idle step refused (no_fuel)")
	tv._command([270, 1, 1])
	tv._command([200, 0, 0])
	var running: bool = await _until(tv, func(): return f.state().engine_on, 120.0)
	check(running, "MASTER FUEL back on: the engine starts again")
	# FUEL QTY SEL over the tanks.
	f.set_fuel(5800.0 * 0.45359)
	await frames(2)
	check(int(c3d.switches.get(c3d.FQS, -1)) == 1, "FUEL QTY SEL starts at NORM")
	q = c3d._fuel_qty()
	check(
		absf(q.x - 1890.0) < 2.0 and absf(q.y - 2810.0) < 2.0 and absf(q.z - 5800.0) < 2.0,
		"NORM: the forward and aft fuselage fuel, the total on the totalizer (%s)" % q
	)
	tv._command([270, 3, -1])
	await frames(2)
	q = c3d._fuel_qty()
	check(
		absf(q.x - 480.0) < 2.0 and absf(q.y - 480.0) < 2.0 and int(c3d.switches.get(c3d.FQS)) == 2,
		"RSVR: the reservoirs, the knob shown there (%s)" % q
	)
	tv._command([270, 3, -1])
	q = c3d._fuel_qty()
	check(absf(q.x - 550.0) < 2.0 and absf(q.y - 550.0) < 2.0, "INT WING: the wing tanks (%s)" % q)
	for i in 3:  # INT WING -> EXT WING -> EXT CTR -> TEST
		tv._command([270, 3, -1])
	check(c3d._fuel_qty() == Vector3(2000, 2000, 6000), "TEST: 2,000 / 2,000 / 6,000 (%s)" % c3d._fuel_qty())
	check(
		c3d._lamp_on("caution_fwd_fuel_low") and c3d._lamp_on("caution_aft_fuel_low"), "TEST: both FUEL LOW lights on"
	)
	tv._command([270, 3, 5])
	q = c3d._fuel_qty()
	check(q.x == 0.0 and q.y == 0.0, "EXT CTR: no centreline tank (%s)" % q)
	check(absf(c3d._prop("f16/fuel/hand-fwd-lag") - q.x) < 1e-3, "the FWD pointer reads the selection")
	tv._command([270, 3, 1])
	check(not c3d._lamp_on("caution_fwd_fuel_low"), "NORM, full reservoirs: FWD FUEL LOW off")
	# The STORES CONFIG light: on while the switch is off the load's category.
	var cat3: bool = tv.weapons.stores.loading_category() == 3
	tv.cat3 = cat3
	check(not c3d._lamp_on("caution_stores_config"), "STORES CONFIG at the load's category: the light off")
	tv._command([232, 0, 0])  # the switch's key (Alt + S)
	check(c3d._lamp_on("caution_stores_config"), "STORES CONFIG off the load's category: the light on")
	Engine.time_scale = 1.0
