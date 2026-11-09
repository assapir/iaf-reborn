# The MVP probe (iaf-2026/docs/plan.md, item F; started by item E3b): Modern IAF's two training missions flown headless
# for each MVP jet (the Sufa at Ramon, the Barak at Ramat David, the F-35I at Nevatim) with scripted inputs, each
# ending in a Pass from the run-time scoring (iaf-2026/docs/training.md §7–§9):
# - start-up: parked cold (no RPM, no power), the throttle starts nothing, the checklist by its keys (the F-16's
#   six steps, the F-35I's four) runs the sequence, the displays come up, the engine idles; a step out of order
#   fails; the recorder's RPM / avionics columns; the debrief record and the pilot log;
# - take-off: the radio menu's three requests answered by the base's tower, a taxi along the base's taxi path
#   (the own iaf.ibx) to the lineup, the roll, the rotation, gear up on the runway heading; the debrief's goals;
# - the afterburner's sound: the light-off's rise and thump, the cut's tail (no mission);
# - a crash (the Sufa's start-up): the mission ends at once in a Fail with the crash first;
# - an ejection (the Sufa's take-off): no sound or radio afterwards, the debrief's reason "ejected", the eject event.
# The front end's part is test_front_end.gd (with `-- --fly` it flies a mission through the screens). Still open for
# item F: the run on a root that holds only the sim's files, macOS and Windows.
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
## The taxi: speed (m/s), slower within TURN_M of a turn; a point is passed within REACH_M; the jet steers to a point
## LOOK_M ahead on the leg (it follows the taxi line: off the pavement fails the mission, training.md §3.0).
const TAXI_MS := 10.0
const TURN_MS := 2.5
const TURN_M := 70.0
const REACH_M := 6.0
const LOOK_M := 12.0
## The take-off: rotation speed (kt) per jet (about the mission's reference speed less 10 kt: training.md §3), the
## climb's pitch.
const ROTATE_KT := {"f16i": 155.0, "f16": 140.0, "f35i": 160.0}
const CLIMB_PITCH := 10.0

var out := ""
var fly_gd: GDScript


## The sim's own data (./modern-iaf-setup), not the original's install.
func require_data() -> void:
	if DirAccess.dir_exists_absolute(settings().own_dir().path_join("resource")):
		return
	print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-mvp-%d" % OS.get_process_id())
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
	if only == "" and jet in ["", "f16i"]:
		await ab_sound()
		await core_sound()
		await crash()
		await eject()
		await wrong_order()
	Engine.time_scale = 1.0


## The flights' records folder goes with the run, passed or failed (base.gd's quit comes through here).
func _quit(code: int) -> void:
	if out.get_file().begins_with("modern-iaf-mvp-"):
		_remove(out)
	await super(code)


## Deletes the folder `dir` and everything in it.
func _remove(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


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
	await _checklist(tv, id == "f35i", id == "f16i")
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


## A crash during the start-up: the run time ends the mission at once (IafTraining's live check).
## The afterburner's sound (iaf-2026/docs/sound.md §1.2): the burner loop at its own pitch, rising from 12 dB down
## with the light-off thump, no restart from stage 1 to 2, the cut's tail fading on the second player.
func ab_sound() -> void:
	var fs_script = _flight_sounds()
	var fs = fs_script.create(null, 100)
	root.add_child(fs)
	var st := {"time": 0.0, "on_ground": false, "rpm": 1.0, "gear": 1.569, "crashed": false, "drag_x": 0.0}
	var inp := {"gear_down": false, "flaps": 0.0, "flaps_state": 0, "brakes": false, "in_cockpit": true}
	inp["agl_m"] = 3000.0
	for stage in [0, 1]:
		st["afterburner"] = stage
		fs.update(st, inp)
		await process_frame
	var vol: float = fs._engine.get_meta("base_volume")
	check(
		settings().ab_sound_real() and fs.engine_code == "SFX_DRY_THRUST" and is_equal_approx(fs.engine_pitch, 1.0),
		"the burner plays at its own pitch (%.2f)" % fs.engine_pitch
	)
	check(fs.played.has("SFX_AB_LIGHT/None"), "the light-off thump plays")
	check(vol < 0.6 * 0.3 and fs._tail.playing, "the burner starts 12 dB down, the dry loop fades (%.3f)" % vol)
	var stream = fs._engine.stream
	st["afterburner"] = 2
	for i in 3:
		fs.update(st, inp)
		await process_frame
	check(
		fs.engine_code == "SFX_AFTERBURNER_THRUST" and fs._engine.stream == stream and fs._engine.playing,
		"stage 1 -> 2: the same loop, no restart"
	)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1700:
		fs.update(st, inp)
		await process_frame
	vol = fs._engine.get_meta("base_volume")
	check(is_equal_approx(vol, 0.6), "the burner at its level after 1.5 s (%.3f)" % vol)
	st["afterburner"] = 0
	fs.update(st, inp)
	check(fs.engine_code == "SFX_START_ENGINE" and fs._tail.playing, "the cut: the dry loop, the burner's tail fading")
	st["afterburner"] = 1
	fs.update(st, inp)
	vol = fs._engine.get_meta("base_volume")
	check(vol > 0.5, "re-lit during the tail: the burner goes on at the tail's level (%.3f)" % vol)
	fs.queue_free()
	# A cut during the rise: the tail fades from the burner's level then, not from full.
	fs = fs_script.create(null, 100)
	root.add_child(fs)
	for stage in [0, 1, 0]:
		st["afterburner"] = stage
		fs.update(st, inp)
		await process_frame
	vol = fs._tail.get_meta("base_volume")
	check(vol < 0.6 * 0.3, "cut during the rise: the tail starts at the burner's level (%.3f)" % vol)
	fs.queue_free()


## flight_sounds.gd, loaded at run time (a preload compiles it before the autoloads exist).
func _flight_sounds() -> GDScript:
	return load("res://shared/audio/flight_sounds.gd")


## The dry engine, the JFS and the wind (iaf-2026/docs/sound.md §1.3–§1.6): the idle loop at its own pitch at idle and
## 6 dB down, 1.3 and full at military; the wind's level as the dynamic pressure.
func core_sound() -> void:
	var fs = _flight_sounds().create(null, 100)
	root.add_child(fs)
	var st := {"time": 0.0, "on_ground": true, "rpm": 0.6, "gear": 0.0, "crashed": false, "afterburner": 0}
	var inp := {"gear_down": true, "flaps": 0.0, "flaps_state": 0, "brakes": false, "in_cockpit": true, "kcas": 0.0}
	fs.update(st, inp)
	var vol: float = fs._engine.get_meta("base_volume")
	check(
		settings().core_sound_real() and is_equal_approx(fs.engine_pitch, 1.0) and absf(vol - 0.6 * 0.501) < 0.01,
		"idle: the loop at its own pitch, 6 dB down (%.2f, %.3f)" % [fs.engine_pitch, vol]
	)
	st["rpm"] = 1.0
	fs.update(st, inp)
	vol = fs._engine.get_meta("base_volume")
	check(is_equal_approx(fs.engine_pitch, 1.3) and is_equal_approx(vol, 0.6), "military: pitch 1.3, full level")
	st["rpm"] = 0.15
	fs.update(st, inp)
	check(is_equal_approx(fs.engine_pitch, 0.3) and fs._wind == null, "the crank: pitch 0.3; no wind standing")
	st["rpm"] = 1.0
	inp["kcas"] = 225.0
	inp["gear_down"] = false
	st["on_ground"] = false
	fs.update(st, inp)
	var w: float = fs._wind.get_meta("base_volume") if fs._wind != null else 0.0
	check(absf(w - 0.25) < 0.01, "the wind at 225 kt: a quarter of its 450 kt level (%.3f)" % w)
	fs.queue_free()


func crash() -> void:
	var tv := await _start("ramon_startup")
	await fly(tv, 1.0)
	tv._on_crashed("test")
	await frames(3)
	var d: Dictionary = tv.addon.result
	check(
		not d.is_empty() and not bool(d.get("pass", true)) and d.get("reasons", [""])[0] == "crash",
		"a crash ends the start-up at once: %s %s" % [d.get("pass"), d.get("reasons")]
	)


## An ejection in the take-off: the sortie ends (Settings.eject_ends_sortie): silent, Fail "ejected" first.
func eject() -> void:
	var tv := await _start("ramon_takeoff")
	await fly(tv, 1.0)
	tv._eject()
	var said: int = tv.radio.said.size()
	var played: int = tv.sounds.played.size()
	await _call(tv, 1)
	await fly(tv, 1.0)
	check(
		tv.sounds.silenced and tv.radio.said.size() == said and tv.sounds.played.size() == played,
		(
			"after the ejection no radio call or sound plays (%d said, %d played)"
			% [tv.radio.said.size() - said, tv.sounds.played.size() - played]
		)
	)
	var d: Dictionary = tv.addon.result
	check(
		not d.is_empty() and d.get("reasons", [""])[0] == "ejected",
		"an ejection ends the take-off: %s %s" % [d.get("pass"), d.get("reasons")]
	)
	var rec := FileAccess.get_file_as_string(String(d.get("flight", "")))
	check(rec.contains('"event":"eject"'), "the recording holds the eject event")


## The start-up checklist by its keys (commands 210–215, training.md §7.1) and the throttle up from OFF for the idle
## step, each when its moment comes; the card ticks each step. `click`: the same steps by the mouse on the 3D
## cockpit's switches (f16_controls.json, cockpit3d_controls.gd), each switch turned to its on position.
func _checklist(tv: Node, f35: bool, click := false) -> void:
	var step := func(n: int) -> void: tv._command([209 + n, 0, 0])
	var rpm := func() -> float: return float(tv.flight.state().rpm)
	if click:
		check(_card_places(tv), "the card names each step's switch and place")
	await _step(tv, 1, "MAIN_PWR", click)  # main power / battery
	await fly(tv, 1.0)
	await _step(tv, 2, "JFS", click)  # JFS / IPP
	# The engine step has no key: the throttle up from OFF (the throttle-up key here) is it.
	var throttle_up := func() -> void: tv._command([5, 0, 0])
	if f35:
		await fly(tv, 11.0)  # the IPP up to speed
		throttle_up.call()  # throttle to idle: the engine starts
		await fly(tv, 0.5)  # the flight takes the throttle's move on its next frame
	else:
		await _until(tv, func(): return rpm.call() >= 0.2, 60.0)
		check(tv.sounds._jfs != null and tv.sounds._jfs.playing, "the JFS whine during the crank")
		await _step(tv, 0, "THROTTLE", click)  # throttle to idle at 20 %
		await _until(tv, func(): return rpm.call() >= 0.55, 60.0)  # the generators on line
		await _step(tv, 4, "AVIONICS_MMC", click)  # avionics power
		await _step(tv, 5, "INS", click)  # INS stored-heading alignment
	await _step(tv, 6, "CANOPY_HANDLE", click)  # canopy
	tv.views.snap = null
	check(tv.sounds.played.has("SFX_DOOR_CLOSE/None"), "the canopy step: the canopy closes")
	if not f35:
		await _until(tv, func(): return tv.sounds._jfs == null, 10.0)
		check(tv.sounds._jfs == null, "the JFS wound down after the generators (RPM %.2f)" % rpm.call())
	var st: Dictionary = tv.flight.state()
	check(
		tv.addon.done.size() == tv.addon.checklist.size() and tv.addon._fault_shown == "",
		(
			"the checklist: %d of %d steps, no fault (%s, power %s)"
			% [tv.addon.done.size(), tv.addon.checklist.size(), st.start_phase, st.power]
		)
	)


## Checklist step `n` (0: the throttle up from OFF) by its key's command, or by a click on its control `node`.
func _step(tv: Node, n: int, node: String, click: bool) -> void:
	if click:
		await _click_control(tv, node)
	else:
		tv._command([209 + n, 0, 0] if n > 0 else [5, 0, 0])


## A left click on the 3D cockpit's control `node` (f16_controls.json), the head turned to it, as the window's mouse
## events: hovering lights it, the click sends its command; a switch with a FlightGear property turns.
func _click_control(tv: Node, node: String) -> void:
	var c3d = tv.cockpit_3d
	var mi: MeshInstance3D = c3d.find_child(node, true, false) if c3d != null else null
	check(mi != null and c3d.clickable != null, "the 3D cockpit's control %s" % node)
	if mi == null:
		return
	var vp: Viewport = tv.get_viewport()
	var centre := func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center()
	var at := await _aim(tv, centre.call(), 0.0)
	check(vp.get_visible_rect().has_point(at), "%s: the head turned to it, on the screen at %s" % [node, at])
	var hover := InputEventMouseMotion.new()
	hover.position = at
	vp.push_input(hover)
	check(mi.material_overlay != null, "%s: the pointer over it lights it (at %s)" % [node, at])
	var rest := mi.transform
	vp.push_input(_click(at, MOUSE_BUTTON_LEFT, true))
	vp.push_input(_click(at, MOUSE_BUTTON_LEFT, false))
	await frames(2)
	if not node in ["THROTTLE", "CANOPY_HANDLE"]:  # the throttle moves with its own animation; the handle: a hit area
		check(not mi.transform.is_equal_approx(rest), "%s: the switch turned" % node)
	hover.position = Vector2.ZERO
	vp.push_input(hover)


## Each line of the start-up card has the switch's name and place under it (the mission's `where`).
func _card_places(tv: Node) -> bool:
	var texts := []
	for l in tv.addon._card.find_children("*", "Label", true, false):
		texts.append(l.text.strip_edges())
	for c in tv.addon.checklist:
		if not c.has("where") or not String(c.where.en) in texts:
			return false
	return true


## A step out of order: the JFS before the main power ends the start-up at once, its fault first.
func wrong_order() -> void:
	var tv := await _start("ramon_startup")
	tv._command([211, 0, 0])
	await frames(3)
	var d: Dictionary = tv.addon.result
	check(
		not d.is_empty() and d.get("reasons", [""])[0] == "no_power" and tv.flight.state().start_phase == "off",
		"the JFS without main power: nothing runs, the start-up fails: %s" % [d.get("reasons")]
	)


func _check_files(tv: Node, jet: String) -> void:
	var head = JSON.parse_string(FileAccess.get_file_as_string(String(tv.addon.result.flight)).get_slice("\n", 0))
	check(
		head is Dictionary and int(head.blackbox) == 2 and "rpm" in head.columns and "avionics" in head.columns,
		"%s: the recording is version 2 with rpm / avionics" % jet
	)
	var db := out.path_join("modern-iaf.sqlite")
	var d = JSON.parse_string(IafPilotLog.debrief(db, tv.addon.sortie))
	check(
		d is Dictionary and d.get("mission") == tv.addon.mission_name,
		"%s: sortie %d's debrief" % [jet, tv.addon.sortie]
	)
	var sum = JSON.parse_string(IafPilotLog.summary(db, settings().pilot()))
	var st = sum.missions.get(str(int(tv.mission_id)), {}).get("status") if sum is Dictionary else null
	check(st != null and int(st) == 1, "%s: the pilot log holds the pass" % jet)


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
	_ils_bars(tv, jet)
	_hud_light(tv, jet)
	var a := await _call(tv, 1)
	check(a == "ACFT_CLEAR_TO_START", "%s take-off: start-up request -> %s" % [jet, a])
	var pl: Array = tv.sounds.played
	check(
		pl.has("key_on.ogg") and pl.rfind("key_on.ogg") < pl.rfind("key_off.ogg"),
		"%s: the tower's answer is keyed: key_on.ogg, its clips, key_off.ogg (sound.md §5.2)" % jet
	)
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
	var goals := ["runway", "liftoff_speed", "reference_speed", "max_centreline_offset", "tower_calls"]
	check(d.get("goals", []) == goals, "%s: the debrief's goals %s" % [jet, d.get("goals")])
	for it in d.get("items", []):
		if it.id in ["taxi_time", "roll_length", "liftoff_speed", "gear_up_height", "tower_calls"]:
			print("  %s %s %s" % [it.id, it.get("value"), it.get("unit", "")])
	_check_files(tv, jet)
	tv.scripted_stick = null
	tv.scripted_rudder = null


## The HUD's ILS bars glide (the Mac play test's finding 24): 0.04° apart moves them under one HUD pixel, where the
## original game's whole-pixel rule (test_real_hud) holds them still.
func _ils_bars(tv: Node, jet: String) -> void:
	var hud = tv.cockpit.hud
	var gear: bool = tv.cockpit.gear_handle_down
	var ils = tv.cockpit.state.get("ils")
	tv.cockpit.gear_handle_down = true
	var at := []
	for dev in [Vector2(0.5, -1.0), Vector2(0.54, -1.04)]:
		tv.cockpit.state["ils"] = dev
		hud._real_frame = -1
		hud.real_hud()
		at.append(hud._real_in.get("ils"))
	var d: Vector2 = at[1] - at[0] if at[0] != null and at[1] != null else Vector2.ZERO
	check(
		d.length() > 0.1 and absf(d.x) < 1.0 and absf(d.y) < 1.0,
		"%s: the ILS bars move %s HUD px for 0.04° (sub-pixel, no whole-pixel step)" % [jet, d]
	)
	tv.cockpit.gear_handle_down = gear
	if ils != null:
		tv.cockpit.state["ils"] = ils
	else:
		tv.cockpit.state.erase("ils")
	hud._real_frame = -1


## The HUD's light (Approvals A10, Settings.hud_daylight): the P43 green at the day level, the night floor in the
## dark, the HUD key stepping the level in eighths, added to the scene, and the combiner glass at 14 %.
func _hud_light(tv: Node, jet: String) -> void:
	var cp = tv.cockpit
	var level: float = settings().hud_brightness
	var light: float = cp.daylight
	settings().hud_brightness = 1.0
	cp.daylight = 1.0
	var own = cp.hud.real_hud().get("colour")
	if own != null:
		# The F-35I: its helmet display keeps its own green, and it has no combiner.
		check(cp.hud._hc() == own, "%s: the helmet keeps its own green (%s)" % [jet, own])
	else:
		check(cp.hud._hc() == Color8(40, 255, 50), "%s: the HUD by day in the P43 green (%s)" % [jet, cp.hud._hc()])
		cp.daylight = 0.0
		var k := 136.0 / 255.0
		var floor_c := Color(40.0 / 255.0 * k, k, 50.0 / 255.0 * k)
		check(cp.hud._hc().is_equal_approx(floor_c), "%s: at night at the floor (%s)" % [jet, cp.hud._hc()])
	cp.daylight = 1.0
	tv._command([123, 0, 0])
	check(settings().hud_brightness == 0.125, "%s: the HUD key from full to the dimmest eighth" % jet)
	tv._command([123, 0, 0])
	check(settings().hud_brightness == 0.25, "%s: the HUD key one eighth up" % jet)
	check(
		cp.hud.material != null and String(cp.hud.material.shader.code).contains("blend_add"),
		"%s: the HUD adds its light to the scene" % jet
	)
	var glass = tv.cockpit_3d._glass if tv.cockpit_3d != null else null
	check(
		own != null or glass != null and is_equal_approx(glass.material_override.albedo_color.a, 0.14),
		"%s: the combiner glass at 14 %% (the F-35I: none)" % jet
	)
	_sym_wheel(tv, jet, own == null)
	settings().hud_brightness = level
	cp.daylight = light


## The F-16s' SYM wheel (cockpit3d_controls.gd, f16_controls.json): hovering lights it, the mouse wheel and a drag on
## it turn it through the HUD key's command, the HUD's level follows, the knob turns and the settings file keeps it.
## The events go in at the window (the cockpit's own world: cockpit_origin.gd passes them on). The F-35I: no table,
## no layer.
func _sym_wheel(tv: Node, jet: String, f16: bool) -> void:
	var c3d = tv.cockpit_3d
	var layer = c3d.clickable if c3d != null else null
	check((layer != null) == f16, "%s: the 3D cockpit's clickable controls (%s)" % [jet, layer])
	if layer == null:
		return
	var knob: MeshInstance3D = c3d.find_child("SYM", true, false)
	var vp: Viewport = tv.get_viewport()  # the window's: the events take the flight's own path to the cockpit
	var at: Vector2 = c3d.camera.unproject_position(knob.global_transform * knob.get_aabb().get_center())
	var hover := InputEventMouseMotion.new()
	hover.position = at
	vp.push_input(hover)
	check(knob.material_overlay != null, "%s: hovering the SYM wheel lights it (at %s)" % [jet, at])
	settings().hud_brightness = 0.5
	c3d._process(0.0)
	var rest := knob.transform.basis
	vp.push_input(_click(at, MOUSE_BUTTON_WHEEL_UP, true))
	check(is_equal_approx(settings().hud_brightness, 0.525), "%s: the wheel up on it: +2.5 %%" % jet)
	vp.push_input(_click(at, MOUSE_BUTTON_LEFT, true))
	var drag := InputEventMouseMotion.new()
	drag.position = at
	drag.relative = Vector2(0, -20)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(drag)
	vp.push_input(_click(at, MOUSE_BUTTON_LEFT, false))
	check(is_equal_approx(settings().hud_brightness, 0.575), "%s: a 20 px drag up: two more steps" % jet)
	c3d._process(0.0)
	check(not knob.transform.basis.is_equal_approx(rest), "%s: the SYM wheel turned" % jet)
	var kept := float(settings().write_config().get_value("graphics", "hud_brightness"))
	check(kept == settings().hud_brightness, "%s: the settings file keeps the wheel's level (%s)" % [jet, kept])
	hover.position = Vector2.ZERO
	vp.push_input(hover)
	check(knob.material_overlay == null, "%s: off the wheel, unlit" % jet)


static func _click(at: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = button
	e.pressed = pressed
	return e


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
	tv.brakes = v > target_ms + 0.5


func _taxi(tv: Node, path: Array, hdg: float) -> bool:
	var i := 0
	var t0: float = tv._sim_time
	var w0: Vector3 = tv.player_world()
	var from := Vector2(w0.x, w0.y)
	while i < path.size():
		if tv._sim_time - t0 > 900.0:
			return false
		var w: Vector3 = tv.player_world()
		var at := Vector2(w.x, w.y)
		var d := at.distance_to(path[i])
		if d < REACH_M or (i == path.size() - 1 and d < 25.0):
			from = path[i]
			i += 1
			continue
		var turn := d < TURN_M and i + 1 < path.size()
		var leg: Vector2 = path[i] - from
		var along := clampf((at - from).dot(leg.normalized()), 0.0, leg.length())
		var aim: Vector2 = from + leg.normalized() * minf(along + LOOK_M, leg.length())
		var err := _bearing_err(tv, aim)
		# Slow through a turn until the nose is on the new leg.
		_drive(tv, err, TURN_MS if turn or absf(err) > 15.0 or i == path.size() - 1 else TAXI_MS)
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


## The head turned until the point `p` (world) is straight ahead (camera.rotation = (pitch, −yaw): terrain_view.gd),
## then lifted by `up` (rad); the point on the screen.
func _aim(tv: Node, p: Vector3, up: float) -> Vector2:
	var cam: Camera3D = tv.cockpit_3d.camera
	var h := Vector2.ZERO
	for i in 4:
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h + Vector2(0.0, up)
	await frames(3)
	return cam.unproject_position(p)
