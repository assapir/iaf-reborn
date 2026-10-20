# AI jets' systems damage and engine sound (docs/damage.md §5, docs/sound.md §3), mission 231 (AI jets flying).
# A hit that leaves an AI jet alive picks a system as the player's pick does, never 2 / 3 / 5 / 7 (FUN_0045d020) and
# never ECM (no AI ECM); the flight model reads the flags (engine damage: the RPM runs down). Every AI jet has an
# engine loop from its flight model (the player's rows); the unit destroyed (state 5) stops it.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(231)
	await seconds(1.0)
	var pilots: Array = tv.ai.pilots.filter(func(p): return p.node != null and int(p.ent.state) < 3)
	check(not pilots.is_empty(), "231: AI jets flying (%d)" % pilots.size())
	if pilots.is_empty():
		return
	var p = pilots[0]
	# The engine loop: one per AI jet, from its flight model; gone when the unit is destroyed.
	var e = p.node.find_child("EngineSound", true, false)
	check(
		e != null and e.engine_code in ["SFX_START_ENGINE", "SFX_DRY_THRUST", "SFX_AFTERBURNER_THRUST"],
		"an AI jet's engine plays (%s)" % (e.engine_code if e != null else "none")
	)
	var last = pilots[pilots.size() - 1]
	var le = last.node.find_child("EngineSound", true, false)
	if le != null and pilots.size() > 2:
		last.ent.state = 5
		await frames(2)
		check(le.engine_code == "", "destroyed: the engine stops")

	# The pick: 40 hits at damage 0.9 (codes 13..24 first), never a code the AI may not take (flags a code
	# implies, e.g. 21's 1 / 11 / 12 / 14 / 15 / 20, are set too).
	p.ent.damage = 0.9
	for i in 40:
		tv.ai.hit(p.ent)
	var broken := []
	for n in 25:
		if p.systems[n]:
			broken.append(n)
	check(not broken.is_empty(), "hits broke systems %s" % str(broken))
	check(not (2 in broken or 3 in broken or 5 in broken or 7 in broken), "no 2 / 3 / 5 / 7 on an AI jet")

	# Engine damage on a single-engine jet (22 → FM bits 4 and 8): no thrust, the RPM runs down.
	var singles: Array = pilots.filter(func(x): return x != p and not x.twin and int(x.ent.state) < 3)
	check(not singles.is_empty(), "a single-engine AI jet (%d)" % singles.size())
	if singles.is_empty():
		return
	var q = singles[0]
	q.ent.damage = 0.5
	var rpm0: float = q.flight.state().rpm
	q.systems[22] = true
	q.flight.set_damage(q.systems, q.twin)
	await seconds(3.0)
	var rpm1: float = q.flight.state().rpm
	check(rpm1 < rpm0 - 0.2, "engine damage: the RPM runs down (%.2f -> %.2f)" % [rpm0, rpm1])
