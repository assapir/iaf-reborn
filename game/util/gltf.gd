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
	var parsed = _take_parsed(path)
	if parsed == null:
		parsed = _parse(path)
	if parsed.is_empty():
		return null
	if parsed[1].get_meta("level") != object_level:
		_set_materials(parsed[1], path)  # parsed ahead at another OBJECT DETAIL level, or a texture left to read back
	return parsed


## The file's glTF parsed ([doc, state], [] when missing / unreadable), ready for open(): its images decoded, its
## textures created, its materials set for the OBJECT DETAIL level (_set_materials); a detailed model's LODs and meshes
## made. On a worker thread for parse_ahead, so the main thread only takes the result.
static func _parse(path: String) -> Array:
	var r := _parse_file(path)
	if r.is_empty():
		return r
	var state: GLTFState = r[1]
	state.set_meta("path", path)
	_set_materials(state, path)
	if is_detailed(path):
		for gm: GLTFMesh in state.get_meshes():
			gm.mesh.generate_lods(25.0, 60.0, [])
			gm.mesh.get_mesh()  # kept by the ImporterMesh: generate_scene() takes it
	return r


## The file read: its base colour images decoded by _own_textures, the other textures (a detailed model's normal and
## ORM maps, embedded) as Godot's import makes them.
static func _parse_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if path.get_extension() != "glb":  # a .glb embeds its images
		state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_DISCARD_TEXTURES
		if doc.append_from_file(path, state) != OK:
			return []
	if state.json.is_empty() or state.json.get("images", []).any(func(im): return not im.has("uri")):
		doc = GLTFDocument.new()
		state = GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			return []
	_own_textures(state, path.get_base_dir())
	return [doc, state]


## Each material's settings for the OBJECT DETAIL level (object_level, recorded as the state's "level"): its texture
## filter, its specular, its key for Model detail, and its base colour texture mipmapped. A texture _own_textures did
## not make is read back from the GPU for that, on the main thread only (a worker would wait for its frame).
static func _set_materials(state: GLTFState, path: String) -> void:
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	var level := object_level
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
		if t == null or t.has_meta("mipmapped"):
			continue
		if not main:
			level = -1  # open() finishes it
			continue
		if not done.has(t):
			var img := t.get_image()
			if img != null and not img.has_mipmaps() and not img.is_compressed():
				img.generate_mipmaps()
				done[t] = ImageTexture.create_from_image(img)
			else:
				done[t] = t
		bm.albedo_texture = done[t]
	state.set_meta("level", level)


## Gives each material its base colour texture from its image (a file beside the model, or embedded in the .glb),
## mipmapped (marked "mipmapped" for _set_materials).
static func _own_textures(state: GLTFState, dir: String) -> void:
	var images: Array = state.json.get("images", [])
	var textures: Array = state.json.get("textures", [])
	var json_mats: Array = state.json.get("materials", [])
	var made := {}
	var mats := state.get_materials()
	for i in mini(mats.size(), json_mats.size()):
		var bm := mats[i] as BaseMaterial3D
		var ti = json_mats[i].get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index")
		if bm == null or ti == null or int(ti) >= textures.size():
			continue
		var tex: Dictionary = textures[int(ti)]
		var src := int(tex.get("extensions", {}).get("KHR_texture_basisu", tex).get("source", -1))
		if not made.has(src):
			made[src] = bm.albedo_texture  # as parsed (null with the textures discarded) unless decoded here
			var img := _image(state, images[src], dir) if src >= 0 and src < images.size() else null
			if img != null:
				if not img.has_mipmaps() and not img.is_compressed():
					img.generate_mipmaps()
				if (dir + "/" == STORES_DIR or _made_by_setup(dir + "/")) and RenderingServer.has_os_feature("s3tc"):
					img.compress(Image.COMPRESS_S3TC)  # the CPU encoder (rendering.md §1.5), ≈ 3 ms a 512² image
				made[src] = ImageTexture.create_from_image(img)
				made[src].set_meta("mipmapped", true)
		bm.albedo_texture = made[src]


## A glTF image: its file in `dir`, or its buffer view (PNG, JPEG, KTX2); null when unreadable.
static func _image(state: GLTFState, im: Dictionary, dir: String) -> Image:
	if im.has("uri"):
		return Image.load_from_file(dir.path_join(String(im.uri).uri_decode()))
	if not im.has("bufferView") or int(im.bufferView) >= state.get_buffer_views().size():
		return null
	var bytes: PackedByteArray = state.get_buffer_views()[int(im.bufferView)].load_buffer_view_data(state)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match String(im.get("mimeType", "")):
		"image/ktx2":
			err = img.load_ktx_from_buffer(bytes)
		"image/png":
			err = img.load_png_from_buffer(bytes)
		"image/jpeg":
			err = img.load_jpg_from_buffer(bytes)
	return img if err == OK else null


## Models parsed ahead on worker threads (parse_ahead): full path -> task id, then -> _parse()'s result.
static var _ahead_tasks := {}
static var _ahead := {}
static var _ahead_lock := Mutex.new()
## Dropped parses still running (drop_ahead): full path -> task id; their results are discarded once done.
static var _stale := {}


## Starts parsing the models at the full `paths` on worker threads (low priority), so model() / object() only finish
## them (the mission screens and the flight's loading screen: the mission's models, ≈ 20–240 ms each; a detailed model
## ≈ 0.4 s with its LODs). A model already opened, or with a detailed stand-in (pass the stand-in), is skipped.
static func parse_ahead(paths: Array) -> void:
	for p in paths:
		if not _objects.has("%d:%s" % [object_level, p]) and detailed(p) == "":
			parse_file_ahead(p)


## parse_ahead() of a file for open(path).
static func parse_file_ahead(path: String) -> void:
	if not _ahead_tasks.has(path):
		_ahead_tasks[path] = WorkerThreadPool.add_task(_parse_task.bind(path), false, "glTF parse")


## True when parse_ahead's work for the full path `p` is done or was never asked for.
static func parsed_ahead(p: String) -> bool:
	return not _ahead_tasks.has(p) or WorkerThreadPool.is_task_completed(_ahead_tasks[p])


## Drops the parses ahead that nobody took, but for the full paths in `keep` (a new mission or jet chosen, the flight
## started): finished ones at once, running ones once they finish (later calls). The memory stays one mission's.
static func drop_ahead(keep: Array = []) -> void:
	var kept := {}
	for p in keep:
		kept[p] = true
	for p in _ahead_tasks.keys():
		if not kept.has(p):
			_stale[p] = _ahead_tasks[p]
			_ahead_tasks.erase(p)
	for p in _stale.keys():
		if WorkerThreadPool.is_task_completed(_stale[p]):
			WorkerThreadPool.wait_for_task_completion(_stale[p])
			_stale.erase(p)
			if not _ahead_tasks.has(p):  # asked for again meanwhile: that task's result stays
				_ahead_lock.lock()
				_ahead.erase(p)
				_ahead_lock.unlock()


## Waits for every parse ahead still running and drops the results nobody took. At exit (Settings): a low-priority
## pool task still queued at the quit hangs Godot 4.7.2's exit for good (docs/rendering.md §1.5, "Pool tasks at
## exit"), so every pool task the game posts is waited for before it.
static func finish_ahead() -> void:
	for t in _ahead_tasks.values() + _stale.values():
		WorkerThreadPool.wait_for_task_completion(t)
	_ahead_tasks.clear()
	_stale.clear()
	_ahead_lock.lock()
	_ahead.clear()
	_ahead_lock.unlock()


static func _parse_task(full: String) -> void:
	var r := _parse(full)
	_ahead_lock.lock()
	_ahead[full] = r
	_ahead_lock.unlock()


## parse_ahead's result for `path`, null when it was not asked for or is not done yet: then the caller parses it
## itself and the task's result is dropped (a queued task may wait behind the whole mission's models).
static func _take_parsed(path: String) -> Variant:
	if not _ahead_tasks.has(path):
		return null
	if not WorkerThreadPool.is_task_completed(_ahead_tasks[path]):
		drop_ahead(_ahead_tasks.keys().filter(func(p): return p != path))
		return null
	WorkerThreadPool.wait_for_task_completion(_ahead_tasks[path])
	_ahead_tasks.erase(path)
	_ahead_lock.lock()
	var r = _ahead.get(path, [])
	_ahead.erase(path)
	_ahead_lock.unlock()
	return r


## open() of a converted object model (path under converted/objects), cached per OBJECT DETAIL level; with
## Models: Detailed its detailed model when there is one (detailed()) and `allow_detailed`.
static var _objects := {}


static func object(path: String, allow_detailed := true) -> Variant:
	var hd := detailed(path) if allow_detailed else ""
	if hd != "":
		return model(hd)
	return model(objects_path(path))


## The full path of a converted object model (path under converted/objects).
static func objects_path(path: String) -> String:
	return _settings().assets_dir().path_join("converted/objects").path_join(path)


## open() of the model at the full `path`, cached per OBJECT DETAIL level: every unit and jet of a type shares it.
static func model(path: String) -> Variant:
	var key := "%d:%s" % [object_level, path]
	if not _objects.has(key):
		_objects[key] = open(path)
	return _objects[key]


## The autoload by node: this script also loads before the autoloads exist (tests preload it).
static func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


## Detailed models (ours, Graphics → MORE → Models: Detailed; docs/aircraft-models.md): the original model's
## file -> our model: in the repo (res://, GPL, tools/f16d/rig.py) or made by setup under assets/ (the F-15, §6).
## Each model falls back on the original on its own (the F-15 also when setup could not download its sources).
const DETAILED := {"f16_h.gltf": "res://extra/models/f16/f16d.glb", "f15_h.gltf": "converted/models/f15/f15c.glb"}
## The detailed stores (GPL, tools/stores/build.gd; docs/aircraft-models.md §5), as DETAILED. Their textures are
## compressed (BC1) at the parse.
const STORES_DIR := "res://extra/models/stores/"
const STORES := {
	"aim9_m.gltf": "aim9",
	"aim7_m.gltf": "aim7",
	"aim120_m.gltf": "aim120",
	"agm65_m.gltf": "agm65",
	"agm88_m.gltf": "agm88",
	"mk82_m.gltf": "mk82",
	"mk83_m.gltf": "mk83",
	"mk84_m.gltf": "mk84",
	"mk82lb_m.gltf": "mk82lb",
	"mk83lb_m.gltf": "mk83lb",
	"mk84lb_m.gltf": "mk84lb",
	"cbu87_m.gltf": "cbu87",
	"cbu93_m.gltf": "cbu87",
	"f16ftk_m.gltf": "f16ftk",
	"f16ftkm.gltf": "f16ftkm",
	"ecmpod_m.gltf": "ecmpod",
	"flrpod_m.gltf": "flrpod",
}


## The detailed model standing in for the original at `path` with the switch on, else "".
static func detailed(path: String) -> String:
	if String(_settings().get("models")) != "detailed":
		return ""
	var f := path.get_file()
	var hd: String = DETAILED.get(f, STORES_DIR + STORES[f] + ".glb" if STORES.has(f) else "")
	if hd != "" and not hd.begins_with("res://"):
		hd = _settings().assets_dir().path_join(hd)
	return hd if hd != "" and FileAccess.file_exists(hd) else ""


## Every detailed store's file (parse_ahead before the flight: a loadout can carry any).
static func detailed_stores() -> Array:
	var out := {}
	for n in STORES.values():
		out[STORES_DIR + n + ".glb"] = true
	return out.keys()


## True for our detailed models (DETAILED, STORES): parsed with LODs. By the path alone (the parse runs on workers).
static func is_detailed(path: String) -> bool:
	return DETAILED.values().has(path) or path.begins_with(STORES_DIR) or _made_by_setup(path)


## A detailed model setup made under assets/ (DETAILED's paths without res://): its textures are compressed at the
## parse, as the stores'.
static func _made_by_setup(path: String) -> bool:
	return path.contains("/converted/models/")


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
