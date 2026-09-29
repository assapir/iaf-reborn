# Animates the moving parts of a converted IAF aircraft model.
#
# Each moving frame `X` in the original model has two helper frames `X1`, `X2`; their
# positions define the hinge axis (converted as empty nodes, see docs/formats/x.md).
# A part is rotated about that axis through `X1`. The models are stored with the gear
# down and everything neutral, so 0° is the rest pose.
extends Node3D

## Part -> [helper A, helper B, sign]. The sign makes positive angles mean: trailing edge
## down (flaperons, stabilators), trailing edge right (rudder), open (brakes), retracted (gear).
const PARTS := {
	"AilerL": ["AilerL1", "AilerL2", 1.0],
	"AilerR": ["AilerR1", "AilerR2", 1.0],
	"ElevaL": ["ElevaL1", "ElevaL2", -1.0],
	"ElevaR": ["ElevaR1", "ElevaR2", 1.0],
	"RuddeL": ["RuddeL1", "RuddeL2", 1.0],
	"SpdbrU": ["SpdbrU1", "SpdbrU2", 1.0],
	"SpdbrD": ["SpdbrD1", "SpdbrD2", 1.0],
	"LdgF": ["LdgF1", "LdgF2", -1.0],
	"LdgL": ["LdgL1", "LdgL2", 1.0],
	"LdgR": ["LdgR1", "LdgR2", -1.0],
	"Canopy": ["Canopy1", "Canopy2", 1.0],
	"Hook": ["Hook1", "Hook2", 1.0],
}

## Deflection limits, degrees (F-16 values where known).
const FLAPERON_ROLL := 20.0
const FLAPERON_FLAPS := 20.0
const STAB_PITCH := 25.0
const STAB_ROLL := 5.0
const RUDDER := 30.0
const SPEED_BRAKE := 60.0
const GEAR_NOSE := 105.0
const GEAR_MAIN := 65.0  # the 1998 gear bays are shallow; more pokes through the skin
## Actuator rates, degrees per second.
const SURFACE_RATE := 60.0
const BRAKE_RATE := 60.0
const GEAR_TIME := 3.0  # seconds for full travel

var parts := {}  # name -> {node, base, pivot, axis, sign, angle}
var gear_pos := 1.0  # 1 = down, 0 = up
var brake_pos := 0.0


## `scene` is the generated glTF scene; call once after loading.
func setup(scene: Node3D) -> void:
	add_child(scene)
	var by_name := {}
	for n in scene.find_children("*", "Node3D", true, false):
		by_name[str(n.name)] = n
	for part in PARTS:
		var cfg: Array = PARTS[part]
		if not (by_name.has(part) and by_name.has(cfg[0]) and by_name.has(cfg[1])):
			continue
		var node: Node3D = by_name[part]
		var a: Vector3 = by_name[cfg[0]].position
		var b: Vector3 = by_name[cfg[1]].position
		if a.distance_to(b) < 1e-4:
			continue
		parts[part] = {"node": node, "base": node.transform, "pivot": a, "axis": (b - a).normalized(), "sign": cfg[2], "angle": 0.0}


func _set_angle(part: String, deg: float, rate: float, delta: float) -> void:
	if not parts.has(part):
		return
	var p: Dictionary = parts[part]
	p.angle = move_toward(p.angle, deg, rate * delta) if delta > 0.0 else deg
	var basis := Basis(p.axis, deg_to_rad(p.angle * p.sign))
	var hinge := Transform3D(basis, p.pivot - basis * p.pivot)
	p.node.transform = hinge * p.base


## Drive the parts from the controls (stick x/y −1..1, pull positive; rudder −1..1; flaps 0..1).
func animate(stick: Vector2, rudder: float, flaps: float, gear_down: bool, brakes: bool, delta: float) -> void:
	# Flaperons: roll right = right trailing edge up, left down; flaps droop both.
	var roll := stick.x * FLAPERON_ROLL
	var droop := flaps * FLAPERON_FLAPS
	_set_angle("AilerL", clamp(droop + roll, -FLAPERON_ROLL, FLAPERON_ROLL + FLAPERON_FLAPS), SURFACE_RATE, delta)
	_set_angle("AilerR", clamp(droop - roll, -FLAPERON_ROLL, FLAPERON_ROLL + FLAPERON_FLAPS), SURFACE_RATE, delta)
	# Stabilators: pull = trailing edge up (nose up), plus a little differential for roll.
	_set_angle("ElevaL", -stick.y * STAB_PITCH + stick.x * STAB_ROLL, SURFACE_RATE, delta)
	_set_angle("ElevaR", -stick.y * STAB_PITCH - stick.x * STAB_ROLL, SURFACE_RATE, delta)
	_set_angle("RuddeL", rudder * RUDDER, SURFACE_RATE, delta)
	brake_pos = move_toward(brake_pos, 1.0 if brakes else 0.0, BRAKE_RATE / SPEED_BRAKE * delta)
	_set_angle("SpdbrU", brake_pos * SPEED_BRAKE, 1e9, 0.0)
	_set_angle("SpdbrD", brake_pos * SPEED_BRAKE, 1e9, 0.0)
	gear_pos = move_toward(gear_pos, 1.0 if gear_down else 0.0, delta / GEAR_TIME)
	var up := 1.0 - gear_pos
	_set_angle("LdgF", up * GEAR_NOSE, 1e9, 0.0)
	_set_angle("LdgL", up * GEAR_MAIN, 1e9, 0.0)
	_set_angle("LdgR", up * GEAR_MAIN, 1e9, 0.0)
	# Gear door: stays visible while any gear is out.
	for n in find_children("LdgDr", "Node3D", true, false):
		n.visible = gear_pos > 0.02
