# The mission editor's calls into the Rust mission editing (IafMissionEdit, crates/iaf-tools mission_edit.rs), with
# the missions as dictionaries (the class takes and returns JSON strings).
# STAND-IN: until IafMissionEdit is built, a minimal GDScript fallback (the "FALLBACK" section at the end) answers
# instead. Delete the fallback, and the `_rs == null` branches, when the class lands.
extends RefCounted

const MissionRuntime := preload("res://mission/mission_runtime.gd")

var _rs: Object = null


func _init() -> void:
	if ClassDB.class_exists("IafMissionEdit"):
		_rs = ClassDB.instantiate("IafMissionEdit")
		_rs.set_assets(Settings.assets_dir())


static func _js(d: Dictionary) -> String:
	return JSON.stringify(d, "", false, true)


static func _parse(s: String) -> Dictionary:
	var v = JSON.parse_string(s)
	return v if v is Dictionary else {}


## "" when `name` is a good mission name, else the reason.
func valid_name(name: String) -> String:
	return _rs.valid_name(name) if _rs else _fb_valid_name(name)


func stem(name: String) -> String:
	return _rs.stem(name) if _rs else _fb_stem(name)


## `base`, else "<base> 2", "3" … : the first name not in `taken` (compared without case).
func free_name(base: String, taken: PackedStringArray) -> String:
	return _rs.free_name(base, taken) if _rs else _fb_free_name(base, taken)


## {mission, id}: `mission` with a new entity copied from `template`, `fields` set.
func add_entity(mission: Dictionary, template: Dictionary, fields: Dictionary) -> Dictionary:
	if _rs == null:
		return _fb_add_entity(mission, template, fields)
	var r := _parse(_rs.add_entity(_js(mission), _js(template), _js(fields)))
	return {"mission": r.get("mission", mission), "id": int(r.get("id", -1))}


func remove_entity(mission: Dictionary, id: int) -> Dictionary:
	return _parse(_rs.remove_entity(_js(mission), id)) if _rs else _fb_remove_entity(mission, id)


## Units `ids` follow the route `points` (world X east, Y north, Z) at `speed_kmh`, hovering at the end when asked.
func set_route(
	mission: Dictionary, ids: PackedInt64Array, points: PackedVector3Array, speed_kmh: float, hover_end: bool
):
	if _rs == null:
		return mission  # FALLBACK: no routes
	return _parse(_rs.set_route(_js(mission), ids, points, speed_kmh, hover_end))


func clear_route(mission: Dictionary, id: int) -> Dictionary:
	return _parse(_rs.clear_route(_js(mission), id)) if _rs else mission


## Flight `number` (1..4) from `spec` {type (bdb object id), count, slot_x, slot_y, alt, heading, points?}.
func set_flight(mission: Dictionary, number: int, spec: Dictionary) -> Dictionary:
	return _parse(_rs.set_flight(_js(mission), number, _js(spec))) if _rs else _fb_set_flight(mission, number, spec)


func remove_flight(mission: Dictionary, number: int) -> Dictionary:
	return _parse(_rs.remove_flight(_js(mission), number)) if _rs else _fb_remove_flight(mission, number)


## The terrain height (m) at world X / Y, null outside the terrain.
func ground_height(x: float, y: float):
	return _rs.ground_height(x, y) if _rs else _fb_ground_height(x, y)


## The mission's issues: [{id, level "error" | "warning", text}].
func check(mission: Dictionary) -> Array:
	if _rs == null:
		return _fb_check(mission)
	var v = JSON.parse_string(_rs.check(_js(mission)))
	return v if v is Array else []


# --- FALLBACK (stand-in until IafMissionEdit lands; delete this section) -------------------------------------------

var _meta := {}
var _tiles := {}
var _surface := false


func _fb_valid_name(name: String) -> String:
	if RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9 _-]{0,39}$").search(name) == null:
		return "Use 1 to 40 English letters, digits, spaces, _ or -, starting with a letter or digit."
	return ""


func _fb_stem(name: String) -> String:
	return name.strip_edges().replace(" ", "_").to_lower()


func _fb_free_name(base: String, taken: PackedStringArray) -> String:
	base = RegEx.create_from_string("[^A-Za-z0-9 _-]").sub(base, "", true).strip_edges().left(36)
	var low := Array(taken).map(func(t): return String(t).to_lower())
	if not base.to_lower() in low:
		return base
	var k := 2
	while ("%s %d" % [base, k]).to_lower() in low:
		k += 1
	return "%s %d" % [base, k]


func _fb_add_entity(mission: Dictionary, template: Dictionary, fields: Dictionary) -> Dictionary:
	var m := mission.duplicate(true)
	var items: Array = m.entities.items
	var id := 0
	for e in items:
		id = maxi(id, int(e.get("0x1e", 0)))
	id += 1
	var e: Dictionary = template.duplicate(true)
	e.merge(fields, true)
	e["0x1e"] = id
	e["0x14"] = 0
	e["0x320"] = 0
	for k in ["scripts0", "scripts1"]:
		if e.has(k):
			e[k].items = []
	var at := items.size()
	if at > 0 and int(items[-1].get("0x14", 0)) == 1:
		at -= 1
	items.insert(at, e)
	return {"mission": m, "id": id}


func _fb_remove_entity(mission: Dictionary, id: int) -> Dictionary:
	var m := mission.duplicate(true)
	m.entities.items = m.entities.items.filter(func(e): return int(e.get("0x1e", -1)) != id)
	for f in m.formations.items:
		for i in f.get("members", []).size():
			if int(f.members[i].get("0x41a", -1)) == id:
				f.members[i] = {"0x410": "", "0x41a": -1, "0x424": -1}
	return m


func _fb_set_flight(mission: Dictionary, number: int, spec: Dictionary) -> Dictionary:
	var m := mission.duplicate(true)
	for f in m.formations.items:
		if int(f.get("0x3f2", 0)) != number:
			continue
		var lead := int(f.members[0].get("0x41a", -1))
		for e in m.entities.items:
			if int(e.get("0x1e", -1)) == lead:
				e["0x2c6"] = spec.get("type", e["0x2c6"])
				e["0x2e4"] = spec.get("slot_x", e["0x2e4"])
				e["0x2ee"] = spec.get("slot_y", e["0x2ee"])
				e["0x2f8"] = spec.get("alt", e["0x2f8"])
				e["0x302"] = spec.get("heading", e["0x302"])
		if spec.has("points"):
			f.points = spec.points
	return m


func _fb_remove_flight(mission: Dictionary, number: int) -> Dictionary:
	var m := mission
	for f in mission.formations.items:
		if int(f.get("0x3f2", 0)) == number:
			for mem in f.members:
				if int(mem.get("0x41a", -1)) >= 0:
					m = _fb_remove_entity(m, int(mem["0x41a"]))
	m = m.duplicate(true)
	m.formations.items = m.formations.items.filter(func(f): return int(f.get("0x3f2", 0)) != number)
	return m


## terrain.gd height_at on the level-6 height tile, from world X / Y.
func _fb_ground_height(x: float, y: float):
	var dir := Settings.assets_dir().path_join("converted/terrain/theatre")
	if _meta.is_empty():
		_meta = Settings.load_json(dir.path_join("meta.json"))
	if _meta.is_empty():
		return null
	var mpu := float(_meta.units_to_metres)
	var t := Vector2((x - float(_meta.x_shift)) / mpu, (float(_meta.y_shift) - y) / mpu)
	var px := int(_meta.node_pixels)
	var s6 := float(px) * float(1 << int(_meta.height_level))
	var n := Vector2i(floori(t.x / s6), floori(t.y / s6))
	if not _tiles.has(n):
		_tiles[n] = Image.load_from_file(dir.path_join("L%d/h_%d_%d.png" % [int(_meta.height_level), n.x, n.y]))
	var img: Image = _tiles[n]
	if img == null or img.is_empty():
		return null
	var g := (t - Vector2(n) * s6) / (s6 / px)
	var c := Vector2i(clampi(floori(g.x), 0, px - 1), clampi(floori(g.y), 0, px - 1))
	var col := img.get_pixel(mini(c.x, img.get_width() - 1), mini(c.y, img.get_height() - 1))
	var raw := float(roundi(col.r * 255.0) * 256 + roundi(col.g * 255.0))
	return (raw - float(_meta.sea_level_raw)) / float(_meta.height_scale) * mpu


func _fb_check(mission: Dictionary) -> Array:
	if not _surface:
		_surface = IafSurface.load(Settings.assets_dir().path_join("install/terraintype.dat"))
	var objs := MissionRuntime.bdb_objects(MissionRuntime.load_bdb(mission))
	var out := []
	var ids := {}
	for e in mission.entities.items:
		ids[int(e.get("0x1e", -1))] = true
		if int(e.get("0x14", 0)) == 1 or (float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0):
			continue
		var cls := int(objs.get(int(e.get("0x2c6", -1)), {}).get("0x5aa", -1))
		if cls in [2, 3, 0x1c]:
			continue
		var x := float(e["0x2e4"])
		var y := float(e["0x2ee"])
		var issue := ""
		if ground_height(x, y) == null:
			issue = "outside the terrain"
		elif _surface:
			var water := IafSurface.raster_rg8(x - 0.5, y + 0.5, 1.0, 1)[0] > 0
			if water and not cls in [0xf, 0x10]:
				issue = "in the water"
			elif not water and cls in [0xf, 0x10]:
				issue = "a ship on land"
		if issue != "":
			out.append({"id": int(e["0x1e"]), "level": "error", "text": "%s: %s" % [e.get("0x2bc", ""), issue]})
	for f in mission.formations.items:
		for mem in f.get("members", []):
			var id := int(mem.get("0x41a", -1))
			if id >= 0 and not ids.has(id):
				out.append({"id": -1, "level": "error", "text": "%s: member %d is missing" % [f.get("0x3e8", ""), id]})
	return out
