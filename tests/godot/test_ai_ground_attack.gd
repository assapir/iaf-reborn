# AI air-to-ground (docs/ai.md §13): mission 221's second-wave Su-24 lead ('AG LEAD') within 10 km of its primary
# target changes to its bombs (380) and dive-bombs (290 → DiveBomb, mode 0x17): approach, dive, the release at the
# vacuum impact (440440) starts the AI ripple (380's quantity 2: two MK-83s, 0.1 s apart) that bursts near the
# target. Its stores weigh on its flight model and leave the pylons with the release. The Su-24 is restarted 15 km from the target,
# 4500 m above it (the dive starts from above 3048 m: docs/ai.md §13.3); the AI runs at 8× time, the player's jet holds still.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(3)
	tv.fm_stopped = true
	var rt = tv.runtime
	var su: Dictionary = {}
	var tgt: Dictionary = {}
	for e in rt.entities.values():
		if e.name == "Su24_1_2nd_wave":
			su = e
		elif e.name == "sesitive target":
			tgt = e
	var p = su.pilot
	check(is_same(p.brain.primary, tgt), "the Su-24's primary target is the 'sesitive target'")
	var tp: Vector3 = rt._world_of(tgt)
	su.world = tp + Vector3(15000, 0, 0)
	su.world.z = tp.z + 4500.0
	su.heading = 270.0
	tv.ai._start(p, Settings().assets_dir().path_join("install"), p.plane)
	su.shield = true  # the player's side fights back (its AI wingman shot the Su-24 down in a trial run)
	var u = tv.ai.combat.units[su.key]
	var loaded := func() -> int:
		var n := 0
		for i in 9:
			n += int(u.stores.station(i).get("count", 0))
		return n
	var loaded0: int = loaded.call()
	var mass0: float = u.stores.fm_mass
	check(loaded0 > 0 and mass0 > 0.0 and u.store_nodes.is_empty(),
		"the Su-24's stores (%d) weigh on its FM (%.0f lb); no models: its model has no Station helpers" % [loaded0, mass0])
	var w = tv.weapons
	var dropped := false
	var drops := []
	var near := INF
	var modes := {}
	var t0: float = rt.now
	Engine.time_scale = 8.0
	while rt.now - t0 < 120.0:
		await process_frame
		modes[p.mode] = true
		for bm in w.bombs:
			if is_same(bm.get("owner"), su):
				dropped = true
				if not drops.any(func(x): return is_same(x, bm)):
					drops.append(bm)
				var bp: Vector3 = load("res://weapons/bombs.gd").position(bm.b, w.now)
				near = minf(near, Vector2(bp.x - tp.x, bp.y - tp.y).length())
	Engine.time_scale = 1.0
	print("Su-24 modes ", modes.keys(), " station ", u.cur, " ", u.w.get("name", ""), " stage ", p.flight.ap_stage() if p.flight.has_method("ap_stage") else "")
	check(modes.has(0x17), "the Su-24 dive-bombs (mode 0x17)")
	check(dropped, "a bomb released")
	check(near < 600.0, "the bomb falls near the target (%.0f m)" % near)
	check(u.ripple.qty() == 2 and is_equal_approx(u.ripple.period(), 0.1) and drops.size() == 2,
		"the ripple: 380's quantity 2 every 0.1 s, two bombs (%d)" % drops.size())
	check(loaded.call() == loaded0 - 2 and u.stores.fm_mass < mass0, "the two bombs left the pylons (%d -> %d), lighter (%.0f lb)" % [loaded0, loaded.call(), u.stores.fm_mass])
