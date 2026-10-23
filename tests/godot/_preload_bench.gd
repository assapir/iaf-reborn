# Dev helper (not run by tools/test.sh): the mission screens' preload and the flight's start (docs/rendering.md §1.5).
# Opens the front end on the TSD of mission PB_MISSION (default 311), stays there PB_WAIT seconds (default 6; 0 = Fly
# at once) and prints the menus' frame times meanwhile (worst, 99th percentile, frames over 16.7 / 33 ms), then flies
# (front_end._fly) and prints the time from Fly to the first flying frame, with the terrain's and the models' progress
# on the way (a start over 60 s prints the terrain's queue and quits with 1). PB_JPEG=1: the terrain's JPEG fallback
# (Terrain.precompressed off). PB_PREFS="sky=atmospheric,water=true,…": settings fields set before the TSD (true /
# false as booleans, else strings). PB_FLY seconds (default 10) of flying frames are timed after the
# start (worst, frames over 50 ms). The time since launch is printed at the main menu, the TSD and the first flying
# frame (docs/rendering.md §1.6, the shader compiles). PB_EVENTS=1 then times what first shows mid-flight (_events);
# PB_SHOTS=<dir> saves the view after the start and after each event. Vsync off; the menus run at Max FPS.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 PB_MISSION=311 PB_WAIT=6 -- --log-file /tmp/p.log --path game \
#     --resolution 2560x1440 -s ../tests/godot/_preload_bench.gd
extends "res://../tests/godot/base.gd"

## Godot's pipeline compile counters (canvas, mesh, surface, draw, specialization) at the last frame, and the time.
var _pipes: Array[int] = [0, 0, 0, 0, 0]
var _pipe_us := 0


## PB_EVENTS=1: what first shows mid-flight, each followed by 2 s of frames: an explosion 300 m ahead (fireball,
## flash, smoke, column, debris), the night-vision goggles, the external view and back.
func _events(tv: Node) -> void:
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var ahead := cam.global_position - cam.global_transform.basis.z * 300.0
	var steps := {
		"fireball": func(): tv.effects.explosion(ahead, 0x10 | 0x4000, 1.0, 5.0, ahead.y),
		"smoke": func(): tv.effects.explosion(ahead, 0x100 | 0x800, 1.0, 5.0, ahead.y),
		"debris": func(): tv.effects.explosion(ahead, 0x2 | 0x8, 1.0, 5.0, ahead.y),
		"goggles": func(): tv._toggle_goggles(),
		"goggles off": func(): tv._toggle_goggles(),
		"external": func(): tv.in_cockpit = false,
		"cockpit": func(): tv.in_cockpit = true,
	}
	for k in steps:
		steps[k].call()
		var e0 := Time.get_ticks_usec()
		var w := 0.0
		while Time.get_ticks_usec() - e0 < 2e6:
			await process_frame
			w = maxf(w, _pipe_frame(k))
		print("PB event %s: worst %.0f ms" % [k, w])
		_shot(k)


## PB_SHOTS=<dir>: the view now as <dir>/<name>.png.
func _shot(name: String) -> void:
	if OS.get_environment("PB_SHOTS") != "":
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("PB_SHOTS").path_join(name + ".png"))


## One frame of the start or the flight: a frame over 100 ms, or one that compiled pipelines while drawing (the
## compiles that stall), prints its length and its pipeline compiles.
func _pipe_frame(phase: String) -> float:
	var now := Time.get_ticks_usec()
	var dt := (now - _pipe_us) / 1000.0
	_pipe_us = now
	var c: Array[int] = []
	for m in [
		Performance.PIPELINE_COMPILATIONS_CANVAS,
		Performance.PIPELINE_COMPILATIONS_MESH,
		Performance.PIPELINE_COMPILATIONS_SURFACE,
		Performance.PIPELINE_COMPILATIONS_DRAW,
		Performance.PIPELINE_COMPILATIONS_SPECIALIZATION
	]:
		c.append(int(Performance.get_monitor(m)))
	var d: Array[int] = []
	for i in 5:
		d.append(c[i] - _pipes[i])
	_pipes = c
	if dt > 100.0 or d[3] > 0:
		print(
			"PB %s frame %.0f ms: pipelines canvas %d mesh %d surface %d draw %d specialization %d" % ([phase, dt] + d)
		)
	return dt


func run() -> void:
	settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var id := int(OS.get_environment("PB_MISSION")) if OS.get_environment("PB_MISSION") != "" else 311
	var wait := float(OS.get_environment("PB_WAIT")) if OS.get_environment("PB_WAIT") != "" else 6.0
	if OS.get_environment("PB_JPEG") == "1":
		load("res://terrain/terrain.gd").precompressed = false  # the JPEGs, compressed at run time
	for kv in OS.get_environment("PB_PREFS").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], p[1] == "true" if p[1] in ["true", "false"] else p[1])
	change_scene_to_file("res://menu/front_end.tscn")
	await frames(1)
	print("PB main menu shown %d ms after launch" % Time.get_ticks_msec())
	await frames(2)
	await create_timer(2.0).timeout  # the front end's own start settles
	var fe: Node = current_scene
	settings().mission_id = id
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	await process_frame
	print("PB TSD shown %d ms after launch" % Time.get_ticks_msec())
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
	_pipe_frame("menu")
	fe._fly()
	var tv: Node = null
	var state := ""
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		_pipe_frame("start")
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
	print("PB flying %d ms after launch; pipelines so far %s" % [Time.get_ticks_msec(), _pipes])
	var fly := float(OS.get_environment("PB_FLY")) if OS.get_environment("PB_FLY") != "" else 10.0
	var f0 := Time.get_ticks_usec()
	var prev := f0
	var worst := 0.0
	var long: Array[String] = []
	while (prev - f0) / 1e6 < fly:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := _pipe_frame("flying")
		worst = maxf(worst, dt)
		if dt > 50.0:
			long.append("%.0f ms at %.2f s" % [dt, (now - f0) / 1e6])
		prev = now
	print("PB flying %.0f s: worst %.0f ms, over 50 ms: %s" % [fly, worst, ", ".join(long)])
	_shot("start")
	if OS.get_environment("PB_EVENTS") == "1":
		await _events(tv)
	print("RESULT PASS")
	quit()
