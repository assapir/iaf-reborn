# Phase 3's lessons (modern-iaf/docs/training.md §16.10), headless:
#   - each of the six lessons in each jet (the Barak, the Sufa, the Adir) resolves: its mission compiled into the sim
#     and naming the lesson, the briefing's eight sections in English and Hebrew, the notebook's Lesson tab, the calls
#     (none in the check ride), the graded items with their standards; the instrument lesson's mission brings its
#     weather (the cloud deck, Weather.level);
#   - lesson 3.1's route flown in the Barak and the Sufa: the player's jet put in the air before steerpoint 1 at 15,000
#     ft, the NAV autopilot flies the four steerpoints (standing in for the pilot), and the recording, its autopilot
#     column cleared, is graded by the lesson's items (IafTraining.score): each flown, the steerpoints not
#     Unsatisfactory (the autopilot holds neither the height in its 70°-bank turns nor the plan's 420 kt, so those two
#     are only printed).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_lessons_navigation.gd --log-file <temp>
extends "res://../modern-iaf/tests/instructor_base.gd"

const SECTIONS := ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]
const JETS := ["f16d", "f16i", "f35i"]
## The jets whose route the player's NAV autopilot flies: the F-35I's bleeds to 165 kt in its first turn and stalls
## (the player's autopilot on the Adir's 6-DoF, open in training.md §16.10).
const ROUTE_JETS := ["f16d", "f16i"]
## The route's start: this far before steerpoint 1, m; its altitude (m) and speed (m/s, 420 kt).
const BEFORE_M := 6000.0
const ALT_M := 4572.0
const SPEED := 216.1


func run() -> void:
	if sim_mission("f16i_navigation_steerpoints") < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	var one := OS.get_environment("IAF_SIM_JET")
	for jet in JETS:
		_lessons(jet)
	await _weather()
	for jet in ROUTE_JETS:
		if one == "" or one == jet:
			await _route(jet)


## Jet `jet`'s six phase-3 lessons resolve.
func _lessons(jet: String) -> void:
	var course = JSON.parse_string(IafTraining.course(jet))
	var phase: Dictionary = {}
	for p in course.phases:
		if p.id == "navigation":
			phase = p
	check(phase.get("lessons", []).size() == 6, "%s: six lessons" % jet)
	for l in phase.get("lessons", []):
		var what := "%s %s" % [jet, l.key]
		var m := String(l.mission)
		check(sim_mission(m) >= 0, "%s: mission %s compiled" % [what, m])
		var readable = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions/%s.json" % m))
		check(readable is Dictionary and readable.get("lesson") == l.key, "%s: its mission names the lesson" % what)
		for s in SECTIONS:
			var ps: Array = l.briefing.get(s, [])
			var ok := not ps.is_empty()
			for p in ps:
				ok = ok and String(p.get("en", "")) != "" and String(p.get("he", "")) != ""
			check(ok, "%s: briefing %s in both languages" % [what, s])
		check(not l.lesson_tab.is_empty(), "%s: the Lesson tab" % what)
		var calls: Array = l.calls if l.get("calls") is Array else []
		check(calls.is_empty() == (l.kind == "check"), "%s: %d calls" % [what, calls.size()])
		for c in calls:
			for line in c.lines:
				check(String(line.en) != "" and String(line.he) != "", "%s: call %s's lines" % [what, c.id])
		check(not l.items.is_empty(), "%s: graded items" % what)
		for i in l.items:
			check(i.has("label") and i.has("standard"), "%s: item %s with its standard" % [what, i.get("id")])


## Lesson 3.3's mission brings its heavy rain and cloud deck; the other lessons fly dry.
func _weather() -> void:
	var s := settings()
	for m in ["f16i_navigation_instruments", "f16i_navigation_steerpoints"]:
		var id := sim_mission(m)
		var misc: Array = s.load_json(s.converted(s.missions_folder().path_join("%s.json" % m))).get("misc", {}).get(
			"items", [{}]
		)
		s.mission_weather(id, misc[0] if not misc.is_empty() else {})
		var deck: bool = not load("res://shared/terrain/weather.gd").level().is_empty()
		check(deck == (m.ends_with("instruments")), "%s: the cloud deck %s" % [m, "on" if deck else "off"])
	s.clear_runway_wind()


## Lesson 3.1 in `jet`, its route flown by the NAV autopilot and graded.
func _route(jet: String) -> void:
	var s := settings()
	var id := sim_mission("%s_navigation_steerpoints" % jet)
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	tv.addon.rules = {}  # unscored: the lesson's checks would end the flight once the jet is put in the air
	var sp1: Vector2 = tv.route[0].world
	var last: Vector2 = tv.route[-1].world
	var fwd := Vector2(sp1.x - last.x, sp1.y - last.y).normalized()
	var pos: Vector3 = tv.world_to_scene(Vector3(sp1.x - fwd.x * BEFORE_M, sp1.y - fwd.y * BEFORE_M, ALT_M))
	tv.rig.position = pos
	var hdg := rad_to_deg(atan2(fwd.x, fwd.y))
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), Vector3(SPEED, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.8
	await frames(2)
	tv.flight.ap_set_route(tv._route_points())
	tv.flight.ap_engage(2, 0)
	Engine.time_scale = TIME_SCALE
	var t0: float = tv._sim_time
	var near := false
	while tv._sim_time - t0 < 1500.0 and not tv.flight.state().crashed:
		var w: Vector3 = tv.player_world()
		near = Vector2(w.x - last.x, w.y - last.y).length() < 1500.0
		if near:
			break
		await process_frame
	Engine.time_scale = 1.0
	check(near and not tv.flight.state().crashed, "%s: the route flown to steerpoint 4" % jet)
	await frames(30)
	tv._log.flush()
	var path := _pilot_flown(ProjectSettings.globalize_path(tv._log.get_path_absolute()))
	var trainer: RefCounted = ClassDB.instantiate("IafTraining")
	var d = JSON.parse_string(trainer.score(path, tv.addon._readable(), s.disk_path("res://data/airbases")))
	check(d is Dictionary and not d.has("error"), "%s: scored %s" % [jet, d.get("error", "") if d is Dictionary else d])
	if not d is Dictionary:
		return
	var graded: Array = d.get("graded", [])
	check(graded.size() == 3, "%s: three items" % jet)
	for g in graded:
		print("%s %s: flown %s, gap %s, %s" % [jet, g.id, g.flown, g.gap, g.grade])
		check(g.flown != null, "%s: %s flown" % [jet, g.id])
		if g.id == "steerpoint_miss":
			check(String(g.grade) != "unsat", "%s: %s graded %s" % [jet, g.id, g.grade])


## A copy of the recording `path` with its autopilot column cleared: the route the autopilot flew, graded as the
## pilot's.
func _pilot_flown(path: String) -> String:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var head = JSON.parse_string(lines[0])
	var k: int = head.columns.find("ap_mode")
	var out := PackedStringArray([lines[0]])
	for l in lines.slice(1):
		var v = JSON.parse_string(l) if l != "" else null
		if v is Array and k >= 0:
			v[k] = 0
			l = JSON.stringify(v)
		out.append(l)
	var copy := path.get_basename() + "-pilot.jsonl"
	var f := FileAccess.open(copy, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	return copy
