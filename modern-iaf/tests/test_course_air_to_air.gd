# Phase 7's lessons (Air-to-air, modern-iaf/docs/training.md §16.11), headless, for each jet (the Barak at Ramat
# David, the Sufa at Ramon, the Adir at Nevatim):
# - the content resolves: each lesson's briefing (its eight sections, the names filled in), the Lesson tab, its
#   diagrams (each one a step or a paragraph names), the calls (check ride 7 none), every `called:` a radio call or an
#   AWACS request; its mission compiled, naming the lesson, its round (`sim.aggressor`) or drones there;
# - each lesson loads as a lesson and its record holds the course's graded items;
# - offensive BFM flown by a script: the jet put in the air at steerpoint 2, the round starts by itself ("fight's
#   on"), three engagements each won by a simulated missile with a gun track before it, then the round over and the
#   recording's items graded: every target shot down, never shot down, the gun's tracking time.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_course_air_to_air.gd --log-file <temp> [-- --jet f16i] [-- --load-only]
extends "res://tests/test_course_lessons.gd"

const GunRounds := preload("res://shared/weapons/gun_rounds.gd")
const PHASE := "air_to_air"
const SETUPS := 3


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-a2a-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	settings().language = "en"
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	var sf: GDScript = load("res://flight/sim_flight.gd")
	var calls: Array = sf.ITEMS.map(func(x): return x[0])
	calls.append_array(sf.AWACS_ITEMS.map(func(x): return "awacs:" + x[0]))
	for unit in UNITS:
		if only != "" and unit != only:
			continue
		var course = JSON.parse_string(IafTraining.course(unit))
		var lessons: Array = course.phases.filter(func(p): return p.id == PHASE)[0].lessons
		check(lessons.size() == 7, "%s: phase 7's seven lessons" % unit)
		var ids := _card_ids(unit)
		for le: Dictionary in lessons:
			_a2a_content(unit, le, ids, calls)
		for le: Dictionary in lessons:
			await _a2a_loads(unit, le)
		if not args.has("--load-only"):
			await _fly_bfm(unit)
	Engine.time_scale = 1.0


func _a2a_content(unit: String, le: Dictionary, ids: Array, calls: Array) -> void:
	var key := String(le.key)
	var what := "%s %s" % [unit, key]
	var text := JSON.stringify(le.briefing) + JSON.stringify(le.lesson_tab)
	for s in ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]:
		check(le.briefing.get(s, []).size() > 0, "%s: the briefing's %s" % [what, s])
	check(not "{jet}" in text and not "{base}" in text, "%s: the jet's and the base's names filled in" % what)
	check(le.lesson_tab is Array and le.lesson_tab.size() > 0, "%s: the notebook's Lesson tab" % what)
	var named := []
	for p in le.briefing.execution + le.lesson_tab:
		if p.has("diagram") and not p.diagram in named:
			named.append(p.diagram)
	var diagrams: Dictionary = le.get("diagrams", {}) if le.get("diagrams") is Dictionary else {}
	check(named.size() > 0 and named.all(func(d): return diagrams.has(d)), "%s: its diagrams %s" % [what, named])
	var check_ride := String(le.kind) == "check"
	check(check_ride == (le.calls == null or le.calls.is_empty()), "%s: calls, none in a check ride" % what)
	var m: Dictionary = settings().load_json("res://data/missions/%s.json" % le.mission)
	var tests: Array = m.get("training", {}).get("end", []).duplicate()
	for c in le.calls if le.calls is Array else []:
		tests.append_array(c.when)
	for t: String in tests:
		var arg := t.substr(t.find(":") + 1)
		match t.get_slice(":", 0):
			"item":
				check(arg in ids, "%s: %s is a card item" % [what, t])
			"called":
				check(arg in calls, "%s: %s is a radio call" % [what, t])
	for i in m.training.checklist:
		check(i in ids, "%s: the mission's %s is a card item" % [what, i])
	check(String(m.get("lesson", "")) == key, "%s: its mission %s names the lesson" % [what, le.mission])
	var id := sim_mission(String(le.mission))
	check(id >= 0, "%s: its mission compiled" % what)
	var s := settings()
	var sim: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(String(le.mission) + ".json")).get(
		"sim", {}
	)
	check(
		sim.has("aggressor") == m.has("aggressor") and (m.has("aggressor") or m.has("drones")),
		"%s: its round or its drones (%s)" % [what, sim.get("aggressor", {}).get("setups")]
	)


func _a2a_loads(unit: String, le: Dictionary) -> void:
	var what := "%s %s" % [unit, le.key]
	var tv := await _start(String(le.mission))
	var addon: Node = tv.addon
	check(String(addon.rules.get("kind", "")) == "lesson", "%s: loads as a lesson" % what)
	await fly(tv, 1.0)
	var d: Dictionary = addon.score()
	check(String(d.get("lesson", "")) == String(le.key), "%s: the record's lesson (%s)" % [what, d.get("lesson")])
	if String(le.kind) != "check":
		check(d.get("graded", []).size() == le.items.size(), "%s: the course's graded items" % what)
	addon.result = {"pass": true}  # not flown on: no sortie logged at the exit


## Offensive BFM by a script: the tower's clearances given, the jet in the air at steerpoint 2; the round starts by
## itself; in each engagement 2 s of gun track, then a simulated missile from 3,000 ft behind kills Red 1.
func _fly_bfm(unit: String) -> void:
	var what := "%s offensive BFM" % unit
	var name := "%s_%s_offensive_bfm" % [unit, PHASE]
	var tv := await _start(name, true)  # the lesson's fixed load (fly.gd arm)
	var addon: Node = tv.addon
	addon.answers = ["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY", "ACFT_CLEAR_TO_TAKEOFF"]
	var a: Array = addon._aggressor_spec.at
	var at := Vector3(float(a[0]), float(a[1]) + 5000.0, 4600.0)
	var cfg := settings()
	var flags := {
		"airborne": true,
		"engine_on": true,
		"real_data": tv.real_data,
		"f16_variant": cfg.f16_variant,
		"f15_variant": cfg.f15_variant,
		"sixdof_data": cfg.sixdof_data()
	}
	tv.rig.position = tv.world_to_scene(at)
	tv.flight.start(cfg.own_dir(), tv.player.fm_section, tv.rig.position, Vector3.ZERO, Vector3(0, 0, -230), flags)
	tv.gear_down = false
	check(await _until(tv, func(): return tv.get_node_or_null("Aggressor") != null, 10.0), "%s: fight's on" % what)
	var agg: Node = tv.get_node_or_null("Aggressor")
	if agg == null:
		return
	check(agg.rules.setup() == "offensive" and not agg.jet.is_empty(), "%s: the offensive set-up, Red 1 up" % what)
	var w = tv.weapons
	for n in SETUPS:
		await frames(2)
		var u = tv.ai.combat.units.get(agg.jet.key)
		for st in u.stations:
			st.count = 0  # Red 1 unarmed: the player's shot is the one judged
		var v := Vector3(0, 200, 0)
		var muzzle := float(w.gun.velocity_jump)
		var t: float = GunRounds.real_time_of_flight(muzzle, 600.0, 5000.0)
		var lead := Vector3(0, 600, 0.5 * 9.81 * t * t)
		var own := {"pos": Vector3(0, 0, 5000), "vel": v, "line": lead, "muzzle": muzzle}
		agg.rules.track(2.0, own, Vector3(0, 600, 5000), v)
		var ir: Dictionary = {}
		for i in w.stores.stations:
			var st: Dictionary = w.stores.station(i)
			if int(st.get("count", 0)) > 0 and int(st.w.get("type", 0)) in [570, 580]:
				ir = st.w
		check(not ir.is_empty(), "%s: an infrared missile for engagement %d" % [what, n + 1])
		if ir.is_empty():
			return
		w.launch_homing(ir, tv.player_world(), w.own(), String(agg.jet.key), 1.0, w._me())
		var k0 := n
		check(
			await _until(tv, func(): return agg.kills.filter(func(k): return k[0] == 0).size() > k0, 30.0),
			"%s: engagement %d won" % [what, n + 1]
		)
		if n + 1 < SETUPS:
			check(
				await _until(tv, func(): return int(agg.rules.score().engagements) == k0 + 1, 15.0),
				"%s: the next set-up" % what
			)
	check(await _until(tv, func(): return agg.done(), 15.0), "%s: the round over after three" % what)
	await fly(tv, 1.0)
	var d: Dictionary = addon.score()
	var graded: Dictionary = {}
	for g in d.get("graded", []):
		graded[String(g.id)] = g
	for id in ["targets_killed", "times_killed", "tracking_time"]:
		var g: Dictionary = graded.get(id, {})
		check(String(g.get("grade", "")) in GOOD, "%s: %s %s (%s)" % [what, id, g.get("grade"), g.get("flown")])
	addon.result = {"pass": true}
	Engine.time_scale = 1.0
