# The Arming screen's data (docs/front-end.md §15): the original's CMissionWeapons (object 0x83d338).
# The weapon list of the mission's object database with a menu tab per type (FUN_004ef290), the
# per-station counts the selected flight's leader may carry (FUN_004ef8a0, from its bdb object's
# CDMEWeaponLoadItem list), and the three loadout tables per flight × 9 stations {weapon id, count}:
# the mission defaults (0x83d340), the current one edited on the screen (0x83d658) and the saved one
# (0x83d970) (filled by FUN_004efef0 -> FUN_004efd50). Scene independent.
extends RefCounted

const WeaponDb := preload("res://weapons/weapon_db.gd")
const Stores := preload("res://weapons/stores.gd")
const MissionRuntime := preload("res://mission/mission_runtime.gd")

## Menu tab by bdb Weapons type (FUN_004ef290, record +8): 0 AA, 1 AG, 2 Misc; other types (SAMs
## 620 / 630, 0) are not in the list.
const TABS := {540: 0, 550: 0, 570: 0, 580: 0, 600: 0, 610: 0,
	500: 1, 510: 1, 560: 1, 590: 1, 635: 1, 640: 1, 650: 1, 565: 2, 660: 2}
## Jet front views bmp/arm/jets/<name>.bmp / .trx by the leader's type code (FUN_00507750).
const JET_ART := {100: "f-16", 110: "f-15", 120: "f4e", 130: "kfir", 140: "lavi2", 160: "mig23",
	180: "mig29", 190: "mirage", 200: "phantom"}
const JET_DIR := "install/resource/menu/bmp/arm/jets"
## Flight names 1..6 (FUN_005bd3c0; flight table +0x328).
const FLIGHT_NAMES := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
## Wing balance margin: 0.05 × the current load (0x6084b4).
const BALANCE := 0.05
## txt/msgs.trx lines of the checks (FUN_00507480).
const MSG_OVERWEIGHT := 0x32
const MSG_LEFT_HEAVY := 0x33
const MSG_RIGHT_HEAVY := 0x34

## The weapon list in bdb order: {id, type, tab, name, icon (arm/weapons art stem), weight (lb),
## max: [9] allowed count per station for the current flight (+0x164)}.
var weapons: Array = []
var _by_id := {}
## Flights 1..6 of the main mission file: n -> {entity, object, type} of the leader (member 0 when
## placed, else member 1).
var flights := {}
## n -> [[id, count] × 9].
var defaults := {}
var current := {}
var saved := {}
## The flight whose allowed counts are loaded (DAT_0083b8a4 when FUN_004ef8a0 last ran).
var flight := 0


## The tables of mission `mission_id` (menu id) right after it loads. `real` = Weapon data: Real
## (the weights shown are the ones the flight uses).
static func create(mission_id: int, real := false) -> RefCounted:
	var files := MissionRuntime.mission_files(mission_id)
	var main: Dictionary = files[0].data if not files.is_empty() else {}
	return from_mission(main, MissionRuntime.load_bdb(main) if not main.is_empty() else {}, real)


static func from_mission(mission: Dictionary, bdb: Dictionary, real := false) -> RefCounted:
	var mw = load("res://weapons/mission_weapons.gd").new()
	var db = WeaponDb.create(bdb, real)
	var raw: Array = bdb.get("weapons", {}).get("items", [])
	for w in raw:
		var id := int(w.get("0x1e", -1))
		var r: Dictionary = db.by_id(id)
		if r.is_empty() or not TABS.has(int(r.type)):
			continue
		var rec := {"id": id, "type": int(r.type), "tab": TABS[int(r.type)], "name": String(r.name),
			"icon": String(r.model_path).get_base_dir().get_file(), "weight": float(r.weight_lb),
			"max": [0, 0, 0, 0, 0, 0, 0, 0, 0]}
		mw._by_id[id] = mw.weapons.size()
		mw.weapons.append(rec)
	mw._load_flights(mission, bdb)
	for n in mw.flights:
		mw.defaults[n] = mw._leader_load(n)
	mw.current = _copy(mw.defaults)
	mw.saved = _copy(mw.defaults)
	return mw


static func _copy(t: Dictionary) -> Dictionary:
	return t.duplicate(true)


## Flights (docs/front-end.md §8.1): the formation number 0x3f2 (−1 = 8), its two member slots; a
## flight exists when a member is placed; the leader is member 0 if placed, else member 1. Only the
## named flights 1..6 have their own table slot.
func _load_flights(mission: Dictionary, bdb: Dictionary) -> void:
	var by_id := {}
	for e in mission.get("entities", {}).get("items", []):
		if e is Dictionary:
			by_id[int(e.get("0x1e", -1))] = e
	var objects := MissionRuntime.bdb_objects(bdb)
	for f in mission.get("formations", {}).get("items", []):
		var n := int(f.get("0x3f2", 0))
		if n < 1 or n > 6 or flights.has(n):
			continue
		for mem in f.get("members", []).slice(0, 2):
			var e: Dictionary = by_id.get(int(mem.get("0x41a", -1)), {})
			if not e.is_empty() and not (float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0):
				var obj: Dictionary = objects.get(int(e.get("0x2c6", -1)), {})
				flights[n] = {"entity": e, "object": obj, "type": int(obj.get("0x5b4", -1))}
				break


## FUN_004efd50: station i of the table = the leader's store at mission start (weapon name and
## count), matched to the list by name; not found = empty.
func _leader_load(n: int) -> Array:
	var f: Dictionary = flights[n]
	var spawn := Stores.loadout(f.entity, f.object)
	var out := []
	for i in 9:
		var id := int(spawn[i][0])
		var count := int(spawn[i][1])
		var slot := [0, 0]
		if count != 0 and _by_id.has(id):
			var name: String = weapons[_by_id[id]].name
			for w in weapons:
				if w.name == name:
					slot = [int(w.id), count]
					break
		out.append(slot)
	return out


func weapon(id: int) -> Dictionary:
	return weapons[_by_id[id]] if _by_id.has(id) else {}


## FUN_004ef8a0(n): every weapon's allowed counts from the leader's CDMEWeaponLoadItems: for each
## item, station i allows max(previous, item count) when its flag i is set.
func reset(n: int) -> void:
	flight = n
	for w in weapons:
		w.max = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	if not flights.has(n):
		return
	for item in flights[n].object.get("loads", {}).get("items", []):
		var w := weapon(int(item.get("0x910", -1)))
		if w.is_empty():
			continue
		var count := int(item.get("0x906", 0))
		var flags := _flags(String(item.get("raw", "")))
		for i in 9:
			w.max[i] = maxi(w.max[i], count if flags[i] != 0 else 0)


## The 9 int32 station flags of a CDMEWeaponLoadItem (raw little-endian hex).
static func _flags(raw: String) -> Array:
	var out := []
	var bytes := raw.hex_decode()
	for i in 9:
		out.append(bytes.decode_s32(i * 4) if bytes.size() >= i * 4 + 4 else 0)
	return out


## FUN_004ef140: listed only when some station allows it.
static func allowed(w: Dictionary) -> bool:
	for m in w.max:
		if m > 0:
			return true
	return false


## The list of tab `tab` (FUN_00519370): bdb order, allowed weapons only.
func tab_list(tab: int) -> Array:
	return weapons.filter(func(w): return w.tab == tab and allowed(w))


func load_of(n: int) -> Array:
	return current.get(n, [])


## FUN_00507bd0: base weight + Σ count × weight (lb).
func current_weight(n: int, base: float) -> float:
	var total := base
	for s in load_of(n):
		var w := weapon(int(s[0]))
		if not w.is_empty():
			total += float(int(s[1])) * float(w.weight)
	return total


## FUN_00507480: 0 when the load may fly, else the message: current > max take-off weight
## (overweight); stations 1–4 (the right wing, drawn on the left) heavier than 6–9 by more than 5 %
## of the current load (right wing heavy), or the other way (left wing heavy).
func check(n: int, base: float, max_tow: float) -> int:
	var cur := current_weight(n, base)
	if max_tow < cur:
		return MSG_OVERWEIGHT
	var right := _side(n, [0, 1, 2, 3])
	var left := _side(n, [5, 6, 7, 8])
	if left + cur * BALANCE < right:
		return MSG_RIGHT_HEAVY
	if right + cur * BALANCE < left:
		return MSG_LEFT_HEAVY
	return 0


func _side(n: int, stations: Array) -> float:
	var t := 0.0
	var load := load_of(n)
	for i in stations:
		if i < load.size():
			var w := weapon(int(load[i][0]))
			if not w.is_empty():
				t += float(int(load[i][1])) * float(w.weight)
	return t


## FUN_00507aa0 for one station: a weapon goes on with the station's maximum count, only where it is
## allowed (false otherwise); `w` = {} clears the station.
func put(n: int, station: int, w: Dictionary) -> bool:
	if not current.has(n):
		return false
	if w.is_empty():
		current[n][station] = [0, 0]
		return true
	if int(w.max[station]) == 0:
		return false
	current[n][station] = [int(w.id), int(w.max[station])]
	return true


## Right-click on a loaded station (FUN_00506fd0): one store less; at 0 the station is empty.
func decrement(n: int, station: int) -> void:
	if current.has(n) and int(current[n][station][1]) != 0:
		current[n][station][1] = int(current[n][station][1]) - 1


## FUN_005075c0: the current tables differ from the saved ones (any flight).
func changed() -> bool:
	return current != saved


## "Use weapon load?" Yes / No (FUN_00507660).
func commit() -> void:
	saved = _copy(current)


func revert() -> void:
	current = _copy(saved)


## DEFAULT (FUN_00506790): the defaults for every flight (the saved table is not touched).
func use_defaults() -> void:
	current = _copy(defaults)


## The jet's front view (FUN_00507750): art stem, base weight, max take-off weight (lb) and the
## station boxes (index 0..8 -> content-local top-left of the 51×32 box). {} for an unknown type.
static func jet(type: int) -> Dictionary:
	var art: String = JET_ART.get(type, "")
	if art == "":
		return {}
	var out := {"art": art, "base": 0.0, "max": 0.0, "stations": {}}
	var path := Settings.assets_dir().path_join(JET_DIR).path_join(art + ".trx")
	if not FileAccess.file_exists(path):
		return out
	var tok := _tokens(path)
	if tok.size() < 3:
		return out
	out.base = float(tok[0])
	out.max = float(tok[1])
	var count := int(tok[2])
	for k in count:
		var at := 3 + k * 3
		if at + 2 >= tok.size():
			break
		out.stations[int(tok[at]) - 1] = Vector2(float(tok[at + 1]), float(tok[at + 2]))
	return out


static func _tokens(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in FileAccess.get_file_as_string(path).replace("\t", " ").replace("\r", " ").replace("\n", " ").split(" ", false):
		out.append(t)
	return out

