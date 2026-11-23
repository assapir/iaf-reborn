# Modern IAF's shoulder-fired teams (docs/ai.md §15.8; shared/ai/air_defence.gd over the Rust site in
# crates/iaf-ai/src/site.rs) on the Sufa's weapons range, headless. The jet comes into sight 1 km past two Igla teams
# (it "pops up" there), going away low:
# - by skill: the High crew launches after its drill, the Low crew's drill takes so long that the jet leaves the
#   missile's reach first; nothing on the RWR from the team (no radar), the MAW warns "SAM"; the missile (type 620,
#   the team's own record) hits the jet that drops no flares;
# - flares: a Strela-2M team's first-generation seeker rejects no flare (the Igla's 0.6), and a seeded run of flares
#   decoys its missile, which misses.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_manpads.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const AGL := 300.0

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
	tv.throttle = 0.74  # MIL (joystick.gd): no afterburner, still pulling away from the Low crew


## Flies until `f` holds, at most `s` s; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await fly(tv, 0.25)
	return f.call()


## Flies in short steps until missile `m` ends (at most `s` s): its closest pass to the jet (m).
func _pass(m, s: float) -> float:
	var t0: float = tv._sim_time
	var near := INF
	while tv._sim_time - t0 < s and m in w.missiles:
		near = minf(near, m.position(w.now).distance_to(tv.player_world()))
		await fly(tv, 0.02)
	return minf(near, m.last_pos.distance_to(tv.player_world()))


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-manpads", false).get_current_dir()
	tv.addon.result = {"pass": true}
	s.invulnerable = true  # the missile reaches the jet; the checks go on
	w = tv.weapons
	var rt: Node = tv.runtime
	var me := String(rt.player_entity().key)
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	_put(j + Vector3(0, -20000, 0), 3000.0, 200.0)  # away while the teams set up
	var high_ents: Array = ad.spawn("igla", Vector3(j.x, j.y, 0))
	var low_ents: Array = ad.spawn("igla", Vector3(j.x + 30, j.y, 0))
	check(high_ents.size() == 1 and low_ents.size() == 1, "two Igla teams")
	if high_ents.is_empty() or low_ents.is_empty():
		return
	var high: Dictionary = ad.site_of(high_ents[0])
	var low: Dictionary = ad.site_of(low_ents[0])
	high.site.set_skill(2)
	low.site.set_skill(0)
	var rec: Dictionary = high.units[0].w
	check(String(rec.name) == "IGLA" and int(rec.type) == 620, "the team's own heat-SAM record (%s)" % rec.name)
	check(int(high_ents[0].klass) == 9 and int(high_ents[0].type_code) == -1, "an infrared SAM with no RWR symbol")
	await fly(tv, 1.0)

	# --- skill: the jet comes into sight 1 km past the teams, going away at 150 m/s -----------------------------------
	_put(Vector3(j.x, j.y + 1000, 0), AGL, 150.0)
	var t0: float = rt.now
	check(await _until(func(): return not high.flying.is_empty(), 15.0), "the High crew launches")
	if high.flying.is_empty():
		return
	var after: float = rt.now - t0
	print("High crew's launch %.1f s after the jet came into sight" % after)
	check(after >= 6.5 - 0.6, "after its reaction and drill (6.5 s)")
	var m = high.flying[0][0]
	check(m.weapon == rec and String(m.target_key) == me, "its missile flies at the jet")
	check(high.locked.is_empty() and not w.rwr.any_launch(), "no lock and no launch on the RWR (passive)")
	# The range's own emitters stay on the RWR; nothing shows at the team.
	var hp: Vector3 = rt._world_of(high_ents[0])
	var at_team := func(x): return Vector2(x.pos.x, x.pos.y).distance_to(Vector2(hp.x, hp.y)) < 500.0
	check(not w.rwr.display().any(at_team), "nothing on the RWR at the team (%s)" % [w.rwr.display()])
	var maw := func(): return tv.cockpit.ews.get("maw", []).any(func(x): return String(x.class) == "SAM")
	check(await _until(maw, 1.0), "the MAW warns of a SAM (%s)" % [tv.cockpit.ews.get("maw", [])])
	check(not rec.has("real_cone_deg"), "the team's seeker cone is its generation's, not the AIM-9M's")
	var near := await _pass(m, 20.0)
	print("Igla: closest pass %.1f m" % near)
	check(near < 15.0, "no flares: the Igla hits (%.1f m)" % near)
	await fly(tv, 6.0)
	check(low.flying.is_empty() and low.site.state(rt.now).rounds[0] == 2, "the Low crew was too slow: no launch")

	# --- flares against the Strela-2M --------------------------------------------------------------------------------
	_put(j + Vector3(0, -20000, 0), 3000.0, 200.0)
	var st_ents: Array = ad.spawn("strela", Vector3(j.x + 5000, j.y, 0))
	var st: Dictionary = ad.site_of(st_ents[0])
	st.site.set_skill(2)
	await fly(tv, 1.0)
	_put(Vector3(j.x + 5000, j.y + 800, 0), AGL, 120.0)
	check(await _until(func(): return not st.flying.is_empty(), 15.0), "the Strela team launches at the tail")
	if st.flying.is_empty():
		return
	m = st.flying[0][0]
	var r_strela := float(m.weapon.motion.get("_decoyReject", -1.0))
	var r_igla := float(rec.motion.get("_decoyReject", -1.0))
	print("decoy rejection: Strela-2M %.2f, Igla %.2f" % [r_strela, r_igla])
	check(r_strela == 0.0 and r_igla > 0.5, "the first-generation seeker rejects no flare, the Igla's more")
	await fly(tv, 1.5)  # its motor burns: closing
	var o: Dictionary = w.own()
	var jet := {"pos": o.pos, "vel": o.vel, "ab": false, "g": 1.0}
	var p_strela: float = m.decoy_chance(true, true, w.now, jet)
	print("one flare now: Strela-2M %.3f" % p_strela)
	check(p_strela > 0.0, "a flare can take it")
	seed(7)
	var taken := false
	for i in 10:
		o = w.own()
		if not w.release_decoy(550, o.pos, o, me, false, 1.0):
			break
		taken = String(m.target_key).begins_with("decoy:")
		if taken:
			break
		await fly(tv, 0.3)
	check(taken, "a flare decoys the Strela (%s)" % m.target_key)
	near = await _pass(m, 20.0)
	print("Strela: closest pass %.1f m" % near)
	check(near > 30.0, "decoyed, it misses (%.1f m)" % near)
	print("teams: ", ad.sites.map(func(x): return x.site.state(rt.now)))
