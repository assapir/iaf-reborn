# What stands on the nearest base (Modern IAF's airbases.json `furniture`, iaf-sim airbases from
# modern-iaf/data/furniture/<icao>.json; modern-iaf/docs/base-furniture.md): hardened aircraft shelters, hangars,
# buildings, the tower, a sunshade, the fence, ramp vehicles and parked jets. Our own simple shapes in vertex colours
# (no model download), one MultiMesh per kind so the whole base is a dozen draw calls; the parked jets are the flying
# jet's model merged into one surface. Rendering only: the flight model does not collide with them.
extends RefCounted

const Gltf := preload("res://shared/util/gltf.gd")
const TailNumber := preload("res://shared/aircraft/tail_number.gd")

## A shelter's arch: its height over its width (a TAB-VEE: 22 m wide, about 8.5 m high; inferred for the IAF's).
const ARCH_RISE := 0.4
const ARCH_STEPS := 12
## Heights (m, inferred): a hangar's eaves and ridge, a building's roof, the sunshade's roof, the fence.
const HANGAR_EAVES := 10.0
const HANGAR_RIDGE := 13.0
const BUILDING_H := 6.0
const SHADE_H := 5.5
const SHADE_BAY := 15.0
const FENCE_H := 2.4
const FENCE_POST := 6.0
## Drawn out to (m): the buildings from the air, the jets and vehicles near the ground, the fence close by.
const FAR := 15000.0
const NEAR := 4000.0
const FENCE_FAR := 2500.0
## The ramp vehicles.
const SMALL := ["gpu", "fuel_truck", "extinguisher", "tug"]
## A parked jet's kind is its aircraft definition's id (shared/extra/planes/<kind>/airframe.json).
const PLANES := "res://shared/extra/planes/%s/"
## The tower's roof over the cab (m, inferred).
const TOWER_TOP := 20.6
## A parked jet's triangles at most (about; the simplified model's).
const JET_TRIS := 6000

const CONCRETE := Color(0.72, 0.69, 0.63)
const SHADOW := Color(0.16, 0.15, 0.14)
const WALL := Color(0.83, 0.79, 0.70)
const ROOF := Color(0.62, 0.62, 0.60)
const DOOR := Color(0.42, 0.44, 0.45)
const GLASS := Color(0.12, 0.18, 0.22)
const STEEL := Color(0.55, 0.56, 0.55)
const OLIVE := Color(0.33, 0.36, 0.24)
const YELLOW := Color(0.78, 0.62, 0.12)
const RED := Color(0.62, 0.08, 0.06)

static var _jet_meshes := {}
static var _jet_frames := {}  # kind -> the flying model's frame in its parked mesh's (_jet)


## The base's furniture but the fence (fence()) under one node, or null while the ground under any of it is still
## loading. `o`: the world origin (engine metres), `terrain` answers height_at().
static func build(items: Array, o: Vector2, terrain: Node) -> Node3D:
	var placed := {}
	for f: Dictionary in items:
		if f.has("line"):
			continue
		var at := _scene(f.at, o)
		var h = terrain.height_at(at)
		if h == null:
			return null
		var kind := String(f.kind)
		var a := deg_to_rad(float(f.heading))
		var s: Array = f.get("size", [1.0, 1.0])
		var size := Vector3(float(s[1]), 1.0, float(s[0]))  # across, up, along the heading
		match kind:
			"shelter":
				size.y = size.x * ARCH_RISE
			"hangar", "building", "tower", "sunshade":
				pass
			_:
				size = Vector3.ONE
		# Local +Z along the grid heading: Godot (sin, 0, −cos) (as the taxiway signs).
		var b := Basis.from_euler(Vector3(0, atan2(sin(a), -cos(a)), 0)) * Basis.from_scale(size)
		if not placed.has(kind):
			placed[kind] = []
		placed[kind].append(Transform3D(b, Vector3(at.x, float(h), at.z)))
	var root := Node3D.new()
	root.name = "BaseFurniture"
	for kind: String in placed:
		var mesh := _mesh(kind)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = placed[kind].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, placed[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind
		mmi.multimesh = mm
		mmi.material_override = _material()
		mmi.visibility_range_end = NEAR if _is_jet(kind) or kind in SMALL else FAR
		if _is_jet(kind):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # in the shelters' shade
			_tail_numbers(mmi, kind, placed[kind], o)
		root.add_child(mmi)
	return root


## The fence along `line` (a furniture row's engine points), or null while the ground under any point is loading.
static func fence(line: Array, o: Vector2, terrain: Node) -> MeshInstance3D:
	var pts := PackedVector3Array()
	for p in line:
		var q := _scene(p, o)
		var h = terrain.height_at(q)
		if h == null:
			return null
		pts.append(Vector3(q.x, float(h), q.z))
	return _fence(pts) if pts.size() >= 2 else null


## Each parked jet's own tail number (TailNumber, docs/aircraft-models.md §1.6): the next of the flight's, so no two
## on the base and none of the flying jets show the same; kept by its place (`o` the world origin) when the base's
## furniture is built again.
static func _tail_numbers(parent: Node3D, kind: String, at: Array, o: Vector2) -> void:
	var model := jet_model(kind)
	for xf: Transform3D in at:
		var jet := Node3D.new()
		jet.transform = xf * _jet_frames[kind]
		TailNumber.mark(jet, model, TailNumber.next(model, "%.0f %.0f" % [xf.origin.x + o.x, o.y - xf.origin.z]))
		if jet.get_child_count() > 0:
			parent.add_child(jet)
		else:
			jet.free()


static func _is_jet(kind: String) -> bool:
	return FileAccess.file_exists(PLANES % kind + "airframe.json")


## The night lights the furniture carries (airbase_lights.gd): [engine point, metres above the ground, colour]. A
## lamp over each shelter's door, a red obstruction light on the tower and on each hangar's ridge (inferred).
static func lights(b: Dictionary) -> Array:
	var out := []
	for f: Dictionary in b.get("furniture", []):
		if not f.has("size"):
			continue
		var a := deg_to_rad(float(f.heading))
		var d := Vector2(sin(a), cos(a))
		var at := Vector2(f.at[0], f.at[1])
		match String(f.kind):
			"shelter":
				var w := float(f.size[1])
				out.append([at + d * float(f.size[0]) * 0.5, w * ARCH_RISE * 0.85, Color(1.0, 0.66, 0.32)])
			"hangar":
				out.append([at, HANGAR_RIDGE + 0.5, Color(1.0, 0.12, 0.06)])
			"tower":
				out.append([at, TOWER_TOP + 0.5, Color(1.0, 0.12, 0.06)])
	return out


static func _scene(p: Array, o: Vector2) -> Vector3:
	return Vector3(float(p[0]) - o.x, 0.0, -(float(p[1]) - o.y))


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


## Kind → its mesh: unit shapes scaled by each row's footprint, the tower, the sunshade and the vehicles at size.
static func _mesh(kind: String) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"shelter":
			_arch(st)
		"hangar":
			# Unit footprint: 1 × 1, walls to the eaves, a low gable along the length, doors in the +Z end.
			_box(st, Vector3(0, HANGAR_EAVES / 2 - 0.5, 0), Vector3(1, HANGAR_EAVES + 1, 1), WALL)
			_gable(st, HANGAR_EAVES, HANGAR_RIDGE)
			_box(st, Vector3(0, HANGAR_EAVES * 0.4, 0.5), Vector3(0.8, HANGAR_EAVES * 0.8, 0.02), DOOR)
		"building":
			_box(st, Vector3(0, BUILDING_H / 2 - 0.5, 0), Vector3(1, BUILDING_H + 1, 1), WALL)
			_box(st, Vector3(0, BUILDING_H + 0.15, 0), Vector3(1.02, 0.3, 1.02), ROOF)
		"tower":
			# On a unit footprint (the row's 20 × 12 m): the low building, the shaft and the glass cab (inferred).
			_box(st, Vector3(0, 3.5, 0), Vector3(1, 8, 1), WALL)
			_box(st, Vector3(0, 12, 0.2), Vector3(0.25, 10, 0.35), WALL)
			_box(st, Vector3(0, 18.5, 0.2), Vector3(0.36, 3, 0.6), GLASS)
			_box(st, Vector3(0, TOWER_TOP - 0.3, 0.2), Vector3(0.4, 0.6, 0.66), ROOF)
		"sunshade":
			# A unit length of roof on posts: a post pair every SHADE_BAY m along it (the row is about 25 bays).
			_box(st, Vector3(0, SHADE_H, 0), Vector3(1, 0.4, 1), ROOF)
			var n := 25
			for i in n + 1:
				for x in [-0.45, 0.45]:
					_box(st, Vector3(x, SHADE_H / 2, -0.5 + float(i) / n), Vector3(0.02, SHADE_H, 0.01), STEEL)
		"gpu":
			_box(st, Vector3(0, 0.75, 0), Vector3(1.4, 1.1, 2.4), YELLOW)
			_wheels(st, 1.4, 2.4)
		"fuel_truck":
			_box(st, Vector3(0, 1.6, 2.6), Vector3(2.4, 2.4, 2.0), OLIVE)
			_box(st, Vector3(0, 0.85, 2.0), Vector3(2.4, 0.9, 3.2), OLIVE)
			_box(st, Vector3(0, 2.2, 3.55), Vector3(2.2, 0.7, 0.05), GLASS)
			_box(st, Vector3(0, 1.9, -1.4), Vector3(2.4, 2.2, 6.0), OLIVE)
			_box(st, Vector3(0, 0.6, 0), Vector3(2.3, 0.4, 8.8), SHADOW)
			_wheels(st, 2.3, 7.0)
		"extinguisher":
			_box(st, Vector3(0, 0.75, 0), Vector3(0.6, 1.1, 0.9), RED)
			_wheels(st, 0.6, 0.6)
		"tug":
			_box(st, Vector3(0, 0.7, 0), Vector3(2.0, 0.9, 3.6), YELLOW)
			_box(st, Vector3(0, 1.6, -0.9), Vector3(1.2, 1.0, 1.2), GLASS)
			_wheels(st, 2.0, 2.6)
		_:
			if _is_jet(kind):
				return _jet(kind)
			return null
	return st.commit()


## A shelter of unit width, height and length: the outer shell and its thick front lip in concrete, the inside dark.
static func _arch(st: SurfaceTool) -> void:
	var outer := []
	var inner := []
	for i in ARCH_STEPS + 1:
		var t := PI * float(i) / ARCH_STEPS
		outer.append(Vector2(0.5 * cos(t), sin(t)))
		inner.append(Vector2(0.46 * cos(t), 0.92 * sin(t)))
	for i in ARCH_STEPS:
		var a: Vector2 = outer[i]
		var b: Vector2 = outer[i + 1]
		# The normal for the scaled arch (x 0.5 w cos t, y ARCH_RISE w sin t): a MultiMesh scales normals by the
		# instance's basis, not its inverse transpose, so (2 cos t, 2.5 sin t) is stored as (2 cos t, 6.25 sin t).
		var tm := PI * (i + 0.5) / ARCH_STEPS
		var n := Vector3(2.0 * cos(tm), sin(tm) / (ARCH_RISE * ARCH_RISE), 0).normalized()
		_quad(
			st,
			Vector3(a.x, a.y, -0.5),
			Vector3(b.x, b.y, -0.5),
			Vector3(b.x, b.y, 0.5),
			Vector3(a.x, a.y, 0.5),
			n,
			CONCRETE
		)
		var c: Vector2 = inner[i]
		var d: Vector2 = inner[i + 1]
		_quad(
			st,
			Vector3(d.x, d.y, -0.47),
			Vector3(c.x, c.y, -0.47),
			Vector3(c.x, c.y, 0.5),
			Vector3(d.x, d.y, 0.5),
			-n,
			SHADOW
		)
		# The lip at the door, the back wall outside and inside.
		_quad(
			st,
			Vector3(a.x, a.y, 0.5),
			Vector3(b.x, b.y, 0.5),
			Vector3(d.x, d.y, 0.5),
			Vector3(c.x, c.y, 0.5),
			Vector3.BACK,
			CONCRETE
		)
		_tri(st, Vector3(0, 0, -0.5), Vector3(b.x, b.y, -0.5), Vector3(a.x, a.y, -0.5), Vector3.FORWARD, CONCRETE)
		_tri(st, Vector3(0, 0, -0.47), Vector3(c.x, c.y, -0.47), Vector3(d.x, d.y, -0.47), Vector3.BACK, SHADOW)


## A gable roof over a unit footprint, eaves to ridge along Z.
static func _gable(st: SurfaceTool, eaves: float, ridge: float) -> void:
	var l := Vector3(-0.5, eaves, 0)
	var r := Vector3(0.5, eaves, 0)
	var t := Vector3(0, ridge, 0)
	# Stored for the instance's scale (see _arch), for a typical 22 m wide hangar.
	var nl := Vector3(-(ridge - eaves) / 22.0, 11.0, 0).normalized()
	var nr := Vector3((ridge - eaves) / 22.0, 11.0, 0).normalized()
	var z := Vector3(0, 0, 0.5)
	_quad(st, l + z, t + z, t - z, l - z, nl, ROOF)
	_quad(st, t + z, r + z, r - z, t - z, nr, ROOF)
	_tri(st, l + z, r + z, t + z, Vector3.BACK, WALL)
	_tri(st, r - z, l - z, t - z, Vector3.FORWARD, WALL)


static func _wheels(st: SurfaceTool, w: float, l: float) -> void:
	for x in [-w / 2, w / 2]:
		for z in [-l / 3, l / 3]:
			_box(st, Vector3(x, 0.3, z), Vector3(0.3, 0.6, 0.6), SHADOW)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s / 2
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sg
			var u := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			var v := Vector3.ZERO
			v[(ax + 2) % 3] = h[(ax + 2) % 3]
			var f := c + n * h[ax]
			if sg > 0:
				_quad(st, f - u - v, f + u - v, f + u + v, f - u + v, n, col)
			else:
				_quad(st, f - u - v, f - u + v, f + u + v, f + u - v, n, col)


## Quad abcd, counter-clockwise seen from its normal's side.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	# Godot's front faces wind clockwise.
	for p in [a, c, b]:
		st.add_vertex(p)


## The fence along the base's outline: posts every FENCE_POST m and a grey mesh between them, as one mesh.
static func _fence(line: PackedVector3Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var n := Vector3(a.z - b.z, 0, b.x - a.x).normalized()
		var up := Vector3(0, FENCE_H, 0)
		_quad(st, a, b, b + up, a + up, n, STEEL)
		_quad(st, b, a, a + up, b + up, -n, STEEL)
		var steps := maxi(1, int(a.distance_to(b) / FENCE_POST))
		for k in steps:
			_box(st, a.lerp(b, float(k) / steps) + Vector3(0, FENCE_H / 2, 0), Vector3(0.1, FENCE_H, 0.1), SHADOW)
	var mi := MeshInstance3D.new()
	mi.name = "fence"
	mi.mesh = st.commit()
	var m := _material()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.albedo_color = Color(1, 1, 1, 0.45)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = FENCE_FAR
	return mi


## The model a jet of aircraft definition `kind` flies with: the definition's "model", else the detailed model of its
## original model file (Gltf.DETAILED), else <kind>.gltf in the definition's folder (the F-35I's); a res:// path or
## one under assets/converted.
static func jet_model(kind: String) -> String:
	var def := Settings.load_json(PLANES % kind + "airframe.json")
	var f := String(def.get("model", Gltf.DETAILED.get(String(def.get("original_model", "")), "")))
	if f == "":
		f = PLANES % kind + kind + ".gltf"
	return f if f.begins_with("res://") else Settings.converted(f)


## A parked jet: the flying jet's model on its gear, every surface merged into one in its material's colour (the
## texture's average), nose along +Z, wheels at y 0. Kept for the flight.
static func _jet(kind: String) -> Mesh:
	if _jet_meshes.has(kind):
		return _jet_meshes[kind]
	var model = Gltf.open(jet_model(kind))
	if model == null:
		return null
	var n := Gltf.instance(model)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not _shown(mi, n):
			continue
		var xf := _to(mi, n)
		for s in mi.mesh.get_surface_count():
			var col := _colour(mi.get_active_material(s))
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var order := idx if not idx.is_empty() else PackedInt32Array(range(v.size()))
			for k in order:
				st.set_color(col)
				st.set_normal((xf.basis * nn[k]).normalized() if nn.size() > k else Vector3.UP)
				st.add_vertex(xf * v[k])
	n.free()
	st.index()  # the LODs need an indexed mesh
	var mesh := st.commit()
	# The model's nose is along −Z (the flying jet stands on Basis(right, up, −forward)): turned to +Z, the wheels'
	# bottom at 0.
	var box := mesh.get_aabb()
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var arrays := mesh.surface_get_arrays(0)
	var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for k in pv.size():
		pv[k] = turn * pv[k] - Vector3(0, box.position.y, 0)
		pn[k] = turn.basis * pn[k]
	arrays[Mesh.ARRAY_VERTEX] = pv
	arrays[Mesh.ARRAY_NORMAL] = pn
	_jet_frames[kind] = Transform3D(turn.basis, Vector3(0, -box.position.y, 0))
	# A parked jet is seen from 20 m and more: the simplified copy nearest JET_TRIS triangles (the importer's LODs;
	# the full model, 62k triangles, cost 11 ms of GPU for 12 jets with their shadows on the Iris Xe).
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	var best := -1
	for k in im.get_surface_lod_count(0):
		if im.get_surface_lod_indices(0, k).size() / 3 >= JET_TRIS:
			best = k
	if best >= 0:
		arrays[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(0, best)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_jet_meshes[kind] = am
	return am


static func _shown(n: Node, root: Node) -> bool:
	while n != null and n != root:
		if n is Node3D and not n.visible:
			return false
		n = n.get_parent()
	return true


static func _to(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			t = p.transform * t
		p = p.get_parent()
	return t


static func _colour(m: Material) -> Color:
	if not m is BaseMaterial3D:
		return CONCRETE
	var c: Color = m.albedo_color
	var tex: Texture2D = m.albedo_texture
	if tex != null:
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
			c *= img.get_pixel(0, 0)
	return Color(c.r, c.g, c.b)
