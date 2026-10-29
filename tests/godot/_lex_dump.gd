# Dev helper (not run by tools/test.sh): dumps each jet model's triangles in its root frame, as vapour_fx.gd's
# _geometry sees them, to measure where the LEX / chine / canard vortices start (vapour_fx.gd LEX, docs/rendering.md
# §6 "LEX sheet"). Headless:
#   IAF_DEFAULT_SETTINGS=1 LEX_OUT=/tmp/lex godot --headless --path game --log-file /tmp/l.log \
#     -s ../tests/godot/_lex_dump.gd
# Writes LEX_OUT/<model file>.json: {tips: [l, r], box: [pos, size], eye, v: the triangles [x, y, z, ...]};
# tools/lex_measure.py reads them.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var out := OS.get_environment("LEX_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var NightLights = load("res://terrain/night_lights.gd")
	var Gltf = load("res://util/gltf.gd")
	for pm in [
		"f16:original:",
		"f16:detailed:",
		"f16:original:sufa",
		"f15:original:",
		"f15:detailed:",
		"f35i:original:",
		"mig29:original:",
		"cfir:original:",
		"lavi:original:"
	]:
		var c: PackedStringArray = pm.split(":")
		settings().models = c[1]
		settings().f16_variant = c[2] if c[2] != "" else "barak"
		var m: Node3D = load("res://aircraft/aircraft_model.gd").create(c[0], -1, false)
		root.add_child(m)
		var hd: String = Gltf.detailed(str(m.desc.get("model", "")))
		var file := (hd if hd != "" else str(m.desc.model)).get_file()
		var frame: Node3D = m.root_frame
		var s: Array = NightLights._light_spots(frame)
		var v := []
		var box := AABB()
		# The frame's own mesh (the body) too; the box as _geometry's: the frame's children only.
		var meshes: Array = frame.find_children("*", "MeshInstance3D", true, false)
		if frame is MeshInstance3D:
			meshes.push_front(frame)
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null or not NightLights._shown(frame, mi) or str(mi.name).begins_with("Afterburner"):
				continue
			if str(mi.name) in ["NavLights", "Strobe"]:
				continue
			var t: Transform3D = NightLights._rel(frame, mi)
			if mi != frame:
				box = box.merge(t * mi.get_aabb())
			if OS.get_environment("LEX_LIST") != "":
				print("  ", mi.name, " ", t * mi.get_aabb(), " ", t.basis.get_scale())
			for i in mi.mesh.get_surface_count():
				var a: Array = mi.mesh.surface_get_arrays(i)
				var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if ix.is_empty():
					ix = PackedInt32Array(range(vs.size()))
				# Triangles, three vertices each.
				for k in ix:
					var q := t * vs[k]
					v.append_array([snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001)])
		var d := {
			"tips": [[s[0].x, s[0].y, s[0].z], [s[1].x, s[1].y, s[1].z]],
			"box": [[box.position.x, box.position.y, box.position.z], [box.size.x, box.size.y, box.size.z]],
			"eye": m.desc.get("eye"),
			"v": v
		}
		var f := FileAccess.open(out.path_join(file + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		print(pm, " -> ", file, " ", v.size() / 3, " vertices")
		m.queue_free()
		await process_frame
	check(true, "dumped")
