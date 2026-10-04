# Script motion op 11 Yaw to target (docs/mission-runtime.md §4, docs/part-animation.md "Vehicles"): 231's T-62 turns
# its turret to the bearing of its target (re-aimed every 1 s), 222's Scud launcher rises 1.5° a second to 90°, 233's
# speedboat (no turret) faces its target. The list entry is jumped to directly; the runtime's clock is stepped.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(231)
	await frames(2)
	var rt = tv.runtime
	var t62: Dictionary = _named(rt, "t62_0")
	var tgt: Dictionary = _named(rt, "mercava0")
	rt._jump(t62, 0, 3)
	_step(rt, 0.1)
	var d: Vector3 = rt._world_of(tgt) - rt._world_of(t62)
	var want := wrapf(float(t62.heading) - rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)
	check(absf(float(t62.get("parts", {}).get("turret", 999.0)) - want) < 1e-3, "231 t62_0: turret at the target's bearing (%.1f°)" % want)
	var turret: Node3D = t62.node.find_child("turret", true, false)
	var rig: Array = t62.get("rig", [])
	var fwd: Vector3 = turret.global_transform.basis * Vector3(0, 0, -1)
	check(absf(wrapf(rad_to_deg(atan2(fwd.x, -fwd.z)) - rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)) < 0.5,
		"the turret's barrel points at the target (%d parts rigged)" % rig.size())
	# The target moves: re-aimed within a second.
	tgt.world += Vector3(3000, 0, 0)
	_step(rt, 1.1)
	d = rt._world_of(tgt) - rt._world_of(t62)
	want = wrapf(float(t62.heading) - rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)
	check(absf(float(t62.parts.turret) - want) < 1e-3, "re-aimed after the target moved (%.1f°)" % want)

	tv = await start_mission(222)
	await frames(2)
	rt = tv.runtime
	var scud: Dictionary = _named(rt, "scud3")
	rt._jump(scud, 0, 3)
	_step(rt, 0.1)
	check(is_equal_approx(float(scud.parts.elevation), -1.5), "222 scud3: the launcher starts rising (−1.5°)")
	_step(rt, 9.5)
	check(is_equal_approx(float(scud.parts.elevation), -15.0), "−1.5° a second (%.1f° after 10 ticks)" % scud.parts.elevation)
	_step(rt, 120.0)
	check(is_equal_approx(float(scud.parts.elevation), -90.0), "stops at −90° (upright)")
	var carrier: Node3D = scud.node.find_child("carrier", true, false)
	check(carrier != null and scud.rig.size() >= 2, "carrier and missile parts rigged (%d)" % scud.rig.size())

	tv = await start_mission(233)
	await frames(2)
	rt = tv.runtime
	var boat: Dictionary = _named(rt, "speedboat 3")
	var sat: Dictionary = _named(rt, "satil 1")
	rt._jump(boat, 0, 2)
	_step(rt, 0.1)
	d = rt._world_of(sat) - rt._world_of(boat)
	check(absf(wrapf(float(boat.heading) - rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)) < 1e-3, "233 speedboat 3 faces its target")


func _step(rt, secs: float) -> void:
	for i in int(secs / 0.05):
		rt._process(0.05)
