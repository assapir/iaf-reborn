## The radio (docs/radio.md): the phrase engine of phrasetemplates.trx / phraseparticalsdata.trx (FUN_004c66a0,
## FUN_004c5750), the tower (TowersManager, FUN_00550ed0 and Ctrl+T FUN_0054fb40), the wingman commands
## (FUN_0043f8d0) and the flight controller's waypoint / eject reports (FUN_0054dc00, FUN_0054e560).
## Every phrase is printed in the subtitle console (FUN_0044a060) and spoken part by part on the phrase channel.
## Host: terrain_view.gd (flight, runtime, ai, weapons, sounds, player_world(), _on_subtitle()); it calls update()
## with the sim time every frame.
extends Node

const SOUND_DIR := "install/resource/soundfiles"
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
const MSG_TEMPLATES := {0: "ACFT_TAXI_TO_RUNWAY", 1: "ACFT_CLEAR_TO_LINEUP", 3: "ACFT_HOLD_POS",
	4: "ACFT_CLEAR_TO_TAKEOFF", 5: "ACFT_PROCEED_TO_RUNWAY", 6: "ACFT_CLEAR_TO_LAND", 8: "ACFT_GO_AROUND_RUNWAY",
	9: "ACFT_TAXI_TO_PARK", 10: "ACFT_GEARS_NOT_OPEN"}
const CLICK := 0xb  # 551c20 case 0xb: KCH2.WAV, no text
const NO_MSG := 0xb
## Wingman commands (command 108 p1 → FUN_00441080's particle).
const WINGMAN_KEYS := {1: "WINGMAN_PROTECTME", 2: "WINGMAN_BUGOUT", 3: "WINGMAN_ENGAGEDESIGNATETARGET",
	4: "WINGMAN_ENGAGEANYTARGETIMNOT", 5: "WINGMAN_TACTICALFORMATION", 6: "WINGMAN_CLOSEFORMATION"}
const COMMAND_PERIOD := 1.5  # brain+0xb8 timer (43edf2)
const REPLY_DELAY := 3.0  # 0x600738
const PROTECT_RANGE := 18540.0  # 0x600740
const ENGAGE_RADIUS := 9270.0  # 0x4610d800 (440860)
const ENGAGE_CLASSES := [0x1c, 3, 2, 1, 10, 9, 8, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10]
const REPORT_DELAY := 3.0  # 0x600e00 (WayptReport)
const AIRCRAFT := [2, 3, 0x1c]
## FUN_005bd3c0: formation kind → name.
const KIND_NAMES := {1: "Alpha", 2: "Bravo", 3: "Charlie", 4: "Delta", 5: "Echo", 6: "Foxtrot", 7: "Enemy",
	8: "Other", 9: "Hotel", 10: "India"}

var host: Node
var now := 0.0
var templates := {}  # NAME -> PackedStringArray of tokens
var particles := {}  # KEY -> [wav, text]
var bases: Array = []  # [{tower: Vector3, lineup: Vector3, rwy: int, hangars: [Vector2]}]
## For tests: every phrase said, {template, text, wavs}; every waypoint report posted, [unit name, waypoint].
var said: Array = []
var posted: Array = []

# TowersManager +0x3318 base, +0x336c state, +0x3388 last message, +0x337c runway clear, +0x3374 period.
var base := -1
var state := 0
var last := NO_MSG
var runway_clear := false
var period := 1.0  # +0x3374, the period field (some paths set only the field)
var _tick_period := 1.0  # the running timer's period
var _next_tick := INF
var _idle_t := 0.0  # static 0x83ff88
var wind := 0  # +0x4dc (551320)
## The player's landed flag (brain +0xe0): set at a landing, cleared at lift-off (v1.1).
var landed := false
## brain+0xb8 of the player's brain: [last, next] (FUN_004d4100; 1e7 at start).
var _cmd_timer := [1.0e7, 1.0e7]
var _events: Array = []  # [time, Callable], one-shot


func _ready() -> void:
	var dir: String = Settings.assets_dir().path_join(SOUND_DIR)
	_load_templates(dir.path_join("phrasetemplates.trx"))
	_load_particles(dir.path_join("phraseparticalsdata.trx"))
	_load_bases(Settings.assets_dir().path_join("install/iaf.ibx"))


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


## FUN_004c66a0: the template's tokens with %Sn / %Dn from the arguments, each key's wav and text; the text
## joins the parts with a blank, except before "," and at the start, where the part's first letter is upper-cased.
func expand(template: String, strings: Array = [], ints: Array = []) -> Dictionary:
	var text := ""
	var wavs: Array[String] = []
	var count := 0
	for tok in templates.get(template, PackedStringArray()):
		var key: String = tok
		if tok.begins_with("%") and tok.length() >= 3:
			var i := int(tok.substr(2)) - 1
			if tok[1] == "S":
				key = String(strings[i]) if i >= 0 and i < strings.size() else ""
			elif tok[1] == "D":
				key = "%d" % int(ints[i]) if i >= 0 and i < ints.size() else ""
		var part: Array = particles.get(key.to_upper(), [])
		if part.is_empty():
			continue  # "Error: key … was not found in map" (UNCERTAIN: the original keeps the stale entry)
		var t: String = part[1]
		if count > 0 and tok != ",":
			text += " "
		elif t != "":
			t = t[0].to_upper() + t.substr(1)
		text += t
		wavs.append(String(part[0]))
		count += 1
	return {"template": template, "text": text, "wavs": wavs}


## A phrase printed (FUN_0044a060) and spoken (FUN_004c5750); `print_it` false: spoken only.
func say(template: String, strings: Array = [], ints: Array = [], print_it := true) -> Dictionary:
	var p := expand(template, strings, ints)
	said.append(p)
	if print_it and p.text != "" and host != null and host.has_method("_on_subtitle"):
		host._on_subtitle(p.text)
	for w in p.wavs:
		play_wav(w)
	return p


## FUN_004c5470(file, 0, 1): a plain wav on the phrase channel.
func play_wav(file: String) -> void:
	if host != null and host.get("sounds") != null:
		host.sounds.play_phrase_wav(file)


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


## FUN_0054f8f0 (flight start) and the mission's wind (FUN_00551320, misc 0x46a).
func _start() -> void:
	_timer(1.0)
	state = 0
	last = NO_MSG
	var w := int(_misc("0x46a", 0))
	wind = w if w in [0, 10, 15, 20] else [0, 10, 15, 20][randi() % 4]


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


## FUN_005513c0: the player's formation name for the tower (kinds 2–6, 9, 10; else "Alpha").
func _tower_callsign() -> String:
	var k := int(_formation_of(_player_ent()).get("kind", 1))
	return (KIND_NAMES[k] if k in [2, 3, 4, 5, 6, 9, 10] else "Alpha") + "_t"


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
	for name in BASES:
		var s: Dictionary = sections.get(name, {})
		var f := func(k: String) -> float: return float(s.get(k, "0"))
		var hangars := []
		for i in int(f.call("HangarsNum")):
			hangars.append(Vector2(f.call("HangarPtX%d" % i), f.call("HangarPtY%d" % i)))
		bases.append({"name": name, "tower": Vector3(f.call("TowerLocX"), f.call("TowerLocY"), f.call("TowerLocZ")),
			"lineup": Vector3(f.call("LineupLocX"), f.call("LineupLocY"), f.call("LineupLocZ")),
			"rwy": int(f.call("RunwayNumber")), "hangars": hangars})


## FUN_00550ed0: one TowersManagerTimer tick.
func _tick() -> void:
	if host == null or host.flight == null:
		return
	var st := _st()
	_find_base()
	match state:
		1:
			if float(st.speed) > STOPPED:
				_idle_t = now
			if _idle_t + IDLE_REPEAT <= now:
				last = NO_MSG
				_idle_t = now
			_ground()
		2:
			_idle_t = now
			if bool(st.on_ground):
				state = 1
		3:
			_idle_t = now
			_approach()
		_:
			_idle_t = now
			state = 1 if bool(st.on_ground) else 2


## FUN_0054fbf0: the first base whose tower is within 18.54 km (2-D); none: timer 4 s, state 2.
func _find_base() -> void:
	var p := _pos()
	base = -1
	for i in bases.size():
		var t: Vector3 = bases[i].tower
		if Vector2(p.x - t.x, p.y - t.y).length() < TOWER_RANGE:
			base = i
			return
	_timer(4.0)
	state = 2


## The runway heading wrapped to (−180, 180] (550850).
static func _rwy_heading(b: Dictionary) -> float:
	var r := fmod(float(b.rwy), 360.0)
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
func _zone_check(zone: Array, clear_always: bool) -> bool:
	var b: Dictionary = bases[base]
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
			if ent.player or int(ent.get("klass", 0)) != 0x1c or int(ent.state) == 5 or mates.any(func(m): return is_same(m, ent)):
				continue
			if (ent.vel as Vector3).length() < STOPPED and _in_zone(b, zone, ent.world, float(ent.get("coll_radius", 0.0))):
				runway_clear = false
	return aligned and _in_zone(b, zone, _pos(), _player_radius())


## The jet's collision radius (FUN_0043b1c0: 0.25 · the model's extents).
func _player_radius() -> float:
	var a = host.get("aircraft")
	return 0.25 * preload("res://ai/ai_flights.gd")._extent_sum(a) if a is Node3D else 0.0


## FUN_0054fef0: on the ground under the tower.
func _ground() -> void:
	var st := _st()
	if not bool(st.on_ground):
		state = 2
		period = 4.0  # the field only: the timer keeps running
		return
	var b: Dictionary = bases[base]
	var p := _pos()
	if landed:
		return
	var h := _hangar_near(b, p)
	if h >= 0 and Vector2(p.x, p.y).distance_to(b.hangars[h]) < AT_HANGAR:
		if period != 1.0:
			_timer(1.0)
		if last != 0 and last != 9:
			_say(0)
		state = 1
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
		state = 1
		return
	if not r:
		if last == 6 and not on_ground:
			state = 2
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
	if base >= 0 and base < TOWER_BASES and state == 2:
		_timer(1.0)
		_say(5)
		state = 3
	elif base == -1 or base >= TOWER_BASES:
		_say(CLICK)
		_timer(4.0)
		state = 2


## FUN_00551c20: a tower message on the current base, then the pilot's "Roger"; sets the last message.
func _say(code: int) -> void:
	last = code
	if code == CLICK:
		said.append({"template": "KCH2", "text": "", "wavs": ["KCH2.WAV"]})
		play_wav("KCH2.WAV")
		return
	var b: Dictionary = bases[base]
	var cs := _tower_callsign()
	var rwy: int = int(b.rwy) / 10
	var t: String = MSG_TEMPLATES[code]
	match code:
		0:
			var hour := int(float(_misc("0x460", 0.0)) + now) / 3600
			var greet := "MORNING"
			if hour >= 12 and hour < 17:
				greet = "AFTERNOON"
			elif hour >= 17 and hour < 22:
				greet = "EVENING"
			say(t, [cs, greet], [rwy])
		1, 6:
			if wind != 0:
				say(t, [cs, "WI_KNOTS%02d" % wind], [rwy])
			else:
				say(t + "_NW", [cs], [rwy])
		5:
			say(t, [cs], [rwy])
		_:
			say(t, [cs])
	say("ACFT_ROGER", [], [], false)


# --- wingman commands (§3) ----------------------------------------------------------------------

## Command 108 (records 98–103): FUN_0043f8d0(cmd) on the player's brain.
func wingman_command(cmd: int) -> void:
	var ai = host.get("ai")
	var me := _player_ent()
	if ai == null or me.is_empty():
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


## A report of a unit on the player's side (FUN_004a4cf0) with a callsign.
func _report(ent: Dictionary, template: String, more: Array, ok: bool) -> void:
	if not ok or ent.is_empty() or host.enemy_of_player(ent):
		return
	var cs := callsign(ent)
	if cs != "":
		say(template, [cs] + more)
