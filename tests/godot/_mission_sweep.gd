# Sweep probe (not a test): each mission in MISSIONS (env, space-separated) runs SWEEP_SECONDS (default 240) of
# mission time at ×8 with the player invulnerable and parked; then the remaining role-1 targets are destroyed and
# the mission must pass. Prints one SWEEP line per mission.
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().invulnerable = true
	Settings().no_crashes = true
	var secs := float(OS.get_environment("SWEEP_SECONDS")) if OS.get_environment("SWEEP_SECONDS") != "" else 240.0
	for id in OS.get_environment("MISSIONS").split(" ", false):
		var tv = await start_mission(int(id))
		var rt = tv.runtime
		Engine.time_scale = 8.0
		var t0: float = rt.now
		var notes: Array = []
		while rt.now - t0 < secs and not rt.failed:
			await process_frame
		Engine.time_scale = 1.0
		var targets: Array = rt.entities.values().filter(func(e): return int(e.role) == rt.ROLE_TARGET)
		var by_others := targets.filter(func(e): return int(e.state) >= 4).size()
		var me: Vector3 = rt._world_of(rt.player_entity())
		var lost: Array = rt.entities.values().filter(func(e): return int(e.role) == rt.ROLE_SURVIVE and int(e.state) >= 4 and not e.player).map(
			func(e): return "%s %.0f km away" % [e.name, Vector2(e.world.x - me.x, e.world.y - me.y).length() / 1000.0])
		if rt.failed:
			notes.append("failed at %ds" % int(rt.now - t0))
		var early := "failed" if rt.failed else ("passed" if rt.passed else "open")
		for e in targets:
			if int(e.state) < 4:
				rt.set_damage_level(e, 5)
		var t1: float = rt.now
		while rt.now - t1 < 2.0:
			await process_frame
		print("SWEEP %s: after %ds %s %s; targets %d (%d by others), left %d; lost %s; then %s" % [id, int(secs), early, notes,
			targets.size(), by_others, rt.targets_left, lost, "PASS" if rt.passed else ("FAILED" if rt.failed else "open")])
		check(rt.passed or rt.failed, "mission %s ends" % id)
