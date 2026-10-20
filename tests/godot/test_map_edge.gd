# The map edge (FUN_005bb9f0, docs/flight-model.md §15.5a): flying east at 3000 m, the inner frame (terrain flag
# 0x100 / 0x200) plays EndWorld.wav once; the outer band (0x40 / 0x80) starts the "Tornado", which throws the jet
# back into the map and ends 8 s later.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tv = await start_mission(311)
	var t = tv.terrain
	# Engine metres → scene (x east, z south of the terrain origin).
	var at := func(east: float, north: float, alt: float) -> Vector3:
		return Vector3(east - t.world_origin.x, alt, -(north - t.world_origin.y))
	var start: Vector3 = at.call(612000.0, 600000.0, 3000.0)
	check(t.surface_at(start) & 0x3c0 == 0x100, "start in the inner frame (mask %x)" % t.surface_at(start))
	check(t.surface_at(at.call(616000.0, 600000.0, 0.0)) & 0xc0 != 0, "the outer band 4 km east")
	tv.gear_down = false
	tv.throttle = 0.74
	tv.flight.start(
		settings().assets_dir().path_join("install"),
		tv.player.fm_section,
		start,
		Vector3(0.0, 0.0, 90.0),
		Vector3(250.0, 0.0, 0.0),
		{"airborne": true, "engine_on": true, "real_data": false}
	)
	await fly(tv, 1.0)
	check(int(tv.flight.state().end_worlds) == 1, "EndWorld counted once in the frame")
	check("endworld.wav" in tv.sounds.played, "EndWorld.wav played")
	var t0: float = tv._sim_time
	while not tv.flight.state().tornado and tv._sim_time - t0 < 30.0:
		await process_frame
	var st: Dictionary = tv.flight.state()
	check(st.tornado, "the Tornado at the outer band (%.0f m east)" % (t.world_origin.x + st.position.x))
	var t_in: float = tv._sim_time
	await fly(tv, 2.5)
	st = tv.flight.state()
	check(st.velocity.x < 0.0 and st.tornado, "thrown back west (vx %.0f m/s)" % st.velocity.x)
	while tv.flight.state().tornado and tv._sim_time - t_in < 20.0:
		await process_frame
	check(not tv.flight.state().tornado, "the Tornado ends (%.1f s)" % (tv._sim_time - t_in))
