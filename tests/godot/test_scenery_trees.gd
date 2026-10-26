# Scenery trees (docs/scenery.md §3.2): with the foliage textures setup composes, each tree kind is one textured
# surface (scenery_foliage.gdshader: leaf cards, a solid core, the trunk) and its far model the solid plain canopy
# (scenery_foliage_far.gdshader); without them (an empty textures folder) the trees fall back to the plain models
# (scenery_tree.gdshader: trunk and canopy).
extends "res://../tests/godot/base.gd"

const TMP := "user://test_scenery_trees"


func run() -> void:
	var Scenery: GDScript = load("res://terrain/scenery.gd")
	var GroundTextures: GDScript = load("res://terrain/ground_textures.gd")

	# --- the fallback: no textures ---
	DirAccess.make_dir_recursive_absolute(TMP.path_join("thirdparty/ambientcg"))
	GroundTextures.base_dir = ProjectSettings.globalize_path(TMP)
	Scenery.reset_trees()
	check(Scenery.foliage() == null, "no foliage files: no texture")
	for kind in Scenery.KINDS.size():
		var near: ArrayMesh = Scenery.tree_mesh(kind)
		var far: ArrayMesh = Scenery.tree_mesh(kind, true)
		var m: ShaderMaterial = near.surface_get_material(0)
		check(
			near.get_surface_count() == 2 and m.shader == Scenery.TREE_SHADER,
			"fallback kind %d: the plain trunk and canopy" % kind
		)
		check(far.surface_get_material(0).shader == Scenery.TREE_SHADER, "fallback kind %d: plain far model" % kind)

	# --- with the textures (setup's foliage step) ---
	GroundTextures.base_dir = ""
	Scenery.reset_trees()
	if Scenery.foliage() == null:
		print("SKIP textured trees: setup has not composed the foliage (assets/thirdparty/ambientcg/trees)")
	else:
		var tex: Texture2DArray = Scenery.foliage()
		check(tex.get_layers() == Scenery.FOLIAGE_LAYERS.size() and tex.has_mipmaps(), "4 layers with mipmaps")
		for kind in Scenery.KINDS.size():
			var near: ArrayMesh = Scenery.tree_mesh(kind)
			var far: ArrayMesh = Scenery.tree_mesh(kind, true)
			var m: ShaderMaterial = near.surface_get_material(0)
			check(
				near.get_surface_count() == 1 and m.shader == Scenery.FOLIAGE_SHADER,
				"kind %d: one textured surface" % kind
			)
			var tn := _triangles(near)
			var tf := _triangles(far)
			check(tn <= 140 and tf < tn, "kind %d: %d triangles near, %d far" % [kind, tn, tf])
			var cols: PackedColorArray = near.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			check(cols.size() == near.surface_get_array_len(0), "kind %d: vertex colours (occlusion, sway)" % kind)
			check(far.surface_get_material(0).shader == Scenery.FOLIAGE_FAR_SHADER, "kind %d: solid far model" % kind)
	Scenery.reset_trees()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP.path_join("thirdparty/ambientcg")))


func _triangles(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var idx := mesh.surface_get_array_index_len(s)
		n += (idx if idx > 0 else mesh.surface_get_array_len(s)) / 3
	return n
