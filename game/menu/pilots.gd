# Pilot records (docs/front-end.md §13): the pilot list (the original's Pilots.dat), each pilot's mission
# history (Pilots\<id>.mis), recording an attempt (§13.7) and the score / rank (§13.8).
# Stored as our own JSON in the user data dir (docs/deviations.md): pilots.json = {selected, pilots: [{name,
# callsign, id, photo}]} and <id>.json = {missions: [{id, attempts: [{result, mult, bonus, kills[37],
# losses[37]}]}]}, newest mission first as in the original's list; a custom photo is <id>.png.
# Tests (IAF_DEFAULT_SETTINGS=1) use a temporary directory instead.
extends RefCounted

## Categories per attempt (nCat, FUN_004f7a40).
const N_CAT := 37
## Points per category (FUN_004f7550).
const POINTS := [1000, 800, 700, 600, 1200, 500, 600, 600, 700, 600, 800,
	400, 400, 2000, 2000, 200, 100, 50, 100, 50, 300, 350,
	800, 400, 400, 400, 800, 100, 100, 200, 500,
	200, 3000, 600, 100, 2000, 2000]
## Type code -> category (FUN_004f6da0; the TSD label table, §8.1).
const TYPE_CATEGORY := {110: 0, 100: 1, 120: 2, 130: 3, 140: 4, 150: 5, 160: 6, 170: 7, 180: 8, 190: 9,
	200: 10, 210: 11, 220: 12, 225: 14, 230: 14, 240: 14, 250: 16, 260: 17, 270: 18, 280: 19, 290: 20,
	300: 21, 310: 22, 320: 23, 330: 24, 340: 26, 350: 27, 360: 28, 370: 29, 380: 30, 390: 30, 400: 31,
	410: 32, 420: 33, 430: 34, 440: 36, 450: 35}
## Fallback by unit class.
const CLASS_CATEGORY := {2: 15, 6: 17, 9: 25, 0xb: 31, 0xc: 31, 0xd: 31, 0x1d: 31, 0x1e: 31}
## Display groups (FUN_004f7120) with their names (FUN_004f78d0) and rows (FUN_004f74f0: 0 air, 1 ground,
## 2 structure).
const GROUPS := [
	["Fighter", 0, [2, 3, 5, 6, 7, 9, 10, 11]], ["Adv Fighter", 0, [0, 1, 4, 8]], ["Bomber", 0, [12]],
	["Support", 0, [13, 14]], ["Helo", 0, [15]], ["Tank", 1, [16]], ["Soft", 1, [17, 19]],
	["Armored", 1, [18]], ["Anti Aircraft", 1, [20, 21, 22, 23, 24, 25, 26, 27, 28]],
	["Naval", 1, [29, 30]], ["Structure", 2, [31, 32, 33, 34, 35, 36]],
]
## Ranks by pilot score (FUN_0051bb90 @51bd3e, §8.1).
const RANKS := [[5000, "Second Lieutenant"], [15000, "Lieutenant"], [30000, "Captain"], [45000, "Major"],
	[75000, "Lt. Colonel"], [100000, "Colonel"]]
## Multiplayer missions: not saved, not counted in the totals (§13.7).
const MP_IDS := [0x21d, 0x29a, 0x213]
## The first mission of each war (FUN_004f17b0).
const FIRST_OF_WAR := [111, 121, 131, 211, 221, 231, 311, 321, 331, 401, 511]

static var _temp: DirAccess


## Where the records live: user://pilots, or a temporary directory for tests.
static func dir() -> String:
	if OS.get_environment("IAF_DEFAULT_SETTINGS") == "1":
		if _temp == null:
			_temp = DirAccess.create_temp("iaf_pilots", false)
		return _temp.get_current_dir()
	DirAccess.make_dir_recursive_absolute("user://pilots")
	return "user://pilots"


# --- the pilot list (Pilots.dat) ----------------------------------------------------------------

var pilots: Array = []
var selected := 0


## Reads the list; a missing file gives one default pilot "Gal" / "default", id 14, photo 0 (FUN_0051c750).
func load_list() -> void:
	var d = _read(dir().path_join("pilots.json"))
	pilots = []
	for p in d.get("pilots", []):
		pilots.append({"name": String(p.name).left(10), "callsign": String(p.callsign).left(12),
			"id": int(p.id), "photo": int(p.photo)})
	if pilots.is_empty():
		pilots.append(blank(14))
		pilots[0].name = "Gal"
		pilots[0].callsign = "default"
	selected = clampi(int(d.get("selected", 0)), 0, pilots.size() - 1)


## Rewrites the list (FUN_0051ce30): a selected pilot with both name and callsign empty is deleted first.
func save_list() -> void:
	if pilots.size() > 1 and _empty(pilots[selected]):
		remove(selected)
	_write(dir().path_join("pilots.json"), {"selected": selected, "pilots": pilots})


## A blank record (FUN_0050b2c0).
static func blank(id: int) -> Dictionary:
	return {"name": "", "callsign": "", "id": id, "photo": 0}


func current() -> Dictionary:
	return pilots[selected] if selected >= 0 and selected < pilots.size() else {}


## New_Pilot (FUN_0051d580): a blank record with the lowest unused id >= 14 (FUN_0051d2c0), appended and
## selected.
func add() -> Dictionary:
	var id := 14
	var used := pilots.map(func(p): return p.id)
	while id in used:
		id += 1
	var p := blank(id)
	pilots.append(p)
	selected = pilots.size() - 1
	return p


## Remove_Pilot (FUN_0051d690): its files and record; the selection stays, or moves to the new last pilot.
func remove(i: int) -> void:
	var id: int = pilots[i].id
	for ext in ["json", "png"]:
		var f := dir().path_join("%d.%s" % [id, ext])
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	pilots.remove_at(i)
	selected = mini(selected, pilots.size() - 1)


static func _empty(p: Dictionary) -> bool:
	return p.name == "" and p.callsign == ""


## A custom photo (photo index >= 14 = the pilot's own picture, <id>.png); "" when there is none.
static func photo_path(id: int) -> String:
	var f := dir().path_join("%d.png" % id)
	return f if FileAccess.file_exists(f) else ""


# --- mission history (Pilots\<id>.mis) ------------------------------------------------------------

static func history(id: int) -> Array:
	return _read(dir().path_join("%d.json" % id)).get("missions", [])


static func save_history(id: int, missions: Array) -> void:
	_write(dir().path_join("%d.json" % id), {"missions": missions})


static func attempts(missions: Array, id: int) -> Array:
	for m in missions:
		if int(m.id) == id:
			return m.attempts
	return []


## FUN_004f6d40: attempts with result > 0.
static func passes(missions: Array, id: int) -> int:
	return attempts(missions, id).filter(func(a): return int(a.result) > 0).size()


## FUN_004f7a10: attempts with result == 0.
static func failures(missions: Array, id: int) -> int:
	return attempts(missions, id).filter(func(a): return int(a.result) == 0).size()


## FUN_004f6da0: the category of a destroyed unit (37 = not counted).
static func category(type_code: int, klass: int) -> int:
	return TYPE_CATEGORY.get(type_code, CLASS_CATEGORY.get(klass, N_CAT))


## FUN_004f68b0, called by the debrief: a new attempt of mission `id` for pilot `pilot_id` from the flight's
## results {result, bonus, kills: [[type, class]], losses: [...]} and the score multiplier. The result is -1
## ("prerequisite not met", not counted) for a Future mission other than the first of its war whose previous
## mission has no pass. Multiplayer missions are not saved.
static func record(pilot_id: int, id: int, results: Dictionary, mult: float) -> void:
	var missions := history(pilot_id)
	var list := attempts(missions, id)
	if list.is_empty() and not missions.any(func(m): return int(m.id) == id):
		missions.push_front({"id": id, "attempts": list})
	var result := int(results.get("result", 0))
	if id >= 200 and id <= 299 and not id in FIRST_OF_WAR and passes(missions, id - 1) == 0:
		result = -1
	var a := {"result": result, "mult": mult, "bonus": int(results.get("bonus", 0)), "kills": [], "losses": []}
	for side in ["kills", "losses"]:
		var counts: Array = []
		counts.resize(N_CAT)
		counts.fill(0)
		for u in results.get(side, []):
			var c := category(int(u[0]), int(u[1]))
			if c < N_CAT:
				counts[c] += 1
		a[side] = counts
	list.append(a)
	if not (id in MP_IDS or (id >= 0x1ff and id <= 0x207)):
		save_history(pilot_id, missions)


## FUN_004f7b30 for one attempt: kill and loss points per row (air / ground / structure) and the score.
static func attempt_score(a: Dictionary) -> Dictionary:
	var mult := float(a.mult)
	var k := [0, 0, 0]
	var l := [0, 0, 0]
	var kills: Array = a.kills
	var losses: Array = a.losses
	for c in mini(kills.size(), N_CAT):
		var row := 0 if c <= 15 else (1 if c <= 30 else 2)
		k[row] = int(k[row] + float(kills[c]) * POINTS[c] * mult)
		l[row] += int(losses[c]) * POINTS[c] * (1 if mult > 0.0 else 0)
	var bonus := int(a.bonus)
	var score := int(float(k[0] + k[1] + k[2] - l[0] - l[1] - l[2]) + bonus * (mult if bonus > 0 else 1.0))
	return {"k": k, "l": l, "score": score}


## FUN_004f66d0: pilot totals from each mission's best attempt (highest score, the later one on a tie),
## multiplayer missions left out: score, kill / loss points per row and {count} per display group; plus the
## number of missions with a pass (FUN_004f79e0, every mission).
static func totals(missions: Array) -> Dictionary:
	var t := {"score": 0, "completed": 0, "k": [0, 0, 0], "l": [0, 0, 0], "kill_groups": [], "loss_groups": []}
	for g in GROUPS:
		t.kill_groups.append(0)
		t.loss_groups.append(0)
	for m in missions:
		var id := int(m.id)
		if passes(missions, id) > 0:
			t.completed += 1
		if m.attempts.is_empty() or id in MP_IDS or (id >= 0x1ff and id <= 0x207):
			continue
		var best := 0
		var best_s := {}
		for i in m.attempts.size():
			var s := attempt_score(m.attempts[i])
			if best_s.is_empty() or best_s.score <= s.score:
				best = i
				best_s = s
		var a: Dictionary = m.attempts[best]
		t.score += best_s.score
		for r in 3:
			t.k[r] += best_s.k[r]
			t.l[r] += best_s.l[r]
		for gi in GROUPS.size():
			for c in GROUPS[gi][2]:
				t.kill_groups[gi] += int(a.kills[c]) if c < a.kills.size() else 0
				t.loss_groups[gi] += int(a.losses[c]) if c < a.losses.size() else 0
	return t


static func rank(score: int) -> String:
	for r in RANKS:
		if score < r[0]:
			return r[1]
	return "General"


## The "make sim" / "not war" cheat (FUN_004f1610): every mission open.
static func cheat(name: String, callsign: String) -> bool:
	return name == "make sim" and callsign == "not war"


## MissBonus from the score file (iaf.ibx [Scenario] ScoreFile = Resource\Missions\Scores.ibx,
## FUN_0059add0): the mission's bonus, 0 when not listed.
static func mission_bonus(id: int) -> int:
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/install/resource/missions/scores.ibx").simplify_path()
	var cfg := FileAccess.get_file_as_string(path)
	var in_section := false
	for line in cfg.split("\n"):
		line = line.strip_edges()
		if line.begins_with("["):
			in_section = line.to_lower() == "[missbonus]"
		elif in_section and line.begins_with("%d=" % id):
			return line.get_slice("=", 1).to_int()
	return 0


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, " "))
