# Model detail (ours, Graphics → MORE → Model detail: ambientCG; docs/rendering.md §9): fine CC0 surface detail
# (normal, roughness, brightness: paint chips, scratches, grime) on the original models up close, over each model's own
# texture, so its colours and markings stay. The materials come from setup's textures step (iaf_tools::thirdparty
# MODEL_DETAIL, packed as DXT5 with every mip level) into assets/thirdparty/ambientcg; without them the switch has no
# effect and its row says "Not downloaded".
#
# Each mesh surface gets a detail class from what the original data gives: the model's folder under converted/objects
# (weapons, planes, ground / sea forces, stationary), the stationary model's own folder (hangars, containers, metal
# structures; ground decals and tents stay as they are), the gear legs' frames (LdgL / LdgR / LdgF / LdGr: tyres on
# their dark texels) and the material (blended = glass, canopies, rotor discs, windows: left as they are).
extends RefCounted

const SHADER_INC := "res://util/model_detail.gdshaderinc"

## The material classes, in the order of setup's list (iaf_tools::thirdparty::MODEL_DETAIL, `model.json`).
const MATERIALS := ["painted", "worn", "concrete", "rubber"]
## The look per detail class: the ambientCG material (a MATERIALS class), metres per
## repeat, normal strength, mean roughness and how much of the pack's roughness variation shows, metallic, brightness
## modulation.
const LOOKS := {
	"store": {"mat": "painted", "tile": 0.8, "normal": 1.6, "rough": 0.42, "var": 1.0, "metal": 0.0, "tint": 0.45},
	"aircraft": {"mat": "painted", "tile": 1.2, "normal": 1.3, "rough": 0.48, "var": 1.0, "metal": 0.0, "tint": 0.35},
	"vehicle": {"mat": "worn", "tile": 1.5, "normal": 1.6, "rough": 0.62, "var": 1.0, "metal": 0.0, "tint": 0.45},
	"concrete": {"mat": "concrete", "tile": 3.0, "normal": 1.5, "rough": 0.9, "var": 0.8, "metal": 0.0, "tint": 0.4},
}
## Tyres (`gear` on): the rubber pack on the gear's dark texels.
const RUBBER := {"mat": "rubber", "tile": 0.25, "rough": 0.92, "dark": 0.16}
## Detail fades out between these view distances (m) and is not sampled beyond.
const FADE := Vector2(40.0, 120.0)

## Class by the model's folder under converted/objects (planes: converted/planes, the flown and AI jets).
const FOLDER_CLASS := {
	"weapons": "store",
	"controllableplanes": "aircraft",
	"noncontrollableplanes": "aircraft",
	"planes": "aircraft",
	"groundforces": "vehicle",
	"seaforces": "vehicle",
	"stationary": "concrete",
}
## Stationary models by their folder: metal (the hangar shell, containers, masts, tanks, towers) and none (tents,
## craters). A corrugated-sheet pack was tried on the hangar: mapped triplanar it crossed the corrugation its own
## texture paints and ribbed its brick wall, so the metal ones take the worn paint.
const STATIONARY_CLASS := {
	"hgrsk1": "vehicle",
	"cntnr": "vehicle",
	"antenas": "vehicle",
	"ftank": "vehicle",
	"hvtgpl": "vehicle",
	"wtrtwr": "vehicle",
	"radum": "vehicle",
	"tent10": "",
	"crater": "",
}
## Gear leg frames (docs/part-animation.md): their meshes get the tyre variant. LdgDr (the doors) stays painted.
const GEAR_FRAMES := ["LdgL", "LdgR", "LdgF", "LdGr"]
## The pilots (crew parts 0x14 / 0x15): cloth and helmets, left as they are.
const PILOT_FRAMES := ["pilot", "pilotB"]

static var _packs := {}  # material class -> [Texture2D, mean roughness]; null = not loaded / missing
static var _manifest = null  # material class -> its nr.bc3 path
static var _tasks := {}  # material class -> WorkerThreadPool task id (loading)
static var _images := {}  # material class -> [Image, mean roughness] loaded by a task, null = unreadable
static var _images_lock := Mutex.new()  # the tasks write _images at once
static var _shaders := {}  # cull mode -> Shader
static var _mats := {}  # [base material's file and index, class, gear] -> ShaderMaterial (shared by every instance)


static func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


## The ambientCG folder (Ground textures' own, so a test pointing that elsewhere moves both).
static func _dir() -> String:
	return _ground().dir()


## terrain/ground_textures.gd, loaded when first needed (it names the Settings autoload, which a script preloading
## this one may compile before).
static func _ground() -> GDScript:
	return load("res://terrain/ground_textures.gd")


## {material class: its pack (`<id>/nr.bc3`)} from setup's list `model.json`; empty when missing.
static func manifest() -> Dictionary:
	if _manifest == null:
		_manifest = {}
		var p := _dir().path_join("model.json")
		var mats: Array = _settings().load_json(p).get("materials", []) if FileAccess.file_exists(p) else []
		for k in mini(mats.size(), MATERIALS.size()):
			_manifest[MATERIALS[k]] = _dir().path_join(String(mats[k].id)).path_join("nr.bc3")
	return _manifest


## True when every material is on disk (the switch can be picked).
static func available() -> bool:
	var m := manifest()
	for mat in MATERIALS:
		if not FileAccess.file_exists(String(m.get(mat, "-"))):
			return false
	return true


## True when models load with the detail: the switch on and the materials there.
static func enabled() -> bool:
	return String(_settings().get("model_detail")) == "ambientcg" and available()


## Starts reading every pack in the background (the front end calls it while the mission's screens are open, the
## flight scene at its start), so no frame waits for the disk.
static func preload_packs() -> void:
	if not enabled():
		return
	for mat in MATERIALS:
		if not _packs.has(mat) and not _tasks.has(mat):
			_tasks[mat] = WorkerThreadPool.add_task(
				_load_pack.bind(mat, String(manifest().get(mat, ""))), false, "model detail pack"
			)


## Waits for the pack loads nobody took and drops their images. At exit (Settings, see Gltf.finish_ahead).
static func finish_packs() -> void:
	for t in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	_images_lock.lock()
	_images.clear()
	_images_lock.unlock()


## Worker: the pack of `mat` at `path` (setup's DXT5 with its mips: R roughness, G / A normal, B brightness) and its
## mean roughness (the 1×1 mip's).
static func _load_pack(mat: String, path: String) -> void:
	var img: Image = _ground().mips(path, Image.FORMAT_DXT5, 16)
	var r = null
	if img != null:
		var last := img.get_mipmap_count()
		var one := Image.create_from_data(
			1, 1, false, Image.FORMAT_DXT5, img.get_data().slice(img.get_mipmap_offset(last))
		)
		one.decompress()
		r = [img, one.get_pixel(0, 0).r]
	_images_lock.lock()
	_images[mat] = r
	_images_lock.unlock()


## The pack of material class `mat` ([texture, mean roughness], [] when missing): waits for its load if still
## running (a flight scene that started without the front end's preload).
static func pack(mat: String) -> Array:
	if not _packs.has(mat):
		if not _tasks.has(mat):
			_tasks[mat] = WorkerThreadPool.add_task(_load_pack.bind(mat, String(manifest().get(mat, ""))))
		WorkerThreadPool.wait_for_task_completion(_tasks[mat])
		_tasks.erase(mat)
		_images_lock.lock()
		var r = _images.get(mat)
		_images.erase(mat)
		_images_lock.unlock()
		_packs[mat] = [ImageTexture.create_from_image(r[0]), r[1]] if r != null else null
	return _packs[mat] if _packs[mat] != null else []


## The detail class of a model at `path` (a converted model's file), "" for none.
static func model_class(path: String) -> String:
	var assets: String = _settings().assets_dir()
	if not path.begins_with(assets):
		return ""  # ours (the detailed F-16D, the extra planes): their own maps
	var rel := path.trim_prefix(assets).trim_prefix("/").trim_prefix("converted/")
	var parts := rel.split("/")
	var top := parts[0] if parts[0] != "objects" else (parts[1] if parts.size() > 1 else "")
	var cls: String = FOLDER_CLASS.get(top, "")
	if cls == "concrete":
		var name := parts[2] if parts.size() > 2 else ""
		if "_ul" in path.get_file():
			return ""  # flat airbase surface pieces (the under layer): the ground's, not a model's
		cls = STATIONARY_CLASS.get(name, cls)
	return cls


## Puts the detail on every surface of `node` (a new scene of the model at `path`) that takes it.
static func apply(node: Node3D, path: String) -> void:
	var cls := model_class(path)
	if cls == "" or not enabled():
		return
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if _under(mi, node, PILOT_FRAMES):
			continue
		var gear := cls == "aircraft" and _under(mi, node, GEAR_FRAMES)
		for s in mi.mesh.get_surface_count():
			var sm := detail_material(mi.get_active_material(s), cls, gear)
			if sm != null:
				mi.set_surface_override_material(s, sm)


static func _under(n: Node, root: Node, frames: Array) -> bool:
	while n != null and n != root:
		if String(n.name) in frames:
			return true
		n = n.get_parent()
	return false


## The shared detail material standing in for `base` in class `cls` (gear: with tyres), or null when `base` keeps its
## own look (blended glass, unshaded or glowing, point-sampled at OBJECT DETAIL 1).
static func detail_material(base: Material, cls: String, gear := false) -> ShaderMaterial:
	var bm := base as BaseMaterial3D
	if bm == null or not LOOKS.has(cls):
		return null
	var t := bm.transparency
	if t != BaseMaterial3D.TRANSPARENCY_DISABLED and t != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return null
	if bm.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or bm.emission_enabled:
		return null
	if bm.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		return null
	# Every parse of a model makes its own materials (AircraftModel opens the glTF per jet): shared by the file's own
	# material instead, so every jet of a type draws with one material per surface.
	var key := [bm.get_meta("model_key", bm), cls, gear]
	if _mats.has(key):
		return _mats[key]
	var look: Dictionary = LOOKS[cls]
	var p := pack(look.mat)
	var p2 := pack(RUBBER.mat) if gear else []
	if p.is_empty() or (gear and p2.is_empty()):
		return null
	var sm := ShaderMaterial.new()
	sm.shader = _shader(bm.cull_mode)
	sm.set_meta("base", bm)
	sm.set_shader_parameter("albedo", bm.albedo_color)
	sm.set_shader_parameter("has_tex", bm.albedo_texture != null)
	sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
	sm.set_shader_parameter("roughness", bm.roughness)
	sm.set_shader_parameter("specular", bm.metallic_specular)
	sm.set_shader_parameter("alpha_scissor", bm.alpha_scissor_threshold if t != 0 else 0.0)
	sm.set_shader_parameter("pack", p[0])
	sm.set_shader_parameter("rough_mean", p[1])
	sm.set_shader_parameter("tile_m", look.tile)
	sm.set_shader_parameter("rough_mid", look.rough)
	sm.set_shader_parameter("rough_var", look.var)
	sm.set_shader_parameter("metallic", look.metal)
	sm.set_shader_parameter("normal_strength", look.normal)
	sm.set_shader_parameter("tint_strength", look.tint)
	sm.set_shader_parameter("fade_near", FADE.x)
	sm.set_shader_parameter("fade_far", FADE.y)
	sm.set_shader_parameter("gear", gear)
	if gear:
		sm.set_shader_parameter("pack2", p2[0])
		sm.set_shader_parameter("rough2_mean", p2[1])
		sm.set_shader_parameter("tile2_m", RUBBER.tile)
		sm.set_shader_parameter("rough2_mid", RUBBER.rough)
		sm.set_shader_parameter("dark_below", RUBBER.dark)
	_mats[key] = sm
	return sm


## The original material behind a surface's material (the detail material's base), for code that reads its texture.
static func base_material(m: Material) -> Material:
	return m.get_meta("base") if m != null and m.has_meta("base") else m


## The detail shader for cull mode `cull` (BaseMaterial3D.CullMode): cull_back for every original material but the
## few two-sided ones.
static func _shader(cull: int) -> Shader:
	if not _shaders.has(cull):
		var modes := ["cull_back", "cull_front", "cull_disabled"]
		var sh := Shader.new()
		sh.code = 'shader_type spatial;\nrender_mode %s;\n#include "%s"\n' % [modes[clampi(cull, 0, 2)], SHADER_INC]
		_shaders[cull] = sh
	return _shaders[cull]


## Draws every detail shader and pack once, too small to see, in front of `camera` until `until` frees the node: the
## flight scene calls it behind its loading screen, so the GPU pipelines and textures are ready before the first model
## shows (no hitch when a jet, a store or a vehicle first comes into view). Null when the detail is off.
static func warm_up(camera: Camera3D) -> Node3D:
	if not enabled():
		return null
	var n := Node3D.new()
	n.name = "ModelDetailWarmUp"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.001, 0.001)
	var k := 0
	for cls in LOOKS:
		for cull in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_DISABLED]:
			var base := StandardMaterial3D.new()
			base.cull_mode = cull
			base.set_meta("model_key", "warm-up:%s:%d" % [cls, cull])
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = detail_material(base, cls, cls == "aircraft")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(0.0001 * k, 0.0, -0.5)
			n.add_child(mi)
			k += 1
	camera.add_child(n)
	return n
