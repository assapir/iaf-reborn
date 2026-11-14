# Modern IAF's mission page preloads the flight as reborn's TSD does (shared/terrain/terrain_preload.gd, the front end's
# _preload_ground): the ground around the picked mission's start on the sim's 1:1 theatre and the mission's models;
# leaving the page drops them; Fly waits for the flight scene's load (TerrainPreload.fly) and hands the loaded nodes to
# the flight's terrain (the same textures). Prints the time from Fly to the first flying frame.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_terrain_preload.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func until(cond: Callable, secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	var tp: GDScript = load("res://shared/terrain/terrain_preload.gd")
	var mr: GDScript = load("res://shared/mission/mission_runtime.gd")
	load("res://tests/test_front_end.gd").fixture(s)
	s.sim_jet = "f16i"
	change_scene_to_file("res://main.tscn")
	await frames(3)
	var fe: Control = current_scene
	fe.show_page("mission")
	await frames(2)
	var id := int(fe.missions[fe.mission_i].menu_id)
	var start = mr.player_start(id, s.player_flight)
	check(start != null and tp._alive() and tp._target == start, "the mission page: the ground around the start loads")
	check(await until(func(): return tp._prefetched.x == id, 30.0), "the flight scene loaded, the prefetch ran")
	fe.show_page("hangar")
	await frames(2)
	check(not tp._alive() and tp._prefetched.x == -1, "leaving the mission page drops the preload")
	fe.show_page("mission")
	await frames(2)
	var pt: Node = tp._terrain
	check(
		await until(func(): return pt.ground_ready() and not pt.missing_after_frame(), 120.0),
		"the preload loads the start's ground (%d nodes)" % pt._res.size()
	)
	var loaded := {}
	for k in pt._res:
		loaded[k] = pt._res[k].tex
	var t0 := Time.get_ticks_usec()
	fe.fly_mission(fe.missions[fe.mission_i])
	check(
		await until(func(): return current_scene != null and current_scene.name == "TerrainView", 30.0),
		"Fly starts the flight"
	)
	var tv: Node = current_scene
	var res: Dictionary = tv.terrain._res
	check(
		loaded.keys().all(func(k): return res.has(k) and res[k].tex == loaded[k]),
		"the flight's terrain holds the preloaded nodes (the same textures)"
	)
	check(not tp._alive(), "the preload's terrain node is gone")
	check(await until(func(): return tv.get("flight") != null and not tv.waiting_for_ground, 120.0), "the flight runs")
	print("Fly to flying %.2f s" % ((Time.get_ticks_usec() - t0) / 1e6))
	var w: Vector3 = tv.player_world()
	check(Vector2(w.x, w.y).distance_to(Vector2(start.x, start.y)) < 100.0, "the jet starts at the mission's start")
