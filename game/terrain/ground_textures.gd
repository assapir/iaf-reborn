# Ground textures (Graphics → MORE, Settings.ground_textures; docs/rendering.md §1.4): the CC0 ambientCG materials setup
# downloads and packs (iaf_tools::thirdparty, assets/thirdparty/ambientcg/<id>/), as two texture arrays for
# terrain.gdshader. Setup stores them compressed as the GPU reads them (DXT1 colour, DXT5 roughness / normal, every mip
# level), so the game only reads the files (on a worker thread while the mission screens are open, preload_async) and
# uploads them at the flight's start: 7 layers of 1024² with mipmaps ≈ 15 MB of video memory.
extends RefCounted

const DIR := "thirdparty/ambientcg"
## The list terrain.gdshader reads, its layers in this order (iaf_tools::thirdparty::GROUND_TEXTURES).
const LIST := "ground.json"
const SIDE := 1024

## The folder holding DIR ("" = Settings.assets_dir(); tests point it elsewhere).
static var base_dir := ""
## The loaded layers (colour, roughness / normal), or null.
static var albedo_tex: Texture2DArray
static var nr_tex: Texture2DArray
static var _loaded := false
static var _task := -1
static var _decoded: Array = []


static func dir() -> String:
	return (base_dir if base_dir != "" else Settings.assets_dir()).path_join(DIR)


## The materials of the list ([{id, size_m, used_for}]), or [] when setup has not fetched them all.
static func materials() -> Array:
	var mats: Array = Settings.load_json(dir().path_join(LIST)).get("materials", [])
	for m in mats:
		for f in ["albedo.bc1", "nr.bc3"]:
			if not FileAccess.file_exists(dir().path_join(String(m.id)).path_join(f)):
				return []
	return mats


static func available() -> bool:
	return not materials().is_empty()


## Starts reading the textures on a worker thread (the mission screens, terrain_preload.gd), so the
## flight's start only uploads them.
static func preload_async() -> void:
	if _loaded or _task >= 0 or Settings.ground_textures != "ambientcg" or not available():
		return
	_task = WorkerThreadPool.add_task(_decode_task, false, "ground textures")


static func _decode_task() -> void:
	_decoded = _decode()


## Sets the shader globals ground_albedo / ground_nr (the layers) and ground_scale_a / _b (1 / metres per repeat, layers
## 0–3 / 4–7) once (waiting for preload_async's work, else reading here); false when the textures are missing.
static func load_globals() -> bool:
	if _loaded:
		return true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	else:
		_decoded = _decode()
	var d := _decoded
	_decoded = []
	if d.is_empty():
		return false
	var ta := Texture2DArray.new()
	var tn := Texture2DArray.new()
	if ta.create_from_images(d[0]) != OK or tn.create_from_images(d[1]) != OK:
		return false
	var sc: PackedFloat32Array = d[2]
	RenderingServer.global_shader_parameter_set("ground_albedo", ta)
	RenderingServer.global_shader_parameter_set("ground_nr", tn)
	RenderingServer.global_shader_parameter_set("ground_scale_a", Vector4(sc[0], sc[1], sc[2], sc[3]))
	RenderingServer.global_shader_parameter_set("ground_scale_b", Vector4(sc[4], sc[5], sc[6], sc[7]))
	albedo_tex = ta
	nr_tex = tn
	_loaded = true
	return true


## [albedo images (DXT1), roughness / normal images (DXT5), 1 / metres per repeat ×8]; [] when missing.
static func _decode() -> Array:
	var mats := materials()
	if mats.is_empty():
		return []
	var albedo: Array[Image] = []
	var nr: Array[Image] = []
	var sc := PackedFloat32Array()
	sc.resize(8)
	sc.fill(1.0)
	for k in mats.size():
		var d := dir().path_join(String(mats[k].id))
		var a := _mips(d.path_join("albedo.bc1"), Image.FORMAT_DXT1, 8)
		var n := _mips(d.path_join("nr.bc3"), Image.FORMAT_DXT5, 16)
		if a == null or n == null:
			return []
		albedo.append(a)
		nr.append(n)
		sc[k] = 1.0 / float(mats[k].size_m)
	return [albedo, nr, sc]


## A packed map: SIDE² in `format` (`block` bytes per 4×4 block) with every mip level (iaf_tools::thirdparty::compress).
static func _mips(path: String, format: Image.Format, block: int) -> Image:
	var b := FileAccess.get_file_as_bytes(path)
	var want := 0
	var s := SIDE
	while s >= 1:
		want += block * ceili(s / 4.0) ** 2
		s /= 2
	if b.size() != want:
		push_warning("ground textures: %s has %d bytes, expected %d (run setup again)" % [path, b.size(), want])
		return null
	return Image.create_from_data(SIDE, SIDE, true, format, b)
