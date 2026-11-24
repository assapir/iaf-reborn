# The F-16s' up-front controls (the Sufa's, then the Barak's: base.gd sim_f16s), HUD control panel and DGFT switch
# (avionics-plan.md §6 slice 5; modern-iaf/docs/ufc.md) on the weapons range, headless: each jet's range mission as the
# front end's Fly sets it up.
# - cold on the ramp: the DED is dark without the UFC's power;
# - airborne 15 NM south of the home base: the ICP keys (Ctrl + digits, Alt + Return …) call the pages; CNI, STPT, T-ILS
#   (TACAN to the home base's station, tuned at the start, the EHSI's TCN), ALOW (the HUD's AL and the GAAF voice's
#   height), BINGO (the HUD's FUEL), a steerpoint's elevation typed in, a markpoint over the jet steered to (the HUD's
#   steerpoint 26), COM1's preset, the backup UHF;
# - the INS: off then STOR HDG, the HUD's ALIGN and no steerpoint until it can navigate;
# - the HUD control panel: VV/VAH, FPM, GND SPD, DED DATA; MASTER ARM at SIMULATE (SIM, nothing fires); DGFT (V) and
#   MSL OVRD (Shift + V): the radar's ACM / CRM, the HUD's DGFT, back as before.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_ded.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var c


func _key(k: Key, mods := "") -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = "ctrl" in mods
		e.alt_pressed = "alt" in mods
		e.shift_pressed = "shift" in mods
		e.pressed = down
		tv._unhandled_input(e)


## The DCS RTN key: Alt + Home, on the laptop map (macOS's default) Ctrl + ,.
func _rtn() -> void:
	if settings().laptop_keys:
		_key(KEY_COMMA, "ctrl")
	else:
		_key(KEY_HOME, "alt")


## ICP keys by their numbers (IafUfc.press), through command 250.
func icp(keys: Array) -> void:
	for k in keys:
		tv._press([250, k, 0])
	await frames(1)


func ded() -> Array:
	return Array(c.ded_lines())


func hud_texts() -> Array:
	c.hud._real_frame = -1
	var r: Dictionary = c.hud.real_hud()
	return r.get("outer", []).filter(func(p): return p.k == "text").map(func(p): return String(p.text))


func run() -> void:
	await require_data()
	for unit in sim_f16s():
		print("-- %s" % unit)
		await _jet(unit, sim_f16s()[unit])


func _jet(_unit: String, base: String) -> void:
	var s := settings()
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-ded", false).get_current_dir()
	tv.addon.result = {"pass": true}
	c = tv.cockpit
	check(c.ufc != null, "the Sufa has the up-front controls (IafUfc)")
	if c.ufc == null:
		return
	await frames(2)
	check(c.up("ufc") or ded().is_empty(), "cold: the DED dark without the UFC's power (%s)" % [ded()])
	# Airborne 15 NM south of the home base's station (the parking spot) at 10,000 ft, heading north.
	var home: Vector2 = Vector2(c.ufc_nav().e, c.ufc_nav().n)
	var stn = ClassDB.class_call_static("IafUfc", "geo", home.x, home.y)
	var at: Vector3 = tv.world_to_scene(Vector3(home.x, home.y - 15.0 * 1852.0, 3048.0))
	tv.rig.position = at
	tv.flight.start(s.own_dir(), tv.player.fm_section, at, Vector3(0, 0, 0), Vector3(0, 0, -200), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85
	await fly(tv, 1.0)
	check(c.up("ufc"), "airborne: the UFC powered")
	await _pages(stn, base.replace("_", " ").to_upper())
	await _ins()
	await _panel()
	await _dgft()


func _pages(stn, home: String) -> void:
	# CNI: the steerpoint and the time.
	_rtn()
	await frames(1)
	var l := ded()
	check(l.size() == 5 and l[0].begins_with("UHF") and "STPT" in l[0], "CNI: UHF, STPT (%s)" % [l])
	# Ctrl + 1: T-ILS, the home base's TACAN (Ramon 75X, Ramat David 99X: tuned at the start) about 15 NM away; the EHSI's
	# TCN.
	_key(KEY_1, "ctrl")
	await frames(1)
	l = ded()
	check(l[0].begins_with("TCN T/R") and home in l[4], "T-ILS: TCN T/R, %s (%s, the jet near %s)" % [home, l, stn])
	var t: Dictionary = c.ufc.tacan(c.ufc_nav())
	var nm := float(t.get("range_m", 0.0)) / 1852.0
	check(t.get("name", "") == home and nm > 13.0 and nm < 17.0, "TACAN range %.1f NM" % nm)
	check(absf(wrapf(float(t.get("bearing", 0.0)), -180.0, 180.0)) < 3.0, "TACAN bearing north (%s)" % t)
	_key(KEY_N, "alt")
	await frames(2)
	check(c.ehsi_tcn, "Alt + N: the EHSI's TCN")
	_key(KEY_N, "alt")
	# ALOW 500 ft: the HUD's AL and the voice's height.
	await icp([18, 2, 5, 0, 0, 10])
	check(float(c.ufc.state().alow_ft) == 500.0, "ALOW 500 (%s)" % [ded()])
	await frames(2)
	check(float(c.state.get("alow_ft", 0.0)) == 500.0, "the cockpit state's ALOW for the GAAF voice")
	# BINGO above the fuel: the HUD's FUEL (flashing: one of two frames' times).
	await icp([18, 12, 2, 4, 0, 0, 0, 0, 10])
	check(s_bingo() == 40000, "LIST 2: BINGO 40000 (%d)" % s_bingo())
	var seen := false
	for i in 30:
		await frames(1)
		seen = seen or hud_texts().has("FUEL")
	check(seen, "the HUD's FUEL below the bingo")
	settings().bingo_lbs = 1500
	# STPT: steerpoint 1's elevation typed in.
	await icp([18, 4, 17, 17, 17, 1, 2, 3, 4, 10])
	check(int(c.waypoints[0].get("elev_ft", -1)) == 1234, "STPT 1's ELEV 1234 (%s)" % [ded()])
	# MARK: OFLY over the jet, steerpoint 26; then STPT 26 steered to, the HUD's steerpoint 26.
	_rtn()  # RTN first: on a page with a data field the digits are data
	_key(KEY_7, "ctrl")
	_key(KEY_ENTER, "alt")
	await frames(1)
	check(c.marks.size() == 1 and int(c.marks[0].number) == 26, "MARK: markpoint 26 (%s)" % [c.marks])
	await icp([18, 4, 2, 6, 10])
	check(c.steer_mark == 0 and c.steer_index() == c.waypoints.size(), "STPT 26 selected")
	hud_texts()
	var steer: Dictionary = c.hud._real_in.get("steerpoint", {})
	check(int(steer.get("number", 0)) == 26 and float(steer.dist_m) < 500.0, "the HUD steers to 26 (%s)" % steer)
	await icp([18, 4, 1, 10])
	check(c.steer_mark == -1 and c.current_waypoint == 0, "back to STPT 1")
	# COM1: preset 5; the backup panel's channel.
	_key(KEY_BRACKETLEFT, "alt")
	await icp([5, 10])
	check(int(c.ufc.state().uhf_khz) == 340200, "COM1 preset 5: 340.20 (%s)" % [ded()])
	_key(KEY_U, "alt")
	await icp([18])
	check(ded()[0].begins_with("UHF  BACKUP"), "Alt + U: the UHF on the backup panel (%s)" % [ded()])


func s_bingo() -> int:
	return int(settings().bingo_lbs)


func _ins() -> void:
	# The INS knob to OFF and back to STOR HDG: aligning, the HUD's ALIGN and no steerpoint.
	# (the checklist's own path, command 214, holds still once the lesson has a result; the knob is turned directly)
	for i in 3:
		tv.flight.start_switch("ins", -1)
	tv.flight.start_switch("ins", 1)
	await frames(3)
	var ins: Array = c.state.get("ins", [])
	check(ins.size() == 4 and int(ins[0]) == 1 and not bool(ins[3]), "STOR HDG, aligning (%s)" % [ins])
	check(hud_texts().has("ALIGN"), "the HUD's ALIGN")
	check(c.hud._real_in.get("steerpoint", {}).is_empty(), "no steerpoint until the INS navigates")
	await icp([18, 12, 6])
	check(ded()[0].begins_with("INS"), "LIST 6: the INS page (%s)" % [ded()])
	# Back to NAV aligned: Ctrl + E's start flies the whole checklist (the INS aligned at NAV).
	var p: Vector3 = tv.rig.position
	tv.flight.start(settings().own_dir(), tv.player.fm_section, p, Vector3.ZERO, Vector3(0, 0, -200), airborne_flags())
	await fly(tv, 0.5)
	hud_texts()
	check(not c.hud._real_in.get("steerpoint", {}).is_empty(), "navigating again: the steerpoint back")


func _panel() -> void:
	tv._press([252, 0, 0])  # SCALES VV/VAH
	check(hud_texts().has("-1"), "VV/VAH: the vertical velocity scale (%s)" % [hud_texts()])
	tv._press([252, 0, 1])
	tv._press([252, 2, 2])  # VELOCITY GND SPD
	check(hud_texts().has("G"), "GND SPD: the G mnemonic")
	tv._press([252, 2, 0])
	_key(KEY_D, "alt")  # DED DATA: the DED's lines on the HUD
	var l := ded()
	# A character per cell (real_hud/f16.rs ded_block): the cells in order spell the line.
	var cells := "".join(hud_texts().filter(func(t): return t.length() == 1))
	check(l[0].replace(" ", "") in cells, "DED DATA: the DED's first line on the HUD (%s)" % l[0])
	tv._press([252, 4, 2])
	# MASTER ARM at SIMULATE: SIM on the HUD, nothing fires.
	var c3d = tv.get("cockpit_3d")
	check(c3d != null and c3d.clickable != null, "the 3D cockpit's controls")
	if c3d == null or c3d.clickable == null:
		return
	c3d.clickable._system_put("master_arm", -1.0, 0.0)
	check(tv.weapons.master_sim and not tv.weapons.master_arm, "MASTER ARM down: SIMULATE")
	await frames(2)
	check(hud_texts().has("SIM"), "SIMULATE: the HUD's SIM")
	# An ICP button of the model: its row's system presses the key (ICP 4: STPT).
	c3d.clickable._system_put("icp_4", 1.0, 0.0)
	check(String(c.ufc.state().page) == "STPT", "the 3D ICP's 4: STPT")
	var rounds: int = tv.weapons.stores.displayed(9)
	tv.weapons.gun_trigger()
	await frames(2)
	tv.weapons.firing = false
	check(tv.weapons.stores.displayed(9) == rounds, "SIMULATE: the gun does not fire")
	tv.weapons.master_sim = false


func _dgft() -> void:
	var w = tv.weapons
	var mode0: int = int(w.radar.mode)
	_key(KEY_V)
	await frames(2)
	check(w.override == 1 and int(w.radar.mode) == 6, "V: DGFT, the radar's ACM (%d, %d)" % [w.override, w.radar.mode])
	# The range's load has no A-A missile: DGFT gives the gun's EEGS (mode 3), else the SRM (1).
	check(w.hud_mode in [1, 3] and hud_texts().has("DGFT"), "DGFT: the SRM / gun and the HUD's DGFT (%d)" % w.hud_mode)
	_key(KEY_V, "shift")
	await frames(2)
	check(w.override == 2 and int(w.radar.mode) == 4 and hud_texts().has("MSL"), "Shift + V: MSL OVRD, CRM")
	_key(KEY_V, "shift")
	await frames(2)
	check(w.override == 0 and int(w.radar.mode) == mode0, "centred: the radar back (%d)" % w.radar.mode)
