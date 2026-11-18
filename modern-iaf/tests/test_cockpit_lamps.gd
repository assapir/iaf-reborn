# The F-16s' 3D-cockpit lamps (the lights audit, 2026-11-17; modern-iaf/docs/cockpit.md "Lamps"): in each F-16's cold
# start-up every lamp is dark without power; on the battery the start-up's lamps light (ENGINE, HYD / OIL PRESS, CANOPY,
# the ELEC panel, ELEC SYS and MASTER CAUTION) and MAL & IND LTS lights them all; each switch-driven lamp follows its
# switch, each state-driven one its state, MASTER CAUTION and the ELEC panel's CAUTION RESET put it out; started, the
# start-up's lamps go out (the JFS RUN and the battery-to-FLCS lamps through the start).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_cockpit_lamps.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup"}
## Lit on the battery, the engine stopped and the canopy up.
const ON_BATTERY := [
	"engine",
	"hyd_oil_press",
	"canopy",
	"main_gen",
	"stby_gen",
	"flcs_pmg",
	"flcs_rly",
	"caution_elec_sys",
	"master_caution"
]

var _ctl: Node
var _c3d: Node
var _id := ""


func run() -> void:
	var icaws: Array = load("res://shared/cockpit/pcd_formats.gd").DAMAGE_CAUTIONS.map(func(r): return r[1])
	check(icaws.has("FCS FAIL") and not icaws.any(func(t): return "FLCS" in t), "the Adir's ICAWS says FCS")
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
		_id = id
		var s := settings()
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(JETS[id] + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": JETS[id], "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await frames(5)
		_c3d = tv.cockpit_3d
		check(_c3d != null and _c3d.clickable != null, "%s: the clickable controls" % id)
		if _c3d == null or _c3d.clickable == null:
			continue
		_ctl = _c3d.clickable
		check(_c3d._lamps.size() >= 100, "%s: the model's lamps (%d keys)" % [id, _c3d._lamps.size()])
		_c3d._process(0.0)
		check(not _c3d.lamps_lit.values().has(true), "%s: cold, every lamp dark %s" % [id, _lit()])
		tv.addon.pick("startup")  # the tower's clearance (training.md §3.3)
		_ctl.put(_r("MAIN_PWR"), 2.0)  # MAIN PWR
		for i in 300:
			if tv.cockpit.power >= 1:
				break
			await process_frame

		_c3d._process(0.0)
		var missing: Array = ON_BATTERY.filter(func(k): return not _c3d.lamps_lit.get(k, false))
		check(missing.is_empty(), "%s: on the battery the start-up's lamps lit (dark: %s)" % [id, missing])
		check(not _lit_now("jfs_run") and not _lit_now("to_flcs"), "%s: JFS RUN, ACFT BATT TO FLCS dark" % id)
		_lamp_test(id)
		_resets(tv, id)
		await _switches(tv, id)
		_states(tv, id)
		await _start(tv, id)


func _r(node: String) -> Dictionary:
	return _ctl._controls.filter(func(e): return e[0].name == node)[0][1]


func _lit_now(key: String) -> bool:
	_c3d._process(0.0)
	return bool(_c3d.lamps_lit.get(key, false))


func _lit() -> Array:
	return _c3d.lamps_lit.keys().filter(func(k): return _c3d.lamps_lit[k])


## The node of lamp `key` (the first) and whether it shows lit: visible and glowing.
func _shows(key: String) -> bool:
	var l: Array = _c3d._lamps[key][0]
	var mats: Array = l[2]
	return l[0].is_visible_in_tree() and mats.all(func(m): return m.emission_energy_multiplier > 0.0)


## MAL & IND LTS held: every lamp lit and shown lit, every unlit twin (the caution panel's legends) hidden; let go,
## as before.
func _lamp_test(id: String) -> void:
	_ctl.press(_r("MAL_IND_LTS"))
	_c3d._process(0.0)
	var dark: Array = _c3d.lamps_lit.keys().filter(func(k): return not _c3d.lamps_lit[k])
	check(dark.is_empty(), "%s: MAL & IND LTS lights every lamp (dark: %s)" % [id, dark])
	var keys: Array = _c3d._lamps.keys()
	var unshown: Array = keys.filter(func(k): return not k.ends_with("_unlit") and not _shows(k))
	check(unshown.is_empty(), "%s: ... each shown lit (not: %s)" % [id, unshown])
	var twins: Array = keys.filter(func(k): return k.ends_with("_unlit") and _c3d._lamps[k][0][0].visible)
	check(twins.is_empty(), "%s: ... the unlit legends hidden (%s)" % [id, twins])
	check(_c3d._legend_lamps.size() >= 6, "%s: the buttons' legend lamps (%d)" % [id, _c3d._legend_lamps.size()])
	_ctl.release()
	check(not _lit_now("caution_hook") and _c3d._lamps["caution_hook_unlit"][0][0].visible, "%s: let go" % id)


## MASTER CAUTION pushed: the cautions but ELEC SYS acknowledged; CAUTION RESET acknowledges ELEC SYS: the lamp out.
## A new caution (the hook down) lights it again.
func _resets(tv: Node, id: String) -> void:
	tv.cockpit.indicators[0] = false
	_ctl.press(_r("master_reset"))
	_ctl.release()
	check(_lit_now("master_caution"), "%s: MASTER CAUTION pushed, ELEC SYS keeps it" % id)
	_ctl.press(_r("CAUTION_RESET"))
	_ctl.release()
	check(not _lit_now("master_caution"), "%s: CAUTION RESET, MASTER CAUTION out" % id)
	check(_lit_now("caution_elec_sys"), "%s: ELEC SYS stays lit" % id)
	_ctl.put(_r("SW_HOOK"), 1.0)
	check(_lit_now("caution_hook") and _lit_now("master_caution"), "%s: HOOK down: its caution, MASTER CAUTION" % id)
	_ctl.press(_r("master_reset"))
	_ctl.release()
	check(not _lit_now("master_caution") and _lit_now("caution_hook"), "%s: pushed, HOOK stays lit" % id)
	_ctl.put(_r("SW_HOOK"), 0.0)
	check(not _lit_now("caution_hook"), "%s: HOOK up, dark" % id)


## Each lamp a switch lights, on and off.
func _switches(_tv: Node, id: String) -> void:
	for t in [
		["FIRE_OHEAT_DETECT", 1.0, ["eng_fire", "caution_overheat"]],
		["SW_DBU", 1.0, ["dbu_on"]],
		["AVTR_TEST", 1.0, ["avtr"]],
		["SW_FLCS_BIT", 1.0, ["flcs_bit_run"]],
	]:
		var r := _r(t[0])
		var was: float = _ctl.value(r)
		_ctl.put(r, t[1])
		for k in t[2]:
			check(_lit_now(k), "%s: %s lights %s" % [id, t[0], k])
		_ctl.put(r, was)
		for k in t[2]:
			check(not _lit_now(k), "%s: %s back, %s dark" % [id, t[0], k])
	_ctl.press(_r("SW_FLCS_TEST"))
	check(_lit_now("flcs_pwr"), "%s: FLCS PWR TEST held lights FLCS PWR" % id)
	_ctl.release()
	check(not _lit_now("flcs_pwr"), "%s: let go, FLCS PWR dark" % id)
	# PROBE HEAT at TEST: the caution flashes.
	_ctl.put(_r("SW_PROBE_HEAT"), -1.0)
	var seen := {}
	for i in 40:
		seen[_lit_now("caution_probe_heat")] = true
		OS.delay_msec(10)
	check(seen.has(true) and seen.has(false), "%s: PROBE HEAT at TEST flashes its caution" % id)
	_ctl.put(_r("SW_PROBE_HEAT"), 0.0)
	# The threat warning prime panel's UNKNOWN: dark without the UFC's power (on at the start's end, _start).
	_ctl.put(_r("unk"), 1.0)
	await frames(3)
	check(not _lit_now("twd_unk"), "%s: UNKNOWN dark on the battery" % id)
	_ctl.put(_r("unk"), 0.0)
	await frames(3)


## Each lamp of a state the game keeps: the ECM pod jamming, the fuel low, the cabin altitude, the damage classes.
func _states(tv: Node, id: String) -> void:
	var c: Control = tv.cockpit
	c.indicators[6] = true
	check(_lit_now("ecm_enbl") and not _c3d._lamps["ecm_enbl_unlit"][0][0].visible, "%s: ECM ENBL lit" % id)
	c.indicators[6] = false
	check(not _lit_now("ecm_enbl") and _c3d._lamps["ecm_enbl_unlit"][0][0].visible, "%s: ECM ENBL dark" % id)
	var fuel: float = c.state.fuel_lbs
	c.state.fuel_lbs = 600.0
	check(_lit_now("caution_fwd_fuel_low") and not _lit_now("caution_aft_fuel_low"), "%s: 600 lb, FWD FUEL LOW" % id)
	c.state.fuel_lbs = 400.0
	check(_lit_now("caution_aft_fuel_low"), "%s: 400 lb, AFT FUEL LOW too" % id)
	c.state.fuel_lbs = fuel
	c.state["cabin_alt_ft"] = 30000.0
	check(_lit_now("caution_cabin_press"), "%s: the cabin at 30,000 ft, CABIN PRESS" % id)
	c.state["cabin_alt_ft"] = 0.0
	var flags: Array = c.damage_flags
	c.damage_flags = []
	c.damage_flags.resize(25)
	c.damage_flags.fill(false)
	c.damage_flags[2] = true
	check(_lit_now("caution_engine_fault") and not _lit_now("caution_avionics"), "%s: ENGINE FAULT" % id)
	c.damage_flags[2] = false
	c.damage_flags[15] = true
	check(_lit_now("caution_avionics") and not _lit_now("caution_engine_fault"), "%s: AVIONICS" % id)
	c.damage_flags[15] = false
	c.damage_flags[1] = true
	check(_lit_now("caution_ecm"), "%s: ECM failed, its caution" % id)
	c.damage_flags = flags
	tv.aircraft.canopy_open = 0.0
	check(not _lit_now("canopy"), "%s: the canopy shut, CANOPY dark" % id)
	tv.aircraft.canopy_open = 1.0


## The start: JFS RUN lit past the JFS's spool-up, ACFT BATT TO FLCS below 44 %; at idle on the generators every
## start-up lamp dark; EQUIP HOT with AIR SOURCE at OFF.
func _start(tv: Node, id: String) -> void:
	Engine.time_scale = 8.0
	_ctl.put(_r("JFS"), 1.0)  # the JFS
	var seen := {}
	var t := 0
	while float(tv.flight.state().rpm) < 0.2 and t < 3000:
		seen["jfs_run"] = seen.get("jfs_run", false) or _lit_now("jfs_run")
		seen["to_flcs"] = seen.get("to_flcs", false) or _lit_now("to_flcs")
		await process_frame
		t += 1
	check(seen.get("jfs_run", false) and seen.get("to_flcs", false), "%s: JFS RUN and BATT TO FLCS lit %s" % [id, seen])
	check(not _lit_now("flcs_pmg"), "%s: the JFS turning, FLCS PMG dark" % id)
	tv._command([5, 0, 0])  # the throttle to idle
	t = 0
	while (tv.cockpit.power < 2 or String(tv.cockpit.state.start_phase) != "running") and t < 6000:
		await process_frame
		t += 1
	Engine.time_scale = 1.0
	await frames(3)
	tv.aircraft.canopy_open = 0.0
	var still: Array = ON_BATTERY.filter(func(k): return k != "master_caution" and _lit_now(k))
	check(still.is_empty(), "%s: running on the generators, the start-up's lamps dark (lit: %s)" % [id, still])
	check(not _lit_now("jfs_run") and not _lit_now("to_flcs"), "%s: JFS RUN, BATT TO FLCS out" % id)
	tv._command([219, 1, tv.addon.SYSTEMS.find("ufc")])  # AVIONIC POWER UFC on, then its 3 s warm-up
	for i in 600:
		if tv.cockpit.up("ufc"):
			break
		await process_frame
	check(tv.cockpit.up("ufc"), "%s: the UFC up" % id)
	_ctl.put(_r("unk"), 1.0)
	await frames(3)
	check(_lit_now("twd_unk"), "%s: UNKNOWN lit on the UFC's power" % id)
	_ctl.put(_r("unk"), 0.0)
	await frames(3)
	check(not _lit_now("twd_unk"), "%s: UNKNOWN dark" % id)
	var air := _r("AirSource_knob")
	_ctl.put(air, 0.0)
	check(_lit_now("caution_equip_hot"), "%s: AIR SOURCE OFF, EQUIP HOT" % id)
	_ctl.put(air, 1.0)
	check(not _lit_now("caution_equip_hot"), "%s: AIR SOURCE NORM, EQUIP HOT dark" % id)
	_faults(tv, id, air)


## On the generators: the lamps whose cause is damage or the unpressurised cabin (manuals.md §7, group B).
func _faults(tv: Node, id: String, air: Dictionary) -> void:
	var c: Control = tv.cockpit
	var st: Dictionary = c.state.duplicate()
	c.state["alt_ft"] = 30000.0
	c.state["cabin_alt_ft"] = 13000.0
	check(not _lit_now("caution_cabin_press"), "%s: 30,000 ft at NORM, CABIN PRESS dark" % id)
	for pos in [0.0, 2.0, 3.0]:
		_ctl.put(air, pos)
		var gauge: float = _c3d._prop("f16/cockpit/pressure-ft")
		check(_lit_now("caution_cabin_press") and gauge == 30000.0, "%s: AIR SOURCE at %d, CABIN PRESS" % [id, pos])
	_ctl.put(air, 1.0)
	c.state = st
	var flags: Array = c.damage_flags
	var lit := func(flag: int, keys: Array) -> bool:
		c.damage_flags = []
		c.damage_flags.resize(25)
		c.damage_flags.fill(false)
		var before: bool = keys.any(_lit_now)
		c.damage_flags[flag] = true
		return not before and keys.all(_lit_now)
	check(lit.call(19, ["main_gen", "caution_elec_sys"]) and not _lit_now("stby_gen"), "%s: damage 19, MAIN GEN" % id)
	check(lit.call(21, ["main_gen", "stby_gen", "caution_elec_sys"]), "%s: damage 21, both generators' lamps" % id)
	check(lit.call(18, ["caution_flt_cont_sys"]), "%s: hydraulics damage, FLCS FAULT" % id)
	check(lit.call(24, ["caution_flt_cont_sys"]), "%s: total flight control damage, FLCS FAULT" % id)
	check(lit.call(11, ["caution_adc", "caution_c_adc"]), "%s: air data damage, ADC and CADC" % id)
	var bits: Array = c.mfds.filter(func(m): return m.get("real_fmt") != null)
	for m in bits:
		m.real_fmt.bit_t = m.real_fmt._clock() - 60.0  # the FLCS format's BIT, run to its end
	check(not bits.is_empty() and lit.call(24, ["flcs_bit_fail"]), "%s: the BIT failed, FLCS BIT FAIL" % id)
	for m in bits:
		m.real_fmt.bit_t = -1.0
	c.damage_flags = flags
