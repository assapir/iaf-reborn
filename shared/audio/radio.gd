## The radio (docs/radio.md): the phrase engine of phrasetemplates.trx / phraseparticalsdata.trx (FUN_004c66a0,
## FUN_004c5750), the tower (TowersManager, FUN_00550ed0 and Ctrl+T FUN_0054fb40), the wingman commands
## (FUN_0043f8d0) and the flight controller's reports: waypoint, airborne, landed, crashed, eject, kill calls
## (FUN_0054dc00, FUN_0054e310, FUN_0054de90, FUN_0054e0e0, FUN_0054e560, FUN_0054c2a0) and the AWACS contact calls
## (FUN_0054b130); their tables and filters are IafFlightController (crates/iaf-avionics/src/fctrl.rs).
## Every phrase is printed in the subtitle console (FUN_0044a060) and spoken part by part on the phrase channel.
## Host: terrain_view.gd (flight, runtime, ai, weapons, sounds, player_world(), _on_subtitle()); it calls update()
## with the sim time every frame.
extends Node

const SOUND_DIR := "resource/soundfiles"
## TowersManager (54eb30): the iaf.ibx sections in base order; 0..3 have a talking tower.
const BASES := ["Ramon", "David", "TelNof", "Refidim", "Inshas", "Damescuss", "Kuzeir", "Bley", "Ryak", "Aman"]
const TOWER_BASES := 4
const TOWER_RANGE := 18540.0  # 0x60cb28, 2-D to TowerLoc (54fbf0)
const HANGAR_SEARCH := 1000.0  # 5521c0
const AT_HANGAR := 100.0  # 0x60cb34
const LINEUP_NEAR := 400.0  # 0x60cb38
const LINEUP_FAR := 200.0  # 0x60cb3c
const ALIGN_DEG := 45.0  # 0x60cb40
const STOPPED := 1.0  # 0x60cb18, m/s
const TAXI_SPEED := 20.0  # 0x60cb30, m/s
const IDLE_REPEAT := 30.0  # 0x60cb20
## The zones (5bea90(r, 1, n, 1, lineup pose)): runway 1500 × 30 (550850), lineup 100 × 4 (550b20).
const RUNWAY_ZONE := [1500.0, 30]
const LINEUP_ZONE := [100.0, 4]
const ZONE_FACTOR := 3.0  # 0x6006b8
## Tower messages (551c20): code → template; 1 / 6 have a no-wind variant.
const MSG_TEMPLATES := {
	0: "ACFT_TAXI_TO_RUNWAY",
	1: "ACFT_CLEAR_TO_LINEUP",
	3: "ACFT_HOLD_POS",
	4: "ACFT_CLEAR_TO_TAKEOFF",
	5: "ACFT_PROCEED_TO_RUNWAY",
	6: "ACFT_CLEAR_TO_LAND",
	8: "ACFT_GO_AROUND_RUNWAY",
	9: "ACFT_TAXI_TO_PARK",
	10: "ACFT_GEARS_NOT_OPEN",
	12: "ACFT_CLEAR_TO_START",  # ours: Modern IAF's start-up request (request)
}
const CLICK := 0xb  # 551c20 case 0xb: KCH2.WAV, no text
const NO_MSG := 0xb
## Wingman commands (command 108 p1 → FUN_00441080's particle).
const WINGMAN_KEYS := {
	1: "WINGMAN_PROTECTME",
	2: "WINGMAN_BUGOUT",
	3: "WINGMAN_ENGAGEDESIGNATETARGET",
	4: "WINGMAN_ENGAGEANYTARGETIMNOT",
	5: "WINGMAN_TACTICALFORMATION",
	6: "WINGMAN_CLOSEFORMATION"
}
const COMMAND_PERIOD := 1.5  # brain+0xb8 timer (43edf2)
const REPLY_DELAY := 3.0  # 0x600738
const PROTECT_RANGE := 18540.0  # 0x600740
const ENGAGE_RADIUS := 9270.0  # 0x4610d800 (440860)
const ENGAGE_CLASSES := [0x1c, 3, 2, 1, 10, 9, 8, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10]
const REPORT_DELAY := 3.0  # 0x600e00 (WayptReport)
const AIRCRAFT := [2, 3, 0x1c]
const AWACS_PERIOD := 12.0  # FlightControllerTimer (54af40), single player
const AWACS_PLAYER_AGL := 50.0  # 0x60ca90: the player at least this high above the terrain
## FUN_005bd3c0: formation kind → name.
const KIND_NAMES := {
	1: "Alpha",
	2: "Bravo",
	3: "Charlie",
	4: "Delta",
	5: "Echo",
	6: "Foxtrot",
	7: "Enemy",
	8: "Other",
	9: "Hotel",
	10: "India"
}
## The friendly formation names (FUN_005513c0's kinds 1–6, 9, 10) in callsign order: Kidon 1 to Kidon 8.
const KIDONS := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Hotel", "India"]

var host: Node
var now := 0.0
var templates := {}  # NAME -> PackedStringArray of tokens
var particles := {}  # KEY -> [wav, text]
## Ours (IAF 2026): KEY -> the particle's Hebrew subtitle (phraseparticles_he.trx, iaf-sim own); empty in the original.
var particles_he := {}
## Ours (Modern IAF): each subtitle said with a Hebrew one, by either text -> [English, Hebrew], as printed (first
## letter upper-cased): the sim's band shows a line in the language of the moment it shows (flight_ui.gd).
var subtitles := {}
var bases: Array = []  # [{tower: Vector3, lineup: Vector3, rwy: int, hangars: [Vector2]}; World scale Real: + hdg]
## How many of the first bases have a talking tower: the original's four (TOWER_BASES), or every base of the project's
## own iaf.ibx (Settings.tower_bases).
var tower_count := TOWER_BASES
## Ours, Modern IAF's radio menu (modern-iaf/docs/training.md §8): the tower answers the player's requests (request) and
## does not talk on its own on the ground; `runway` is the designator the tower of base `runway_base` (its iaf.ibx
## section, the mission's base) gives ("25R"; "" = the base's iaf.ibx RunwayDesignator, else from RunwayNumber).
var menu := false
var runway := ""
var runway_base := ""
## For tests: every phrase said, {template, text, wavs}; every waypoint report posted, [unit name, waypoint].
var said: Array = []
## Ours (Modern IAF's Scramble, docs/ai.md §23): while true the flight AI's calls (flight_call) wait, so the AWACS's
## task call comes first; hold_calls(false) says them in order. Off everywhere else.
var _holding := false
var _held: Array = []
var posted: Array = []

# TowersManager +0x3318 base, +0x336c state, +0x3388 last message, +0x337c runway clear, +0x3374 period.
var base := -1
## The TowersManager state (+0x336c, FUN_00550ed0): INIT before the first tick, GROUND under a tower, AIRBORNE (or no
## tower in range), CLEARED after Ctrl+T ("proceed to runway").
enum Tower { INIT, GROUND, AIRBORNE, CLEARED }
var state := Tower.INIT
var last := NO_MSG
var runway_clear := false
var period := 1.0  # +0x3374, the period field (some paths set only the field)
var _tick_period := 1.0  # the running timer's period
var _next_tick := INF
var _idle_t := 0.0  # static 0x83ff88
var wind := 0  # +0x4dc (551320)
## Where the mission's wind blows from (misc 0x474, degrees; 0x46a when a mission stores the pair swapped). Only
## Better physics "Wind and turbulence" reads it (docs/flight-model.md §10).
var wind_from := 0
## The player's landed flag (brain +0xe0): set at a landing, cleared at lift-off (v1.1).
var landed := false
## brain+0xb8 of the player's brain: [last, next] (FUN_004d4100; 1e7 at start).
var _cmd_timer := [1.0e7, 1.0e7]
var _events: Array = []  # [time, Callable], one-shot
## The FlightController (DAT_00699348): the AWACS contact table, the kill / landed / airborne filters.
var fc: RefCounted = ClassDB.instantiate("IafFlightController")
var _awacs_next := INF
## Ours (Modern IAF's AWACS controller, docs/ai.md §24): the requests of the radio menu's AWACS page and the Eitam
## (IafAwacs); `awacs_task` the flight's task target (world; Scramble's free_combat.gd sets it), null none.
var awacs: RefCounted = ClassDB.instantiate("IafAwacs") if ClassDB.class_exists("IafAwacs") else null
var awacs_task := Callable()


func _ready() -> void:
	var dir: String = Settings.own_dir().path_join(SOUND_DIR)
	_load_templates(dir.path_join("phrasetemplates.trx"))
	_load_particles(dir.path_join("phraseparticalsdata.trx"))
	for line in FileAccess.get_file_as_string(dir.path_join("phraseparticles_he.trx")).split("\n"):
		var cols := line.split("\t")
		if cols.size() == 2 and not line.begins_with(";"):
			particles_he[cols[0].to_upper()] = cols[1].strip_edges()
	if not particles_he.is_empty():
		for k in LETTER_HE:
			if not particles_he.has(k):
				particles_he[k] = LETTER_HE[k]
	_load_bases(Settings.own_dir().path_join("iaf.ibx"))
	# Extras "Real Betty" (docs/sound.md §7): Modern IAF's tower phrases over the original's (its templates and
	# particles win, the rest stay the original's; the clips come through the sound table) and every base's tower talks.
	var sim: String = Settings.sim_sounds("phrasetemplates.trx") if Settings.real_betty == "modern" else ""
	if sim != "":
		_load_templates(sim.path_join("phrasetemplates.trx"))
		var own := particles.duplicate()
		_load_particles(sim.path_join("phraseparticalsdata.trx"))
		# The sim's callsigns are kidon style ("Kidon 1"); the original game keeps its own ("Alpha"): its callsign
		# particles, and none of the sim's clips that say one.
		for k in particles.keys():
			if Array(k.split("+")).any(func(x): return _is_callsign(x)):
				if own.has(k):
					particles[k] = own[k]
				else:
					particles.erase(k)
		tower_count = bases.size()


## A callsign particle key: a formation's name and _T / _P / _R ("ALPHA_T", the tower's).
static func _is_callsign(key: String) -> bool:
	var cut := key.rfind("_")
	return cut > 0 and key.substr(cut) in ["_T", "_P", "_R"] and KIND_NAMES.values().has(key.left(cut).capitalize())


# --- phrases (§1) -------------------------------------------------------------------------------


func _load_templates(path: String) -> void:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var t := line.strip_edges()
		if t == "" or t.begins_with(";"):
			continue
		var tok := t.split(" ", false)
		var toks := PackedStringArray()
		for s in tok:
			for u in s.split("\t", false):
				toks.append(u)
		templates[toks[0]] = toks.slice(1)


func _load_particles(path: String) -> void:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var t := line.strip_edges()
		if t == "" or t.begins_with(";"):
			continue
		var cols := t.replace("\t", " ").split(" ", false)
		if cols.size() < 2:
			continue
		var text := " ".join(cols.slice(2)) if cols.size() > 2 else ""
		particles[cols[0].to_upper()] = [cols[1], text]
	for k in LETTER_PARTS:
		if not particles.has(k):
			particles[k] = LETTER_PARTS[k]


## Ours: a parallel runway's letter as a particle (World scale Real's real designations, docs/radio.md §1): our clips
## rwyl / rwyr / rwyc (shared/extra/tower_numbers).
const LETTERS := {"L": "RWY_L", "R": "RWY_R", "C": "RWY_C"}
const LETTER_PARTS := {"RWY_L": ["RwyL", "left"], "RWY_R": ["RwyR", "right"], "RWY_C": ["RwyC", "center"]}
## Their Hebrew subtitles, where the Hebrew table (particles_he) has none of its own: "25 ימין", not "ימני" (the user,
## 20 Nov 2026).
const LETTER_HE := {"RWY_L": "שמאל", "RWY_R": "ימין", "RWY_C": "מרכז"}


## FUN_004c66a0: the template's tokens with %Sn / %Dn from the arguments, each key's wav and text; the text
## joins the parts with a blank, except before "," and at the start, where the part's first letter is upper-cased.
func expand(template: String, strings: Array = [], ints: Array = []) -> Dictionary:
	var text := ""
	var text_he := ""
	var count := 0
	var toks: Array = []  # [token, key]
	for tok in templates.get(template, PackedStringArray()):
		var key: String = tok
		var letter := ""
		if tok.begins_with("%") and tok.length() >= 3:
			var i := int(tok.substr(2)) - 1
			if tok[1] == "S":
				key = String(strings[i]) if i >= 0 and i < strings.size() else ""
			elif tok[1] == "D":
				key = "%d" % int(ints[i]) if i >= 0 and i < ints.size() else ""
				# Ours: a parallel runway's number "25L" speaks its letter after it (LETTERS).
				if i >= 0 and i < ints.size() and ints[i] is String and String(ints[i]).right(1) in LETTERS:
					letter = LETTERS[String(ints[i]).right(1)]
		toks.append([tok, key])
		if letter != "":
			toks.append([letter, letter])
	var keys: Array[String] = []
	for tk in toks:
		var tok: String = tk[0]
		var key: String = tk[1]
		var part: Array = particles.get(key.to_upper(), [])
		if part.is_empty():
			continue  # "Error: key … was not found in map" (UNCERTAIN: the original keeps the stale entry)
		var t: String = part[1]
		if count > 0 and tok != ",":
			text += " "
		elif t != "":
			t = t[0].to_upper() + t.substr(1)
		text += t
		if not particles_he.is_empty():
			text_he += ("" if count == 0 or tok == "," else " ") + String(particles_he.get(key.to_upper(), part[1]))
		keys.append(key.to_upper())
		count += 1
	# The subtitle in the game's language: the voice stays English (Modern IAF's Hebrew subtitles, phraseparticles_he).
	var shown := text_he if Settings.language == "he" and text_he != "" else text
	return {"template": template, "text": text, "text_he": text_he, "wavs": joined_wavs(keys), "shown": shown}


## Ours: the subtitle `en` and its Hebrew `he` known as one line (`subtitles`).
func bilingual(en: String, he: String) -> void:
	if en == "" or he == "":
		return
	var pair := [en[0].to_upper() + en.substr(1), he[0].to_upper() + he.substr(1)]
	subtitles[pair[0]] = pair
	subtitles[pair[1]] = pair


## Ours (Modern IAF, modern-iaf/docs/sound.md §3): each key's clip, where the longest run of keys that has a joined
## particle ("ALPHA_T+,+HOLD_POS", one clip said in one breath) plays that one clip instead. The original's particle
## files hold no joined key, so its phrases play key by key. A joined particle plays only where its clip exists in the
## language spoken (sound_table.gd has_clip): in Hebrew a callsign is always its own clip (sound.md §3.1).
func joined_wavs(keys: Array[String]) -> Array[String]:
	var wavs: Array[String] = []
	var table = host.sounds.get("table") if host != null and host.get("sounds") != null else null
	var i := 0
	while i < keys.size():
		var j := keys.size()
		while j > i + 1:
			var p: Array = particles.get("+".join(PackedStringArray(keys.slice(i, j))), [])
			if not p.is_empty() and (table == null or table.has_clip(String(p[0]))):
				break
			j -= 1
		wavs.append(String(particles["+".join(PackedStringArray(keys.slice(i, j)))][0]))
		i = j
	return wavs


## A phrase printed (FUN_0044a060) and spoken (FUN_004c5750); `print_it` false: spoken only. `subtitle`: printed in
## place of the phrase's own text (the sim's pilot call).
func say(template: String, strings: Array = [], ints: Array = [], print_it := true, subtitle := "") -> Dictionary:
	var p := expand(template, strings, ints)
	if host != null and host.get("sounds") is Object and host.sounds.get("silenced") == true:
		return p  # the sortie ended (an ejection in IAF 2026): no more radio
	said.append(p)
	var text: String = subtitle if subtitle != "" else (p.shown if print_it and p.text != "" else "")
	if subtitle == "" and text != "":
		bilingual(p.text, p.text_he)
	var shown := text != "" and host != null and host.has_method("_on_subtitle")
	if shown and not menu:
		host._on_subtitle(text)
	var clicks: bool = Settings.radio_key_clicks() and not p.wavs.is_empty()
	if clicks:
		play_wav("key_on.ogg")
	var players: Array = []  # the voice's: the subtitle shows from its first word to its last
	for w in p.wavs:
		players.append(play_wav(w))
	if clicks:
		play_wav("key_off.ogg")
	if shown and menu:
		cue_subtitle(text, players)
	return p


## Ours (Modern IAF, `menu`): the subtitle `text` of the line spoken by `players` (play_wav's, in order) shows as the
## first one starts and stays until the last one ends (the user, 2026-11-13: "comms subtitle should show up as
## talking"; 28 Nov, A141: "subtitles not sync with sound"). No clip (not shipped): it shows when the speech queued
## before it ends, for the band's own time; no sound: at once.
func cue_subtitle(text: String, players: Array = []) -> void:
	var s = host.get("sounds") if host != null else null
	var ps := players.filter(func(n): return n is Node)
	if s is Object and s.has_method("on_start") and s.get("silenced") != true and not ps.is_empty():
		s.on_start(ps[0], host._on_subtitle.bind(text, ps[-1]))
	elif s is Object and s.has_method("phrase_cue") and s.get("silenced") != true:
		s.phrase_cue(host._on_subtitle.bind(text))
	else:
		host._on_subtitle(text)


## FUN_004c5470(file, 0, 1): a plain wav on the phrase channel; its player (null: not shipped, or no sound).
func play_wav(file: String) -> Node:
	if host != null and host.get("sounds") != null:
		return host.sounds.play_phrase_wav(file)
	return null


# --- time ---------------------------------------------------------------------------------------


## Every frame with the sim time: the tower timer and the one-shot radio events.
func update(t: float) -> void:
	now = t
	if host != null and host.flight != null and not bool(host.flight.state().on_ground):
		landed = false  # v1.1 clears the landed flag at lift-off
	if _next_tick == INF:
		_start()
	while now >= _next_tick:
		_next_tick += _tick_period
		_tick()
	while now >= _awacs_next:
		_awacs_next += AWACS_PERIOD
		_awacs()
	while not _events.is_empty() and now >= float(_events[0][0]):
		var e: Array = _events.pop_front()
		(e[1] as Callable).call()


func _after(delay: float, f: Callable) -> void:
	_events.append([now + delay, f])
	_events.sort_custom(func(a, b): return a[0] < b[0])


## FUN_00550e40: the repeating TowersManagerTimer every `p` s, restarted now.
func _timer(p: float) -> void:
	period = p
	_tick_period = p
	_next_tick = now + p


## FUN_0054f8f0 (flight start) and the mission's wind (FUN_00551320, misc 0x46a); the FlightControllerTimer
## (FUN_0054af40) every 12 s from the flight start.
func _start() -> void:
	_timer(1.0)
	_awacs_next = now + AWACS_PERIOD
	state = Tower.INIT
	last = NO_MSG
	# Better physics "Wind and turbulence": the flight's wind was picked with the mission (Settings.runway_wind).
	var picked: Array = Settings.flight_wind if not Settings.flight_wind.is_empty() else Settings.pick_wind(_misc_all())
	wind = int(picked[0])
	wind_from = int(picked[1])
	if host != null and host.has_method("apply_wind"):
		host.apply_wind()


func _misc_all() -> Dictionary:
	var rt = host.get("runtime") if host != null else null
	return rt.misc if rt != null else {}


func _misc(key: String, def: Variant) -> Variant:
	var rt = host.get("runtime") if host != null else null
	return rt.misc.get(key, def) if rt != null else def


# --- the player ---------------------------------------------------------------------------------


func _st() -> Dictionary:
	return host.flight.state() if host != null and host.flight != null else {}


func _pos() -> Vector3:
	return host.player_world()


func _player_ent() -> Dictionary:
	var rt = host.get("runtime")
	return rt.player_entity() if rt != null else {}


func _formation_of(ent: Dictionary) -> Dictionary:
	var ai = host.get("ai")
	return ai._formation_of(ent) if ai != null and not ent.is_empty() else {}


## Ours (Modern IAF; the user, 20 Nov 2026: "Use kidon style, where kidon 1 is the first formation the second is
## kidon 2 etc"): formation `name`'s callsign "Kidon N", N its place among the friendly formation names (KIDONS:
## Alpha, the player's, is 1; Hotel and India, kinds 9 and 10, are 7 and 8); its jets are "Kidon N-M" (he.wikipedia
## טיסת מבנה, modern-iaf/docs/research/radio-terms.md). The particle keys stay the exe's (ALPHA_T, HOTEL_T).
static func kidon(name: String) -> String:
	var k := KIDONS.find(name)
	return "Kidon %d" % (k + 1) if k >= 0 else name


## A callsign ("Kidon 1", "Kidon 1-2") on a screen in the game's language: "כידון 1" in Hebrew.
static func callsign_text(cs: String) -> String:
	return cs.replace("Kidon", "כידון") if Settings.language == "he" else cs


## FUN_005513c0: a unit's formation name (kinds 2–6, 9, 10; else "Alpha").
func formation_name(ent: Dictionary) -> String:
	var k := int(_formation_of(ent).get("kind", 1))
	return KIND_NAMES[k] if k in [2, 3, 4, 5, 6, 9, 10] else "Alpha"


## The player's callsign for the tower.
func _tower_callsign() -> String:
	return formation_name(_player_ent()) + "_t"


## FUN_0054ccb0: "<formation><Leader|Wingman>" upper-cased; "" for "Other" (no report).
func callsign(ent: Dictionary) -> String:
	var f := _formation_of(ent)
	var s: String
	if f.is_empty():
		s = String(ent.get("name", "")) + " - No formation"
	else:
		s = String(KIND_NAMES.get(int(f.kind), "Unknown")) + ("Leader" if is_same(f.members[0], ent) else "Wingman")
	s = s.to_upper()
	return "" if s.substr(0, 5) == "OTHER" else s


# --- the tower (§2) -----------------------------------------------------------------------------


func _load_bases(path: String) -> void:
	var sections := Settings.load_ibx(path)
	var names: Array = Settings.tower_bases(sections)
	if names.is_empty():
		names = BASES
	else:
		tower_count = names.size()
	for name in names:
		var s: Dictionary = sections.get(name, {})
		var f := func(k: String) -> float: return float(s.get(k, "0"))
		var hangars := []
		for i in int(f.call("HangarsNum")):
			hangars.append(Vector2(f.call("HangarPtX%d" % i), f.call("HangarPtY%d" % i)))
		var b := {
			"name": name,
			"tower": Vector3(f.call("TowerLocX"), f.call("TowerLocY"), f.call("TowerLocZ")),
			"lineup": Vector3(f.call("LineupLocX"), f.call("LineupLocY"), f.call("LineupLocZ")),
			"rwy": int(f.call("RunwayNumber")),
			"hangars": hangars,
			"letter": "",
			# Ours (Modern IAF's iaf.ibx): the designator as painted and signed; "" = from RunwayNumber.
			"designator": String(s.get("RunwayDesignator", ""))
		}
		# Better physics "Wind and turbulence": the other end of a runway the tower turned into the wind.
		var iw := IafBases.into_wind(name) if ClassDB.class_exists("IafBases") else PackedFloat64Array()
		b.turned = not iw.is_empty()
		if b.turned:
			if Settings.new_ai():  # Modern IAF: the departure enters at the main end's lineup and backtracks
				b.entry = b.lineup
			b.lineup = Vector3(iw[0], iw[1], iw[2])
			b.rwy = int(iw[3])
			b.designator = String(s.get("RunwayDesignatorOpposite", ""))
		# World scale Real: the base at its real place (docs/world-scale.md §3.3).
		var m := Settings.base_moved(b.lineup.x, b.lineup.y)
		if not m.is_empty():
			# rwy: the real designator × 10 (magnetic, what the tower says); hdg: the true heading (the zones).
			b.hdg = wrapi(roundi(b.rwy + m[2]), 0, 360)
			b.rwy = IafBases.designator(name, b.hdg) * 10
			b.letter = IafBases.designator_letter(name, b.hdg)  # a parallel runway's L / R / C
			for k in ["tower", "lineup", "entry"].filter(func(k): return b.has(k)):
				var q := Settings.base_moved(b[k].x, b[k].y)
				if not q.is_empty():
					b[k] = Vector3(q[0], q[1], b[k].z + q[4])
			for i in hangars.size():
				var q := Settings.base_moved(hangars[i].x, hangars[i].y)
				if not q.is_empty():
					hangars[i] = Vector2(q[0], q[1])
		bases.append(b)


## FUN_00550ed0: one TowersManagerTimer tick.
func _tick() -> void:
	if host == null or host.flight == null:
		return
	var st := _st()
	_find_base()
	match state:
		Tower.GROUND:
			if float(st.speed) > STOPPED:
				_idle_t = now
			if _idle_t + IDLE_REPEAT <= now:
				last = NO_MSG
				_idle_t = now
			_ground()
		Tower.AIRBORNE:
			_idle_t = now
			if bool(st.on_ground):
				state = Tower.GROUND
		Tower.CLEARED:
			_idle_t = now
			_approach()
		_:
			_idle_t = now
			state = Tower.GROUND if bool(st.on_ground) else Tower.AIRBORNE


## FUN_0054fbf0: the first base whose tower is within 18.54 km (2-D); none: timer 4 s, state 2.
func _find_base() -> void:
	base = base_at(_pos())
	if base < 0:
		_timer(4.0)
		state = Tower.AIRBORNE


## The first base whose tower is within TOWER_RANGE (2-D) of `p`, −1 none.
func base_at(p: Vector3) -> int:
	for i in bases.size():
		var t: Vector3 = bases[i].tower
		if Vector2(p.x - t.x, p.y - t.y).length() < TOWER_RANGE:
			return i
	return -1


## The runway heading wrapped to (−180, 180] (550850).
static func _rwy_heading(b: Dictionary) -> float:
	var r := fmod(float(b.get("hdg", b.rwy)), 360.0)
	return r - 360.0 if r > 180.0 else r


## A zone of 5bea90: `n` spheres of radius `r` 2r apart along the runway, centred on the lineup point. An object
## of radius `ro` is in it when |p − c|² < (r + ro)² · 3 for a sphere (FUN_0043d020, 0x6006b8 = 3.0).
static func _in_zone(b: Dictionary, zone: Array, p: Vector3, ro: float) -> bool:
	var r: float = zone[0]
	var n: int = zone[1]
	var h := deg_to_rad(_rwy_heading(b))
	var fwd := Vector3(sin(h), cos(h), 0.0)
	for j in n:
		if p.distance_squared_to(b.lineup + fwd * ((2 * j + 1) * r - n * r)) < (r + ro) * (r + ro) * ZONE_FACTOR:
			return true
	return false


## FUN_005504e0 / FUN_00550240: the player inside the zone and lined up within 45° of the runway (the difference
## of the two headings in (−180, 180], not wrapped); runway_clear = no other stopped aircraft in it (not the
## player's leader or wingman). The runway check computes runway_clear only when aligned.
func _zone_check(zone: Array, clear_always: bool, at := -1) -> bool:
	var b: Dictionary = bases[at if at >= 0 else base]
	var aligned := absi(int(_rwy_heading(b) - wrapf(float(_st().heading), -180.0, 180.0))) <= ALIGN_DEG
	if not (aligned or clear_always):
		return false
	runway_clear = true
	var me := _player_ent()
	var mates: Array = _formation_of(me).get("members", []).slice(0, 2)
	var rt = host.get("runtime")
	if rt != null:
		for ent in rt.entities.values():
			# Aircraft leave the object list at state 5 (FUN_004a86b0).
			if (
				ent.player
				or int(ent.get("klass", 0)) != 0x1c
				or int(ent.state) == 5
				or mates.any(func(m): return is_same(m, ent))
			):
				continue
			if (
				(ent.vel as Vector3).length() < STOPPED
				and _in_zone(b, zone, ent.world, float(ent.get("coll_radius", 0.0)))
			):
				runway_clear = false
	return aligned and _in_zone(b, zone, _pos(), _player_radius())


## The jet's collision radius (FUN_0043b1c0: 0.25 · the model's extents).
func _player_radius() -> float:
	var a = host.get("aircraft")
	return 0.25 * preload("res://shared/ai/ai_flights.gd")._extent_sum(a) if a is Node3D else 0.0


## FUN_0054fef0: on the ground under the tower.
func _ground() -> void:
	var st := _st()
	if not bool(st.on_ground):
		state = Tower.AIRBORNE
		period = 4.0  # the field only: the timer keeps running
		return
	var b: Dictionary = bases[base]
	var p := _pos()
	if landed or menu:
		return
	var h := _hangar_near(b, p)
	if h >= 0 and Vector2(p.x, p.y).distance_to(b.hangars[h]) < AT_HANGAR:
		if period != 1.0:
			_timer(1.0)
		if last != 0 and last != 9:
			_say(0)
		state = Tower.GROUND
		return
	var busy := last in [10, 6, 8]
	var lined_up := _zone_check(LINEUP_ZONE, true)
	if not lined_up or busy:
		var d := Vector2(p.x, p.y).distance_to(Vector2(b.lineup.x, b.lineup.y))
		if d < LINEUP_NEAR and d > LINEUP_FAR and not busy:
			if runway_clear:
				if not last in [1, 4]:
					_say(1)
				return
			if not last in [3, 4]:
				_say(3)
	elif last != 4:
		_say(4)


## FUN_005521c0: the nearest hangar within 1000 m, −1 none (the original then reads uninitialised memory: none).
static func _hangar_near(b: Dictionary, p: Vector3) -> int:
	var best := -1
	var dmin := HANGAR_SEARCH
	for i in b.hangars.size():
		var d: float = Vector2(p.x, p.y).distance_to(b.hangars[i])
		if d < dmin:
			best = i
			dmin = d
	return best


## FUN_0054fd00: after "proceed to runway".
func _approach() -> void:
	var st := _st()
	var r := _zone_check(RUNWAY_ZONE, false)
	var on_ground := bool(st.on_ground)
	if on_ground and float(st.speed) < TAXI_SPEED and last == 6:
		_say(9)
		state = Tower.GROUND
		return
	if not r:
		if last == 6 and not on_ground:
			state = Tower.AIRBORNE
		return
	var code := 8
	if runway_clear:
		if absf(float(st.gear)) < 1e-5:  # getter 0x19: the gear down and locked
			if last != 6:
				_say(6)
			return
		code = 10
	if last != code:
		_say(code)
	last = code


## Ctrl+T (command 107, FUN_0054fb40).
func contact_tower() -> void:
	if base >= 0 and base < tower_count and state == Tower.AIRBORNE:
		_timer(1.0)
		_say(5)
		state = Tower.CLEARED
	elif base == -1 or base >= tower_count:
		_say(CLICK)
		_timer(4.0)
		state = Tower.AIRBORNE


## Ours, Modern IAF's radio menu (modern-iaf/docs/training.md §8): the player asks the tower of the base within
## TOWER_RANGE for "startup", "taxi", "lineup" or "takeoff"; the tower state machine (base, state, last) is left as
## it is. Start-up is always cleared; taxi once the engine runs (else hold position); line-up within LINEUP_NEAR of the
## lineup point with the runway clear, the holding point (86–101 m out) included (else hold position; ours:
## modern-iaf/docs/training.md §8); take-off by _ground's rule: lined up in the lineup zone "cleared for take-off",
## between LINEUP_FAR and LINEUP_NEAR of the lineup point "line up" with the runway clear (else hold position),
## elsewhere hold position. Near no talking tower: the click. Returns the answer
## (expand's {template, text, wavs}; template "KCH2": the click).
func request(kind: String) -> Dictionary:
	var at := base_at(_pos())
	if at < 0 or at >= tower_count:
		var click := {"template": "KCH2", "text": "", "wavs": ["KCH2.WAV"]}
		said.append(click)
		play_wav("KCH2.WAV")
		return click
	if kind == "radio_check":  # Modern IAF's radio check (modern-iaf/docs/training.md §8): "read you five", no readback
		return say("ACFT_RADIO_CHECK", [_tower_callsign()])
	var code := 3
	match kind:
		"startup":
			code = 12
		"taxi":
			code = 0 if bool(_st().get("engine_on", false)) else 3
		"lineup":
			# On a base turned into the wind, also at the runway's entry, where the backtrack to the lineup starts.
			var d := Vector2(_pos().x, _pos().y).distance_to(_flat(bases[at].lineup))
			d = minf(d, Vector2(_pos().x, _pos().y).distance_to(_flat(entry_of(at))))
			_zone_check(LINEUP_ZONE, true, at)  # sets runway_clear
			if d < LINEUP_NEAR and runway_clear:
				code = 1
		"takeoff":
			var b: Dictionary = bases[at]
			var d := Vector2(_pos().x, _pos().y).distance_to(Vector2(b.lineup.x, b.lineup.y))
			if _zone_check(LINEUP_ZONE, true, at):
				code = 4
			elif d < LINEUP_NEAR and d > LINEUP_FAR and runway_clear:
				code = 1
	return _speak(at, code)


## FUN_00551c20: a tower message on the current base, then the pilot's "Roger"; sets the last message.
func _say(code: int) -> void:
	last = code
	if code == CLICK:
		said.append({"template": "KCH2", "text": "", "wavs": ["KCH2.WAV"]})
		play_wav("KCH2.WAV")
		return
	_speak(base, code)


## Tower message `code` of base `at` and the pilot's "Roger" (551c20's speech); returns the message (say's). Ours
## (Modern IAF's flight AI): `cs` another callsign particle (a wingman's), answered by its own `answer` in place of the
## player's "Roger".
func _speak(at: int, code: int, cs := "", answer := []) -> Dictionary:
	cs = cs if cs != "" else _tower_callsign()
	var rwy: Variant = runway_of(at)
	var t: String = MSG_TEMPLATES[code]
	# The wind: %S2 its speed (the original's particle), %S3 ours, its direction in ICAO's 10° steps, 360 for north
	# ("wind 270 degrees, 10 knots": Modern IAF's templates, modern-iaf/docs/sound.md §3); the original's templates
	# leave %S3 out.
	var dir := "WDIR%03d" % (posmod(roundi(wind_from / 10.0) * 10 - 1, 360) + 1)
	var w := ["WI_KNOTS%02d" % wind, dir] if wind != 0 else ["WIND_CALM", ""]
	var p := {}
	match code:
		0:
			var hour := int(float(_misc("0x460", 0.0)) + now) / 3600
			p = say(t, [cs, Settings.tower_greeting(hour)], [rwy])
		1, 6:
			if wind != 0:
				p = say(t, [cs] + w, [rwy])
			else:
				p = say(t + "_NW", [cs], [rwy])
		4:
			# The wind and the runway are ours (Modern IAF's template); the original's template says the callsign only.
			p = say(t, [cs] + w, [rwy])
		5:
			p = say(t, [cs], [rwy])
		_:
			p = say(t, [cs])
	if not answer.is_empty():
		say("WNG_ACK", answer)
	else:
		readback(t, rwy)
	return p


## Where a departure at base `at` enters the runway: the lineup point, on a base turned into the wind the main end's
## lineup, where the backtrack down the runway starts (docs/autopilot.md §2.4).
func entry_of(at: int) -> Vector3:
	return bases[at].get("entry", bases[at].lineup)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


## The runway end base `at`'s tower names: RunwayNumber / 10 (FUN_00551c20), World scale Real's letter, Modern IAF's
## designator ("25R"), the mission's runway (`runway`) unless the tower turned the base into the wind (its other end's
## designator then, docs/autopilot.md §2.4).
func runway_of(at: int) -> Variant:
	var b: Dictionary = bases[at]
	var rwy: Variant = int(b.rwy) / 10
	if b.letter != "":
		rwy = "%d%s" % [rwy, b.letter]
	if b.designator != "" and not b.has("hdg"):
		rwy = b.designator
	if runway != "" and b.name == runway_base and not b.get("turned", false):
		rwy = runway
	return rwy


## The player's answer to the tower's `template` (FUN_00551c20: "Roger"). Ours (Modern IAF, the user, 17 Nov 2026:
## "the readback and not only "roger""): where the phrase table has RB_<template>, the player reads the clearance
## back in their own voice, the callsign last ("Taxi to runway 25 right, Kidon 1": modern-iaf/docs/sound.md §3).
func readback(template: String, rwy: Variant = "") -> void:
	var rb := "RB_" + template.trim_suffix("_NW")
	if templates.has(rb) and Settings.new_ai():  # the 1998 game answers "Roger", also with the sim's phrases
		say(rb, [formation_name(_player_ent()) + "_P"], [rwy])
	else:
		say("ACFT_ROGER", [], [], false)


# --- wingman commands (§3) ----------------------------------------------------------------------


## Command 108 (records 98–103): FUN_0043f8d0(cmd) on the player's brain. Modern IAF's four-ship (IafAi) takes its
## own of them through the radio menu's commands (FLIGHT_KEYS).
func wingman_command(cmd: int) -> void:
	var ai = host.get("ai")
	var me := _player_ent()
	if ai == null or me.is_empty():
		return
	if FLIGHT_KEYS.has(cmd):
		if ai.get("flight_ai") != null and host.get("addon") != null and host.addon.has_method("flight_command"):
			host.addon.flight_command(FLIGHT_KEYS[cmd][0], FLIGHT_KEYS[cmd][1])
		if cmd > 6 or ai.get("flight_ai") != null:
			return
	var w: Dictionary = ai.partner_of(me)  # brain+0x44
	if w.is_empty() or int(w.state) in [4, 5] or int(w.control) == 0:
		return
	var spoke := _command_timer()
	if spoke:
		say("WINGMAN_COMMAND", [WINGMAN_KEYS.get(cmd, "")])
	if spoke and ai.on_ground(w):
		_negative()
		return
	var t := {}
	match cmd:
		1:
			t = _entity(host.weapons.rwr.nearest() if host.get("weapons") != null else "")
			if t.is_empty() or ai.world_of(t).distance_to(_pos()) > PROTECT_RANGE or not int(t.klass) in AIRCRAFT:
				_negative(spoke)
				return
		3:
			t = _radar_target()
			if t.is_empty() or not host.enemy_of_player(t):
				_negative(spoke)
				return
		4:
			t = engage_any(w)
			if t.is_empty():
				_negative(spoke)
				return
	var p = w.get("pilot")
	if p == null:
		return  # not flown here (a mission-controlled wingman): its brain does not run
	if cmd in [1, 3, 4] and not t.is_empty():
		p.brain.target = t
	if cmd > 0 and cmd < 7:
		p.brain.wingman_command = cmd


## FUN_004d4100 on brain+0xb8: fires when now is outside [last, next], then next = now + 1.5 s.
func _command_timer() -> bool:
	if now >= _cmd_timer[0] and now <= _cmd_timer[1]:
		return false
	_cmd_timer = [now, now + COMMAND_PERIOD]
	return true


## FUN_00441310(0) 3 s later (only when the command was spoken).
func _negative(spoke := true) -> void:
	if spoke:
		_after(REPLY_DELAY, func(): say("WINGMAN_REPLY_NEGATIVE", ["NEGATIVE"]))


func _entity(key: String) -> Dictionary:
	var rt = host.get("runtime")
	return rt.entities.get(key, {}) if rt != null and key != "" else {}


## FUN_0044e430: the radar's target (locked).
func _radar_target() -> Dictionary:
	var wp = host.get("weapons")
	if wp == null or wp.radar == null:
		return {}
	return _entity(String(wp.radar.locked().get("key", "")))


## FUN_00440860: a target for "engage other target".
func engage_any(w: Dictionary) -> Dictionary:
	var ai = host.get("ai")
	var me := _player_ent()
	var centre := me
	var klass := 0
	var t := _radar_target()
	if not t.is_empty():
		klass = int(t.klass)
		if klass == 0x1c:
			var f: Dictionary = ai._formation_of(t)
			var o: Dictionary = {}
			if not f.is_empty():
				o = f.members[1] if f.members.size() > 1 and not is_same(f.members[1], t) else f.members[0]
			if not o.is_empty() and not int(o.state) in [4, 5]:
				return o
		centre = t
	var c: Vector3 = ai.world_of(centre)
	var best := {}
	var dmin := ENGAGE_RADIUS
	for ent in host.runtime.entities.values():
		if ent.player or is_same(ent, w) or int(ent.state) in [4, 5] or not int(ent.get("klass", 0)) in ENGAGE_CLASSES:
			continue
		if klass != 0 and (int(ent.klass) != klass or is_same(ent, t)):
			continue
		var d: float = ai.world_of(ent).distance_to(c)
		if d < dmin and host.enemy_of_player(ent):
			best = ent
			dmin = d
	return best


# --- flight-controller reports (§4) -------------------------------------------------------------


## WayptReport (FUN_0054dc00) 3 s after `ent` moved on to waypoint `wp`.
func waypoint_passed(ent: Dictionary, wp: int) -> void:
	posted.append([String(ent.get("name", "")), wp])
	_after(REPORT_DELAY, func(): _report(ent, "PASS_WAYPT_PHRASE", ["G%d" % wp], wp != 0))


## EjectReport (FUN_0054e560): "<callsign> ejected" (the host schedules it 4.5 s after the ejection).
func ejected(ent: Dictionary) -> void:
	_report(ent, "EJECTED_PHRASE", [], true)


## AirborneReport (FUN_0054e310), 3 s after an AI jet's take-off (TakeoffCL above 100 m AGL): "<callsign> airborne",
## not twice in a row for one callsign.
func report_airborne(ent: Dictionary) -> void:
	_after(
		REPORT_DELAY,
		func():
			if not ent.is_empty() and not host.enemy_of_player(ent) and fc.airborne(callsign(ent)):
				say("AIRBORNE_PHRASE", [callsign(ent)])
	)


## LandedReport (FUN_0054de90), 3 s after a landing roll stopped (StopPlaneCL): "<callsign> landed", not twice in
## a row for one callsign.
func report_landed(ent: Dictionary) -> void:
	_after(
		REPORT_DELAY,
		func():
			if not ent.is_empty() and not host.enemy_of_player(ent) and fc.landed(callsign(ent)):
				say("LANDED_PHRASE", [callsign(ent)])
	)


## CrashedReport (FUN_0054e0e0): "<callsign> crashed" (the runtime posts it 2.5 s after an aircraft was destroyed
## without a killer).
func crashed(ent: Dictionary) -> void:
	_report(ent, "CRASHED_PHRASE", [], true)


## The kill call (FUN_0054c2a0; the runtime posts it 5 s after a kill by `killer`): "Alpha leader shot down MiG 29",
## "… was shot down by SAM", "… destroyed tank", "… shot friendly F-16".
func kill(victim: Dictionary, killer: Dictionary) -> void:
	if victim.is_empty() or killer.is_empty():
		return
	var r: Array = fc.kill(now, _kill_unit(victim), _kill_unit(killer), int(victim.side) != int(killer.side))
	if not r.is_empty():
		say(r[0], [r[1], r[2]])


func _kill_unit(ent: Dictionary) -> Dictionary:
	return {
		"enemy": host.enemy_of_player(ent),
		"klass": int(ent.get("klass", -1)),
		"type_code": int(ent.get("type_code", -1)),
		"name": String(ent.get("name", "")).left(19),
		"callsign": callsign(ent)
	}


## FlightControllerTimer (FUN_0054b130): the AWACS calls. With the player alive, controlled and at least 50 m above
## the terrain, every alive, controlled aircraft other than the player and the wingman is offered to the contact
## table; the calls due are said (ACFT_FCTRL_LONG / _SHORT).
func _awacs() -> void:
	if host == null or host.get("runtime") == null or not fc.awacs_due():
		return
	if awacs != null and not awacs.in_service():
		return  # Modern IAF: the Eitam is lost (docs/ai.md §24.4)
	var me := _player_ent()
	if me.is_empty() or int(me.state) in [4, 5] or int(me.control) == 0:
		return
	var p := _pos()
	var g = host.mission_ground(p)
	if absf(p.z - (float(g) if g != null else 0.0)) < AWACS_PLAYER_AGL:
		return
	var ai = host.get("ai")
	var wing: Dictionary = ai.partner_of(me) if ai != null else {}
	var units := []
	for ent in host.runtime.entities.values():
		if (
			ent.player
			or is_same(ent, wing)
			or not int(ent.get("klass", 0)) in AIRCRAFT
			or int(ent.state) in [4, 5]
			or int(ent.control) == 0
		):
			continue
		var w: Vector3 = ai.world_of(ent) if ai != null else ent.world
		var eg = host.mission_ground(w)
		# Modern IAF: with an Eitam, only what its radar sees (docs/ai.md §24.4).
		if eitam_flies() and not awacs.sees(p, {"pos": w, "ground": float(eg) if eg != null else 0.0}):
			continue
		units.append(
			{
				"key": ent.key,
				"callsign": formation_name(ent),
				"enemy": host.enemy_of_player(ent),
				"known": ent.get("known", false),
				"pos": w,
				"ground": float(eg) if eg != null else 0.0,
				"heading": float(ent.get("heading", 0.0)),
				"rand": randi() & 0x7fff
			}
		)
	# +0x314 (the player on the FlyTSD: long calls only) stays false: the FlyTSD freezes the sim and this timer.
	# Modern IAF: the player's flight AI hears each call (an AI jet holding the contact reports it).
	var fa = ai.get("flight_ai") if ai != null else null
	for c in fc.scan(p, units, false, formation_name(me)):
		say(c[0], Array(c[1]))
		if fa != null:
			fa.awacs(host.runtime.now, c[2].bearing, c[2].miles, int(c[2].code) != 0)


# --- Modern IAF's AWACS controller (docs/ai.md §24) --------------------------------------------------------------


## The aircraft offered to the controller (IafAwacs): every alive, controlled aircraft in the air but the player's,
## hostile when an enemy the side knows (the contact calls' `known`), else a bogey; ours friendly.
func awacs_contacts() -> Array:
	var out := []
	var ai = host.get("ai") if host != null else null
	var rt = host.get("runtime") if host != null else null
	if rt == null:
		return out
	for ent in rt.entities.values():
		if ent.player or not int(ent.get("klass", 0)) in AIRCRAFT or int(ent.state) in [4, 5] or int(ent.control) == 0:
			continue
		var w: Vector3 = ai.world_of(ent) if ai != null else ent.world
		var g = host.mission_ground(w)
		var ident := "friendly"
		if host.enemy_of_player(ent):
			ident = "hostile" if ent.get("known", false) else "bogey"
		(
			out
			. append(
				{
					"key": ent.key,
					"pos": w,
					"ground": float(g) if g != null else 0.0,
					"heading": float(ent.get("heading", 0.0)),
					"ident": ident,
					"tanker": bool(ent.get("tanker", false)),
				}
			)
		)
	return out


## The request's data: the player's callsign and place, the radar's locked track, the flight's task target and its
## home base (the mission's base, its lineup point).
func awacs_ask() -> Dictionary:
	var a := {"callsign": formation_name(_player_ent()), "player": _pos()}
	var locked := _radar_target()
	if not locked.is_empty():
		a.locked = String(locked.key)
	if awacs_task.is_valid():
		var t = awacs_task.call()
		if t != null:
			a.task = t
	for b in bases:
		if b.name == runway_base:
			a.home = b.lineup
	return a


## The flight has an Eitam (alive or lost): the controller's picture is its radar's (docs/ai.md §24.1).
func eitam_flies() -> bool:
	return awacs != null and not awacs.eitam().is_empty()


## Why request `id` cannot be made now (IafAwacs.refusal: lost, no_lock, no_tanker, no_home), "" when it can.
func awacs_refusal(id: String) -> String:
	if awacs == null:
		return "lost"
	return String(awacs.refusal(id, awacs_ask(), awacs_contacts()))


## The player's request `id` to the AWACS (the radio menu's AWACS page): the pilot's call ("Eitam, Kidon 1, picture"),
## the radio's gap, then the controller's answer said line by line in the AWACS voice; each group it names goes to
## the flight AI as a contact call does (an AI jet holding it reports "contact"). The answer's lines (radio.gd say's
## records), [] when the request is refused.
func awacs_request(id: String, pilot_line := "") -> Array:
	if awacs_refusal(id) != "":
		return []
	var cs := formation_name(_player_ent())
	say("PILOT_CALL", ["EITAM_P", cs + "_P", "REQ_AWX_" + id.to_upper()], [], false, pilot_line)
	play_wav("radio_gap.ogg")
	var a: Dictionary = awacs.answer(id, awacs_ask(), awacs_contacts())
	var out := []
	for l in a.get("lines", []):
		out.append(say(l[0], Array(l[1])))
	var ai = host.get("ai")
	var fa = ai.get("flight_ai") if ai != null else null
	if fa != null:
		for n in a.get("named", []):
			fa.awacs(now, n.bearing, n.miles, n.hostile)
	return out


## Ours (Modern IAF, modern-iaf/docs/research/radio-terms.md): the flight AI's numbers and call words (voices.json's
## WNG_* particles, the wingmen's voice).
const WING_NUMBERS := ["", "WNG_ONE", "WNG_TWO", "WNG_THREE", "WNG_FOUR"]
## Modern IAF's four-ship (ours, docs/ai.md §8.10, §8.11): command 108's p1 -> [to, the radio menu's command]: cover me
## to Kidon 1-2 (record 101, Alt + P), engage my target to Kidon 1-2 (record 99, Alt + E), sort (record 98, Alt + W),
## weapons free to the flight round the SPI (record 256, Alt + \), the flight low level / back to altitude in turn
## (record 257, Ctrl + \, docs/ai.md §20). The 1998 game has no IafAi flight: its brain takes 1–6 as before; 7 and 8
## are Modern IAF's only.
const FLIGHT_KEYS := {1: [2, "cover"], 3: [2, "engage"], 4: [0, "sort"], 7: [0, "free"], 8: [0, "low_level"]}

const WING_WORDS := {
	"unable": "WNG_UNABLE",
	"in_position": "WNG_IN_POSITION",
	"joker": "WNG_JOKER",
	"bingo": "WNG_BINGO",
	"rtb": "WNG_RTB",
	"spike": "WNG_SPIKE",
	"mud": "WNG_MUD",
	"defending": "WNG_DEFENDING",
	"contact": "WNG_CONTACT",
	"break_left": "WNG_BREAK_LEFT",
	"break_right": "WNG_BREAK_RIGHT",
	"engaged": "WNG_ENGAGED",
	"targeted": "WNG_TARGETED",
	"fox_1": "WNG_FOX1",
	"fox_2": "WNG_FOX2",
	"fox_3": "WNG_FOX3",
	"guns": "WNG_GUNS",
	"splash": "WNG_SPLASH",
	"winchester": "WNG_WINCHESTER",
	"in": "WNG_IN",
	"release": "WNG_RELEASE",
	"alpha": "WNG_ALPHA",
	"done": "WNG_DONE",
}


## Ours (Modern IAF's Scramble): the flight AI's calls wait (`on`) or, held ones first, are said again.
func hold_calls(on: bool) -> void:
	_holding = on
	if not on:
		var held := _held
		_held = []
		for c in held:
			flight_call(c[0], c[1], c[2], c[3])


## Ours (Modern IAF): the flight AI's call `id` from jet `from` (IafAi.step) said and subtitled: "Kidon 1-2." (ack),
## "Kidon 1-2, unable", "Kidon 1-3 has the lead", "Kidon 1-2, six point two" (an ops check's fuel state, `fuel_kg` in
## thousands of pounds); a break is called to the element mate (#2 calls "Kidon 1-1, break left" when a missile flies
## at #1). The tower's landing calls to the jet at `at` (world): "Kidon 1-2, cleared to land runway 25 left" on its
## turn to final (tower_land), "Kidon 1-2, welcome back, taxi to parking" after its roll (tower_park), from the
## talking tower in range, each answered with the callsign (docs/ai.md §8.7).
func flight_call(from: int, id: String, fuel_kg := 0.0, at := Vector3.INF) -> void:
	if _holding:
		_held.append([from, id, fuel_kg, at])
		return
	var n: String = WING_NUMBERS[clampi(from, 0, 4)]
	var table = host.sounds.get("table") if host != null and host.get("sounds") != null else null
	if table != null:
		table.speaker = from  # his Hebrew voice (sound_table.gd hebrew)
	if id in ["tower_land", "tower_park"]:
		var b := base_at(at) if at != Vector3.INF else -1
		if b >= 0 and b < tower_count and from >= 2:
			_speak(b, 6 if id == "tower_land" else 9, n + "_T", [n])
		return
	match id:
		"ack":
			say("WNG_ACK", [n])
		"lead_change":
			say("WNG_LEAD", [n])
		"fuel_state":
			var tenths := clampi(roundi(fuel_kg * 2.20462 / 100.0), 0, 999)
			var whole := str(floori(tenths / 10.0))
			var parts := [n]
			for ch in whole:
				parts.append("WNG_D" + ch)
			parts.append("WNG_D%d" % (tenths % 10))
			say("WNG_FUEL" if whole.length() == 1 else "WNG_FUEL2", parts)
		_ when id.begins_with("lead_"):
			# An AI lead's order to its flight (IafAi.lead_order, the player its wingman): "Kidon 1, tac right".
			say("LEAD_CALL", ["WNG_KIDON1", "WNG_L_" + id.trim_prefix("lead_").to_upper()])
		"break_left", "break_right":
			var mate := from + 1 if from % 2 == 1 else from - 1
			say("WNG_CALL", [WING_NUMBERS[clampi(mate, 0, 4)], WING_WORDS[id]])
		_:
			if WING_WORDS.has(id):
				say("WNG_CALL", [n, WING_WORDS[id]])


## Ours, Modern IAF's tanker (shared/ai/tanker.gd; modern-iaf/docs/research/air-refuelling.md §8.3): its callsign by
## kind, the receiver's callsign in its voice by the flight's number (the player's own as the flight's, "Kidon 1"), and
## each event's words (voices.json TNK_*).
const TANKER_CALLSIGNS := {"kc46": "TNK_GIDEON", "reem": "TNK_REEM"}
const TANKER_TO := ["TNK_KIDON1", "TNK_KIDON1", "TNK_KIDON1_2", "TNK_KIDON1_3", "TNK_KIDON1_4"]
const TANKER_WORDS := {
	"cleared_precontact": "TNK_PRECONTACT",
	"stand_by": "TNK_STAND_BY",
	"cleared_contact": "TNK_CLEARED_CONTACT",
	"contact": "TNK_CONTACT",
	"disconnect": "TNK_DISCONNECT",
	"breakaway": "TNK_BREAKAWAY",
	"complete": "TNK_COMPLETE",
}


## The tanker of `kind` says `event` to receiver `n` (the flight's number, the player's own jet's included): "Kidon 1,
## Gideon, cleared pre-contact" with its own callsign, the others "Kidon 1-2, contact".
func tanker_call(kind: String, event: String, n: int) -> void:
	if not TANKER_WORDS.has(event):
		return
	var to: String = TANKER_TO[clampi(n, 0, 4)]
	if event == "cleared_precontact":
		say("TNK_CALL3", [to, TANKER_CALLSIGNS.get(kind, "TNK_GIDEON"), TANKER_WORDS[event]])
	else:
		say("TNK_CALL", [to, TANKER_WORDS[event]])


## A report of a unit on the player's side (FUN_004a4cf0) with a callsign.
func _report(ent: Dictionary, template: String, more: Array, ok: bool) -> void:
	if not ok or ent.is_empty() or host.enemy_of_player(ent):
		return
	var cs := callsign(ent)
	if cs != "":
		say(template, [cs] + more)
