# Runtime loading of the converted glTF models (objects, aircraft, weapons, the viewer).
extends RefCounted

## The renderer's OBJECT DETAIL level 1..3 (1 − ftol(−2·slider), FUN_004d8ce0 → 0x7d1924), set by the flight
## scene before it loads models. Besides the LOD switch (terrain_view.gd) it sets the render states of every
## object (FUN_0040bd90): level 1 point-sampled textures (D3D TEXTUREMAG / MIN = NEAREST), level 3 specular.
static var object_level := 3


static func detail_level(slider: float) -> int:
	return clampi(1 + floori(2.0 * slider + 1e-4), 1, 3)

## Parses a glTF file: [GLTFDocument, GLTFState], or null when missing / unreadable. Godot's runtime
## glTF import creates the textures without mipmaps, so a model seen from afar samples its full-size
## texture and shimmers while the camera moves; every texture gets mipmaps and anisotropic filtering.
static func open(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var done := {}
	for m in state.get_materials():
		var bm := m as BaseMaterial3D
		if bm == null:
			continue
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if object_level == 1 \
				else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if object_level < 3:
			bm.metallic_specular = 0.0  # SPECULARENABLE off
		var t := bm.albedo_texture
		if t == null:
			continue
		if not done.has(t):
			var img := t.get_image()
			if img != null and not img.has_mipmaps() and not img.is_compressed():
				img.generate_mipmaps()
				done[t] = ImageTexture.create_from_image(img)
			else:
				done[t] = t
		bm.albedo_texture = done[t]
	return [doc, state]


## open() of a converted object model (path under converted/objects), cached per OBJECT DETAIL level.
static var _objects := {}


static func object(path: String) -> Variant:
	var key := "%d:%s" % [object_level, path]
	if not _objects.has(key):
		# The autoload by node: this script also loads before the autoloads exist (tests preload it).
		var settings: Node = Engine.get_main_loop().root.get_node("Settings")
		_objects[key] = open(settings.assets_dir().path_join("converted/objects").path_join(path))
	return _objects[key]


## A new scene of a model opened with open().
static func instance(model: Array) -> Node3D:
	return model[0].generate_scene(model[1]) as Node3D



## Where model_aabb() measures each mesh: its own frame (no transform), the model node's frame, the world.
enum { MESH_SPACE, NODE_SPACE, GLOBAL_SPACE }


## The merged bounds of every mesh under `node`, each in `space` (the mesh's own frame when the node is
## outside the tree); AABB() when it has none.
static func model_aabb(node: Node3D, space := NODE_SPACE) -> AABB:
	var inv := node.global_transform.affine_inverse() if space == NODE_SPACE and node.is_inside_tree() else Transform3D.IDENTITY
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.get_aabb() if space == MESH_SPACE or not node.is_inside_tree() else (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
