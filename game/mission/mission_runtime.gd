# The mission runtime (docs/mission-runtime.md): runs a loaded mission and its base missions from
# the original data. Nothing runs per frame in the original: everything comes from a timer queue
# (script entries, 4 s radius checks, delayed end-of-mission events) and entity state changes.
# Generic for every mission; the host (terrain_view.gd) supplies the player's position, plays
# audio and shows subtitles / message boxes.
extends Node

signal subtitle(text: String)
signal message_box(msg: int, buttons: Array)  # msgs.trx line, ["deb", "fly", "exit"]
signal end_flight(debrief: bool)

const RADIUS_PERIOD := 4.0
const END_BOX_DELAY := 10.0
const ALL_DEAD_DELAY := 5.0
## Control mode (entity 0x320 bit 0) and roles (0x32a).
const ROLE_SURVIVE := 0
const ROLE_TARGET := 1

var host: Node
var now := 0.0
var _timers: Array = []  # [time, seq, Callable] kept sorted
var _seq := 0

## Entities by key "<file index>:<entity id>": {name, file, id, world (X, Y, alt), role, mission_ctl,
## slots, watched, sensor, alive_scenario, state, visible, node, player, lists: [motion, trigger],
## current: [index, index], path}.
var entities := {}
var events := {}  # "<file index>:<event id>" -> {debrief, audio, left, actions}
var paths := {}  # "<file index>:<path id>" -> [Vector3 world]
var audio := {}  # bdb Audio id -> {wav, subtitle}
var debriefs := {}  # "<file index>:<id>" -> {text, flag}
var misc := {}
var targets_left := 0
var passed := false
var failed := false
var debrief_notes := ["", ""]  # flag 0 texts, flag 1 texts
var _shown_debriefs := {}


func setup(host_node: Node, mission_files: Array, bdb: Dictionary) -> void:
	host = host_node
	for a in bdb.get("audio", {}).get("items", []):
		audio[int(a["0x1e"])] = {"wav": String(a.get("0x136", "")), "subtitle": String(a.get("0x140", ""))}
	for fi in mission_files.size():
		var m: Dictionary = mission_files[fi]
		if fi == 0:
			misc = m.misc.items[0]
		for d in m.get("debrief", {}).get("items", []):
			debriefs["%d:%d" % [fi, int(d["0x1e"])]] = {"text": String(d.get("0x26c", "")), "flag": int(d.get("0x262", 0))}
		for p in m.get("paths", {}).get("items", []):
			var pts: Array = []
			for q in p.get("points", []):
				pts.append(Vector3(q[1], q[2], q[3]))
			paths["%d:%d" % [fi, int(p["0x1e"])]] = pts
		for ev in m.get("events", {}).get("items", []):
			events["%d:%d" % [fi, int(ev["0x1e"])]] = {
				"debrief": int(ev.get("0x38e", -1)), "audio": int(ev.get("0x3ac", -1)),
				"left": int(ev.get("0x398", 0)), "actions": ev.get("list", []),
			}
		for e in m.entities.items:
			if not (e is Dictionary):
				continue
			var name := String(e.get("0x2bc", ""))
			# Unused player slots (Player2..7 at -1, -1) are not spawned; other entities are, wherever
			# they are (sensors are logic nodes, e.g. the takeoff "Win sensor" at -1).
			var unplaced := float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0
			if unplaced and name.begins_with("Player") and name != "Player1":
				continue
			var ent := {
				"key": "%d:%d" % [fi, int(e["0x1e"])], "name": name, "file": fi, "id": int(e["0x1e"]),
				"world": Vector3(float(e["0x2e4"]), float(e["0x2ee"]), float(e.get("0x2f8", 0))),
				"role": int(e.get("0x32a", 2)), "mission_ctl": int(e.get("0x320", 0)) & 1 == 1,
				"slots": e.get("slots", []), "watched": int(e.get("0xac", -1)),
				"sensor": true, "alive_scenario": true, "state": 1, "visible": true, "node": null,
				"player": fi == 0 and name == "Player1",
				"lists": [_list(e.get("scripts0", {})), _list(e.get("scripts1", {}))],
				"current": [-1, -1], "path": null, "type": int(e.get("0x2c6", -1)),
			}
			entities[ent.key] = ent
			if ent.role == ROLE_TARGET:
				targets_left += 1


## A script list by list index ("raw10").
static func _list(obj: Dictionary) -> Dictionary:
	var out := {}
	for sc in obj.get("items", []):
		out[int(sc.get("raw10", -1))] = sc
	return out


## Activation (FUN_004a8890): mission-controlled entities start both script lists at index 1
## and arm their reached / left checks.
func start() -> void:
	for ent in entities.values():
		if ent.player or not ent.mission_ctl:
			continue
		for li in 2:
			if ent.lists[li].has(1):
				_jump(ent, li, 1)
		_arm_reached(ent)


func _process(delta: float) -> void:
	now += delta
	for ent in entities.values():
		if ent.path != null:
			_move_on_path(ent)
	while not _timers.is_empty() and _timers[0][0] <= now:
		var t: Array = _timers.pop_front()
		t[2].call()


func _after(seconds: float, what: Callable) -> void:
	_seq += 1
	_timers.append([now + seconds, _seq, what])
	_timers.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))


# --- scripts (§4) -----------------------------------------------------------------------------

func _jump(ent: Dictionary, li: int, index: int) -> void:
	if not ent.alive_scenario or not ent.lists[li].has(index):
		return
	ent.current[li] = index
	var sc: Dictionary = ent.lists[li][index]
	var duration := float(sc.get("0x87a", 0))
	if li == 0 and int(sc.get("0x884", -1)) >= 1:
		duration += float(sc["0x884"])
	if li == 0:
		_motion(ent, sc, duration)
	else:
		_trigger(ent, sc)
	if duration != -1.0:
		_after(duration, _entry_done.bind(ent, li, index))


func _entry_done(ent: Dictionary, li: int, index: int) -> void:
	if ent.current[li] != index:
		return  # jumped elsewhere meanwhile
	var next := int(ent.lists[li][index].get("0x898", -1))
	if next == 0 or next == -1:
		ent.current[li] = -1
		return
	_jump(ent, li, next)


## Trigger list opcodes (scripts1).
func _trigger(ent: Dictionary, sc: Dictionary) -> void:
	match int(sc.get("0x83e", -1)):
		5:
			if not ent.player:
				_destroy(ent)
		6:
			fire_event(ent.file, int(sc.get("0x8ac", 0)))
		7:
			play_message(int(sc.get("0x8ac", 0)))
		8:
			subtitle.emit(String(sc.get("0x848", "")))
		10:
			ent.alive_scenario = false
		11:
			ent["shield"] = true
		12:
			ent["shield"] = false
		13:
			_set_visible(ent, true)
		14:
			_set_visible(ent, false)
		16:
			ent.sensor = true
		17:
			ent.sensor = false
		_:
			pass  # 3, 4, 15 (Wait), 18, 19 (Destroy entity: no-op in this build), 23, 26 …


## Motion list opcodes (scripts0).
func _motion(ent: Dictionary, sc: Dictionary, duration: float) -> void:
	match int(sc.get("0x83e", -1)):
		16:
			var pts: Array = paths.get("%d:%d" % [ent.file, int(sc.get("0x8ac", -1))], [])
			if not pts.is_empty():
				ent.path = {"points": pts, "start": now, "duration": maxf(duration, 0.001) if duration > 0.0 else 1e7}
		_:
			ent.path = null  # 1 Hover and the rest: hold position


## Path traversal: along the path's points over the entry's duration (kinematics UNCERTAIN).
func _move_on_path(ent: Dictionary) -> void:
	var p: Dictionary = ent.path
	var pts: Array = p.points
	var f := clampf((now - p.start) / p.duration, 0.0, 1.0)
	var seg := f * (pts.size() - 1)
	var i := mini(int(seg), pts.size() - 2)
	ent.world = pts[0] if pts.size() == 1 else pts[i].lerp(pts[i + 1], seg - i)
	if f >= 1.0:
		ent.path = null
	host.mission_entity_moved(ent)


func _set_visible(ent: Dictionary, on: bool) -> void:
	ent.visible = on
	host.mission_entity_visible(ent)


# --- reached / left checks (§2.2) -------------------------------------------------------------

func _slot(ent: Dictionary, i: int) -> Dictionary:
	return ent.slots[i] if i < ent.slots.size() else {}


func _arm_reached(ent: Dictionary) -> void:
	var reached := int(_slot(ent, 5).get("0x33e", 0))
	var left := int(_slot(ent, 4).get("0x33e", 0))
	if (reached == 0 and left == 0) or not entities.has("%d:%d" % [ent.file, ent.watched]):
		return
	_after(0.0, _reached_tick.bind(ent))


func _distance_ok(ent: Dictionary) -> bool:
	var w: Dictionary = entities["%d:%d" % [ent.file, ent.watched]]
	var r := float(_slot(ent, 4).get("0x348", 0))
	return _world_of(ent).distance_squared_to(_world_of(w)) < r * r


func _reached_tick(ent: Dictionary) -> void:
	if not ent.alive_scenario:
		return
	if _distance_ok(ent):
		if ent.sensor:
			fire_event(ent.file, int(_slot(ent, 5).get("0x33e", 0)))
		if int(_slot(ent, 4).get("0x33e", 0)) != 0:
			_after(RADIUS_PERIOD, _left_tick.bind(ent))
	else:
		_after(RADIUS_PERIOD, _reached_tick.bind(ent))


func _left_tick(ent: Dictionary) -> void:
	if not ent.alive_scenario:
		return
	if not _distance_ok(ent):
		fire_event(ent.file, int(_slot(ent, 4).get("0x33e", 0)))
	else:
		_after(RADIUS_PERIOD, _left_tick.bind(ent))


func _world_of(ent: Dictionary) -> Vector3:
	return host.player_world() if ent.player else ent.world


# --- events (§3) -------------------------------------------------------------------------------

func fire_event(file: int, id: int) -> void:
	var ev: Dictionary = events.get("%d:%d" % [file, id], {})
	if ev.is_empty() or ev.left <= 0:
		return
	ev.left -= 1
	if ev.audio != 0 and ev.audio != -1:
		play_message(ev.audio)
	if ev.debrief != 0 and ev.debrief != -1:
		_add_debrief(file, ev.debrief)
	for a in ev.actions:
		var target: Dictionary = entities.get("%d:%d" % [file, int(a[0])], {})
		if target.is_empty():
			continue
		if int(a[1]) != 0 and int(a[1]) != -1:
			_jump(target, 0, int(a[1]))
		if int(a[2]) != 0 and int(a[2]) != -1:
			_jump(target, 1, int(a[2]))


## PlayMessage (FUN_004ba7ee): the bdb Audio wav on the speech channel and its subtitle.
func play_message(id: int) -> void:
	var a: Dictionary = audio.get(id, {})
	if a.is_empty():
		return
	host.mission_play_wav(a.wav)
	if a.subtitle != "":
		subtitle.emit(a.subtitle)


func _add_debrief(file: int, id: int) -> void:
	var key := "%d:%d" % [file, id]
	var d: Dictionary = debriefs.get(key, {})
	if d.is_empty() or _shown_debriefs.has(key):
		return
	_shown_debriefs[key] = true
	debrief_notes[1 if d.flag == 1 else 0] += "\n\n" + d.text


# --- entity state and mission end (§2, §5) ----------------------------------------------------

## Destroyed (Explode, or killed): destroy event, killScenario, role rules.
func _destroy(ent: Dictionary) -> void:
	if ent.state >= 4:
		return
	ent.state = 5
	if ent.sensor:
		fire_event(ent.file, int(_slot(ent, 1).get("0x33e", 0)))
	ent.alive_scenario = false
	_set_visible(ent, false)
	_role_rules(ent)


## The player's aircraft was destroyed (crash).
func player_destroyed() -> void:
	for ent in entities.values():
		if ent.player:
			_destroy(ent)
			# All players dead: the flight ends after 5 s and goes to the debrief (event 0x82).
			_after(ALL_DEAD_DELAY, func(): end_flight.emit(true))


func _role_rules(ent: Dictionary) -> void:
	if ent.role == ROLE_SURVIVE and not failed:
		play_message(int(misc.get("0x4c4", -1)))
		failed = true
		_after(END_BOX_DELAY, func(): message_box.emit(14, ["deb", "fly", "exit"]))
	elif ent.role == ROLE_TARGET:
		targets_left -= 1
		if targets_left == 0 and not passed and not failed:
			play_message(int(misc.get("0x4ce", -1)))
			passed = true
			_after(END_BOX_DELAY, func(): message_box.emit(13, ["deb", "fly"]))


## Debrief (FUN_00597a80): headline 0x47e if passed else 0x492, then the notes.
func debrief_text() -> Dictionary:
	var headline := String(misc.get("0x47e" if passed else "0x492", ""))
	return {"passed": passed, "headline": headline, "notes": (debrief_notes[0] + debrief_notes[1]).strip_edges()}
