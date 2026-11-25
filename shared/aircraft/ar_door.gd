## The air refuelling receptacle's door on a jet's model (ours; modern-iaf/docs/research/air-refuelling.md §5, §6), as
## its aircraft definition's `receptacle_door` says: shut, nothing is drawn (the model's own skin); open, a dark opening
## on the spine at the receptacle and the door's leaf. `slipway` (the F-16's, T.O. 1F-16A-1 p. 1-79): the door turns
## its aft end down into the fuselage, the leaf the slipway ahead of the receptacle; the models have no cut there, so
## it is drawn flush on the spine. `up` (the F-35's: its doors open upward, second-hand): one leaf up about its aft
## edge (inferred). The sizes are inferred.
extends RefCounted

## The opening's width and length (m); the slipway leaf's share of its length, from its forward edge; the `up` leaf's
## angle from shut (deg: past upright, clear of the boom).
const SIZE := Vector2(0.34, 0.62)
const LEAF_SHARE := 0.7
const UP_DEG := 100.0
const DARK := Color(0.03, 0.03, 0.035)
const LEAF := Color(0.42, 0.43, 0.45)
const UP_LEAF := Color(0.2, 0.21, 0.22)  # the F-35's dark grey skin (its model's)


## The door on `model` (a jet's model, its frame the jet's: x right, y up, -z forward) of the jet `airframe`
## (Settings.airframe: `receptacle` forward, right, up m) open or shut; nothing for a jet without a receptacle.
static func set_open(model: Node3D, airframe: Dictionary, open: bool) -> void:
	var r: Array = airframe.get("receptacle", [])
	if model == null or r.size() != 3:
		return
	var d := model.get_node_or_null("ArDoor") as Node3D
	if d == null:
		if not open:
			return
		d = _build(Vector3(float(r[1]), float(r[2]), -float(r[0])), String(airframe.get("receptacle_door", "slipway")))
		model.add_child(d)
	d.visible = open


static func _build(at: Vector3, kind: String) -> Node3D:
	var d := Node3D.new()
	d.name = "ArDoor"
	d.position = at
	var hole := _box(Vector3(SIZE.x, 0.03, SIZE.y), DARK)
	d.add_child(hole)
	if kind == "up":  # the opening round the receptacle, the leaf up about its aft edge
		hole.position = Vector3(0.0, -0.012, 0.0)
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, 0.004, SIZE.y / 2.0)
		hinge.rotation.x = deg_to_rad(UP_DEG)
		var leaf := _box(Vector3(SIZE.x - 0.02, 0.025, SIZE.y - 0.02), UP_LEAF)
		leaf.position = Vector3(0.0, 0.0, -SIZE.y / 2.0)
		hinge.add_child(leaf)
		d.add_child(hinge)
		return d
	# The slipway: the opening ahead of the receptacle, the leaf in its forward part.
	hole.position = Vector3(0.0, -0.012, -SIZE.y / 2.0)
	var slip := _box(Vector3(SIZE.x - 0.05, 0.03, SIZE.y * LEAF_SHARE), LEAF)
	slip.position = Vector3(0.0, -0.008, -SIZE.y * (1.0 - LEAF_SHARE / 2.0) + 0.02)
	d.add_child(slip)
	return d


static func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.7
	b.material = mat
	m.mesh = b
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
