# Generic aircraft model (docs/aircraft.md): every converted aircraft loads with its descriptor;
# the F-16 gear retracts in the original 3.14 s and the legs vanish when fully up; flaperons droop;
# the speed brakes open; the afterburner flame is drawn only at an afterburner stage; the flown
# F-16 in a mission carries the model and follows the flight model's gear ramp.
extends "res://../tests/godot/base.gd"

## Loaded at run time: scripts that use the Settings autoload do not compile before it exists.
var AircraftModel: GDScript


func run() -> void:
	AircraftModel = load("res://aircraft/aircraft_model.gd")
	var idx: Dictionary = AircraftModel.index()
	check(idx.size() >= 8, "aircraft index lists every plane (%d)" % idx.size())
	var bad := []
	for plane in idx:
		var m: Node3D = AircraftModel.create(plane)
		if m == null or m.desc.get("format", 0) != 1:
			bad.append(plane)
			continue
		root.add_child(m)
		m.update({"gear_down": true, "afterburner": 2}, 0.1)
		m.free()
	check(bad.is_empty(), "all aircraft descriptors and models load (failed: %s)" % [bad])

	var f16: Node3D = AircraftModel.create("f16", 100, false)
	root.add_child(f16)
	check(f16.parts.has("LdgL") and f16.parts.has("AilerL") and f16.flames.size() == 1, "F-16 parts and one nozzle")
	var leg: Node3D = f16.part_node("LdgL")
	check(not leg.visible, "airborne start: gear up, legs hidden")
	# Lower the gear: an event, then 0.5 rad/s.
	f16.update({"gear_down": false}, 0.0)
	f16.update({"gear_down": true}, 0.0)
	var t := 0.0
	while t < 3.3:
		f16.update({"gear_down": true}, 0.1)
		t += 0.1
	var down_basis := leg.transform.basis
	check(leg.visible and absf(f16.ramps.gear) < 0.05, "gear down after 3.3 s (ramp %.3f)" % f16.ramps.gear)
	f16.update({"gear_down": false}, 1.0)
	check(leg.visible and not leg.transform.basis.is_equal_approx(down_basis), "retracting moves the leg")
	f16.update({"gear_down": false}, 1.0)
	f16.update({"gear_down": false}, 1.2)
	check(not leg.visible, "legs and doors hidden once fully up (3.14 s)")
	check(not f16.part_node("LdgDr").visible, "doors hidden with the gear up")
	# Flaps: the F-16 flaperons droop by a third of 16.8°.
	f16.update({"flaps": 1.0}, 0.0)
	f16.settle()
	check(absf(f16.ramps.flaps - 0.29275 * 0.33) < 1e-4, "F-16 flap droop 0.33 x 0.29275")
	var pa: Array = f16.part_pose(1)
	check(absf(pa[0] + 0.29275 * 0.33) < 1e-4, "left flaperon = aileron - flaps")
	f16.update({"brakes": true}, 0.0)
	f16.settle()
	check(absf(f16.part_pose(9)[0] - 0.855) < 1e-4 and absf(f16.part_pose(10)[0] + 0.855) < 1e-4, "speed brakes open 49 degrees")
	# Afterburner: only at an AB stage; military power (RPM 100 %) draws nothing (level 74).
	f16.update({"afterburner": 0, "rpm": 1.0}, 0.1)
	await process_frame
	check(not f16.flame_lit(), "no flame at military power")
	f16.update({"afterburner": 1}, 0.1)
	await process_frame
	check(f16.flame_lit() and f16.flames[0].level == 87, "flame at AB stage 1 (level 87)")
	f16.update({"afterburner": 0}, 0.1)
	check(not f16.flame_lit(), "flame out after AB")
	check(f16.part_node("Canopy").visible, "canopy drawn from outside (crew object 0x53d180)")
	f16.free()

	# Per-type rule: the MiG-29 main legs vanish at 8/9 of the travel.
	var mig: Node3D = AircraftModel.create("mig29", -1, true)
	root.add_child(mig)
	check(mig.type_code == 180 and mig.flames.size() == 2, "MiG-29: type 180, two nozzles")
	mig.update({"gear_down": true}, 0.0)
	mig.update({"gear_down": false}, 2.85)
	check(not mig.part_node("LdgL").visible and mig.part_node("LdgF").visible, "MiG-29 main legs gone at 8/9, nose leg still out")
	mig.free()

	# In a mission: the F-16 follows the flight model's gear ramp.
	var tv = await start_mission(311)
	check(tv.aircraft != null and tv.aircraft.desc.name == "f16", "mission jet is the generic F-16 model")
	await frames(3)
	check(absf(tv.aircraft.ramps.gear - tv.flight.state().gear) < 1e-4, "gear pose follows the flight model")
