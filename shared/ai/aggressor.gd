# Ours, Modern IAF's training round against an aggressor F-16 with simulated shots (docs/ai.md §26,
# modern-iaf/docs/training-plan.md §3 phase 7; the rules in Rust: crates/iaf-ai/src/aggressor.rs, IafAggressor). A
# child of the flight scene (terrain_view.gd) made by `start`: by a lesson's mission (its `aggressor`, sim_flight.gd)
# or the dev hook. The aggressor is a jet of the enemy side (a Sufa by default; ai_flights.gd `spawn`) flown by the
# enemy fighter's trees at the High skill's tactics
# (`enemy_flight`), told where the player is ("fight's on": its flight's `vector`). Both jets are shielded: a shot
# between them is simulated. A missile flies unseen and harmless on the existing physical missile (player_weapons.gd
# launch_homing asks `sim_side`; its burst asks `missile_end`); the gun's rounds fly and their hits on the other jet
# count (`gun_hit`). The calls ("Fox", "guns", "kill", "knock it off") are said on the radio: the player's in the
# pilot's voice, the aggressor's ("Red 1") in the wingmen's. After "knock it off" the next set-up starts in the air; a
# lesson's round flies its set-ups once, then the aggressor stays out of the fight and the player flies home. The
# recording gets the round's events for the lesson's grades (training.md §16.11): `fight`, `sim_kill`, `engagement`.
extends Node

const AiFlights := preload("res://shared/ai/ai_flights.gd")
const GunRounds := preload("res://shared/weapons/gun_rounds.gd")
const PLAYER := 0
const AGGRESSOR := 1
## The aggressor's record by default (a Sufa: the aggressors are F-16s) and its skill (2 High: the adversary tactics).
const UNIT := "f16i"
const SKILL := 2
## The calls' words: the player's in the pilot's voice, the aggressor's in the wingmen's (voices.json).
const CALLSIGN := "AGR_RED1"
const PLAYER_WORDS := {
	"fox_1": "PLT_FOX1",
	"fox_2": "PLT_FOX2",
	"fox_3": "PLT_FOX3",
	"guns": "PLT_GUNS",
	"kill": "PLT_KILL",
	"kio": "PLT_KIO",
}
const AGGRESSOR_WORDS := {
	"fox_1": "WNG_FOX1",
	"fox_2": "WNG_FOX2",
	"fox_3": "WNG_FOX3",
	"guns": "WNG_GUNS",
	"kill": "WNG_KILL",
	"kio": "WNG_KIO",
}
## The aggressor speaks in this wingman's Hebrew voice of the flight's cast (sound_table.gd speaker).
const SPEAKER := 2

var host: Node
## The round's rules (Rust).
var rules = ClassDB.instantiate("IafAggressor")
## The aggressor's entity and its IafAi; the set-ups' centre (world) and the player's heading in them (deg).
var jet := {}
var flight = null
var centre := Vector3.ZERO
var heading := 0.0
## The calls said, [from, id] (tests); the kills judged, [shooter side, what: "missile" or "gun"].
var said: Array = []
var kills: Array = []
## The aggressor's stores at its spawn (each engagement starts with them).
var _counts: Array = []
## The round's engagements already recorded (the `engagement` events).
var _logged := 0


## The round on the flight scene `h`, null when none.
static func of(h: Node) -> Node:
	return h.get_node_or_null("Aggressor") if h != null else null


## Ours (docs/ai.md §26; a lesson's mission, or a dev / test hook): a round of `setups` (offensive, defensive,
## high_aspect, bvr; empty: the three BFM ones in turn) round `at` (world), the player heading `hdg` (deg) in them;
## the aggressor spawned and both jets put in the air at the first set-up. `opts`: `unit` (the aggressor's record,
## default UNIT), `arm` (its stores in place of the record's pylons: {station: [weapon name, count]}, ai_flights.gd
## spawn), `once` (a lesson's round: the set-ups flown once). The round, null when the aggressor could not fly.
static func start(h: Node, setups: PackedStringArray, at: Vector3, hdg: float, opts := {}) -> Node:
	var n: Node = of(h)
	if n == null:
		n = load("res://shared/ai/aggressor.gd").new()
		n.name = "Aggressor"
		n.host = h
		h.add_child(n)
	if not n._begin(setups, at, hdg, opts):
		h.remove_child(n)
		n.free()
		return null
	return n


func _begin(setups: PackedStringArray, at: Vector3, hdg: float, opts := {}) -> bool:
	centre = at
	heading = hdg
	rules.start(setups, host.runtime.now, bool(opts.get("once", false)))
	_logged = 0
	var first: Dictionary = IafAggressor.place(rules.setup(), at, hdg).aggressor
	if jet.is_empty():
		var unit := String(opts.get("unit", UNIT))
		jet = host.ai.spawn(unit, first.pos, float(first.heading), [], -1, opts.get("arm", {}))
		if jet.is_empty():
			push_warning("aggressor: no %s to spawn" % unit)
			return false
		var u = host.ai.combat.units.get(jet.key)
		_counts = u.stations.map(func(st): return int(st.count)) if u != null else []
		flight = host.ai.enemy_flight([jet], at, {}, SKILL)
		if flight == null:
			push_warning("aggressor: no enemy flight")
			return false
		host.ai.enemy_flights[-1].vector = _vector
	jet.shield = true
	host.runtime.player_entity().shield = true
	if not _place(rules.setup()):
		return false
	_event({"event": "fight", "state": "on", "setups": Array(setups), "unit": String(opts.get("unit", UNIT))})
	return true


## The engagement of set-up `name` begins: both jets in the air at its starts, their stores full again.
func _place(name: String) -> bool:
	var pl: Dictionary = IafAggressor.place(name, centre, heading)
	if pl.is_empty():
		push_warning("aggressor: no set-up %s" % name)
		return false
	_player_to(pl.player)
	var a: Dictionary = pl.aggressor
	var ai = host.ai.restart_in_air(jet, a.pos, float(a.heading), float(a.speed))
	if ai == null:
		push_warning("aggressor: the jet did not start again in the air")
		return false
	flight = ai
	var u = host.ai.combat.units.get(jet.key)
	if u != null:
		for i in mini(_counts.size(), u.stations.size()):
			u.stations[i].count = _counts[i]
	var w = host.get("weapons")
	if w != null:
		w.stores.reload()
		w._push_stores()
	print("aggressor: set-up %s" % name)
	return true


## The player's jet in the air at `s` ({pos (world), heading, speed}), engine on, gear and flaps up.
func _player_to(s: Dictionary) -> void:
	var pos: Vector3 = host.world_to_scene(s.pos)
	var h := deg_to_rad(float(s.heading))
	host.rig.position = pos
	host.rig.basis = Basis()
	var flags := {
		"airborne": true,
		"engine_on": true,
		"real_data": host.real_data,
		"f16_variant": Settings.f16_variant,
		"f15_variant": Settings.f15_variant,
		"sixdof_data": Settings.sixdof_data()
	}
	var vel := Vector3(sin(h), 0.0, -cos(h)) * float(s.speed)
	host.flight.start(Settings.own_dir(), host.player.fm_section, pos, Vector3(0.0, 0.0, float(s.heading)), vel, flags)
	if host.has_method("_apply_player_prefs"):
		host._apply_player_prefs()
	host.gear_down = false
	host.flaps = 0.0
	host.brakes = false


## The aggressor's "fight's on" (its flight's vector, ai_flights.gd _step_enemy): the player's jet while it is in the
## fight, {} when out.
func _vector() -> Dictionary:
	var me: Dictionary = host.runtime.player_entity()
	if rules.out(PLAYER):
		return {}
	return {"id": me.key, "pos": host.player_world(), "vel": host.ai.combat._velocity_of(me)}


## The round's side of the shooter `owner` (an entity) when its shot at `target` (a key, "" none) is simulated, else
## -1: an air-to-air missile (`type`: 570, 580, 600, 610) of either jet at the other, or at nothing; the player's at
## anything with MASTER ARM at SIMULATE. A shot at another unit (a drone) is live, and so is any other weapon.
func sim_side(owner: Dictionary, target: String, type: int) -> int:
	var side := _side(owner)
	if side < 0 or not type in [570, 580, 600, 610]:
		return -1
	if target == "" or target == _key(1 - side):
		return side
	var w = host.get("weapons")
	return side if side == PLAYER and w != null and w.master_sim else -1


func _side(owner: Dictionary) -> int:
	if jet.is_empty() or owner.is_empty():
		return -1
	if owner.get("player", false):
		return PLAYER
	return AGGRESSOR if String(owner.get("key", "")) == String(jet.key) else -1


func _key(side: int) -> String:
	return String(jet.key) if side == AGGRESSOR else String(host.runtime.player_entity().key)


func _world(side: int) -> Vector3:
	return host.ai.world_of(jet) if side == AGGRESSOR else host.player_world()


## A simulated missile `mis` of `side` launched: its "Fox" call by its guidance (ai_flights.gd FOX).
func launched(mis: RefCounted, side: int) -> void:
	mis.set_meta("engagement", int(rules.score().engagements))
	rules.fox(host.runtime.now, side, AiFlights.FOX.get(int(mis.weapon.get("type", 0)), "fox_2"))


## A simulated missile `mis` ended at `mis.last_pos`: a kill when it burst within its blast of the other jet.
func missile_end(mis: RefCounted) -> void:
	var side := int(mis.get_meta("sim", -1))
	if side < 0:
		return
	# (A missile of an engagement already ended kills nothing: it may still home on the jet at its next set-up.)
	if int(mis.get_meta("engagement", -1)) != int(rules.score().engagements):
		return
	var r := float(mis.weapon.get("radius", 0.0))
	if IafAggressor.missile_kill(mis.last_pos, _world(1 - side), r, mis.dud):
		if rules.missile_hit(host.runtime.now, side):
			_killed(side, "missile")


## A gun round fired by `owner`: "guns" at a burst's first round.
func round_fired(owner: Dictionary) -> void:
	var side := _side(owner)
	if side >= 0:
		rules.round_fired(host.runtime.now, side)


## A gun round of `owner` hit `hit` (the unit it hit, {} none): true when it is the other jet of the round (a
## simulated hit: no damage, no effect), counted towards the gun's kill.
func gun_hit(owner: Dictionary, hit: Dictionary) -> bool:
	var side := _side(owner)
	if side < 0 or hit.is_empty() or String(hit.get("key", "")) != _key(1 - side):
		return false
	if rules.gun_hit(host.runtime.now, side):
		_killed(side, "gun")
	return true


## `side`'s simulated `how` (missile, gun) killed the other jet: counted and recorded.
func _killed(side: int, how: String) -> void:
	kills.append([side, how])
	_event({"event": "sim_kill", "by": "player" if side == PLAYER else "aggressor", "how": how, "setup": rules.setup()})


## A round's event into the flight's recording (terrain_view.gd blackbox_event; docs/blackbox.schema.json).
func _event(e: Dictionary) -> void:
	if host.has_method("blackbox_event"):
		host.blackbox_event(e)


## The player's "knock it off" (the key, command 304): the engagement ends, the next set-up follows.
func knock_it_off() -> bool:
	return rules.knock_it_off(host.runtime.now, PLAYER)


## Whether a lesson's round is over: its set-ups flown, the aggressor out of the fight.
func done() -> bool:
	return rules.done()


## The round's end (the node freed): neither jet shielded or out of a fight any more.
func _exit_tree() -> void:
	if not jet.is_empty():
		jet.shield = false
		jet["out"] = false
	var rt = host.get("runtime") if host != null else null
	if rt != null:
		rt.player_entity().shield = false
		rt.player_entity()["out"] = false


func _process(delta: float) -> void:
	if jet.is_empty() or host.get("runtime") == null or host.get("flight") == null or host.frozen:
		return
	if rules.done():
		return  # a lesson's round over: the aggressor out (and shielded), the player free (_finish)
	var now: float = host.runtime.now
	host.runtime.player_entity()["out"] = rules.out(PLAYER)
	jet["out"] = rules.out(AGGRESSOR)
	var pw: Vector3 = host.player_world()
	var aw: Vector3 = host.ai.world_of(jet)
	var combat = host.ai.combat
	var me: Dictionary = host.runtime.player_entity()
	var w = host.get("weapons")
	if w != null and combat != null:
		var o: Dictionary = w.own()
		var line: Vector3 = GunRounds.shot_dir(o.fwd, o.up)
		var me_gun := {"pos": pw, "vel": o.vel, "line": line, "muzzle": float(w.gun.velocity_jump)}
		rules.track(delta, me_gun, aw, combat._velocity_of(jet))
	var floor_m: float = IafAggressor.floor()
	var low := _agl(pw) < floor_m or _agl(aw) < floor_m
	var r: Dictionary = rules.step(now, pw.distance_to(aw), low)
	for c in r.get("calls", []):
		_say(int(c.from), String(c.id))
	var sc: Dictionary = rules.score()
	var tracked: Array = sc.get("tracked_s", [])
	while _logged < int(sc.get("engagements", 0)):
		var t := float(tracked[_logged]) if _logged < tracked.size() else 0.0
		_event({"event": "engagement", "n": _logged + 1, "tracked_s": snappedf(t, 0.1)})
		_logged += 1
	if rules.done():
		_finish(me)
	elif String(r.get("next", "")) != "":
		_place(String(r.next))


## A lesson's round over: the player back in the world (not shielded, not out), the aggressor out of the fight.
func _finish(me: Dictionary) -> void:
	me.shield = false
	me["out"] = false
	jet["out"] = true
	_event({"event": "fight", "state": "done"})


func _agl(w: Vector3) -> float:
	var g = host.mission_ground(w)
	return w.z - (float(g) if g != null else 0.0)


## The call `id` of `from` on the radio, subtitled: "Kidon 1, Fox two" in the pilot's voice, "Red 1, kill" in the
## wingmen's.
func _say(from: int, id: String) -> void:
	said.append([from, id])
	var radio = host.get("radio")
	if radio == null:
		return
	if from == PLAYER:
		radio.say("WNG_CALL", [radio.formation_name(host.runtime.player_entity()) + "_P", PLAYER_WORDS[id]])
		return
	var table = host.sounds.get("table") if host.get("sounds") != null else null
	if table != null:
		table.speaker = SPEAKER
	radio.say("WNG_CALL", [CALLSIGN, AGGRESSOR_WORDS[id]])
