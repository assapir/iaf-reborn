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
const FreeCombat := preload("free_combat.gd")
const Tanker := preload("res://shared/ai/tanker.gd")
const Card := preload("card.gd")
const FlightUi := preload("flight_ui.gd")
const FrameMeter := preload("frame_meter.gd")
## A pass pauses the flight under the front end's "accomplished" panel (training.md §9) once the radio's queued speech
## is said; a fail flies on end_hold_s with nothing over the view, then ends into the debrief.
## The menu's lines: [request id, English, Hebrew] (radio.gd request; "landing": its Ctrl+T contact_tower).
const ITEMS := [
	["startup", "Request start-up", "בקשת התנעה"],
	["taxi", "Request taxi", "בקשת הסעה"],
	["lineup", "Request line-up", "בקשת כניסה למסלול"],
	["takeoff", "Request take-off", "בקשת המראה"],
	["landing", "Contact tower (landing)", "קריאה למגדל (נחיתה)"],
	["radio_check", "Radio check", "בדיקת קשר"],
]
## The first page's lines: id, English, Hebrew (the user, 19 Nov: "1: tower ... 2: wingman's commands ... 3 will be
## AWACS"). AWACS opens the controller's requests (docs/ai.md §24.5).
const TOP := [
	["m:tower", "Tower", "מגדל"],
	["m:wingmen", "Wingmen", "המבנה"],
	["m:awacs", "AWACS", "AWACS"],
	["m:tanker", "Tanker", "מטוס תדלוק"],
]
## The AWACS page's requests: id (radio.gd awacs_request), English, Hebrew; the pilot's words after the address
## ("Eitam, Kidon 1, picture"), English and Hebrew (docs/ai.md §24.2).
const AWACS_ITEMS := [
	["picture", "Picture", "תמונת מצב", "picture", "תמונת מצב"],
	["bogey_dope", "Bogey dope", "המגע הקרוב", "bogey dope", "המגע הקרוב"],
	["declare", "Declare", "זיהוי", "declare", "זיהוי"],
	["vector_target", "Vector to target", "כיוון למטרה", "request vector to target", "בקשת כיוון למטרה"],
	["vector_home", "Vector home", "כיוון לבסיס", "request vector home", "בקשת כיוון לבסיס"],
	["vector_tanker", "Vector to tanker", "כיוון למטוס התדלוק", "request vector to tanker", "בקשת כיוון למטוס התדלוק"],
]
## The tanker's page (only while the flight has a tanker, shared/ai/tanker.gd; the user, 25 Nov 2026: "it should be in
## coms, if available (not for every mission) and ask and get approval to start"): the one call, its words in
## modern-iaf/docs/research/air-refuelling.md §8.4. The address the pilot says by the tanker's kind.
const TANKER_ITEMS := [["tanker:request", "Request refuelling", "בקשת תדלוק"]]
const TANKER_NAMES := {"kc46": ["Gideon", "גדעון", "GIDEON_P"], "reem": ["Re'em", "ראם", "REEM_P"]}
## A page of more lines than the number keys reach shows its first eight and this ninth line, which shows the rest
## (every line has a number key; 0 goes back to the first eight).
const MORE := ["m:more", "More ›", "עוד ‹"]
## The page a `0` goes back to.
const PARENT := {
	"tower": "", "wingmen": "", "awacs": "", "tanker": "", "to": "wingmen", "formation": "to", "spacing": "formation"
}
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
	["sort", "Sort", "חלוקת מטרות", "CMD_SORT", "f"],
	["free", "Weapons free", "אש חופשית", "CMD_FREE", "few"],
	["low", "Low level", "גובה נמוך", "CMD_LOW", "f"],
	["high", "Back to altitude", "חזרה לגובה", "CMD_HIGH", "f"],
	["cover", "Cover me", "חיפוי", "CMD_COVER", "few"],
	["refuel", "Refuel", "תדלוק", "CMD_REFUEL", "few"],
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
## The shapes' page's last line opens the spacing page: close up / spread out, one step each (IafAi's command;
## docs/ai.md §8.7; the words of modern-iaf/docs/research/radio-terms.md).
const SPACING_PAGE := ["m:spacing", "Spacing ›", "מרווחים ‹"]
const SPACING := [
	["close_up", "Close up", "מבנה צמוד", "CMD_CLOSE_UP"],
	["spread_out", "Spread out", "להגדיל מרווחים", "CMD_SPREAD_OUT"],
]
## The pilot's call, printed in the game's language and said by the pilot's voice (radio.gd PILOT_CALL: the address,
## the callsign, REQ_<ID>; modern-iaf/docs/sound.md §5.2).
const CALLS := {
	"startup": ["request start-up", "בקשת התנעה"],
	"taxi": ["request taxi", "בקשת הסעה"],
	"lineup": ["request line-up", "בקשת כניסה למסלול"],
	"takeoff": ["ready for take-off", "בקשת המראה"],
	"landing": ["request landing", "בקשת נחיתה"],
	"radio_check": ["radio check", "בדיקת קשר"],
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
## The radio menu closes by itself this long after it opened or after its last key, s (the user, 2026-11-15: "the
## radio menu should disappear after few seconds if not in use"; the original game has no such menu: inferred).
const MENU_S := 6.0
## A take-off is scored once airborne (every 3 s until it passes), a start-up once the engine idles with the avionics
## up; either this long past its time budget. A pass is kept and the flight goes on. The run's state (when it is
## scored, its fail, 3 failed scores in a row ending it, the hold before the debrief) is IafTraining's run
## (crates/iaf-tools/src/training.rs Run).
# ponytail: each score re-reads the whole recording (O(length)); a scorer fed sample by sample if it shows.
const PAST_BUDGET := 5.0
## A take-off's fail reasons no later flying can mend: the mission ends on them once airborne.
const FINAL := ["wrong_runway", "excursion", "over_time"]

var host: Node
var open := false
var _menu_at := 0  # the radio menu's opening or last key (ms): MENU_S later it closes
## The menu's page: "" the first (Tower, Wingmen, AWACS), "tower" the tower's calls, "awacs" the AWACS's requests,
## "wingmen" the flight's
## addressees, "to" an addressee's commands (`_to`), "formation" the flight's shapes, "spacing" close up / spread out.
var page := ""
var _to := 0
var _rest := false  # the page's lines after its first eight (MORE)
## The menu's calls as shown (ids), and the tower's answers so far (templates; approvals for IafTraining.radio_calls).
var shown: Array = []
var answers := PackedStringArray()
var _hold_m := {}  # iaf.ibx section -> its holding point's distance to the lineup point (m), once read
## The text over the flight: the band of radio lines, the panel, the key hint (flight_ui.gd).
var ui: Control
var _sim := {}
## The flight's tanker from its mission ({kind: kc46 / reem, anchor: [x, y] world m, the inbound leg's start, course:
## deg}; modern-iaf/docs/research/air-refuelling.md §8.1), or `--tanker kc46|reem` (a developer's hook: its track
## starts 5 km ahead of the jet on its heading); placed once the ground is in. {} none.
var _tanker_spec := {}
var _tanker_tried := false
## The training mission: its readable file's name (res://data/missions/<name>.json) and rules; {} for a flight without.
var mission_name := ""
var rules := {}
## The jet the mission flies (its readable file's start.unit: f16i, f16d, f35i), stored with the sortie.
var plane := ""
## The debrief record once scored ({} before), and its sortie in the records database (0 before). Set from outside
## (tests): the run counts as scored, no hold.
var result: Dictionary:
	get:
		return _result
	set(d):
		_result = d
		if trainer != null and not d.is_empty():
			trainer.run_finish(bool(d.get("pass", false)), INF)
var _result := {}
var sortie := 0
## Tests: where the records database and (isolated) the recording go; "" = Settings.records_dir().
var out_dir := ""
## The training run's IafTraining (its live check, its run and scorer; null without rules) and the run's fail reason
## ("" while none).
var trainer: RefCounted
var _why: String:
	get:
		return String(trainer.run_why()) if trainer != null else ""
	set(v):
		if trainer != null:
			trainer.run_fail(v)
## The runway ends not the mission's the tower named already.
var _wrong_said: Array = []
## When the flight ends into the debrief (s, sim time: a pause or the time compression holds it), once the mission
## failed; score() failures in a row.
var _end_at: float:
	get:
		return trainer.run_end_at() if trainer != null else INF
var _score_fails: int:
	get:
		return trainer.run_fails() if trainer != null else 0
## A start-up lesson's items of the jet's card it asks for (the readable mission's training.checklist: card item ids,
## training.md §12), the flight model's start-up steps whose switches are on (ids: IafFlight.start_on, read each
## frame), a step's fault waiting for the live check, the last fault shown, the jet's checklist card (card.gd) and
## the pilot's notebook (kneeboard.gd: its CHECKLIST page shows the card; training.md §11).
var checklist: Array = []
var card: Node
## The air refuelling checklist (card.gd on the card file's "refuel" sections): run and shown on the notebook's
## AIR REFUEL tab only while the flight has a tanker (training.md §11).
var refuel_card: Node
var _had_tanker := false
var done: Array = []
var _fault := ""
var _fault_shown := ""
var kneeboard: Node
## The mission's failures still to plan on the flight (its readable file's `failures`, training.md §15), and the
## failures already announced (master caution and the voice once each).
var _failures_plan: Array = []
var _failures_seen: Array = []
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
## The engine step has no key: the throttle moved up from OFF is it, as the real idle-cutoff detent (training.md
## §7.1). The briefing names the Throttle idle key (record 7, the 1 key); OFF is the throttle's bottom, a lever's noise
## allowed.
const THROTTLE_OFF := 0.02
## The throttle last frame (-1 before the first: a lever already up at the start is no step).
var _throttle_was := -1.0
## The 3D cockpit's start-up switches as last set from the flight model (_sync_switches): step id -> on.
var _shown := {}
## The canopy is the flight model's (iaf-flight start.rs `Canopy`: its travel, the switch, the lock lever, the key's
## sequence), run on this add-on's frame time; this add-on draws it. Drawn once; the opening last drawn (another hand's
## change goes to the flight model). CANOPY_S: the travel, open to shut (s), without a flight model.
const CANOPY_S := 10.0
var _canopy_set := false
var _canopy_drawn := 0.0
## A jet with a canopy switch and a lock lever (the F-16s' 3D cockpit; cockpit.md §5.6), and the cockpit it was read
## from; the canopy's run last frame (-1 down, 0 stopped, 1 up) and its lever down.
var _spider := false
var _spider_c3d: Node = null
var _canopy_dir := 0.0
var _canopy_locked := false
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
		_tanker_spec = readable.get("tanker", {})
		_failures_plan = readable.get("failures", [])
		if String(readable.get("category", "")) == "fly_now":
			add_child(FreeCombat.new(host, host.radio.runway_base))  # Scramble's enemy and task (front-end.md §2.1)
	if not rules.is_empty():
		trainer = ClassDB.instantiate("IafTraining")
		var err: String = trainer.open(_readable(), Settings.disk_path("res://data/airbases"))
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
	refuel_card = Card.new(self, plane, "refuel")
	add_child(refuel_card)
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
		var e: Vector3 = r.entry_of(at)  # the runway's entry: the line-up call is made at its holding point
		var l := Vector2(e.x, e.y)
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
	if page == "awacs":
		return _bi(ui.s("fl_radio_to") % TOP[2][2 if he else 1])
	if page == "tanker":
		return _bi(ui.s("fl_radio_to") % _tanker_name(1 if he else 0))
	var a: Array = ADDRESSEES.filter(func(x): return x[0] == _to)[0]
	var who: String = a[2 if he else 1]
	if page == "to":
		return _bi(ui.s("fl_radio_to") % who)
	var what: String = (
		(SPACING_PAGE if page == "spacing" else COMMANDS[0])[2 if he else 1].trim_suffix(" ›").trim_suffix(" ‹")
	)
	return _bi(ui.s("fl_radio_to") % ("%s, %s" % [who, what]))


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
			TOP
			+ TANKER_ITEMS
			+ ITEMS
			+ AWACS_ITEMS
			+ ADDRESSEES.map(func(a): return ["to:%d" % a[0], a[1] + " ›", a[2] + " ‹"])
			+ COMMANDS
			+ SHAPES
			+ [SPACING_PAGE]
			+ SPACING
			+ [MORE]
		):
			if it[0] == shown[i]:
				lines.append(_bi("%d. %s" % [i + 1, it[lang]]))
				break
	if page != "":
		lines.append("0. %s" % ui.s("fl_radio_back"))
	return lines


## The lines shown off (index in `shown` -> true), dimmed and clickable no more: the AWACS's requests that cannot be
## made now (radio.gd awacs_refusal: the Eitam lost, no radar lock, no tanker, no home base). No reason line: the game
## manual says when each is off (the user, 25 Nov 2026: "no need to write why something is disabled").
func _off() -> Dictionary:
	var off := {}
	if page == "awacs":
		for i in shown.size():
			if host.radio.awacs_refusal(String(shown[i])) != "":
				off[i] = true
	return off


## The entries of the page now (ids): Tower, Wingmen, AWACS; the tower's calls; the flight's addressees with an AI jet
## alive (the four-ship, IafAi); an addressee's commands; the shapes.
func _entries() -> Array:
	if page == "":
		return TOP.map(func(x): return x[0]).filter(func(id): return id != "m:tanker" or _tanker() != null)
	if page == "tanker":
		return TANKER_ITEMS.map(func(x): return x[0])
	if page == "formation":
		return SHAPES.map(func(x): return x[0]) + [SPACING_PAGE[0]]
	if page == "spacing":
		return SPACING.map(func(x): return x[0])
	if page == "awacs":
		return AWACS_ITEMS.map(func(x): return x[0])
	if page == "to":
		var kind := "f" if _to == 0 else ("e" if _to == 5 else "w")
		var with_tanker := _tanker() != null  # "refuel" only while the flight has a tanker
		return (
			COMMANDS
			. filter(func(c): return kind in c[4] and (c[0] != "refuel" or with_tanker))
			. map(func(c): return c[0])
		)
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


## The panel in the new language: the open menu now.
func _language_changed() -> void:
	if open:
		_show()


func set_open(on: bool) -> void:
	open = on
	page = ""
	_rest = false
	_menu_at = Time.get_ticks_msec()
	_show()


## The menu's page now in the panel, each line clickable (`choose`), or the panel cleared when closed.
func _show() -> void:
	shown = _entries() if open else []
	if shown.size() > 9:
		shown = shown.slice(8) if _rest else shown.slice(0, 8) + [MORE[0]]
	if open:
		ui.show_menu(_title(), _lines(), _clicked, _off())
	else:
		ui.hide_panel()


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
		if _rest:
			_rest = false
		else:
			page = PARENT[page]
		_show()
	elif id == MORE[0]:
		_rest = true
		_show()
	elif id.begins_with("m:"):
		page = id.substr(2)
		_rest = false
		_show()
	elif id.begins_with("to:"):
		_to = int(id.substr(3))
		page = "to"
		_rest = false
		_show()
	elif id == "formation":
		page = "formation"
		_rest = false
		_show()
	elif page == "tower":
		set_open(false)
		pick(id)
	elif page == "awacs":
		if host.radio.awacs_refusal(id) == "":  # off: dimmed, no pick
			set_open(false)
			awacs_pick(id)
	elif page == "tanker":
		set_open(false)
		if id == "tanker:request":
			request_refuelling()
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
## "engage" the jets at the radar's locked enemy aircraft, else at the player's ground target, which they attack one
## after the other (ai_flights.gd engage_target, docs/ai.md §8.10), "sort" shares the bandits out between the jets,
## "free" sends the jets hunting round the SPI (docs/ai.md §8.11), "low" / "high" set and end the flight's low level
## (docs/ai.md §20; the key's "low_level" is the one of the two not in force). Recorded as a `radio` event.
func flight_command(to: int, id: String) -> void:
	var ai = host.get("ai")
	if ai == null or ai.get("flight_ai") == null:
		return
	if id == "low_level":
		id = "high" if ai.flight_ai.is_low() else "low"
	var r: Node = host.radio
	var addr: String = ADDRESSEES.filter(func(a): return a[0] == to)[0][3]
	var said: Array = (COMMANDS + SHAPES + SPACING).filter(func(c): return c[0] == id)
	if not said.is_empty():
		r.say("FLT_CMD", [addr, said[0][3]])
	var now: float = host.runtime.now
	var ok: bool
	match id:
		"engage":
			ok = ai.engage_target(to)
		"split":
			# No SPI: a point at infinity, outside the same area, so element 2 answers "unable".
			var spi = host.weapons.spi()
			ok = ai.flight_ai.split(now, host.world_to_scene(spi) if spi != null else Vector3.INF)
		"sort":
			ok = ai.flight_ai.sort(now)
		"free":
			# No SPI: the hunt is round the lead itself.
			var at = host.weapons.spi()
			ok = ai.flight_ai.weapons_free(now, to, host.world_to_scene(at if at != null else host.player_world())) >= 0
		_:
			ok = ai.flight_ai.command(now, to, id)
	host._log_event(host._log_st, {"event": "radio", "call": "%s:%d" % [id, to], "answer": "ok" if ok else "none"})


## One AWACS request `id` (docs/ai.md §24.2): the pilot's call printed in both languages and said ("Eitam, Kidon 1,
## picture"), then the controller's answer (radio.gd awacs_request); a `radio` event recorded. The answer's lines.
func awacs_pick(id: String) -> Array:
	var r: Node = host.radio
	var it: Array = AWACS_ITEMS.filter(func(x): return x[0] == id)[0]
	var said_cs: String = r.kidon(r.formation_name(r._player_ent()))
	var lines := ["Eitam, %s, %s" % [said_cs, it[3]], "עיטם, %s, %s" % [said_cs.replace("Kidon", "כידון"), it[4]]]
	r.bilingual(lines[0], lines[1])
	var out: Array = r.awacs_request(id, lines[1 if _he() else 0])
	var answer := " ".join(out.map(func(p): return String(p.text)))
	host._log_event(host._log_st, {"event": "radio", "call": "awacs:" + id, "answer": answer})
	return out


## The mission's tanker (or the `--tanker` hook's) placed once the jet flies over loaded ground.
func _place_tanker() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--tanker")
	if _tanker_spec.is_empty() and not _tanker_tried and at >= 0 and at + 1 < args.size():
		var w: Vector3 = host.player_world() if host.get("flight") != null else Vector3.ZERO
		var h := deg_to_rad(float(host.flight.state().get("heading", 0.0))) if host.get("flight") != null else 0.0
		_tanker_spec = {
			"kind": args[at + 1], "anchor": [w.x + 5000.0 * sin(h), w.y + 5000.0 * cos(h)], "course": rad_to_deg(h)
		}
	if _tanker_tried or _tanker_spec.is_empty() or host.get("flight") == null or host.waiting_for_ground:
		return
	_tanker_tried = true
	if _tanker() != null:
		return  # Scramble's draw placed one
	var a: Array = _tanker_spec.get("anchor", [0.0, 0.0])
	var kind := String(_tanker_spec.get("kind", "kc46"))
	if Tanker.place(host, kind, Vector3(a[0], a[1], 0.0), float(_tanker_spec.get("course", 0))) == null:
		push_warning("tanker: no tanker of kind %s" % kind)


## The flight's tanker (shared/ai/tanker.gd), null when it has none.
func _tanker() -> Node:
	return host.get("tanker")


## The tanker's callsign in `lang` (0 English, 1 Hebrew).
func _tanker_name(lang: int) -> String:
	var t := _tanker()
	return TANKER_NAMES.get(String(t.kind) if t != null else "kc46", TANKER_NAMES.kc46)[lang]


## The Tanker page's call (research §8.3): "Gideon, Kidon 1, request refuelling", the gap, and the tanker's answer
## (cleared pre-contact, or stand by with another jet on the boom); recorded as a `radio` event.
func request_refuelling() -> void:
	var t := _tanker()
	if t == null:
		return
	var r: Node = host.radio
	var cs: String = r.formation_name(r._player_ent())
	var said_cs: String = r.kidon(cs)
	var lines := [
		"%s, %s, %s" % [_tanker_name(0), said_cs, TANKER_ITEMS[0][1].to_lower()],
		"%s, %s, %s" % [_tanker_name(1), said_cs.replace("Kidon", "כידון"), TANKER_ITEMS[0][2]]
	]
	r.bilingual(lines[0], lines[1])
	var addr: String = TANKER_NAMES.get(String(t.kind), TANKER_NAMES.kc46)[2]
	r.say("PILOT_CALL", [addr, cs + "_P", "REQ_REFUEL"], [], false, lines[1 if _he() else 0])
	r.play_wav("radio_gap.ogg")
	t.request(t._player_id())
	host._log_event(host._log_st, {"event": "radio", "call": "tanker", "answer": "request"})


## The runway end the tower names for the mission's runway ("25R"; its other end when the tower turned the base into
## the wind: radio.gd runway_of, docs/autopilot.md §2.4); "" when the mission names none.
func runway_in_use() -> String:
	var r: Node = host.radio
	if r.runway == "":
		return ""
	for i in r.bases.size():
		if r.bases[i].name == r.runway_base:
			return str(r.runway_of(i))
	return r.runway


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
		r.readback("ACFT_HOLD_POS")  # "Holding, Kidon 1"
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
	if float(host._sim_time) >= _end_at:
		trainer.run_ended()
		host._end_flight(true)  # into the debrief (Settings.flown_sortie)
	if open and Time.get_ticks_msec() - _menu_at > MENU_S * 1000.0:
		set_open(false)  # not in use
	_throttle_step()
	_sync_switches()
	_place_tanker()
	var changed: bool = card.update()
	var tanker: bool = host.tanker != null
	changed = (tanker and refuel_card.update()) or changed or tanker != _had_tanker
	_had_tanker = tanker
	if changed and kneeboard != null:
		kneeboard.refresh()
	_canopy(delta)
	_failures()
	if rules.is_empty() or trainer.run_finished() or host.flight == null or host.get("_log") == null:
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
	var budget := float(rules.get("time_budget_s", 900.0))
	var ready := false
	if String(rules.get("kind", "")) == "startup":
		ready = bool(st.get("engine_on", false)) and bool(st.get("avionics", false))
		ready = ready and _steps().all(func(id): return card.done.has(id))  # every item the lesson asks for ticked
	elif String(rules.get("kind", "")) == "lesson":
		ready = true  # a course lesson: scored every 3 s, its end read from the recording (training.md §16.2)
	else:
		ready = not bool(st.on_ground)  # airborne: scored with the gear up or down, so a missing goal shows
	# Scored every 3 s once ready (or past the budget) and the recorder has written a sample of it (10 a second).
	if not trainer.run_tick(t, ready or t > budget + PAST_BUDGET):
		return
	var d := score()
	if d.has("error"):
		_score_failed(d)
		return
	trainer.run_scored()
	# A pass holds; a take-off not yet on its heading or with the gear down may still pass: scored again until its
	# budget (no line over the flight says what is missing: the user, 25 Nov 2026, only radio over the flight; the
	# debrief does). A roll off the runway or past the budget cannot pass: it ends.
	var why: Array = d.get("reasons", [])
	if bool(d.get("pass", false)):
		_finish(d)  # a pass stays: the flight goes on until the player ends it
	elif t > budget + PAST_BUDGET or String(rules.kind) == "startup" or why.any(func(r): return r in FINAL):
		_finish(d)


## A lesson's failure started now (the dev hook; IafFlight.start_failure's names): "" or why not.
func start_failure(id: String) -> String:
	return String(host.flight.start_failure(id)) if host.flight != null else "no_flight"


## The mission's failures planned once the flight exists, and each failure's start announced as the jet does it: the
## MASTER CAUTION and the voice's "Warning" (a warning light) or "Caution", and a `failure` event in the recording.
func _failures() -> void:
	if host.flight == null or not host.flight.has_method("failures"):
		return
	for f in _failures_plan:
		var e := String(
			host.flight.plan_failure(String(f.get("id", "")), String(f.get("on", "time")), float(f.get("value", 0.0)))
		)
		if e != "":
			push_warning("failure %s: %s" % [f, e])
	_failures_plan = []
	var d: Dictionary = host.flight.failures()
	var warnings: PackedStringArray = d.get("warnings", PackedStringArray())
	for id in d.get("active", PackedStringArray()):
		if _failures_seen.has(id):
			continue
		_failures_seen.append(id)
		host.damage_light(0, true)
		host.damage_sound("VOC_BBETTY", "BTY_FIRE" if warnings.has(id) else "BTY_CAUTION")
		host._log_event(host.get("_log_st") if host.get("_log_st") != null else {}, {"event": "failure", "failure": id})


## Lined up on runway end `wrong` ("" none), not the mission's: the tower says so once per end ("Kidon 1, you are on
## runway 7 left, the assigned runway is 25 right": ACFT_WRONG_RUNWAY, training.md §3.3); the roll on it fails
## (IafTraining.check "wrong_runway").
func _wrong_runway(wrong: String) -> void:
	if wrong != "" and not wrong in _wrong_said:
		_wrong_said.append(wrong)
		host.radio.say("ACFT_WRONG_RUNWAY", [host.radio._tower_callsign()], [wrong, String(trainer.runway())])


## The mission ends now: scored and finished (retried every 3 s if it cannot be scored; `now`: at once).
func _end_now(t: float, now := false) -> void:
	if not trainer.run_due(t, now):
		return
	var d := score()
	if d.has("error"):
		_score_failed(d)
	else:
		_finish(d)


## score() failed (`d.error`): after 3 in a row the run ends, failed, its debrief saying it could not be scored
## (reason "no_score", the front end's string), so a run never flies on with no word.
func _score_failed(d: Dictionary) -> void:
	push_warning("training: %s" % d.error)
	if trainer.run_score_failed():
		_finish(
			{"pass": false, "reasons": ["no_score"], "kind": String(rules.get("kind", "")), "error": String(d.error)}
		)


## The player ended the flight before the mission's end: scored as it stands.
func _exit_tree() -> void:
	if not rules.is_empty() and not trainer.run_finished() and host.get("_log") != null:
		_end_now(0.0, true)


func _readable() -> String:
	return Settings.disk_path("res://data/missions/%s.json" % mission_name)


## The recording so far against the mission's rules (IafTraining, the readable mission and the airbases of
## modern-iaf/data).
func score() -> Dictionary:
	if host.get("weapons") != null:
		host.weapons.flush_burst()  # a burst still firing: its rounds counted so far (the combat logbook)
	host._log.flush()
	var flight: String = ProjectSettings.globalize_path(host._log.get_path_absolute())
	var d = JSON.parse_string(trainer.score(flight, _readable(), Settings.disk_path("res://data/airbases")))
	return d if d is Dictionary else {"error": "no debrief"}


func _finish(d: Dictionary) -> void:
	_result = d
	trainer.run_finish(bool(d["pass"]), INF if d["pass"] else float(host._sim_time) + trainer.end_hold_s())
	d["flight"] = ProjectSettings.globalize_path(host._log.get_path_absolute())
	d["date"] = Time.get_datetime_string_from_system()
	d["elapsed_s"] = snappedf(float(host._log_t), 0.1)
	d["plane"] = plane
	var db: String = Settings.records_db() if out_dir == "" else _dir().path_join("modern-iaf.sqlite")
	sortie = IafPilotLog.log_sortie(db, Settings.pilot(), int(host.mission_id), JSON.stringify(d))
	Settings.flown_sortie = sortie
	print("training %s: %s %s" % [mission_name, "PASS" if d["pass"] else "FAIL", d.get("reasons", [])])
	host._log_event(host._log_st, {"event": "mission", "name": "training " + ("pass" if d["pass"] else "fail")})
	# A pass: the flight pauses under the "accomplished" panel, Continue or Debrief (the user, 2026-11-15: "it pause and
	# show 'continue/debrief' buttons"), once the radio has said what it queued (the pause would cut its voice); a fail
	# flies on end_hold_s (the radio's last line said), with nothing over the view (the user, 25 Nov 2026: only radio
	# over the flight), then ends into the debrief, which names the reason.
	if d["pass"]:
		var snd = host.get("sounds")
		if snd is Object and snd.has_method("phrase_cue") and snd.get("silenced") != true:
			snd.phrase_cue(_accomplished)
		else:
			_accomplished()
	else:
		set_open(false)


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
	if STEP_IDS[i] == "canopy":
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
	if id == "canopy":
		_canopy_locked = on  # recorded here, not again by _canopy
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
	if host.flight != null:
		_canopy_pull()
		host.flight.canopy_switch(int(signf(v)))


## The canopy step (command 215; iaf-flight start.rs `canopy_set`): with the F-16's lock lever `want` 0, the Canopy key,
## runs the whole sequence, 1 / -1 the lever itself; else the one CANOPY switch.
func _canopy_step(want: int) -> void:
	_canopy_pull()
	_set_switch("canopy", want, "canopy")


## The drawn canopy put somewhere by another hand (a test, a picture's helper): the flight model takes it.
func _canopy_pull() -> void:
	var a = host.get("aircraft")
	if a != null and _canopy_set and host.flight != null and a.canopy_open != _canopy_drawn:
		host.flight.set_canopy_open(a.canopy_open)
		_canopy_drawn = a.canopy_open


## The canopy (training.md §7.1), the flight model's travel drawn: the outside model (aircraft_model.gd canopy_open)
## and the cockpit view's frame turn alike. With the lock lever: one door sound per run, and the lever down at the end
## of a run recorded as the step.
func _canopy(delta: float) -> void:
	var a = host.get("aircraft")
	if a == null:
		return
	var c3d = host.get("cockpit_3d")
	if c3d != _spider_c3d:
		_spider_c3d = c3d
		_spider = is_instance_valid(c3d) and c3d.clickable != null and c3d.clickable.has_system("canopy_lock")
	if host.flight != null:
		# Each frame (a new start's flight model has them too); flags only, the travel stays the flight model's.
		host.flight.set_canopy_lever(_spider, bool(host.start_engine_on))
		_canopy_pull()
		var lifted: bool = host.flight.canopy_tick(delta if _canopy_set else 0.0)
		var c: Array = host.flight.canopy()
		a.canopy_open = float(c[0])
		_canopy_drawn = a.canopy_open
		var dir := float(c[1])
		var locked: bool = host.flight.start_on("canopy")
		if lifted:
			# The whole sequence over an open canopy (the Start engine command): recorded as the lever up, as before
			# the canopy moved into the flight model.
			host._log_event(host._log_st, {"event": "checklist", "step": "canopy", "on": false})
		if _spider and locked and not _canopy_locked and _canopy_dir < 0.0:
			host._log_event(host._log_st, {"event": "checklist", "step": "canopy"})  # the sequence's end: locked
		_canopy_locked = locked
		if _spider and dir != _canopy_dir and host.sounds != null:
			# One door sound per run (sound.md §1.7): short taps of the switch stop it, never stack it.
			if is_instance_valid(_canopy_snd):  # a door sound that finished is freed
				host.sounds.stop(_canopy_snd)
			_canopy_snd = null
			if dir != 0.0:
				_canopy_snd = host.sounds.play("SFX_DOOR_CLOSE" if dir < 0.0 else "SFX_DOOR_OPEN")
		_canopy_dir = dir
	else:
		var up := 0.0 if host.start_engine_on else 1.0
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
	var r := Basis(part.axis, a.canopy_open * a.canopy_up)
	for f: Node3D in _frames:
		if is_instance_valid(f):
			f.transform = Transform3D(r * _frames[f].basis, _frames[f].origin)
			var g := f.get_node_or_null("CanopyGlass") as Node3D
			if g != null:
				g.visible = a.canopy_open > 0.0
				var over := g.get_node_or_null("FrameOverGlass") as MeshInstance3D
				if over != null and g.visible:  # the frame's lighting (cockpit3d.gd _night_mats' emission) followed
					for i in over.mesh.get_surface_count():
						var m := over.get_surface_override_material(i) as BaseMaterial3D
						var src := (f as MeshInstance3D).get_active_material(i) as BaseMaterial3D
						if m != null and src != null:
							m.emission = src.emission
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


## The F-35I's 3D cockpit has the canopy's rails and bow only: with the canopy up, the lid (its glass and frame, the
## outside bow left out) shows from the seat as a copy of the outside model's canopy part (glass and canopy_frame.glb)
## in the 3D cockpit's frame, the airframe's at the scale about the eye that puts the hinge where the frame node turns
## (tools/f35i/cockpit3d.py PRESENT_SCALE), as `CanopyGlass` under the frame node, shown while the canopy is open; with
## it `FrameOverGlass`, the frame node's rails and bow drawn again after the glass.
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
	# The bow from the seat is the 3D cockpit's own (canopy_arch, on the frame node): the copy's (canopy_bow_ext) sat
	# lower and drew a second arch coming down onto it as the canopy closed (docs/f35i.md §4.1 "Canopy", 2026-11-25).
	# It covers the slot between the glass's two sheets, so it stays, as glass: left out, the slot showed the sky
	# untinted, a bright arch under the dark one (the user, Approvals A88, 2026-11-25). From the seat the slot shows
	# wider than the bar (it lies 1 cm under the glass's face), so the bar is widened (_slot_bar); a stencil keeps the
	# tint single: the glass marks its pixels and the bar tints only the others.
	var bow := g.find_child("canopy_bow_ext", true, false) as MeshInstance3D
	var glass := _glass_material(g)
	if bow != null and not _glass_marks(g):
		bow.free()
	elif bow != null:
		var m := _one_sheet(glass)
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.render_priority = 1  # after the glass
		m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ | BaseMaterial3D.STENCIL_FLAG_WRITE
		m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
		m.stencil_reference = 1
		bow.mesh = _slot_bar(bow.mesh)
		for i in bow.mesh.get_surface_count():
			bow.set_surface_override_material(i, m)
	# model -> 3D cockpit: p -> eye + (p - eye) k; then into the frame node (its origin `at`, unturned when shut).
	var s := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), eye * (1.0 - k))
	g.transform = Transform3D(Basis.IDENTITY, -at) * s * Transform3D(part.basis, part.origin)
	f.add_child(g)
	# The 3D cockpit's arch stands outside the copy's glass (its top 0.16 m over it, for the head clearance:
	# tools/f35i/cockpit3d.py ARCH_TOP), so the glass tinted it as it rose. With the copy, the frame (rails, arch) is drawn
	# once more after the glass, at its own depth: seen untinted, as a bow inside the glass. No shadow: the frame casts it.
	var mi := f as MeshInstance3D
	if mi != null and mi.mesh != null:
		var over := MeshInstance3D.new()
		over.name = "FrameOverGlass"
		over.mesh = mi.mesh
		over.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
			if m != null:
				m = m.duplicate() as BaseMaterial3D
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.render_priority = 1
				over.set_surface_override_material(i, m)
		over.transform = g.transform.affine_inverse()
		g.add_child(over)


## The bow's arch in the canopy's frame (tools/f35i/canopy_frame.py: SEAM_FOOT, SEAM_TOP, AXIS_Z; Blender's +y nose is
## the glTF's -z): at the angle a from the top about the axis, its middle stands SEAM_FOOT + (SEAM_TOP - SEAM_FOOT)
## cos a ahead. SLOT_BAR: the slot bar's width as a share of the bow's 7 cm (21 cm: the slot from the seat, inferred
## from the pictures).
const SEAM_FOOT := 0.13
const SEAM_TOP := 0.29
const SEAM_AXIS := -0.15
const SLOT_BAR := 3.0


## The bow's mesh widened fore and aft about its middle line by SLOT_BAR: one bar, so no two layers meet in it.
static func _slot_bar(mesh: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for j in v.size():
			var mid := -(SEAM_FOOT + (SEAM_TOP - SEAM_FOOT) * cos(atan2(v[j].x, v[j].y - SEAM_AXIS)))
			v[j].z = mid + (v[j].z - mid) * SLOT_BAR
		a[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


## The canopy glass's material in `n` (the surface named canopy_glass), null without one.
static func _glass_material(n: Node) -> BaseMaterial3D:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and m.resource_name == "canopy_glass":
				return m
	return null


## The glass's material for one of its two sheets (`_one_sheet_mesh`), tinting as both do.
static func _one_sheet(glass: BaseMaterial3D) -> BaseMaterial3D:
	var m := glass.duplicate() as BaseMaterial3D
	m.albedo_color.a = 1.0 - pow(1.0 - m.albedo_color.a, 2.0)
	return m


## The copy's glass marks its pixels in the stencil (reference 1) for the slot's bars; false without glass.
static func _glass_marks(n: Node) -> bool:
	var found := false
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "canopy_bow_ext":
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and m.resource_name == "canopy_glass":
				# One sheet, at both sheets' tint: the two sheets' edges, seen apart from the seat, left a one-sheet
				# hairline at each edge of the slot (2026-11-25).
				mi.mesh = _one_sheet_mesh(mi.mesh, i)
				m = _one_sheet(m)
				m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
				m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
				m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
				m.stencil_reference = 1
				mi.set_surface_override_material(i, m)
				found = true
	return found


## The download's glass is two sheets 1.4 cm apart, joined at their rims, both facing out, each side a mirror copy of
## the other whose outer sheet's strips over the seam reach past it (the seam and the sheet beside it covered twice).
## The copy from the seat keeps the outer sheet alone without those strips, each side's edge at the seam moved onto it
## (corners under SEAM_SNAP from x = 0). A triangle with another one of the glass more than SHEET_OVERLAP and less than
## SHEET_GAP farther on the ray from SHEET_FROM (a point under the glass in its mesh's frame) is on the inner sheet;
## one seen edge-on from there (|cos| under SHEET_RIM) is a rim. SHEET_BIN: the bins (of the rays' unit direction's x
## and z) the triangles are found in.
const SHEET_GAP := 0.1
const SHEET_OVERLAP := 0.002
const SHEET_FROM := Vector3(0.0, -0.6, 0.0)
const SHEET_RIM := 0.25
const SHEET_BIN := 0.03
const SEAM_SNAP := 0.02


## `mesh` with surface `s`'s outer sheet alone, closed at the seam.
static func _one_sheet_mesh(mesh: Mesh, s: int) -> ArrayMesh:
	var a := mesh.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var bin := func(p: Vector3) -> Vector2i:
		var d := (p - SHEET_FROM).normalized()
		return Vector2i(floori(d.x / SHEET_BIN), floori(d.z / SHEET_BIN))
	var bins := {}
	for t in idx.size() / 3:
		var b0: Vector2i = bin.call(v[idx[t * 3]])
		var b1 := b0
		for k in [1, 2]:
			var b: Vector2i = bin.call(v[idx[t * 3 + k]])
			b0 = b0.min(b)
			b1 = b1.max(b)
		for x in range(b0.x, b1.x + 1):
			for z in range(b0.y, b1.y + 1):
				if not bins.has(Vector2i(x, z)):
					bins[Vector2i(x, z)] = []
				bins[Vector2i(x, z)].append(t)
	var keep := PackedInt32Array()
	var moved := v.duplicate()
	for t in idx.size() / 3:
		var tri := [v[idx[t * 3]], v[idx[t * 3 + 1]], v[idx[t * 3 + 2]]]
		var xs: Array = tri.map(func(p: Vector3) -> float: return p.x)
		if xs.min() < 0.0 and xs.max() > 0.0:
			continue  # a strip over the seam
		var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		var dist := SHEET_FROM.distance_to(c)
		var dir := (c - SHEET_FROM) / dist
		var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		var drop := absf(n.dot(dir)) < SHEET_RIM
		for o: int in [] if drop else bins.get(bin.call(c), []):
			var h = Geometry3D.ray_intersects_triangle(
				SHEET_FROM, dir, v[idx[o * 3]], v[idx[o * 3 + 1]], v[idx[o * 3 + 2]]
			)
			if o != t and h != null:
				var e := SHEET_FROM.distance_to(h) - dist
				drop = e > SHEET_OVERLAP and e < SHEET_GAP
				if drop:
					break
		if not drop:
			for k in 3:
				var i := idx[t * 3 + k]
				keep.append(i)
				if absf(v[i].x) < SEAM_SNAP:
					moved[i].x = 0.0
	a[Mesh.ARRAY_VERTEX] = moved
	a[Mesh.ARRAY_INDEX] = keep
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a if i == s else mesh.surface_get_arrays(i))
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out


## The throttle up from OFF (its keys or the axis) takes the checklist's engine step once the starter step (JFS / IPP)
## is done; before it the throttle moves alone.
func _throttle_step() -> void:
	var thr := float(host.throttle)
	var up := _throttle_was >= 0.0 and _throttle_was <= THROTTLE_OFF and thr > THROTTLE_OFF
	_throttle_was = thr
	if up and _idle_step_due():
		start_step(STEP_IDS.find("engine"), 1)


## The throttle's move from OFF is the idle step now: the starter step done (or, in the air, the engine windmilling
## fast enough to light: the airstart, training.md §7.2) and the idle step not yet, in a mission whose checklist has it
## or in a flight without one (a restart after a shutdown).
func _idle_step_due() -> bool:
	var turning: bool = "starter" in done or (host.flight != null and host.flight.start_on("airstart"))
	return turning and not "engine" in done and (checklist.is_empty() or "engine" in _steps())


## The Throttle OFF key (command 218, keys.json record 121): the throttle over the idle-cutoff detent to OFF, the fuel
## cut (IafFlight.start_step "cutoff", training.md §7.2). A running engine winds down; the recording gets a checklist
## step "cutoff" with its fault (shutdown, no_start), which fails a training mission. A restart takes the starter step
## and the throttle's move from OFF again.
func throttle_off() -> void:
	if host.flight == null:
		return
	var fault: String = host.flight.start_step("cutoff")
	if trainer != null and not rules.is_empty():
		fault = String(trainer.step_fault("cutoff", fault))  # a lesson's own shutdown is no fault (training.md §16.2)
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
