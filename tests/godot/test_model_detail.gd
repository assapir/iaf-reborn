# Model detail (Graphics → MORE → Model detail, docs/rendering.md "Model detail", util/model_detail.gd): off (the
# default) every model keeps its original materials; on, the stores, the jets, the vehicles and the airbase buildings
# get the shared detail material of their class over their own texture, the tyres the gear variant, while glass
# (blended materials), the pilots and the airbase's flat surface pieces keep theirs; without the downloaded materials
# the switch changes nothing and its row says so. The packs are DXT5-compressed and stay inside the video memory budget.
extends "res://../tests/godot/base.gd"

const Gltf := preload("res://util/gltf.gd")
const ModelDetail := preload("res://util/model_detail.gd")
## The video memory budget of the packs (MiB).
const VRAM_MIB := 32.0

var aircraft_model: GDScript


func run() -> void:
	aircraft_model = load("res://aircraft/aircraft_model.gd")
	check(settings().model_detail == "original", "Model detail defaults to Original")
	var off: Node3D = aircraft_model.create("cfir", 130, true)
	check(_detail_surfaces(off).is_empty(), "off: the Kfir keeps its original materials")
	off.free()
	if not ModelDetail.available():
		print("SKIP the materials are not downloaded (iaf-convert model-detail assets/thirdparty/ambientcg)")
		_check_missing()
		return
	settings().model_detail = "ambientcg"
	ModelDetail.preload_packs()  # as the front end does: in the background

	# The jet: body detailed, the canopy (blended) and the pilots as they are, the gear legs with tyres.
	var jet: Node3D = aircraft_model.create("cfir", 130, true)
	var surf := _detail_surfaces(jet)
	check(surf.size() > 0, "on: the Kfir's surfaces take the detail (%d)" % surf.size())
	var glass := 0
	var glass_detailed := 0
	var gear := 0
	var pilots_detailed := 0
	var bases_kept := true
	for mi: MeshInstance3D in jet.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var active := mi.get_active_material(s)
			if base != null and base.transparency not in [0, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:
				glass += 1
				glass_detailed += int(active is ShaderMaterial)
			if active is ShaderMaterial:
				if (active as ShaderMaterial).get_shader_parameter("gear"):
					gear += 1
				if ModelDetail._under(mi, jet, ModelDetail.PILOT_FRAMES):
					pilots_detailed += 1
				var b0 := ModelDetail.base_material(active) as BaseMaterial3D
				bases_kept = bases_kept and b0.get_meta("model_key") == base.get_meta("model_key")
	check(bases_kept, "on: each detail material stands for its surface's own material")
	check(glass > 0 and glass_detailed == 0, "on: the canopy glass keeps its own material (%d surfaces)" % glass)
	check(gear > 0, "on: the gear legs take the tyre variant (%d surfaces)" % gear)
	check(pilots_detailed == 0, "on: the pilots keep their own materials")

	# One shared material per base material and class: a second jet adds none.
	var jet2: Node3D = aircraft_model.create("cfir", 130, true)
	var surf2 := _detail_surfaces(jet2)
	check(surf2 == surf, "on: a second Kfir shares the first one's detail materials")
	jet.free()
	jet2.free()

	# The objects by class.
	var cases := {
		"weapons/mk82/mk82_m.gltf": "store",
		"weapons/f4ftk/f4ftk_m.gltf": "store",
		"groundforces/t62/t62_h.gltf": "vehicle",
		"seaforces/isrlsp_h/isrlsp_h.gltf": "vehicle",
		"stationary/hgrdr1/hgrdr1_h.gltf": "concrete",
		"stationary/hgrsk1/hgrsk1_h.gltf": "vehicle",
		"stationary/concrite/hgr_ul_1.gltf": "",
		"stationary/tent10/tent10_h.gltf": "",
	}
	for path in cases:
		var full: String = settings().assets_dir().path_join("converted/objects").path_join(path)
		check(ModelDetail.model_class(full) == cases[path], "class of %s: '%s'" % [path, cases[path]])
		var model = Gltf.object(path)
		if model == null:
			print("SKIP %s: not converted" % path)
			continue
		var n := Gltf.instance(model)
		var tile := -1.0
		for sm: ShaderMaterial in _detail_surfaces(n):
			tile = sm.get_shader_parameter("tile_m")
		var want: float = ModelDetail.LOOKS[cases[path]].tile if cases[path] != "" else -1.0
		check(tile == want, "%s: detail %s" % [path, "of its class" if want > 0 else "none"])
		n.free()

	# Two shaders in all (the cull modes), and the warm-up draws every class with them before a flight shows models.
	check(ModelDetail._shaders.size() <= 2, "shaders: %d (one per cull mode)" % ModelDetail._shaders.size())
	var cam := Camera3D.new()
	root.add_child(cam)
	var warm := ModelDetail.warm_up(cam)
	check(
		warm != null and warm.get_child_count() == ModelDetail.LOOKS.size() * 2,
		"warm-up: every class in both cull modes (%d draws)" % (warm.get_child_count() if warm != null else 0)
	)
	cam.free()

	# The packs: DXT5 with mipmaps, inside the budget.
	var bytes := 0
	for mat in ModelDetail.manifest():
		var p := ModelDetail.pack(String(mat))
		var img := (p[0] as ImageTexture).get_image()
		check(
			img.get_format() == Image.FORMAT_DXT5 and img.has_mipmaps(),
			"pack %s: DXT5, %d px, mipmaps" % [mat, img.get_width()]
		)
		bytes += img.get_data_size()
	check(bytes / 1048576.0 <= VRAM_MIB, "packs: %.1f MiB of video memory (budget %d)" % [bytes / 1048576.0, VRAM_MIB])
	_check_missing()
	settings().model_detail = "original"


## Missing materials (offline setup): the switch on changes nothing.
func _check_missing() -> void:
	var keep = ModelDetail._manifest
	ModelDetail._manifest = {}
	settings().model_detail = "ambientcg"
	check(not ModelDetail.available() and not ModelDetail.enabled(), "missing: not available, not enabled")
	var jet: Node3D = aircraft_model.create("cfir", 130, true)
	check(_detail_surfaces(jet).is_empty(), "missing: the Kfir keeps its original materials with the switch on")
	jet.free()
	ModelDetail._manifest = keep
	settings().model_detail = "original"


## The detail materials on `node`'s surfaces (unique, in order).
func _detail_surfaces(node: Node3D) -> Array:
	var out := []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if m is ShaderMaterial and not out.has(m):
				out.append(m)
	return out
