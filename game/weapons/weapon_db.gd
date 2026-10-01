# The weapon database (docs/weapons.md §1): the bdb Weapons table of the mission's object database
# (CDMEWeaponsItem, read by FUN_004c37c2) joined with the motion parameters of
# resource/weaponsmotion/weapons.ibx ([WEAPONnnn] sections by `type` = generation·1000 + sub type,
# [DEBUGDATA]). Weapon data "real" (Extras) overlays public real-world numbers (real_weapons.gd,
# docs/real-weapons.md) on the same records; the original stays the default.
extends RefCounted

const IBX := "install/resource/weaponsmotion/weapons.ibx"

## Sub types (bdb Weapons 0x780, weapons.ibx header).
const GUN := 565
const HEAT := 570
const LIMITED_HEAT := 580

## bdb id -> weapon record (see _record).
var weapons := {}
## weapons.ibx: type code (e.g. 3570) -> {field: float}; "DEBUGDATA" -> {_debugParamNNN: float}.
var motion := {}
var debug := {}
var real := false


## Loads the weapons of `bdb` (a converted .bdb JSON) and weapons.ibx; `real` = Weapon data: Real.
static func create(bdb: Dictionary, real_data := false) -> RefCounted:
	var db = load("res://weapons/weapon_db.gd").new()
	db.real = real_data
	db._load_ibx(Settings.assets_dir().path_join(IBX))
	var models: Dictionary = Settings.load_json(Settings.assets_dir().path_join("converted/objects/objects.json"))
	var paths: Dictionary = models.get(String(bdb.get("_file", "default6_1.bdb")).to_lower(), models.get("default6_1.bdb", {}))
	# Present record 0x65e: the model's uniform scale (as for every mission model, terrain_view.gd).
	var scales := {}
	for pr in bdb.get("present", {}).get("items", []):
		scales[int(pr.get("0x1e", -1))] = float(pr.get("0x65e", 10.0))
	for w in bdb.get("weapons", {}).get("items", []):
		var r := _record(w, paths)
		r["scale"] = float(scales.get(r.model, 1.0))
		db.weapons[r.id] = r
	if real_data:
		preload("res://weapons/real_weapons.gd").apply(db)
	return db


static func _record(w: Dictionary, paths: Dictionary) -> Dictionary:
	var model := int(w.get("0x730", 0))
	return {
		"id": int(w.get("0x1e", -1)),
		"name": String(w.get("0x708", "")).strip_edges(),
		"kind": String(w.get("0x712", "")).strip_edges(),
		"type": int(w.get("0x780", 0)),
		"generation": int(float(w.get("0x762", 0))),
		"power": float(w.get("0x744", 0)),
		"radius": float(w.get("0x74e", 0)),
		"weight_lb": float(w.get("0x758", 0)),
		"drag": float(w.get("0x73a", 0)),
		"model": model,
		"model_path": String(paths.get(str(model), "")),
	}


func _load_ibx(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var section := ""
	var cur := {}
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var l := raw.strip_edges()
		var c := l.find(";")
		if c >= 0:
			l = l.substr(0, c).strip_edges()
		if l == "":
			continue
		if l.begins_with("[") and l.ends_with("]"):
			section = l.substr(1, l.length() - 2)
			cur = {}
			if section == "DEBUGDATA":
				debug = cur
			continue
		var eq := l.find("=")
		if eq < 0:
			continue
		var key := l.substr(0, eq).strip_edges()
		var val := l.substr(eq + 1).strip_edges().trim_suffix("f")
		if key == "type":
			motion[int(val)] = cur
		cur[key] = float(val)


## The weapons.ibx section of sub type `type` and generation `gen` (type code gen·1000 + type), else
## the default section of the sub type (generation 0); {} when neither exists.
func motion_for(type: int, gen: int) -> Dictionary:
	return motion.get(gen * 1000 + type, motion.get(type, {}))


func debug_param(i: int, default := 0.0) -> float:
	return float(debug.get("_debugParam%03d" % i, default))


func by_id(id: int) -> Dictionary:
	return weapons.get(id, {})
