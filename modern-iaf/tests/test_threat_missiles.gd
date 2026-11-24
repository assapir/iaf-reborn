# Modern IAF's threat missiles on the physical missile (docs/real-weapons.md §2.1, §2.6; docs/ai.md §15.1;
# modern-iaf/docs/avionics-plan.md §7.2 step 5) and the jammer against a missile's seeker (ai-plan.md K9), headless on
# the Sufa's weapons range:
# - the MiG-29A's R-73 (from behind) and R-27R (head on) fly their records' motor and burst at the jet;
# - a Tor-M1 launches its own 9M331 (type 630, a radar SAM the RWR hears) and it bursts at the jet; an S-300's
#   launchers carry the 48N6E2, lofting;
# - the Sufa's jammer (J): a radar seeker outside its burn-through rolls once on its chance (the 48N6E2's 0.12, the
#   R-27R's 0.3), one inside it or with the jammer off none; a seeded run of R-27Rs loses some, not all.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_threat_missiles.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const ALT := 3000.0
## The jet's travel in one 0.05 s frame at 200 m/s.
const FRAME_M := 10.0

var tv: Node
var w


## The jet `agl` m above the ground at `at` (world), flying north at `speed` m/s.
func _put(at: Vector3, agl: float, speed: float) -> void:
	var g = tv.mission_ground(at)
	var sp: Vector3 = tv.world_to_scene(Vector3(at.x, at.y, float(g if g != null else 0.0) + agl))
	tv.rig.position = sp
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, sp, Vector3.ZERO, Vector3(0, 0, -speed), airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.85


## Flies until `f` holds, at most `s` s; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await fly(tv, 0.25)
	return f.call()


func _record(name: String) -> Dictionary:
	for id in w.db.weapons:
		if String(w.db.weapons[id].get("name", "")) == name:
			return w.db.weapons[id]
	return {}


## Flies until missile `m` ends (at most `s` s); its burst's distance from the jet then, INF when it did not end. The
## jet is read at the frame's start: it moves up to `FRAME_M` within the frame.
func _burst(m, s: float) -> float:
	var miss := INF
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s:
		var at: Vector3 = w.own().pos
		await fly(tv, 0.05)
		if not m in w.missiles:
			miss = m.last_pos.distance_to(at)
			break
	return miss


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-tm", false).get_current_dir()
	tv.addon.result = {"pass": true}
	s.invulnerable = true
	w = tv.weapons
	var rt: Node = tv.runtime
	check(s.modern_ew() and s.modern_fuzes(), "Modern IAF's countermeasure and fuze rules")
	var j: Vector3 = tv.player_world()
	_put(j, ALT, 200.0)
	await fly(tv, 0.5)
	var me := String(rt.player_entity().key)

	# --- the MiG-29A's missiles -------------------------------------------------------------------------------------
	var r73: Dictionary = _record("R-73")
	var r27: Dictionary = _record("R-27R")
	check(not r73.is_empty() and not r27.is_empty(), "the R-73 and R-27R records")
	if r73.is_empty() or r27.is_empty():
		return
	for pair in [[r73, 8840.0], [r27, 39242.0]]:
		var m: Dictionary = w._motion(pair[0])
		check(
			float(m.get("_motorThrust", 0.0)) == pair[1],
			"%s: the physical missile's motor (%s; rebuild the db step)" % [pair[0].name, m.get("_motorThrust")]
		)
	var o: Dictionary = w.own()
	var mig: Dictionary = tv.ai.spawn("mig29a", o.pos - o.fwd * 3000.0, 0.0, [])
	check(not mig.is_empty(), "a MiG-29A behind")
	if mig.is_empty():
		return
	var behind := {"vel": o.vel, "fwd": o.fwd, "up": o.up, "right": o.right}
	var a = w.launch_homing(r73, o.pos - o.fwd * 3000.0, behind, me, 1.0, mig)
	var miss: float = await _burst(a, 30.0)
	print("R-73 from 3 km behind: burst %.1f m from the jet" % miss)
	check(miss <= float(r73.radius) + FRAME_M and not a.dud, "the R-73 bursts at the jet (%.1f m)" % miss)
	o = w.own()
	var head := {"vel": -o.fwd * 250.0, "fwd": -o.fwd, "up": o.up, "right": o.right}
	var b = w.launch_homing(r27, o.pos + o.fwd * 15000.0, head, me, 1.0, mig)
	miss = await _burst(b, 40.0)
	print("R-27R from 15 km ahead: burst %.1f m from the jet" % miss)
	check(miss <= float(r27.radius) + FRAME_M and not b.dud, "the R-27R bursts at the jet (%.1f m)" % miss)

	# --- the SAM sites' own missiles ----------------------------------------------------------------------------------
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	j = tv.player_world()
	var s300: Array = ad.spawn("s300", j + Vector3(60000, 60000, 0), 0.0, [])
	var ss: Dictionary = ad.site_of(s300[0])
	ss.site.set_emcon("silent")
	var u48 = ss.units.filter(func(u): return u != null)[0]
	var m48: Dictionary = w._motion(u48.w)
	print("S-300's record: %s type %d, loft %s" % [u48.w.name, u48.w.type, m48.get("_loft")])
	check(u48.w.name == "48N6E2" and int(u48.w.type) == 630, "the S-300 fires its 48N6E2 (a radar SAM)")
	check(float(m48.get("_loft", 0.0)) == 1.0 and float(m48.get("_motorThrust", 0.0)) > 0.0, "physical, lofting")
	var tor: Array = ad.spawn("tor", j + Vector3(0, 11000, 0))
	var ts: Dictionary = ad.site_of(tor[0])
	ts.site.set_emcon("radiate")
	check(await _until(func(): return not ts.flying.is_empty(), 60.0), "the Tor launches")
	if ts.flying.is_empty():
		return
	var c = ts.flying[0][0]
	print("Tor's missile: %s type %d" % [c.weapon.name, c.weapon.type])
	check(c.weapon.name == "9M331" and int(c.weapon.type) == 630, "its own 9M331 (a radar SAM)")
	check(float(w._motion(c.weapon).get("_motorThrust", 0.0)) > 0.0, "on the physical missile")
	check(w.rwr.any_launch(), "the RWR hears its launch")
	miss = await _burst(c, 30.0)
	print("9M331: burst %.1f m from the jet" % miss)
	check(miss <= float(c.weapon.radius) + FRAME_M, "the 9M331 bursts at the jet (%.1f m)" % miss)
	ts.site.set_emcon("silent")
	for m in w.missiles:
		m.guidance_off = true
	await fly(tv, 0.5)

	# --- K9: the jammer against the seeker -----------------------------------------------------------------------------
	if not tv.cockpit.indicators[6]:
		w.ecm_key()
	check(is_equal_approx(w.jam_share(), 0.3), "the Sufa's jammer on (J)")
	o = w.own()
	head = {"vel": -o.fwd * 250.0, "fwd": -o.fwd, "up": o.up, "right": o.right}
	var far = w.launch_homing(u48.w, o.pos + o.fwd * 30000.0, head, me, 1.0, u48.ent)
	var near = w.launch_homing(u48.w, o.pos + o.fwd * 5000.0, head, me, 1.0, u48.ent)
	await fly(tv, 0.2)
	o = w.own()
	var jet := {
		"pos": o.pos,
		"vel": o.vel,
		"rcs": s.airframe(w.jet_type).get("rcs"),
		"bays": w.bay_open(),
		"stores": w.stores.external(),
		"jam": w.jam_share()
	}
	var p_far: float = far.jam_chance(w.now, jet)
	var p_near: float = near.jam_chance(w.now, jet)
	var p_off: float = far.jam_chance(w.now, jet.merged({"jam": 0.0}, true))
	print("48N6E2 against the jammer: 30 km %.3f, 5 km %.3f, jammer off %.3f" % [p_far, p_near, p_off])
	check(is_equal_approx(p_far, 0.6 * (1.0 - 0.8)), "outside the burn-through: its counter-countermeasures' share")
	check(p_near == 0.0 and p_off == 0.0, "inside the burn-through, or no jamming: none")
	check(far.has_meta("jam_rolled") and not near.has_meta("jam_rolled"), "rolled once outside, not inside")
	far.guidance_off = true
	near.guidance_off = true
	seed(5)
	var run := []
	for i in 10:
		run.append(w.launch_homing(r27, o.pos + o.fwd * (25000.0 + 200.0 * i), head, me, 1.0, mig))
	await fly(tv, 0.2)
	var broken := run.filter(func(m): return m.guidance_off).size()
	print("R-27Rs against the jammer: %d of 10 lost" % broken)
	check(run.all(func(m): return m.has_meta("jam_rolled")), "each rolled")
	check(broken > 0 and broken < 10, "the seeded run: some lost (%d), not all" % broken)
	for m in w.missiles:
		m.guidance_off = true
	w.ecm_key()
