# The whole checklist card (modern-iaf/docs/training.md §12; the user, 18 Nov: "have we update the checklist in the
# game yet? with what we agreed on?"), headless, per jet: test_checklist_card.gd's flight from a cold jet to AFTER
# TAKEOFF by the card's items, then the way home in the same flight. A scripted pilot (_pilot: stick, throttle,
# rudder and brakes, no autopilot) climbs above 3,000 ft, flies out along the runway's line, turns back onto a 2.5°
# final, flares and stops on the runway. On the approach BEFORE LANDING is done by real clicks on the 3D cockpit's
# controls, then AFTER LANDING, PRIOR TO ENGINE SHUTDOWN (the F-16s) and ENGINE SHUTDOWN on the runway: every checked
# item of the card ticks, the landing sections' in the card's order, and the jet ends cold (no engine, no power).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_card_landing.gd --log-file <temp> [-- --jet f16i]
extends "res://tests/test_mvp.gd"

## The sections flown after AFTER TAKEOFF, in the card's order (the F-35I's card has no before_shutdown).
const HOME := ["before_landing", "after_landing", "before_shutdown", "shutdown"]
## The scripted pilot's flight: the height above the runway flown out (m; above the card's 3,000 ft) and the height of
## the way back and the final, the path's angle, how far back along the runway's line the final starts, the path's aim
## point past the lineup, the flare's height (the jet's centre above the ground), the speed until the gear is down, the
## throttle's idle and military power.
const PATTERN_M := 1300.0
const LOW_M := 750.0
const GLIDE_DEG := 2.5
const OUT_M := 24000.0
const AIM_M := 250.0
const FLARE_M := 40.0
const FINAL_KT := 210.0
const IDLE := 0.05
const MIL := 0.74

var _tv: Node
var _lineup := Vector2.ZERO
var _hdg := 0.0
var _elev := 0.0
var _leg := 0
var _alpha := 4.0
var _down := false
var _sank_high := false
var _agl_was := INF
var _ground_fpm := 0.0
var _thr_i := 0.0
var _roll_i := 0.0
var _final_kt := FINAL_KT


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-mvp-landing-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	for id in JETS:
		if only == "" or id == only:
			await _whole_card(id)
	Engine.time_scale = 1.0


func _whole_card(id: String) -> void:
	var tv := await _card_flight(id)
	var card = tv.addon.card
	var sec := func() -> String:
		return String(card.sections[card.section].id) if card.section < card.sections.size() else ""
	check(sec.call() == "before_landing", "%s: AFTER TAKEOFF done, BEFORE LANDING next (%s)" % [id, sec.call()])
	# Home: out along the runway's line above 3,000 ft, the turn back, the final.
	var s: Dictionary = settings().load_ibx(settings().own_dir().path_join("iaf.ibx"))[JETS[id][2]]
	var n := int(s.TaxiWayPtsFrom) - 1
	_lineup = Vector2(float(s["FromTaxiPtX%d" % n]), float(s["FromTaxiPtY%d" % n]))
	_hdg = float(s.RunwayNumber)
	_elev = float(s.LineupLocZ)
	_leg = 0
	_alpha = 4.0
	_down = false
	_sank_high = false
	_agl_was = INF
	_ground_fpm = 0.0
	_thr_i = 0.0
	_roll_i = 0.0
	_final_kt = FINAL_KT
	_tv = tv
	process_frame.connect(_pilot)
	Engine.time_scale = TIME_SCALE
	# Above 3,000 ft a descent leaves BEFORE LANDING closed.
	var high := await _wait(tv, id, func(): return _leg >= 1 and _sank_high, 600.0)
	check(high and _leg == 1 and not card.phase_ok(), "%s: a descent above 3,000 ft leaves BEFORE LANDING waiting" % id)
	if not high:
		return _end_pilot()
	# The approach: descending below 3,000 ft above the ground the card opens BEFORE LANDING; its items by clicks.
	var due := func() -> bool: return sec.call() == "before_landing" and card.phase_ok()
	var open := await _wait(tv, id, func(): return due.call() and float(tv.flight.state().speed_kt) < 280.0, 900.0)
	Engine.time_scale = 1.0
	check(open and not tv.flight.state().on_ground, "%s: BEFORE LANDING opens on the approach" % id)
	if not open:
		return _end_pilot()
	check(not tv.gear_down, "%s: the gear still up at BEFORE LANDING" % id)
	await _fly_section(tv, "before_landing")
	tv.views.snap = Vector2.ZERO
	_final_kt = FINAL_KT - 25.0  # the gear down: the final's speed, then by the angle of attack
	check(tv.gear_down, "%s: the gear lowered by the handle's click" % id)
	if tv.crashed:
		return _end_pilot()
	check(sec.call() == "after_landing" and not tv.flight.state().on_ground, "%s: BEFORE LANDING done in the air" % id)
	# The landing: the final, the flare, the touchdown and the stop on the runway.
	Engine.time_scale = TIME_SCALE
	var stopped := func() -> bool: return tv.flight.state().on_ground and float(tv.flight.state().speed) < 0.5
	var landed := await _wait(tv, id, stopped, 900.0)
	_end_pilot()
	check(landed, "%s: landed and stopped (crashed %s)" % [id, tv.crashed])
	if not landed:
		return
	var surf: int = tv.terrain.surface_at(tv.flight.state().position)
	check((surf & tv.terrain.SURFACE_ANY_RUNWAY) != 0, "%s: stopped on the runway (surface %x)" % [id, surf])
	check(not tv.player_damage.flags[7], "%s: the gear whole after the touchdown" % id)
	tv.scripted_stick = Vector2.ZERO
	tv.scripted_rudder = 0.0
	tv.brakes = true
	# After landing and the shutdown, each section in its turn.
	for name in HOME.slice(1):
		if not card.sections.any(func(x): return x.id == name):
			continue
		await frames(2)
		check(sec.call() == name, "%s: the card at %s (%s)" % [id, name, sec.call()])
		await _fly_section(tv, name)
	await frames(2)
	check(card.section == card.sections.size(), "%s: the card done to its end (%s)" % [id, sec.call()])
	var checked: Array = card.flat.filter(func(it): return it.has("check")).map(func(it): return it.id)
	var left: Array = checked.filter(func(i): return not card.done.has(i))
	check(left.is_empty(), "%s: every checked item of the card ticked (left %s)" % [id, left])
	# Cold: the engine off and wound down, no electrical power, the displays dark.
	Engine.time_scale = TIME_SCALE
	await _until(tv, func(): return float(tv.flight.state().rpm) < 0.1, 180.0)
	Engine.time_scale = 1.0
	var st: Dictionary = tv.flight.state()
	check(
		not st.engine_on and int(st.power) == 0 and tv.cockpit.power == 0 and float(st.rpm) < 0.1,
		"%s: the jet ends cold (engine %s, power %s, RPM %.2f)" % [id, st.engine_on, st.power, st.rpm]
	)
	print("%s card: %d items, %d checked, all ticked: %s" % [id, card.flat.size(), checked.size(), left.is_empty()])
	Engine.time_scale = TIME_SCALE


## The card's current section `name` by clicks: the items its controls already satisfy are ticked as it opens (MASTER
## ARM left at OFF); the others tick one by one in the card's order, each by its own clicks.
func _fly_section(tv: Node, name: String) -> void:
	var card = tv.addon.card
	var items: Array = card.sections[card.section].items.filter(func(it): return it.has("check"))
	var todo: Array = items.filter(func(it): return not card.done.has(it.id)).map(func(it): return it.id)
	var held: Array = items.filter(func(it): return card.done.has(it.id)).map(func(it): return it.id)
	await _fly_card(tv, func(it): return String(card.sections[int(it.section)].id) == name)
	var ticked: Array = card.done.keys().filter(func(i): return i in todo)
	check(
		ticked == todo and not todo.is_empty(),
		"%s: %s ticked in the card's order by clicks %s (already in place: %s)" % [tv.addon.plane, name, ticked, held]
	)


## Waits for `cond` up to `limit` s of the sim, the flight's state printed every 30 s (every 2 s near the ground);
## false at a crash or when the time is up.
func _wait(tv: Node, id: String, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	var said := t0
	while not tv.crashed and not cond.call() and tv._sim_time - t0 < limit:
		if tv._sim_time - said > (2.0 if tv.player_world().z - _elev < 150.0 else 30.0):
			said = tv._sim_time
			_say(tv, id)
		await process_frame
	_say(tv, id)
	return not tv.crashed and cond.call()


## The scripted pilot let go: a flight that ended early (a crash, a wait's time up) goes no further.
func _end_pilot() -> void:
	if process_frame.is_connected(_pilot):
		process_frame.disconnect(_pilot)
	Engine.time_scale = 1.0


## The scripted pilot, every frame: leg 0 climbs to PATTERN_M above the runway on its heading; leg 1 flies to the
## point OUT_M back along the runway's line and descends to LOW_M near it; leg 2 is the final: onto the line, level
## until the path comes down, the path to a point AIM_M past the lineup, the flare, then idle, brakes and the rudder
## on the centreline. The pitch holds a vertical speed (the flight path's angle plus the angle of attack), the bank a
## heading, the throttle a speed.
func _pilot() -> void:
	var tv := _tv
	if not is_instance_valid(tv) or tv.crashed or paused:
		return
	var dt: float = minf(tv.get_process_delta_time(), 0.1)
	var st: Dictionary = tv.flight.state()
	var w: Vector3 = tv.player_world()
	var dir := Vector2(sin(deg_to_rad(_hdg)), cos(deg_to_rad(_hdg)))
	var rel := Vector2(w.x, w.y) - _lineup
	var along := rel.dot(dir)
	var right := rel.dot(Vector2(dir.y, -dir.x))
	var h: float = w.z - _elev
	var ground = tv.terrain.height_at(tv.rig.position)
	var agl: float = tv.rig.position.y - float(ground) if ground != null else INF
	_sank_high = _sank_high or (float(st.vs_fpm) < -300.0 and agl / 0.3048 > 3300.0 and agl < 1.0e5)
	if _leg == 2 and (st.on_ground or _down):
		# Down: idle, the nose held low through a skip, then the brakes and the rudder on the centreline.
		_down = true
		tv.throttle = IDLE
		tv.brakes = bool(st.on_ground)
		tv.scripted_stick = Vector2(-float(st.roll) * 0.03, 0.0 if st.on_ground else (4.0 - float(st.pitch)) * 0.1)
		_drive_roll(tv, _bearing_err(tv, _lineup + dir * (along + 300.0)) if st.on_ground else 0.0)
		return
	var want_hdg := _hdg
	var want_h := PATTERN_M
	var want_kt := 250.0
	var bank := 30.0
	var far := _lineup - dir * OUT_M
	var glide := (AIM_M - along) * tan(deg_to_rad(GLIDE_DEG))
	match _leg:
		0:
			want_h = PATTERN_M + 200.0  # past the height flown out: leg 1 begins with a descent, still above 3,000 ft
			if h > PATTERN_M + 150.0:
				_leg = 1
		1:
			want_hdg = rad_to_deg(atan2(far.x - w.x, far.y - w.y))
			if Vector2(w.x, w.y).distance_to(far) < 12000.0:  # down to the final's height: the approach begins
				want_kt = 220.0
				want_h = LOW_M
			if Vector2(w.x, w.y).distance_to(far) < 3000.0:
				_leg = 2
		2:
			want_hdg = _hdg - clampf(right * 0.03, -60.0, 60.0)
			want_kt = _final_kt
			want_h = LOW_M
	var vs_want := clampf((want_h - h) * 20.0, -2500.0, 3000.0)
	# The ground's own rise or fall under the jet (a sloping runway), from the height above it.
	if _agl_was < 1.0e5 and agl < 1.0e5 and dt > 0.0:
		_ground_fpm = lerpf(_ground_fpm, float(st.vs_fpm) - (agl - _agl_was) / dt * 196.85, clampf(dt / 0.5, 0.0, 1.0))
	_agl_was = agl
	if _leg == 2 and glide < LOW_M:
		# On the path: its own descent rate plus the height error; near the ground the flare.
		var sink := float(st.speed_kt) * 101.3 * sin(deg_to_rad(GLIDE_DEG))
		vs_want = clampf(-sink + (maxf(glide, 0.0) - h) * 20.0, -2000.0, 1500.0)
		if agl < 60.0 and along < -2500.0:
			vs_want = maxf(vs_want, 500.0)  # a hill under the path
		# The flare: the sink falls with the height (0.2 m/s per m above the wheels' touch) to 100 fpm, measured
		# against the ground.
		if agl < FLARE_M:
			vs_want = maxf(vs_want, minf(-100.0, -(agl - 2.0) * 40.0) + _ground_fpm)
	# The pitch for that vertical speed: the flight path's angle plus the angle of attack (smoothed, in the bank's
	# plane).
	_alpha = lerpf(_alpha, rad_to_deg(float(st.alpha)), clampf(dt / 1.5, 0.0, 1.0))
	var path := rad_to_deg(asin(clampf(vs_want * 0.00508 / maxf(float(st.speed), 40.0), -0.3, 0.3)))
	var quick := 0.003 if _leg == 2 and agl < FLARE_M else 0.001  # the flare answers faster
	var lift := (vs_want - float(st.vs_fpm)) * quick
	var pitch_want := clampf(path + _alpha * cos(deg_to_rad(float(st.roll))) + lift, -12.0, 16.0)
	var herr := wrapf(want_hdg - float(st.heading), -180.0, 180.0)
	var roll_want := clampf(herr * 1.5, -bank, bank)
	# The bank asked for is held against a lopsided load: the roll error summed into the stick.
	var roll_err: float = roll_want - float(st.roll)
	_roll_i = clampf(_roll_i + roll_err * 0.01 * dt, -0.2, 0.2)
	tv.scripted_stick = Vector2(
		clampf(roll_err * 0.03 + _roll_i, -0.5, 0.5), clampf((pitch_want - float(st.pitch)) * 0.1, -0.4, 0.6)
	)
	# The final's speed follows the angle of attack (13°: each jet at its own weight), once the gear is down.
	if _leg == 2 and tv.gear_down:
		_final_kt = clampf(_final_kt + (float(st.aoa) - 13.0) * 1.5 * dt, 140.0, FINAL_KT)
	tv.scripted_rudder = 0.0
	var kt_err: float = want_kt - float(st.speed_kt)
	_thr_i = clampf(_thr_i + kt_err * 0.004 * dt, 0.0, 0.5)
	tv.throttle = IDLE if _leg == 2 and agl < 6.0 else clampf(0.15 + _thr_i + kt_err * 0.02, IDLE, MIL)


## The Throttle OFF item by its key's command (no pointer on the throttle), and MAIN PWR OFF once the RPM is below
## 20 %, as its line says; every other item as test_mvp.gd does it.
func _do_item(tv: Node, it: Dictionary, keys: bool) -> void:
	if it.check.has("throttle_off"):
		tv._command([218, 0, 0])
		await frames(2)
		return
	if it.id == "main_power_off":
		var low := await _until(tv, func(): return float(tv.flight.state().rpm) < 0.2, 120.0)
		check(low, "%s: the RPM below 20 %% before MAIN PWR OFF" % tv.addon.plane)
	await super(tv, it, keys)


func _say(tv: Node, id: String) -> void:
	var st: Dictionary = tv.flight.state()
	var w: Vector3 = tv.player_world()
	var dir := Vector2(sin(deg_to_rad(_hdg)), cos(deg_to_rad(_hdg)))
	var rel := Vector2(w.x, w.y) - _lineup
	var at := [rel.dot(dir) * 0.001, rel.dot(Vector2(dir.y, -dir.x))]
	var fly := [id, tv._sim_time, _leg, st.speed_kt, w.z - _elev, st.vs_fpm, st.aoa]
	var text := "  %s %.0f s: leg %d, %.0f kt, %.0f m above the runway, %.0f fpm, AoA %.1f" % fly
	print(text + ", %.1f km along and %.0f m right of its line, gear %s" % (at + [tv.gear_down]))
