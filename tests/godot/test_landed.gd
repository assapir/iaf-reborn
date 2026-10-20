# The mission's landed handler (FUN_00440f90, docs/mission-runtime.md §5.5, docs/ai.md §7.2): each new landing
# the flight model counts (`landings`, v1.1: every landing) sends the player's **wingman** to the route's last
# waypoint; the player's own NAV steering is not touched. The player's next-waypoint select also sets its brain
# index (FUN_00440e90 in FUN_004532a0). A dead leader's index goes to its wingman (FUN_00440ed0), a dead wingman's
# nowhere. Mission 221: alpha_1 (player) and alpha_2 (AI).
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(221)
	await frames(5)
	check(tv.route.size() > 1, "the player's formation has a route (%d waypoints)" % tv.route.size())
	var wing = null
	for p in tv.ai.pilots:
		if p.ent.name == "alpha_2":
			wing = p
	check(wing != null, "the player's wingman flies")
	check(int(tv.flight.state().get("landings", -1)) == 0, "no landing yet")
	tv.cockpit.current_waypoint = 0
	tv._landings = -1  # one more landing than the host has seen (as after a touchdown)
	await frames(3)
	check(
		wing.waypoint_index() == tv.route.size() - 1,
		"landed: the wingman on the last waypoint (%d)" % wing.waypoint_index()
	)
	check(tv.cockpit.current_waypoint == 0, "the player's NAV is not touched")
	tv.autopilot.set_waypoint(1)
	check(
		tv.flight.ap_waypoint_index() == 1,
		"next waypoint: the brain index follows (%d)" % tv.flight.ap_waypoint_index()
	)

	# --- leader death (FUN_004a86b0 → FUN_00440eb0 → FUN_00440ed0): the wingman takes the dead leader's index ---
	var DM = load("res://mission/damage_model.gd")
	var ai_pair: Dictionary = {}
	for f in tv.ai._formations:
		if (
			f.members.size() >= 2
			and f.members[0].get("pilot") != null
			and f.members[1].get("pilot") != null
			and f.route.size() > 2
		):
			ai_pair = f
			break
	check(not ai_pair.is_empty(), "an AI formation with two AI jets")
	if not ai_pair.is_empty():
		var l = ai_pair.members[0].pilot
		var w2 = ai_pair.members[1].pilot
		l.set_waypoint_index(1)
		w2.set_waypoint_index(2)
		tv.runtime.set_damage_level(ai_pair.members[1], DM.EXPLODED)
		check(l.waypoint_index() == 1, "a dead wingman passes nothing to its leader")
		w2.set_waypoint_index(0)
		l.set_waypoint_index(ai_pair.route.size() - 2)
		tv.runtime.set_damage_level(ai_pair.members[0], DM.EXPLODED)
		check(
			w2.waypoint_index() == ai_pair.route.size() - 2,
			"an AI leader's death: its wingman on the leader's waypoint (%d)" % w2.waypoint_index()
		)
	wing.set_waypoint_index(0)
	tv.autopilot.set_waypoint(2)
	tv.runtime.set_damage_level(tv.runtime.player_entity(), DM.EXPLODED)
	check(
		wing.waypoint_index() == 2,
		"the player (leader) dies: the wingman on the player's waypoint (%d)" % wing.waypoint_index()
	)
