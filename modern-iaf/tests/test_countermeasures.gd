# Modern IAF's countermeasures and jamming (docs/real-weapons.md §2.3, docs/ai.md §15.6; modern-iaf/docs/ai-plan.md
# K8, K9), headless on the Sufa's weapons range:
# - decoys: an AIM-9M and an AIM-9X launched at the jet from behind by a MiG-29A (the dev hook ai_flights.gd `spawn`):
#   each seeker's own chance (the AIM-9X's imaging seeker lower, chaff none against infrared, the afterburner cuts a
#   flare's), and the release path's roll takes the AIM-9M with a seeded run of flares; chaff against an AIM-120 on
#   the beam above a jet flying straight away;
# - the Sufa's jammer (J): an S-300 80 km ahead finds the jet but its track radar cannot lock it while the jammer is
#   on (its burn-through ~61 km with the 8 stores' 5.2 m2 head-on); the threat display shows the jamming chevrons;
#   jammer off, the lock comes;
# - an enemy jet jamming 50 km ahead shows on the player's radar as a strobe, not a contact.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_countermeasures.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const ALT := 8000.0

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


func _tap(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		tv._unhandled_input(e)


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-cm", false).get_current_dir()
	tv.addon.result = {"pass": true}
	s.invulnerable = true
	w = tv.weapons
	var rt: Node = tv.runtime
	check(s.modern_ew(), "Modern IAF's countermeasure rules")
	var j: Vector3 = tv.player_world()
	_put(j, ALT, 250.0)
	await fly(tv, 0.5)
	j = tv.player_world()

	# --- K8: decoys against the seekers -----------------------------------------------------------------------------
	var mig: Dictionary = tv.ai.spawn("mig29a", j + Vector3(0, -2000, 0), 0.0, [])
	check(not mig.is_empty(), "the launcher behind")
	var m9: Dictionary = _record("AIM-9M")
	var m9x: Dictionary = w.db.weapons.get(1001, _record("AIM-9X"))  # the sim flies modern_weapons.gd's 1001
	var m120: Dictionary = _record("AIM-120")
	check(not m9.is_empty() and not m9x.is_empty() and not m120.is_empty(), "the AIM-9M, AIM-9X and AIM-120 records")
	if mig.is_empty() or m9.is_empty() or m9x.is_empty() or m120.is_empty():
		return
	var me := String(rt.player_entity().key)
	var o: Dictionary = w.own()
	var from := {"vel": o.vel, "fwd": o.fwd, "up": o.up, "right": o.right}
	var launch := func(rec: Dictionary):
		w.launch_homing(rec, o.pos - o.fwd * 2000.0, from, me, 1.0, mig)
		return w.missiles[-1]
	var a = launch.call(m9)
	var x = launch.call(m9x)
	var r = launch.call(m120)
	await fly(tv, 1.5)  # the motors burn: closing
	o = w.own()
	var jet := {"pos": o.pos, "vel": o.vel, "ab": false, "g": 1.0}
	var p9: float = a.decoy_chance(true, true, w.now, jet)
	var p9x: float = x.decoy_chance(true, true, w.now, jet)
	var p_ab: float = a.decoy_chance(true, true, w.now, jet.merged({"ab": true}, true))
	var p_chaff_ir: float = a.decoy_chance(false, true, w.now, jet)
	print("flare: AIM-9M %.3f, AIM-9X %.3f, AIM-9M beside the afterburner %.3f" % [p9, p9x, p_ab])
	check(p9 > p9x and p9x > 0.0, "the imaging seeker rejects more (%.3f > %.3f)" % [p9, p9x])
	check(is_equal_approx(p_ab, p9 * 0.25), "a lit afterburner outshines the flare")
	check(p_chaff_ir == 0.0, "chaff does nothing to an infrared seeker")
	var beam := jet.merged({"vel": Vector3(250, 0, 0)}, true)
	var pc_away: float = r.decoy_chance(false, false, w.now, jet)
	var pc_beam: float = r.decoy_chance(false, false, w.now, beam)
	print("chaff on the AIM-120: away %.3f, beam %.3f" % [pc_away, pc_beam])
	check(pc_beam > 3.0 * pc_away and pc_away > 0.0, "chaff works on the beam")
	# The release path: a seeded run of flares takes the AIM-9M (each its own roll, no first-failure stop).
	seed(11)
	var taken := false
	for i in 15:
		if not w.release_decoy(550, o.pos, o, me, false, 1.0):
			break
		taken = String(a.target_key).begins_with("decoy:")
		if taken:
			break
	check(taken, "a flare takes the AIM-9M (%s)" % a.target_key)
	for m in [a, x, r]:
		m.guidance_off = true

	# --- K9: the Sufa's jammer against an S-300 -----------------------------------------------------------------------
	_put(j + Vector3(0, 20000, 0), ALT, 150.0)
	await fly(tv, 0.5)
	j = tv.player_world()
	if not tv.cockpit.indicators[6]:
		w.ecm_key()
	print("jam share %.2f (%s)" % [w.jam_share(), s.airframe(w.jet_type).get("name", "")])
	check(is_equal_approx(w.jam_share(), 0.3), "the Sufa's jammer on (J): its burn-through share")
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var s300: Array = ad.spawn("s300", Vector3(j.x, j.y + 80000, 0), 180.0, [])
	var site: Dictionary = ad.site_of(s300[0])
	site.site.set_emcon("radiate")
	# (The site's own track list: the RWR shows a lock past its range as inactive.)
	var locked := func(): return not site.locked.is_empty()
	var searched := func(): return w.rwr.display().any(func(e): return e.search and int(e.type) == 310)
	check(await _until(searched, 6.0), "the S-300 searches")
	check(not await _until(locked, 25.0), "jamming at 80 km: its track radar holds no lock")
	var syms: Array = tv.cockpit.ews.get("symbols", [])
	print("symbols: ", syms.map(func(sy): return [sy.label, sy.get("jammed", false)]))
	check(syms.any(func(sy): return String(sy.label) == "5" and sy.get("jammed", false)), "the jamming chevrons >5<")
	w.ecm_key()
	check(w.jam_share() == 0.0, "the jammer off")
	check(await _until(locked, 25.0), "unjammed: the lock comes")
	site.site.set_emcon("silent")

	# --- K9: an enemy jammer on the player's radar --------------------------------------------------------------------
	tv._command([200, 0, 0])
	tv._command([213, 0, 0])
	await fly(tv, 3.0)
	if int(w.radar.mode) != w.radar.LRS:
		_tap(KEY_Q)
	await fly(tv, 1.0)
	o = w.own()
	# (Level ahead: the jet's climb would put it above the scan.)
	var ahead: Dictionary = tv.ai.spawn(
		"mig29a", o.pos + Vector3(o.fwd.x, o.fwd.y, 0).normalized() * 50000.0, 180.0, []
	)
	check(not ahead.is_empty(), "a jet 50 km ahead")
	if ahead.is_empty():
		return
	ahead["jam"] = 0.3  # the dev hook: its jammer on (the MiG-29A (9.12) has none, docs/ai.md §15.6)
	var strobed := func(): return not w.radar.strobes().is_empty()
	check(await _until(strobed, 15.0), "its strobe on the radar (mode %d)" % w.radar.mode)
	check(not w.radar.contacts.any(func(c): return c.key == ahead.key), "and no contact past the burn-through")
	check(tv.cockpit.radar.get("strobes", []).size() > 0, "the cockpit's radar copy carries it")
	ahead["jam"] = 0.0
	var seen := func(): return w.radar.contacts.any(func(c): return c.key == ahead.key)
	check(await _until(seen, 15.0), "not jamming: a contact")
