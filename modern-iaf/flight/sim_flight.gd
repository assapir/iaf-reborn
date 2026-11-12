# Modern IAF's part of the flight scene (Settings.flight_addon, a child of terrain_view.gd): the radio menu and the
# training run (modern-iaf/docs/training.md §7–§9).
# - The text over the flight in the sim's own look (flight_ui.gd): the mission card (H), the radio lines, the panel.
# - The radio menu: the "Call the tower" key (Ctrl+T, command 107) opens a numbered list of the calls that fit the
#   moment (IafTraining.radio_calls: start-up, taxi, take-off, contact the tower for landing); a number picks, any
#   other key closes it. The tower answers by TTS (radio.gd request), each call a `radio` event in the recording.
# - A training mission (the compiled mission's `sim.training`): IafTraining (crates/iaf-tools training.rs) checks each
#   frame for a fail (a crash, damage, the wheels off the pavement) and ends the mission at once on one; else the
#   mission ends its hold after the goal, or when the player ends the flight. At its end the recording is scored by
#   IafTraining, the sortie and its debrief record stored in the records database (IafPilotLog).
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
## The menu's line when no call fits now.
const NO_CALL := {"en": "No call fits now", "he": "אין קריאה מתאימה כעת"}
## The pilot's call, printed in the game's language and said by the pilot's voice (radio.gd PILOT_CALL: the address,
## the callsign, REQ_<ID>; modern-iaf/docs/sound.md §5.2).
const CALLS := {
	"startup": ["request start-up", "בקשת התנעה"],
	"taxi": ["request taxi", "בקשת הסעה"],
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
## A take-off is scored once airborne with the gear up (every SCORE_EVERY s until it passes), a start-up once the
## engine idles with the avionics up; either this long past its time budget. A pass ends the mission after the rules'
## hold (IafTraining.end_hold_s).
# ponytail: each score re-reads the whole recording (O(length)); a scorer fed sample by sample if it shows.
const SCORE_EVERY := 3.0
const PAST_BUDGET := 5.0

var host: Node
var open := false
## The menu's calls as shown (ids), and the tower's answers so far (templates; approvals for IafTraining.radio_calls).
var shown: Array = []
var answers := PackedStringArray()
var _hold_m := {}  # iaf.ibx section -> its holding point's distance to the lineup point (m), once read
## The text over the flight: the mission card, the band of radio lines, the panel, the key hint (flight_ui.gd).
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
var _pass_at := INF
## When the flight ends into the debrief (ms, real time), once the mission ended; the banner over the view.
var _end_ms := INF
var _banner: PanelContainer
## The start-up checklist (the readable mission's training.checklist: [{step, key, en, he, where, wait}]), the
## steps done (ids), a step's fault waiting for the live check, the last fault shown, and the card.
var checklist: Array = []
var done: Array = []
var _fault := ""
var _fault_shown := ""
var _card: PanelContainer
const CARD_TITLE := {"en": "START-UP CHECKLIST", "he": "רשימת התנעה"}
const CARD_DONE := {"en": "All steps done.", "he": "כל השלבים בוצעו."}
const STEP_IDS := ["main_power", "starter", "engine", "avionics", "ins", "canopy"]
## The checklist's first key record (modern-iaf/data/keys.json, records 119–124: STEP_IDS in order; commands 210–215).
const CHECK_KEY := 119
## The engine step has no key: the throttle moved up from OFF is it, as the real idle-cutoff detent (training.md
## §7.1). The card names the Throttle idle key (record 7, the 1 key); OFF is the throttle's bottom, a lever's noise
## allowed.
const THROTTLE_IDLE_KEY := 7
const THROTTLE_OFF := 0.02
## The throttle last frame (-1 before the first: a lever already up at the start is no step).
var _throttle_was := -1.0
## The 3D cockpit's start-up switches put off for a cold start (_cold_switches), once.
var _switches_off := false
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
	# The card opens at the start, once the loading screen is gone: it freezes the flight, which would stop the loading
	# under the screen for good (the 2026-11-10 hang at "the jet"). Scripted runs (IAF_DEFAULT_SETTINGS) fly on without it.
	# A mission with the start-up checklist opens with its card instead (training.md §7.1); H opens the mission card.
	if Settings.card_at_start and checklist.is_empty():
		_card_after_loading()
	if not checklist.is_empty():
		_build_card()


func _dir() -> String:
	var d := out_dir
	if d == "":
		d = Settings.records_dir()
	DirAccess.make_dir_recursive_absolute(d)
	return d


# --- the radio menu ---------------------------------------------------------------------------------------------------


func _he() -> bool:
	return Settings.language == "he"


## The calls that fit now, in menu order (IafTraining.radio_calls, training.md §8).
func calls() -> Array:
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
	return Array(IafTraining.radio_calls(now))


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
	var lines := [(TITLE.he if _he() else TITLE.en) % base]
	for i in shown.size():
		for it in ITEMS:
			if it[0] == shown[i]:
				lines.append("%d. %s" % [i + 1, it[lang]])
	if shown.is_empty():
		lines.append(NO_CALL.he if _he() else NO_CALL.en)
	return "\n".join(lines)


func _tower_name() -> String:
	return _base_name(host.radio.base_at(host.radio._pos()))


## Base `i`'s name in the game's language; "—" for no tower.
func _base_name(i: int) -> String:
	var r: Node = host.radio
	if i < 0 or i >= r.tower_count:
		return "—"
	var names: Array = BASE_NAMES.get(String(r.bases[i].name), [r.bases[i].name, r.bases[i].name])
	return names[1 if _he() else 0]


func set_open(on: bool) -> void:
	open = on
	shown = calls() if on else []
	ui.show_panel(menu_text() if on else "")


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
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 201:
		ui.open_card(_sim)  # the Mission card key (keys.json record 118); the card closes itself
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
## recorded. A call that does not fit now (calls()) is not made: "".
func pick(id: String) -> String:
	if not id in calls():
		return ""
	var r: Node = host.radio
	var cs: String = r.formation_name(r._player_ent())
	# The tower called: the one in range on the ground (request's), the radio's base in the air (contact_tower's).
	var at: int = r.base if id == "landing" else r.base_at(r._pos())
	var has_tower: bool = at >= 0 and at < r.tower_count
	var line: String = "%s, %s" % [cs, CALLS[id][1 if _he() else 0]]
	if has_tower:
		line = "%s, %s" % [(TOWER.he if _he() else TOWER.en) % _base_name(at), line]
	host._on_subtitle(line)
	var twr: String = String(r.bases[at].name).to_upper() + "_TWR" if has_tower else ""
	r.say("PILOT_CALL", [twr, cs + "_P", "REQ_" + id.to_upper()], [], false)
	r.play_wav("radio_gap.ogg")
	if id == "landing":
		r.contact_tower()
		return ""
	var p: Dictionary = r.request(id)
	answers.append(String(p.template))
	host._log_event(host._log_st, {"event": "radio", "call": id, "answer": p.template, "text": p.text})
	return String(p.template)


# --- the training run -------------------------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	if not result.is_empty() and Time.get_ticks_msec() >= _end_ms:
		_end_ms = INF
		host._end_flight(true)  # into the debrief (Settings.flown_sortie)
	_throttle_step()
	_cold_switches()
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
	# A pass ends after its hold (already run); a fail shows its reason that long first.
	var hold: float = 0.0 if d["pass"] else trainer.end_hold_s()
	_end_ms = Time.get_ticks_msec() + hold * 1000.0
	if d["pass"]:
		_show_banner(COMPLETE.he if _he() else COMPLETE.en, "")
	else:
		var why: Array = d.get("reasons", [])
		_show_banner(String(s.get("fail", "")), String(s.get(why[0], why[0])) if not why.is_empty() else "")


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
		_switch(i, true)
		if id == "canopy" and host.sounds != null:
			host.sounds.play("SFX_DOOR_CLOSE")  # the canopy runs down and locks (modern-iaf/docs/sound.md §1.7)
	host._log_event(host._log_st, e)
	if _card != null:
		_fill_card()


## The 3D cockpit's switch of step `i` (its click command, 210 + i; cockpit3d_controls.gd set_switch) on or off.
func _switch(i: int, on: bool) -> void:
	var c3d = host.get("cockpit_3d")
	if is_instance_valid(c3d) and c3d.clickable != null:
		c3d.clickable.set_switch(210 + i, on)


## A cold jet's switches start off (a hot one's stay as modelled).
func _cold_switches() -> void:
	if _switches_off or host.start_engine_on or not is_instance_valid(host.get("cockpit_3d")):
		return
	_switches_off = true
	for i in STEP_IDS.size():
		_switch(i, String(STEP_IDS[i]) in done)


## The throttle up from OFF (its keys or the axis) takes the checklist's engine step once the starter step (JFS / IPP)
## is done; before it the throttle moves alone.
func _throttle_step() -> void:
	var thr := float(host.throttle)
	var up := _throttle_was >= 0.0 and _throttle_was <= THROTTLE_OFF and thr > THROTTLE_OFF
	_throttle_was = thr
	if up and _idle_step_due():
		start_step(STEP_IDS.find("engine"))


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
		for id in ["starter", "engine"]:
			done.erase(id)
			_switch(STEP_IDS.find(id), false)
	host.throttle = 0.0
	host._throttle_event()
	_throttle_was = 0.0
	host._log_event(host._log_st, e)
	if _card != null:
		_fill_card()


## The Throttle idle key (command 9 to OFF, record 7) leaves the throttle at OFF, so _throttle_step sees no move: the
## key itself takes the engine step at OFF once the starter step is done (training.md §7.1).
func _idle_key(cmd: Array) -> void:
	if int(cmd[0]) != 9 or float(cmd[1]) * 0.01 > THROTTLE_OFF or Joystick.drops_key(9):
		return
	if float(host.throttle) <= THROTTLE_OFF and _idle_step_due():
		start_step(STEP_IDS.find("engine"))


func _steps() -> Array:
	return checklist.map(func(c): return String(c.step))


func _card_after_loading() -> void:
	while is_inside_tree() and host.waiting_for_ground:
		await get_tree().process_frame
	if is_inside_tree():
		ui.open_card(_sim)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "Checklist"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the clicks reach the 3D cockpit's switches under it
	_card.add_theme_stylebox_override("panel", Look.box(Look.PAPER, Look.RULE, 1, 5, Vector2(16, 12)))
	_card.custom_minimum_size.x = 380
	ui.add_child(_card)
	_place_card()
	ui.language_changed.connect(_place_card)


## At the inline-end top (the left in Hebrew): the radio menu's panel holds the inline-start top (flight_ui.gd).
func _place_card() -> void:
	if _he():
		_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_card.grow_horizontal = Control.GROW_DIRECTION_END
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


## The card: the title with the step's number, the step to take now with its key, its switch's place and the state
## to wait for, and the fault; "All steps done." once every step is taken (the Mac play test, 2026-11-11: one step at
## a time, smaller).
func _fill_card() -> void:
	for c in _card.get_children():  # out at once: two steps in one frame leave one step shown
		_card.remove_child(c)
		c.queue_free()
	var lang := "he" if _he() else "en"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var i := 0
	while i < checklist.size() and String(checklist[i].step) in done:
		i += 1
	_card_line(v, "%s  %d/%d" % [CARD_TITLE[lang], mini(i + 1, checklist.size()), checklist.size()], 15, Look.INK_MUTED)
	if i == checklist.size():
		_card_line(v, CARD_DONE[lang], 18, Look.NAVY)
	else:
		var c: Dictionary = checklist[i]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.layout_direction = Control.LAYOUT_DIRECTION_RTL if _he() else Control.LAYOUT_DIRECTION_LTR
		row.add_theme_constant_override("separation", 16)
		v.add_child(row)
		var l := _card_line(row, "%d. %s" % [i + 1, c[lang]], 18, Look.NAVY)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rec := THROTTLE_IDLE_KEY if c.step == "engine" else CHECK_KEY + STEP_IDS.find(String(c.step))
		var k: String = ui.key_name(rec)  # as bound, Cmd on macOS
		_card_line(row, k, 16, Look.INK_MUTED).text_direction = Control.TEXT_DIRECTION_LTR
		if c.has("where"):  # the switch's name and place, for the 3D cockpit's mouse (cockpit3d_controls.gd)
			_card_line(v, String(c.where[lang]), 14, Look.INK_MUTED)
		if c.has("wait"):  # the state to wait for before the next step (the briefing's How shows the same)
			_card_line(v, String(c.wait[lang]), 14, Look.INK_MUTED)
	if _fault_shown != "":
		var f := _card_line(v, String(trainer.text(_fault_shown, lang)), 16, Color("b3261e"))
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size.x = 348


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
