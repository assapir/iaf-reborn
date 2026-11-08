# Modern IAF's part of the flight scene (Settings.flight_addon, a child of terrain_view.gd): the radio menu and the
# training run (iaf-2026/docs/training.md §7–§9).
# - The text over the flight in the sim's own look (flight_ui.gd): the mission card (H), the radio lines, the panel.
# - The radio menu: the "Call the tower" key (Ctrl+T, command 107) opens a numbered list; 1–4 pick a request (start-up,
#   taxi, take-off, contact the tower for landing), any other key closes it. The tower answers by TTS (radio.gd
#   request), each call a `radio` event in the recording.
# - A training mission (the compiled mission's `sim.training`): at its end the recording is scored by IafTraining
#   (crates/iaf-tools training.rs), the debrief record written to user://debriefs/ and the attempt to the pilot log.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const FlightUi := preload("flight_ui.gd")
## The menu's lines: [request id, English, Hebrew] (radio.gd request; "landing": its Ctrl+T contact_tower).
const ITEMS := [
	["startup", "Request start-up", "בקשת התנעה"],
	["taxi", "Request taxi", "בקשת הסעה"],
	["takeoff", "Request take-off", "בקשת המראה"],
	["landing", "Contact tower (landing)", "קריאה למגדל (נחיתה)"],
]
const TITLE := {"en": "Radio: %s tower", "he": "קשר: מגדל %s"}
## The pilot's call, printed in the game's language (no pilot voice for it yet: sound.md §7).
const CALLS := {
	"startup": ["request start-up", "בקשת התנעה"],
	"taxi": ["request taxi", "בקשת הסעה"],
	"takeoff": ["ready for take-off", "בקשת המראה"],
}
## The call's address: "Ramon tower" / "מגדל רמון".
const TOWER := {"en": "%s tower", "he": "מגדל %s"}
## The bases' names by their iaf.ibx section (the own iaf.ibx, sim_bases::BASES).
const BASE_NAMES := {
	"Ramon": ["Ramon", "רמון"],
	"David": ["Ramat David", "רמת דוד"],
	"Hatzerim": ["Hatzerim", "חצרים"],
	"Nevatim": ["Nevatim", "נבטים"],
}
## A take-off is scored once airborne with the gear up (every SCORE_EVERY s until it passes), a start-up once the
## engine idles with the avionics up; either at a crash or this long past its time budget.
# ponytail: each score re-reads the whole recording (O(length)); a scorer fed sample by sample if it shows.
const SCORE_EVERY := 3.0
const PAST_BUDGET := 5.0

var host: Node
var open := false
## The text over the flight: the mission card, the band of radio lines, the panel, the key hint (flight_ui.gd).
var ui: Control
var _sim := {}
## The training mission: its readable file's name (res://data/missions/<name>.json) and rules; {} for a flight without.
var mission_name := ""
var rules := {}
## The debrief record once scored ({} before), and where it was written.
var result := {}
var debrief_file := ""
## Tests: where the debrief, the pilot log and (isolated) the recording go; "" = user:// (or a temporary folder in
## isolated runs).
var out_dir := ""
var _next_score := 0.0
var _ready_at := INF
const RECORDED_S := 0.25


static func create(h: Node) -> Node:
	var n = new()
	n.name = "SimFlight"
	n.host = h
	return n


func _ready() -> void:
	host.radio.menu = true
	var files: Array = MissionRuntime.mission_files(host.mission_id)
	if not files.is_empty():
		var sim: Dictionary = files[0].data.get("sim", {})
		_sim = sim
		var rwy = sim.get("runway")
		host.radio.runway = rwy if rwy is String else ""
		# The runway is the mission's base's (its readable file's start.base, an English base name).
		var readable := Settings.load_json("res://data/missions/%s.json" % files[0].name)
		var base_en := String(readable.get("start", {}).get("base", ""))
		for sec in BASE_NAMES:
			if BASE_NAMES[sec][0] == base_en:
				host.radio.runway_base = sec
		rules = sim.get("training", {})
		mission_name = String(files[0].name) if not rules.is_empty() else ""
	if not rules.is_empty() and not Settings.blackbox:
		push_warning("training: the recorder is off (Extras), so this flight cannot be scored")
	elif not rules.is_empty() and host.blackbox_path == "" and Settings.isolated():
		# Tests record beside the debrief (the player's flights folder untouched).
		host.blackbox_path = _dir().path_join("flight-%s-%s.jsonl" % [Settings.file_stamp(), mission_name])
	var layer := CanvasLayer.new()
	layer.layer = 16
	add_child(layer)
	ui = FlightUi.new(host)
	layer.add_child(ui)
	# The card opens at the start; scripted runs (IAF_DEFAULT_SETTINGS) fly on without it.
	if not Settings.isolated():
		ui.open_card.call_deferred(_sim)


func _dir() -> String:
	var d := out_dir
	if d == "":
		d = Settings.debriefs_dir()
	DirAccess.make_dir_recursive_absolute(d)
	return d


# --- the radio menu ---------------------------------------------------------------------------------------------------


func _he() -> bool:
	return Settings.language == "he"


## The menu's text in the game's language.
func menu_text() -> String:
	var lang := 1 if not _he() else 2
	var base := _tower_name()
	var lines := [(TITLE.he if _he() else TITLE.en) % base]
	for i in ITEMS.size():
		lines.append("%d. %s" % [i + 1, ITEMS[i][lang]])
	return "\n".join(lines)


func _tower_name() -> String:
	var r: Node = host.radio
	var i: int = r.base_at(r._pos())
	if i < 0 or i >= r.tower_count:
		return "—"
	var names: Array = BASE_NAMES.get(String(r.bases[i].name), [r.bases[i].name, r.bases[i].name])
	return names[1 if _he() else 0]


func set_open(on: bool) -> void:
	open = on
	ui.show_panel(menu_text() if on else "")


## A radio line or a message (terrain_view.gd _on_subtitle): the band of the sim's own text, not the original's
## console.
func subtitle(text: String) -> void:
	if ui != null:
		ui.subtitle(text)


## A key press (terrain_view.gd before its key table): the "Call the tower" key opens / closes the menu; while it is
## open 1–4 pick and any other key closes it. True when taken.
func key(event: InputEventKey) -> bool:
	if event.echo or event.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return open and event.echo  # a lone modifier is part of the next key (Ctrl+T closes the menu)
	var rec: int = host.keys.find_key(host.keys.key_of_event(event), Settings.key_bindings)
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 201:
		ui.open_card(_sim)  # the Mission card key (keys.json record 118); the card closes itself
		return true
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 107:
		set_open(not open)
		return true
	if not open:
		return false
	var k := event.keycode
	var i := -1
	if k >= KEY_1 and k <= KEY_9:
		i = k - KEY_1
	elif k >= KEY_KP_1 and k <= KEY_KP_9:
		i = k - KEY_KP_1
	set_open(false)
	if i >= 0 and i < ITEMS.size():
		pick(ITEMS[i][0])
	return true


## One menu pick: the pilot's call printed, the tower's answer (radio.gd request), a `radio` event recorded.
func pick(id: String) -> String:
	var r: Node = host.radio
	if id == "landing":
		r.contact_tower()
		return ""
	var cs: String = r.formation_name(r._player_ent())
	var tower: String = (TOWER.he if _he() else TOWER.en) % _tower_name()
	host._on_subtitle("%s, %s, %s" % [tower, cs, CALLS[id][1 if _he() else 0]])
	var p: Dictionary = r.request(id)
	host._log_event(host._log_st, {"event": "radio", "call": id, "answer": p.template, "text": p.text})
	return String(p.template)


# --- the training run -------------------------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	if rules.is_empty() or not result.is_empty() or host.flight == null or host.get("_log") == null:
		return
	var t: float = host._log_t
	if t < _next_score:
		return
	var st: Dictionary = host._log_st  # this frame's flight state (terrain_view.gd _record)
	if st.is_empty():
		return
	var budget := float(rules.get("time_budget_s", 900.0))
	var ready := false
	if String(rules.get("kind", "")) == "startup":
		ready = bool(st.get("engine_on", false)) and bool(st.get("avionics", false))
	else:
		ready = not bool(st.on_ground) and not host.gear_down
	if not (ready or host.crashed or t > budget + PAST_BUDGET):
		_ready_at = INF
		return
	# Scored once the recorder has written a sample of it (10 a second).
	_ready_at = minf(_ready_at, t)
	if t - _ready_at < RECORDED_S:
		return
	_next_score = t + SCORE_EVERY
	var d := score()
	if d.has("error"):
		push_warning("training: %s" % d.error)
		return
	# A take-off not yet on its heading may still pass: scored again next second, until its budget.
	if bool(d.get("pass", false)) or host.crashed or t > budget + PAST_BUDGET or String(rules.kind) == "startup":
		_finish(d)


## The recording so far against the mission's rules (IafTraining, the readable mission and the airbases of
## iaf-2026/data).
func score() -> Dictionary:
	host._log.flush()
	var flight: String = ProjectSettings.globalize_path(host._log.get_path_absolute())
	var m := ProjectSettings.globalize_path("res://data/missions/%s.json" % mission_name)
	var bases := ProjectSettings.globalize_path("res://data/airbases")
	var d = JSON.parse_string(IafTraining.score(flight, m, bases))
	return d if d is Dictionary else {"error": "no debrief"}


func _finish(d: Dictionary) -> void:
	result = d
	d["flight"] = ProjectSettings.globalize_path(host._log.get_path_absolute())
	d["date"] = Time.get_datetime_string_from_system()
	d["elapsed_s"] = snappedf(float(host._log_t), 0.1)
	debrief_file = _dir().path_join("debrief-%s-%s.json" % [Settings.file_stamp(), mission_name])
	var f := FileAccess.open(debrief_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
	Settings.flown_debrief = debrief_file
	_pilot_log(d)
	var en: Dictionary = d.get("strings", {}).get("en", {})
	print("training %s: %s %s" % [mission_name, "PASS" if d["pass"] else "FAIL", d.get("reasons", [])])
	host._log_event(host._log_st, {"event": "mission", "name": "training " + ("pass" if d["pass"] else "fail")})
	_show_result(d, d.get("strings", {}).get("he" if _he() else "en", en))


## The attempt in the pilot log, the shape of the original game's pilot records (iaf-reborn/menu/pilots.gd: <id>.json
## = {missions: [{id, attempts: [{result, mult, bonus, kills, losses}]}]}, newest mission first), plus the debrief
## file and the date; the pilot is Settings.pilot_id, else the default pilot 14.
func _pilot_log(d: Dictionary) -> void:
	var path: String = Settings.pilot_log_file()
	if out_dir != "":
		path = out_dir.path_join(path.get_file())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var missions: Array = Settings.load_json(path).get("missions", [])
	var id := int(host.mission_id)
	var entry: Dictionary = {}
	for m in missions:
		if int(m.id) == id:
			entry = m
	if entry.is_empty():
		entry = {"id": id, "attempts": []}
		missions.push_front(entry)
	(
		entry
		. attempts
		. append(
			{
				"result": 1 if d["pass"] else 0,
				"mult": 1.0,
				"bonus": 0,
				"kills": [],
				"losses": [],
				"debrief": debrief_file,
				"date": d.date,
			}
		)
	)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"missions": missions}))


## The result over the flight until the flight ends and the front end opens its debrief: pass / fail, the reasons
## and the numbers.
func _show_result(d: Dictionary, s: Dictionary) -> void:
	var lines := [String(s.get("pass" if d["pass"] else "fail", ""))]
	for r in d.get("reasons", []):
		lines.append(String(s.get(r, r)))
	for it in d.get("items", []):
		var v = it.get("value")
		var num := str(int(v)) if v != null and float(v) == roundf(float(v)) else str(v)
		var shown := String(s.get(it.get("note", ""), "")) if v == null else "%s %s" % [num, String(it.unit)]
		lines.append("%s: %s" % [String(s.get(it.id, it.id)), shown.strip_edges()])
	ui.show_panel("\n".join(lines))
	open = false
