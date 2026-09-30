# The mission's landed handler (FUN_00440f90, docs/mission-runtime.md §5.5): each new landing the flight
# model counts (`landings`, v1.1: every landing, not only the first) sends the NAV steering to the
# route's last waypoint.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(313)
	await frames(5)
	check(tv.route.size() > 1, "the player's formation has a route (%d waypoints)" % tv.route.size())
	check(int(tv.flight.state().get("landings", -1)) == 0, "no landing yet")
	tv.cockpit.current_waypoint = 0
	# One more landing than the host has seen (as after a touchdown).
	tv._landings = -1
	await frames(3)
	check(tv.cockpit.current_waypoint == tv.route.size() - 1, "landed: NAV on the last waypoint (%d)" % tv.cockpit.current_waypoint)
	tv.cockpit.current_waypoint = 0
	await frames(3)
	check(tv.cockpit.current_waypoint == 0, "nothing more without a new landing")
