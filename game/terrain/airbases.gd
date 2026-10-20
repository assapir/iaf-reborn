# Airbases, Detailed (Preferences → Graphics → MORE → Airbases; docs/rendering.md §7, docs/deviations.md §2): near the
# ground, terrain.gdshader draws a procedural runway, taxiway and apron surface with markings over the nearest base's
# paved surface. The runways (ends, width, designation numbers), the AI's taxi paths and the paved-surface mask come from
# the 1998 art and iaf.ibx (`iaf-terrain airbases` → assets/converted/terrain/airbases.json, crates/iaf-tools
# airbases.rs). Rendering only: the flight model's runway surface stays terraintype.dat's.
extends RefCounted

## The nearest base within this distance of the camera (m, to its runways' middle) is drawn.
const RANGE := 15000.0

static var _bases := []
static var _loaded := false
static var _loaded_moved := false
static var _current := -1
static var _origin := Vector2(INF, INF)
static var _on := false


## The bases (airbases.json's list; [] when it was not converted).
## World scale Real: each base at its new site (IafBases.base: the runways moved at the real width, `mask_affine`, `centre`).
static func bases() -> Array:
	var moved := Settings.sync_bases()
	if not _loaded or moved != _loaded_moved:
		_loaded = true
		_loaded_moved = moved
		var j: Dictionary = Settings.load_json(Settings.assets_dir().path_join("converted/terrain/airbases.json"))
		_bases = j.get("bases", [])
		if _bases.is_empty():
			push_warning("airbases.json missing: run tools/setup-cli.sh (Airbases = Detailed draws nothing)")
		if moved:
			for i in _bases.size():
				var m: Dictionary = IafBases.base(String(_bases[i].name), _bases[i])
				if not m.is_empty():
					_bases[i] = m
	return _bases


## A base's middle (engine metres): its runways' middle, else its lineup point.
static func centre(b: Dictionary) -> Vector2:
	if b.has("centre"):
		return b.centre
	var rw: Array = b.get("runways", [])
	if rw.is_empty():
		return Vector2(b.lineup[0], b.lineup[1])
	var c := Vector2.ZERO
	for r in rw:
		c += (Vector2(r.ends[0][0], r.ends[0][1]) + Vector2(r.ends[1][0], r.ends[1][1])) * 0.5
	return c / rw.size()


## Applies Settings.airbases (a flight's start, or the Graphics page during a flight).
## World scale Real: always on (a moved base has no painted runways at its new site; docs/world-scale.md §3.3).
static func apply() -> void:
	_on = Settings.airbases == "detailed" or Settings.sync_bases()
	RenderingServer.global_shader_parameter_set("terrain_airbases", 1.0 if _on else 0.0)
	_current = -1
	if not _on:
		RenderingServer.global_shader_parameter_set("airbase_info", Vector4.ZERO)


## Per frame with the camera's position: the nearest base's surface to the shader.
static func update_view(cam: Vector3, terrain: Node) -> void:
	if not _on or terrain == null:
		return
	var o: Vector2 = terrain.world_origin
	var here := o + Vector2(cam.x, -cam.z)
	var best := -1
	var best_d := RANGE
	for i in bases().size():
		var d := centre(_bases[i]).distance_to(here)
		if d < best_d:
			best_d = d
			best = i
	if best == _current and o == _origin:
		return
	_current = best
	_origin = o
	if best < 0:
		RenderingServer.global_shader_parameter_set("airbase_info", Vector4.ZERO)
		return
	_select(_bases[best], o)


## The base's mask and data textures (Godot X east, Z south, relative to the flight's world origin).
static func _select(b: Dictionary, o: Vector2) -> void:
	var m: Dictionary = b.mask
	var img := Image.load_from_file(Settings.assets_dir().path_join("converted/terrain").path_join(m.file))
	if img == null or img.is_empty():
		RenderingServer.global_shader_parameter_set("airbase_info", Vector4.ZERO)
		return
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	RenderingServer.global_shader_parameter_set("airbase_mask", ImageTexture.create_from_image(img))
	var w_m: float = float(m.w) * float(m.px_m)
	var h_m: float = float(m.h) * float(m.px_m)
	# The mask's uv = M · (x, z) + offset (Godot x, z from the world origin): the game point G of a scene point is
	# (X, Y) itself, or on a moved base the inverse move (mask_affine); u = (G.x − origin.x) / w, v = (origin.y − G.y) / h.
	var a := PackedFloat64Array([1, 0, 0, 0, 1, 0])
	if b.has("mask_affine"):
		a = b.mask_affine
	var gx0 := a[0] * o.x + a[1] * o.y + a[2]
	var gy0 := a[3] * o.x + a[4] * o.y + a[5]
	RenderingServer.global_shader_parameter_set("airbase_mask_xf",
			Vector4(a[0] / w_m, -a[3] / h_m, -a[1] / w_m, a[4] / h_m))
	RenderingServer.global_shader_parameter_set("airbase_mask_rect",
			Vector4((gx0 - float(m.origin[0])) / w_m, (float(m.origin[1]) - gy0) / h_m, 0.0, 0.0))
	var texels := []
	for r in b.runways:
		var e0 := _godot(r.ends[0], o)
		var e1 := _godot(r.ends[1], o)
		var d := (e1 - e0).normalized()
		var c := (e0 + e1) * 0.5
		texels.append(Color(c.x, c.y, d.x, d.y))
		texels.append(Color(e0.distance_to(e1) * 0.5, float(r.width) * 0.5, float(r.numbers[0]), float(r.numbers[1])))
		var t: Array = r.get("thresholds", [0, 0])
		texels.append(Color(float(t[0]), float(t[1]), 0.0, 0.0))
	var data := Image.create(maxi(texels.size(), 1), 1, false, Image.FORMAT_RGBAF)
	for i in texels.size():
		data.set_pixel(i, 0, texels[i])
	RenderingServer.global_shader_parameter_set("airbase_data", ImageTexture.create_from_image(data))
	RenderingServer.global_shader_parameter_set("airbase_info", Vector4(b.runways.size(), 0, 0, 0))


## Engine metres [X, Y] → Godot (x, z) relative to the world origin.
static func _godot(p: Array, o: Vector2) -> Vector2:
	return Vector2(float(p[0]) - o.x, -(float(p[1]) - o.y))
