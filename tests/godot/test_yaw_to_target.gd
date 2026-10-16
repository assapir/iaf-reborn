# Script motion op 11 Yaw to target (docs/mission-runtime.md §4, docs/part-animation.md "Vehicles"): 231's T-62 turns
# its turret to the bearing of its target (re-aimed every 1 s), 222's Scud launcher rises 1.5° a second to 90°, 233's
# speedboat (no turret) faces its target. The list entry is jumped to directly; the runtime's clock is stepped.
# Vehicle parts (FUN_005c5460): 212's SA-6 radar dish steps 0.4° every 2 s; its helicopters' rotors spin 10° per rotor
# part per frame; a release hides the Scud's Missile part (FUN_004ab810).
extends "res://../tests/godot/base.gd"

const VehicleParts := preload("res://mission/vehicle_parts.gd")


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
	var missile: Node3D = scud.node.find_child("missile", true, false)
	check(missile != null and missile.visible, "the Scud's missile part is shown")
	scud.parts["missile_gone"] = true  # what the release sets (combat.gd _release)
	tv.mission_entity_parts(scud)
	check(not missile.visible, "a release hides it")

	tv = await start_mission(233)
	await frames(2)
	rt = tv.runtime
	var boat: Dictionary = _named(rt, "speedboat 3")
	var sat: Dictionary = _named(rt, "satil 1")
	rt._jump(boat, 0, 2)
	_step(rt, 0.1)
	d = rt._world_of(sat) - rt._world_of(boat)
	check(absf(wrapf(float(boat.heading) - rad_to_deg(atan2(d.x, d.y)), -180.0, 180.0)) < 1e-3, "233 speedboat 3 faces its target")

	tv = await start_mission(212)
	await frames(2)
	rt = tv.runtime
	var dish: Dictionary = {}
	var heli: Dictionary = {}
	for e in tv._dishes:
		if dish.is_empty() and VehicleParts.has_radar(e.rig):
			dish = e
		if heli.is_empty() and VehicleParts.rotor_count(e.rig) > 0:
			heli = e
	check(not dish.is_empty(), "212: a unit with a Radar part (%s)" % dish.get("name", "-"))
	if not dish.is_empty():
		var a0 := float(dish.parts.get("radar", 0.0))
		var t0: float = rt.now
		_step(rt, 2.1)
		await frames(1)
		check(is_equal_approx(float(dish.parts.radar) - a0, 0.4), "the dish stepped 0.4° in 2 s (%.1f → %.1f)" % [a0, dish.parts.radar])
		_step(rt, 1.0)
		await frames(1)
		check(is_equal_approx(float(dish.parts.radar) - a0, 0.4), "and not again within the next second")
		check(rt.now > t0, "the clock ran")
	check(not heli.is_empty(), "212: a helicopter with rotors (%s, %d rotor parts)" % [heli.get("name", "-"), VehicleParts.rotor_count(heli.get("rig", []))])
	if not heli.is_empty():
		var rotor: Node3D = heli.node.find_child("rotora", true, false)
		var b0: Basis = rotor.transform.basis
		var r0 := float(heli.parts.get("rotor", 0.0))
		await frames(1)
		var n := VehicleParts.rotor_count(heli.rig)
		check(is_equal_approx(fposmod(float(heli.parts.rotor) - r0, 360.0), fposmod(10.0 * n, 360.0)) or float(heli.parts.rotor) < r0,
			"the rotors' angle +10° per rotor part a frame (%.0f → %.0f)" % [r0, heli.parts.rotor])
		check(not rotor.transform.basis.is_equal_approx(b0), "the main rotor turned")


func _step(rt, secs: float) -> void:
	for i in int(secs / 0.05):
		rt._process(0.05)
