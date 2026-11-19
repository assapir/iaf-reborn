# Modern IAF's air-defence sites (docs/ai.md §15; shared/ai/air_defence.gd over the Rust site in
# crates/iaf-ai/src/site.rs) on the Sufa's weapons range, headless: an S-300PMU-2, a Tor-M1 and a ZSU-23-4 spawned
# near the jet (no mission places one). The RWR lists the S-300's search radar while it radiates and not while it is
# silent; its track locks the jet; it launches the existing missile (the RWR's launch flag); then it ceases and
# marches. The ZSU fires its rounds and moves to its alternate position after the engagement.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_enemy_sites.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

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


## The RWR lists a radar of type `type` searching the jet.
func _search(type: int) -> bool:
	return w.rwr.display().any(func(e): return e.search and int(e.type) == type)


## The RWR lists a lock of type `type`.
func _locked(type: int) -> bool:
	return w.rwr.display().any(func(e): return not e.search and int(e.type) == type and e.active)


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-sites", false).get_current_dir()
	tv.addon.result = {"pass": true}
	s.invulnerable = true  # the stand-in missiles and rounds hit; the checks go on
	w = tv.weapons
	check(s.rwr_search, "the threat display lists searching radars")
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	_put(j, 3000.0, 200.0)
	var s300: Array = ad.spawn("s300", j + Vector3(0, 25000, 0), 180.0, [j + Vector3(3000, 25000, 0)])
	var tor: Array = ad.spawn("tor", j + Vector3(40000, 0, 0))
	var zsu: Array = ad.spawn("zsu", j + Vector3(0, -30000, 0), 0.0, [j + Vector3(2000, -30000, 0)])
	check(
		s300.size() == 6 and tor.size() == 1 and zsu.size() == 1,
		"the parts (%d, %d, %d)" % [s300.size(), tor.size(), zsu.size()]
	)
	var placed := func(e): return e.node is Node3D and e.node.is_inside_tree() and tv.runtime.entities.has(e.key)
	check((s300 + tor + zsu).all(placed), "each part a mission entity with its stand-in shape")
	var site: Dictionary = ad.site_of(s300[0])
	check(site.units.filter(func(u): return u != null).size() == 4, "four launchers armed through combat.gd")

	site.site.set_emcon("silent")
	await fly(tv, 4.5)
	check(not _search(310), "silent: no S-300 search radar on the RWR")
	site.site.set_emcon("radiate")
	check(await _until(_search.bind(310), 6.0), "radiating: the RWR lists it (%s)" % [w.rwr.display()])
	check(await _until(_locked.bind(310), 12.0), "the 30N6E2's track locks the jet (%s)" % [w.rwr.display()])
	check(await _until(func(): return not site.flying.is_empty(), 150.0), "a launch")
	check(not site.flying.is_empty() and site.flying[0][0] in w.missiles, "the existing missile flies at the jet")
	check(w.rwr.any_launch(), "the RWR's launch flag")
	site.site.set_emcon("silent")  # the engagement ends
	var phase := func(st: Dictionary): return String(st.site.state(tv.runtime.now).phase)
	check(await _until(func(): return phase.call(site) == "march", 30.0), "the S-300 ceases and marches")
	await fly(tv, 2.5)
	check(not _search(310), "marching: its radars off")

	var zs: Dictionary = ad.site_of(zsu[0])
	var zp: Vector3 = zsu[0].world
	_put(zp + Vector3(0, -3000, 0), 600.0, 150.0)
	var fired := func(): return int(zs.site.state(tv.runtime.now).rounds[0]) < 2000
	check(await _until(fired, 30.0), "the ZSU fires bursts")
	check(_locked(360), "its radar locks the jet")
	await fly(tv, 0.5)
	check(zs.units[0].rounds.pool.any(func(r): return r.flying), "its rounds fly (the existing round model)")
	_put(j + Vector3(0, 10000, 0), 3000.0, 200.0)  # away: the engagement over
	check(await _until(func(): return zsu[0].world.distance_to(zp) > 20.0, 40.0), "the ZSU relocates")
	print("sites: ", ad.sites.map(func(x): return x.site.state(tv.runtime.now)))
