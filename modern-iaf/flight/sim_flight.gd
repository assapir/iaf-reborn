# Modern IAF's part of the flight scene (Settings.flight_addon, a child of terrain_view.gd): the radio menu and the
# training run (modern-iaf/docs/training.md §7–§9).
# - The text over the flight in the sim's own look (flight_ui.gd): the radio lines, the panel, the key hint.
# - The radio menu: the "Call the tower" key (Ctrl+T, command 107) opens a numbered list of the calls that fit the
#   moment (IafTraining.radio_calls: start-up, taxi, line-up, take-off, contact the tower for landing); a number
#   picks, any other key closes it. The tower answers by TTS (radio.gd request), each call a `radio` event in the
#   recording; each line's subtitle shows as its voice starts (radio.gd cue_subtitle).
# - A training mission (the compiled mission's `sim.training`): IafTraining (crates/iaf-tools training.rs) checks each
#   frame for a fail (a crash, damage, the wheels off the pavement, a phase without the tower's clearance or the roll
#   on another runway: the tower says so) and ends the mission at once on one; a pass pauses the flight under a panel
#   (Continue the flight, or Debrief), the pass kept either way. At its end the recording is scored by
#   IafTraining, the sortie and its debrief record stored in the records database (IafPilotLog).
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
const Kneeboard := preload("kneeboard.gd")
const Card := preload("card.gd")
const FlightUi := preload("flight_ui.gd")
const FrameMeter := preload("frame_meter.gd")
const WizardTheme := preload("../setup/wizard_theme.gd")  # relative: a test of the original's project loads it too
const Look := preload("../menu/look.gd")
## A pass pauses the flight under the front end's "accomplished" panel (training.md §9) once the radio's queued speech
## is said; a fail shows the record's "Fail" and its reason in a banner, then the debrief.
## The menu's lines: [request id, English, Hebrew] (radio.gd request; "landing": its Ctrl+T contact_tower).
const ITEMS := [
	["startup", "Request start-up", "בקשת התנעה"],
	["taxi", "Request taxi", "בקשת הסעה"],
	["lineup", "Request line-up", "בקשת כניסה למסלול"],
	["takeoff", "Request take-off", "בקשת המראה"],
	["landing", "Contact tower (landing)", "קריאה למגדל (נחיתה)"],
]
## The first page's lines: id, English, Hebrew (the user, 19 Nov: "1: tower ... 2: wingman's commands ... 3 will be
## AWACS"). AWACS has no request call to make (its contact calls come by themselves, radio.gd), so its line is shown
## off with the reason (fl_radio_awacs_off).
const TOP := [
	["m:tower", "Tower", "מגדל"],
	["m:wingmen", "Wingmen", "המבנה"],
	["m:awacs", "AWACS", "AWACS"],
]
## The page a `0` goes back to.
const PARENT := {"tower": "", "wingmen": "", "to": "wingmen", "formation": "to"}
## The flight's pages (ours, modern-iaf/docs/ai-plan.md F5; the user, 19 Nov: "radion menu instead of hotkeys"): after
## the tower's calls, one line per addressee of the four-ship (IafAi's `to`: 0 the flight, 5 the element, 2..4 one
## wingman), its English and Hebrew label and the address the pilot says (voices.json). The callsigns are kidon style
## (the user, 20 Nov 2026; radio.gd `kidon`): the flight Kidon 1, its jets Kidon 1-1..1-4.
const ADDRESSEES := [
	[0, "Kidon 1", "כידון 1", "ALPHA_P"],
	[5, "Kidon 1, element 3–4", "כידון 1, זוג 3–4", "CMD_KIDON1_34"],
	[2, "Kidon 1-2", "כידון 1-2", "CMD_KIDON1_2"],
	[3, "Kidon 1-3", "כידון 1-3", "CMD_KIDON1_3"],
	[4, "Kidon 1-4", "כידון 1-4", "CMD_KIDON1_4"],
]
## An addressee's commands: id, English, Hebrew (the words of modern-iaf/docs/research/radio-terms.md), the particle
## said, and whom it is offered to (f the flight, e the element, w one wingman). "formation" opens the shapes' page.
const COMMANDS := [
	["formation", "Formation", "מבנה", "", "f"],
	["rejoin", "Rejoin", "הצטרפות", "CMD_REJOIN", "few"],
	["split", "Split", "פיצול", "CMD_SPLIT", "e"],
	["engage", "Engage my target", "תקיפת המטרה שלי", "CMD_ENGAGE", "few"],
	["rtb", "RTB", "חזרה לבסיס", "CMD_RTB", "few"],
	["check", "Check in", "בדיקת קשר", "CMD_CHECK", "few"],
	["ops_check", "Ops check", "בדיקת מערכות ודלק", "CMD_OPS_CHECK", "few"],
]
const SHAPES := [
	["fingertip", "Fingertip", "מבנה ארבע אצבעות", "CMD_FINGERTIP"],
	["line_abreast", "Line abreast", "מבנה מקבילי", "CMD_LINE_ABREAST"],
	["trail", "Trail", "מבנה טור", "CMD_TRAIL"],
	["echelon_right", "Echelon right", "מבנה אלכסון ימין", "CMD_ECHELON_RIGHT"],
	["echelon_left", "Echelon left", "מבנה אלכסון שמאל", "CMD_ECHELON_LEFT"],
	["diamond", "Diamond", "מבנה יהלום", "CMD_DIAMOND"],
	["vic", "Vic", "מבנה וי", "CMD_VIC"],
	["delta", "Delta", "מבנה דלתא", "CMD_DELTA"],
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
## The radio menu closes by itself this long after it opened or after its last key, s (the user, 2026-11-15: "the
## radio menu should disappear after few seconds if not in use"; the original game has no such menu: inferred).
const MENU_S := 6.0
const SCORE_EVERY := 3.0
const PAST_BUDGET := 5.0
## A take-off's fail reasons no later flying can mend: the mission ends on them once airborne.
const FINAL := ["wrong_runway", "excursion", "over_time"]

var host: Node
var open := false
var _menu_at := 0  # the radio menu's opening or last key (ms): MENU_S later it closes
## The menu's page: "" the first (Tower, Wingmen, AWACS), "tower" the tower's calls, "wingmen" the flight's
## addressees, "to" an addressee's commands (`_to`), "formation" the flight's shapes.
var page := ""
var _to := 0
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
## A start-up lesson's items of the jet's card it asks for (the readable mission's training.checklist: card item ids,
## training.md §12), the flight model's start-up steps whose switches are on (ids: IafFlight.start_on, read each
## frame), a step's fault waiting for the live check, the last fault shown, the jet's checklist card (card.gd) and
## the pilot's notebook (kneeboard.gd: its CHECKLIST page shows the card; training.md §11).
var checklist: Array = []
var card: Node
var done: Array = []
var _fault := ""
var _fault_shown := ""
var kneeboard: Node
const STEP_IDS := ["main_power", "starter", "engine", "avionics", "ins", "canopy"]
## The F-16's power switches one by one (command 219's p2 → SYSTEMS[i]; iaf-flight start.rs SYSTEMS, the same order):
## the four AVIONIC POWER switches (together the avionics step) and the SNSR PWR panel's FCR, RDR ALT, LEFT HDPT and
## RIGHT HDPT (the chin pods).
const SYSTEMS := ["mmc", "st_sta", "mfd", "ufc", "fcr", "rdr_alt", "l_hdpt", "r_hdpt"]
## The F-16's switches of three positions: a command's p1 2 puts one at its in-between position (MAIN PWR at BATT, the
## JFS at START 1, RDR ALT at STBY; iaf-flight start.rs Start::position), the flight model's step of that name.
const IN_BETWEEN := {"main_power": "main_power_batt", "starter": "starter_1", "rdr_alt": "rdr_alt_stby"}
## The avionics step's switches of SYSTEMS (the AVIONIC POWER panel's four; the step is on with all four).
const AVIONIC_POWER := ["mmc", "st_sta", "mfd", "ufc"]
## The INS knob's positions (iaf-flight start.rs INS_KNOB): STOR HDG aligns in 90 s, NORM in 8 minutes, NAV navigates.
const INS_STOR_HDG := 1
const INS_NORM := 2
const INS_NAV := 3
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
## The canopy's travel, open to shut (s): FlightGear's F-16 (Systems/jsb-controls.xml fcs/canopy-control-1, 10 s); the
## F-35I's inferred the same.
const CANOPY_S := 10.0
var _canopy_set := false
## A jet with a canopy switch and a lock lever (the F-16s' 3D cockpit; cockpit.md §5.6), and the cockpit it was read
## from: the canopy runs while the switch is held (`_canopy_drive`: 1 OPEN, -1 CLOSE) or the Canopy key's sequence is
## under way (`_canopy_run`: 1 down then the lever down, -1 up); the flight model's canopy step is the lever down.
var _spider := false
var _spider_c3d: Node = null
var _canopy_drive := 0.0
var _canopy_run := 0
var _canopy_dir := 0.0
var _canopy_snd: Node = null  # the door sound of the canopy's current run: stopped when the run stops or turns
## The cockpit view's canopy frames (own_bc's: the F-16's cut model, the F-35I's 3D cockpit) -> their shut transform;
## the 3D cockpit they were found with.
var _frames := {}
var _frames_c3d: Node = null
var _frames_bc: Node = null


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
	card = Card.new(self, plane)
	add_child(card)
	# A mission with the start-up checklist starts with the notebook raised at its START-UP page (training.md §11).
	add_child(FrameMeter.new())  # the frame time the Settings screen shows (front-end.md §4.2)
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


## The menu's text in the game's language: the title and the entries in `shown`, numbered (0 back on a later page).
func menu_text() -> String:
	return "\n".join([_title()] + _lines())


func _title() -> String:
	var he := _he()
	if page == "":
		return _bi(ui.s("fl_radio_top"))
	if page == "tower":
		return _bi(ui.s("fl_radio") % _tower_name())
	if page == "wingmen":
		return _bi(ui.s("fl_radio_to") % TOP[1][2 if he else 1])
	var a: Array = ADDRESSEES.filter(func(x): return x[0] == _to)[0]
	var who: String = a[2 if he else 1]
	return _bi(ui.s("fl_radio_to") % (who if page == "to" else "%s, %s" % [who, COMMANDS[0][2 if he else 1]]))


## Hebrew text with each Latin run (a number, "3–4", "1-2") in a Unicode isolate, so the parentheses and the
## neighbours around it keep the right-to-left order (the front end's way, flight_graphs.gd); English as is.
func _bi(t: String) -> String:
	if not _he():
		return t
	var re := RegEx.new()
	re.compile("[A-Za-z0-9]+(?:[ \u2013-][A-Za-z0-9]+)*")
	return re.sub(t, "\u2066$0\u2069", true)


## The numbered lines of `shown` (then the back line on a later page).
func _lines() -> Array:
	var lang := 1 if not _he() else 2
	var lines := []
	# No "(next)" mark (the user, 17 Nov: "remove the (next) from the raio menu").
	for i in shown.size():
		for it in (
			TOP + ITEMS + ADDRESSEES.map(func(a): return ["to:%d" % a[0], a[1] + " ›", a[2] + " ‹"]) + COMMANDS + SHAPES
		):
			if it[0] == shown[i]:
				lines.append(_bi("%d. %s" % [i + 1, it[lang]]))
				break
	if page != "":
		lines.append("0. %s" % ui.s("fl_radio_back"))
	return lines


## The lines shown off (index in `shown` -> the reason), clickable no more.
func _off() -> Dictionary:
	var off := {}
	var i: int = shown.find("m:awacs")
	if i >= 0:
		off[i] = _bi(ui.s("fl_radio_awacs_off"))
	return off


## The entries of the page now (ids): Tower, Wingmen, AWACS; the tower's calls; the flight's addressees with an AI jet
## alive (the four-ship, IafAi); an addressee's commands; the shapes.
func _entries() -> Array:
	if page == "":
		return TOP.map(func(x): return x[0])
	if page == "formation":
		return SHAPES.map(func(x): return x[0])
	if page == "to":
		var kind := "f" if _to == 0 else ("e" if _to == 5 else "w")
		return COMMANDS.filter(func(c): return kind in c[4]).map(func(c): return c[0])
	if page == "tower":
		return calls()
	var ai = host.get("ai")
	var fa = ai.get("flight_ai") if ai != null else null
	var ids := []
	if fa == null or host.ejected:
		return ids
	var alive := {}
	for m in ai._ai_members:
		if not m[1].player and int(m[1].state) < 3:
			alive[int(m[0])] = true
	for a in ADDRESSEES:
		var n: int = a[0]
		if (n == 0 and not alive.is_empty()) or (n == 5 and (alive.has(3) or alive.has(4))) or alive.has(n):
			ids.append("to:%d" % n)
	return ids


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
		_show()
	_wrong_shown = ""
	_next_score = 0.0


func set_open(on: bool) -> void:
	open = on
	page = ""
	_menu_at = Time.get_ticks_msec()
	_show()
	_wrong_shown = ""  # the wrong-runway line (if any) back once the menu closes


## The menu's page now in the panel, each line clickable (`choose`), or the panel cleared when closed.
func _show() -> void:
	shown = _entries() if open else []
	if open:
		ui.show_menu(_title(), _lines(), _clicked, _off())
	else:
		ui.show_panel("")


## A line clicked: its number, 0 the back line (after the entries).
func _clicked(i: int) -> void:
	_menu_at = Time.get_ticks_msec()
	choose(i + 1 if i < shown.size() else 0)


## The menu's entry `n` (1 the first; 0 back to the first page, else closes): a tower's call is made, an addressee or
## Formation opens its page, a command is given (flight_command). Any other number closes the menu.
func choose(n: int) -> void:
	var ids := shown
	var id: String = String(ids[n - 1]) if n >= 1 and n <= ids.size() else ""
	if n == 0 and page != "":
		page = PARENT[page]
		_show()
	elif id == "m:awacs":
		pass  # off: the line says why
	elif id.begins_with("m:"):
		page = id.substr(2)
		_show()
	elif id.begins_with("to:"):
		_to = int(id.substr(3))
		page = "to"
		_show()
	elif id == "formation":
		page = "formation"
		_show()
	elif page == "tower":
		set_open(false)
		pick(id)
	elif page == "":
		set_open(false)
	else:
		set_open(false)
		if id != "":
			flight_command(_to, id)


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
		_menu_at = Time.get_ticks_msec()  # a key held in the menu keeps it open
		return open and event.echo  # a lone modifier is part of the next key (Ctrl+T closes the menu)
	var rec: int = host.keys.find_key(host.keys.key_of_event(event), Settings.key_bindings)
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 203:
		# The Checklist notebook (keys.json, training.md §11): p1 0 raise / stow (record 118, H), -1 / 1 the previous /
		# next page while it is raised (records 222 / 223, Page Up / Page Down).
		var way := int(host.keys.records[rec].press[1])
		if way == 0:
			kneeboard.toggle()
		elif not open:
			kneeboard.turn(way)
		return true
	if rec >= 0 and int(host.keys.records[rec].press[0]) == 107:
		set_open(not open)
		return true
	if not open:
		if rec >= 0:
			_idle_key(host.keys.records[rec].press)
		return false
	var k := event.keycode
	var n := -1
	if k >= KEY_0 and k <= KEY_9:
		n = k - KEY_0
	elif k >= KEY_KP_0 and k <= KEY_KP_9:
		n = k - KEY_KP_0
	_menu_at = Time.get_ticks_msec()
	if n < 0:
		set_open(false)
	else:
		choose(n)
	return true


## A command of the radio menu's flight pages to `to` (IafAi's: 0 the flight, 5 the element, 2..4 one wingman): the
## pilot's call said with its subtitle ("Kidon 1-2, rejoin"), then IafAi takes it and the wingmen answer (ai_flights.gd
## says their calls). "split" sends element 2 to the SPI (the radar's designated point, else the steerpoint),
## "engage" the jets at the radar's locked enemy aircraft (ai_flights.gd engage_target). Recorded as a `radio` event.
func flight_command(to: int, id: String) -> void:
	var ai = host.get("ai")
	if ai == null or ai.get("flight_ai") == null:
		return
	var r: Node = host.radio
	var addr: String = ADDRESSEES.filter(func(a): return a[0] == to)[0][3]
	var said: Array = (COMMANDS + SHAPES).filter(func(c): return c[0] == id)
	if not said.is_empty():
		r.say("FLT_CMD", [addr, said[0][3]])
	var now: float = host.runtime.now
	var ok: bool
	match id:
		"engage":
			ok = ai.engage_target(to)
		"split":
			ok = ai.flight_ai.split(now, host.world_to_scene(host.weapons.spi()))
		_:
			ok = ai.flight_ai.command(now, to, id)
	host._log_event(host._log_st, {"event": "radio", "call": "%s:%d" % [id, to], "answer": "ok" if ok else "none"})


## One menu pick: the pilot's call printed and said, the gap, the tower's answer (radio.gd request), a `radio` event
## recorded. A ground call whose earlier clearance is missing gets "negative, hold position, request … first"
## (ACFT_NEGATIVE, IafTraining.missing_before) and clears nothing. A call not in the menu now (calls()) is not made: "".
func pick(id: String) -> String:
	if not id in calls():
		return ""
	var r: Node = host.radio
	var cs: String = r.formation_name(r._player_ent())
	var said_cs: String = r.kidon(cs)
	# The tower called: the one in range on the ground (request's), the radio's base in the air (contact_tower's).
	var at: int = r.base if id == "landing" else r.base_at(r._pos())
	var has_tower: bool = at >= 0 and at < r.tower_count
	var lines := ["%s, %s" % [said_cs, CALLS[id][0]], "%s, %s" % [said_cs.replace("Kidon", "כידון"), CALLS[id][1]]]
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
	if p.template == "ACFT_CLEAR_TO_START" and host.ai != null:
		host.ai.flight_cleared_to_start()  # the clearance is the flight's (modern-iaf/docs/ai-plan.md F2)
	if kneeboard != null:
		kneeboard.refresh()  # the start-up lesson's call ticked on the START-UP page
	host._log_event(host._log_st, {"event": "radio", "call": id, "answer": p.template, "text": p.text})
	return String(p.template)


# --- the training run -------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	if not result.is_empty() and Time.get_ticks_msec() >= _end_ms:
		_end_ms = INF
		host._end_flight(true)  # into the debrief (Settings.flown_sortie)
	if open and Time.get_ticks_msec() - _menu_at > MENU_S * 1000.0:
		set_open(false)  # not in use
	_throttle_step()
	_sync_switches()
	if card.update() and kneeboard != null:
		kneeboard.refresh()
	_canopy(delta)
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
			# The tower calls it once ("Kidon 1, taxi without clearance": ACFT_NO_TAXI_CLEARANCE, training.md §3.3); a
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
		ready = ready and _steps().all(func(id): return card.done.has(id))  # every item the lesson asks for ticked
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


## Lined up on runway end `wrong` ("" none), not the mission's: the tower says so once per end ("Kidon 1, you are on
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
	# A pass: the flight pauses under the "accomplished" panel, Continue or Debrief (the user, 2026-11-15: "it pause and
	# show 'continue/debrief' buttons"), once the radio has said what it queued (the pause would cut its voice); a fail
	# shows its reason end_hold_s, then the flight ends into the debrief.
	if d["pass"]:
		var snd = host.get("sounds")
		if snd is Object and snd.has_method("phrase_cue") and snd.get("silenced") != true:
			snd.phrase_cue(_accomplished)
		else:
			_accomplished()
	else:
		_end_ms = Time.get_ticks_msec() + trainer.end_hold_s() * 1000.0
		var why: Array = d.get("reasons", [])
		_show_banner(String(s.get("fail", "")), String(s.get(why[0], why[0])) if not why.is_empty() else "")


# --- the start-up checklist (training.md §7.1) ------------------------------------------------------------------


## A checklist switch (commands 210–215 → STEP_IDS[i]; `want` the command's p1: 1 on, -1 off, 0 (a key) the other
## way): the flight model sets it (IafFlight.start_switch decides its consequence and fault; modern-iaf/docs/cockpit.md
## §5.2); the recording gets a change ("on": false for a switch back off) or a fault; the notebook follows the switches.
## The avionics key turns all eight SYSTEMS on while any is off, and the four off only when all eight are on: after the
## four clicked on, the key once turned them off and never reached the FCR (the user, 17 Nov: "it seems I can't power
## it").
func start_step(i: int, want := 0) -> void:
	if i < 0 or i >= STEP_IDS.size():
		return
	if STEP_IDS[i] == "canopy" and _spider and host.flight != null:
		_canopy_step(want)
		return
	if STEP_IDS[i] == "avionics" and want == 0 and host.flight != null:
		want = 0 if SYSTEMS.all(func(s): return host.flight.start_on(s)) else 1
	_set_switch(STEP_IDS[i], want, STEP_IDS[i])


## One F-16 power switch (command 219, p2 → SYSTEMS[i], `want` as start_step's): an AVIONIC POWER switch's change
## of the avionics step is recorded as the step's.
func system_switch(i: int, want: int) -> void:
	if i >= 0 and i < SYSTEMS.size():
		_set_switch(SYSTEMS[i], want, "avionics")


## Switch `sw` set (IafFlight.start_switch; `want` 2: its in-between position, IN_BETWEEN), its checklist step `id`
## recorded when it changes or faults, with the position of a switch of more than two (the INS knob's, IN_BETWEEN's).
## The switches work after a lesson's pass too: the flight goes on (until 17 Nov they froze there, the FCR unpowerable).
func _set_switch(sw: String, want: int, id: String) -> void:
	if host.flight == null:
		return
	var was: bool = host.flight.start_on(id)
	var pos := _position(sw)
	var fault: String = host.flight.start_switch(IN_BETWEEN.get(sw, sw) if want == 2 else sw, mini(want, 1))
	var on: bool = host.flight.start_on(id)
	var e := {"event": "checklist", "step": id}
	var turned: bool = _position(sw) != pos
	if turned:
		e["position"] = _position(sw)  # the INS knob's 0 OFF .. 5 ATT; IafFlight.start_position's
	if fault != "":
		e["fault"] = fault
		_fault = fault
		_fault_shown = fault
	elif not on:
		e["on"] = false
	if fault != "" or on != was or turned:
		host._log_event(host._log_st, e)
	if on != was and id == "canopy" and host.sounds != null and not _spider:
		# The canopy runs down and locks, or opens (modern-iaf/docs/sound.md §1.7); with a canopy switch: _canopy.
		host.sounds.play("SFX_DOOR_CLOSE" if on else "SFX_DOOR_OPEN")
	_shown.erase(sw)  # shown again from the flight model: a click it refused goes back
	_sync_switches()
	kneeboard.refresh()  # a fault shows on the START-UP page even with no switch changed


## The position of switch `sw` when it has more than two (the INS knob, IN_BETWEEN's), else -9.
func _position(sw: String) -> int:
	if sw == "ins":
		return host.flight.ins_knob()
	return host.flight.start_position(sw) if IN_BETWEEN.has(sw) else -9


## The checklist from the flight model's switches (IafFlight.start_on), each frame: `done`, the notebook, and the 3D
## cockpit's switches that changed (cockpit3d_controls.gd set_switch: a step's by its command 210 + i, a power
## switch's by 219 and its index; the JFS switch springs back to OFF; a cold jet's start off; a refused click back).
func _sync_switches() -> void:
	if host.flight == null:
		return
	var now := []
	for id in STEP_IDS:
		# MAIN PWR's step is done at MAIN PWR, not at BATT (no generators on the buses: the avionics would wait).
		if host.flight.start_on(id) and (id != "main_power" or host.flight.start_position(id) == 2):
			now.append(id)
	var c3d = host.get("cockpit_3d")
	if is_instance_valid(c3d) and c3d.clickable != null:
		for id in STEP_IDS + SYSTEMS:
			var on: bool = id in now if id in STEP_IDS else host.flight.start_on(id)
			if _shown.get(id) != on:
				var i: int = STEP_IDS.find(id)
				c3d.clickable.set_switch(210 + i if i >= 0 else 219, on, SYSTEMS.find(id))
			_shown[id] = on
		# The INS knob at its position (OFF .. ATT; IafFlight.ins_knob), not only on / off.
		var knob: int = host.flight.ins_knob()
		if _shown.get("ins_knob") != knob:
			c3d.clickable.set_switch(214, knob != 0, -1, knob)
			_shown["ins_knob"] = knob
	# The INS step is done at NAV with the alignment finished (the user, 17 Nov: "I also see align on the hud but no idea
	# how to do that"): its switch is on from STOR HDG (the 3D knob above), the step waits for the alignment and NAV.
	var steps := now.filter(func(id): return id != "ins" or ins_ready())
	if steps != done:
		done = steps
		if kneeboard != null:
			kneeboard.refresh()


## The INS ready to navigate: the knob at NAV, the alignment done (IafFlight.ins_status).
func ins_ready() -> bool:
	return host.flight.ins_knob() == INS_NAV and bool(host.flight.ins_status()[2])


## The F-16's canopy switch held at `v` (1 OPEN, -1 CLOSE) or let go (0): cockpit3d_controls.gd "canopy_switch".
func canopy_switch(v: float) -> void:
	_canopy_drive = signf(v)
	_canopy_run = 0  # the hand on the switch ends the key's sequence


## The canopy step on a jet with a canopy switch and a lock lever (cockpit.md §5.6). `want` 0, the Canopy key: the
## whole sequence, the other way from now (locked or closing: the lever up, then the canopy up; else the canopy down,
## then the lever down). 1 / -1, the lever itself: down only over a canopy fully down (else it stays up), up at any
## time on the ground. A click on the lever ends the key's sequence, as a hand on the switch does. In the air the
## lever stays down, by the key too.
func _canopy_step(want: int) -> void:
	var a = host.get("aircraft")
	var locked: bool = host.flight.start_on("canopy")
	if locked and want <= 0 and not bool(host.flight.state().get("on_ground", true)):
		return  # airborne: the lever stays down
	if want == 0:
		_canopy_run = -1 if (locked if _canopy_run == 0 else _canopy_run > 0) else 1
	else:
		_canopy_run = 0
	if want < 0 or (want == 0 and locked):
		_set_switch("canopy", -1, "canopy")
	elif want > 0 and a != null and a.canopy_open <= 0.0:
		_set_switch("canopy", 1, "canopy")


## The canopy (training.md §7.1): up on a cold jet until its step, then down over CANOPY_S; shut on a hot or airborne
## start. The outside model (aircraft_model.gd canopy_open) and the cockpit view's frame turn alike.
func _canopy(delta: float) -> void:
	var a = host.get("aircraft")
	if a == null:
		return
	var c3d = host.get("cockpit_3d")
	if c3d != _spider_c3d:
		_spider_c3d = c3d
		_spider = is_instance_valid(c3d) and c3d.clickable != null and c3d.clickable.has_system("canopy_lock")
	var up := 0.0 if host.start_engine_on or "canopy" in done else 1.0
	if _spider and _canopy_set and host.flight != null:
		# The lever up: the key's sequence or the held switch runs the canopy. Down over an open canopy (the Start engine
		# command takes every step at once): the canopy comes down.
		var dir := -1.0
		if not host.flight.start_on("canopy"):
			dir = float(-_canopy_run) if _canopy_run != 0 else _canopy_drive
		else:
			_canopy_run = 0
		a.canopy_open = clampf(a.canopy_open + dir * delta / CANOPY_S, 0.0, 1.0)
		if (a.canopy_open <= 0.0 and dir < 0.0) or (a.canopy_open >= 1.0 and dir > 0.0):
			dir = 0.0  # at its stop
			if _canopy_run > 0:
				_set_switch("canopy", 1, "canopy")  # the sequence's end: the lever down
			_canopy_run = 0
		if dir != _canopy_dir and host.sounds != null:
			# One door sound per run (sound.md §1.7): short taps of the switch stop it, never stack it.
			if is_instance_valid(_canopy_snd):  # a door sound that finished is freed
				host.sounds.stop(_canopy_snd)
			_canopy_snd = null
			if dir != 0.0:
				_canopy_snd = host.sounds.play("SFX_DOOR_CLOSE" if dir < 0.0 else "SFX_DOOR_OPEN")
		_canopy_dir = dir
	else:
		a.canopy_open = move_toward(a.canopy_open, up, delta / CANOPY_S) if _canopy_set else up
	_canopy_set = true
	var bc = host.get("own_bc")
	if is_instance_valid(bc) and (_frames.is_empty() or c3d != _frames_c3d or bc != _frames_bc):
		_frames_c3d = c3d
		_frames_bc = bc
		_frames.clear()
		for n in ["Canopy", "canopy_frame"]:  # the F-16's cut model, the F-35I's 3D cockpit (tools/f35i/cockpit3d.py)
			var f := bc.find_child(n, true, false) as Node3D
			if f != null:
				_frames[f] = f.transform
	var part = a.parts.get("Canopy", a.parts.get("canopy"))
	if part == null or part.axis == null:
		return
	for f: Node3D in _frames:
		if is_instance_valid(f) and f.name == "canopy_frame" and part.has("hinge") and not f.has_node("CanopyGlass"):
			_canopy_glass(f, part, a.desc.get("eye", []))
	var r := Basis(part.axis, a.canopy_open * a.CANOPY_UP)
	for f: Node3D in _frames:
		if is_instance_valid(f):
			f.transform = Transform3D(r * _frames[f].basis, _frames[f].origin)
			var g := f.get_node_or_null("CanopyGlass") as Node3D
			if g != null:
				g.visible = a.canopy_open > 0.0
			var tips := f.get_node_or_null("canopy_tips") as Node3D
			if tips != null:
				# The F-35I's 3D-cockpit rails end short of the front hinge, shut (tools/f35i/cockpit3d.py
				# RAIL_3D_END); raised, their front ends run on down to the hinge.
				tips.visible = a.canopy_open > 0.0
			if f.has_meta("open_mesh"):  # the F-16's frame off its seat: its skirt folded (aircraft_model.gd)
				var mi := f as MeshInstance3D
				if not mi.has_meta("shut_mesh"):
					mi.set_meta("shut_mesh", mi.mesh)
				mi.mesh = mi.get_meta("open_mesh") if a.canopy_open > 0.0 else mi.get_meta("shut_mesh")


## The F-35I's 3D cockpit has the canopy's rails and bow only: with the canopy up, the lid (its glass, frame and aft
## frame) shows from the seat as a copy of the outside model's canopy part (glass and canopy_frame.glb) in the 3D
## cockpit's frame, the airframe's at the scale about the eye that puts the hinge where the frame node turns
## (tools/f35i/cockpit3d.py PRESENT_SCALE), as `CanopyGlass` under the frame node, shown while the canopy is open.
func _canopy_glass(f: Node3D, part: Dictionary, eye_a: Array) -> void:
	if eye_a.size() < 3:
		return
	var eye := Vector3(eye_a[0], eye_a[1], eye_a[2])
	var hinge: Vector3 = part.hinge
	var at: Vector3 = _frames[f].origin
	var k := (at - eye).length() / (hinge - eye).length()
	var g := (part.node as Node3D).duplicate() as Node3D
	g.name = "CanopyGlass"
	g.visible = false
	# model -> 3D cockpit: p -> eye + (p - eye) k; then into the frame node (its origin `at`, unturned when shut).
	var s := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), eye * (1.0 - k))
	g.transform = Transform3D(Basis.IDENTITY, -at) * s * Transform3D(part.basis, part.origin)
	f.add_child(g)


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
	return checklist.map(func(c): return String(c))


## The pass's pause: the notebook and the radio menu put away, the front end's "accomplished" panel over the frozen
## flight (terrain_view.gd _open_front_end; Continue closes it, Debrief ends the flight into the debrief).
func _accomplished() -> void:
	if not is_inside_tree() or host.ejected or host.crashed:
		return
	if open:
		set_open(false)
	kneeboard.set_raised(false)
	host.close_front_end()  # the pause menu, should it be open
	host._open_front_end("done")


## The banner over the view in the front end's look (navy, Heebo) until the flight ends into the debrief: "Fail" with
## the reason that ended it.
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
