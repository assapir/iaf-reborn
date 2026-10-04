# Collisions of the player's jet with units (docs/damage.md §7, FUN_0043c140 -> FUN_0043b340): only
# units whose bdb Objects 0x58c is set have a collider. Mission 315 starts the jet inside a shelter
# (schacha3, 0x58c = 0): no collision, and the jet taxis out. A collidable building or vehicle on the
# jet's spot destroys both; a hidden one too (the original keeps its collider), not with
# Physics "fix_ghost_collision".
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv: Node = await start_mission(315)
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var shelter: Dictionary = _named(rt, "schacha3")
	check(not shelter.is_empty() and not shelter.collidable, "schacha3 (shelter) has no collider (0x58c = 0)")
	var d0: float = tv.rig.position.distance_to(shelter.node.position)
	check(d0 < shelter.coll_radius, "the jet starts inside the shelter (%.1f m from its centre, radius %.0f m)" % [d0, shelter.coll_radius])
	await frames(30)
	check(int(me.state) == 1 and int(shelter.state) == 1, "no collision at the start")
	# Taxi out: brakes off, throttle up, until the jet is clear of the shelter's radius.
	tv.brakes = false
	tv.throttle = 0.9
	var t0 := Time.get_ticks_msec()
	while tv.rig.position.distance_to(shelter.node.position) < shelter.coll_radius + 5.0 \
			and Time.get_ticks_msec() - t0 < 60000 and int(me.state) == 1:
		await process_frame
	tv.throttle = 0.0
	var d1: float = tv.rig.position.distance_to(shelter.node.position)
	check(d1 >= shelter.coll_radius + 5.0, "the jet taxis out of the shelter (%.0f m from its centre)" % d1)
	check(int(me.state) == 1 and int(shelter.state) == 1, "jet and shelter intact after taxiing out")

	# A collidable unit on the jet's spot: both destroyed.
	var tgt: Dictionary = _named(rt, "mercav strf4")
	check(tgt.collidable, "the Merkava has a collider (0x58c = 1)")
	tv.fm_stopped = true  # the test places the jet
	tv.rig.position = tgt.node.position
	await frames(3)
	check(int(me.state) >= 3 and int(tgt.state) == 5, "flying into a vehicle destroys both (jet %d, vehicle %d)" % [me.state, tgt.state])

	# A hidden collidable building keeps its collider; Physics "fix_ghost_collision" skips it.
	for fix in [false, true]:
		Settings().better["fix_ghost_collision"] = fix
		tv = await start_mission(315)
		rt = tv.runtime
		me = rt.player_entity()
		var b: Dictionary = {}
		for e in rt.entities.values():
			if e.get("collidable", false) and e.node != null and e.klass in [0xc, 0xd] and e.type_code != 450 \
					and int(e.role) == 2:
				b = e
				break
		check(not b.is_empty(), "a collidable building (%s)" % b.get("name", "-"))
		rt._set_visible(b, false)
		tv.fm_stopped = true
		tv.rig.position = b.node.position
		await frames(3)
		if fix:
			check(int(me.state) == 1 and int(b.state) == 1, "fix_ghost_collision: no collision with the hidden building")
		else:
			check(int(me.state) >= 3 and int(b.state) == 5, "original: the hidden building still collides")
	Settings().better["fix_ghost_collision"] = false
