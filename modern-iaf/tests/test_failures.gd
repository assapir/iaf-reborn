# The failures a lesson starts (modern-iaf/docs/training.md §15), one case per failure, each started through the dev
# hook (sim_flight.gd start_failure) on a jet placed airborne over its take-off mission's base (10,000 ft, heading
# north), with its real indications and its recovery by the checklist's steps:
#   - engine_fire: ENG FIRE, OVERHEAT, MASTER CAUTION, FIRE on the fault list; the throttle to minimum puts it out;
#   - flameout: the engine runs down, ENGINE lights, the EPU starts; the throttle to OFF and up again relights it;
#   - hyd_a / hyd_b: HYD/OIL PRESS, the system's gauge at zero, ISA ALL FAIL; with B the lever leaves the gear up and
#     ALT GEAR lowers it;
#   - gen_main: MAIN GEN and ELEC SYS, the displays stay up; gen_both: MAIN GEN and STBY GEN, the EPU starts by itself
#     and holds the displays; gen_epu: the EPU does not start until its switch goes to ON;
#   - standby_gains: STBY GAINS, the FLCS light, STBY GAIN on the fault list;
#   - the F-35I: the fire on its ENG FIRE light and the ICAWS, its generator on the IPP, the gear fault (GEAR FAIL,
#     the gear stays down), and the F-16-only failures
#     refused with their reason.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_failures.gd --log-file <temp>
extends "res://tests/test_mvp.gd"

const ALT_M := 3048.0


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-failures-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var tv := await _start("ramat_david_takeoff")
	tv.addon.rules = {}  # unscored
	await frames(5)
	check(tv.cockpit_3d != null, "the Barak's 3D cockpit")
	if tv.cockpit_3d == null:
		return
	await engine_fire(tv)
	await flameout(tv)
	await hydraulics(tv)
	await generators(tv)
	await standby_gains(tv)
	var f35 := await _start("nevatim_takeoff")
	f35.addon.rules = {}
	await frames(5)
	await adir(f35)


## The jet placed airborne again (a new flight: no failures), the throttle at `throttle`.
func _air(tv: Node, throttle := 0.7) -> void:
	var pos := Vector3(tv.rig.position.x, ALT_M, tv.rig.position.z)
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 0, -180.0), airborne_flags()
	)
	tv.gear_down = false
	tv.gear_legs = [0, 0, 0]
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = throttle
	tv.cockpit.indicators[0] = false
	tv.addon._failures_seen = []
	tv.player_damage.flags.fill(false)  # a case's gear lowered fast leaves no damage for the next
	Engine.time_scale = 2.0
	await fly(tv, 2.0)


func _lamp(tv: Node, key: String) -> bool:
	return tv.cockpit_3d._lamp_on(key)


func _pfl(tv: Node) -> Array:
	return tv.cockpit_3d.Display.pfl_faults(tv.cockpit.pfl_flags()).map(func(f): return String(f[2]).strip_edges())


## Starts `id` by the dev hook and lets two frames pass: its start announced (MASTER CAUTION, the recording).
func _fail(tv: Node, id: String) -> void:
	var e: String = tv.addon.start_failure(id)
	check(e == "", "%s: started by the dev hook (%s)" % [id, e])
	await frames(3)
	check(tv.cockpit.indicators[0] and tv.addon._failures_seen.has(id), "%s: MASTER CAUTION and the voice" % id)


func engine_fire(tv: Node) -> void:
	await _air(tv, 0.74)
	await _fail(tv, "engine_fire")
	check(_lamp(tv, "eng_fire") and _lamp(tv, "caution_overheat"), "engine_fire: ENG FIRE and OVERHEAT lit")
	check(_pfl(tv).has(">FIRE          <"), "engine_fire: FIRE on the fault list (%s)" % [_pfl(tv)])
	tv.throttle = 0.2  # THROTTLE - MINIMUM PRACTICAL
	await fly(tv, 17.0)
	check(not _lamp(tv, "eng_fire"), "engine_fire: out at minimum thrust")
	check(String(tv.flight.state().get("start_phase", "")) == "running", "engine_fire: the engine still runs")


func flameout(tv: Node) -> void:
	await _air(tv, 0.6)
	await _fail(tv, "flameout")
	await fly(tv, 20.0)
	var st: Dictionary = tv.flight.state()
	check(float(st.rpm) < 0.52 and _lamp(tv, "engine"), "flameout: run down (%.0f %%), ENGINE lit" % (100.0 * st.rpm))
	check(_lamp(tv, "main_gen") and _lamp(tv, "epu_run"), "flameout: MAIN GEN lit, the EPU runs by itself")
	tv.addon.throttle_off()  # THROTTLE - OFF, then midrange
	await frames(3)
	tv.throttle = 0.4
	var lit := await _until(tv, func(): return String(tv.flight.state().get("start_phase", "")) == "running", 60.0)
	check(lit, "flameout: the air start relit it (%s)" % tv.flight.state().get("start_phase", ""))


func hydraulics(tv: Node) -> void:
	await _air(tv)
	await _fail(tv, "hyd_a")
	await frames(3)
	var ab: PackedFloat32Array = tv.cockpit.state.get("hyd_ab", PackedFloat32Array([1.0, 1.0]))
	check(_lamp(tv, "hyd_oil_press") and ab[0] == 0.0 and ab[1] > 0.9, "hyd_a: HYD/OIL PRESS, gauge A at 0 (%s)" % ab)
	check(_pfl(tv).has("ISA  ALL  FAIL") and _lamp(tv, "caution_flt_cont_sys"), "hyd_a: ISA ALL FAIL, FLCS FAULT")

	await _air(tv, 0.6)
	await _fail(tv, "hyd_b")
	tv.throttle = 0.0  # slow to the ALT GEAR's 190 kt first
	tv.brakes = true
	await _until(tv, func(): return float(tv.flight.state().cas_kt) < 200.0, 120.0)
	tv.brakes = false
	tv.throttle = 0.6
	tv._press([14, 0, 0])  # the gear handle down: nothing moves
	await fly(tv, 8.0)
	check(not tv.cockpit.gear_legs.any(func(v): return int(v) == 2), "hyd_b: the gear handle alone leaves it up")
	tv.cockpit_3d.clickable._system_put("alt_gear", 1.0)  # ALT GEAR handle - PULL
	await fly(tv, 8.0)
	var st: Dictionary = tv.flight.state()
	check(
		tv.cockpit.gear_legs.all(func(v): return int(v) == 2),
		(
			"hyd_b: ALT GEAR lowers it (%s; gear %.2f, %.0f kt, gear damage %s)"
			% [tv.cockpit.gear_legs, st.gear, st.cas_kt, tv.player_damage.flags[7]]
		)
	)
	tv.cockpit_3d.clickable._system_put("alt_gear", 0.0)


func generators(tv: Node) -> void:
	await _air(tv)
	await _fail(tv, "gen_main")
	await fly(tv, 2.0)
	check(
		_lamp(tv, "main_gen") and not _lamp(tv, "stby_gen") and _lamp(tv, "caution_elec_sys"),
		"gen_main: MAIN GEN, ELEC SYS"
	)
	check(int(tv.flight.state().get("power", 0)) == 2, "gen_main: the standby generator holds the displays")

	await _air(tv)
	await _fail(tv, "gen_both")
	await fly(tv, 6.0)
	check(_lamp(tv, "main_gen") and _lamp(tv, "stby_gen") and _lamp(tv, "epu_run"), "gen_both: both lit, EPU run")
	check(
		int(tv.flight.state().get("power", 0)) == 2,
		"gen_both: the EPU holds the displays (%d)" % tv.flight.state().get("power", 0)
	)

	await _air(tv)
	await _fail(tv, "gen_epu")
	await fly(tv, 6.0)
	check(
		not _lamp(tv, "epu_run") and int(tv.flight.state().get("power", 0)) == 1,
		"gen_epu: no automatic EPU start, the displays dark"
	)
	tv.cockpit_3d.switches[tv.cockpit_3d.EPU_SW] = 2.0  # EPU - ON
	await fly(tv, 6.0)
	check(
		_lamp(tv, "epu_run") and int(tv.flight.state().get("power", 0)) == 2,
		"gen_epu: EPU at ON runs it and the displays come back"
	)
	tv.cockpit_3d.switches[tv.cockpit_3d.EPU_SW] = 1.0


func standby_gains(tv: Node) -> void:
	await _air(tv)
	await _fail(tv, "standby_gains")
	check(_lamp(tv, "stby_gains") and _lamp(tv, "flcs"), "standby_gains: STBY GAINS and FLCS lit")
	check(_pfl(tv).has(">STBY GAIN     <"), "standby_gains: STBY GAIN on the fault list (%s)" % [_pfl(tv)])
	var z0: float = tv.flight.state().alt_ft
	await fly(tv, 10.0)
	check(absf(float(tv.flight.state().alt_ft) - z0) < 500.0, "standby_gains: the jet flies on its fixed gains")


func adir(tv: Node) -> void:
	await _air(tv, 0.74)
	for id in ["hyd_a", "hyd_b", "gen_both", "gen_epu"]:
		var e: String = tv.addon.start_failure(id)
		check(e != "", "F-35I: %s refused (%s)" % [id, e])
	await _fail(tv, "engine_fire")
	check(_lamp(tv, "eng_fire"), "F-35I engine_fire: ENG FIRE lit")
	var pcd = tv.cockpit.pcd
	check(pcd != null and pcd.cautions().any(func(c): return c[0] == "ENG FIRE"), "F-35I engine_fire: ICAWS ENG FIRE")
	await _air(tv)
	await _fail(tv, "gen_main")
	await fly(tv, 3.0)
	var lines: Array = pcd.fmt.icaws_lines(pcd.cautions()) if pcd != null else []
	check(lines.any(func(c): return c[0] == "ELEC FAIL"), "F-35I gen_main: ICAWS ELEC FAIL (%s)" % [lines])
	check(int(tv.flight.state().get("power", 0)) == 2, "F-35I gen_main: the IPP holds the displays")
	# The gear fault (the Eielson crash): the gear lowered, then it does not come up.
	await _air(tv)
	tv.throttle = 0.0
	tv.brakes = true
	await _until(tv, func(): return float(tv.flight.state().cas_kt) < 250.0, 120.0)
	tv.brakes = false
	tv.throttle = 0.6
	tv._press([14, 0, 0])  # gear down
	await _until(tv, func(): return tv.cockpit.gear_legs.all(func(v): return int(v) == 2), 30.0)
	await _fail(tv, "gear_fault")
	tv._press([14, 0, 0])  # gear up: it stays down
	await fly(tv, 8.0)
	lines = pcd.fmt.icaws_lines(pcd.cautions()) if pcd != null else []
	check(
		tv.cockpit.gear_legs.all(func(v): return int(v) == 2) and bool(tv.flight.failures().gear_held),
		"F-35I gear_fault: the gear stays down with the handle up (%s)" % [tv.cockpit.gear_legs]
	)
	check(lines.any(func(c): return c[0] == "GEAR FAIL"), "F-35I gear_fault: ICAWS GEAR FAIL (%s)" % [lines])
