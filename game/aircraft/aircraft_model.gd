# Generic external model of any IAF aircraft, animated exactly like the original's flight-model
# part callback FUN_0059dd70 (docs/part-animation.md, docs/aircraft.md).
#
# Data: `assets/converted/planes/<plane>/aircraft.json` (written by `iaf-convert aircraft`): the
# parts the original loader keeps (table ids, pivots, hinge axes), the nozzles, stations and other
# helpers. Logic: the per-type rules of the callback, below, keyed by the aircraft type code
# (100 F-16, 110 F-15, 120/200 F-4, 130 Kfir, 140 Lavi, 150 MiG-21, 160 MiG-23, 170 MiG-25,
# 180 MiG-29, 190 Mirage, 210 MiG-17, 220 Tu-22 …). A descriptor may add `part_rules` overrides.
#
# Hinge (FUN_0053c030): the part turns about its OWN origin, axis from the helper frame (X1/X2)
# nearer the model origin toward the farther one, by +θ in our Z-mirrored glTF space.
extends Node3D

const PLANES_DIR := "../assets/converted/planes"

## Ramp limits (rad) and rates (rad/s), constructor FUN_005b72d0 / FUN_005a2a10.
const FLAPS_MAX := 0.29275  # 16.8°
const F16_FLAPS_FACTOR := 0.33  # event 6 on the F-16 (type 100)
const GEAR_MAX := 1.569  # 89.9°, 0 = down
const SPEED_BRAKE_MAX := 0.855  # 49°
const HOOK_MAX := 0.7855  # 45°
const RUDDER_MAX := 0.3926  # 22.5°
const ELEVATOR_MAX := 0.5236  # 30°
const AILERON_MAX := 0.7855  # 45°
const RATE_CONFIG := 0.5  # S+0x300..0x360
const RATE_SURFACE := 0.7  # S+0x380..0x400
## Visibility thresholds of the callback.
const EPS := 1e-5
## Drag chute jitter: a new ±5° angle every 0.1 s while deployed (state 2).
const CHUTE_JITTER := PI / 36.0
const CHUTE_PERIOD := 0.1

## The descriptor (aircraft.json) and the type code whose rules apply.
var desc: Dictionary = {}
var type_code := 100
## The glTF scene and its root frame (parts are its direct children).
var scene: Node3D
var root_frame: Node3D
## name -> {node, id, basis, origin, axis (Vector3 or null)}
var parts := {}
## Afterburner flames (left, right) — only when the model has an engine pair.
var flames: Array = []
## The original's animation ramps (radians).
var ramps := {"flaps": 0.0, "gear": GEAR_MAX, "speed_brake": 0.0, "hook": 0.0,
	"rudder": 0.0, "elevator_l": 0.0, "elevator_r": 0.0, "aileron_l": 0.0, "aileron_r": 0.0}
var _targets := {}
## Last lever positions: like the original's events, a ramp is retargeted only when its lever moves.
var _levers := {}
## Pilot / canopy (ids 0x14..0x17): the flight-model callback hides them on a flown aircraft
## (docs/aircraft.md §2.3; the F-16 then shows a flat cockpit cover). Off = the original.
var crew_visible := false
var _chute_angle := 0.0
var _chute_t := 0.0
var _time := 0.0


## Loads `<planes>/<plane>/aircraft.json` and its glTF. `type` < 0 takes the descriptor's type.
## `on_ground`: the ground-start ramps (gear down, full flaps, speed brake open; FUN_005a2a10).
static func create(plane: String, type := -1, on_ground := false) -> Node3D:
	var dir := ProjectSettings.globalize_path("res://").path_join(PLANES_DIR).path_join(plane).simplify_path()
	var d: Dictionary = load_descriptor(plane)
	if d.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(dir.path_join(d.model), state) != OK:
		return null
	var m: Node3D = load("res://aircraft/aircraft_model.gd").new()
	m.name = plane
	m.setup(doc.generate_scene(state) as Node3D, d, type, on_ground)
	return m


static func load_descriptor(plane: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(PLANES_DIR).path_join(plane).path_join("aircraft.json").simplify_path()
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## Every aircraft of the install (the converter's index): plane folder -> {model, type, label, …}.
static func index() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(PLANES_DIR).path_join("aircraft.json").simplify_path()
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func setup(gltf_scene: Node3D, descriptor: Dictionary, type := -1, on_ground := false) -> void:
	scene = gltf_scene
	desc = descriptor
	type_code = type if type >= 0 else int(desc.get("type", 100))
	add_child(scene)
	root_frame = scene.find_child(str(desc.get("root", "")), true, false) as Node3D
	if root_frame == null:
		root_frame = scene.get_child(0) as Node3D if scene.get_child_count() > 0 else scene
	var info: Dictionary = desc.get("parts", {})
	for n in root_frame.get_children():
		if not n is Node3D:
			continue
		var p = info.get(str(n.name))
		if p == null:
			# Not a part: the loader drops unknown frames and never draws helpers, stations,
			# EndWing, Pilon / Camera, height (FUN_0041c240, FUN_0053c030).
			n.visible = false
			continue
		var axis = null
		if p.axis != null:
			axis = Vector3(p.axis[0], p.axis[1], p.axis[2]).normalized()
		parts[str(n.name)] = {"node": n, "id": int(p.id), "basis": n.transform.basis, "origin": n.transform.origin, "axis": axis}
	# Afterburner: only a model with a complete Engine / Engine1 pair draws flames (clump+0x27c).
	var eng: Dictionary = desc.get("engines", {})
	if int(eng.get("pairs", 0)) > 0:
		for side in ["left", "right"]:
			var pos = eng.get(side)
			if pos == null:
				continue  # the original draws it at the unset 99999 position: nowhere
			var f: MeshInstance3D = load("res://aircraft/afterburner.gd").new()
			f.name = "Afterburner_" + side
			f.nozzle = Vector3(pos[0], pos[1], pos[2])
			f.radius = float(eng.radius)
			f.scale_factor = float(desc.get("scale", 5.0))
			root_frame.add_child(f)
			flames.append(f)
	# Start ramps (FUN_005a2a10): airborne gear up, flaps 0, speed brake 0; ground start gear 0,
	# flaps 0.29275 (the full value, also on the F-16), speed brake 0.855.
	ramps.gear = 0.0 if on_ground else GEAR_MAX
	ramps.flaps = FLAPS_MAX if on_ground else 0.0
	ramps.speed_brake = SPEED_BRAKE_MAX if on_ground else 0.0
	for k in ramps:
		_targets[k] = ramps[k]
	_apply()


## Drives the parts. `input` (all optional, like the flight state dictionary):
##   stick_x (+right), stick_y (+pull), rudder (−1..1), flaps (lever 0..1), gear_down, brakes (speed brake),
##   hook, chute (0 off, 1 armed, 2 deployed, 3 gone), on_ground, gear (the flight model's gear ramp, rad),
##   afterburner (stage 0..2), rpm (0..1.14).
func update(input: Dictionary, delta: float) -> void:
	_time += delta
	var on_ground: bool = input.get("on_ground", false)
	# Events (FUN_0059cf50 / d170 / d370 / d570): retarget only when the lever moves.
	if _lever("flaps", float(input.get("flaps", 0.0))):
		_targets.flaps = float(input.get("flaps", 0.0)) * FLAPS_MAX * (F16_FLAPS_FACTOR if type_code == 100 else 1.0)
	var gear_down: bool = input.get("gear_down", _targets.gear < GEAR_MAX)
	if _lever("gear_down", gear_down):
		_targets.gear = 0.0 if gear_down else GEAR_MAX
	var brakes: bool = input.get("brakes", false)
	if _lever("brakes", brakes):
		_targets.speed_brake = SPEED_BRAKE_MAX if brakes else 0.0
	var hook: bool = input.get("hook", false)
	if _lever("hook", hook):
		_targets.hook = HOOK_MAX if hook else 0.0
	var sr: float = input.get("stick_x", 0.0)
	var sp: float = input.get("stick_y", 0.0)
	# Rudder (FUN_0059c910 / FUN_0059d770): the pedals in the air, the stick roll on the ground.
	_targets.rudder = (-sr * RUDDER_MAX) if on_ground else float(input.get("rudder", 0.0)) * RUDDER_MAX
	# Ailerons (FUN_0059d770): airborne only, not on the deltas (their elevons come from the mixer).
	var delta_wing := type_code in [130, 190]
	if not on_ground and not delta_wing:
		_targets.aileron_l = -AILERON_MAX * sr
		_targets.aileron_r = -AILERON_MAX * sr
	# Pitch mixer FUN_0059da00.
	var a := AILERON_MAX if delta_wing else ELEVATOR_MAX
	var f := 0.5 if type_code in [110, 190, 130] else (0.65 if type_code == 100 else 1.0)
	var m := (1.0 - f) * sr * a if type_code in [110, 100, 190, 130] else 0.0
	var l := sp * f * a - m
	var r := -sp * f * a - m
	if type_code in [120, 200]:
		l *= 0.6
		r *= 0.6
	if delta_wing:
		_targets.aileron_l = l
		_targets.aileron_r = r
	else:
		_targets.elevator_l = l
		_targets.elevator_r = r
	for k in ramps:
		var rate := RATE_SURFACE if k in ["rudder", "elevator_l", "elevator_r", "aileron_l", "aileron_r"] else RATE_CONFIG
		ramps[k] = move_toward(ramps[k], _targets[k], rate * delta)
	if input.has("gear"):
		ramps.gear = float(input.gear)  # the flight model's own gear ramp (exact timing)
	# Drag chute (FUN_0059ff30): jitter while deployed.
	var chute: int = input.get("chute", 0)
	if chute == 2 and _time - _chute_t > CHUTE_PERIOD:
		_chute_angle = randf_range(-CHUTE_JITTER, CHUTE_JITTER)
		_chute_t = _time
	_chute_state = chute
	# Afterburner level (FUN_005a8d40): 75 + 12.5·stage when lit, else RPM·100·0.74 (never drawn).
	var stage: int = input.get("afterburner", 0)
	var level := int(75.0 + 12.5 * stage) if stage > 0 else int(clampf(float(input.get("rpm", 0.0)), 0.0, 1.0) * 100.0 * 0.74)
	for fl in flames:
		fl.level = level
	_apply()


var _chute_state := 0


## Ends every ramp at its target at once (posed captures and tests).
func settle() -> void:
	for k in ramps:
		ramps[k] = _targets[k]
	_apply()


func _lever(key: String, value) -> bool:
	if not _levers.has(key):
		_levers[key] = value  # the first call only records the start position (no event)
		return false
	if _levers[key] == value:
		return false
	_levers[key] = value
	return true


## Angle θ and visibility of part `id` (FUN_0059dd70), from the current ramps.
func part_pose(id: int) -> Array:
	var t := type_code
	var g: float = ramps.gear
	var gear_out := absf(g - GEAR_MAX) >= EPS
	match id:
		1:  # AilerL (the F-16 flaperons droop with the flaps)
			return [ramps.aileron_l - (ramps.flaps if t == 100 else 0.0), true]
		2:  # AilerR
			return [ramps.aileron_r + (ramps.flaps if t == 100 else 0.0), true]
		5, 6:  # RuddeL, Rudde
			return [ramps.rudder, true]
		7:  # FlapL
			return [-ramps.flaps, true]
		8:  # FlapR
			return [ramps.flaps, true]
		9, 10:  # SpdbrU / SpdbrD
			var sb: float = ramps.speed_brake * (1.0 if id == 9 else -1.0)
			if t in [110, 140, 160, 190]:
				sb = -sb
			return [sb, t == 100 or absf(sb) >= EPS]
		11:  # ElevaL
			return [-ramps.elevator_l if t == 140 else ramps.elevator_l, true]
		12:  # ElevaR
			return [-ramps.elevator_r if t == 140 else ramps.elevator_r, true]
		13:  # ElevoL
			return [ramps.aileron_l, true]
		14:  # ElevoR
			return [ramps.aileron_r, true]
		15:  # LdgL
			if t == 180:
				return [-g, g < 0.8889 * GEAR_MAX]
			if t == 190:
				return [g, g < 0.7778 * GEAR_MAX]
			return [-g if t == 110 else g, gear_out]
		16:  # LdgR
			if t == 180:
				return [g, g < 0.8889 * GEAR_MAX]
			if t == 190:
				return [-g, g < 0.7778 * GEAR_MAX]
			return [g if t == 110 else -g, gear_out]
		17:  # LdgF
			if t == 180:
				return [minf(g, 0.87264), gear_out]
			return [g if t in [110, 130, 140, 160] else -g, gear_out]
		18:  # LdgDr: never rotates, hidden once the gear is fully up
			return [0.0, gear_out]
		19:  # Hook
			return [ramps.hook, absf(ramps.hook) >= EPS]
		0x14, 0x15, 0x16, 0x17:  # pilot, pilotB, canopy, canopyB
			return [0.0, crew_visible]
		0x27:  # Parach
			return [_chute_angle, _chute_state == 2]
		0x1d, 0x1e, 0x1f, 0x20:  # RotorA..D
			# Helicopters (type −1) are not flown by the flight model; their mover's callback is not
			# decoded (UNCERTAIN): the rotors are shown static.
			return [0.0, t < 0]
	# Canards, turret, radar, wheels, engines…: not drawn on a flown aircraft.
	return [0.0, false]


func _apply() -> void:
	var overrides: Dictionary = desc.get("part_rules", {})
	for name in parts:
		var p: Dictionary = parts[name]
		var pose := part_pose(p.id)
		var o = overrides.get(name)
		if o is Dictionary:
			pose[0] *= float(o.get("sign", 1.0))
			if o.has("visible"):
				pose[1] = bool(o.visible)
		p.node.visible = pose[1]
		var b: Basis = p.basis
		if p.axis != null and pose[1]:
			b = Basis(p.axis, pose[0]) * b
		p.node.transform = Transform3D(b, p.origin)


## True while any afterburner flame is drawn.
func flame_lit() -> bool:
	for f in flames:
		if f.lit():
			return true
	return false


func part_node(name: String) -> Node3D:
	return parts[name].node if parts.has(name) else null
