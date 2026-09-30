## The AI brain (MBrain, docs/ai.md §2–§6): a bdb rule list walked every period; the first rule that fires
## per action type wins the tick, a rule with the stop flag (0x1ae = 0) ends it, sub-brains switch the list.
## Manoeuvres go to the pilot's autopilot (`pilot.set_mode`); combat actions are hooks for the combat job.
extends RefCounted

## Controlled aircraft (class 0x1c): period code 0x1cc = 2 s; others 480 = 4 s (FUN_004404d0).
const PERIOD_AIRCRAFT := 2.0
const PERIOD_DEFAULT := 4.0
## Single player, enemies of the player: ×2 Rookie, ×1.5 Normal (0x6007a0), ×1 Expert.
const SKILL_PERIOD := [2.0, 1.5, 1.0]
const MAX_LOOPS := 10
## Knots per m/s in condition 6 / 12 (0x612690).
const KT := 1.9427955
## Condition codes whose measure is a bool (compared as bools by op 0).
const BOOL_CODES := [0, 1, 2, 8, 18, 19, 20, 22, 23, 25, 26, 27, 28, 31, 32, 34, 37, 38, 39]
## Codes whose constant keeps the float value (else ftol).
const FLOAT_CONST := [9, 13, 24]

## Manoeuvre code (bdb action 0xbe) → autopilot mode (§5). Codes marked T need a target.
const MANOEUVRES := {100: 0xb, 110: 0xd, 120: 0xe, 130: 0xf, 140: 0x11, 150: 0x10, 160: 0x12, 170: 0x13,
	180: 0x14, 190: 1, 200: 3, 210: 0x18, 220: 0x16, 230: 10, 240: 7, 250: 8, 270: 8, 280: 9, 290: 0x17}
const NEEDS_TARGET := [110, 120, 130, 140, 150, 160, 170, 180, 210, 220, 290]

var ent: Dictionary  # the mission runtime entity
var pilot  # ai_flights.gd pilot record: set_mode(mode, arg), waypoint index, flight state, landed
var host  # ai_flights.gd
var base_rules: Array = []  # [{stop, conds: [[code, op, value]], acts: [[id, audio, delay]]}]
var rules: Array = []
var in_sub := false
var switched := false
var period := PERIOD_AIRCRAFT
var next_tick := 0.0
var ticking := false
var done := {}  # action types run this tick
## +0x44 leader (partner), +0x48 wingman command, +0x68 engaged, +0x6c combat disabled, +0x70 target,
## +0x74 primary target.
var leader: Dictionary = {}
var wingman_command := 0
var engaged := false
var combat_disabled := false
var target: Dictionary = {}
var primary: Dictionary = {}


## Rule list of a bdb brain item (FUN_00595060: 0x208 ? rules0 : rules1).
static func rules_of(item: Dictionary) -> Array:
	var out := []
	var list: Array = item.get("rules0" if int(item.get("0x208", 0)) != 0 else "rules1", {}).get("items", [])
	for r in list:
		var conds := []
		for c in r.get("list16", []):
			conds.append([int(c[1]), int(c[2]), float(c[3])])
		var acts := []
		for a in r.get("list20", []):
			if int(a[2]) != -1:
				acts.append([int(a[2]), int(a[3]), float(a[4])])
		out.append({"stop": int(r.get("0x1ae", 0)) == 0, "conds": conds, "acts": acts})
	return out


func setup(h, e: Dictionary, p, brain_rules: Array, aircraft: bool) -> void:
	host = h
	ent = e
	pilot = p
	base_rules = brain_rules
	rules = base_rules
	period = PERIOD_AIRCRAFT if aircraft else PERIOD_DEFAULT


## reset (FUN_0043eef0): flags cleared (not "combat disabled", not the waypoint index), the leader and the
## primary target found again, the period set, the tick scheduled now if it is not.
func reset(now: float) -> void:
	done.clear()
	wingman_command = 0
	engaged = false
	target = {}
	leader = host.partner_of(ent)
	primary = host.member_target(ent)
	period = (PERIOD_AIRCRAFT if ent.klass == 0x1c else PERIOD_DEFAULT) * host.skill_period_factor(ent)
	if not rules.is_empty() and not ticking:
		ticking = true
		next_tick = now


## transferControl (FUN_004401d0): the tick stops, weapons safe, the autopilot off, back to the base list.
func transfer_control() -> void:
	ticking = false
	engaged = false
	pilot.set_mode(0)
	rules = base_rules
	in_sub = false


func update(now: float) -> void:
	while ticking and now >= next_tick:
		next_tick += period
		tick(now)


## One evaluation (FUN_00442120).
func tick(now: float) -> void:
	var loops := 0
	var i := 0
	done.clear()
	while i < rules.size():
		var r: Dictionary = rules[i]
		if _fires(r):
			for a in r.acts:
				_run(a, now)
			if switched:
				switched = false
				done.clear()
				loops += 1
				if loops == MAX_LOOPS:
					push_warning("Brain is in loop forever - stop the brain!!! (%s)" % ent.name)
					transfer_control()
					break
				i = 0
				continue
			if r.stop:
				break
		i += 1
	done.clear()


## AND of the rule's conditions; no condition, an unknown code (> 39) or op (∉ 0..5): never.
func _fires(r: Dictionary) -> bool:
	if r.conds.is_empty():
		return false
	for c in r.conds:
		if c[0] < 0 or c[0] > 39 or c[1] < 0 or c[1] > 5:
			return false
		if not _test(c[0], c[1], c[2]):
			return false
	return true


func _test(code: int, op: int, value: float) -> bool:
	var m = measure(code)
	var k := value if code in FLOAT_CONST else float(int(value))
	if op == 0:
		if code in BOOL_CODES:
			return bool(m if m != null else 0) == bool(int(k))  # UNCERTAIN: invalid taken as 0
		return m != null and float(m) == k
	if m == null:
		return false
	var l := float(m)
	match op:
		1: return l > k
		2: return l < k
		3: return l >= k
		4: return l <= k
		_: return l != k


func _alive(e: Dictionary) -> bool:
	return not e.is_empty() and not (int(e.state) in [4, 5])


## A condition's measure (§4); null = invalid. The combat-only measures are null until the combat job.
func measure(code: int) -> Variant:
	var st: Dictionary = pilot.state()
	match code:
		0:
			return 1
		1:
			return null if target.is_empty() else int(target.klass in [2, 3, 0x1c])
		2:
			return null if target.is_empty() else int(target == primary)
		4:
			return st.position_world.z
		5:
			return wrapf(float(st.heading), -180.0, 180.0)
		6:
			return float(st.speed) * KT
		7:
			return st.g
		9:
			return null if target.is_empty() else host.world_of(target).z
		11:
			return null if target.is_empty() else float(target.get("heading", 0.0))
		13:
			return null if not _alive(target) else host.world_of(target).distance_to(st.position_world)
		15:
			return randi() % 101
		16:
			return null if target.is_empty() else st.position_world.z - host.world_of(target).z
		18:
			return null if target.is_empty() else int(st.position_world.z < host.world_of(target).z)
		22:
			return null if leader.is_empty() else int(not _alive(leader))
		23:
			return null if leader.is_empty() else int(host.on_ground(leader))
		24:
			return null if primary.is_empty() else host.world_of(primary).distance_to(st.position_world)
		25:
			return null if primary.is_empty() else int(not _alive(primary))
		29:
			return wingman_command
		30:
			return pilot.waypoint_action()
		31:
			return null if target.is_empty() else int(host.engaged(target))
		32:
			return null if target.is_empty() else int(not _alive(target))
		33:
			return pilot.waypoint_index()
		34:
			return null if target.is_empty() else int(target.player)
		35:
			return pilot.fuel_ratio()
		36:
			return float(ent.damage) * 100.0
	return null  # 3, 8, 10, 12, 14, 17, 19–21, 26–28, 37–39: combat job (UNCERTAIN sensors)


## One action: type gate (5, 6 never marked; sub-brains never gated), its effect, its audio.
func _run(a: Array, now: float) -> void:
	var id: int = a[0]
	if id == 1000:
		_sub_brain(a[1])
		return
	var act: Dictionary = host.action(id)
	var code := int(act.get("0xbe", -1))
	var type := _type_of(code)
	var gated := type >= 0 and type != 5 and type != 6 and code != 390
	if not (gated and done.has(type)):
		if gated:
			done[type] = true
		_exec(code)
	if a[1] != 0 and a[1] != -1:
		host.play_audio(ent, a[1], a[2])


static func _type_of(code: int) -> int:
	if code >= 100 and code <= 290:
		return 0
	match code:
		300: return 1
		310: return 2
		320: return 3
		330, 340, 350, 360, 370, 380, 390: return 4
		400, 410, 420: return 5
		430, 440: return 6
		550, 560: return 8
	if code >= 450 and code <= 540:
		return 7
	return -1


func _exec(code: int) -> void:
	if MANOEUVRES.has(code):
		if code in NEEDS_TARGET and target.is_empty():
			return  # a combat manoeuvre without a target: combat job
		if (code == 250 or code == 280) and pilot.landed:
			return  # 443c90 / 443f60 refuse after a landing (ctl+0xe0)
		var mode: int = MANOEUVRES[code]
		var arg = leader if code in [190, 200] else (target if code in NEEDS_TARGET else ent)
		pilot.set_mode(mode, arg)
		if code == 270 and not leader.is_empty():
			host.landed_handler(ent)
		return
	match code:
		260:
			pilot.set_waypoint_index(1)
		550:
			if not engaged and not combat_disabled and _alive(target):
				engaged = true
				host.combat_hook(ent, "start", target)
		560:
			if engaged:
				engaged = false
				host.combat_hook(ent, "stop", target)
		_:
			host.combat_hook(ent, str(code), target)  # launch, flares, chaff, weapons, targets, radar


## Sub-brain (FUN_00444cc0): the list of brain `id`, or back to the base list for 0 / -1 / unknown; the
## wingman command is consumed.
func _sub_brain(id: int) -> void:
	var list: Array = host.brain_rules(id)
	if list.is_empty():
		rules = base_rules
		in_sub = false
	else:
		rules = list
		in_sub = true
	wingman_command = 0
	switched = true


## Trigger op 22 (FUN_004407e0).
func disable_combat() -> void:
	combat_disabled = true
	if engaged:
		engaged = false
		host.combat_hook(ent, "safe", target)
		transfer_control()


## Trigger op 21 (FUN_00440830).
func enable_combat(now: float) -> void:
	combat_disabled = false
	reset(now)
