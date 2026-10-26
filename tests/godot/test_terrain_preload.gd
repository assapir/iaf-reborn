# The mission screens' preload (docs/rendering.md §1.5, terrain/terrain_preload.gd): on the TSD the ground around the
# selected flight's start loads and the mission's models parse ahead; another flight re-aims the ground at its start;
# leaving the mission screens drops both; Fly hands the loaded nodes to the flight's terrain (the same textures), and
# once the flight runs no parse is left over.
extends "res://../tests/godot/base.gd"


func until(cond: Callable, secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func open_tsd(fe: Node, id: int) -> void:
	settings().mission_id = id
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	await frames(3)


func run() -> void:
	var tp: GDScript = load("res://terrain/terrain_preload.gd")
	var mr: GDScript = load("res://mission/mission_runtime.gd")
	var gltf: GDScript = load("res://util/gltf.gd")
	change_scene_to_file("res://menu/front_end.tscn")
	await frames(3)
	var fe: Node = current_scene
	await open_tsd(fe, 113)  # two flights 85 km apart
	var first: int = fe.tsd.default_flight()
	var s1 = mr.player_start(113, first)
	check(tp._alive() and tp._target == s1, "the TSD: the ground around the selected flight's start loads")
	check(await until(func(): return tp._prefetched.x == 113, 30.0), "the flight scene loaded, the prefetch ran")
	var files: Array = mr.mission_files(113)
	var models: Array = tp.mission_models(files, mr.load_bdb(files[0].data))
	check(
		not models.is_empty() and models.all(func(p): return gltf._ahead_tasks.has(p)),
		"the mission's %d models parse ahead" % models.size()
	)

	fe.screen = "jet"
	fe._enter_screen()
	await frames(2)
	check(not tp._alive() and gltf._ahead_tasks.is_empty(), "leaving the mission screens drops the ground and models")

	await open_tsd(fe, 113)
	var other := 2 if first != 2 else 1
	fe.tsd.select_flight(other)
	await frames(2)
	var s2 = mr.player_start(113, other)
	check(s2 != s1 and tp._target == s2, "another flight on the TSD re-aims the ground at its start")
	var pt: Node = tp._terrain
	check(
		await until(func(): return pt.ground_ready() and not pt.missing_after_frame(), 120.0),
		"the preload loads the start's ground (%d nodes)" % pt._res.size()
	)
	var loaded := {}
	for k in pt._res:
		loaded[k] = pt._res[k].tex

	fe._fly()
	var tv: Node = null
	check(
		await until(func(): return current_scene != null and current_scene.name == "TerrainView", 30.0),
		"Fly starts the flight"
	)
	tv = current_scene
	var res: Dictionary = tv.terrain._res
	check(
		loaded.keys().all(func(k): return res.has(k) and res[k].tex == loaded[k]),
		"the flight's terrain holds the preloaded nodes (the same textures)"
	)
	check(not tp._alive(), "the preload's terrain node is gone")
	check(await until(func(): return tv.get("flight") != null and not tv.waiting_for_ground, 60.0), "the flight runs")
	var w: Vector3 = tv.player_world()
	check(Vector2(w.x, w.y).distance_to(Vector2(s2.x, s2.y)) < 2000.0, "the jet starts at the chosen flight's start")
	check(gltf._ahead_tasks.is_empty() and gltf._ahead.is_empty(), "no model parsed ahead is left over")

	# Models Detailed: the player's detailed F-16D parses ahead too, with its LODs and meshes made on the worker, and
	# open() takes that parse.
	settings().models = "detailed"
	var hd: String = gltf.DETAILED["f16_h.gltf"]
	tp._prefetched = Vector3i(-1, -1, -1)
	tp.prefetch_flight(231, 0)
	check(gltf._ahead_tasks.has(hd), "Models Detailed: the player's F-16D parses ahead")
	check(await until(func(): return gltf.parsed_ahead(hd), 60.0), "the F-16D's parse ends")
	var st: GLTFState = gltf._ahead.get(hd, [null, null])[1]
	check(
		st != null and st.get_meshes().any(func(m): return m.mesh.get_surface_lod_count(0) > 0),
		"the parse made the F-16D's LODs"
	)
	gltf._objects.erase("%d:%s" % [gltf.object_level, hd])
	var m = gltf.model(hd)
	check(m != null and m[1] == st and not gltf._ahead.has(hd), "the flight's open takes the parse ahead")
	gltf.drop_ahead()
	settings().models = "original"
