# The F-35I model (docs/f35i.md, docs/part-animation.md §2.2): with the gear up the nose and main gear doors are
# hidden, the shut nose doors shown, the bay doors closed and no body geometry hangs under the nose; with the gear
# down the open doors show. Its pylons are hidden until a station is loaded. Rolling wheels: on the ground the
# wheels turn by ground speed / radius; in the air, or with the switch off, they hold.
extends "res://../tests/godot/base.gd"

var AircraftModel: GDScript


func run() -> void:
	AircraftModel = load("res://aircraft/aircraft_model.gd")
	var air: Node3D = AircraftModel.create("f35i", 1000, false)
	root.add_child(air)
	air.update({}, 0.1)
	for n in ["LdgDr", "LdgF", "LdgL", "LdgR"]:
		check(not air.part_node(n).visible, "gear up: %s hidden" % n)
	var shut: Node3D = air.part_node("LdgDrUp")
	check(shut != null and shut.visible, "gear up: the shut nose doors shown")
	for n in ["BayLi", "BayLo", "BayRi", "BayRo"]:
		var p: Dictionary = air.parts[n]
		check(p.node.visible and p.node.transform.basis.is_equal_approx(p.basis), "bay door %s shut" % n)
	check(is_zero_approx(air.bay_fraction()), "bay doors shut")
	var low := _lowest_under_nose(air.root_frame)
	check(low > -0.75, "nothing on the body hangs under the nose (lowest y %.2f m)" % low)
	for letter in "ABHI":
		var py := air.root_frame.get_node_or_null("Pylon" + letter) as Node3D
		check(py != null and not py.visible, "pylon %s present and hidden while its station is empty" % letter)

	var ground: Node3D = AircraftModel.create("f35i", 1000, true)
	root.add_child(ground)
	ground.update({"on_ground": true, "gear_down": true}, 0.0)
	check(ground.part_node("LdgDr").visible and shut != null and not ground.part_node("LdgDrUp").visible,
			"gear down: the open doors shown, the shut ones hidden")
	check(ground.wheels.size() == 3, "three wheels ride on the legs (%d)" % ground.wheels.size())
	var main: Dictionary = {}
	for w in ground.wheels:
		if str(w.node.name) == "WheelsB":
			main = w
	check(not main.is_empty() and absf(main.radius - 0.25) < 0.02, "main wheel radius from its mesh (%.3f m)" % main.get("radius", 0.0))
	Settings().rolling_wheels = false
	ground.update({"on_ground": true, "gear_down": true, "ground_speed": 20.0}, 0.5)
	check(is_zero_approx(ground.wheel_roll), "switch off: the wheels stand still (original)")
	Settings().rolling_wheels = true
	ground.update({"on_ground": true, "gear_down": true, "ground_speed": 20.0}, 0.5)
	check(is_equal_approx(ground.wheel_roll, -10.0), "on the ground: 20 m/s for 0.5 s rolls 10 m (%.2f)" % ground.wheel_roll)
	var want: Basis = Basis(Vector3.RIGHT, fmod(-10.0 / float(main.radius), TAU)) * main.basis
	check(main.node.transform.basis.is_equal_approx(want), "the main wheel turned by distance / radius about its axle")
	# Rolling forward (nose -Z): the wheel's bottom moves aft (+Z) relative to its axle.
	ground.wheel_roll = 0.0
	ground.update({"on_ground": true, "gear_down": true, "ground_speed": 1.0}, 0.05)
	var bottom: Vector3 = main.node.transform.basis * Vector3(0, -main.radius, 0)
	check(bottom.z > 0.0, "rolling forward turns the wheel's bottom aft (%.4f)" % bottom.z)
	var held: float = ground.wheel_roll
	ground.update({"on_ground": false, "gear_down": true, "ground_speed": 80.0}, 0.5)
	check(is_equal_approx(ground.wheel_roll, held), "in the air the wheels hold")
	Settings().rolling_wheels = false
	air.free()
	ground.free()


## The lowest visible point (m, model frame) of the body's own meshes over the nose bay (|x| < 0.4, z −6.5..−4.5).
func _lowest_under_nose(frame: Node3D) -> float:
	var low := INF
	for mi: MeshInstance3D in frame.find_children("*", "MeshInstance3D", false, false) + ([frame] if frame is MeshInstance3D else []):
		if mi.mesh == null or not mi.visible:
			continue
		var xf := frame.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := xf * v
				if absf(p.x) < 0.4 and p.z > -6.5 and p.z < -4.5:
					low = minf(low, p.y)
	return low
