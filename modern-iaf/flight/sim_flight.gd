# Modern IAF's part of the flight scene (Settings.flight_addon, a child of terrain_view.gd): the radio menu and the
# training run (modern-iaf/docs/training.md §7–§9).
# - The text over the flight in the sim's own look (flight_ui.gd): the radio lines, the panel, the key hint.
# - The radio menu: the "Call the tower" key (Ctrl+T, command 107) opens a numbered list of the calls that fit the
#   moment (IafTraining.radio_calls: start-up, taxi, line-up, take-off, contact the tower for landing); a number
#   picks, any other key closes it. The tower answers by TTS (radio.gd request), each call a `radio` event in the
#   recording; each line's subtitle shows as its voice starts (radio.gd cue_subtitle).
# - A training mission (the compiled mission's `sim.training`): IafTraining (crates/iaf-tools training.rs) checks each
#   frame for a fail (a crash, damage, the wheels off the pavement, a phase without the tower's clearance or the roll
#   on another runway: the tower says so) and ends the mission at once on one; a pass is kept and the flight goes on
#   until the player ends it. At its end the recording is scored by
#   IafTraining, the sortie and its debrief record stored in the records database (IafPilotLog).
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const Kneeboard := preload("kneeboard.gd")
const FlightUi := preload("flight_ui.gd")
const WizardTheme := preload("../setup/wizard_theme.gd")  # relative: a test of the original's project loads it too
const Look := preload("../menu/look.gd")
## The banner at the goal (training.md §9: strings fl_complete, under it fl_fly_on) stays BANNER_S s; a fail shows
## the record's "Fail" and its reason.
const BANNER_S := 10.0
## The menu's lines: [request id, English, Hebrew] (radio.gd request; "landing": its Ctrl+T contact_tower).
const ITEMS := [
	["startup", "Request start-up", "בקשת התנעה"],
	["taxi", "Request taxi", "בקשת הסעה"],
	["lineup", "Request line-up", "בקשת כניסה למסלול"],
	["takeoff", "Request take-off", "בקשת המראה"],
	["landing", "Contact tower (landing)", "קריאה למגדל (נחיתה)"],
]
## The pilot's call, printed in the game's language and said by the pilot's voice (radio.gd PILOT_CALL: the address,
## the callsign, REQ_<ID>; modern-iaf/docs/sound.md §5.2).
const CALLS := {
	"startup": ["request start-up", "בקשת התנעה"],
	"taxi": ["request taxi", "בקשת הסעה"],
	"lineup": ["request line-up", "בקשת כניסה למסלול"],
	"takeoff": ["ready for take-off", "בקשת המראה"],
	"landing": ["request landing", "בקשת נחיתה"],
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
## A take-off is scored once airborne (every SCORE_EVERY s until it passes), a start-up once the
## engine idles with the avionics up; either this long past its time budget. A pass is kept and the flight goes on.
# ponytail: each score re-reads the whole recording (O(length)); a scorer fed sample by sample if it shows.
const SCORE_EVERY := 3.0
const PAST_BUDGET := 5.0
## A take-off's fail reasons no later flying can mend: the mission ends on them once airborne.
const FINAL := ["wrong_runway", "excursion", "over_time"]

var host: Node
var open := false
## The menu's calls as shown (ids), and the tower's answers so far (templates; approvals for IafTraining.radio_calls).
var shown: Array = []
var answers := PackedStringArray()
var _hold_m := {}  # iaf.ibx section -> its holding point's distance to the lineup point (m), once read
## The text over the flight: the band of radio lines, the panel, the key hint (flight_ui.gd).
var ui: Control
var _sim := {}
## The training mission: its readable file's name (res://data/missions/<name>.json) and rules; {} for a flight without.
var mission_name := ""
var rules := {}
## The jet the mission flies (its readable file's start.unit: f16i, f16d, f35i), stored with the sortie.
var plane := ""
## The debrief record once scored ({} before), and its sortie in the records database (0 before).
var result := {}
var sortie := 0
## Tests: where the records database and (isolated) the recording go; "" = Settings.records_dir().
var out_dir := ""
var _next_score := 0.0
var _ready_at := INF
## The training run's IafTraining (its live check and scorer), its fail reason ("" while none) and when it passed.
var trainer: RefCounted
var _why := ""
## The runway end the jet is lined up on that is not the mission's (shown), and the ends the tower named already.
var _wrong_shown := ""
var _wrong_said: Array = []
## When the flight ends into the debrief (ms, real time), once the mission ended; the banner over the view.
var _end_ms := INF
var _banner: PanelContainer
## The start-up checklist (the readable mission's training.checklist: [{step, key, en, he, where, wait}]), the
## steps whose switches are on (ids: IafFlight.start_on, read each frame), a step's fault waiting for the live
## check, the last fault shown, and the pilot's notebook (kneeboard.gd: its START-UP page shows them; training.md §11).
var checklist: Array = []
var done: Array = []
var _fault := ""
var _fault_shown := ""
var kneeboard: Node
const STEP_IDS := ["main_power", "starter", "engine", "avionics", "ins", "canopy"]
## The F-16's power switches one by one (command 219's p2 → SYSTEMS[i]; iaf-flight start.rs SYSTEMS, the same order):
## the four AVIONIC POWER switches (together the avionics step) and the SNSR PWR panel's FCR and RDR ALT.
const SYSTEMS := ["mmc", "st_sta", "mfd", "ufc", "fcr", "rdr_alt"]
## The checklist's first key record (modern-iaf/data/keys.json, records 119–124: STEP_IDS in order; commands 210–215).
const CHECK_KEY := 119
## The engine step has no key: the throttle moved up from OFF is it, as the real idle-cutoff detent (training.md
## §7.1). The briefing names the Throttle idle key (record 7, the 1 key); OFF is the throttle's bottom, a lever's noise
## allowed.
const THROTTLE_IDLE_KEY := 7
const THROTTLE_OFF := 0.02
## The throttle last frame (-1 before the first: a lever already up at the start is no step).
var _throttle_was := -1.0
## The 3D cockpit's start-up switches as last set from the flight model (_sync_switches): step id -> on.
var _shown := {}
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
		plane = String(readable.get("start", {}).get("unit", ""))
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
	ui.language_changed.connect(_language_changed)
	# A mission with the start-up checklist starts with the notebook raised at its START-UP page (training.md §11).
	kneeboard = Kneeboard.new(self)
	add_child(kneeboard)


func _dir() -> String:
	var d := out_dir
	if d == "":
		d = Settings.records_dir()
	DirAccess.make_dir_recursive_absolute(d)
	return d


# --- the radio menu ---------------------------------------------------------------------------------------------------


func _he() -> bool:
	return Settings.language == "he"


## The menu's calls, in menu order (IafTraining.radio_calls, training.md §8): every ground call on the ground,
## landing in the air.
func calls() -> Array:
	return Array(IafTraining.radio_calls(_radio_now()))


## The call the moment expects next ("" none; IafTraining.next_call), marked in a training mission's menu.
func next_call() -> String:
	return String(IafTraining.next_call(_radio_now()))


func _radio_now() -> Dictionary:
	var r: Node = host.radio
	var st: Dictionary = host.flight.state() if host.flight != null else {}
	var now := {
		"on_ground": bool(st.get("on_ground", true)),
		"engine_on": bool(st.get("engine_on", false)),
		"avionics": bool(st.get("avionics", false)),
		"answers": answers,
		"hot": host.start_engine_on and not host.start_airborne,
	}
	var p: Vector3 = r._pos()
	var at: int = r.base_at(p)
	if at >= 0 and at < r.tower_count:
		var l := Vector2(r.bases[at].lineup.x, r.bases[at].lineup.y)
		now["lineup_m"] = Vector2(p.x, p.y).distance_to(l)
		var sec := String(r.bases[at].name)
		if not _hold_m.has(sec):
			_hold_m[sec] = _hold_of(sec, l)
		if _hold_m[sec] != null:
			now["hold_m"] = _hold_m[sec]
	return now


## The holding point of iaf.ibx section `sec`: its taxi-out path's last point before the lineup `l`; its distance to
## `l` (m), null without a path.
func _hold_of(sec: String, l: Vector2) -> Variant:
	var s: Dictionary = Settings.load_ibx(Settings.own_dir().path_join("iaf.ibx")).get(sec, {})
	var n := int(s.get("TaxiWayPtsFrom", 0))
	if n < 2:
		return null
	return Vector2(float(s["FromTaxiPtX%d" % (n - 2)]), float(s["FromTaxiPtY%d" % (n - 2)])).distance_to(l)


## The menu's text in the game's language: the title and the calls in `shown`, numbered.
func menu_text() -> String:
	var lang := 1 if not _he() else 2
	var base := _tower_name()
	var lines := [ui.s("fl_radio") % base]
	var next := next_call() if not rules.is_empty() else ""
	for i in shown.size():
		for it in ITEMS:
			if it[0] == shown[i]:
				lines.append("%d. %s%s" % [i + 1, it[lang], ui.s("fl_next") if it[0] == next else ""])
	return "\n".join(lines)


func _tower_name() -> String:
	return _base_name(host.radio.base_at(host.radio._pos()))


## Base `i`'s name in the game's language (`lang` 0 English, 1 Hebrew); "—" for no tower.
func _base_name(i: int, lang := -1) -> String:
	var r: Node = host.radio
	if i < 0 or i >= r.tower_count:
		return "—"
	var names: Array = BASE_NAMES.get(String(r.bases[i].name), [r.bases[i].name, r.bases[i].name])
	return names[lang if lang >= 0 else (1 if _he() else 0)]


## The panel in the new language: the open menu now, a training line ("To complete: …", the wrong runway) at the next
## frame's score.
func _language_changed() -> void:
	if open:
		ui.show_panel(menu_text())
	_wrong_shown = ""
	_next_score = 0.0


func set_open(on: bool) -> void:
	open = on
	shown = calls() if on else []
	ui.show_panel(menu_text() if on else "")
	_wrong_shown = ""  # the wrong-runway line (if any) back once the menu closes


## A radio line or a message (terrain_view.gd _on_subtitle): the band of the sim's own text, not the original's
## console.
func subtitle(text: String) -> void:
	if ui != null:
		ui.subtitle(text)


## A key press (terrain_view.gd before its key table): the "Call the tower" key opens / closes the menu; while it is
## open a shown call's number picks it and any other key closes it. True when taken.
func key(event: InputEventKey) -> bool:
	if host.ejected:
		return false  # the sortie ended: no radio
	if event.echo or event.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return open and event.echo  # a lone modifier is part of the next key (Ctrl+T closes the menu)
	var rec: int = host.keys.find_key(host.keys.key_of_event(event), Settings.key_bindings)
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 203:
		# The Checklist notebook key (keys.json record 118, H; training.md §11).
		kneeboard.toggle()
		return true
	if not open and kneeboard.key(event):
		return true
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 107:
		set_open(not open)
		return true
	if not open:
		if rec >= 0:
			_idle_key(host.keys.records[rec].press)
		return false
	var k := event.keycode
	var i := -1
	if k >= KEY_1 and k <= KEY_9:
		i = k - KEY_1
	elif k >= KEY_KP_1 and k <= KEY_KP_9:
		i = k - KEY_KP_1
	var ids := shown
	set_open(false)
	if i >= 0 and i < ids.size():
		pick(ids[i])
	return true


## One menu pick: the pilot's call printed and said, the gap, the tower's answer (radio.gd request), a `radio` event
## recorded. A ground call whose earlier clearance is missing gets "negative, hold position, request … first"
## (ACFT_NEGATIVE, IafTraining.missing_before) and clears nothing. A call not in the menu now (calls()) is not made: "".
func pick(id: String) -> String:
	if not id in calls():
		return ""
	var r: Node = host.radio
	var cs: String = r.formation_name(r._player_ent())
	# The tower called: the one in range on the ground (request's), the radio's base in the air (contact_tower's).
	var at: int = r.base if id == "landing" else r.base_at(r._pos())
	var has_tower: bool = at >= 0 and at < r.tower_count
	var lines := ["%s, %s" % [cs, CALLS[id][0]], "%s, %s" % [cs, CALLS[id][1]]]
	if has_tower:
		lines[0] = "%s, %s" % [TOWER.en % _base_name(at, 0), lines[0]]
		lines[1] = "%s, %s" % [TOWER.he % _base_name(at, 1), lines[1]]
	r.bilingual(lines[0], lines[1])  # shown in the language of the moment it shows (flight_ui.gd)
	var line: String = lines[1 if _he() else 0]
	var twr: String = String(r.bases[at].name).to_upper() + "_TWR" if has_tower else ""
	r.say("PILOT_CALL", [twr, cs + "_P", "REQ_" + id.to_upper()], [], false, line)  # the line as the voice starts
	r.play_wav("radio_gap.ogg")
	if id == "landing":
		r.contact_tower()
		return ""
	var need := String(IafTraining.missing_before(id, answers, host.start_engine_on and not host.start_airborne))
	var p: Dictionary
	if need != "" and has_tower:
		p = r.say("ACFT_NEGATIVE", [r._tower_callsign(), "FIRST_" + need.to_upper()])
		r.say("ACFT_ROGER", [], [], false)
	else:
		p = r.request(id)
	answers.append(String(p.template))
	host._log_event(host._log_st, {"event": "radio", "call": id, "answer": p.template, "text": p.text})
	return String(p.template)


# --- the training run -------------------------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	if not result.is_empty() and Time.get_ticks_msec() >= _end_ms:
		_end_ms = INF
		host._end_flight(true)  # into the debrief (Settings.flown_sortie)
	_throttle_step()
	_sync_switches()
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
		var now := {
			"on_ground": bool(st.on_ground),
			"x": o.x + p.x,
			"y": o.y - p.z,
			"crashed": host.crashed,
			"damage": float(ent.get("damage", 0.0)),
			"ejected": host.ejected,
			"fault": _fault,
			"rpm": float(st.get("rpm", 0.0)) * 100.0,
			"speed_kt": float(st.get("speed_kt", 0.0)),
			"heading": float(st.get("heading", 0.0)),
			"answers": answers,
			"hot": host.start_engine_on and not host.start_airborne,
		}
		_wrong_runway(String(trainer.wrong_runway(now)))
		_why = trainer.check(now)
		if _why == "off_pavement":
			host._log_event(st, {"event": "surface", "paved": false})
		elif _why.ends_with("_clearance") or _why == "wrong_runway":
			host._log_event(st, {"event": "clearance", "reason": _why})
			# The tower calls it once ("Alpha, taxi without clearance": ACFT_NO_TAXI_CLEARANCE, training.md §3.3); a
			# wrong runway it named at the line-up (_wrong_runway).
			if _why != "wrong_runway":
				host.radio.say("ACFT_" + _why.to_upper(), [host.radio._tower_callsign()])
	if _why != "":
		_end_now(t)
		return
	if t < _next_score:
		return
	var budget := float(rules.get("time_budget_s", 900.0))
	var ready := false
	if String(rules.get("kind", "")) == "startup":
		ready = bool(st.get("engine_on", false)) and bool(st.get("avionics", false))
		ready = ready and _steps().all(func(id): return id in done)  # every checklist step's switch on
	else:
		ready = not bool(st.on_ground)  # airborne: scored with the gear up or down, so a missing goal shows
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
	# A pass holds; a take-off not yet on its heading or with the gear down may still pass: scored again, its missing
	# goal shown ("To complete: …"), until its budget. A roll off the runway or past the budget cannot pass: it ends.
	var why: Array = d.get("reasons", [])
	if bool(d.get("pass", false)):
		ui.show_panel("")
		_finish(d)  # a pass stays: the flight goes on until the player ends it
	elif t > budget + PAST_BUDGET or String(rules.kind) == "startup" or why.any(func(r): return r in FINAL):
		_finish(d)
	elif not open and not why.is_empty():
		ui.show_panel(String(trainer.text("todo_" + String(why[0]), "he" if _he() else "en")))


## Lined up on runway end `wrong` ("" none), not the mission's: the tower says so once per end ("Alpha, you are on
## runway 7 left, the assigned runway is 25 right": ACFT_WRONG_RUNWAY, training.md §3.3) and the panel shows it while
## it lasts; the roll on it fails (IafTraining.check "wrong_runway").
func _wrong_runway(wrong: String) -> void:
	var mine := String(trainer.runway())
	if wrong != "" and not wrong in _wrong_said:
		_wrong_said.append(wrong)
		host.radio.say("ACFT_WRONG_RUNWAY", [host.radio._tower_callsign()], [wrong, mine])
	if wrong == _wrong_shown or open:  # the menu holds the panel: shown once it closes
		return
	_wrong_shown = wrong
	var t := String(trainer.text("todo_wrong_runway", "he" if _he() else "en")).split("{}")
	ui.show_panel(t[0] + wrong + t[1] + mine + t[2] if wrong != "" else "")


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
## modern-iaf/data).
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
	d["plane"] = plane
	var db: String = Settings.records_db() if out_dir == "" else _dir().path_join("modern-iaf.sqlite")
	sortie = IafPilotLog.log_sortie(db, Settings.pilot(), int(host.mission_id), JSON.stringify(d))
	Settings.flown_sortie = sortie
	var en: Dictionary = d.get("strings", {}).get("en", {})
	print("training %s: %s %s" % [mission_name, "PASS" if d["pass"] else "FAIL", d.get("reasons", [])])
	host._log_event(host._log_st, {"event": "mission", "name": "training " + ("pass" if d["pass"] else "fail")})
	var s: Dictionary = d.get("strings", {}).get("he" if _he() else "en", en)
	# A pass: the banner with how to end, the flight going on (the user, 2026-11-13: "on mission complete - allow to
	# keep flying"); a fail shows its reason end_hold_s, then the flight ends into the debrief.
	if d["pass"]:
		_show_banner(ui.s("fl_complete"), ui.s("fl_fly_on"))
		get_tree().create_timer(BANNER_S, false).timeout.connect(_hide_banner)
	else:
		_end_ms = Time.get_ticks_msec() + trainer.end_hold_s() * 1000.0
		var why: Array = d.get("reasons", [])
		_show_banner(String(s.get("fail", "")), String(s.get(why[0], why[0])) if not why.is_empty() else "")


# --- the start-up checklist (training.md §7.1) ------------------------------------------------------------------


## A checklist switch (commands 210–215 → STEP_IDS[i]; `want` the command's p1: 1 on, -1 off, 0 (a key) the other
## way): the flight model sets it (IafFlight.start_switch decides its consequence and fault; modern-iaf/docs/cockpit.md
## §5.2); the recording gets a change ("on": false for a switch back off) or a fault; the notebook follows the switches.
func start_step(i: int, want := 0) -> void:
	if i >= 0 and i < STEP_IDS.size():
		_set_switch(STEP_IDS[i], want, STEP_IDS[i])


## One F-16 power switch (command 219, p2 → SYSTEMS[i], `want` as start_step's): an AVIONIC POWER switch's change
## of the avionics step is recorded as the step's.
func system_switch(i: int, want: int) -> void:
	if i >= 0 and i < SYSTEMS.size():
		_set_switch(SYSTEMS[i], want, "avionics")


## Switch `sw` set (IafFlight.start_switch), its checklist step `id` recorded when it changes or faults.
func _set_switch(sw: String, want: int, id: String) -> void:
	if host.flight == null or not result.is_empty():
		return
	var was: bool = host.flight.start_on(id)
	var fault: String = host.flight.start_switch(sw, want)
	var on: bool = host.flight.start_on(id)
	var e := {"event": "checklist", "step": id}
	if fault != "":
		e["fault"] = fault
		_fault = fault
		_fault_shown = fault
	elif not on:
		e["on"] = false
	if fault != "" or on != was:
		host._log_event(host._log_st, e)
	if on != was and id == "canopy" and host.sounds != null:
		# The canopy runs down and locks, or opens (modern-iaf/docs/sound.md §1.7).
		host.sounds.play("SFX_DOOR_CLOSE" if on else "SFX_DOOR_OPEN")
	_shown.erase(sw)  # shown again from the flight model: a click it refused goes back
	_sync_switches()
	kneeboard.refresh()  # a fault shows on the START-UP page even with no switch changed


## The checklist from the flight model's switches (IafFlight.start_on), each frame: `done`, the notebook, and the 3D
## cockpit's switches that changed (cockpit3d_controls.gd set_switch: a step's by its command 210 + i, a power
## switch's by 219 and its index; the JFS switch springs back to OFF; a cold jet's start off; a refused click back).
func _sync_switches() -> void:
	if host.flight == null:
		return
	var now := []
	for id in STEP_IDS:
		if host.flight.start_on(id):
			now.append(id)
	var c3d = host.get("cockpit_3d")
	if is_instance_valid(c3d) and c3d.clickable != null:
		for id in STEP_IDS + SYSTEMS:
			var on: bool = id in now if id in STEP_IDS else host.flight.start_on(id)
			if _shown.get(id) != on:
				var i: int = STEP_IDS.find(id)
				c3d.clickable.set_switch(210 + i if i >= 0 else 219, on, SYSTEMS.find(id))
			_shown[id] = on
	if now != done:
		done = now
		if kneeboard != null:
			kneeboard.refresh()


## The throttle up from OFF (its keys or the axis) takes the checklist's engine step once the starter step (JFS / IPP)
## is done; before it the throttle moves alone.
func _throttle_step() -> void:
	var thr := float(host.throttle)
	var up := _throttle_was >= 0.0 and _throttle_was <= THROTTLE_OFF and thr > THROTTLE_OFF
	_throttle_was = thr
	if up and _idle_step_due():
		start_step(STEP_IDS.find("engine"), 1)


## The throttle's move from OFF is the idle step now: the starter step done and the idle step not yet, in a mission
## whose checklist has it or in a flight without one (a restart after a shutdown).
func _idle_step_due() -> bool:
	return "starter" in done and not "engine" in done and (checklist.is_empty() or "engine" in _steps())


## The Throttle OFF key (command 218, keys.json record 121): the throttle over the idle-cutoff detent to OFF, the fuel
## cut (IafFlight.start_step "cutoff", training.md §7.2). A running engine winds down; the recording gets a checklist
## step "cutoff" with its fault (shutdown, no_start), which fails a training mission. A restart takes the starter step
## and the throttle's move from OFF again.
func throttle_off() -> void:
	if host.flight == null:
		return
	var fault: String = host.flight.start_step("cutoff")
	var e := {"event": "checklist", "step": "cutoff"}
	if fault != "":  # the fuel was on: the start's steps to take again (a cold or cranking engine keeps them)
		e["fault"] = fault
		_fault = fault
		_fault_shown = fault
	host.throttle = 0.0
	host._throttle_event()
	_throttle_was = 0.0
	host._log_event(host._log_st, e)
	_sync_switches()
	kneeboard.refresh()


## The Throttle idle key (command 9 to OFF, record 7) leaves the throttle at OFF, so _throttle_step sees no move: the
## key itself takes the engine step at OFF once the starter step is done (training.md §7.1).
func _idle_key(cmd: Array) -> void:
	if int(cmd[0]) != 9 or float(cmd[1]) * 0.01 > THROTTLE_OFF or Joystick.drops_key(9):
		return
	if float(host.throttle) <= THROTTLE_OFF and _idle_step_due():
		start_step(STEP_IDS.find("engine"), 1)


func _steps() -> Array:
	return checklist.map(func(c): return String(c.step))


func _hide_banner() -> void:
	if is_instance_valid(_banner):
		_banner.queue_free()


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
