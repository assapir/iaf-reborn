# Modern IAF's SAM network (docs/ai.md §15.5; shared/ai/air_defence.gd over the Rust network in
# crates/iaf-ai/src/net.rs) on the Sufa's weapons range, headless: two S-300PMU-2 batteries under an 83M6E2 (the 64N6E2
# search radar, the 54K6E2 command post) ahead of the jet (no mission places one). The RWR lists the 64N6E2's search
# while the batteries' own search radars stay off; the network cues one battery's track radar, which locks the jet
# and launches, the other battery holding fire; with the command post destroyed the batteries search for themselves.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sam_net.gd --log-file <temp>
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


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-samnet", false).get_current_dir()
	tv.addon.result = {"pass": true}
	s.invulnerable = true  # the stand-in missiles hit; the checks go on
	w = tv.weapons
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var j: Vector3 = tv.player_world()
	_put(j, 3000.0, 200.0)
	var a: Array = ad.spawn("s300", j + Vector3(-3000, 30000, 0), 180.0)
	var b: Array = ad.spawn("s300", j + Vector3(3000, 30000, 0), 180.0)
	var sa: Dictionary = ad.site_of(a[0])
	var sb: Dictionary = ad.site_of(b[0])
	var net: Array = ad.spawn_net(j + Vector3(0, 50000, 0), j + Vector3(2000, 48000, 0), [sa, sb])
	check(net.size() == 2 and net.all(func(e): return tv.runtime.entities.has(e.key)), "the 64N6E2 and the 54K6E2")
	var search := func(): return w.rwr.display().any(func(e): return e.search and int(e.type) == 310)
	var own_search := func(): return a[0].get("radiating", false) or b[0].get("radiating", false)
	check(await _until(search, 6.0), "the RWR lists the 64N6E2's search (%s)" % [w.rwr.display()])
	check(net[0].radiating and not net[1].radiating, "the radar radiates, the post does not")
	check(not own_search.call(), "the batteries' own search radars stay off")
	# The search radars' antennas (docs/ai.md §15.4): the 64N6E2's turns while it radiates, the 96L6E's stays still
	# while its battery is networked.
	check(net[0].has("antenna") and a[0].has("antenna"), "the 64N6E2's and the 96L6E's antennas")
	var turned := func(e: Dictionary, s0: float): return absf(wrapf(e.antenna[0].rotation.y - s0, -PI, PI)) > 0.3
	var y_net: float = net[0].antenna[0].rotation.y
	var y_96: float = a[0].antenna[0].rotation.y
	await fly(tv, 1.0)
	check(turned.call(net[0], y_net), "the 64N6E2's antenna turns")
	check(not turned.call(a[0], y_96), "the networked 96L6E's antenna stays still")
	var locked := func(): return not sa.locked.is_empty() or not sb.locked.is_empty()
	var both := false
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < 120.0 and sa.flying.is_empty() and sb.flying.is_empty():
		both = both or (not sa.locked.is_empty() and not sb.locked.is_empty())
		await fly(tv, 0.25)
	check(not sa.flying.is_empty() or not sb.flying.is_empty(), "a cued battery launches")
	check(locked.call() and not both, "one battery locks the jet, not both")
	check(sa.flying.is_empty() or sb.flying.is_empty(), "one battery fires, the other holds")
	# The locking battery's 30N6E2 (our truck model) lays its antenna on the jet (docs/ai.md §15.4).
	var ls: Dictionary = sa if not sa.locked.is_empty() else sb
	var tr: Dictionary = ls.ents[ls.track]
	var key: String = ls.locked.keys()[0] if not ls.locked.is_empty() else ""
	var off := absf(wrapf(tr.antenna[0].rotation.y - ad._yaw(tr, key), -PI, PI)) if tr.has("antenna") else PI
	check(key != "" and off < deg_to_rad(15.0), "the 30N6E2's antenna on the jet (%.1f° off)" % rad_to_deg(off))
	check(w.rwr.any_launch(), "the RWR's launch flag")
	check(not own_search.call(), "no battery's own search while networked")

	net[1].state = 4  # the command post destroyed
	check(await _until(own_search, 2.0), "without the post the batteries search for themselves")
	var y0 := [a[0].antenna[0].rotation.y, b[0].antenna[0].rotation.y]
	net[0].state = 4  # the search radar destroyed
	await fly(tv, 1.0)
	y_net = net[0].antenna[0].rotation.y
	var spun := [turned.call(a[0], y0[0]), turned.call(b[0], y0[1])]
	check(spun[0] or spun[1], "a searching 96L6E's antenna turns (%s)" % [spun])
	await fly(tv, 1.0)
	check(not turned.call(net[0], y_net), "the destroyed 64N6E2's antenna stops")
	print("net: ", ad.sites.map(func(x): return x.site.state(tv.runtime.now)))
