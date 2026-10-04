# AI air-to-air (docs/ai.md §13): mission 221's MiG-29 wingman, whose formation slot targets the player (420 "find
# best target" = the primary), sees the player 7 km ahead, selects it and launches a missile at it inside its
# envelope (300 Launch: the cone, the fire gate); the player's RWR gets the launch. The player's jet holds still
# (flight model stopped); the AI runs at 8× time.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(3)
	tv.fm_stopped = true
	tv.gear_down = false
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var mig: Dictionary = {}
	for e in rt.entities.values():
		if e.name == "mig29_2_6th_wave":
			mig = e
	var u = tv.ai.combat.units.get(mig.key)
	check(u != null and u.air and int(u.w.get("type", 0)) == 570, "the MiG-29 is armed (AA-11 selected)")
	check(is_same(mig.pilot.brain.primary, me), "its primary target is the player")
	var w = tv.weapons
	var fired := false
	var flagged := false
	var t0: float = rt.now
	Engine.time_scale = 8.0
	while rt.now - t0 < 60.0 and not fired:
		# The player 7 km ahead of the MiG along its velocity, at its height.
		var v: Vector3 = mig.vel
		var ahead: Vector3 = mig.world + (v.normalized() if v.length() > 1.0 else Vector3(0, 1, 0)) * 7000.0
		tv.rig.position = tv.world_to_scene(ahead)
		await process_frame
		fired = w.missiles.any(func(m): return is_same(m.get_meta("owner"), mig))
		flagged = flagged or w.rwr.any_launch()
	Engine.time_scale = 1.0
	print("MiG target ", mig.pilot.brain.target.get("name", "-"), " mode ", mig.pilot.mode, " station ", u.cur, " after %.0f s" % (rt.now - t0))
	check(is_same(mig.pilot.brain.target, me), "the MiG targets the player")
	check(fired, "the MiG launched a missile at the player")
	check(flagged, "the player's RWR: missile launch")
