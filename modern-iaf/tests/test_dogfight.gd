# Modern IAF's enemy fighters in the dogfight (docs/ai.md §18.2, modern-iaf/docs/ai-plan.md K4), headless on the Sufa's
# weapons range: a MiG-29A (spawned in the air by the dev hook ai_flights.gd `spawn`, flown by `enemy_flight` with no
# network; no mission places one), its missiles taken off, 2 km behind a scripted jet on the player's side. It sees the
# jet, commits, flies the BFM leaf onto it and fires its gun through combat.gd's launch (370, then 300). The CPU per AI
# jet per frame at time scale 1 is printed (X5).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_dogfight.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
const ALT := 5000.0
const MOVES := ["pursuit", "lead", "lag", "high yo-yo", "low yo-yo", "rate", "radius", "vertical", "turn"]

var tv: Node


## Flies until `f` holds, at most `s` s; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await process_frame
	return f.call()


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-dogfight", false).get_current_dir()
	tv.addon.result = {"pass": true}
	var rt: Node = tv.runtime
	var j: Vector3 = tv.player_world()
	var up := func(x: float, y: float) -> Vector3: return Vector3(j.x + x, j.y + y, ALT)
	# The scripted jet flies north on its route; the MiG 2 km behind it.
	var mine := int(rt.player_entity().get("side", 2))
	var jet: Dictionary = tv.ai.spawn("mig29a", up.call(0, 22000), 0.0, [[j.x, j.y + 400000, ALT, 0]], mine)
	var a: Dictionary = tv.ai.spawn("mig29a", up.call(0, 20000), 0.0, [])
	check(not jet.is_empty() and not a.is_empty(), "the scripted jet and the MiG in the air")
	if jet.is_empty() or a.is_empty():
		return
	jet.pilot.set_mode(7)
	var u = tv.ai.combat.units.get(a.key)
	var gun: bool = u != null and u.stations.size() > 9 and int(u.stations[9].w.get("type", 0)) == 565
	check(gun and int(u.stations[9].count) > 0, "its gun with rounds")
	if not gun:
		return
	var rounds0 := int(u.stations[9].count)
	# Gun only: its missiles taken off (one would end the fight before the gun's range; a jet with rounds left still
	# commits, docs/ai.md §18.2).
	for k in u.stations.size():
		if k != 9:
			u.stations[k].count = 0
	var f = tv.ai.enemy_flight([a], up.call(0, 20000), {})
	check(f != null and a.pilot.by_ai, "flown as an enemy fighter")
	if f == null:
		return
	# The CPU per AI jet per frame at time scale 1 (X5), 10 s from the start of the fight.
	tv.ai.cost_us = 0
	tv.ai.cost_frames = 0
	await fly(tv, 10.0)
	var ms: float = tv.ai.cost_us / 1000.0 / maxi(tv.ai.cost_frames, 1) / maxi(tv.ai.pilots.size(), 1)
	print("X5: %.3f ms per AI jet per frame (CPU; %d jets, %d frames)" % [ms, tv.ai.pilots.size(), tv.ai.cost_frames])
	var st: Dictionary = f.state(1)
	check(st.get("visual", false) and st.get("committed", false), "sees the jet and commits: %s" % [st])
	check(String(st.phase) in MOVES, "flies a BFM move (%s)" % st.phase)
	Engine.time_scale = TIME_SCALE
	var fired := func(): return int(u.stations[9].count) < rounds0
	check(await _until(fired, 90.0), "fires its gun")
	var gap: float = rt._world_of(jet).distance_to(rt._world_of(a))
	print("%d rounds fired at %.0f m, %s" % [rounds0 - int(u.stations[9].count), gap, f.state(1).phase])
	check(int(a.state) < 3, "the MiG flies on")
	Engine.time_scale = 1.0
