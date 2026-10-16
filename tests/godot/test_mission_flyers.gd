# Mission-controlled flyers (docs/mission-runtime.md §4 Path): a helicopter / transport / jet on a script Path holds
# the points' z above the ground and faces along its leg; a ground unit on a Path keeps to the terrain and turns along
# it too; a hovering helicopter (motion op 1) stays at its altitude. 231: the MI-24s' "do path" at 200 m; 215: MI24_1
# hovers 75 s first.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(231)
	var rt = tv.runtime
	await fly(tv, 3.0)
	var heli: Dictionary = _named(rt, "MI24_1")
	check(heli.get("path") != null, "231 MI24_1 flies its path")
	var g = tv.mission_ground(heli.world)
	var agl: float = float(heli.alt) - float(g)
	check(absf(agl - 200.0) < 15.0, "on its path 200 m above the ground (%.0f m)" % agl)
	var pts: Array = heli.path.points  # its single leg (world coordinates; the per-frame step is below float32's grain)
	var leg: Vector3 = pts[-1] - pts[-2]
	var track := rad_to_deg(atan2(leg.x, leg.y))
	check(absf(wrapf(track - float(heli.heading), -180.0, 180.0)) < 0.5,
		"it faces along its leg (heading %.1f°, leg %.1f°)" % [heli.heading, track])
	check(is_equal_approx(heli.node.rotation.y, -deg_to_rad(float(heli.heading))), "the model turned with it")
	tv = await start_mission(115)
	rt = tv.runtime
	await fly(tv, 3.0)
	var tank := {}
	for e in rt.entities.values():
		if e.get("path") != null and not e.get("airborne_class", false) and e.node != null:
			tank = e
	check(not tank.is_empty(), "115: a ground unit drives a path")
	if not tank.is_empty():
		var gg = tv.mission_ground(tank.world)
		check(absf(float(tank.alt) - float(gg)) < 1.0 and is_equal_approx(tank.node.rotation.y, -deg_to_rad(float(tank.heading))),
			"%s keeps to the terrain, turned along its path (heading %.0f°)" % [tank.name, tank.heading])
	tv = await start_mission(215)
	rt = tv.runtime
	var mi: Dictionary = _named(rt, "MI24_1")
	var alt0: float = float(mi.alt)
	var p0: Vector3 = mi.world
	await fly(tv, 3.0)
	check(mi.get("path") == null and mi.world.distance_to(p0) < 1.0 and is_equal_approx(float(mi.alt), alt0),
		"215 MI24_1 hovers at %.0f m (%.0f above the ground)" % [alt0, alt0 - float(tv.mission_ground(p0))])
