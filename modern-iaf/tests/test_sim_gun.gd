# The sim's gun (modern-iaf/docs/weapons.md): the Sufa's take-off mission headless.
# - The rounds are the unit record's 511 (the bdb's count, no per-type table) and run out: the gun stops at 0.
# - The flight starts with the master arm safe: the trigger fires nothing (even with the gear-down safety off) until
#   the Master arm key (Shift+A, command 202) arms it.
# - The own art: the muzzle flash's gunfire.tga and a tracer streak per round slot (converted/own).
# - The F-35I's gun record at the GAU-22/A's rate; the bomb fixes and the wind on falling stores on.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_gun.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


## The sim's own data (./modern-iaf-setup), not the original's install.
func _press(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func run() -> void:
	await require_data()
	var s := settings()
	var m: Dictionary = s.load_json(s.assets_dir().path_join("converted/modern-iaf/missions/ramon_takeoff.json"))
	load("res://flight/fly.gd").set_jet(m)
	s.mission_files_override = [{"name": "ramon_takeoff", "data": m}]
	var tv: Node = await start_mission(int(m.sim.menu_id))
	s.mission_files_override = []
	var w = tv.weapons
	var gun: Dictionary = w.stores.station(9)
	check(float(gun.get("initial", 0)) == 511.0, "Sufa gun: %s rounds (the unit record's)" % gun.get("initial"))
	check(not w.master_arm, "the flight starts with the master arm safe")
	# The F-35I (type 1000) fires the same record at its GAU-22/A's rate and speed (definition `gun`, jet_gun).
	var adir: Dictionary = load("res://shared/weapons/real_weapons.gd").jet_gun(gun.w, 1000)
	check(
		is_equal_approx(float(adir.rounds_per_tick), 11.0) and float(adir.motion._velocityJump) == 1040.0,
		"F-35I gun: %s rounds a tick (3,300 rpm: 180 rounds in 3.3 s)" % adir.rounds_per_tick
	)
	# Real behaviour on (sim_settings.gd): the bomb fixes, and the mission's wind on the falling stores.
	check(w.bomb_burst_fix and w.lock_threat_fix, "the sim fixes the bomb burst and the lock threat")
	tv.radio.wind = 20
	tv.apply_wind()
	var bw: float = tv.Bombs.wind.length() * 3600.0 / 1852.0
	check(is_equal_approx(bw, 0.0 if s.no_wind else 20.0), "a 20 kt wind drifts the bombs (%.1f kt)" % bw)
	w.safety_off = true  # past the gear-down rule: only the master arm holds the gun
	_press(tv, KEY_TAB)
	await frames(10)
	_press(tv, KEY_TAB, false)
	check(w.stores.displayed(9) == 511 and not w.firing, "safe: the trigger fires nothing (%d)" % w.stores.displayed(9))
	_press(tv, KEY_A, true, true)
	check(w.master_arm, "Shift+A arms the master arm")
	check(w._round_nodes.size() > 0 and w._round_nodes[0].has_meta("tracer"), "a tracer per round slot")
	var flash: Texture2D = w._flash.get_child(0).material_override.albedo_texture if w._flash != null else null
	check(flash is ImageTexture, "the muzzle flash draws the own gunfire.tga")
	_press(tv, KEY_TAB)
	var t0: float = tv._sim_time
	var shown := false
	while w.firing and tv._sim_time - t0 < 15.0:
		shown = shown or w._round_nodes.any(func(n): return n.visible)
		await process_frame
	_press(tv, KEY_TAB, false)
	var took: float = tv._sim_time - t0
	check(shown, "the tracers fly")
	check(
		w.stores.displayed(9) == 0 and not w.firing and took > 4.5 and took < 6.0,
		"511 rounds empty the gun in %.1f s (6000 rpm: 5.1 s)" % took
	)
	_press(tv, KEY_TAB)
	await frames(5)
	check(not w.firing and w.stores.displayed(9) == 0, "empty: the trigger fires nothing")
