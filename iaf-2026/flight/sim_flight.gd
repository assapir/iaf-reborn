# IAF 2026's part of the flight scene (Settings.flight_addon, a child of terrain_view.gd): the radio menu and the
# training run (iaf-2026/docs/training.md §7–§9).
# - The radio menu: the "Call the tower" key (Ctrl+T, command 107) opens a numbered list; 1–4 pick a request (start-up,
#   taxi, take-off, contact the tower for landing), any other key closes it. The tower answers by TTS (radio.gd
#   request), each call a `radio` event in the recording.
# - A training mission (the compiled mission's `sim.training`): at its end the recording is scored by IafTraining
#   (crates/iaf-tools training.rs), the debrief record written to user://debriefs/ and the attempt to the pilot log.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
## The menu's lines: [request id, English, Hebrew] (radio.gd request; "landing": its Ctrl+T contact_tower).
const ITEMS := [
	["startup", "Request start-up", "בקשת התנעה"],
	["taxi", "Request taxi", "בקשת הסעה"],
	["takeoff", "Request take-off", "בקשת המראה"],
	["landing", "Contact tower (landing)", "קריאה למגדל (נחיתה)"],
]
const TITLE := {"en": "Radio: %s tower", "he": "קשר: מגדל %s"}
## The pilot's call, printed (no pilot voice for it yet: sound.md §7).
const CALLS := {"startup": "request start-up", "taxi": "request taxi", "takeoff": "ready for take-off"}
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
var _panel: PanelContainer
var _label: Label
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
	_build_menu()


func _dir() -> String:
	var d := out_dir
	if d == "":
		d = OS.get_temp_dir().path_join("iaf2026-debriefs") if Settings.isolated() else "user://debriefs"
	DirAccess.make_dir_recursive_absolute(d)
	return d


# --- the radio menu ---------------------------------------------------------------------------------------------------


func _he() -> bool:
	return Settings.language == "he"


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 16
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 96)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6)
	box.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_panel.add_child(_label)
	_panel.visible = false
	layer.add_child(_panel)


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


## The label's system font: one with Hebrew glyphs in Hebrew (a font that lacks them spaced the fallback's letters
## apart, 2026-11-03); the sim's own OFL font comes with its front end (item E2).
func _font() -> void:
	var font := SystemFont.new()
	var he := ["Noto Sans Hebrew", "Arial", "DejaVu Sans"]
	font.font_names = PackedStringArray(he if _he() else ["Noto Sans", "Arial", "DejaVu Sans"])
	_label.add_theme_font_override("font", font)


func set_open(on: bool) -> void:
	open = on
	_font()
	_label.text = menu_text()
	_label.text_direction = Control.TEXT_DIRECTION_RTL if _he() else Control.TEXT_DIRECTION_LTR
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	_panel.visible = on


## A key press (terrain_view.gd before its key table): the "Call the tower" key opens / closes the menu; while it is
## open 1–4 pick and any other key closes it. True when taken.
func key(event: InputEventKey) -> bool:
	if event.echo or event.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return open and event.echo  # a lone modifier is part of the next key (Ctrl+T closes the menu)
	var rec: int = host.keys.find_key(host.keys.key_of_event(event), Settings.key_bindings)
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
	host._on_subtitle("%s tower, %s, %s" % [_tower_name(), cs, CALLS[id]])
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
	debrief_file = _dir().path_join("debrief-%s-%s.json" % [Settings.file_stamp(), mission_name])
	var f := FileAccess.open(debrief_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "  ") + "\n")
	_pilot_log(d)
	var en: Dictionary = d.get("strings", {}).get("en", {})
	print("training %s: %s %s" % [mission_name, "PASS" if d["pass"] else "FAIL", d.get("reasons", [])])
	host._log_event(host._log_st, {"event": "mission", "name": "training " + ("pass" if d["pass"] else "fail")})
	_show_result(d, d.get("strings", {}).get("he" if _he() else "en", en))


## The attempt in the pilot log, the shape of the original game's pilot records (iaf-reborn/menu/pilots.gd: <id>.json
## = {missions: [{id, attempts: [{result, mult, bonus, kills, losses}]}]}, newest mission first), plus the debrief
## file and the date; the pilot is Settings.pilot_id, else the default pilot 14.
func _pilot_log(d: Dictionary) -> void:
	var dir := out_dir
	if dir == "":
		dir = _dir().path_join("pilots") if Settings.isolated() else "user://pilots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%d.json" % (Settings.pilot_id if Settings.pilot_id >= 0 else 14))
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
		f.store_string(JSON.stringify({"missions": missions}, "  ") + "\n")


## The result over the flight until the debrief page (item E2): pass / fail, the reasons and the numbers.
func _show_result(d: Dictionary, s: Dictionary) -> void:
	var lines := [String(s.get("pass" if d["pass"] else "fail", ""))]
	for r in d.get("reasons", []):
		lines.append(String(s.get(r, r)))
	for it in d.get("items", []):
		var v = it.get("value")
		var num := str(int(v)) if v != null and float(v) == roundf(float(v)) else str(v)
		var shown := String(s.get(it.get("note", ""), "")) if v == null else "%s %s" % [num, String(it.unit)]
		lines.append("%s: %s" % [String(s.get(it.id, it.id)), shown.strip_edges()])
	_font()
	_label.text = "\n".join(lines)
	_label.text_direction = Control.TEXT_DIRECTION_RTL if _he() else Control.TEXT_DIRECTION_LTR
	_panel.visible = true
	open = false
