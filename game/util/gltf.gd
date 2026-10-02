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


## A new scene of a model opened with open().
static func instance(model: Array) -> Node3D:
	return model[0].generate_scene(model[1]) as Node3D

