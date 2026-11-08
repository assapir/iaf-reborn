# Modern IAF's part of the flight scene (Settings.flight_addon, a child of terrain_view.gd): the radio menu and the
# training run (iaf-2026/docs/training.md §7–§9).
# - The text over the flight in the sim's own look (flight_ui.gd): the mission card (H), the radio lines, the panel.
# - The radio menu: the "Call the tower" key (Ctrl+T, command 107) opens a numbered list; 1–4 pick a request (start-up,
#   taxi, take-off, contact the tower for landing), any other key closes it. The tower answers by TTS (radio.gd
#   request), each call a `radio` event in the recording.
# - A training mission (the compiled mission's `sim.training`): IafTraining (crates/iaf-tools training.rs) checks each
#   frame for a fail (a crash, damage, the wheels off the pavement) and ends the mission at once on one; else the
#   mission ends its hold after the goal, or when the player ends the flight. At its end the recording is scored by
#   IafTraining, the debrief record written to user://debriefs/ and the attempt to the pilot log.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const FlightUi := preload("flight_ui.gd")
const WizardTheme := preload("../setup/wizard_theme.gd")  # relative: a test of the original's project loads it too
const Look := preload("../menu/look.gd")
## The banner at the goal (training.md §9); a fail shows the record's "Fail" and its reason.
const COMPLETE := {"en": "Mission complete", "he": "המשימה הושלמה"}
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
## engine idles with the avionics up; either this long past its time budget. A pass ends the mission after the rules'
## hold (IafTraining.end_hold_s).
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
## The training run's IafTraining (its live check and scorer), its fail reason ("" while none) and when it passed.
var trainer: RefCounted
var _why := ""
var _pass_at := INF
## When the flight ends into the debrief (ms, real time), once the mission ended; the banner over the view.
var _end_ms := INF
var _banner: PanelContainer
## The start-up checklist (the readable mission's training.checklist: [{step, key, en, he}]), the steps done (ids),
## a step's fault waiting for the live check, the last fault shown, and the card.
var checklist: Array = []
var done: Array = []
var _fault := ""
var _fault_shown := ""
var _card: PanelContainer
const CARD_TITLE := {"en": "START-UP CHECKLIST", "he": "רשימת התנעה"}
const CARD_NEXT := {"en": "Next: %s", "he": "הבא: %s"}
const CARD_DONE := {"en": "All steps done.", "he": "כל השלבים בוצעו."}
const STEP_IDS := ["main_power", "starter", "engine", "avionics", "ins", "canopy"]
## The checklist's first key record (iaf-2026/data/keys.json, records 119–124: STEP_IDS in order; commands 210–215).
const CHECK_KEY := 119
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
		# The rules from the readable mission, as IafTraining reads them (the compiled sim.training only says it is one).
		rules = readable.get("training", {}) if sim.has("training") else {}
		mission_name = String(files[0].name) if not rules.is_empty() else ""
		checklist = readable.get("training", {}).get("checklist", [])
	if not rules.is_empty():
		trainer = ClassDB.instantiate("IafTraining")
		var err: String = trainer.open(_readable(), ProjectSettings.globalize_path("res://data/airbases"))
		if err != "":
			push_warning("training: %s" % err)
			rules = {}
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
	if not checklist.is_empty():
		_build_card()


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
	if host.ejected:
		return false  # the sortie ended: no radio
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
	if not result.is_empty() and Time.get_ticks_msec() >= _end_ms:
		_end_ms = INF
		host._end_flight(true)  # into the debrief (Settings.flown_debrief)
	if rules.is_empty() or not result.is_empty() or host.flight == null or host.get("_log") == null:
		return
	var t: float = host._log_t
	var st: Dictionary = host._log_st  # this frame's flight state (terrain_view.gd _record)
	if st.is_empty():
		return
	# A fail ends the mission at once (IafTraining decides; the wheels off the pavement go into the recording).
	if _why == "":
		var o: Vector2 = host.terrain.world_origin
		var p: Vector3 = host.rig.position
		var ent: Dictionary = host.runtime.player_entity() if host.runtime != null else {}
		_why = (
			trainer
			. check(
				{
					"on_ground": bool(st.on_ground),
					"x": o.x + p.x,
					"y": o.y - p.z,
					"crashed": host.crashed,
					"damage": float(ent.get("damage", 0.0)),
					"ejected": host.ejected,
					"fault": _fault,
				}
			)
		)
		if _why == "off_pavement":
			host._log_event(st, {"event": "surface", "paved": false})
	if _why != "" or t - _pass_at >= trainer.end_hold_s():
		_end_now(t)
		return
	if t < _next_score or _pass_at < INF:
		return
	var budget := float(rules.get("time_budget_s", 900.0))
	var ready := false
	if String(rules.get("kind", "")) == "startup":
		ready = bool(st.get("engine_on", false)) and bool(st.get("avionics", false))
		ready = ready and done.size() >= checklist.size()  # every checklist step taken
	else:
		ready = not bool(st.on_ground) and not host.gear_down
	if not (ready or t > budget + PAST_BUDGET):
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
	# A pass holds; a take-off not yet on its heading may still pass: scored again, until its budget.
	if bool(d.get("pass", false)):
		_pass_at = t
		_show_banner(COMPLETE.he if _he() else COMPLETE.en, "")
	elif t > budget + PAST_BUDGET or String(rules.kind) == "startup":
		_finish(d)


## The mission ends now: scored and finished (retried every SCORE_EVERY s if it cannot be scored).
func _end_now(t: float) -> void:
	if t < _next_score:
		return
	_next_score = t + SCORE_EVERY
	var d := score()
	if d.has("error"):
		push_warning("training: %s" % d.error)
	else:
		_finish(d)


## The player ended the flight before the mission's end: scored as it stands.
func _exit_tree() -> void:
	if not rules.is_empty() and result.is_empty() and host.get("_log") != null:
		_next_score = 0.0
		_end_now(0.0)


func _readable() -> String:
	return ProjectSettings.globalize_path("res://data/missions/%s.json" % mission_name)


## The recording so far against the mission's rules (IafTraining, the readable mission and the airbases of
## iaf-2026/data).
func score() -> Dictionary:
	host._log.flush()
	var flight: String = ProjectSettings.globalize_path(host._log.get_path_absolute())
	var d = JSON.parse_string(trainer.score(flight, _readable(), ProjectSettings.globalize_path("res://data/airbases")))
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
	var s: Dictionary = d.get("strings", {}).get("he" if _he() else "en", en)
	# A pass ends after its hold (already run); a fail shows its reason that long first.
	var hold: float = 0.0 if d["pass"] else trainer.end_hold_s()
	_end_ms = Time.get_ticks_msec() + hold * 1000.0
	if d["pass"]:
		_show_banner(COMPLETE.he if _he() else COMPLETE.en, "")
	else:
		var why: Array = d.get("reasons", [])
		_show_banner(String(s.get("fail", "")), String(s.get(why[0], why[0])) if not why.is_empty() else "")


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


# --- the start-up checklist (training.md §7.1) ------------------------------------------------------------------


## A checklist key (commands 210–215 → STEP_IDS[i]): the flight model takes the step (IafFlight.start_step decides
## its consequence and fault); the recording gets it; the card ticks it or shows the fault.
func start_step(i: int) -> void:
	if i < 0 or i >= STEP_IDS.size() or host.flight == null or not result.is_empty():
		return
	var id: String = STEP_IDS[i]
	var fault: String = host.flight.start_step(id)
	var e := {"event": "checklist", "step": id}
	if fault != "":
		e["fault"] = fault
		_fault = fault
		_fault_shown = fault
	elif not id in done:
		done.append(id)
	host._log_event(host._log_st, e)
	if _card != null:
		_fill_card()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "Checklist"
	_card.add_theme_stylebox_override("panel", Look.box(Look.PAPER, Look.RULE, 1, 5, Vector2(24, 18)))
	_card.custom_minimum_size.x = 520
	# At the inline-end top (the left in Hebrew): the radio menu's panel holds the inline-start top (flight_ui.gd).
	ui.add_child(_card)
	if _he():
		_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_card.offset_left = 24
	else:
		_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_card.offset_right = -24
	_card.offset_top = 96
	_fill_card()


## A label of the card.
func _card_line(parent: Node, text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.text_direction = Control.TEXT_DIRECTION_RTL if _he() else Control.TEXT_DIRECTION_LTR
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(l)
	return l


## The card: the title, each step with its key (ticked when done, the next one marked), the next step or the fault.
func _fill_card() -> void:
	for c in _card.get_children():
		c.queue_free()
	var lang := "he" if _he() else "en"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_card.add_child(v)
	_card_line(v, CARD_TITLE[lang], 22, Look.NAVY)
	var next := ""
	for i in checklist.size():
		var c: Dictionary = checklist[i]
		var is_done := String(c.step) in done
		var is_next := not is_done and next == ""
		if is_next:
			next = String(c[lang])
		var row := HBoxContainer.new()
		row.layout_direction = Control.LAYOUT_DIRECTION_RTL if _he() else Control.LAYOUT_DIRECTION_LTR
		row.add_theme_constant_override("separation", 16)
		v.add_child(row)
		var mark := "✓" if is_done else ("▶" if is_next else "·")
		var colour: Color = Look.INK_MUTED if is_done else (Look.NAVY if is_next else Look.INK)
		var l := _card_line(row, "%s  %d. %s" % [mark, i + 1, c[lang]], 20, colour)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var k: String = ui.key_name(CHECK_KEY + STEP_IDS.find(String(c.step)))  # as bound, Cmd on macOS
		_card_line(row, k, 18, Look.INK_MUTED).text_direction = Control.TEXT_DIRECTION_LTR
	_card_line(v, CARD_NEXT[lang] % next if next != "" else CARD_DONE[lang], 20, Look.NAVY)
	if _fault_shown != "":
		_card_line(v, String(trainer.text(_fault_shown, lang)), 20, Color("b3261e")).autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART
		)


## The banner over the view in the front end's look (navy, Heebo) until the flight ends into the debrief: "Mission
## complete", or "Fail" with the reason that ended it.
func _show_banner(title: String, reason: String) -> void:
	if _banner != null:
		_banner.queue_free()
	var font := FontFile.new()
	font.load_dynamic_font(ProjectSettings.globalize_path(WizardTheme.FONT))
	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.add_theme_stylebox_override("panel", Look.box(Look.NAVY, Look.ACCENT, 3, 5, Vector2(48, 24)))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 160
	var v := VBoxContainer.new()
	_banner.add_child(v)
	for line in [[title, 48, Color.WHITE], [reason, 26, Look.ACCENT_TEXT]]:
		if line[0] == "":
			continue
		var l := Label.new()
		l.text = line[0]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", line[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_direction = Control.TEXT_DIRECTION_RTL if _he() else Control.TEXT_DIRECTION_LTR
		v.add_child(l)
	ui.add_child(_banner)
	ui.show_panel("")
	open = false
