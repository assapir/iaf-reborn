# The mission runtime (docs/mission-runtime.md): runs a loaded mission and its base missions from
# the original data. Nothing runs per frame in the original: everything comes from a timer queue
# (script entries, 4 s radius checks, delayed end-of-mission events) and entity state changes.
# Generic for every mission; the host (terrain_view.gd) supplies the player's position, plays
# audio and shows subtitles / message boxes.
extends Node

signal subtitle(text: String)
signal message_box(msg: int, buttons: Array)  # msgs.trx line, ["deb", "fly", "exit"]
signal end_flight(debrief: bool)
signal event_fired(id: int, name: String)  # the blackbox's mission events

const RADIUS_PERIOD := 4.0
const END_BOX_DELAY := 10.0
const ALL_DEAD_DELAY := 5.0
## Control mode (entity 0x320 bit 0) and roles (0x32a).
const ROLE_SURVIVE := 0
const ROLE_TARGET := 1
const DamageModel := preload("res://mission/damage_model.gd")

var host: Node
var now := 0.0
var _timers: Array = []  # [time, seq, Callable] kept sorted
var _seq := 0

## Entities by key "<file index>:<entity id>": {name, file, id, world (X, Y, alt), role, mission_ctl,
## slots, watched, sensor, alive_scenario, state, visible, node, player, lists: [motion, trigger],
## current: [index, index], path, control, side, heading, vel; damage (docs/damage.md): klass,
## type_code, strength, size, collidable, damage, requested, killer, shield, smoke, fall}.
var entities := {}
var events := {}  # "<file index>:<event id>" -> {debrief, audio, left, actions, conds, counter}
## Mission counters (§3.1): id -> value, all 0 at load; ids 1..max counter id any event names.
var counters := {}
var paths := {}  # "<file index>:<path id>" -> [Vector3 world]
var audio := {}  # bdb Audio id -> {wav, subtitle}
var debriefs := {}  # "<file index>:<id>" -> {text, flag}
var misc := {}
var targets_left := 0
var passed := false
var failed := false
var debrief_notes := ["", ""]  # flag 0 texts, flag 1 texts
var _shown_debriefs := {}
var _all_dead := false  # rule 1 posted (debrief unit +0x661c)


## The files of menu mission `id` (missionlist.json: the main .mis, then its base missions, as
## converted by `iaf-convert missions`): [{name, data}] in that order, data {} for a missing file;
## [] when the id is not listed.
static func mission_files(id: int) -> Array:
	var dir := Settings.assets_dir().path_join("converted/missions")
	var out := []
	for name in Settings.load_json(dir.path_join("missionlist.json")).get(str(id), []):
		out.append({"name": String(name), "data": Settings.load_json(dir.path_join(String(name) + ".json"))})
	return out


## The object database a mission file names (converted .bdb); {} when missing.
static func load_bdb(mission: Dictionary) -> Dictionary:
	var name := String(mission.get("bdb", "")).to_lower()
	return Settings.load_json(Settings.assets_dir().path_join("converted/missions").path_join(name + ".json"))


## A bdb's Objects by id (0x1e).
static func bdb_objects(bdb: Dictionary) -> Dictionary:
	var out := {}
	for o in bdb.get("objects", {}).get("items", []):
		out[int(o["0x1e"])] = o
	return out


## The player's aircraft at mission load (FUN_004bb439): the leader of the formation with id (0x1e)
## 1, else 2, 3, 4 (the formation map is keyed by the formation id, FUN_005bcb40 / insert FUN_005bc980
## from FUN_004b3604), whatever its flight letter. A formation's leader is member 0 if placed, else
## member 1 (unplaced = both coordinates negative, like the unused PlayerN slots). `wanted` = the
## flight (0x3f2 = 1..4, Alpha..Delta) picked on the TSD (Fly makes that flight's leader the player
## object, FUN_005045b0 -> FUN_004d31f0); 0 or a flight without a leader = the default. Returns
## {flight (the formation's 0x3f2), entity} or {} when there is none.
static func player_flight(mission: Dictionary, wanted := 0) -> Dictionary:
	var by_id := {}
	for e in mission.get("entities", {}).get("items", []):
		if e is Dictionary:
			by_id[int(e.get("0x1e", -1))] = e
	var leader := func(f: Dictionary) -> Dictionary:
		for mem in f.get("members", []):
			var e: Dictionary = by_id.get(int(mem.get("0x41a", -1)), {})
			if not e.is_empty() and not (float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0):
				return e
		return {}
	var formations: Array = mission.get("formations", {}).get("items", [])
	if wanted >= 1 and wanted <= 4:
		for f in formations:
			if int(f.get("0x3f2", 0)) == wanted:
				var e: Dictionary = leader.call(f)
				if not e.is_empty():
					return {"flight": wanted, "entity": e}
	for id in [1, 2, 3, 4]:
		for f in formations:
			if int(f.get("0x1e", -1)) == id:
				var e: Dictionary = leader.call(f)
				if not e.is_empty():
					return {"flight": int(f.get("0x3f2", 0)), "entity": e}
				break
	return {}


## Where the player starts (engine world X, Y, altitude): the leader of flight `wanted` (else the
## default flight, player_flight()) of the menu mission's main file; null when there is none.
static func player_start(id: int, wanted := 0) -> Variant:
	var files := mission_files(id)
	if files.is_empty() or files[0].data.is_empty():
		return null
	var pf := player_flight(files[0].data, wanted)
	if pf.is_empty():
		return null
	var e: Dictionary = pf.entity
	return Vector3(float(e["0x2e4"]), float(e["0x2ee"]), float(e["0x2f8"]))


## `player_id`: entity id (0x1e) of the player's aircraft in the main file (player_flight());
## -1 = the default flight's leader.
func setup(host_node: Node, mission_files: Array, bdb: Dictionary, player_id := -1) -> void:
	host = host_node
	if player_id < 0 and not mission_files.is_empty():
		player_id = int(player_flight(mission_files[0]).get("entity", {}).get("0x1e", -1))
	for a in bdb.get("audio", {}).get("items", []):
		audio[int(a["0x1e"])] = {"wav": String(a.get("0x136", "")), "subtitle": String(a.get("0x140", ""))}
	var objects := {}
	for o in bdb.get("objects", {}).get("items", []):
		objects[int(o.get("0x1e", -1))] = o
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
			var conds: Array = ev.get("conds", [])
			for c in conds:
				if int(c.get("0x3de", -1)) >= 1:
					for id in range(1, int(c["0x3de"]) + 1):
						counters[id] = 0
			events["%d:%d" % [fi, int(ev["0x1e"])]] = {
				"debrief": int(ev.get("0x38e", -1)), "audio": int(ev.get("0x3ac", -1)),
				"left": int(ev.get("0x398", 0)), "actions": ev.get("list", []),
				"conds": conds.slice(0, 2), "counter": conds[2] if conds.size() > 2 else {},
				"name": String(ev.get("0x384", "")),
			}
		for e in m.entities.items:
			if not (e is Dictionary):
				continue
			var name := String(e.get("0x2bc", ""))
			# Unused player slots (Player2..7 at -1, -1) are not spawned; other entities are, wherever
			# they are (sensors are logic nodes, e.g. the takeoff "Win sensor" at -1).
			var is_player := fi == 0 and int(e["0x1e"]) == player_id
			var unplaced := float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0
			if unplaced and name.to_lower().begins_with("player") and not is_player:
				continue
			var ent := {
				"key": "%d:%d" % [fi, int(e["0x1e"])], "name": name, "file": fi, "id": int(e["0x1e"]),
				"world": Vector3(float(e["0x2e4"]), float(e["0x2ee"]), float(e.get("0x2f8", 0))),
				"role": int(e.get("0x32a", 2)), "mission_ctl": int(e.get("0x320", 0)) & 1 == 1,
				"slots": e.get("slots", []), "watched": int(e.get("0xac", -1)),
				"sensor": true, "alive_scenario": true, "state": 1, "visible": true, "node": null,
				"player": is_player,
				"lists": [_list(e.get("scripts0", {})), _list(e.get("scripts1", {}))],
				"current": [-1, -1], "path": null, "type": int(e.get("0x2c6", -1)),
				"control": 3 if is_player else (2 if int(e.get("0x320", 0)) & 1 == 1 else 1),
				"side": int(e.get("0x2d0", 0)), "heading": float(e.get("0x302", 0)),
				"vel": Vector3.ZERO, "fall": null, "combat": true, "brain": _brain_of(e),
				"armament": e.get("armament"),
			}
			_init_damage(ent, objects.get(ent.type, {}))
			entities[ent.key] = ent
			if ent.role == ROLE_TARGET:
				targets_left += 1


## The entity's brain id (0x2da): the loader copies it to the spawn descriptor as is (FUN_0058f110 @58f1e6) and the
## spawner attaches only a brain found by that id (FUN_004b815f), so −1 is no brain (the unit fires only by script;
## 112's T-55s, which the original never lets fire on their own).
static func _brain_of(e: Dictionary) -> int:
	return int(e.get("0x2da", -1))


static func _init_damage(ent: Dictionary, obj: Dictionary) -> void:
	ent.klass = int(obj.get("0x5aa", -1))
	ent.type_code = int(obj.get("0x5b4", -1))
	ent.strength = DamageModel.strength_of(obj)
	ent.size = DamageModel.size_of(obj)
	ent.damageable = true
	# bdb Objects 0x58c: the unit gets a collider (FUN_004b8118, docs/damage.md §7).
	ent.collidable = int(obj.get("0x58c", 0)) != 0
	ent.damage = 0.0
	ent.requested = -1
	ent.killer = {}
	ent.shield = false
	ent.smoke = false
	ent.smoke_timer = false


## A script list by list index ("raw10").
static func _list(obj: Dictionary) -> Dictionary:
	var out := {}
	for sc in obj.get("items", []):
		out[int(sc.get("raw10", -1))] = sc
	return out


## Activation (FUN_004a9100): mission-controlled entities start both script lists at index 1
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
			var was: Vector3 = ent.world
			_move_on_path(ent)
			ent.vel = (ent.world - was) / delta if delta > 0.0 else Vector3.ZERO
		if ent.fall != null:
			_fall_update(ent)
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
		1:
			# Launch at location (FUN_005c4160): the point (x, y, z) at the script's +0x28..+0x30 — the editor stores x in
			# the text field 0x848, y / z in 0x852 / 0x85c (215's Scud: "447090", 620870, 10000).
			if host.has_method("mission_launch_at"):
				host.mission_launch_at(ent, Vector3(float(String(sc.get("0x848", "0"))), float(sc.get("0x852", 0.0)),
					float(sc.get("0x85c", 0.0))))
		2:
			# Launch at target (FUN_005c42f0): the unit's weapon at entity 0x8ac (docs/ai.md §14). 0x852 (script +0x3c)
			# ≠ 0 is a kill shot (release flag 2), 0 a miss for show (flag 0: its blast hurts nothing).
			host.mission_launch(ent, entities.get("%d:%d" % [ent.file, int(sc.get("0x8ac", -1))], {}),
				float(sc.get("0x852", 0.0)) != 0.0)
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
		21:
			# Enable combat (FUN_00440830): combat allowed again, the brain reset (docs/ai.md §6).
			ent["combat"] = true
			if host.has_method("mission_combat"):
				host.mission_combat(ent, true)
		22:
			# Disable combat (FUN_004407e0): an engaged unit's weapons go safe and its brain stops
			# (transferControl, docs/ai.md §6).
			ent["combat"] = false
			if host.has_method("mission_combat"):
				host.mission_combat(ent, false)
		_:
			pass  # 3, 4, 15 (Wait), 18, 19 (Destroy entity: no-op in this build), 23, 26 …


## Motion list opcodes (scripts0).
func _motion(ent: Dictionary, sc: Dictionary, duration: float) -> void:
	ent["aim_seq"] = int(ent.get("aim_seq", 0)) + 1  # a new motion ends a running yaw to target (UNCERTAIN)
	match int(sc.get("0x83e", -1)):
		5:
			# Turn (FUN_005c3940): mover mode 5 with the arg +0x28. The FM mover's setMode (FUN_005a8410) has no case 5, and
			# the data uses it only on 224's brain-controlled MiG: nothing happens. Other movers' mode 5: not traced.
			pass
		11:
			ent.path = null
			_yaw_to_target(ent, entities.get("%d:%d" % [ent.file, int(sc.get("0x8ac", -1))], {}))
		16:
			var pts: Array = paths.get("%d:%d" % [ent.file, int(sc.get("0x8ac", -1))], [])
			if not pts.is_empty():
				ent.path = _path_from(ent, pts, float(sc.get("0x852", 1.0)) < 0.0, maxf(duration, 0.001) if duration > 0.0 else 1e7)
		_:
			ent.path = null  # 1 Hover and the rest: hold position


## Motion op 11 Yaw to target (FUN_005c39e0, target = entity 0x8ac): types 250 and 291–339 start the "Subpart yaw
## to target motion" (vtable 0x612898, FUN_005c3ee0, first tick now, then every 1.0 s): the turret (250, part+0xc) or
## the launcher (part+0x14) is set to the target's bearing each tick, without end. Type 270: the same timer without a
## target lowers part+0x10 (carrier and missile) by 1.5° a tick down to −90° (0x612878 / 0x612874): the launcher rises.
## Others: mover mode 9 with the target (its rate not traced: the unit faces the target each tick, UNCERTAIN).
## UNCERTAIN: the part angle taken as the target's bearing relative to the hull, positive to the left (the original's
## −10° term in FUN_005c3ee0 not reproduced).
func _yaw_to_target(ent: Dictionary, target: Dictionary) -> void:
	var tc := int(ent.get("type_code", -1))
	if not ent.has("parts"):
		ent["parts"] = {}
	var field := "turret" if tc == 250 else ("launcher" if tc > 290 and tc < 340 else "")
	_aim_tick(ent, target, field, tc == 270, int(ent.aim_seq))


func _aim_tick(ent: Dictionary, target: Dictionary, field: String, raise: bool, seq: int) -> void:
	if int(ent.aim_seq) != seq or int(ent.state) >= 4:
		return
	if raise:
		var e := float(ent.parts.get("elevation", 0.0))
		if e <= -90.0:
			return
		ent.parts["elevation"] = e - 1.5
	elif not target.is_empty() and int(target.state) < 5:
		var d: Vector3 = _world_of(target) - _world_of(ent)
		var bearing := rad_to_deg(atan2(d.x, d.y))
		if field == "":
			ent.heading = bearing
		else:
			ent.parts[field] = wrapf(float(ent.heading) - bearing, -180.0, 180.0)  # +θ about the hinge turns left
	host.mission_entity_parts(ent)
	_after(1.0, _aim_tick.bind(ent, target, field, raise, seq))


## Path traversal: along the path's points over the entry's duration (kinematics UNCERTAIN).
func _move_on_path(ent: Dictionary) -> void:
	var p: Dictionary = ent.path
	var pts: Array = p.points
	var f := clampf((now - p.start) / p.duration, 0.0, 1.0)
	var d := f * float(p.length)
	ent.world = pts[-1]
	for i in pts.size() - 1:
		var seg: float = Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y).length()
		if d <= seg:
			ent.world = pts[i].lerp(pts[i + 1], d / seg if seg > 0.0 else 1.0)
			break
		d -= seg
	if f >= 1.0:
		ent.path = null
	host.mission_entity_moved(ent)


## Motion op 16 Path (FUN_0047beef → FUN_0047c4cf): the unit joins the path at its closest point (FUN_0047eb90), goes
## toward the last point (0x852 ≥ 0) or the first (< 0) at a constant speed, the remaining length over the entry's
## duration (the duration variant, 0x884 = −1 on 604 of the 713 Path entries; the current-speed variant, 0x884 ≠ −1,
## is taken the same, UNCERTAIN). Points by arc length (before: equal time per segment, so 115's tanks crossed the
## first long legs at ~100 km/h).
func _path_from(ent: Dictionary, pts: Array, backward: bool, duration: float) -> Dictionary:
	var line: Array = pts.duplicate()
	if backward:
		line.reverse()
	var here: Vector3 = ent.world
	var h := Vector2(here.x, here.y)
	var best := INF
	var at := 0
	var start: Vector3 = line[0]
	for i in line.size() - 1:
		var a := Vector2(line[i].x, line[i].y)
		var b := Vector2(line[i + 1].x, line[i + 1].y)
		var t := clampf((h - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
		var dist := h.distance_to(a.lerp(b, t))
		if dist < best:
			best = dist
			at = i
			start = line[i].lerp(line[i + 1], t)
	var rest: Array = [start] + line.slice(at + 1) if line.size() > 1 else line
	var length := 0.0
	for i in rest.size() - 1:
		length += Vector2(rest[i + 1].x - rest[i].x, rest[i + 1].y - rest[i].y).length()
	return {"points": rest, "start": now, "duration": duration, "length": length}


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


## A unit's current position (world X, Y, altitude): the player's jet, else the unit's position with
## the altitude it stands at (the host snaps ground units to the terrain: "alt").
func _world_of(ent: Dictionary) -> Vector3:
	if ent.player:
		return host.player_world()
	var w: Vector3 = ent.world
	return Vector3(w.x, w.y, ent.get("alt", w.z))


# --- events (§3) -------------------------------------------------------------------------------

## Fire (FUN_004c3425): the counter action runs on every trigger, before the executions and the
## condition are checked (v1.1; v1.0 ran it only when the event fired).
func fire_event(file: int, id: int) -> void:
	var ev: Dictionary = events.get("%d:%d" % [file, id], {})
	if ev.is_empty():
		return
	_counter_action(ev.counter)
	if ev.left <= 0 or not _condition(ev.conds):
		return
	ev.left -= 1
	event_fired.emit(id, ev.name)
	if ev.audio != 0 and ev.audio != -1:
		play_message(ev.audio)
	if ev.debrief != 0 and ev.debrief != -1:
		_add_debrief(file, ev.debrief)
	# Actions (FUN_004c35d6): one whose entity is not found is skipped (v1.1).
	for a in ev.actions:
		var target: Dictionary = entities.get("%d:%d" % [file, int(a[0])], {})
		if target.is_empty():
			continue
		if int(a[1]) != 0 and int(a[1]) != -1:
			_jump(target, 0, int(a[1]))
		if int(a[2]) != 0 and int(a[2]) != -1:
			_jump(target, 1, int(a[2]))


## A condition {0x3de counter id, 0x3d4 operator, 0x3ca value} exists only for a counter id in 1..#counters
## (FUN_004ba32c); cond0 AND cond1, or whichever exists, or none (always true). Operators
## (FUN_004b5e6a): 0 ==, 1 >, 2 <, 3 >=, 4 <=, 5 != (another code: UNCERTAIN, taken as false).
func _condition(conds: Array) -> bool:
	for c in conds:
		var k := int(c.get("0x3de", -1))
		if not counters.has(k):
			continue
		var v: int = counters[k]
		var x := int(c.get("0x3ca", 0))
		var ok: bool
		match int(c.get("0x3d4", -1)):
			0: ok = v == x
			1: ok = v > x
			2: ok = v < x
			3: ok = v >= x
			4: ok = v <= x
			5: ok = v != x
			_: ok = false
		if not ok:
			return false
	return true


## The counter action (cond 2, FUN_004ba4ce): 6 =, 7 +=, 8 -=, 9 --, 10 ++ the value.
func _counter_action(c: Dictionary) -> void:
	var k := int(c.get("0x3de", -1))
	if not counters.has(k):
		return
	var x := int(c.get("0x3ca", 0))
	match int(c.get("0x3d4", -1)):
		6: counters[k] = x
		7: counters[k] += x
		8: counters[k] -= x
		9: counters[k] -= 1
		10: counters[k] += 1


## PlayMessage (FUN_004bb10b): the bdb Audio wav on the speech channel and its subtitle.
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


# --- damage and destruction (docs/damage.md) ------------------------------------------------------
# The unit status (MStatus, entity+0x1c): state 1 alive, 3 fatally hit ("going down"), 4 destroyed,
# 5 exploded; +0x10 the damage fraction 0..1, +0x28 the requested level. The damage object
# (entity+0x10): strength (hit points) and the shield flag (trigger ops 11 / 12).

## A blast at `point` (world X, Y, alt) of `power` within `radius` m: every unit it reaches takes
## FUN_004642f0's share (DamageModel.blast). `source` = the entity that fired (hits need one, as in
## FUN_004a9970); `kind` = "gun" for gun rounds (the player's hit thump), else a weapon / "blast".
## `only` = the unit keys the blast may reach (a gun round's candidate list, docs/weapons.md §3.7);
## null = every unit. Returns the entities it damaged.
func area_damage(point: Vector3, power: float, radius: float, source: Dictionary, kind := "blast", only = null) -> Array:
	var out := []
	for ent in entities.values():
		if ent.state == DamageModel.EXPLODED or ent == source or not ent.damageable:
			continue
		if only != null and not ent.key in only:
			continue
		var dmg := DamageModel.blast(_world_of(ent), ent.size, point, power, radius)
		if dmg > 0.0 and _hit(ent, dmg, source, kind):
			out.append(ent)
	return out


## Direct damage (a hit on the unit itself): `amount` in the same units as a blast's power, i.e.
## compared with the unit's strength (a blast at distance 0).
func apply_damage(target: Dictionary, amount: float, kind: String, source: Dictionary) -> bool:
	if target.is_empty() or not target.damageable or target.state == DamageModel.EXPLODED:
		return false
	return _hit(target, amount, source, kind)


## The end of a release-flag-2 weapon (a script op 2 kill shot, FUN_004d6130 @4d673a): after its blast the target,
## alive or going down, explodes (level 5); the player not when shielded (FUN_0058a350) or Invulnerable.
func scripted_kill(target: Dictionary, source: Dictionary) -> void:
	if target.is_empty() or not int(target.state) in [1, 3]:
		return
	if target.player and (target.shield or host.mission_pref("invulnerable")):
		return
	set_damage_level(target, DamageModel.EXPLODED, source, "script")


## The hit handler (FUN_004a97b0 -> FUN_004642f0 -> FUN_004a9970). Returns true when it counted.
func _hit(ent: Dictionary, dmg: float, source: Dictionary, kind: String) -> bool:
	# The player's jet takes no hits with Invulnerable (pref +0x1c, single player).
	if ent.player and host.mission_pref("invulnerable"):
		return false
	# A unit does not hit itself; the shooter must exist (FUN_004a9970 looks it up).
	if source.is_empty() or source == ent:
		return false
	var old: float = ent.damage
	var new := 0.0
	var kill := false
	if ent.shield:
		# FUN_004642f0: a shielded unit takes nothing, and damage it had is cleared (FUN_005865c0).
		if ent.damage > 0.0:
			ent.damage = 0.0
		return false
	var r := DamageModel.add_damage(old, dmg, ent.strength, _enemy_of_player(ent), host.mission_pref("ai_level"))
	new = r[0]
	kill = r[1]
	if not kill and new - old < DamageModel.MIN_STEP:
		return false
	ent.killer = source
	if kill:
		set_damage_level(ent, DamageModel.EXPLODED, source, kind)
	elif new > 0.0:
		_set_damage(ent, new, -1, source, kind)
	return true


## Sets a unit's damage level (FUN_004a8ae0 with damage 0 and a level): 3 fatally hit, 4 destroyed,
## 5 exploded. Used by trigger op 5 Explode (level 5), the flight model's crash (5), the crash motion's
## ground contact and the weapons later.
func set_damage_level(ent: Dictionary, level: int, source := {}, kind := "") -> void:
	_set_damage(ent, 0.0, level, source, kind)


## FUN_004a8ae0 / FUN_004a8da0: store the damage, derive the requested level (MStatus+0x28, kept
## between calls), run the transition, then the alive-hit reaction.
func _set_damage(ent: Dictionary, damage: float, level: int, source: Dictionary, kind: String) -> void:
	if ent.state == DamageModel.EXPLODED:
		return
	if level >= 1 and level <= 5:
		ent.requested = level
	else:
		var l := DamageModel.level_for(damage)
		if l > 0:
			ent.requested = l
	if damage >= 0.0 and damage <= 1.0:
		ent.damage = damage
	match ent.requested:
		DamageModel.HIT:
			if ent.state == DamageModel.ALIVE:
				ent.state = DamageModel.HIT
				_fatally_hit(ent)
		DamageModel.DESTROYED:
			if ent.state == DamageModel.ALIVE or ent.state == DamageModel.HIT:
				ent.state = DamageModel.DESTROYED
				_destroyed(ent)
		DamageModel.EXPLODED:
			if ent.state == DamageModel.ALIVE or ent.state == DamageModel.HIT:
				ent.state = DamageModel.EXPLODED
				_destroyed(ent)
	if ent.state == DamageModel.ALIVE:
		_damaged_alive(ent, source, kind)


## FUN_004a9c60: a hit that left the unit alive. Controlled aircraft (class 0x1c): the controller's
## hit reaction (FUN_0044d590: the player's shake, thump and systems damage) and the damage smoke
## from 0.25 (checked again 20 s later: it stops unless the damage reached 0.5).
func _damaged_alive(ent: Dictionary, source: Dictionary, kind: String) -> void:
	if ent.klass != 0x1c or ent.damage <= 0.0:
		return
	if ent.player:
		host.mission_player_hit(ent, source, kind)
	if ent.damage >= DamageModel.SMOKE_AT and not ent.smoke_timer and ent.state != DamageModel.EXPLODED \
			and ent.state != DamageModel.DESTROYED:
		ent.smoke_timer = true
		ent.smoke = true
		host.mission_entity_smoke(ent, true)
		# FUN_004a7de0: below 0.5 the smoke stops and the timer handle (+0x48) is cleared, so a later
		# hit can start it again; at 0.5 or more it smokes for good.
		_after(DamageModel.SMOKE_CHECK, func():
			if ent.damage < DamageModel.SMOKE_KEEP_AT:
				if ent.smoke:
					ent.smoke = false
					host.mission_entity_smoke(ent, false)
				ent.smoke_timer = false)


## State 1 -> 3 (FUN_004a8100): the hit event (slot 0, sensor on), control mode 0 (a mission-controlled
## unit's scenario is killed, FUN_004a8e70), the damaged model, and an aircraft goes down (crash
## motion 0x14); the player hears "Eject! Eject!" and loses the controls.
func _fatally_hit(ent: Dictionary) -> void:
	if ent.sensor and ent.alive_scenario:
		fire_event(ent.file, int(_slot(ent, 0).get("0x33e", 0)))
	if ent.mission_ctl:
		ent.alive_scenario = false
	ent.control = 0
	ent.path = null
	# The destruction motion (0x14) replaces the unit's motion (the player's flight model too).
	var w := _world_of(ent)
	var mv: Array = host.mission_unit_motion(ent)  # [angles (pitch, roll, heading), velocity]
	var g = host.mission_ground(w)
	ent.fall = DamageModel.fall_start(ent.klass, w, mv[0], mv[1], g if g != null else 0.0,
			func(): return randi() & 0x7fff)
	ent.fall.t0 = now
	ent.fall.smoked = false
	if ent.fall.timer:
		_after(DamageModel.FALL_CHECK, _fall_tick.bind(ent))
	host.mission_entity_state(ent)


## Per frame: the unit follows its destruction motion (terrain clamp where the terrain is above 0.1 m).
func _fall_update(ent: Dictionary) -> void:
	var r := DamageModel.fall_at(ent.fall, now - ent.fall.t0)
	var p: Vector3 = r[0]
	var g = host.mission_ground(p)
	if g != null and g > 0.1 and p.z < g:
		p.z = g
	ent.fall.pos = p
	ent.fall.angles = r[1]
	if ent.player:
		host.mission_player_fall(p, r[1])
	else:
		ent.world = p
		ent.alt = p.z
		ent.angles = r[1]
		host.mission_entity_moved(ent)


## StopDestructionMotionEvent (FUN_00496c12), every 0.5 s: past its time -> state 5; at 2 m above
## the ground or less -> snapped to the terrain, explosion, state 5; the first tick higher up starts
## the smoke trail (type 2).
func _fall_tick(ent: Dictionary) -> void:
	if ent.fall == null or ent.state != DamageModel.HIT:
		return
	var tau: float = now - ent.fall.t0
	if tau >= ent.fall.T:
		ent.fall = null
		set_damage_level(ent, DamageModel.EXPLODED)
		return
	var p: Vector3 = ent.fall.get("pos", _world_of(ent))
	var g = host.mission_ground(p)
	var agl: float = p.z - (g if g != null else 0.0)
	if agl <= DamageModel.FALL_IMPACT_AGL:
		if g != null and g > 0.1:
			p.z = g
		ent.fall = null
		if not ent.player:
			ent.world = p
			ent.alt = p.z
			host.mission_entity_moved(ent)
		ent.smoke = false
		host.mission_entity_smoke(ent, false)
		set_damage_level(ent, DamageModel.EXPLODED)
		return
	if not ent.fall.smoked:
		ent.fall.smoked = true
		ent.smoke = true
		host.mission_entity_smoke(ent, true)
	_after(DamageModel.FALL_CHECK, _fall_tick.bind(ent))


## State 4 or 5 (FUN_004a8280 / FUN_004a8420 -> FUN_004a86b0): the destroy event (slot 1, sensor on)
## and killScenario, control mode 0, then the final status: the explosion at the unit, its smoke and
## sounds stop, and the role accounting (FUN_00599da0).
func _destroyed(ent: Dictionary) -> void:
	if ent.sensor and ent.alive_scenario:
		fire_event(ent.file, int(_slot(ent, 1).get("0x33e", 0)))
	ent.alive_scenario = false
	ent.path = null
	ent.fall = null
	ent.control = 0
	ent.smoke = false
	host.mission_entity_state(ent)
	_role_rules(ent)


## Explode (trigger op 5) and the flight model's crash: level 5.
func _destroy(ent: Dictionary) -> void:
	set_damage_level(ent, DamageModel.EXPLODED)


## The player's aircraft was destroyed (the flight model's crash: FUN_005bb9f0 -> level 5).
func player_destroyed() -> void:
	var p := player_entity()
	if not p.is_empty():
		set_damage_level(p, DamageModel.EXPLODED)


## The runtime entity the player flies ({} without one).
func player_entity() -> Dictionary:
	for ent in entities.values():
		if ent.player:
			return ent
	return {}


## FUN_004a4cf0 as FUN_004642f0 uses it: a unit not on the player's side (without a player: sides 2 / 3).
func _enemy_of_player(ent: Dictionary) -> bool:
	var p := player_entity()
	if p.is_empty():
		return ent.side == 2 or ent.side == 3
	return ent.side != p.side


## The player ejected (FUN_005485a0, docs/mission-runtime.md §5.4): the player no longer counts as
## alive (control mode 0), so the role rules run at once (role "survive": misc audio 0x4c4, failed)
## and game event 0x82 ends the flight into the debrief 5 s later. The jet itself is not destroyed
## here; its later crash does not run the rules again.
func player_ejected() -> void:
	var p := player_entity()
	if not p.is_empty() and p.control != 0:
		p.control = 0
		_role_rules(p)


## FUN_00599da0 (docs/mission-runtime.md §5.1). Rule 1: when no player is alive any more (state 4 / 5
## or control mode 0), game event 0x82 ends the flight into the debrief 5 s later. Rule 2: the role of
## the unit (0 must survive -> misc audio 0x4c4, failed, box 14 after 10 s; 1 target -> when the last
## one goes, misc audio 0x4ce, passed, box 13 after 10 s).
func _role_rules(ent: Dictionary) -> void:
	if ent.get("accounted", false):
		return
	ent.accounted = true
	if ent.player and not _all_dead:
		_all_dead = true
		_after(ALL_DEAD_DELAY, func(): end_flight.emit(true))
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


## Debrief (FUN_0059a0f0): headline 0x47e if passed else 0x492, then the notes; and the results the pilot
## records keep (docs/front-end.md §13.7): result = passed, bonus = the score file's MissBonus for the mission
## (halved and negative when not passed: trunc(-0.5 · bonus)), and every destroyed unit (state 4 / 5) as
## [type code, class]: on the player's side (side 1 without a player) a loss, otherwise a kill.
func debrief_text(mission_id := -1) -> Dictionary:
	var headline := String(misc.get("0x47e" if passed else "0x492", ""))
	var bonus: int = preload("res://menu/pilots.gd").mission_bonus(mission_id)
	var kills: Array = []
	var losses: Array = []
	var p := player_entity()
	for ent in entities.values():
		if ent.state != DamageModel.DESTROYED and ent.state != DamageModel.EXPLODED:
			continue
		var own: bool = ent.side == 1 if p.is_empty() else ent.side == p.side
		(losses if own else kills).append([ent.type_code, ent.klass])
	return {"passed": passed, "headline": headline, "notes": (debrief_notes[0] + debrief_notes[1]).strip_edges(),
		"result": 1 if passed else 0, "bonus": bonus if passed else int(-0.5 * bonus), "kills": kills, "losses": losses}
