# The cockpit view's own jet from the detailed F-16 (docs/aircraft-models.md §1.4): with Models Detailed (the F-16D)
# or the Sufa, the player's cockpit model is the detailed F-16 cut at its front seat's eye: the ACES II seat kept
# behind the eye with its headrest, the front pilot's body, the gear legs and nothing ahead of the eye left out; with
# Models Original it stays the original's f16_bc.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_detailed_cockpit.gd
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://util/gltf.gd")


func run() -> void:
	await require_data()
	var aircraft_model: GDScript = load("res://aircraft/aircraft_model.gd")
	for path in [Gltf.DETAILED["f16_h.gltf"], Gltf.SUFA]:
		var tag := String(path).get_file()
		var whole: Node3D = Gltf.instance(Gltf.model(path))
		var crew := whole.find_child("pilot", true, false) as MeshInstance3D
		var n: int = aircraft_model.F16_SEAT_SURFACES
		check(
			(
				crew.mesh.surface_get_material(n - 1).resource_name == "ac_texture.png_23_2s"
				and crew.mesh.surface_get_material(n).resource_name == "ac_plain_11"
			),
			"%s: the crew mesh's seat surfaces end at %d" % [tag, n]
		)
		whole.free()
		var t0 := Time.get_ticks_usec()
		var cut: Array = aircraft_model.detailed_cockpit(path)
		print("%s: cut in %.0f ms" % [tag, (Time.get_ticks_usec() - t0) / 1000.0])
		var m: Node3D = cut[0]
		var eye: Vector3 = cut[1]
		var root := m.get_child(0) as Node3D
		check(absf(eye.x) < 0.05 and absf(eye.y - 0.85) < 0.1, "%s: the eye on the centre line, at %s" % [tag, eye])
		var ahead := 0
		var seat_aft := -INF
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = root.transform * mi.transform if mi.get_parent() == root else root.transform
			for s in mi.mesh.get_surface_count():
				var v: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				for i in range(0, idx.size(), 3):
					var z := maxf(maxf((xf * v[idx[i]]).z, (xf * v[idx[i + 1]]).z), (xf * v[idx[i + 2]]).z)
					ahead += 1 if z <= eye.z else 0
					if mi.name == "pilot":
						seat_aft = maxf(seat_aft, z)
			if mi.name == "pilot":
				check(
					mi.mesh.get_surface_count() > 0 and mi.mesh.get_surface_count() <= n,
					"%s: the front seat without its pilot" % tag
				)
		check(ahead == 0, "%s: no triangle wholly ahead of the eye (%d)" % [tag, ahead])
		check(
			seat_aft - eye.z > 0.4 and seat_aft - eye.z < 0.7,
			"%s: seat back %.2f m behind the eye" % [tag, seat_aft - eye.z]
		)
		check(root.get_node_or_null("pilotB") != null, "%s: the rear cockpit and its crew stay" % tag)
		for g in ["LdgF", "LdgL", "LdgR", "LdgDr"]:
			check(root.get_node_or_null(g) == null, "%s: no %s" % [tag, g])
		check((root.get_node("LdgDrUp") as Node3D).visible, "%s: the closed gear doors shown" % tag)
		m.free()

	# In a mission: Original keeps the original's f16_bc, Detailed and the Sufa the cut model.
	for c in [["original", "barak", false], ["detailed", "barak", true], ["original", "sufa", true]]:
		settings().models = c[0]
		settings().f16_variant = c[1]
		var tv := await start_mission(231)
		await frames(3)
		var detailed: bool = tv.own_bc != null and tv.own_bc.find_child("pilot", true, false) != null
		check(tv.own_bc != null and detailed == c[2], "Models %s, %s: detailed cockpit model %s" % c)
	settings().models = "original"
	settings().f16_variant = "barak"
