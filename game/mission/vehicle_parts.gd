# Ground vehicles' moving parts: the vehicle part callback FUN_005c5460 (part record entity+0x3c, FUN_005c5400) for
# Turret (id 0x18, angle part+0xc), Carrier (0x1a, +0x10), Launcher (0x1b, +0x14) and Missile (0x1c, +0x10), each
# turned about its hinge (the X1 / X2 helpers `<name>1` / `<name>2`, as the aircraft parts, FUN_0053da00: the axis
# from the helper nearer the model origin toward the farther one, +θ). Angles in degrees, wrapped to ±180
# (FUN_00459bd0). Script motion op 11 writes them (mission_runtime.gd). Not built: the Radar dish's step (0.4° every
# 2.0 s, +0x18), rotors, wheels.
extends RefCounted

## Part frame name → the angle it reads.
const FIELDS := {"turret": "turret", "carrier": "elevation", "missile": "elevation", "launcher": "launcher"}


## The parts of a vehicle model and its LOD children: [{node, basis, origin, axis, field}].
static func rig(model: Node3D) -> Array:
	var out := []
	if model == null:
		return out
	for n in model.find_children("*", "Node3D", true, false):
		var field = FIELDS.get(String(n.name).to_lower())
		var parent := n.get_parent() as Node3D
		if field == null or parent == null:
			continue
		var a := parent.get_node_or_null(NodePath(String(n.name) + "1")) as Node3D
		var b := parent.get_node_or_null(NodePath(String(n.name) + "2")) as Node3D
		if a == null or b == null:
			continue
		var near := a.position if a.position.length() <= b.position.length() else b.position
		var far := b.position if near == a.position else a.position
		if (far - near).length() < 1e-6:
			continue
		out.append({"node": n, "basis": n.transform.basis, "origin": n.transform.origin, "axis": (far - near).normalized(),
			"field": field})
	return out


## Poses the rig from `angles` {turret, elevation, launcher} (degrees; missing = 0).
static func apply(parts: Array, angles: Dictionary) -> void:
	for p in parts:
		var theta := deg_to_rad(wrapf(float(angles.get(p.field, 0.0)), -180.0, 180.0))
		p.node.transform = Transform3D(Basis(p.axis, theta) * p.basis, p.origin)
