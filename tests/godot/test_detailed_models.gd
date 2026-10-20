# Detailed models (Preferences → Extras → Models, docs/aircraft-models.md): with the switch off every F-16 is exactly
# the original model; on, the detailed F-16D loads (KTX2 textures, LODs, one shared parse), carries every helper of
# the original at the original's position (stations, gun, eye, engine, wingtips, height: 1 cm), every moving part
# hinged on its own surface (FlightGear's hinge lines; the offsets from the original's are printed) with an axis
# within AXIS_DEG of the original's (the stabilators' 10° anhedral is the largest), keeps
# the original's descriptor for everything the game reads, has the IAF dorsal spine of the original (its top profile
# from the canopy to the fin, SPINE_*), animates (gear, closed doors, speed brakes, flaperons), and flies as the
# player's and the AI's jets.
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://util/gltf.gd")
const HELPER_M := 0.01
## How far a part's pivot may lie outside its own mesh bounds.
const HINGE_M := 0.05
const AXIS_DEG := 12.0
## How far a detailed mesh may reach outside the original's bounds (the FlightGear F-16 is 0.6 m shorter, 0.2 m
## taller on its gear).
const LOOSE_M := 1.0
## The IAF dorsal spine: stations (m aft of the eye, along the jet) between the canopy's rear end and the fin's leading
## edge where the detailed body's top must follow the original's within SPINE_M at 0.1 m off the centre line and
## within SPINE_SIDE_M at 0.3 m (its shoulders are rounder than the original's box). The original's whole spine sits
## SPINE_OFFSET_M higher (its canopy is 0.16 m taller than FlightGear's; the detailed spine meets FlightGear's
## canopy and the foot of its fin and rudder), measured at the fin's root and taken out first. FlightGear's slim
## US spine is 0.3 to 0.4 m below.
## How far from a store's Station helper its pylon's surface may be; TIP_M for the wingtip rails (StationA / I: the
## original has no rail there, its missiles bring their own launcher, which meets FlightGear's tip rail 0.10 m off).
const ATTACH_M := 0.05
const TIP_M := 0.12
const SPINE_STATIONS := [4.5, 5.0, 6.0, 7.0, 8.0]
const SPINE_SIDE_STATIONS := [5.0, 6.0, 7.0]
const SPINE_FIN := 8.25
const SPINE_M := 0.05
const SPINE_SIDE_M := 0.08
const SPINE_OFFSET_M := 0.15

var AircraftModel: GDScript


func run() -> void:
	AircraftModel = load("res://aircraft/aircraft_model.gd")
	var orig_desc: Dictionary = AircraftModel.load_descriptor("f16")
	var orig_path: String = Settings().assets_dir().path_join("converted/planes/f16").path_join(orig_desc.model)
	var orig_scene: Node3D = Gltf.instance(Gltf.open(orig_path))
	var orig_root := orig_scene.find_child("f16", true, false) as Node3D

	# Off (the default): the original, untouched.
	check(Settings().models == "original", "Models defaults to Original")
	var off: Node3D = AircraftModel.create("f16", 100, false)
	check(
		off.find_child("LdgDrUp", true, false) == null and off.desc == orig_desc,
		"off: the original descriptor and model"
	)
	check(
		_names(off.root_frame) == _names(orig_root) and _tris(off) == _tris(orig_scene),
		"off: the original's nodes and triangles (%d)" % _tris(off)
	)
	check(Gltf.detailed("controllableplanes/f16/f16_h.gltf") == "", "off: no detailed model for the Reference viewer")
	off.free()

	# On.
	Settings().models = "detailed"
	var t0 := Time.get_ticks_msec()
	var on: Node3D = AircraftModel.create("f16", 100, false)
	var first_ms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var again: Node3D = AircraftModel.create("f16", 100, true)
	var second_ms := Time.get_ticks_msec() - t0
	check(on != null and on.find_child("LdgDrUp", true, false) != null, "on: the detailed model loads")
	check(second_ms < 100, "on: parsed once, later jets share it (first %d ms, second %d ms)" % [first_ms, second_ms])
	var tris := _tris(on)
	check(tris > 30000, "on: detailed triangles %d (original %d)" % [tris, _tris(orig_scene)])
	var tex := _albedo(on)
	check(
		tex != null and tex.get_width() >= 2048 and tex.get_image().has_mipmaps(),
		"on: the 2048 px KTX2 livery with mipmaps"
	)
	var paint := _material_with(on, tex)
	check(
		(
			paint != null
			and paint.normal_enabled
			and paint.normal_texture != null
			and paint.roughness_texture != null
			and paint.metallic_texture != null
			and paint.ao_enabled
			and paint.ao_texture != null
		),
		"on: the paint is PBR (normal, roughness, metallic, occlusion maps)"
	)
	var pivot_box := _box(on.part_node("AilerL"), on.part_node("AilerL")).grow(HINGE_M)
	check(
		(
			pivot_box.size != Vector3.ZERO
			and pivot_box.has_point(Vector3.ZERO)
			and not pivot_box.has_point(Vector3(5, 0, 0))
		),
		"on: the pivot check sees the part's own mesh (a point 5 m off fails)"
	)
	var lods := 0
	for mi: MeshInstance3D in on.find_children("*", "MeshInstance3D", true, false):
		var am := mi.mesh as ArrayMesh
		if (
			am != null
			and am.get_surface_count() > 0
			and (RenderingServer.mesh_get_surface(am.get_rid(), 0).get("lods", []) as Array).size() > 0
		):
			lods += 1
	check(lods > 0, "on: meshes carry LODs (%d)" % lods)
	check(
		Gltf.detailed("controllableplanes/f16/f16_h.gltf") != "",
		"on: the Reference viewer's F-16 maps to the detailed model"
	)

	# Every helper of the original, same place; every part present.
	var fr: Node3D = on.root_frame
	var missing := []
	var far := []
	var report := []
	for n in orig_root.get_children():
		var name := String(n.name)
		var mine := fr.get_node_or_null(NodePath(name)) as Node3D
		if mine == null:
			missing.append(name)
			continue
		if (
			orig_desc.parts.has(name)
			or (name.ends_with("1") or name.ends_with("2")) and orig_desc.parts.has(name.left(-1))
		):
			continue  # parts and their hinge helpers: below
		var dd: float = mine.position.distance_to((n as Node3D).position)
		report.append("%s %.3f" % [name, dd])
		if dd > HELPER_M:
			far.append(name)
	print("helpers (name, offset m): ", ", ".join(report))
	check(missing.is_empty(), "on: every node of the original exists (missing %s)" % [missing])
	check(far.is_empty(), "on: helpers within %.2f m of the original's (off: %s)" % [HELPER_M, far])
	var bad := []
	report = []
	for name in orig_desc.parts:
		var p: Dictionary = orig_desc.parts[name]
		var mine := fr.get_node_or_null(NodePath(name)) as Node3D
		if mine == null or p.axis == null or not on.desc.parts.has(name):
			continue
		var oa := Vector3(p.axis[0], p.axis[1], p.axis[2]).normalized()
		var ma := Vector3(on.desc.parts[name].axis[0], on.desc.parts[name].axis[1], on.desc.parts[name].axis[2])
		var op := Vector3(p.pivot[0], p.pivot[1], p.pivot[2])
		var off_line := (mine.position - op) - oa * (mine.position - op).dot(oa)
		var deg := rad_to_deg(oa.angle_to(ma))
		report.append("%s %.3f m %.1f°" % [name, off_line.length(), deg])
		var box := _box(mine, mine).grow(HINGE_M)
		if deg > AXIS_DEG or box.size == Vector3.ZERO or not box.has_point(Vector3.ZERO):
			bad.append(name)
	print("hinges (name, pivot off the original's hinge line, axis angle to the original's): ", ", ".join(report))
	check(
		bad.is_empty(),
		"on: each pivot on its own part, axes within %.0f° of the original's (outside: %s)" % [AXIS_DEG, bad]
	)

	# Nothing detached: every mesh (the body and each part, rest pose) inside the original's bounds grown by
	# LOOSE_M, each part touching the body, the afterburner at the tail cone's end.
	var obox := _box(orig_root, orig_root)
	var body := _box(fr, fr, false)
	var stray := []
	for mi: MeshInstance3D in [fr] + fr.find_children("*", "MeshInstance3D", true, false):
		if (
			mi.mesh != null
			and not String(mi.name).begins_with("Afterburner_")
			and not obox.grow(LOOSE_M).encloses(_xf(mi, fr) * mi.get_aabb())
		):
			stray.append(String(mi.name))
	check(
		stray.is_empty(),
		(
			"on: every mesh inside the original's bounds + %.1f m (stray: %s; original %s, detailed body %s)"
			% [LOOSE_M, stray, obox, body]
		)
	)
	var loose := []
	for name in orig_desc.parts:
		var part := fr.get_node_or_null(NodePath(name)) as Node3D
		if part != null and part.get_child_count() + (1 if part is MeshInstance3D else 0) > 0:
			var pb := _box(part, fr)
			if pb.size != Vector3.ZERO and not pb.intersects(body.grow(0.05)):
				loose.append(name)
	check(loose.is_empty(), "on: every part touches the body (loose: %s)" % [loose])
	# The IAF dorsal spine: the body's top profile against the original's (the same frame: the helpers match).
	var eye: Vector3 = (fr.get_node("Camera") as Node3D).position
	var det_tris: PackedVector3Array = (fr as MeshInstance3D).mesh.get_faces()
	var orig_tris: PackedVector3Array = (orig_root as MeshInstance3D).mesh.get_faces()
	var off_m := _top(orig_tris, eye, 0.1, SPINE_FIN) - _top(det_tris, eye, 0.1, SPINE_FIN)
	var spine := []
	var spine_bad := false
	for st in SPINE_STATIONS + SPINE_SIDE_STATIONS.map(func(v): return -v):  # negative: the 0.3 m line
		var x := 0.1 if st > 0 else 0.3
		var o := _top(orig_tris, eye, x, absf(st)) - off_m
		var d := _top(det_tris, eye, x, absf(st))
		spine.append("%.1f m aft x %.1f: %.3f / %.3f" % [absf(st), x, d, o])
		spine_bad = spine_bad or absf(d - o) > (SPINE_M if st > 0 else SPINE_SIDE_M)
	print("dorsal spine top (detailed / original - %.3f m), m above the eye: " % off_m, ", ".join(spine))
	check(
		not spine_bad and absf(off_m) < SPINE_OFFSET_M,
		"on: the IAF dorsal spine follows the original's top from the canopy to the fin (offset %.2f m)" % off_m
	)
	# The afterburner's ring (the engine point, its radius) lies on the body's nozzle: body vertices within 10 cm of
	# the exit plane at about that radius all round.
	var eng: Array = on.desc.engines.left
	var ep := Vector3(eng[0], eng[1], eng[2])
	var r := float(on.desc.engines.radius)
	var sectors := {}
	for si in (fr as MeshInstance3D).mesh.get_surface_count():
		for v: Vector3 in (fr as MeshInstance3D).mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var d := Vector2(v.x - ep.x, v.y - ep.y)
			if absf(v.z - ep.z) < 0.1 and d.length() > 0.7 * r and d.length() < 1.3 * r:
				sectors[posmod(int(round(rad_to_deg(d.angle()) / 45.0)), 8)] = true
	check(
		sectors.size() == 8,
		"on: the afterburner ring sits on the nozzle's exit (r %.2f m, %d of 8 sectors)" % [r, sectors.size()]
	)

	# What the game reads stays the original's.
	var same := true
	for k in ["stations", "gun", "end_wing", "eye", "height", "scale", "type", "root"]:
		same = same and on.desc.get(k) == orig_desc.get(k)
	check(same, "on: stations, gun, wingtips, eye, height from the original's descriptor")
	var st_ok := true
	for s in orig_desc.stations:
		var h := fr.get_node_or_null(NodePath(String(s))) as Node3D
		var v: Array = orig_desc.stations[s]
		st_ok = st_ok and h != null and h.position.distance_to(Vector3(v[0], v[1], v[2])) < HELPER_M
	check(st_ok, "on: the model's Station helpers sit on the descriptor's stations")
	# Every store station (StationA..I) has its pylon or rail: body geometry within ATTACH_M of the store's attach
	# point along an axis (above it on a pylon, beside or under it on a wingtip rail); a store on a station without
	# one would float.
	var att := []
	var floating := []
	for s in orig_desc.stations:
		if String(s).length() != "StationA".length():
			continue  # the gun and the flare dispenser
		var h := fr.get_node_or_null(NodePath(String(s))) as Node3D
		var gap := _near(det_tris, h.position) if h != null else INF
		att.append("%s %.3f (original %.3f)" % [s, gap, _near(orig_tris, h.position)])
		if gap > (TIP_M if String(s) in ["StationA", "StationI"] else ATTACH_M):
			floating.append(String(s))
	print("stations (name, gap to the body m): ", ", ".join(att))
	check(
		floating.is_empty(),
		"on: every station has its pylon or rail (within %.2f m, tips %.2f m; none: %s)" % [ATTACH_M, TIP_M, floating]
	)
	check(on.flames.size() == 1, "on: one afterburner nozzle")

	# Animation: airborne gear up (legs and open doors hidden, closed doors shown), ground start gear down.
	check(
		not on.part_node("LdgL").visible and not on.part_node("LdgDr").visible and on.part_node("LdgDrUp").visible,
		"airborne: gear and open doors hidden, closed doors shown"
	)
	check(
		again.part_node("LdgL").visible and again.part_node("LdgDr").visible and not again.part_node("LdgDrUp").visible,
		"ground: gear and open doors shown, closed doors hidden"
	)
	var sb: Node3D = on.part_node("SpdbrU")
	var b0 := sb.transform.basis
	on.update({"brakes": false}, 0.0)
	on.update({"brakes": true}, 0.0)
	on.settle()
	check(not sb.transform.basis.is_equal_approx(b0), "speed brakes open")
	var fl: Node3D = on.part_node("AilerL")
	var f0 := fl.transform.basis
	on.update({"flaps": 1.0}, 0.0)
	on.settle()
	check(not fl.transform.basis.is_equal_approx(f0), "flaperons droop")
	# Jets share the parsed meshes; what changes one jet's look replaces its own mesh (night-light points here).
	var mi_a := on.part_node("ElevaL") as MeshInstance3D
	var mi_b := again.part_node("ElevaL") as MeshInstance3D
	check(mi_a.mesh == mi_b.mesh, "two detailed jets share one mesh")
	var holder := Node3D.new()
	mi_a.owner = null
	mi_a.reparent(holder, false)
	load("res://terrain/night_lights.gd").to_points(holder, StandardMaterial3D.new())
	check(
		mi_a.mesh != mi_b.mesh and mi_b.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES,
		"changing one jet's mesh leaves the other's"
	)
	holder.free()
	on.free()
	again.free()
	orig_scene.free()

	# In a mission: the player's and the AI's F-16s.
	var tv := await start_mission(231)
	await frames(5)
	check(
		tv.aircraft != null and tv.aircraft.find_child("LdgDrUp", true, false) != null,
		"mission 231: the player's F-16 is detailed"
	)
	var ai := 0
	for n in tv.find_children("f16", "Node3D", true, false):
		if n != tv.aircraft and n.find_child("LdgDrUp", true, false) != null:
			ai += 1
	check(ai > 0, "mission 231: the AI's F-16s are detailed (%d)" % ai)
	Settings().models = "original"


## The highest point of `tris` (frame of the root) straight under (x, `aft` m behind the eye), above the eye's height.
func _top(tris: PackedVector3Array, eye: Vector3, x: float, aft: float) -> float:
	var from := Vector3(x, eye.y + 10.0, eye.z + aft)
	var best := -INF
	for i in range(0, tris.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, tris[i], tris[i + 1], tris[i + 2])
		if hit != null:
			best = maxf(best, (hit as Vector3).y - eye.y)
	return best


## The distance from `p` to the nearest triangle of `tris` along the six axes (INF: none).
func _near(tris: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		for i in range(0, tris.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(p, dir, tris[i], tris[i + 1], tris[i + 2])
			if hit != null:
				best = minf(best, p.distance_to(hit))
	return best


func _names(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if not String(c.name).begins_with("Afterburner_"):  # added by AircraftModel
			out.append(String(c.name))
	out.sort()
	return out


func _tris(n: Node) -> int:
	var t := 0
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name).begins_with("Afterburner_"):
			continue
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			var idx = a[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


func _albedo(n: Node) -> Texture2D:
	var best: Texture2D = null
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if (
				m != null
				and m.albedo_texture != null
				and (best == null or m.albedo_texture.get_width() > best.get_width())
			):
				best = m.albedo_texture
	return best


## `n`'s transform relative to `frame` (outside the tree).
func _xf(n: Node3D, frame: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != frame:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


## The merged bounds of the meshes of `n` in `frame` (`deep` false: only `n`'s own mesh).
func _box(n: Node3D, frame: Node3D, deep := true) -> AABB:
	var list: Array = n.find_children("*", "MeshInstance3D", true, false) if deep else []
	if n is MeshInstance3D:
		list.append(n)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in list:
		if mi.mesh == null or String(mi.name).begins_with("Afterburner_"):
			continue
		var b := _xf(mi, frame) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _material_with(n: Node, tex: Texture2D) -> BaseMaterial3D:
	for mi: MeshInstance3D in (
		n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else [])
	):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.albedo_texture == tex:
				return m
	return null
