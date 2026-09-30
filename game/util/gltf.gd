# Runtime loading of the converted glTF models (objects, aircraft, weapons, the viewer).
extends RefCounted

const UNDERLAY_SHADER := preload("res://terrain/underlay.gdshader")


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
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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


## A flat ground model (the airbases' runway / taxiway / apron underlays, ul_rw*.x) lies exactly on
## the terrain, which the original flattens around airbases: drawn as-is it z-fights with the ground
## imagery below it. Its surfaces get terrain/underlay.gdshader, which draws them a little towards the
## camera (docs/deviations.md).
static func make_underlay(node: Node3D) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s) as BaseMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = UNDERLAY_SHADER
			if src != null:
				mat.set_shader_parameter("albedo", src.albedo_color)
				mat.set_shader_parameter("albedo_tex", src.albedo_texture)
				mat.set_shader_parameter("roughness", src.roughness)
				mat.set_shader_parameter("metallic", src.metallic)
			m.set_surface_override_material(s, mat)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
