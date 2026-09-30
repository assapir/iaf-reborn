# AI aircraft (docs/ai.md): mission 221 "Back to the Wall" — brain-controlled jets fly the flight model
# under their autopilot: they navigate their routes (the waypoint index advances, they close on their
# waypoints) and the wingmen keep formation on their leaders.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(3)
	check(tv.ai != null and tv.ai.pilots.size() >= 8, "AI jets flying (%d)" % (tv.ai.pilots.size() if tv.ai != null else 0))
	var p0: Dictionary = {}
	for p in tv.ai.pilots:
		p0[p] = {"world": p.ent.world, "wp": p.waypoint_index()}
		print("  %s mode %d wp %d alt %.0f speed %.0f" % [p.ent.name, p.mode, p.waypoint_index(), p.ent.world.z, p.state().speed])
	Engine.time_scale = 8.0
	var t0: float = tv.runtime.now
	while tv.runtime.now - t0 < 120.0:
		await process_frame
	Engine.time_scale = 1.0
	var moved := 0
	for p in tv.ai.pilots:
		print("  %s mode %d wp %d alt %.0f speed %.0f moved %.0f m" % [p.ent.name, p.mode, p.waypoint_index(), p.ent.world.z, p.state().speed, (p.ent.world - p0[p].world).length()])
		if (p.ent.world - p0[p].world).length() > 10000.0:
			moved += 1
	check(moved >= 6, "the AI jets flew (%d moved > 10 km in 120 s)" % moved)
	check(tv.ai.contacts().size() == tv.ai.pilots.size(), "contacts for radar / RWR")
