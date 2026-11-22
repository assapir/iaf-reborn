# Modern IAF's AI jets land wherever the player is (docs/ai.md §18.4), headless on the Sufa's weapons range: a MiG-29A
# 20 km out on Nevatim's approach goes home and lands there, with the player's jet parked in a Nevatim shelter (the
# terrain under the landing loaded) and then in a Tel Nof shelter, 70 km off, with the terrain's view range cut to 10 km
# (the 200 km one keeps Nevatim's heights loaded from Tel Nof): no terrain loaded at Nevatim until the AI jet's own
# heights come. Each lands without a crash, its wheels on the runway, and stops.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_ai_far_landing.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 8.0

var tv: Node


func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await process_frame
	return f.call()


## The player's jet parked in `base`'s first shelter, engine off.
func _park_player(ibx: Dictionary, base: String) -> void:
	var b: Dictionary = ibx[base]
	var sp: Vector3 = tv.world_to_scene(Vector3(float(b.HangarPtX0), float(b.HangarPtY0), float(b.LineupLocZ)))
	var flags := airborne_flags()
	flags.airborne = false
	flags.engine_on = false
	tv.rig.position = sp
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, sp, Vector3(0, 0, float(b.HangarPtHdg0)), Vector3.ZERO, flags
	)


## A MiG-29A 15 km out on Nevatim's approach at 1,500 m, sent home: it lands at Nevatim.
func _land_at_nevatim(ibx: Dictionary, what: String) -> void:
	var b: Dictionary = ibx["Nevatim"]
	var l := Vector3(float(b.LineupLocX), float(b.LineupLocY), float(b.LineupLocZ))
	var h := deg_to_rad(float(b.RunwayNumber))
	var fwd := Vector3(sin(h), cos(h), 0)
	var wp: Vector3 = l - fwd * 15000.0 + Vector3(0, 0, 1500)
	var mine := int(tv.runtime.player_entity().get("side", 2))
	var jet: Dictionary = tv.ai.spawn("mig29a", wp - fwd * 5000.0, float(b.RunwayNumber), [[wp.x, wp.y, wp.z, 7]], mine)
	check(not jet.is_empty(), "%s: the jet in the air" % what)
	if jet.is_empty():
		return
	jet.pilot.set_mode(8)
	var low := [INF]
	var done := func():
		var st: Dictionary = jet.pilot.flight.state()
		var g = tv.mission_ground(jet.world)
		if g != null:
			low[0] = minf(low[0], jet.world.z - float(g))
		return int(jet.state) >= 3 or (jet.pilot.flight.ap_landed() and float(st.speed) < 1.0)
	await _until(done, 900.0)
	var st: Dictionary = jet.pilot.flight.state()
	var off: float = Vector2(jet.world.x - l.x, jet.world.y - l.y).length()
	var g = tv.mission_ground(jet.world)
	print(
		(
			"%s: state %d, %s, landed %s, %.0f m from the lineup, %.1f m over the ground %s, lowest %.1f m"
			% [
				what,
				int(jet.state),
				jet.pilot.flight.ap_stage(),
				jet.pilot.flight.ap_landed(),
				off,
				jet.world.z - float(g if g != null else 0.0),
				g,
				low[0]
			]
		)
	)
	check(int(jet.state) < 3 and not st.crashed, "%s: no crash" % what)
	check(jet.pilot.flight.ap_landed() and off < 5000.0, "%s: landed at Nevatim" % what)
	check(g != null and absf(jet.world.z - float(g)) < 5.0, "%s: on the ground" % what)
	tv.runtime.set_damage_level(jet, 5)


func run() -> void:
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-far-landing", false).get_current_dir()
	tv.addon.result = {"pass": true}
	var ibx: Dictionary = s.load_ibx(s.own_dir().path_join("iaf.ibx"))
	# The mission's own AI jets fly 44-69 km from Nevatim, inside its 65 km height node: gone, they keep no heights there.
	for p in tv.ai.pilots:
		tv.runtime.set_damage_level(p.ent, 5)
	_park_player(ibx, "Nevatim")
	await fly(tv, 5.0)
	Engine.time_scale = TIME_SCALE
	await _land_at_nevatim(ibx, "the player at Nevatim")
	Engine.time_scale = 1.0
	_park_player(ibx, "TelNof")
	var far: float = tv.terrain.view_range
	tv.terrain.view_range = 10000.0
	var nb: Dictionary = ibx["Nevatim"]
	var nev: Vector3 = tv.world_to_scene(Vector3(float(nb.LineupLocX), float(nb.LineupLocY), 0))
	var gone := func(): return tv.terrain.height_at(nev) == null
	check(await _until(gone, 120.0), "the player at Tel Nof: no terrain loaded at Nevatim")
	Engine.time_scale = TIME_SCALE
	await _land_at_nevatim(ibx, "the player at Tel Nof")
	Engine.time_scale = 1.0
	tv.terrain.view_range = far
