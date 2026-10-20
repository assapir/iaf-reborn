# AI sensors and locks (docs/ai.md §13–§14). Mission 313's first ZSU (sensor 5 NM = 9270 m): the player beyond the
# sensor range is not seen, with its jammer on (ctl+0x1b8) it is seen at any range (FUN_004af300); with its radar quiet
# only within 0.7 R even jamming. Condition 26 (FUN_005c1530): the player as the target counts while its RWR lists
# something. A sensor's lock on a unit with a brain sets its brain+0x7c (FUN_004b0510: the unit itself, original bug;
# fix_lock_threat: the owner); the unlock clears it. Action 430 (FUN_00444a60): a unit without a controller targets its
# brain+0x7c. The AI launch q against a jammer (FUN_00454b70) is a Rust unit test (release.rs).
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().jet_id = -1
	var tv = await start_mission(313)
	await frames(3)
	tv.frozen = true
	var g = tv.ai.combat
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var u = null
	for k in g.units:
		if g.units[k].ent.name == "first zsu":
			u = g.units[k]
	check(u != null and is_equal_approx(u.sensor_r, 5 * 1854.0), "first zsu: sensor 5 NM")
	if u == null:
		return
	var zsu: Vector3 = rt._world_of(u.ent)
	var w = tv.weapons
	var seen := func() -> bool:
		g._scan(u)
		return u.contacts.any(func(c): return is_same(c.ent, me))
	# 9.5 km, 1000 m up (line of sight over the terrain), the radar on.
	tv.player_world_override = zsu + Vector3(9500, 0, 1000)
	w.radar.cycle_mode(rt.now)
	check(w.radar.mode > 1, "the player's radar is on (mode %d)" % w.radar.mode)
	tv.cockpit.indicators[6] = false
	check(not seen.call(), "beyond the sensor range: not seen")
	tv.cockpit.indicators[6] = true
	check(w.ecm_on() and seen.call(), "jamming: seen at any range")
	w.radar.standby()
	check(not seen.call(), "radar quiet: only within 0.7 R, even jamming")
	tv.cockpit.indicators[6] = false

	# Condition 26 with the player as the target: its RWR list.
	u.brain.target = me
	w.rwr.clear()
	check(g.measure(u.ent, 26, me) == 0, "26: the player with an empty RWR list: 0")
	w.rwr.lock(u.ent.key)
	check(g.measure(u.ent, 26, me) == 1, "26: the player locked (RWR lists the zsu): 1")
	w.rwr.unlock(u.ent.key)

	# A lock on a unit with a brain: its brain+0x7c (the unit itself), cleared by the unlock; 26 follows it.
	var other = null
	for k in g.units:
		if g.units[k] != u and g.units[k].brain != null:
			other = g.units[k]
	check(other != null, "a second unit with a brain")
	if other == null:
		return
	w.lock_threat_fix = false
	g.on_lock(me, other.ent, true)
	check(is_same(other.brain.attacker, other.ent), "on-lock: brain+0x7c = the unit itself (original bug)")
	check(g.measure(u.ent, 26, other.ent) == 1, "26: a locked unit: 1")
	g.on_lock(me, other.ent, false)
	check(other.brain.attacker.is_empty(), "on-unlock clears it")
	w.lock_threat_fix = true
	g.on_lock(me, other.ent, true)
	check(is_same(other.brain.attacker, me), "fix_lock_threat: brain+0x7c = the owner")

	# Action 430: no controller → target = brain+0x7c.
	other.brain.target = {}
	g.combat(other.ent, "430", {})
	check(is_same(other.brain.target, me), "430: the target is brain+0x7c")
	g.on_lock(me, other.ent, false)
	w.lock_threat_fix = false
