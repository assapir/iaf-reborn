# The player's autopilot switch and the master arm as single states (the statemachines audit #19, #23; Rust
# crates/iaf-flight/src/player_ap.rs and iaf-avionics master::MasterArm), in mission 312's air start:
#   - autopilot damage in NAV puts the lamp out and stops the loop but keeps the mode, so the throttle keys stay
#     dropped (the exe's ctl+0x974 == 2 gate) and the stick reaches the jet;
#   - NAV on an empty route: the lamp lit, no loop (as the exe);
#   - the master arm's three positions: SIMULATE is never armed, the key arms from it, OFF and ARM by the fields.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_switch_states.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(312)
	await frames(3)
	var ap = tv.autopilot
	check(ap.mode == 1 and tv.cockpit.indicators[8], "air start: AP LVL, lamp lit")
	ap.key()
	check(
		ap.mode == 2 and tv.cockpit.indicators[8] and String(tv.flight.ap_stage()) != "none", "A: NAV, the loop flies"
	)
	tv.damage_autopilot()
	check(
		ap.mode == 2 and not tv.cockpit.indicators[8] and String(tv.flight.ap_stage()) == "none",
		"damage: the lamp out, the loop stopped, the mode kept (%s)" % tv.flight.ap_stage()
	)
	check(not ap.throttle_allowed(), "damaged NAV still drops the throttle keys")
	check(ap.stick_event(Vector2(1.0, 0.0)) and ap.mode == 2, "the lamp out: the stick passes, the mode stays")
	ap._engage(0)
	tv.flight.ap_set_route(PackedFloat64Array())
	ap._engage(2)
	check(
		ap.mode == 2 and tv.cockpit.indicators[8] and String(tv.flight.ap_stage()) == "none",
		"NAV on an empty route: the lamp lit, no loop"
	)
	ap._engage(0)
	# The master arm: the original game's jets stay armed.
	var w = tv.weapons
	check(w.master_arm and not w.master_sim, "the 1998 game starts armed")
	w.master_sim = true
	check(w.master_sim and not w.master_arm, "SIMULATE is safe")
	tv._press([202, 0, 0])
	check(w.master_arm and not w.master_sim, "the master arm key arms from SIMULATE")
	w.master_arm = false
	check(not w.master_arm and not w.master_sim, "safe: OFF")
	w.master_sim = false
	check(not w.master_arm and not w.master_sim, "off SIMULATE at OFF: OFF")
	w.master_arm = true
	check(w.master_arm and not w.master_sim, "ARM")
