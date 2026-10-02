# Pylons (docs/weapons.md "Pylons"): the original has no pylon object; the pylons are part of every jet's
# model (thin double-sided quads under the wing stations, drawn always, whatever is loaded). Check that each
# flyable jet's converted model has pylon geometry reaching down to (below) its wing stations B..D, F..H.
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://util/gltf.gd")
const JETS := ["f16", "f15", "f42000", "lavi", "cfir", "mirage"]
const WING := ["StationB", "StationC", "StationD", "StationF", "StationG", "StationH"]


func run() -> void:
	var base: String = Settings().assets_dir().path_join("converted/planes")
	for jet in JETS:
		var desc: Dictionary = Settings().load_json(base.path_join(jet).path_join("aircraft.json"))
		var model = Gltf.open(base.path_join(jet).path_join(String(desc.get("model", ""))))
		if model == null:
			check(false, "%s: model loads" % jet)
			continue
		var root_node: Node3D = Gltf.instance(model)
		var verts := PackedVector3Array()
		for mi in root_node.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != root_node:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for s in mi.mesh.get_surface_count():
				for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					verts.append(xf * v)
		var stations: Dictionary = desc.get("stations", {})
		var found := 0
		var wanted := 0
		for st in WING:
			var p = stations.get(st)
			if not p is Array:
				continue
			wanted += 1
			var sp := Vector3(p[0], p[1], p[2])
			for v in verts:
				if absf(v.x - sp.x) < 0.15 and absf(v.z - sp.z) < 1.0 and v.y <= sp.y + 0.02:
					found += 1
					break
		check(wanted > 0 and found == wanted, "%s: pylon geometry at %d / %d wing stations" % [jet, found, wanted])
		root_node.free()
