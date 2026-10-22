# Dev helper (not run by tools/test.sh): terrain streaming (docs/rendering.md §1.5). Does the mission screens'
# preload (as _ground_tex_bench.gd GT_PRELOAD=1), starts the flight and prints the start time (scene change to the
# first flying frame); then a low fast pass (frozen flight model, cockpit, ST_KT knots at ST_ALT m above the ground,
# default 600 kt / 300 m, for 60 s, heading ST_HDG degrees, default 270) with the colour / height nodes waiting each
# second, the worst frame and the average fps; then the time to load one colour node on a worker thread (the
# nodes loaded, each again). ST_DDS=0 loads the JPEGs and compresses them (the path without setup's bc1 step).
# GT_SET="key=value,…" sets Settings keys (str_to_var values). Vsync off.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file /tmp/s.log --path game --resolution 2560x1440 \
#     -s ../tests/godot/_stream_bench.gd -- --mission 311
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tp: GDScript = load("res://terrain/terrain_preload.gd")
	load("res://terrain/terrain.gd").precompressed = OS.get_environment("ST_DDS") != "0"
	settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kv in OS.get_environment("GT_SET").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]))
	tp.preload_scene()
	while ResourceLoader.load_threaded_get_status(tp.SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await process_frame
	var m := OS.get_cmdline_user_args().find("--mission")
	tp.prefetch_flight(int(OS.get_cmdline_user_args()[m + 1]) if m >= 0 else -1)
	await create_timer(3.0).timeout
	var t0 := Time.get_ticks_usec()
	change_scene_to_packed(tp.scene())
	await frames(2)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	print("ST start %.2f s" % ((Time.get_ticks_usec() - t0) / 1e6))
	await create_timer(2.0).timeout
	tv.frozen = true
	tv.fm_stopped = true
	var env := func(k: String, d: float) -> float: return float(OS.get_environment(k)) if OS.has_environment(k) else d
	var alt: float = env.call("ST_ALT", 300.0)
	var speed: float = env.call("ST_KT", 600.0) * 0.514444
	var hdg := deg_to_rad(env.call("ST_HDG", 270.0))
	var fwd := Vector3(sin(hdg), 0.0, -cos(hdg))
	tv.rig.basis = Basis.looking_at(fwd, Vector3.UP)
	var t: Node = tv.terrain
	var worst := 0.0
	var n := 0
	var start := Time.get_ticks_usec()
	var last := start
	var next_print := 0.0
	var peak := 0
	var pending_s := 0.0
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		var el := (now - start) / 1e6
		if el > 60.0:
			break
		if el > 0.5:  # the first frames after the jump
			worst = maxf(worst, dt * 1000.0)
		n += 1
		tv.rig.position += fwd * speed * dt
		tv.rig.position.y = t.height_at(tv.rig.position) + alt
		t._results_mutex.lock()
		var pending: int = t._queue.size() + t._busy.size() + t._results.size()
		t._results_mutex.unlock()
		peak = maxi(peak, pending)
		pending_s += pending * dt
		if el >= next_print:
			print("ST t=%2d s  pending %d" % [int(el), pending])
			next_print += 5.0
	print(
		(
			"ST pass worst %.1f ms  avg %.1f fps  pending peak %d  node-seconds waiting %.0f"
			% [worst, n / 60.0, peak, pending_s]
		)
	)
	var keys: Array = t._res.keys().filter(func(k): return k.x == 0)
	keys = keys.slice(0, 40)
	var th := Thread.new()
	th.start(
		func() -> float:
			var u0 := Time.get_ticks_usec()
			for k in keys:
				t._decode(k)
			return (Time.get_ticks_usec() - u0) / 1000.0 / keys.size()
	)
	while th.is_alive():
		await process_frame
	print("ST node load %.1f ms (%d colour nodes, one worker thread)" % [th.wait_to_finish(), keys.size()])
	print("RESULT PASS")
	quit()
