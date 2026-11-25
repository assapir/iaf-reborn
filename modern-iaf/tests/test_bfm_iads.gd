# Modern IAF's enemy fighter on the network and the crews' emission control (docs/ai.md §15.1, §15.5, §18.2), headless
# on the Sufa's weapons range (dev hooks only; no mission places one): a MiG-29A with only its R-73s and gun, flown by
# `enemy_flight` on an S-300 network whose search radar is out of reach, 3 km behind a scripted jet on the player's
# side. Its radar's contact goes over the network (the GCI's vector holds the jet, from the MiG's track alone) and it
# fires an R-73 on the physical missile. Then an autonomous S-300
# battery at the Medium skill searches without a pause.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_bfm_iads.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const ALT := 5000.0

var tv: Node


## Flies until `f` holds, at most `s` s; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await fly(tv, 0.25)
	return f.call()


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-bfmiads", false).get_current_dir()
	tv.addon.result = {"pass": true}
	s.invulnerable = true
	var rt: Node = tv.runtime
	var w = tv.weapons
	var j: Vector3 = tv.player_world()
	var up := func(x: float, y: float) -> Vector3: return Vector3(j.x + x, j.y + y, ALT)
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var a: Array = ad.spawn("s300", j + Vector3(0, 60000, 0), 180.0)
	# The 64N6E2 400 km off, past its reach: the network's picture comes only from the MiG's radar.
	var ents: Array = ad.spawn_net(j + Vector3(0, 400000, 0), j + Vector3(2000, 398000, 0), [ad.site_of(a[0])])
	var n: Dictionary = ad.net_of(ents[0])
	check(not n.is_empty(), "the network")
	var mine := int(rt.player_entity().get("side", 2))
	var jet: Dictionary = tv.ai.spawn("mig29a", up.call(0, 23000), 0.0, [[j.x, j.y + 400000, ALT, 0]], mine)
	var m: Dictionary = tv.ai.spawn("mig29a", up.call(0, 20000), 0.0, [])
	check(not jet.is_empty() and not m.is_empty(), "the scripted jet and the MiG in the air")
	if jet.is_empty() or m.is_empty() or n.is_empty():
		return
	jet.pilot.set_mode(7)
	# Its R-73s only (the R-27R taken off): the fight's missile.
	var u = tv.ai.combat.units.get(m.key)
	var r73 := 0
	for k in mini(9, u.stations.size()):
		var t := int(u.stations[k].w.get("type", 0))
		if t == 610:
			u.stations[k].count = 0
		elif t in [570, 580]:
			r73 += int(u.stations[k].count)
	check(r73 > 0, "its R-73s")
	var f = tv.ai.enemy_flight([m], up.call(0, 20000), n)
	check(f != null, "flown as an enemy fighter on the network")
	if f == null:
		return
	var shared := func(): return n.get("contacts", {}).has(String(jet.key))
	check(await _until(shared, 20.0), "its radar's contact shared with the network")
	await fly(tv, 0.5)
	var v: Dictionary = n.gci.vector(rt.now, up.call(0, 20000))
	check(String(v.get("id", "")) == String(jet.key), "the GCI's vector holds the jet (%s)" % [v])
	var fox2 := func():
		return w.missiles.any(
			func(x): return is_same(x.get_meta("owner", {}), m) and int(x.weapon.get("type", 0)) in [570, 580]
		)
	check(await _until(fox2, 60.0), "an R-73 fired in the fight (%s)" % [f.state(1)])

	# An autonomous battery searches without a pause at the Medium skill (a High crew's blinks, docs/ai.md §15.1).
	var b: Array = ad.spawn("s300", j + Vector3(60000, 0, 0), 270.0)
	var radiating := func(): return b.any(func(e): return e.get("radiating", false))
	check(await _until(radiating, 3.0), "the battery searches")
	await fly(tv, 25.0)
	check(radiating.call(), "and searches on")
