# The cockpit view's own jet from the detailed F-16 (docs/aircraft-models.md §1.4): with Models Detailed (the F-16D)
# or the Sufa, the player's cockpit model is the detailed F-16 cut at its front seat's eye: the ACES II seat kept
# behind the eye with its headrest, the front pilot's body, the gear legs and nothing ahead of the eye left out; with
# Models Original it stays the original's f16_bc.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn \
#     -s ../tests/godot/test_detailed_cockpit.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	await require_data()
	# Loaded here, not preloaded: gltf.gd reaches Settings, which a scene script (-s) compiles before.
	var gltf: GDScript = load("res://shared/util/gltf.gd")
	var aircraft_model: GDScript = load("res://shared/aircraft/aircraft_model.gd")
	for path in [gltf.DETAILED["f16_h.gltf"], settings().airframe_def("f16i").model]:
		var tag := String(path).get_file()
		var whole: Node3D = gltf.instance(gltf.model(path))
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
			if not mi.visible:  # the canopy's glass, kept hidden for an open canopy (Modern IAF)
				continue
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
		_check_well(aircraft_model, path, tag)
		for g in ["LdgF", "LdgL", "LdgR", "LdgDr"]:
			check(root.get_node_or_null(g) == null, "%s: no %s" % [tag, g])
		check((root.get_node("LdgDrUp") as Node3D).visible, "%s: the closed gear doors shown" % tag)
		var can := root.get_node("Canopy") as MeshInstance3D
		var grey := true
		for s in can.mesh.get_surface_count():
			var cm := can.mesh.surface_get_material(s) as BaseMaterial3D
			grey = grey and cm.albedo_color == aircraft_model.F16_FRAME_COLOUR and cm.albedo_texture == null
		check(grey, "%s: the canopy frame in frame grey, not the livery" % tag)
		var seat := root.get_node("pilot") as MeshInstance3D
		var seat_mat := seat.mesh.surface_get_material(0) as BaseMaterial3D
		var orig_mat := gltf.instance(gltf.model(path)).find_child("pilot", true, false) as MeshInstance3D
		check(
			seat_mat.roughness > 0.8 and orig_mat.get_active_material(0).roughness == 0.5,
			(
				"%s: the seat matte (%s), the outside jets' seat unchanged (%s)"
				% [tag, seat_mat.roughness, orig_mat.get_active_material(0).roughness]
			)
		)
		orig_mat.get_parent().get_parent().free()
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


## With the 3D cockpit (both games): no interior triangle stands in the front seat's well, where the rear cockpit's
## footwell stood as a black slab (docs/aircraft-models.md §1.4).
func _check_well(aircraft_model: GDScript, path: String, tag: String) -> void:
	var cut: Array = aircraft_model.detailed_cockpit(path, true)
	var m: Node3D = cut[0]
	var eye: Vector3 = cut[1] + Vector3(0, aircraft_model.F16_3D_SEAT_DOWN, 0)
	var root := m.get_child(0) as Node3D
	var left := 0
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.name == "pilot":
			continue
		var xf: Transform3D = root.transform * mi.transform if mi.get_parent() == root else root.transform
		for s in mi.mesh.get_surface_count():
			if not mi.mesh.surface_get_material(s).resource_name.begins_with("ac_"):
				continue
			var a := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var in_well := true
				var near := false
				for k in 3:
					var q := xf * v[idx[i + k]]
					in_well = in_well and absf(q.x) < aircraft_model.F16_SEAT_HALF_WIDTH
					in_well = in_well and q.y < eye.y - aircraft_model.F16_LAP_BELOW
					near = near or q.z < eye.z + aircraft_model.F16_CONSOLE_AFT
				left += 1 if in_well and near else 0
	check(left == 0, "%s: the 3D cockpit's seat well empty (%d triangles)" % [tag, left])
	m.free()
