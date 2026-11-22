# Modern IAF's enemy fighters (docs/ai.md §18, modern-iaf/docs/ai-plan.md K3), headless on the Sufa's weapons range: a
# MiG-29A pair on a CAP orbit (spawned in the air by the dev hook ai_flights.gd `spawn`, flown by `enemy_flight`; no
# mission places one) under an S-300 network's 64N6E2 and 54K6E2 (air_defence.gd `spawn_net`, no batteries). A
# scripted jet on the player's side flies north at the station: the network's sweeps vector the pair, the lead
# commits, its radar finds the jet and locks it, and the pair shoots through combat.gd's launch with the MiG's own
# missile records; a radar missile launched at the lead is notched (the Medium skill's tactics). The CPU per AI jet
# per frame at time scale 1 is printed (X5).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_intercept.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

# terrain.gd is loaded where used: an -s script compiles before the autoloads it reads.

const TIME_SCALE := 4.0
const ALT := 7000.0

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
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-intercept", false).get_current_dir()
	tv.addon.result = {"pass": true}
	var w = tv.weapons
	var rt: Node = tv.runtime
	var j: Vector3 = tv.player_world()
	var up := func(x: float, y: float) -> Vector3: return Vector3(j.x + x, j.y + y, ALT)
	# The scripted jet: 100 km south of the station, flying north on its route.
	var mine := int(rt.player_entity().get("side", 2))
	var jet: Dictionary = tv.ai.spawn("mig29a", up.call(0, 20000), 0.0, [[j.x, j.y + 400000, ALT, 0]], mine)
	check(not jet.is_empty(), "the scripted jet in the air")
	if jet.is_empty():
		return
	jet.pilot.set_mode(7)
	# The network north of the station, the pair on station heading south.
	var station: Vector3 = up.call(0, 120000)
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var ents: Array = ad.spawn_net(up.call(10000, 140000), up.call(12000, 138000), [])
	var net: Dictionary = ad.net_of(ents[0])
	var a: Dictionary = tv.ai.spawn("mig29a", station, 180.0, [])
	var b: Dictionary = tv.ai.spawn("mig29a", station + Vector3(1500, 0, 0), 180.0, [])
	check(not a.is_empty() and not b.is_empty() and not net.is_empty(), "the pair and the network")
	if a.is_empty() or b.is_empty():
		return
	var u = tv.ai.combat.units.get(a.key)
	var aa := func(t: int): return u.stations.filter(func(x): return int(x.w.get("type", 0)) == t and x.count > 0)
	check(u != null and aa.call(610).size() == 2 and aa.call(570).size() + aa.call(580).size() == 4, "R-27Rs, R-73s")
	if u == null or aa.call(610).is_empty():
		return
	var r27: Dictionary = aa.call(610)[0].w
	var f = tv.ai.enemy_flight([a, b], station, net)
	check(f != null and a.pilot.by_ai and b.pilot.by_ai, "flown as an enemy pair")
	if f == null:
		return
	# The CPU per AI jet per frame at time scale 1 (X5), 20 s with the pair on station and the scripted jet.
	tv.ai.cost_us = 0
	tv.ai.cost_frames = 0
	await fly(tv, 20.0)
	var ms: float = tv.ai.cost_us / 1000.0 / maxi(tv.ai.cost_frames, 1) / maxi(tv.ai.pilots.size(), 1)
	print("X5: %.3f ms per AI jet per frame (CPU; %d jets, %d frames)" % [ms, tv.ai.pilots.size(), tv.ai.cost_frames])
	check(String(f.state(1).phase) == "cap" and String(f.state(2).phase) == "slot", "on station: %s" % [f.state(1)])
	Engine.time_scale = TIME_SCALE
	var committed := func(): return f.state(1).get("committed", false)
	check(await _until(committed, 120.0), "the lead commits on the network's vector")
	var gap: float = rt._world_of(jet).distance_to(rt._world_of(a))
	var vec: Dictionary = net.gci.vector(rt.now, station)
	check(vec.get("id") == jet.key and not f.state(1).contact, "vectored, not by its radar (%.0f km)" % [gap / 1000])
	var contact := func(): return f.state(1).get("contact", false)
	check(await _until(contact, 120.0), "its radar finds the jet")
	check(tv.ai.enemy_flights[-1].locks.get(1, "") == jet.key, "and locks it")
	var shot := func():
		return w.missiles.any(
			func(m): return is_same(m.get_meta("owner", {}), a) or is_same(m.get_meta("owner", {}), b)
		)
	check(await _until(shot, 120.0), "the pair shoots")
	var mis: Array = w.missiles.filter(func(m): return m.target_key == jet.key)
	gap = rt._world_of(jet).distance_to(rt._world_of(a))
	check(not mis.is_empty(), "%d missile(s) at the jet from %.1f km" % [mis.size(), gap / 1000])
	# A radar missile (the R-27R's record) launched at the lead from the jet: notched.
	var jp = jet.pilot.state()
	var ter: GDScript = load("res://shared/terrain/terrain.gd")
	var o := {
		"vel": jet.vel,
		"fwd": ter.dir_to_world(jp.forward),
		"up": ter.dir_to_world(jp.up),
		"right": ter.dir_to_world(jp.right)
	}
	w.launch_homing(r27, rt._world_of(jet), o, a.key, 1.0, jet)
	var defending := func(): return f.state(1).get("defending", false)
	check(await _until(defending, 10.0), "the lead defends")
	check(String(f.state(1).phase) == "notch", "a notch (%s)" % f.state(1).phase)
	# The lowest height while it notches (after the 5 s clear it goes back to the intercept).
	var z0: float = a.world.z
	var low := z0
	var notch_s := 0.0
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 30.0 and int(a.state) < 3:
		if String(f.state(1).phase) == "notch":
			low = minf(low, a.world.z)
		var ts: float = tv._sim_time
		await process_frame
		if String(f.state(1).phase) == "notch":
			notch_s += tv._sim_time - ts
	print("notch %.1f s, %.0f → %.0f m, now %s at %.0f m" % [notch_s, z0, low, f.state(1).phase, a.world.z])
	check(int(a.state) >= 3 or low < z0 - 50.0, "down into the look-down (%.0f → %.0f m)" % [z0, low])
	Engine.time_scale = 1.0
