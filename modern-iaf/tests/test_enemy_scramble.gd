# Modern IAF's enemy scramble from a base (docs/ai.md §18.3, modern-iaf/docs/ai-plan.md K3), headless on the Sufa's
# weapons range: two MiG-29As parked in Ramon's shelters (the dev hook ai_flights.gd `enemy_base`; the sim has no
# enemy base, so Ramon stands in; no mission places one) under an S-300 network's 64N6E2 and 54K6E2. A scripted jet
# on the player's side flies south at the base: the network's vector scrambles the pair, both start, taxi and take
# off, and the lead commits. The jet shot down, the pair goes home, lands and parks in its shelters. The player's jet
# is moved to Nevatim and parked there.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_enemy_scramble.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 8.0
const ALT := 7000.0

var tv: Node


## Flies until `f` holds, at most `s` s; whether it held.
func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await process_frame
	return f.call()


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-scramble", false).get_current_dir()
	tv.addon.result = {"pass": true}
	var rt: Node = tv.runtime
	var ibx: Dictionary = s.load_ibx(s.own_dir().path_join("iaf.ibx"))
	var b: Dictionary = ibx["Ramon"]
	var base := Vector3(float(b.LineupLocX), float(b.LineupLocY), float(b.LineupLocZ))
	# The player's jet parked at Nevatim's lineup, engine off, 58 km from Ramon: below the network's radar horizon, and
	# near enough that the terrain under Ramon stays loaded.
	var nb: Dictionary = ibx["Nevatim"]
	var sp: Vector3 = tv.world_to_scene(Vector3(float(nb.LineupLocX), float(nb.LineupLocY), float(nb.LineupLocZ)))
	var flags := airborne_flags()
	flags.airborne = false
	flags.engine_on = false
	tv.rig.position = sp
	tv.flight.start(s.own_dir(), tv.player.fm_section, sp, Vector3(0, 0, float(nb.RunwayNumber)), Vector3.ZERO, flags)
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var nents: Array = ad.spawn_net(base + Vector3(8000, 0, 0), base + Vector3(9000, -1000, 0), [])
	var net: Dictionary = ad.net_of(nents[0])
	var station := Vector3(base.x, base.y, ALT)
	var f = tv.ai.enemy_base("mig29a", "Ramon", 2, station, net)
	check(f != null and tv.ai.enemy_flights.size() == 1, "the pair parked at Ramon")
	if f == null:
		return
	var pair: Array = tv.ai.enemy_flights[0].members.map(func(m): return m[1])
	var st := func(i: int) -> Dictionary: return pair[i].pilot.flight.state()
	check(pair.size() == 2, "two jets")
	check(
		pair.all(func(e): return e.pilot.flight.state().on_ground and not e.pilot.flight.state().engine_on),
		"parked, engines off"
	)
	# The scripted jet: 110 km north of the base, flying south, then east-west legs 70 km north of it (inside the commit
	# range) while the pair taxies (about 4 min).
	var mine := int(rt.player_entity().get("side", 2))
	var at := Vector3(base.x, base.y + 110000, ALT)
	var legs := []
	for k in 8:
		legs.append([base.x + (30000 if k % 2 == 0 else -30000), base.y + 70000, ALT, 0])
	var jet: Dictionary = tv.ai.spawn("mig29a", at, 180.0, legs, mine)
	check(not jet.is_empty(), "the scripted jet in the air")
	if jet.is_empty():
		return
	jet.pilot.set_mode(7)
	await fly(tv, 10.0)
	check(not st.call(0).engine_on, "no scramble while the jet is outside the commit range")
	Engine.time_scale = TIME_SCALE
	check(await _until(func(): return st.call(0).engine_on, 200.0), "the network's vector scrambles the lead")
	check(await _until(func(): return st.call(1).engine_on, 120.0), "the wingman starts after it")
	var up := func(): return pair.all(func(e): return e.pilot.flight.ap_airborne())
	check(await _until(up, 400.0), "both take off")
	var committed := func(): return f.state(1).get("committed", false)
	check(await _until(committed, 60.0), "the lead commits (%s)" % f.state(1).phase)
	# The jet shot down: the sortie is over.
	rt.set_damage_level(jet, 5)
	check(await _until(func(): return String(f.state(1).phase) == "home", 90.0), "the lead goes home")
	var parked := func():
		return pair.all(func(e): return e.pilot.flight.ap_landed() and not e.pilot.flight.state().engine_on)
	check(await _until(parked, 1500.0), "both land and park (%s, %s)" % [f.state(1).stage, f.state(2).stage])
	for e in pair:
		var off: float = Vector2(e.world.x - base.x, e.world.y - base.y).length()
		check(off < 5000.0 and int(e.state) < 3, "%s at Ramon (%.0f m from the lineup)" % [e.name, off])
	Engine.time_scale = 1.0
