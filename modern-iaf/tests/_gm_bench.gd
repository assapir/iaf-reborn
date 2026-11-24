# Dev helper (not run by tools/test.sh): the real FCR's ground map's cost (docs/radar.md §9.7). The Sufa on its weapons
# range, 3000 m up, the range's hulks 30° left (as _fcr_ag_shot.gd), flown live: BENCH_SECS (default 12) in CRM, then
# in GM (R), then CRM again. Per phase: the mean and worst frame, the mean process time, the root viewport's GPU time,
# and the radar frames (scans) timed one by one. Vsync off. Prints a BENCH line per phase.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <temp> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_gm_bench.gd
extends "res://../tests/godot/base.gd"


func _tap(tv: Node, k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		tv._unhandled_input(e)


## Each system's _process, taken off the engine and timed here (as tests/godot/_cpu_profile.gd).
func _parts(tv: Node) -> Dictionary:
	var parts := {"terrain_view": tv, "terrain": tv.terrain, "runtime": tv.runtime, "ai": tv.ai, "cockpit": tv.cockpit}
	parts["hud"] = tv.cockpit.hud
	for i in tv.cockpit.mfds.size():
		parts["mfd %d" % i] = tv.cockpit.mfds[i]
	for k in parts.keys():
		if parts[k] == null or not parts[k].has_method("_process"):
			parts.erase(k)
	return parts


func _phase(tv: Node, name: String, secs: float) -> void:
	var w = tv.weapons
	var parts := _parts(tv)
	var spent := {}
	for k in parts:
		parts[k].set_process(false)
		spent[k] = 0.0
	var vp := root.get_viewport().get_viewport_rid()
	var n := 0
	var sum := 0.0
	var worst := 0.0
	var proc := 0.0
	var gpu := 0.0
	var scans := PackedFloat64Array()
	var serial := int(w.radar.real.get("ag", {}).get("pic", {}).get("serial", -1))
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(secs * 1e6):
		var dt := (Time.get_ticks_usec() - last) / 1e6
		for k in parts:
			var a := Time.get_ticks_usec()
			parts[k]._process(dt)
			spent[k] += (Time.get_ticks_usec() - a) / 1000.0
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		n += 1
		sum += ms
		worst = maxf(worst, ms)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var s := int(w.radar.real.get("ag", {}).get("pic", {}).get("serial", -1))
		if s != serial:
			serial = s
			scans.append(ms)
	for k in parts:
		parts[k].set_process(true)
	var each := []
	for k in parts:
		each.append("%s %.2f" % [k, spent[k] / n])
	print("BENCH %s _process ms: %s" % [name, ", ".join(each)])
	# One radar frame, called directly (a scan; in GM it starts the picture's painting, which waits for one still being
	# painted: so once).
	var t0 := Time.get_ticks_usec()
	w.radar.scan(w.now)
	var direct := (Time.get_ticks_usec() - t0) / 1000.0
	print(
		(
			(
				"BENCH %s frames %d  frame mean %.2f ms worst %.2f ms  process %.2f ms  gpu %.2f ms  scan %.2f ms  "
				+ "frames with a new picture %s"
			)
			% [name, n, sum / n, worst, proc / n, gpu / n, direct, Array(scans).map(func(x): return "%.1f" % x)]
		)
	)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var secs := float(OS.get_environment("BENCH_SECS")) if OS.get_environment("BENCH_SECS") != "" else 12.0
	var unit: String = sim_f16s().keys()[0]
	var base: String = sim_f16s()[unit]
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	var tv: Node = await start_mission(id)
	settings().mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-gm-bench-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	var t1 := {}
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == "Target 1":
			t1 = e
	var at := Vector2(t1.world.x + 22000.0, t1.world.y - 35700.0)
	var g = tv.mission_ground(Vector3(at.x, at.y, 0.0))
	var pos: Vector3 = tv.world_to_scene(Vector3(at.x, at.y, float(g if g != null else 0.0) + 3000.0))
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 0, -220), airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.85
	tv._command([213, 0, 0])  # the FCR up in STBY, CRM by itself in the air
	RenderingServer.viewport_set_measure_render_time(root.get_viewport().get_viewport_rid(), true)
	await ground_streamed(tv, 20000, 10)
	await fly(tv, 3.0)
	await _phase(tv, "CRM", secs)
	_tap(tv, KEY_R)
	await fly(tv, 2.5)
	check(String(tv.weapons.radar.real.get("ag", {}).get("name", "")) == "GM", "R: GM")
	await _phase(tv, "GM", secs)
	# GM on, the MFD showing another page: the radar's own cost without the format's drawing.
	var shown := []
	for sc in tv.cockpit_3d._screens:
		if sc[0].page == 2:
			shown.append(sc[0])
			sc[0].page = 3
	await _phase(tv, "GM-other-page", secs)
	for m in shown:
		m.page = 2
	_tap(tv, KEY_R)
	await fly(tv, 1.0)
	await _phase(tv, "CRM2", secs)
	tv.queue_free()
	await frames(5)
