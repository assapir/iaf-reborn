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
	check(
		loaded0 > 0 and mass0 > 0.0 and u.store_nodes.is_empty(),
		(
			"the Su-24's stores (%d) weigh on its FM (%.0f lb); no models: its model has no Station helpers"
			% [loaded0, mass0]
		)
	)
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
	print(
		"Su-24 modes ",
		modes.keys(),
		" station ",
		u.cur,
		" ",
		u.w.get("name", ""),
		" stage ",
		p.flight.ap_stage() if p.flight.has_method("ap_stage") else ""
	)
	check(modes.has(0x17), "the Su-24 dive-bombs (mode 0x17)")
	check(dropped, "a bomb released")
	check(near < 600.0, "the bomb falls near the target (%.0f m)" % near)
	check(
		u.ripple.qty() == 2 and is_equal_approx(u.ripple.period(), 0.1) and drops.size() == 2,
		"the ripple: 380's quantity 2 every 0.1 s, two bombs (%d)" % drops.size()
	)
	check(
		loaded.call() == loaded0 - 2 and u.stores.fm_mass < mass0,
		"the two bombs left the pylons (%d -> %d), lighter (%.0f lb)" % [loaded0, loaded.call(), u.stores.fm_mass]
	)
	await _rockets_and_lgb(tv, su, tgt, u)


## The ripple's other stores (FUN_00454270's case 500 / 510 / 560 / 650; FUN_00454b70): rockets fly the fixed-weapon
## motion at the led ripple point and burst near the target; a laser bomb (the AI has no designator) glides the guided
## motion to the target's position now (no lead). The Su-24 restarted 3 km out, 800 m up, at the target.
func _rockets_and_lgb(tv, su: Dictionary, tgt: Dictionary, u) -> void:
	var rt = tv.runtime
	var w = tv.weapons
	var tp: Vector3 = rt._world_of(tgt)
	var of := func(type: int) -> Dictionary:
		for x in w.db.weapons.values():
			if int(x.get("type", 0)) == type:
				return x
		return {}
	for type in [560, 650]:
		var wt: Dictionary = of.call(type)
		check(not wt.is_empty(), "a %d weapon in the data (%s)" % [type, wt.get("name", "")])
		if wt.is_empty():
			continue
		su.world = tp + Vector3(3000, 0, 800)
		su.heading = 270.0
		tv.ai._start(su.pilot, Settings().assets_dir().path_join("install"), su.pilot.plane)
		u.stations[0] = {"w": wt, "count": 4}
		tv.ai.combat._select(u, 0)
		u.ripple_left = u.ripple.qty()
		u.ripple_next = rt.now
		u.ripple_target = tgt
		var near := INF
		var fired := 0
		var t0: float = rt.now
		while rt.now - t0 < 25.0:
			await process_frame
			if type == 560:
				for k in w._rocket_nodes:
					if is_same(w._rocket_nodes[k].get("owner"), su):
						fired = maxi(fired, w._rocket_nodes.size())
						var rp: Vector3 = w.rockets.position(w.rockets.pool[k], w.now)
						near = minf(near, Vector2(rp.x - tp.x, rp.y - tp.y).length())
			else:
				for g in w.guided:
					if is_same(g.get_meta("owner", {}), su):
						fired = maxi(fired, 1)
						var gp: Vector3 = g.position(w.now)
						near = minf(near, Vector2(gp.x - tp.x, gp.y - tp.y).length())
		check(
			fired > 0 and int(u.stations[0].count) < 4,
			"%d: the Su-24's ripple releases them (%d left)" % [type, int(u.stations[0].count)]
		)
		check(near < 150.0, "%d: they reach the target (%.0f m)" % [type, near])
