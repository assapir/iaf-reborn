# The mission's landed handler (FUN_00440f90, docs/mission-runtime.md §5.5, docs/ai.md §7.2): each new landing
# the flight model counts (`landings`, v1.1: every landing) sends the player's **wingman** to the route's last
# waypoint; the player's own NAV steering is not touched. The player's next-waypoint select also sets its brain
# index (FUN_00440e90 in FUN_004532a0). Mission 221: alpha_1 (player) and alpha_2 (AI).
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
	check(wing.waypoint_index() == tv.route.size() - 1, "landed: the wingman on the last waypoint (%d)" % wing.waypoint_index())
	check(tv.cockpit.current_waypoint == 0, "the player's NAV is not touched")
	tv.autopilot.set_waypoint(1)
	check(tv.flight.ap_waypoint_index() == 1, "next waypoint: the brain index follows (%d)" % tv.flight.ap_waypoint_index())
