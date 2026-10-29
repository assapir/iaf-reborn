# Dev probe (not run by tools/test.sh): (A) the release order of 6 MK-82s, one per station on stations 1-3 and 5-7
# (3 per wing), in ripple pairs (quantity 2), the first press on station 1 (set here, as the AG cycle does); (B) with
# Better physics "Asymmetric stores", the F-16's roll with a right-heavy moment and after the moment returns to 0 (the
# load balanced again), stick centred, autopilot off. Rust test: aircraft.rs balanced_stores_stop_the_roll.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/_drop_balance_probe.gd
extends "res://../tests/godot/base.gd"


func bank(tv: Node) -> float:
	return rad_to_deg(asin(clampf(-float(tv.flight.state().right.y), -1.0, 1.0)))


func run() -> void:
	await require_data()
	# --- A: release order -------------------------------------------------------------------
	var MR = load("res://mission/mission_runtime.gd")
	var bdb: Dictionary = MR.load_bdb(MR.mission_files(231)[0].data)
	var f16: Dictionary = MR.bdb_objects(bdb)[1]
	var desc: Dictionary = load("res://aircraft/aircraft_model.gd").load_descriptor("f16")
	var tv = await start_mission(231)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	var hp := [0, 0, 15, 1, 15, 1, 15, 1, 0, 0, 15, 1, 15, 1, 15, 1, 0, 0]
	var w = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w)
	w.setup(tv, {"armament": {"hardpoints": hp}}, f16, bdb, desc)
	var vel := Vector3(0, 0, -200)
	var tanks: Array = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("t55"))
	start_over(tv, w, tv.runtime._world_of(tanks[0]) + Vector3(0, -3000, 0), vel, "F-16")
	print("stations with MK-82: %s" % [range(10).filter(func(i): return w.stores.displayed(i) > 0)])
	w.stores.cur = range(10).filter(func(i): return w.stores.displayed(i) > 0)[0]
	w._master_from_type(false)
	print(
		"ripple quantity %d, period %.2f s; first selected station %d" % [w.ripple_qty, w.ripple_period, w.stores.cur]
	)
	var t := 0.0
	var order := []
	for pair in 3:
		w.update(t)
		var n0: int = w.bombs.size()
		w.fire_selected()
		var t_first := -1.0
		for k in 40:
			t = fly_step(tv, w, vel, t, 0.05)
			if w.bombs.size() > n0 and t_first < 0.0:
				t_first = t
			if w.bombs.size() >= n0 + 2:
				break
		w.release_selected()
		var got: Array = []
		for i in range(10):
			got.append(w.stores.displayed(i))
		order.append({"left": got, "moment": w.stores.roll_moment, "dt": t - t_first})
		print(
			(
				"pair %d: counts per station %s, last fired %d, moment %.0f kg·m, %.2f s between the two bombs"
				% [pair + 1, got, w.stores.last_fired, w.stores.roll_moment, t - t_first]
			)
		)
		for k in 20:
			t = fly_step(tv, w, vel, t, 0.05)
	check(absf(order[2].moment) < 1.0, "all six away, the moment is 0")
	# --- B: roll before / after the load balances --------------------------------------------
	settings().better["asymmetric_stores"] = true
	settings().player_flight = 0
	tv = await start_mission(324)
	tv.autopilot._engage(0)
	await fly(tv, 1.0)
	var t0: float = tv._sim_time
	var log := []
	tv.flight.set_stores_moment(907.0 * 3.0)
	var balanced_at := -1.0
	while tv._sim_time - t0 < 6.0:
		await process_frame
		var s: float = tv._sim_time - t0
		if s >= 3.0 and balanced_at < 0.0:
			tv.flight.set_stores_moment(0.0)
			balanced_at = s
		log.append([s, bank(tv)])
	var rate := func(a: float, b: float) -> float:
		var pa: Array = log.filter(func(r): return r[0] >= a)[0]
		var pb: Array = log.filter(func(r): return r[0] >= b)[0]
		return (pb[1] - pa[1]) / (pb[0] - pa[0])
	for win in [[1.0, 2.0], [2.0, 3.0], [3.0, 3.1], [3.1, 3.5], [3.5, 4.0], [4.0, 5.0], [5.0, 6.0]]:
		print("  %.1f-%.1f s: roll rate %+.1f °/s" % [win[0], win[1], rate.call(win[0], win[1])])
	print("  bank at 3.0 s %.1f°, at 6.0 s %.1f°" % [log.filter(func(r): return r[0] >= 3.0)[0][1], log[-1][1]])
	check(absf(rate.call(4.0, 6.0)) < 1.0, "balanced: the roll has stopped (%.2f °/s)" % rate.call(4.0, 6.0))
	check(
		absf(rate.call(3.0, 3.5)) < 2.0,
		"balanced: it stops at once (%.2f °/s in the first 0.5 s)" % rate.call(3.0, 3.5)
	)
