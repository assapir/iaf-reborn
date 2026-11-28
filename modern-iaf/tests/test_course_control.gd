# Phase 6's lessons (modern-iaf/docs/training.md §16.9), headless, for each jet (the Barak at Ramat David, the Sufa at
# Ramon, the Adir at Nevatim):
# - the content resolves as phase 1's (test_course_lessons.gd): the briefing's sections, the Lesson tab, the
#   calls (check ride 6 none), each `called:` a call of the radio menu: the tower's, the AWACS page's, the tanker's;
# - each lesson loads as a lesson and is scored with the course's graded items; the AWACS page holds Check in and Judy,
#   the tanker lessons have their tanker;
# - lesson 6.3 flown from beside the tanker (the jet put in the air there, then held on the boom's stations as
#   test_air_refuel.gd holds it): the check-in ("radar contact"), the vector to the tanker, the request, the door,
#   pre-contact, contact and full; the recording's `tanker` events; its graded items at least Average.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_course_control.gd --log-file <temp> [-- --jet f16i] [-- --load-only]
extends "res://tests/test_mvp.gd"

const UNITS := ["f16d", "f16i", "f35i"]
const GOOD := ["average", "above"]

## The track's speed, m/s (480 kt; tanker.rs).
const SPEED := 246.9
## The room left in the tanks for the boom, kg.
const ROOM := 600.0


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-control-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	settings().language = "en"
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	var sim = load("res://flight/sim_flight.gd")
	var calls: Array = sim.ITEMS.map(func(x): return x[0])
	calls.append_array(sim.AWACS_ITEMS.map(func(x): return "awacs:" + x[0]))
	calls.append("tanker")
	check("checkin" in sim.AWACS_ITEMS.map(func(x): return x[0]), "the AWACS page has Check in")
	check("judy" in sim.AWACS_ITEMS.map(func(x): return x[0]), "the AWACS page has Judy")
	for unit in UNITS:
		if only != "" and unit != only:
			continue
		var course = JSON.parse_string(IafTraining.course(unit))
		var phase: Dictionary = course.phases.filter(func(p): return p.id == "control")[0]
		var ids := _card_ids(unit)
		for le: Dictionary in phase.lessons:
			_content(unit, le, ids, calls)
		for le: Dictionary in phase.lessons:
			await _loads_control(unit, le)
		if not args.has("--load-only"):
			await _refuel(unit)
	Engine.time_scale = 1.0


## The card items of jet `unit`'s card, the lesson-only ones too.
func _card_ids(unit: String) -> Array:
	var s := settings()
	for f in DirAccess.get_files_at(s.readable("res://data/checklists")):
		var d: Dictionary = s.load_json("res://data/checklists/" + f)
		if unit in d.get("jets", []):
			var ids := []
			for sec in d.sections:
				ids.append_array(sec.items.map(func(it): return it.id))
			return ids
	return []


func _content(unit: String, le: Dictionary, ids: Array, calls: Array) -> void:
	var what := "%s %s" % [unit, le.key]
	var text := JSON.stringify(le.briefing) + JSON.stringify(le.lesson_tab)
	for sec in ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]:
		check(le.briefing.get(sec, []).size() > 0, "%s: the briefing's %s" % [what, sec])
	check(not "{jet}" in text and not "{base}" in text, "%s: the jet's and the base's names filled in" % what)
	check(le.lesson_tab is Array and le.lesson_tab.size() > 0, "%s: the notebook's Lesson tab" % what)
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
	check(String(m.get("lesson", "")) == String(le.key), "%s: its mission %s names the lesson" % [what, le.mission])
	check(sim_mission(String(le.mission)) >= 0, "%s: its mission compiled" % what)


func _loads_control(unit: String, le: Dictionary) -> void:
	var what := "%s %s" % [unit, le.key]
	var tv := await _start(String(le.mission))
	var addon: Node = tv.addon
	check(String(addon.rules.get("kind", "")) == "lesson", "%s: loads as a lesson" % what)
	var m: Dictionary = settings().load_json("res://data/missions/%s.json" % le.mission)
	check(
		m.has("tanker") == (String(le.key) in ["control.tanker", "control.night", "control.check"]),
		"%s: its tanker" % what
	)
	await fly(tv, 1.0)
	var d: Dictionary = addon.score()
	check(String(d.get("lesson", "")) == String(le.key), "%s: the record's lesson (%s)" % [what, d.get("lesson")])
	var graded: Array = d.get("graded", [])
	# A check ride grades the items its flight gave occasion for (Course::graded_items): no night or emergency
	# lesson's without the night or the emergency.
	var ride := String(le.kind) == "check"
	var n_ok: bool = (
		graded.size() > 0 and graded.size() <= le.items.size() if ride else graded.size() == le.items.size()
	)
	check(n_ok, "%s: the course's graded items (%d of %d)" % [what, graded.size(), le.items.size()])
	addon.result = {"pass": true}  # not flown on: no sortie logged at the exit


## Lesson 6.3 from beside its tanker: the AWACS's check-in and vector, the tanker's request, the boom to full.
func _refuel(unit: String) -> void:
	var what := "%s control.tanker" % unit
	var tv := await _start("%s_control_tanker" % unit)
	var addon: Node = tv.addon
	Engine.time_scale = 1.0
	var tk: Node = null
	for i in 300:
		tk = tv.get("tanker")
		if tk != null:
			break
		await frames(1)
	check(tk != null, "%s: the mission's tanker in the air" % what)
	if tk == null:
		return
	# The tower's clearances given (the flight is put in the air, not flown there), then the jet 1.5 km behind the
	# tanker, in the air at its speed.
	addon.answers.append_array(["ACFT_CLEAR_TO_START", "ACFT_TAXI_TO_RUNWAY", "ACFT_CLEAR_TO_TAKEOFF"])
	var pose: Dictionary = tk.tk.pose()
	var pos: Vector3 = pose.position - pose.forward * 1500.0 + Vector3(0.0, -150.0, 0.0)
	tv.rig.position = pos
	var s := settings()
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 0), Vector3(SPEED, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.throttle = 0.7
	s.invulnerable = true
	await frames(2)
	var said: Array = addon.awacs_pick("checkin")
	check(said.size() == 1 and String(said[0].template) == "AWX_CHECKIN", "%s: checked in (%s)" % [what, said])
	said = addon.awacs_pick("vector_tanker")
	check(
		said.size() == 1 and String(said[0].text).ends_with("tanker"),
		"%s: the vector to the tanker (%s)" % [what, said]
	)
	addon.request_refuelling()
	var me: int = tk._player_id()
	check(_said(tk, "cleared_precontact", me), "%s: cleared pre-contact (%s)" % [what, tk.said])
	tv._command([296, 1, 0])  # the door open
	tv.flight.set_fuel(float(tv.flight.state().internal_fuel_kg) - ROOM)
	var rc: Vector3 = tv.receptacle()
	check(rc != Vector3.INF, "%s: a receptacle" % what)
	tk.test_player_state = func(dt: float): return _held(tk, rc, dt)
	var full := func(): return _said(tk, "complete", me)
	check(await _until(tv, full, 120.0), "%s: contact and full (%s)" % [what, tk.said])
	tk.test_player_state = null
	tv._command([296, -1, 0])
	s.invulnerable = false
	var d: Dictionary = addon.score()
	var got := {}
	for g in d.get("graded", []):
		got[String(g.id)] = g
	for id in ["tanker_contact_time", "tanker_disconnects", "fuel_taken"]:
		var g: Dictionary = got.get(id, {})
		check(String(g.get("grade", "")) in GOOD, "%s: %s %s (%s)" % [what, id, g.get("grade"), g.get("flown")])
	addon.result = {"pass": true}


func _said(tk: Node, name: String, n: int) -> bool:
	return tk.said.any(func(c): return c[0] == name and int(c[1]) == n)


## The jet held with its receptacle on its station (test_air_refuel.gd's).
func _held(tk: Node, rc: Vector3, dt: float) -> Dictionary:
	var st: Dictionary = tk.tk.station(tk._player_id())
	var p: Dictionary = tk.tk.pose()
	var fwd: Vector3 = Vector3(p.forward.x, 0.0, p.forward.z).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var at: Vector3 = st.get("at", p.position) + p.velocity * dt
	var centre: Vector3 = at
	if String(st.get("kind", "")) == "receptacle":
		centre = at - fwd * rc.x - right * rc.y - Vector3.UP * rc.z
	return {"position": centre, "velocity": p.velocity, "forward": fwd, "right": right, "up": Vector3.UP}
