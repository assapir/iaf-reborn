# Ground fire (docs/ai.md §14). AAA: mission 313's ZSUs run their 'zsu' brain (400 target, 550 within 4000 m), the
# sensor sees the player, start combat locks the player's RWR and arms the fire timer (_reactionTime 10 s, then
# every 0.5 s); no shot beyond 2250 m; inside it the rounds fly at the lead point and hit (the player's damage
# grows). SAM: an SA-3 launcher engages within 17 km, launches one SA-3 (630) inside its DLZ after _reactionTime 20 s
# (the RWR's launch flag), none at a target behind it, and the missile reaches the jet. The flight is frozen; the
# ground units and the weapons run on a scripted sim time. Rockets: mission 322's units have brain −1 and take their
# object's default brain ('mission'); its rocket vehicle fires at the player within 4 km and the burst damages it.
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().jet_id = -1
	var tv = await start_mission(313)
	await frames(3)
	tv.frozen = true
	var g = tv.ai.ground
	# Six SA-3 launchers (630; their Disable combat runs only when their radar dies) and three ZSUs (565).
	var aaa: Array = g.units.values().filter(func(x): return int(x.w.type) == 565)
	check(g.units.size() == 9 and aaa.size() == 3, "313: nine armed ground units, three ZSUs (%d / %d)" % [aaa.size(), g.units.size()])
	var u = null
	for k in g.units:
		if g.units[k].ent.name == "first zsu":
			u = g.units[k]
	check(u != null and int(u.w.type) == 565 and u.rounds != null, "first zsu carries the AAA (565)")
	if u == null:
		return
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var zsu: Vector3 = rt._world_of(u.ent)
	var t: float = rt.now
	# 3000 m away, 300 m up: engaged (≤ 4000 m) but out of gun range.
	tv.player_world_override = zsu + Vector3(3000, 0, 300)
	t = _run(g, t, 20.0)
	check(u.brain.target == me and u.brain.engaged, "the zsu targets the player and engages")
	check(tv.weapons.rwr._find(u.ent.key) >= 0, "start combat locks the player's RWR")
	check(u.rounds.flying_count() == 0 and me.damage == 0.0, "no shot beyond 2250 m")
	# 1500 m: the rounds fly and hit.
	tv.player_world_override = zsu + Vector3(1500, 0, 300)
	var flew := 0
	for i in 200:
		t += 0.05
		g.update(t)
		flew = maxi(flew, u.rounds.flying_count())
	check(flew > 0, "rounds in the air inside 2250 m (%d)" % flew)
	check(me.damage > 0.0, "the rounds hit the player (damage %.3f)" % me.damage)
	# 7000 m: beyond 6000 the brain stops combat; the fire timer is off.
	tv.player_world_override = zsu + Vector3(7000, 0, 300)
	t = _run(g, t, 15.0)
	check(not u.brain.engaged and u.fire_next == INF, "beyond 6000 m combat stops")


	# A fresh load: the AAA hits may have broken the RWR (system 14).
	tv = await start_mission(313)
	await frames(3)
	tv.frozen = true
	await _sam(tv, tv.ai.ground)
	await _rockets()


func _sam(tv, g) -> void:
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	tv.player_world_override = null
	me.damage = 0.0
	var u = null
	for x in g.units.values():
		if x.ent.name == "sa3 1launcher1":
			u = x
		else:
			g.set_combat(x.ent, false)
	check(u != null and int(u.w.type) == 630, "sa3 1launcher1 carries the SA3 (630)")
	if u == null:
		return
	var site: Vector3 = rt._world_of(u.ent)
	var h := deg_to_rad(float(u.ent.heading))
	var fwd := Vector3(sin(h), cos(h), 0)
	var w = tv.weapons
	var t: float = rt.now + 100.0
	var wt: float = w.now
	# Behind the site, 10 km, 3000 m up: engaged, never launched.
	tv.rig.position = tv.world_to_scene(site - fwd * 10000.0 + Vector3(0, 0, 3000))
	for i in 800:
		t += 0.05
		wt += 0.05
		g.update(t)
		w.update(wt)
	check(u.brain.engaged and u.missile == null, "a target behind the site: engaged, no launch")
	# In front: one launch after the reaction time, the RWR's launch flag, the missile reaches the jet.
	tv.rig.position = tv.world_to_scene(site + fwd * 10000.0 + Vector3(0, 0, 3000))
	var launched := -1.0
	var flagged := false
	var ended := false
	for i in 1200:
		t += 0.05
		wt += 0.05
		g.update(t)
		w.update(wt)
		if u.missile != null and launched < 0.0:
			launched = t
		flagged = flagged or w.rwr.any_launch()
		if u.missile != null and not u.missile in w.missiles:
			ended = true
			break
	check(launched > 0.0 and u.missile.weapon.type == 630, "an SA-3 launched")
	check(flagged, "the RWR's launch flag")
	check(ended and me.damage > 0.0, "the SA-3 reaches the jet (damage %.2f)" % me.damage)


func _run(g, t: float, secs: float) -> float:
	for i in int(secs / 0.05):
		t += 0.05
		g.update(t)
	return t


func _rockets() -> void:
	var tv = await start_mission(322)
	await frames(3)
	tv.frozen = true
	var g = tv.ai.ground
	var rt = tv.runtime
	var u = null
	var sams := 0
	for x in g.units.values():
		if int(x.w.type) == 560:
			u = x
		elif int(x.w.type) == 630:
			sams += 1
	check(u != null and sams == 9, "322: the rocket vehicle and nine SAM launchers (SA-2, Hawk) armed (object brain 'mission') (%d)" % sams)
	if u == null:
		return
	for x in g.units.values():
		if x != u:
			g.set_combat(x.ent, false)
	var me: Dictionary = rt.player_entity()
	var p: Vector3 = rt._world_of(u.ent)
	tv.player_world_override = p + Vector3(1500, 0, 200)
	var t: float = rt.now
	var fired := false
	for i in 800:
		t += 0.05
		g.update(t)
		fired = fired or u.rounds.flying_count() > 0
	check(fired, "the rocket vehicle fires at the player within 4 km")
	check(me.damage > 0.0 or int(me.state) >= 3, "the rockets burst at the player (damage %.2f, state %d)" % [me.damage, int(me.state)])
