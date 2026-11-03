# The MVP probe (iaf-2026/docs/plan.md, item F; started by item E3b): IAF 2026's two training missions flown headless
# for each MVP jet (the Sufa at Ramon, the Barak at Ramat David, the F-35I at Nevatim) with scripted inputs, each
# ending in a Pass from the run-time scoring (iaf-2026/docs/training.md §7–§9):
# - start-up: parked cold (no RPM, no power), the throttle starts nothing, the start command runs the sequence, the
#   displays come up, the engine idles; the recorder's RPM / avionics columns; the debrief record and the pilot log;
# - take-off: the radio menu's three requests answered by the base's tower, a taxi along the base's taxi path
#   (the own iaf.ibx) to the lineup, the roll, the rotation, gear up on the runway heading.
# Still open for item F: the front end's part (E2), Hebrew, the run on a root that holds only the sim's files, macOS
# and Windows.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 \
#     -s ../iaf-2026/tests/test_mvp.gd --log-file <temp> [-- --jet f16i] [-- --only startup|takeoff]
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/iaf-2026/missions"
## airframe id -> [the jet, its base's missions' prefix, its iaf.ibx section]
const JETS := {
	"f16i": ["Sufa", "ramon", "Ramon"],
	"f16": ["Barak", "ramat_david", "David"],
	"f35i": ["F-35I", "nevatim", "Nevatim"],
}
## The probe's clock: the sim runs this much faster than the frames (time compression, as the C key).
const TIME_SCALE := 6.0
## The taxi: speed (m/s), slower within TURN_M of a turn; a point is passed within REACH_M.
const TAXI_MS := 10.0
const TURN_MS := 4.0
const TURN_M := 40.0
const REACH_M := 12.0
## The take-off: rotation speed (kt) per jet (about the mission's reference speed less 10 kt: training.md §3), the
## climb's pitch.
const ROTATE_KT := {"f16i": 155.0, "f16": 140.0, "f35i": 160.0}
const CLIMB_PITCH := 10.0

var out := ""
var fly_gd: GDScript


## The sim's own data (./iaf2026-setup), not the original's install.
func require_data() -> void:
	if DirAccess.dir_exists_absolute(settings().own_dir().path_join("resource")):
		return
	print("NEEDS DATA: IAF 2026's own data (./iaf2026-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("iaf2026-mvp-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--only") + 1] if args.has("--only") else ""
	var jet := args[args.find("--jet") + 1] if args.has("--jet") else ""
	for id in JETS:
		if jet != "" and id != jet:
			continue
		if only != "takeoff":
			await startup(id)
		if only != "startup":
			await takeoff(id)
	Engine.time_scale = 1.0


func _start(name: String) -> Node:
	var s := settings()
	var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(name + ".json"))
	fly_gd.set_jet(m)
	s.mission_files_override = [{"name": name, "data": m}]
	Engine.time_scale = 1.0
	var tv: Node = await start_mission(int(m.sim.menu_id))
	s.mission_files_override = []
	tv.addon.out_dir = out
	Engine.time_scale = TIME_SCALE
	return tv


func _press(tv: Node, k: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.ctrl_pressed = ctrl
	e.pressed = true
	tv._unhandled_input(e)


## Waits until `cond` holds or `limit` s of sim time pass; true when it held.
func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true


func startup(id: String) -> void:
	var jet: String = JETS[id][0]
	var tv := await _start(JETS[id][1] + "_startup")
	var st: Dictionary = tv.flight.state()
	check(
		not st.engine_on and float(st.rpm) == 0.0 and int(st.power) == 0 and tv.cockpit.power == 0,
		"%s start-up: parked cold (rpm %s, power %s)" % [jet, st.rpm, st.power]
	)
	tv.throttle = 0.3
	tv._throttle_event()
	await fly(tv, 2.0)
	check(not tv.flight.state().engine_on, "%s: the throttle starts nothing" % jet)
	tv.throttle = 0.0
	_press(tv, KEY_E, true)  # Start engine (Ctrl+E, the own keys.json)
	await fly(tv, 5.0)
	st = tv.flight.state()
	check(
		st.start_phase != "off" and int(st.power) >= 1,
		"%s: the start runs (%s, power %s)" % [jet, st.start_phase, st.power]
	)
	var ok := await _until(tv, func(): return not tv.addon.result.is_empty(), 150.0)
	var d: Dictionary = tv.addon.result
	check(ok and bool(d.get("pass", false)), "%s: start-up scored %s %s" % [jet, d.get("pass"), d.get("reasons")])
	var items := {}
	for it in d.get("items", []):
		items[it.id] = it
	check(
		not items.get("time_to_idle", {}).has("note") and float(items.get("time_to_idle", {}).get("value", 0)) > 30.0,
		"%s: time to idle %s s from the RPM column" % [jet, items.get("time_to_idle", {}).get("value")]
	)
	check(
		not items.get("time_to_avionics", {}).has("note"),
		"%s: time to avionics %s s from the avionics column" % [jet, items.get("time_to_avionics", {}).get("value")]
	)
	st = tv.flight.state()
	check(tv.cockpit.power == 2 and float(st.rpm) >= 0.6, "%s: idle with the displays up" % jet)
	_check_files(tv, jet)


func _check_files(tv: Node, jet: String) -> void:
	var head = JSON.parse_string(FileAccess.get_file_as_string(String(tv.addon.result.flight)).get_slice("\n", 0))
	check(
		head is Dictionary and int(head.blackbox) == 2 and "rpm" in head.columns and "avionics" in head.columns,
		"%s: the recording is version 2 with rpm / avionics" % jet
	)
	check(FileAccess.file_exists(tv.addon.debrief_file), "%s: debrief %s" % [jet, tv.addon.debrief_file.get_file()])
	var log: Dictionary = settings().load_json(out.path_join("14.json"))
	var m: Array = log.get("missions", []).filter(func(x): return int(x.id) == int(tv.mission_id))
	check(not m.is_empty() and m[0].attempts[-1].result == 1, "%s: the pilot log holds the pass" % jet)


## The radio menu: Ctrl+T opens it, the number picks; the tower's answer.
func _call(tv: Node, n: int) -> String:
	_press(tv, KEY_T, true)
	var shown: bool = tv.addon.open
	_press(tv, KEY_1 + n - 1)
	await fly(tv, 0.5)
	var said: Array = tv.radio.said
	return "%s%s" % ["" if shown else "(menu not shown) ", said[-2].template if said.size() >= 2 else "-"]


func takeoff(id: String) -> void:
	var jet: String = JETS[id][0]
	var tv := await _start(JETS[id][1] + "_takeoff")
	var a := await _call(tv, 1)
	check(a == "ACFT_CLEAR_TO_START", "%s take-off: start-up request -> %s" % [jet, a])
	_press(tv, KEY_E, true)
	check(await _until(tv, func(): return tv.flight.state().engine_on, 120.0), "%s: the engine idles" % jet)
	a = await _call(tv, 2)
	check(a == "ACFT_TAXI_TO_RUNWAY", "%s: taxi request -> %s" % [jet, a])
	var s: Dictionary = settings().load_ibx(settings().own_dir().path_join("iaf.ibx"))[JETS[id][2]]
	var path: Array = []
	for i in int(s.TaxiWayPtsFrom):
		path.append(Vector2(float(s["FromTaxiPtX%d" % i]), float(s["FromTaxiPtY%d" % i])))
	var hdg := float(s.RunwayNumber)
	tv.brakes = false
	tv.scripted_stick = Vector2.ZERO
	var taxied := await _taxi(tv, path, hdg)
	check(taxied, "%s: taxied %d points to the lineup" % [jet, path.size()])
	a = await _call(tv, 3)
	check(a == "ACFT_CLEAR_TO_TAKEOFF", "%s: take-off request -> %s" % [jet, a])
	await _roll(tv, id, path[-1], hdg)
	var ok := await _until(tv, func(): return not tv.addon.result.is_empty(), 120.0)
	var d: Dictionary = tv.addon.result
	check(ok and bool(d.get("pass", false)), "%s: take-off scored %s %s" % [jet, d.get("pass"), d.get("reasons")])
	for it in d.get("items", []):
		if it.id in ["taxi_time", "roll_length", "liftoff_speed", "gear_up_height", "tower_calls"]:
			print("  %s %s %s" % [it.id, it.get("value"), it.get("unit", "")])
	_check_files(tv, jet)
	tv.scripted_stick = null
	tv.scripted_rudder = null


## The heading error to `p` from the jet, degrees (−180, 180]; positive: `p` to the right.
static func _bearing_err(tv: Node, p: Vector2) -> float:
	var w: Vector3 = tv.player_world()
	var brg := rad_to_deg(atan2(p.x - w.x, p.y - w.y))
	return wrapf(brg - float(tv.flight.state().heading), -180.0, 180.0)


## Nose-wheel steering toward the bearing error (rudder right +), the speed held by throttle and brakes.
func _drive(tv: Node, err: float, target_ms: float) -> void:
	tv.scripted_rudder = clampf(err / 25.0, -1.0, 1.0)
	var v: float = tv.flight.state().speed
	tv.throttle = clampf((target_ms - v) * 0.08, 0.0, 0.6)
	tv.brakes = v > target_ms + 2.0


func _taxi(tv: Node, path: Array, hdg: float) -> bool:
	var i := 0
	var t0: float = tv._sim_time
	while i < path.size():
		if tv._sim_time - t0 > 900.0:
			return false
		var w: Vector3 = tv.player_world()
		var d := Vector2(w.x, w.y).distance_to(path[i])
		if d < REACH_M or (i == path.size() - 1 and d < 25.0):
			i += 1
			continue
		var turn := d < TURN_M and i + 1 < path.size()
		_drive(tv, _bearing_err(tv, path[i]), TURN_MS if turn or i == path.size() - 1 else TAXI_MS)
		await process_frame
	# Stopped on the lineup, then turned onto the runway heading, as a pilot lines up.
	var c: Vector2 = path[-1]
	var dir := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	while absf(wrapf(hdg - float(tv.flight.state().heading), -180.0, 180.0)) > 3.0:
		if tv._sim_time - t0 > 900.0:
			return false
		_drive(tv, _bearing_err(tv, c + dir * 150.0), TURN_MS)
		await process_frame
	tv.throttle = 0.0
	tv.brakes = true
	return await _until(tv, func(): return tv.flight.state().speed < 0.5, 30.0)


## The roll on the centreline, the rotation, the climb on the heading, gear up.
func _roll(tv: Node, id: String, lineup: Vector2, hdg: float) -> void:
	var dir := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	tv.brakes = false
	tv.throttle = 1.0
	tv._throttle_event()
	var t0: float = tv._sim_time
	var gear_at := INF
	while tv.addon.result.is_empty() and tv._sim_time - t0 < 120.0 and not tv.crashed:
		var st: Dictionary = tv.flight.state()
		var w: Vector3 = tv.player_world()
		var along := (Vector2(w.x, w.y) - lineup).dot(dir)
		var herr := wrapf(hdg - float(st.heading), -180.0, 180.0)
		if st.on_ground:
			_drive_roll(tv, _bearing_err(tv, lineup + dir * (along + 300.0)))
			tv.scripted_stick = Vector2(0, 0.5 if float(st.speed_kt) > ROTATE_KT[id] else 0.0)
		else:
			if gear_at == INF:
				gear_at = tv._sim_time + 2.0
			elif tv._sim_time > gear_at and tv.gear_down:
				tv._toggle_gear()
			tv.scripted_rudder = 0.0
			var pitch_cmd := clampf((CLIMB_PITCH - float(st.pitch)) * 0.05, -0.3, 0.5)
			var roll_cmd := clampf((clampf(herr * 2.0, -15.0, 15.0) - float(st.roll)) * 0.03, -0.5, 0.5)
			tv.scripted_stick = Vector2(roll_cmd, pitch_cmd)
		await process_frame


func _drive_roll(tv: Node, err: float) -> void:
	tv.scripted_rudder = clampf(err / 10.0, -1.0, 1.0)
