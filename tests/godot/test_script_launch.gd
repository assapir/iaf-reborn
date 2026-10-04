# Script trigger op 2 Launch at target (docs/ai.md §14): an armed unit fires its weapon at the script's target, without
# a brain or a range check. 233's MI-24 (a helicopter, class 2: no sensor, fires only by script) launches its missile
# (580) at its boat target and hits it; 112's T-55 fires a rocket (560) at its Merkava. The jump to the list entry is
# direct; the ground units and the weapons run on a scripted sim time, the flight is frozen.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(233)
	await frames(3)
	tv.frozen = true
	var rt = tv.runtime
	var heli: Dictionary = _named(rt, "MI24 1")
	var boat: Dictionary = _named(rt, "satil 1")
	var u = tv.ai.combat.units.get(heli.key)
	check(u != null and u.brain == null and int(u.w.type) == 580, "233 MI24 1: armed (580), no brain-driven fire (class 2)")
	if u == null:
		return
	_place_ahead(tv, heli, boat)
	var w = tv.weapons
	var n0: int = w.missiles.size()
	rt._jump(heli, 1, 2)
	check(w.missiles.size() == n0 + 1 and u.missile != null and u.missile.target_key == boat.key, "op 2: a missile at the boat")
	var t: float = w.now
	for i in 600:
		t += 0.05
		w.update(t)
		if not u.missile in w.missiles:
			break
	check(not u.missile in w.missiles and (boat.damage > 0.0 or int(boat.state) >= 3),
		"the missile reaches the boat (damage %.2f, state %d)" % [boat.damage, int(boat.state)])

	tv = await start_mission(112)
	await frames(3)
	tv.frozen = true
	rt = tv.runtime
	var t55: Dictionary = _named(rt, "T55 South 1")
	var mk: Dictionary = _named(rt, "mercava South 1")
	u = tv.ai.combat.units.get(t55.key)
	check(u != null and int(u.w.type) == 560, "112 T55 South 1: rockets (560)")
	if u == null:
		return
	_place_ahead(tv, t55, mk)
	rt._jump(t55, 1, 3)
	check(u.rounds.flying_count() == 1, "op 2: a rocket at the Merkava")
	var now: float = rt.now
	for i in 400:
		now += 0.05
		tv.ai.combat.update(now)
		if u.rounds.flying_count() == 0:
			break
	check(u.rounds.flying_count() == 0 and (mk.damage > 0.0 or int(mk.state) >= 3), "the rocket bursts at the Merkava (damage %.2f)" % mk.damage)


## The target 1500 m ahead of the shooter at its height, in clear line of sight (the scripts' own timing and the
## units' paths are not run here).
func _place_ahead(tv, shooter: Dictionary, target: Dictionary) -> void:
	var h := deg_to_rad(float(shooter.heading))
	if int(shooter.klass) == 2:  # the helicopter hovers among hills: lifted clear of them
		shooter.path = null
		shooter.world = tv.runtime._world_of(shooter) + Vector3(0, 0, 300)
		tv.mission_entity_moved(shooter)
		shooter.alt = shooter.world.z
	target.path = null
	target.world = tv.runtime._world_of(shooter) + Vector3(sin(h), cos(h), 0) * 1500.0 + Vector3(0, 0, 20)
	target["airborne_class"] = true  # keep it at that height (mission_entity_moved snaps ground units)
	tv.mission_entity_moved(target)
	target.alt = target.world.z
