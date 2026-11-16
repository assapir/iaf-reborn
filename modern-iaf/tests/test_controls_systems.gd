# The 3D cockpit's controls of the systems the game has (finish list C2; modern-iaf/docs/cockpit.md "Every control"):
# in each F-16's cold start-up flight each control with a `system` (f16_controls.json) works its system, and the
# system's own key moves the control: MASTER ARM, STORES CONFIG, MPO (held), ALT FLAPS, the MFD BRT rockers, HMCS SYM
# INT, MAL & IND LTS (held), MASTER CAUTION, the ICP's A-A / A-G; then in the air EMER JETT. First the switches of
# three positions (C3): MAIN PWR, the JFS, RDR ALT.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_controls_systems.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup"}
const AA_TYPES := [570, 580, 600, 610]

var _ctl: Node
var _c3d: Node


func run() -> void:
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
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
		await _three(tv, id)
		tv._press([210, 1, 0])  # main power, for the lamps
		await frames(3)
		tv.addon.result = {"pass": true}  # the training's checks stop (sim_flight.gd _finish)
		await _ground(tv, id)
		await _air(tv, id)


func _r(node: String) -> Dictionary:
	return _ctl._controls.filter(func(e): return e[0].name == node)[0][1]


func _click(node: String) -> void:
	_ctl.press(_r(node))
	_ctl.release()


## The switch `node`'s position after a frame's sync.
func _shown(node: String) -> float:
	_c3d._process(0.0)
	return _ctl.value(_r(node))


## The switches of three positions (finish list C3; start.rs Start::position) through every position both ways, each
## the flight model's, and their keys shown: MAIN PWR OFF / BATT / MAIN PWR, the JFS START 1 / OFF / START 2, RDR ALT
## OFF / STBY / RDR ALT.
func _three(tv: Node, id: String) -> void:
	for e in [
		["MAIN_PWR", "main_power", [1, 2, 1, 0, 2]],
		["RDR_ALT", "rdr_alt", [1, 2, 1, 0]],
		["JFS", "starter", [-1, 0, 1, 0]]
	]:
		for p in e[2]:
			_ctl.put(_r(e[0]), float(p))
			await frames(1)
			check(
				tv.flight.start_position(e[1]) == p and _shown(e[0]) == float(p),
				"%s: %s at %d (the flight model's %d)" % [id, e[0], p, tv.flight.start_position(e[1])]
			)
	tv._press([210, 0, 0])  # the key: main power off and on
	await frames(1)
	check(_shown("MAIN_PWR") == 0.0, "%s: the main power key shows OFF" % id)
	tv._press([210, 0, 0])
	await frames(1)
	check(_shown("MAIN_PWR") == 2.0, "%s: and MAIN PWR" % id)


func _ground(tv: Node, id: String) -> void:
	var w = tv.weapons
	# MASTER ARM: safe at the start, OFF; a click to MASTER ARM arms; the key back to safe shows OFF; SIMULATE is safe.
	check(not w.master_arm and _shown("master-arm-switch") == 0.0, "%s: MASTER ARM at OFF, safe" % id)
	_click("master-arm-switch")
	check(w.master_arm and _shown("master-arm-switch") == 1.0, "%s: MASTER ARM arms" % id)
	tv._press([202, 0, 0])
	check(not w.master_arm and _shown("master-arm-switch") == 0.0, "%s: the master arm key shows OFF" % id)
	_ctl.put(_r("master-arm-switch"), -1.0)
	check(not w.master_arm and _shown("master-arm-switch") == -1.0, "%s: SIMULATE stays, safe" % id)
	# STORES CONFIG: CAT III and back by the key's flag.
	_click("SW_STORES_CONFIG")
	check(tv.cat3 and _shown("SW_STORES_CONFIG") == 1.0, "%s: STORES CONFIG CAT III" % id)
	tv.cat3 = false
	check(_shown("SW_STORES_CONFIG") == 0.0, "%s: Alt+S's CAT I shown" % id)
	# MPO: held, the override; let go, none; Alt+M held shows it.
	_ctl.press(_r("SW_MPO"))
	check(tv.mpo and _shown("SW_MPO") == 1.0, "%s: MPO held overrides" % id)
	_ctl.release()
	check(not tv.mpo and _shown("SW_MPO") == 0.0, "%s: MPO let go" % id)
	tv.mpo_on = true
	check(_shown("SW_MPO") == 1.0, "%s: Alt+M held shows MPO" % id)
	tv.mpo_on = false
	# ALT FLAPS: EXTEND lowers the flaps; the flaps key back up shows NORM.
	var f0: bool = float(tv.flaps) > 0.0
	_ctl.put(_r("SW_ALT_FLAPS_50"), 0.0 if f0 else 1.0)
	check((float(tv.flaps) > 0.0) != f0, "%s: ALT FLAPS moves the flaps" % id)
	tv._press([12, 0, 0])
	check(_shown("SW_ALT_FLAPS_50") == (1.0 if f0 else 0.0), "%s: the flaps key moves ALT FLAPS" % id)
	# MFD BRT: a step down on the left rocker dims both displays; the right one shows it.
	var b: float = settings().mfd_brightness
	_ctl._turn(_r("MFD1_MFDButtonBrightness"), -1.0)
	check(is_equal_approx(settings().mfd_brightness, maxf(b - 0.1, 0.1)), "%s: MFD BRT dims the displays" % id)
	check(is_equal_approx(_shown("MFD2_MFDButtonBrightness"), settings().mfd_brightness), "%s: both rockers" % id)
	settings().mfd_brightness = b
	# HMCS SYM INT: OFF takes the helmet display's power.
	_ctl.put(_r("HMCS_SYM_INT_KNOB"), 0.0)
	check(not tv.cockpit.helmet_power, "%s: HMCS SYM INT OFF, the helmet display dark" % id)
	_ctl.put(_r("HMCS_SYM_INT_KNOB"), 0.5)
	check(tv.cockpit.helmet_power, "%s: HMCS SYM INT on" % id)
	# MAL & IND LTS with main power (on since the start): every lamp lit while held.
	check(tv.cockpit.power >= 1, "%s: main power on" % id)
	_ctl.press(_r("MAL_IND_LTS"))
	_c3d._process(0.0)
	var lit: Array = _c3d.lamps_lit.values()
	check(not lit.is_empty() and lit.all(func(v): return v), "%s: MAL & IND LTS lights every lamp" % id)
	_ctl.release()
	_c3d._process(0.0)
	check(not _c3d.lamps_lit.values().all(func(v): return v), "%s: let go, the lamps as before" % id)
	# MASTER CAUTION: its push puts the lamp out.
	tv.cockpit.indicators[0] = true
	_click("master_reset")
	check(not tv.cockpit.indicators[0], "%s: MASTER CAUTION reset" % id)
	# The ICP's A-A / A-G select an air-to-air / an air-to-ground store.
	_click("a-a")
	check(int(w.stores.current_type()) in AA_TYPES, "%s: A-A selects an A-A missile" % id)
	_click("a-g")
	check(not int(w.stores.current_type()) in AA_TYPES, "%s: A-G selects an A-G store" % id)


## In the air (the jet restarted 1,500 m up, as test_sim_jettison): EMER JETT drops every store but the A-A missiles.
func _air(tv: Node, id: String) -> void:
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 1500.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	var vel: Vector3 = (st0.forward * Vector3(1, 0, 1)).normalized() * 200.0
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), vel, airborne_flags())
	tv.gear_down = false
	await frames(10)
	var w = tv.weapons
	var other := func() -> int:
		var n := 0
		for i in 9:
			if not int(w.stores.type_of(i)) in AA_TYPES:
				n += int(w.stores.displayed(i))
		return n
	var before: int = other.call()
	check(before > 0, "%s: stores other than A-A missiles to jettison (%d)" % [id, before])
	_click("EMER_JETT")
	await frames(3)
	check(other.call() < before, "%s: EMER JETT jettisons (%d -> %d)" % [id, before, other.call()])
