# Animates the moving parts of a converted IAF aircraft model exactly like the original
# (docs/part-animation.md, flight-model callback FUN_0059dd70). F-16 rules for now.
#
# Hinge (FUN_0053c030): axis from the helper frame (`X1`/`X2`) nearer the model origin toward
# the farther one; the part turns about its OWN origin by +θ in our Z-mirrored glTF space.
extends Node3D

const GEAR_MAX := 1.569  # rad (89.9°), 0 = down
const FLAPS_MAX := 0.29275  # rad (16.8°)
const F16_FLAPS_FACTOR := 0.33  # the F-16 droops its flaperons by a third of that
const SPEED_BRAKE_MAX := 0.855  # rad (49°)
const HOOK_MAX := 0.7855  # rad (45°)
const RUDDER_MAX := 0.3926  # rad (22.5°)
const ELEVATOR_MAX := 0.5236  # rad (30°)
const AILERON_MAX := 0.7855  # rad (45°)
## F-16 pitch mixer: share of the stabilator travel used for pitch (the rest mixes in roll).
const F16_PITCH_SHARE := 0.65
## Ramp rates, rad/s: configuration items / control surfaces.
const RATE_CONFIG := 0.5
const RATE_SURFACE := 0.7

## Parts that exist on the model: name -> {node, basis, origin, axis}.
var parts := {}
## Current values of the original's animation ramps (radians).
var ramps := {"flaps": 0.0, "gear": GEAR_MAX, "speed_brake": 0.0, "hook": 0.0,
	"rudder": 0.0, "elevator_l": 0.0, "elevator_r": 0.0, "aileron": 0.0}


## `scene` is the generated glTF scene; call once after loading.
func setup(scene: Node3D, gear_down: bool) -> void:
	add_child(scene)
	ramps.gear = 0.0 if gear_down else GEAR_MAX
	var by_name := {}
	for n in scene.find_children("*", "Node3D", true, false):
		by_name[str(n.name).to_lower()] = n
	for n in scene.find_children("*", "Node3D", true, false):
		var name := str(n.name)
		var h1: Node3D = by_name.get((name + "1").to_lower())
		var h2: Node3D = by_name.get((name + "2").to_lower())
		if h1 == null or h2 == null or n.get_meta("extras", {}).get("iaf_helper", false):
			continue
		var p1 := h1.position
		var p2 := h2.position
		var axis := (p2 - p1) if p1.length() <= p2.length() else (p1 - p2)
		if axis.length() < 1e-6:
			continue
		parts[name] = {"node": n, "basis": n.transform.basis, "origin": n.transform.origin, "axis": axis.normalized()}


func _pose(name: String, theta: float, show := true) -> void:
	if not parts.has(name):
		return
	var p: Dictionary = parts[name]
	p.node.visible = show
	p.node.transform = Transform3D(Basis(p.axis, theta) * p.basis, p.origin)


func _ramp(key: String, target: float, rate: float, delta: float) -> float:
	ramps[key] = move_toward(ramps[key], target, rate * delta)
	return ramps[key]


## Drive the parts from the pilot's controls (stick −1..1, pull +; rudder −1..1; flaps 0..1).
func animate(stick: Vector2, rudder: float, flaps: float, gear_down: bool, brakes: bool, delta: float) -> void:
	var fl := _ramp("flaps", FLAPS_MAX * F16_FLAPS_FACTOR * flaps, RATE_CONFIG, delta)
	var g := _ramp("gear", 0.0 if gear_down else GEAR_MAX, RATE_CONFIG, delta)
	var sb := _ramp("speed_brake", SPEED_BRAKE_MAX if brakes else 0.0, RATE_CONFIG, delta)
	var hook := _ramp("hook", 0.0, RATE_CONFIG, delta)
	var ru := _ramp("rudder", rudder * RUDDER_MAX, RATE_SURFACE, delta)
	# Pitch mixer (FUN_0059da00, F-16): tailerons share pitch and roll.
	var roll_mix := (1.0 - F16_PITCH_SHARE) * stick.x * ELEVATOR_MAX
	var el := _ramp("elevator_l", stick.y * F16_PITCH_SHARE * ELEVATOR_MAX - roll_mix, RATE_SURFACE, delta)
	var er := _ramp("elevator_r", -stick.y * F16_PITCH_SHARE * ELEVATOR_MAX - roll_mix, RATE_SURFACE, delta)
	var ail := _ramp("aileron", -AILERON_MAX * stick.x, RATE_SURFACE, delta)

	_pose("AilerL", ail - fl)  # flaperons: roll plus flap droop
	_pose("AilerR", ail + fl)
	_pose("RuddeL", ru)
	_pose("ElevaL", el)
	_pose("ElevaR", er)
	_pose("SpdbrU", sb)
	_pose("SpdbrD", -sb)
	var gear_out := absf(g - GEAR_MAX) >= 1e-5
	_pose("LdgL", g, gear_out)
	_pose("LdgR", -g, gear_out)
	_pose("LdgF", -g, gear_out)
	# The gear doors never rotate; they are hidden once the gear is fully up.
	for n in find_children("LdgDr", "Node3D", true, false):
		n.visible = gear_out
	_pose("Hook", hook, absf(hook) >= 1e-5)
