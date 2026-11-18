# The F-16s' bomb release submodes, fuzing and the laser path (avionics slice 9; modern-iaf/docs/weapons.md §9) on the
# weapons range, headless: <base>_range set up as the front end's Fly does.
# - MK-82s on stations 3 and 7, the flight model frozen and the jet flown on a scripted path, WPN REL (Space) held as
#   the pilot holds it: CCRP level, DTOS in a dive then a toss pull-out, LADD's run-in at 200 ft and 4 g pull-up at
#   the cue, MAN in a dive released with the reticle on the target; each bomb bursts within its blast radius (the
#   record's blast_m, the bomb's spread) of the range's Target 1.
# - The SMS: OSB 2's menu lists CCIP CCRP DTOS LADD MAN and picks one, OSB 18 the fuze, OSB 17 the arming delay.
# - A MAN release at 150 ft: LOW, and the bomb hits before its fuze arms: a dud, no burst.
# - The laser path, flying (the 6-DoF): a GBU-12 in CCRP with the Litening slaved to the target and LASER ARM; the
#   release automatic, the bomb guided onto the spot within its blast radius.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_bombs.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const DT := 0.05

var tv: Node
var w
var c
## The scripted sim time (the frozen flight).
var t := 0.0


func _press(k: Key, shift := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false) -> void:
	_press(k, shift)
	_press(k, shift, false)


func run() -> void:
	await require_data()
	for unit in sim_f16s():
		print("-- %s" % unit)
		await _scripted(unit, sim_f16s()[unit])
		await _laser(unit, sim_f16s()[unit])


func _start(unit: String, base: String, load: Array) -> Vector3:
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo := ""
	for l in load:
		lo = IafBriefing.put(rec, lo, int(l[0]), String(l[1]), bool(l[2]))
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-bombs", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	var hulk := {}
	for e in tv.runtime.entities.values():
		if String(e.name) == "Target 1":
			hulk = e
	check(not hulk.is_empty(), "the range's Target 1")
	var p: Vector3 = hulk.world
	p.z = float(tv.mission_ground(p))
	return p


## The jet at world `p` with world velocity `v`: the rig there, the flight model restarted (stopped) at `v`.
func _at(p: Vector3, v: Vector3) -> void:
	var sp: Vector3 = tv.world_to_scene(p)
	tv.rig.position = sp
	var vs := Vector3(v.x, v.z, -v.y)
	tv.rig.basis = Basis.looking_at(vs.normalized(), Vector3.UP)
	# The attitude along the velocity (pitch, roll, heading in degrees): the flight model holds the speed along it.
	var att := Vector3(rad_to_deg(asin(v.z / v.length())), 0.0, rad_to_deg(atan2(v.x, v.y)))
	tv.flight.start(settings().own_dir(), tv.player.fm_section, sp, att, vs, airborne_flags())
	w.scripted_vel = v  # the 6-DoF starts level: the weapons take the path's own velocity


## One scripted step: the jet moved along `v` (world), the weapons updated at the new time.
func _step(v: Vector3) -> void:
	tv.rig.position += Vector3(v.x, v.z, -v.y) * DT
	t += DT
	w.update(t)


## Follows the player's falling bomb until it is gone: where its path first met the ground (the burst itself waits
## for the next of the impact checks, 0.5 s apart: docs/weapons.md §9), else its last point; null when none fell.
func _impact(max_s := 60.0) -> Variant:
	var last = null
	var t0 := t
	while t - t0 < max_s:
		var bm = w.bombs.back() if not w.bombs.is_empty() else null
		var q = null
		if bm == null and not w.guided.is_empty():
			q = w.guided.back().position(t)
		elif bm != null:
			q = ClassDB.class_call_static("IafBomb", "position", bm.b, t)
		elif last != null:
			return last
		if q != null:
			last = q
			var g = tv.mission_ground(q)
			if g != null and q.z <= float(g):
				while not (w.bombs.is_empty() and w.guided.is_empty()) and t - t0 < max_s:
					t += DT
					w.update(t)
				return q
		t += DT
		w.update(t)
		await process_frame
	return last


func _released() -> int:
	return w.stores.total(500, "MK-82")


## Flies `path` (Callable(i) -> world velocity of step i) until a bomb leaves (WPN REL held from the start), at most
## `max_s`; true when it left.
func _until_release(path: Callable, max_s: float) -> bool:
	var before := _released()
	w.fire_selected()
	var v: Vector3 = path.call(0)
	var i := 0
	while _released() == before and i * DT < max_s:
		i += 1
		var nv: Vector3 = path.call(i)
		if not nv.is_equal_approx(v):
			v = nv
			_at(w.to_world(tv.rig.position), v)
		_step(v)
		if i % 20 == 0:
			await process_frame
	w.release_selected()
	return _released() < before


func _hit(what: String, p: Vector3, radius: float) -> void:
	var at = await _impact()
	var d := INF if at == null else Vector2(at.x - p.x, at.y - p.y).length()
	check(d < radius, "%s: the bomb bursts %.1f m from Target 1 (spread %.0f m)" % [what, d, radius])


func _scripted(unit: String, base: String) -> void:
	var p := await _start(unit, base, [[3, "mk-82", true]])
	tv.frozen = true
	tv.fm_stopped = true
	tv.gear_down = false
	# The range's target steerpoint, on Target 1: the SPI without a designation.
	for k in c.waypoints.size():
		if (c.waypoints[k].world as Vector2).distance_to(Vector2(p.x, p.y)) < 300.0:
			c.current_waypoint = k
	var sp: Vector2 = c.waypoints[c.current_waypoint].world
	check(
		sp.distance_to(Vector2(p.x, p.y)) < 300.0,
		"a steerpoint on Target 1 (%.0f m)" % sp.distance_to(Vector2(p.x, p.y))
	)
	t = tv._sim_time
	w.master_arm = true
	w.safety_off = true
	w.release_pairs = false
	w._ripple.set_values(1, 10)  # SGL, one pulse a press
	_at(p + Vector3(-9000, 0, 1000), Vector3(200, 0, 0))
	w._push_stores()
	w.select_ag()
	w.update(t)
	await frames(2)
	var radius := float(w.stores.station(w.stores.cur).w.radius)
	check(w.hud_mode == 5 and w.delivery_on(), "MK-82 selected, A-G: the submodes apply")
	await _sms()
	await _ccrp(p, radius)
	await _dtos(p, radius)
	await _ladd(p, radius)
	await _man(p, radius)
	await _low(p)
	tv.frozen = false
	tv.fm_stopped = false
	w.scripted_vel = null


## OSB 2 opens the menu with the five submodes; OSB 19 (the second) picks CCRP; OSB 18 the fuze, OSB 17 the delay.
func _sms() -> void:
	var f = c.mfds[1].real_fmt
	f._own_sms(2)
	check(f.sms_sub, "OSB 2: the submode menu")
	var subs: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "ag_submodes", false)
	check(Array(subs) == ["CCIP", "CCRP", "DTOS", "LADD", "MAN"], "the menu: %s" % [subs])
	f._own_sms(19)
	w.update(t)
	check(w.ag_submode() == "CCRP" and not f.sms_sub, "OSB 19: CCRP, the menu closed")
	f._own_sms(18)
	w.update(t)
	check(String(c.weapons.delivery_set.fuze) == "NOSE", "OSB 18: NOSE (%s)" % c.weapons.delivery_set.fuze)
	f._own_sms(17)
	w.update(t)
	check(is_equal_approx(float(c.weapons.delivery_set.ad), 6.0), "OSB 17: AD 6.00 s")
	tv._press([290, 1, 0])
	tv._press([290, 1, 0])
	tv._press([290, 2, 0])
	tv._press([290, 2, 0])
	tv._press([290, 2, 0])
	tv._press([290, 2, 0])
	tv._press([290, 2, 0])
	w.update(t)
	var ds: Dictionary = c.weapons.delivery_set
	check(
		String(ds.fuze) == "NSTL" and is_equal_approx(float(ds.ad), 4.8), "the keys: NSTL, AD 4.80 s round (%s)" % [ds]
	)


## CCRP level at 1,000 m, 200 m/s, the radar's designated point on the target: the release by itself.
func _ccrp(p: Vector3, radius: float) -> void:
	w.radar.designate(p.x, p.y, p.z, t)
	_at(p + Vector3(-7000, 0, 1000), Vector3(200, 0, 0))
	w.update(t)
	var dl: Dictionary = w.ag.delivery
	check(
		dl.get("ttr") != null and float(dl.ttr) > 0.0 and dl.target != null,
		"CCRP: a time to release (%s)" % [dl.get("ttr")]
	)
	check(String(c.weapons.ag.delivery.submode) == "CCRP", "the HUD gets CCRP's cues")
	var ok := await _until_release(func(_i): return Vector3(200, 0, 0), 40.0)
	check(ok, "CCRP: released by itself, WPN REL held")
	await _hit("CCRP", p, radius)


## DTOS: a 30° dive at 250 m/s on the target, WPN REL designates under the TD box; a 4 g pull-out after 2 s releases.
func _dtos(p: Vector3, radius: float) -> void:
	tv._press([290, 0, 0])  # CCRP → CCIP
	tv._press([290, 0, 0])  # CCIP → DTOS
	w.update(t)
	check(w.ag_submode() == "DTOS" and w.dtos_point == null, "the missile step key: DTOS, the TD box on the marker")
	var h := 2000.0
	var g0 := deg_to_rad(-30.0)
	_at(p + Vector3(-h / tan(-g0), 0, h), Vector3(cos(g0), 0, sin(g0)) * 250.0)
	w.update(t)
	var gamma := [g0]
	var path := func(i: int) -> Vector3:
		if i * DT > 2.0 and gamma[0] < deg_to_rad(20.0):
			gamma[0] += 9.80665 * (4.0 - cos(gamma[0])) / 250.0 * DT
		return Vector3(cos(gamma[0]), 0, sin(gamma[0])) * 250.0
	var ok := await _until_release(path, 20.0)
	check(
		w.dtos_point != null and w.dtos_point.distance_to(p) < 150.0,
		"WPN REL designated the target (%s)" % [w.dtos_point]
	)
	check(ok, "DTOS: released in the pull-out")
	await _hit("DTOS", p, radius)


## LADD: 200 ft over the target's height at 283 m/s (550 KTAS), the pull-up at the cue (4 g to 45°).
func _ladd(p: Vector3, radius: float) -> void:
	w.set_ag_submode("LADD")
	_at(p + Vector3(-13000, 0, 61), Vector3(283, 0, 0))
	w.update(t)
	check(w.ag.delivery.get("pull_up") != null, "LADD: a time to the pull-up")
	var state := {"gamma": 0.0, "pull": false}
	var path := func(_i: int) -> Vector3:
		if not state.pull and w.ag.delivery.get("pull_up") != null and float(w.ag.delivery.pull_up) <= DT:
			state.pull = true
		if state.pull and state.gamma < deg_to_rad(45.0):
			state.gamma = minf(state.gamma + 9.80665 * (4.0 - cos(state.gamma)) / 283.0 * DT, deg_to_rad(45.0))
		return Vector3(cos(state.gamma), 0, sin(state.gamma)) * 283.0
	var ok := await _until_release(path, 60.0)
	check(state.pull and ok, "LADD: the pull-up at the cue, released in the climb")
	await _hit("LADD", p, radius)


## MAN: a 30° dive; the pilot presses with the reticle on the target (here: the bombs' own fall point reaches it).
func _man(p: Vector3, radius: float) -> void:
	w.set_ag_submode("MAN")
	var g0 := deg_to_rad(-30.0)
	var v := Vector3(cos(g0), 0, sin(g0)) * 230.0
	# The flight path meets the ground 500 m past the target; the bombs' fall, short of it, runs onto the target.
	_at(p + Vector3(-1600.0 / tan(-g0) + 500.0, 0, 1600), v)
	w.update(t)
	var i := 0
	while float(w.ag.impact.x) < p.x and i < 600:
		_step(v)
		i += 1
	var before := _released()
	w.fire_selected()
	_step(v)
	w.release_selected()
	check(_released() == before - 1, "MAN: released at once")
	await _hit("MAN", p, radius)


## MAN at 150 ft over open ground 4 km short of the target: LOW, and a dud.
func _low(p: Vector3) -> void:
	var at := p + Vector3(-6000, 0, 0)
	at.z = float(tv.mission_ground(at)) + 150.0 * 0.3048
	var v := Vector3(220, 0, 0)
	_at(at, v)
	w.update(t)
	check(bool(w.ag.delivery.get("low", false)), "150 ft: LOW")
	var d0: int = w.duds
	var before := _released()
	w.fire_selected()
	_step(v)
	w.release_selected()
	check(_released() == before - 1, "released at 150 ft")
	await _impact(15.0)
	check(w.duds == d0 + 1, "the bomb hit before its fuze armed: a dud (%d)" % (w.duds - d0))


## The laser path, flying: a GBU-12 in CCRP on the radar's designated target, the Litening slaved to it with LASER
## ARM: the release by itself and the bomb on the spot.
func _laser(unit: String, base: String) -> void:
	var p := await _start(unit, base, [[5, "litening", false], [3, "gbu-12", true]])
	var pos: Vector3 = tv.world_to_scene(p + Vector3(-7000, 0, 1000))
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 90), Vector3(200, 0, 0), airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.85
	await fly(tv, 0.5)
	w.select_ag()
	await frames(3)
	var k: int = Array(c.mfds[0].real.state().slots).find("TGP")
	c.mfds[0].press(7 + k)  # the format row's OSB 14 - k (test_sim_pod.gd osb): the TGP
	await frames(2)
	c.soi = 0
	w.radar.designate(p.x, p.y, p.z, w.now)
	_tap(KEY_SLASH, true)  # TMS down: the pod slaved to the designation
	_tap(KEY_L, true)  # LASER ARM
	_tap(KEY_A, true)  # MASTER ARM
	w.safety_off = true
	w.release_pairs = false
	w._ripple.set_values(1, 10)
	tv._press([290, 0, 0])
	tv._press([290, 0, 0])
	await fly(tv, 0.2)
	check(w.ag_submode() == "CCRP" and int(w.stores.current_type()) == 650, "GBU-12 in CCRP")
	var before: int = w.stores.total(650, "GBU-12")
	w.fire_selected()
	var t0: float = tv._sim_time
	while w.stores.total(650, "GBU-12") == before and tv._sim_time - t0 < 40.0:
		await process_frame
	w.release_selected()
	check(w.stores.total(650, "GBU-12") == before - 1, "CCRP released the GBU-12 by itself")
	var g = w.guided.back() if not w.guided.is_empty() else null
	check(g != null and g.aim.distance_to(p) < 40.0, "the GBU-12 takes the target at the release")
	var lased := false
	while g != null and g in w.guided and tv._sim_time - t0 < 90.0:
		lased = lased or w.eo.laser
		await process_frame
	check(lased, "the pod's laser fired during the fall")
	# The guided motion's burst (guided.rs update: on the aim within its burst distance).
	var last = g.last_pos if g != null else null
	var radius := float(w.stores.station(2).w.radius)
	var d := INF if last == null else Vector2(last.x - p.x, last.y - p.y).length()
	check(d < radius, "the laser path: the GBU-12 bursts %.1f m from the target (spread %.0f m)" % [d, radius])
