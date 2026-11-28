# Modern IAF's training round against an aggressor with simulated shots (docs/ai.md §26), headless on the Sufa's
# weapons range: the dev hook shared/ai/aggressor.gd `start` puts the player and an aggressor Sufa in the air at the
# set-ups (no lesson places one yet). The player flies straight on ALT HOLD and HDG SEL.
#   - defensive: the aggressor 3,000 ft behind, both shielded; it shoots, its shot is simulated (no model, nothing
#     hurt), "Red 1, Fox" or "guns", "Red 1, kill", the player out of the fight, "knock it off", the next set-up;
#   - offensive: the player 3,000 ft behind; the player's missile at the aggressor simulated ("Kidon 1, Fox two",
#     no model), its burst judged: "Kidon 1, kill", the aggressor out (no bandit, no vector);
#   - the player's "knock it off" (command 304) ends the high-aspect engagement and the next set-up follows;
#   - the rule of which shot is simulated: a shot at a drone is live with MASTER ARM at ARM, simulated at SIMULATE.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_aggressor.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0

var tv: Node
var agg: Node


## Flies until `f` holds, at most `s` s of sim time; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await process_frame
	return f.call()


## The player's jet on ALT HOLD and HDG SEL (after each set-up's new flight-model start).
func _straight() -> void:
	tv._command([292, 0, 1])
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])


func _said(from: int, id: String) -> bool:
	return agg.said.any(func(c): return c[0] == from and c[1] == id)


func _heard(text: String) -> bool:
	return tv.radio.said.any(func(p): return String(p.template) == "WNG_CALL" and String(p.text).contains(text))


func run() -> void:
	await require_data()
	var s := settings()
	s.language = "en"
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-aggressor", false).get_current_dir()
	tv.addon.rules = {}  # unscored: the set-ups move the jet
	var j: Vector3 = tv.player_world()
	var at := Vector3(j.x, j.y + 20000.0, 0.0)
	agg = load("res://shared/ai/aggressor.gd").start(
		tv, PackedStringArray(["defensive", "offensive", "high_aspect"]), at, 0.0
	)
	check(agg != null and not agg.jet.is_empty(), "the round and its aggressor Sufa")
	if agg == null:
		return
	await frames(2)
	_straight()
	var me: Dictionary = tv.runtime.player_entity()
	var pw: Vector3 = tv.player_world()
	var aw: Vector3 = tv.ai.world_of(agg.jet)
	var gap := pw.distance_to(aw)
	check(absf(gap - 914.4) < 60.0 and aw.y < pw.y, "defensive: the aggressor 3,000 ft behind (%.0f m)" % gap)
	check(agg.jet.shield and me.shield, "both jets shielded")
	check(agg.jet.pilot.by_ai and agg.flight != null, "the aggressor flown by the enemy trees")
	# --- Defensive: the aggressor's shot, simulated; the kill; knock it off; the next set-up.
	Engine.time_scale = TIME_SCALE
	var shot := func(): return _said(1, "fox_1") or _said(1, "fox_2") or _said(1, "fox_3") or _said(1, "guns")
	check(await _until(shot, 90.0), "the aggressor shoots (%s)" % [agg.said])
	var live: Array = tv.weapons.missiles.filter(func(m): return is_same(m.get_meta("owner", {}), agg.jet))
	check(live.all(func(m): return m.has_meta("sim") and not m.has_meta("node")), "its missile flies unseen")
	check(await _until(func(): return _said(1, "kill"), 90.0), "Red 1 calls kill (%s)" % [agg.said])
	check(_heard("Red 1, kill"), "said and subtitled: Red 1, kill")
	check(int(me.state) < 3 and me.get("out", false), "the player out of the fight, not hurt (state %d)" % me.state)
	var ids: Array = tv.ai._bandits(int(agg.jet.side)).map(func(b): return int(b.id))
	check(not tv.ai._bandit_id(me) in ids, "the aggressor has the player no more as a bandit")
	check(await _until(func(): return _said(1, "kio"), 10.0), "Red 1 calls knock it off")
	check(await _until(func(): return agg.rules.setup() == "offensive", 15.0), "the next set-up: offensive")
	await frames(2)
	_straight()
	# --- Offensive: the player's shot at the aggressor, simulated, judged at its burst.
	pw = tv.player_world()
	aw = tv.ai.world_of(agg.jet)
	check(absf(pw.distance_to(aw) - 914.4) < 60.0 and pw.y < aw.y, "offensive: the player 3,000 ft behind")
	check(not me.get("out", false) and not agg.jet.get("out", false), "both in the fight again")
	# Its weapons taken off for this engagement: the player's shot is the one judged.
	var u = tv.ai.combat.units.get(agg.jet.key)
	for st in u.stations:
		st.count = 0
	var w = tv.weapons
	var ir: Dictionary = {}
	for i in 9:
		var st: Dictionary = w.stores.station(i)
		if int(st.get("count", 0)) > 0 and int(st.w.get("type", 0)) in [570, 580]:
			ir = st.w
	check(not ir.is_empty(), "the Sufa's infrared missile")
	if ir.is_empty():
		return
	var said0: int = agg.said.size()
	var mis = w.launch_homing(ir, pw, w.own(), String(agg.jet.key), 1.0, w._me())
	check(mis.has_meta("sim") and not mis.has_meta("node"), "the player's missile flies unseen")
	check(not w.rwr.missiles.any(func(e): return e.missile.id == mis.get_meta("id")), "no launch warning")
	await frames(1)
	check(_said(0, "fox_2") and _heard("Kidon 1, fox two"), "Kidon 1, Fox two")
	check(await _until(func(): return agg.kills.any(func(k): return k[0] == 0), 30.0), "its burst a kill")
	check(int(agg.jet.state) < 3, "the aggressor not hurt")
	check(await _until(func(): return agg.said.slice(said0).has([0, "kill"]), 5.0), "Kidon 1 calls kill")
	check(agg.jet.get("out", false), "the aggressor out of the fight")
	check(await _until(func(): return agg.rules.setup() == "high_aspect", 20.0), "the next set-up: high aspect")
	await frames(2)
	_straight()
	# --- The player's knock it off.
	tv._command([304, 0, 0])
	await frames(1)
	check(_said(0, "kio") and _heard("Kidon 1, knock it off"), "Kidon 1, knock it off (the key)")
	check(await _until(func(): return agg.rules.setup() == "defensive", 10.0), "the next set-up after it")
	Engine.time_scale = 1.0
	# --- Which shot is simulated: the player's at a drone is live at ARM, simulated at SIMULATE; the jets' at each
	# other always.
	w.master_arm = true
	check(agg.sim_side(w._me(), "drone:1", 580) == -1, "at ARM a shot at a drone is live")
	check(agg.sim_side(w._me(), String(agg.jet.key), 580) == 0, "a shot at the aggressor is simulated")
	check(agg.sim_side(agg.jet, String(me.key), 580) == 1, "the aggressor's shot at the player is simulated")
	w.master_sim = true
	check(
		agg.sim_side(w._me(), "drone:1", 580) == 0 and w._may_fire(),
		"at SIMULATE every air-to-air shot is simulated, and fires"
	)
	var sc: Dictionary = agg.rules.score()
	print("aggressor: %d engagements, kills %s, calls %s" % [sc.engagements, sc.kills, agg.said])
	check(int(sc.engagements) == 3 and sc.kills == [1, 1], "three engagements, a kill each")
