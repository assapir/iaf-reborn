# Phase 4's lessons (modern-iaf/docs/training.md §16.8), headless, for each jet (the Barak at Ramat David, the Sufa at
# Ramon, the Adir at Nevatim):
# - the content resolves: each lesson's briefing (its eight sections, the names filled in), the notebook's Lesson tab
#   and the instructor's calls (check ride 4 none), every test known, each `called:` a radio call or a flight command,
#   each `lead_order:` an order of the lesson's lead_plan; its mission compiled and naming the lesson;
# - each lesson loads: the lesson's rules, the player's number in the flight (start.seat) with an AI lead, the pairs
#   take-off, the lead's plan taken, the record scored with the course's graded items;
# - lesson 4.2 in the air: the AI lead's line abreast and tac turn said, recorded as lead_order events, the player's
#   `formation` events recorded, the turn swapping the sides.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_formation_lessons.gd --log-file <temp> [-- --jet f16i] [-- --load-only]
extends "res://tests/test_mvp.gd"

const UNITS := ["f16d", "f16i", "f35i"]
const TESTS := [
	"start",
	"idle",
	"aligned",
	"hold_point",
	"lined_up",
	"initial",
	"over_runway",
	"downwind",
	"final_turn",
	"final",
	"touchdown_zone",
	"climb_out",
	"slowed",
	"parked",
	"engine_off",
	"power_off",
	"airborne",
	"in_slot",
	"flight_joined",
	"flight_landed"
]


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-formation-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	settings().language = "en"
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	var sf = load("res://flight/sim_flight.gd")
	var calls: Array = sf.ITEMS.map(func(x): return x[0])
	var commands: Array = (sf.COMMANDS + sf.SHAPES + sf.SPACING).map(func(x): return x[0])
	for unit in UNITS:
		if only != "" and unit != only:
			continue
		var course = JSON.parse_string(IafTraining.course(unit))
		var phase: Dictionary = course.phases.filter(func(p): return p.id == "formation")[0]
		check(phase.lessons.size() == 6, "%s: six formation lessons" % unit)
		for le: Dictionary in phase.lessons:
			_content(unit, le, calls, commands)
		for le: Dictionary in phase.lessons:
			await _loads(unit, le)
		if not args.has("--load-only"):
			await _tac_turn(unit)
	Engine.time_scale = 1.0


func _content(unit: String, le: Dictionary, calls: Array, commands: Array) -> void:
	var key := String(le.key)
	var what := "%s %s" % [unit, key]
	var text := JSON.stringify(le.briefing) + JSON.stringify(le.lesson_tab)
	for s in ["mission", "target", "enemy", "our_forces", "weather_area", "execution", "coordination", "signal"]:
		check(le.briefing.get(s, []).size() > 0, "%s: the briefing's %s" % [what, s])
	check(not "{jet}" in text and not "{base}" in text, "%s: the names filled in" % what)
	check(le.lesson_tab is Array and le.lesson_tab.size() > 0, "%s: the notebook's Lesson tab" % what)
	var check_ride := String(le.kind) == "check"
	check(check_ride == (le.calls == null or le.calls.is_empty()), "%s: calls, none in a check ride" % what)
	var m: Dictionary = settings().load_json("res://data/missions/%s.json" % le.mission)
	var orders: Array = m.get("lead_plan", []).map(func(p): return String(p.order))
	var tests: Array = m.get("training", {}).get("end", []).duplicate()
	for c in le.calls if le.calls is Array else []:
		tests.append_array(c.when)
	for t: String in tests:
		var arg := t.substr(t.find(":") + 1)
		match t.get_slice(":", 0):
			"called":
				var ok := arg in calls or (arg.get_slice(":", 0) in commands and arg.get_slice(":", 1).is_valid_int())
				check(ok, "%s: %s is a radio call or a flight command" % [what, t])
			"lead_order":
				check(arg in orders, "%s: %s is in the lead's plan" % [what, t])
			_:
				check(t in TESTS, "%s: %s is a test" % [what, t])
	for c in m.training.calls:
		var ok: bool = c in calls or (c.get_slice(":", 0) in commands and c.get_slice(":", 1).is_valid_int())
		check(ok, "%s: the mission's call %s" % [what, c])
	check(String(m.get("lesson", "")) == key, "%s: its mission %s names the lesson" % [what, le.mission])
	check(sim_mission(String(le.mission)) >= 0, "%s: its mission compiled" % what)


func _loads(unit: String, le: Dictionary) -> void:
	var what := "%s %s" % [unit, le.key]
	var m: Dictionary = settings().load_json("res://data/missions/%s.json" % le.mission)
	var tv := await _start(String(le.mission))
	var addon: Node = tv.addon
	check(String(addon.rules.get("kind", "")) == "lesson", "%s: loads as a lesson" % what)
	await fly(tv, 1.0)
	var fa = tv.ai.flight_ai
	check(fa != null, "%s: the flight's AI" % what)
	if fa != null:
		var seat := int(m.start.get("seat", 1))
		var me: Dictionary = fa.state(seat)
		check(
			String(me.get("role", "")) == ("lead" if seat == 1 else "wingman"), "%s: the player is #%d" % [what, seat]
		)
		if seat > 1:
			check(String(fa.state(1).get("role", "")) == "lead", "%s: an AI jet leads" % what)
		check(fa.state(int(m.start.count)).size() > 0, "%s: %d jets" % [what, m.start.count])
	var d: Dictionary = addon.score()
	check(String(d.get("lesson", "")) == String(le.key), "%s: the record's lesson (%s)" % [what, d.get("lesson")])
	# (A check ride leaves out the emergency items its emergency gave no occasion for: training.rs emergency_only.)
	var n: int = d.get("graded", []).size()
	var ok: bool = n == le.items.size() if String(le.kind) != "check" else n > 0 and n <= le.items.size()
	check(ok, "%s: the course's graded items (%d of %d)" % [what, n, le.items.size()])
	addon.result = {"pass": true}  # not flown on: no sortie logged at the exit


## Lesson 4.2 put in the air (the dev hooks: the player's jet airborne, the flight behind it): the lead's line abreast
## and its tac turn right, each said and recorded, and the player's `formation` events in the recording.
func _tac_turn(unit: String) -> void:
	var what := "%s formation.tactical in the air" % unit
	var tv := await _start("%s_formation_tactical" % unit)
	var o: Vector3 = tv.player_world()
	var pos: Vector3 = tv.world_to_scene(Vector3(o.x, o.y, o.z + 3000.0))
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(160.0, 0, 0), airborne_flags()
	)
	tv.gear_down = false
	tv.flaps = 0.0
	tv.brakes = false
	tv.throttle = 0.7
	await frames(2)
	check(tv.ai.flight_in_air(90.0), "%s: the flight in the air" % what)
	await fly(tv, 2.0)
	var fa = tv.ai.flight_ai
	check(fa.lead_order(tv.runtime.now, "line_abreast"), "%s: line abreast" % what)
	await fly(tv, 30.0)
	check(String(fa.state(2).shape) == "line_abreast", "%s: the shape" % what)
	check(fa.lead_order(tv.runtime.now, "tac_right"), "%s: tac right" % what)
	await fly(tv, 2.0)
	check(bool(fa.state(2).turning), "%s: the turn under way" % what)
	check(bool(fa.state(2).mirror), "%s: the sides swap" % what)
	var said: Array = tv.ai.flight_calls.map(func(c): return String(c.id))
	check("lead_line_abreast" in said and "lead_tac_right" in said, "%s: the lead's calls (%s)" % [what, said])
	var log := FileAccess.get_file_as_string(tv.blackbox_path)
	check(log.contains('"lead_order"') and log.contains('"tac_right"'), "%s: lead_order recorded" % what)
	check(log.contains('"formation"') and log.contains('"slot_m"'), "%s: the player's slot recorded" % what)
	tv.addon.result = {"pass": true}
