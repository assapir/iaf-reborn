# Dev helper (not run by tools/test.sh): the mission screens' preload and the flight's start (docs/rendering.md §1.5).
# Opens the front end on the TSD of mission PB_MISSION (default 311), stays there PB_WAIT seconds (default 6; 0 = Fly
# at once) and prints the menus' frame times meanwhile (worst, 99th percentile, frames over 16.7 / 33 ms), then flies
# (front_end._fly) and prints the time from Fly to the first flying frame, with the terrain's and the models' progress
# on the way (a start over 60 s prints the terrain's queue and quits with 1). PB_JPEG=1: the terrain's JPEG fallback
# (Terrain.precompressed off). Vsync off; the menus run at Max FPS.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 PB_MISSION=311 PB_WAIT=6 -- --log-file /tmp/p.log --path game \
#     --resolution 2560x1440 -s ../tests/godot/_preload_bench.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var id := int(OS.get_environment("PB_MISSION")) if OS.get_environment("PB_MISSION") != "" else 311
	var wait := float(OS.get_environment("PB_WAIT")) if OS.get_environment("PB_WAIT") != "" else 6.0
	if OS.get_environment("PB_JPEG") == "1":
		load("res://terrain/terrain.gd").precompressed = false  # the JPEGs, compressed at run time
	change_scene_to_file("res://menu/front_end.tscn")
	await frames(3)
	await create_timer(2.0).timeout  # the front end's own start settles
	var fe: Node = current_scene
	settings().mission_id = id
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	var dts: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while (last - start) / 1e6 < wait:
		await process_frame
		var now := Time.get_ticks_usec()
		dts.append((now - last) / 1000.0)
		last = now
	if not dts.is_empty():
		dts.remove_at(0)  # the TSD's own first frame
	if not dts.is_empty():
		var s := dts.duplicate()
		s.sort()
		print(
			(
				"PB menus %d frames  worst %.1f ms  p99 %.1f ms  >16.7 ms %d  >33 ms %d"
				% [
					s.size(),
					s[-1],
					s[int(0.99 * (s.size() - 1))],
					s.filter(func(d): return d > 16.7).size(),
					s.filter(func(d): return d > 33.3).size()
				]
			)
		)
	var tp: GDScript = load("res://terrain/terrain_preload.gd")
	var pt: Node = tp._terrain
	if pt != null:
		print(
			(
				"PB preload at Fly: %d resources, ground ready %s, missing %s"
				% [pt._res.size(), pt.ground_ready(), pt.missing_after_frame()]
			)
		)
	var t0 := Time.get_ticks_usec()
	fe._fly()
	var tv: Node = null
	var state := ""
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
		if tv != null and tv.get("terrain") != null and tv.terrain.is_inside_tree():
			var q = tv.get("_parse_queue")
			var st := (
				"ground %s models %s res %d"
				% [tv.terrain.ground_ready(), "-" if q == null else str(q.size()), tv.terrain._res.size()]
			)
			if (Time.get_ticks_usec() - t0) / 1e6 > 60.0:
				var t: Node = tv.terrain
				var miss: Array = t._near.keys().filter(func(k): return not t._near[k])
				print(
					(
						"PB timeout: blocked_near %d near-missing %s busy %s results %s queue %s jobs %d wanted %d"
						% [
							t._blocked_near,
							miss.slice(0, 8),
							t._busy.keys(),
							t._results.keys(),
							t._queue,
							t._jobs.size(),
							t._wanted.size()
						]
					)
				)
				print("PB timeout: missing in res: %s" % [miss.filter(func(k): return t._res.has(k)).size()])
				quit(1)
				return
			if st != state:
				state = st
				print("PB %.2f s %s" % [(Time.get_ticks_usec() - t0) / 1e6, st])
	print("PB mission %d wait %.0f s: Fly to flying %.2f s" % [id, wait, (Time.get_ticks_usec() - t0) / 1e6])
	await frames(30)
	print("RESULT PASS")
	quit()
