# Ground vehicles' moving parts: the vehicle part callback FUN_005c5460 (part record entity+0x3c, FUN_005c5400) for
# Turret (id 0x18, angle part+0xc), Carrier (0x1a, +0x10), Launcher (0x1b, +0x14) and Missile (0x1c, +0x10), each
# turned about its hinge (the X1 / X2 helpers `<name>1` / `<name>2`, as the aircraft parts, FUN_0053da00: the axis
# from the helper nearer the model origin toward the farther one, +θ). Angles in degrees, wrapped to ±180
# (FUN_00459bd0). Script motion op 11 writes them (mission_runtime.gd); the Radar dish (0x19, +0x18) steps 0.4° every
# 2.0 s (`step_radar`); RotorA–D (0x1d–0x20, +0x20) +10° per part per frame (`step_rotors`, the same rule as the
# aircraft crew object's +0x10); a release hides the Missile part (+8 = 0, FUN_004ab810). Wheels (+1° a call): no
# shipped vehicle model has Wheels frames.
extends RefCounted

## Part frame name → the angle it reads.
const FIELDS := {"turret": "turret", "carrier": "elevation", "missile": "elevation", "launcher": "launcher", "radar": "radar",
	"rotora": "rotor", "rotorb": "rotor", "rotorc": "rotor", "rotord": "rotor"}
## The rotors' step (0x612a64 / 0x612a6c): +10° per part per draw call, one angle for all of them, back to 0 past 360°.
const ROTOR_STEP := 10.0
## The Radar part's step (0x612a60 / 0x612a5c): +0.4° once 2.0 s have passed since the last step.
const RADAR_STEP := 0.4
const RADAR_PERIOD := 2.0


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
			"field": field, "missile": String(n.name).to_lower() == "missile"})
	return out


## Poses the rig from `angles` {turret, elevation, launcher} (degrees; missing = 0).
static func apply(parts: Array, angles: Dictionary) -> void:
	for p in parts:
		var theta := deg_to_rad(wrapf(float(angles.get(p.field, 0.0)), -180.0, 180.0))
		p.node.transform = Transform3D(Basis(p.axis, theta) * p.basis, p.origin)
		if p.missile:
			p.node.visible = not angles.get("missile_gone", false)


## The rig's rotor parts (0 without).
static func rotor_count(parts: Array) -> int:
	return parts.filter(func(p): return p.field == "rotor").size()


## One frame of the rotors (FUN_005c5460 cases 0x1d–0x20): each rotor part's call adds 10° to the one angle
## (`angles.rotor`), which goes back to 0 once above 360° (frame-rate dependent, as the original).
static func step_rotors(angles: Dictionary, count: int) -> void:
	var a := float(angles.get("rotor", 0.0))
	for i in count:
		a += ROTOR_STEP
		if a > 360.0:
			a = 0.0
	angles["rotor"] = a


## Whether a rig has a Radar part (its dish steps with `step_radar`).
static func has_radar(parts: Array) -> bool:
	return parts.any(func(p): return p.field == "radar")


## The Radar part's step (FUN_005c5460 case 0x19): at `now` (sim s), +0.4° once 2.0 s passed since the last step
## (`angles.radar_t`, 0 at first: the first call steps). True when it stepped.
static func step_radar(angles: Dictionary, now: float) -> bool:
	if now - float(angles.get("radar_t", 0.0)) < RADAR_PERIOD:
		return false
	angles["radar_t"] = now
	angles["radar"] = float(angles.get("radar", 0.0)) + RADAR_STEP
	return true
