# Runtime loading of the converted glTF models (objects, aircraft, weapons, the viewer).
extends RefCounted

const ModelDetail := preload("res://util/model_detail.gd")

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
	var mats := state.get_materials()
	for i in mats.size():
		var bm := mats[i] as BaseMaterial3D
		if bm == null:
			continue
		# The same material in every parse of the file (Model detail shares its materials by it).
		bm.set_meta("model_key", "%d:%s#%d" % [object_level, path, i])
		bm.texture_filter = (
			BaseMaterial3D.TEXTURE_FILTER_NEAREST
			if object_level == 1
			else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		)
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
	state.set_meta("path", path)
	return [doc, state]


## open() of a converted object model (path under converted/objects), cached per OBJECT DETAIL level; with
## Models: Detailed its detailed model when there is one (detailed()).
static var _objects := {}


static func object(path: String) -> Variant:
	var hd := detailed(path)
	if hd != "":
		return open_detailed(hd)
	var key := "%d:%s" % [object_level, path]
	if not _objects.has(key):
		_objects[key] = open(_settings().assets_dir().path_join("converted/objects").path_join(path))
	return _objects[key]


## The autoload by node: this script also loads before the autoloads exist (tests preload it).
static func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


## Detailed models (ours, Graphics → MORE → Models: Detailed; docs/aircraft-models.md): the original model's
## file -> our model in the repo (GPL, tools/f16d/rig.py). Each model falls back on the original on its own.
const DETAILED := {"f16_h.gltf": "res://extra/models/f16/f16d.glb"}
static var _detailed := {}


## The detailed model standing in for the original at `path` with the switch on, else "".
static func detailed(path: String) -> String:
	if String(_settings().get("models")) != "detailed":
		return ""
	var hd: String = DETAILED.get(path.get_file(), "")
	return hd if hd != "" and FileAccess.file_exists(hd) else ""


## open() of a detailed model, parsed once per OBJECT DETAIL level and shared by every jet (its textures are
## large); its meshes get LODs so far jets draw a fraction of the triangles.
static func open_detailed(path: String) -> Variant:
	var key := "%d:%s" % [object_level, path]
	if not _detailed.has(key):
		var model = open(path)
		if model != null:
			for gm: GLTFMesh in (model[1] as GLTFState).get_meshes():
				gm.mesh.generate_lods(25.0, 60.0, [])
		_detailed[key] = model
	return _detailed[key]


## A new scene of a model opened with open(), with Model detail when it is on (util/model_detail.gd). A detailed
## model's closed gear doors (LdgDrUp) start hidden: a static model stands on its gear (AircraftModel shows them once
## the gear is up).
static func instance(model: Array) -> Node3D:
	var n := model[0].generate_scene(model[1]) as Node3D
	ModelDetail.apply(n, String(model[1].get_meta("path", "")))
	var up := n.find_child("LdgDrUp", true, false)
	if up != null:
		up.visible = false
	return n


## Where model_aabb() measures each mesh: its own frame (no transform), the model node's frame, the world.
enum { MESH_SPACE, NODE_SPACE, GLOBAL_SPACE }


## The merged bounds of every mesh under `node`, each in `space` (the mesh's own frame when the node is
## outside the tree); AABB() when it has none.
static func model_aabb(node: Node3D, space := NODE_SPACE) -> AABB:
	var inv := (
		node.global_transform.affine_inverse()
		if space == NODE_SPACE and node.is_inside_tree()
		else Transform3D.IDENTITY
	)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := (
			mi.get_aabb()
			if space == MESH_SPACE or not node.is_inside_tree()
			else (inv * mi.global_transform) * mi.get_aabb()
		)
		box = b if first else box.merge(b)
		first = false
	return box
