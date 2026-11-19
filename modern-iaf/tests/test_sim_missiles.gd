# The air-to-air missiles' employment flow (avionics-plan.md §6 slice 8, G26, G27; modern-iaf/docs/weapons.md §8),
# headless, on each jet's weapons range (the Sufa, the Barak, the Adir) with every missile the jet carries hung on its
# stations (the F-16s: AIM-9M, Python 5, AIM-120; the F-35I: AIM-9X, AIM-120 in its bays). For each missile, at a
# fresh drone, through the cockpit's keys:
# - select: "]" until the missile is the selected store (the IR missiles' SRM mode, the AIM-120's MRM mode);
# - lock: the radar on (Q) and the drone locked (Enter, then TMS up "/" where Enter only bugs);
# - the IR missiles: the seeker caged on the radar's lock hears the drone (the lock tone, the small diamond); Ctrl + S
#   steps SPOT / SCAN and back; the uncage key (Shift + M) uncages it: it tracks (the HUD's large diamond);
# - SHOOT on the HUD; Space launches (the F-35I's AIM-120 once its bay doors are open);
# - the post-launch cues: the time to active ("A", the AIM-120 head-on from 20 km) or to impact
#   ("T") on the HUD and the FCR's / SRCH's target marked;
# - the drone goes down.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_missiles.gd --log-file <temp>
# tools/test.sh also flies the Sufa's (IAF_SIM_JET=f16i) at --fixed-fps 30 and 120: a hit must not hang on the frame
# rate (docs/real-weapons.md §2.1).
extends "res://../tests/godot/base.gd"

## Range mission, jet, its stations' missiles, the missiles in the order flown with the launch distance (m).
const JETS := [
	[
		"ramon_range",
		"f16i",
		{"1": "aim-9m", "2": "python-5", "3": "aim-120", "7": "aim-120", "8": "python-5", "9": "aim-9m"},
		[["AIM-9M", 2500.0], ["PYTH-5", 2500.0], ["AIM-120", 20000.0]]
	],
	[
		"ramat_david_range",
		"f16d",
		{"1": "aim-9m", "2": "python-5", "3": "aim-120", "7": "aim-120", "8": "python-5", "9": "aim-9m"},
		[["AIM-9M", 2500.0], ["PYTH-5", 2500.0], ["AIM-120", 20000.0]]
	],
	[
		"nevatim_range",
		"f35i",
		{"1": "aim-9x", "3": "aim-120", "5": "aim-120", "11": "aim-9x"},
		[["AIM-9X", 2500.0], ["AIM-120", 20000.0]]
	],
]

var tv: Node
var w
## The nose's lift over the steering point that put the dot into the launch circle (the second missile's).
var _lift := 6.0


func _press(k: Key, shift := false, ctrl := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false, ctrl := false) -> void:
	_press(k, shift, ctrl)
	_press(k, shift, ctrl, false)


## The jet restarted airborne `dist` m behind the drone at its height, speed and heading.
func _behind(d, dist: float) -> void:
	var st: Dictionary = d.state()
	var pos: Vector3 = st.position - st.velocity.normalized() * dist
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, float(st.heading)), st.velocity, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.85


## The jet put for the shot: the IR missiles from behind the drone, the AIM-120 head-on (its zone from behind, about
## 18 km, leaves its launch circle at the smallest inside its seeker's 14 km; real-weapons.md §2.1).
func _set_up_shot(d, dist: float, behind: bool) -> void:
	if behind:
		_behind(d, dist)
		return
	var st: Dictionary = d.state()
	var pos: Vector3 = st.position + st.velocity.normalized() * dist
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(),
		tv.player.fm_section,
		pos,
		Vector3(0, 0, float(st.heading) + 180.0),
		-st.velocity,
		airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.85


## Waits until `cond` holds, at most `limit` s of sim time. With a drone `keep`, the jet is put back 3 km behind it
## every 5 s: nobody flies it while the test waits (a long wait ended in the ground). Each frame the Real HUD is laid
## out as a drawn frame would (headless draws none; the MRM's SHOOT reads the circle it drew).
## The jet restarted where it is, flying `up` degrees above the world point `p` at its speed (an airborne start points
## the nose along the velocity).
func _aim_at(p: Vector3, up := 0.0) -> void:
	var o: Dictionary = w.own()
	var to: Vector3 = (p - o.pos).normalized()
	var hdg := atan2(to.x, to.y)
	var el := asin(to.z) + deg_to_rad(up)
	var dir := Vector3(cos(el) * sin(hdg), cos(el) * cos(hdg), sin(el))
	var speed: float = maxf(Vector3(o.vel).length(), 200.0)
	tv.flight.start(
		settings().own_dir(),
		tv.player.fm_section,
		tv.rig.position,
		Vector3(rad_to_deg(el), 0, rad_to_deg(hdg)),
		w.Terrain.dir_to_scene(dir) * speed,
		airborne_flags()
	)


## Waits for SHOOT. The radar missile: the pilot puts the steering dot into the launch circle, which sits below the
## boresight (real_hud mrm_circle: the F-16's 6° under the gun cross, the F-35I's 4°): the jet flies at the steering
## point, flying half a degree more above it every few frames, held there (the flight model restarted each frame) until
## SHOOT; it stays held for the launch.
func _steer(srm: bool) -> bool:
	if srm:
		return await _until(func(): return bool(tv.cockpit.weapons.get("shoot", false)), 4.0)
	for step in 36:
		_lift = 0.5 * step
		for f in 4:
			var pt = tv.cockpit.weapons.get("mrm_point")
			if pt != null:
				_aim_at(pt, _lift)
			tv.cockpit.hud._real_frame = -1
			tv.cockpit.hud.real_hud()
			await process_frame
		if bool(tv.cockpit.weapons.get("shoot", false)):
			return true
	return false


func _until(cond: Callable, limit: float, keep = null) -> bool:
	if not is_instance_valid(tv):
		return false
	var t0: float = tv._sim_time
	var put := t0
	while is_instance_valid(tv) and not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		if keep != null and tv._sim_time - put > 5.0 and _alive(keep):
			put = tv._sim_time
			_behind(keep, 3000.0)
		tv.cockpit.hud._real_frame = -1
		tv.cockpit.hud.real_hud()
		await process_frame
	return is_instance_valid(tv)


func _rank(p) -> String:
	var n := String(p.ent.name)
	if n.begins_with("Drone 1"):
		return "0"
	if n.begins_with("Drone 2"):
		return "9"
	return "1" + String.chr(126 - n.unicode_at(n.length() - 1))  # the pair: the wingman (the higher number) first


func _alive(d) -> bool:
	return is_instance_valid(d.node) and int(d.ent.state) < 3


## The radar's locked drone (null: none).
func _locked_drone():
	var k := String(w.radar.locked().get("key", "")) if w.radar.has_lock() else ""
	for p in tv.ai.pilots:
		if String(p.ent.key) == k and k != "":
			return p
	return null


func _hud_texts() -> Array:
	tv.cockpit.hud._real_frame = -1
	var r: Dictionary = tv.cockpit.hud.real_hud()
	return r.get("outer", []).filter(func(p): return p.k == "text").map(func(p): return String(p.text))


func run() -> void:
	await require_data()
	var only := OS.get_environment("IAF_SIM_JET")
	for j in JETS:
		if only == "" or only == j[1]:
			print("-- %s" % j[1])
			await _jet(j[0], j[1], j[2], j[3])


func _jet(mission: String, unit: String, hung: Dictionary, flown: Array) -> void:
	var s := settings()
	var id := sim_mission(mission)
	check(load("res://flight/fly.gd").prepare(id), "%s: mission %d prepared as the front end's Fly" % [unit, id])
	# Every missile of the jet on its stations, as the Arming page would hang them (IafBriefing.sim_load).
	var pylons = JSON.parse_string(
		IafBriefing.sim_load(
			ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit),
			ProjectSettings.globalize_path("res://data/db/weapons"),
			JSON.stringify(hung)
		)
	)
	check(pylons is Array and s.arm_loadouts.size() == 1, "%s: the missiles' load built (%s)" % [unit, pylons])
	s.arm_loadouts = {s.arm_loadouts.keys()[0]: pylons}
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-missiles", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the live check off: the jet is put in the air without the tower
	w = tv.weapons
	await fly(tv, 3.0)
	check(not w.seeker.head.is_empty(), "%s: the modern seeker head (cage / uncage) is on" % unit)
	# The drones that fly straight and high: Drone 1, then the pair's wingman and leader (behind the wingman the jet
	# is behind both), Drone 2 (low) last; Drone 3 breaks away from a fighter (its "drone_evade" brain) and is left out.
	var drones: Array = tv.ai.pilots.filter(
		func(p): return int(p.ent.side) == 2 and not String(p.ent.name).begins_with("Drone 3")
	)
	drones.sort_custom(func(a, b): return _rank(a) < _rank(b))
	check(drones.size() >= flown.size(), "%s: a drone for each missile (%d)" % [unit, drones.size()])
	var armed := false
	for k in flown.size():
		# The next drone still flying (an earlier shot may have taken another than its own).
		var live: Array = drones.slice(k) + drones.slice(0, k)
		live = live.filter(func(p): return _alive(p))
		if live.is_empty():
			check(false, "%s: a drone left for the %s" % [unit, flown[k][0]])
			break
		await _shot(unit, live[0], String(flown[k][0]), float(flown[k][1]), armed)
		armed = true
	if is_instance_valid(tv):
		tv.queue_free()
	await frames(5)


func _shot(unit: String, d, name: String, dist: float, armed: bool) -> void:
	var tag := "%s %s" % [unit, name]
	var key := String(d.ent.key)
	_set_up_shot(d, dist, name != "AIM-120")
	await frames(3)
	if not armed:
		_tap(KEY_A, true)  # Shift + A, the master arm
		w.safety_off = true
	check(w.master_arm, "%s: armed" % tag)
	# Select: "]" steps the air-to-air stores.
	var srm: bool = name != "AIM-120"
	for i in 8:
		if w.stores.current_name() == name and w.hud_mode == (1 if srm else 2):
			break
		_tap(KEY_BRACKETRIGHT)
		await frames(2)
	check(
		w.stores.current_name() == name and w.hud_mode == (1 if srm else 2),
		"%s: ']' selects it (%s, HUD mode %d)" % [tag, w.stores.current_name(), w.hud_mode]
	)
	# Lock: the radar on, the drone locked.
	if int(w.radar.mode) < 2:
		_tap(KEY_Q)
		await fly(tv, 3.0)
	# Enter bugs the next target, TMS up ("/") locks the bug. A lock on another live drone of the range serves as well.
	var locked := false
	for attempt in 6:
		var lk = _locked_drone()
		locked = lk != null and _alive(lk)
		if locked:
			d = lk
			key = String(d.ent.key)
			break
		_set_up_shot(d, dist, srm)
		if w.radar.has_lock():
			_tap(KEY_SLASH, true)  # TMS down (Shift + /): the lock on a drone already down is dropped
			await fly(tv, 0.5)
		_tap(KEY_ENTER)
		await fly(tv, 1.0)
		if not w.radar.has_lock():
			_tap(KEY_SLASH)
			await fly(tv, 1.0)
		if not w.radar.has_lock():
			# The pointer: a click on a drone's symbol on the FCR presses TMS up there (lock_key, event 0x2a).
			for ct in w.radar.contacts:
				if tv.ai.pilots.any(func(p): return String(p.ent.key) == String(ct.key) and _alive(p)):
					w.radar.lock_key(String(ct.key))
					break
			await fly(tv, 0.5)
	check(
		locked,
		(
			"%s: the radar locks a drone (%s; mode %d, lock %s, %d contacts)"
			% [tag, key, w.radar.mode, w.radar.locked().get("key", ""), w.radar.contacts.size()]
		)
	)
	_set_up_shot(d, dist, srm)
	await fly(tv, 1.0)
	if srm:
		# Caged on the radar's line of sight: the seeker hears the drone (the lock tone), the small diamond.
		var heard := await _until(func(): return w.seeker.lock and w.seeker.target_key == key, 3.0)
		check(heard and not w.seeker.head.uncaged, "%s: caged, the seeker hears the drone (tone lock)" % tag)
		check(not bool(tv.cockpit.weapons.srm_head.get("tracking", true)), "%s: caged: the small diamond" % tag)
		var scan: bool = w.seeker.head.scan
		_tap(KEY_S, false, true)  # Ctrl + S: SPOT / SCAN
		await frames(2)
		check(w.seeker.head.scan != scan, "%s: Ctrl + S steps SPOT / SCAN" % tag)
		_tap(KEY_S, false, true)
		await frames(2)
		_tap(KEY_M, true)  # Shift + M: uncage
		await fly(tv, 0.5)
		check(
			w.seeker.head.uncaged and bool(tv.cockpit.weapons.srm_head.get("tracking", false)),
			"%s: Shift + M uncages: the seeker tracks the drone, the large diamond (%s)" % [tag, w.seeker.head]
		)
	var shoot := await _steer(srm)
	var wp: Dictionary = tv.cockpit.weapons
	check(
		shoot,
		(
			"%s: SHOOT (dlz %s, dist %.0f, circle %s, point at %s px, Real HUD inside %s)"
			% [
				tag,
				tv.cockpit.radar.get("dlz", []),
				float(w.radar.locked().get("dist", 0.0)),
				wp.circle,
				w.IrSeeker.screen_offset(w.own(), wp.mrm_point) if wp.mrm_point != null else null,
				tv.cockpit.hud.real_mrm_inside()
			]
		)
	)
	if tv.cockpit.hud_on_glass:  # the F-16s' combiners (avionics-plan.md B9): the widest layout, the DLZ's
		var was: Vector2i = await project_window()  # a text measured at a real size (base.gd project_window)
		var off := off_glass(tv.cockpit)
		check(off.is_empty(), "%s: the combiner holds the HUD (outside %s of %s)" % [tag, off, tv.cockpit.hud_clip])
		root.size = was
		await frames(2)
	var before: int = w.missiles.size()
	_press(KEY_SPACE)
	var gone := await _until(func(): return w.missiles.size() > before, 3.0)  # the F-35I's bay doors open first
	_press(KEY_SPACE, false, false, false)
	check(gone, "%s: Space launches" % tag)
	var mis = w.missiles.back() if gone else null
	check(mis != null and String(mis.target_key) == key, "%s: the missile flies at the drone" % tag)
	# The post-launch cues: the time to active (the AIM-120 from beyond its seeker's reach) or to impact.
	var cue = null
	if await _until(func(): return tv.cockpit.weapons.get("msl_time") != null, 2.0):
		cue = tv.cockpit.weapons.msl_time
	check(
		cue != null and bool(cue.active) == (not srm),
		"%s: the post-launch time %s (%s)" % [tag, "to active" if not srm else "to impact", cue]
	)
	if cue != null:
		var want := ("A%02d" if cue.active else "T%02d") % mini(ceili(float(cue.s)), 99)
		var texts := _hud_texts()
		check(
			texts.any(func(t): return t.length() == 3 and t[0] == want[0] and t.substr(1).is_valid_int()),
			"%s: the HUD shows the time (%s in %s)" % [tag, want, texts]
		)
	check(tv.cockpit.weapons.get("msl_targets", {}).has(key), "%s: the FCR marks the missile's target" % tag)
	if not srm:
		var t_seen := await _until(
			func(): return tv.cockpit.weapons.get("msl_time") != null and not tv.cockpit.weapons.msl_time.active,
			30.0,
			d
		)
		check(t_seen, "%s: the cue turns to the time to impact once the seeker is active" % tag)
	var killed := await _until(func(): return int(d.ent.state) >= 3 or not mis in w.missiles, 60.0, d)
	killed = killed and int(d.ent.state) >= 3
	if not killed and mis != null and not mis in w.missiles and _alive(d):
		print("%s: the missile burst %.0f m from the drone" % [tag, mis.last_pos.distance_to(w._rwr_unit(key).pos)])
	var second := false
	if not killed and _alive(d):
		# A miss (the shared model's chase): the second missile of the pair, the same steps.
		second = true
		_set_up_shot(d, dist, srm)
		await fly(tv, 1.0)
		if srm and not w.seeker.head.uncaged:
			_tap(KEY_M, true)
			await fly(tv, 0.5)
		await _steer(srm)
		_press(KEY_SPACE)
		await fly(tv, 1.5)
		_press(KEY_SPACE, false, false, false)
		killed = await _until(func(): return int(d.ent.get("state", 3)) >= 3, 60.0, d)
	check(
		killed,
		(
			"%s: the drone goes down (state %d%s)"
			% [tag, int(d.ent.get("state", 3)), ", the second missile" if second else ""]
		)
	)
	await fly(tv, 1.0)
