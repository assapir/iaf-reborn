# Dev helper (not a test): the frame rate while flying over the terrain (the streaming quadtree working), not just at
# rest. Mission 311 from Ramat David, the rig moved straight ahead at `speed` for `secs` at each altitude, the flight
# model stopped. Per leg: frames per second, frame time average / 95th percentile / worst, the main-thread process
# time, the GPU time, draw calls, primitives and the terrain nodes drawn.
#   IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 -s ../tests/godot/_flight_bench.gd
# BENCH_LEGS=alt:speed:secs,... (default 150:250:20,1500:250:20,6000:300:20). BENCH_BEST=1: the best graphics (every
# Graphics slider / switch up, MSAA 4× + FXAA, terrain close up, atmospheric sky, the modern imagery layers where
# converted: mapi2015 in Israel, sentinel2 outside). BENCH_OFF=a,b: switch parts off to
# see their cost: terrain (streaming), terrain_draw (the nodes hidden), cockpit, runtime, ai, weapons, effects, trails,
# overlay, sounds, scene (the whole flight scene's _process), mfd, hud. BENCH_SPIKES=1 prints every frame over 12 ms.
extends "res://../tests/godot/base.gd"


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var legs := []
	for l in OS.get_environment("BENCH_LEGS").split(",", false):
		var p := l.split(":")
		legs.append([float(p[0]), float(p[1]), float(p[2])])
	if legs.is_empty():
		legs = [[150.0, 250.0, 20.0], [1500.0, 250.0, 20.0], [6000.0, 300.0, 20.0]]
	if OS.get_environment("BENCH_BEST") == "1":
		var best := {"terrain_detail": 1.0, "object_detail": 1.0, "visual_effects": 1.0, "smoke_trails": true, "textured_sky": true,
			"shadows": true, "external_stores": true, "antialiasing": "msaa4_fxaa", "terrain_closeup": true, "sky": "atmospheric",
			"imagery_israel": "mapi2015", "imagery_outside": "sentinel2"}
		for k in best:
			Settings().set(k, best[k])
	# BENCH_SET=key=value,...: overrides after that (e.g. antialiasing=msaa4 / terrain_closeup=false / shadows=false).
	for kv in OS.get_environment("BENCH_SET").split(",", false):
		var p := kv.split("=")
		var cur = Settings().get(p[0])
		Settings().set(p[0], (p[1] == "true") if cur is bool else (float(p[1]) if cur is float else p[1]))
	var tv = await start_mission(311)
	tv.apply_render_options()
	print("layers: ", tv.terrain.layers)
	tv.frozen = true
	tv.fm_stopped = true
	await frames(30)
	for part in OS.get_environment("BENCH_OFF").split(",", false):
		match part:
			"terrain":
				tv.terrain.set_process(false)
			"terrain_draw":
				tv.terrain.visible = false
			"cockpit":
				tv.cockpit.visible = false
				tv.cockpit.process_mode = Node.PROCESS_MODE_DISABLED
			"scene":
				tv.set_process(false)
			"mfd":
				for m in tv.cockpit.mfds:
					m.process_mode = Node.PROCESS_MODE_DISABLED
					m.visible = false
			"hud":
				tv.cockpit.hud.process_mode = Node.PROCESS_MODE_DISABLED
				tv.cockpit.hud.visible = false
				if tv.cockpit.hud.outer != null:
					tv.cockpit.hud.outer.visible = false
			_:
				var n = tv.get(part)
				if n is Node:
					n.process_mode = Node.PROCESS_MODE_DISABLED
					if n is CanvasItem or n is Node3D:
						n.visible = false
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for leg in legs:
		var alt: float = leg[0]
		var speed: float = leg[1]
		var secs: float = leg[2]
		var g = tv.terrain.height_at(tv.rig.position)
		tv.rig.position.y = (g if g != null else 0.0) + alt
		tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(-4.0), deg_to_rad(-30.0), 0.0), EULER_ORDER_YXZ)
		tv._apply_view()
		# Let the ground stream in first, then fly.
		var t0 := Time.get_ticks_msec()
		while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 20000:
			await process_frame
		await frames(30)
		var times: Array[float] = []
		var proc := 0.0
		var gpu := 0.0
		var calls := 0.0
		var prims := 0.0
		var nodes := 0.0
		var fwd: Vector3 = -tv.rig.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec() - start < int(secs * 1e6):
			await process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1e6
			last = now
			times.append(dt * 1000.0)
			if dt > 0.012 and OS.get_environment("BENCH_SPIKES") == "1":
				print("  spike %.1f ms at %.2f s" % [dt * 1000.0, (now - start) / 1e6])
			tv.rig.position += fwd * speed * dt
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			nodes += tv.terrain._drawn.size()
		var n := float(times.size())
		var sorted := times.duplicate()
		sorted.sort()
		var avg := 0.0
		for t in times:
			avg += t
		avg /= n
		print("FLIGHT %5.0f m %3.0f m/s: %5.1f fps  frame %5.2f ms (p95 %5.2f, max %6.2f)  process %5.2f ms  gpu %5.2f ms  calls %5.0f  prims %7.0fk  nodes %4.0f"
			% [alt, speed, 1000.0 / avg, avg, sorted[int(n * 0.95)], sorted[-1], proc / n, gpu / n, calls / n, prims / n / 1000.0, nodes / n])
	print("RESULT PASS")
