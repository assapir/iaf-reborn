# Extras "Bomb release" (docs/weapons.md §9.10): 6 MK-82 singles on stations 1-3 / 5-7, ripple quantity 2, Space
# held per press in mission 231 (frozen flight model, scripted sim time). Original: one store per tick in
# FUN_0053b680's order 1, 7, 2, 6, 3, 5. Real PAIRS: (1, 7), (2, 6), (3, 5), each pair in one step and the lateral
# moment ~0 after it. Real SGL: 1, 7, 2, 6, 3, 5 alternating wings.
extends "res://../tests/godot/base.gd"

const HP := [0, 0, 15, 1, 15, 1, 15, 1, 0, 0, 15, 1, 15, 1, 15, 1, 0, 0]


## The release events of every store: [[stations that dropped in one step], ...] and the moment after each.
func releases(mode: String, pairs: bool) -> Dictionary:
	settings().bomb_release = mode
	var MR = load("res://mission/mission_runtime.gd")
	var bdb: Dictionary = MR.load_bdb(MR.mission_files(231)[0].data)
	var f16: Dictionary = MR.bdb_objects(bdb)[1]
	var desc: Dictionary = load("res://aircraft/aircraft_model.gd").load_descriptor("f16")
	var tv = await start_mission(231)
	await frames(5)
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	var w = load("res://weapons/player_weapons.gd").new()
	tv.add_child(w)
	w.setup(tv, {"armament": {"hardpoints": HP}}, f16, bdb, desc)
	w.release_pairs = pairs
	var vel := Vector3(0, 0, -200)
	var tanks: Array = tv.runtime.entities.values().filter(func(e): return String(e.name).begins_with("t55"))
	start_over(tv, w, tv.runtime._world_of(tanks[0]) + Vector3(0, -3000, 0), vel, "F-16")
	w.stores.cur = 1
	w._master_from_type(false)
	var events := []
	var moments := []
	var t := 0.0
	var counts := func(): return range(9).map(func(i): return w.stores.displayed(i))
	for press in 6:
		w.update(t)
		w.fire_selected()
		for k in 60:
			var before: Array = counts.call()
			t = fly_step(tv, w, vel, t, 0.02)
			var after: Array = counts.call()
			var gone := range(9).filter(func(i): return after[i] < before[i])
			if not gone.is_empty():
				events.append(gone)
				moments.append(w.stores.roll_moment)
		w.release_selected()
		for k in 10:
			t = fly_step(tv, w, vel, t, 0.05)
		if range(9).all(func(i): return w.stores.displayed(i) == 0):
			break
	print("%s pairs=%s: %s, moments %s" % [mode, pairs, events, moments])
	tv.queue_free()
	await frames(2)
	return {"events": events, "moments": moments}


func run() -> void:
	await require_data()
	var o: Dictionary = await releases("original", true)
	check(o.events == [[1], [7], [2], [6], [3], [5]], "Original: one store per tick, 1 7 2 6 3 5 (%s)" % [o.events])
	var r: Dictionary = await releases("real", true)
	check(r.events == [[1, 7], [2, 6], [3, 5]], "Real PAIRS: each symmetric pair in one step (%s)" % [r.events])
	# ~0: the model's attach points are mirrored to about 1 cm (4 kg·m against one MK-82's ~950 kg·m).
	check(
		r.moments.all(func(m): return absf(m) < 0.02 * absf(o.moments[0])),
		"Real PAIRS: the moment ~0 after every pair %s" % [r.moments]
	)
	var s: Dictionary = await releases("real", false)
	check(s.events == [[1], [7], [2], [6], [3], [5]], "Real SGL: alternating wings (%s)" % [s.events])
	settings().bomb_release = "original"
