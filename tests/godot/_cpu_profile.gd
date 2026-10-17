# Dev helper (not a test): where the frame's CPU time goes. Each system's _process is taken off the engine and called
# here between Time.get_ticks_usec(), the rig flown straight ahead as in _flight_bench.gd; plus the render thread's
# CPU time (viewport_get_measured_render_time_cpu) and the frame setup time. PROFILE_MISSION (default 221: many AI jets,
# SAMs), PROFILE_ALT (m above the ground, default 150), PROFILE_SECS (default 15), PROFILE_LIVE=1 (the simulation runs: the
# jet flies its flight model, the AI and weapons work; else frozen and the rig is moved), PROFILE_UPSCALING (Settings.upscaling,
# default off). docs/graphics-research.md.
#   IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 -s ../tests/godot/_cpu_profile.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var env := func(k: String, d: float) -> float: return float(OS.get_environment(k)) if OS.get_environment(k) != "" else d
	if OS.get_environment("PROFILE_UPSCALING") != "":
		Settings().upscaling = OS.get_environment("PROFILE_UPSCALING")
	var tv = await start_mission(int(env.call("PROFILE_MISSION", 221.0)))
	var live := OS.get_environment("PROFILE_LIVE") == "1"
	tv.frozen = not live
	tv.fm_stopped = not live
	await frames(30)
	var parts := {"terrain": tv.terrain, "scene (terrain_view)": tv, "mission runtime": tv.runtime, "ai flights": tv.ai,
		"ai combat": tv.ai.combat, "cockpit": tv.cockpit, "hud": tv.cockpit.hud}
	for i in tv.cockpit.mfds.size():
		parts["mfd %d" % i] = tv.cockpit.mfds[i]
	for k in parts.keys():
		if parts[k] == null or not parts[k].has_method("_process"):
			parts.erase(k)
		else:
			parts[k].set_process(false)
	var g = tv.terrain.height_at(tv.rig.position)
	tv.rig.position.y = (g if g != null else 0.0) + env.call("PROFILE_ALT", 150.0)
	tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(-4.0), deg_to_rad(-30.0), 0.0), EULER_ORDER_YXZ)
	tv._apply_view()
	var t0 := Time.get_ticks_msec()
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 20000:
		for k in parts:
			parts[k]._process(0.016)
		await process_frame
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var sum := {}
	var worst := {}
	for k in parts:
		sum[k] = 0.0
		worst[k] = 0.0
	var render_cpu := 0.0
	var setup := 0.0
	var frame := 0.0
	var n := 0
	var fwd: Vector3 = -tv.rig.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(env.call("PROFILE_SECS", 15.0) * 1e6):
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		if not live:
			tv.rig.position += fwd * 250.0 * dt
		for k in parts:
			var a := Time.get_ticks_usec()
			parts[k]._process(dt)
			var ms := (Time.get_ticks_usec() - a) / 1000.0
			sum[k] += ms
			worst[k] = maxf(worst[k], ms)
		await process_frame
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		setup += RenderingServer.get_frame_setup_time_cpu()
		frame += dt * 1000.0
		n += 1
	print("PROFILE %s 3D mode %d scale %.2f frames %d  frame %.2f ms  render-thread cpu %.2f ms  frame setup %.2f ms" % [str(root.size), tv.get_viewport().scaling_3d_mode, tv.get_viewport().scaling_3d_scale, n, frame / n, render_cpu / n, setup / n])
	for k in sum:
		print("  %-20s avg %6.3f ms  worst %7.2f ms" % [k, sum[k] / n, worst[k]])
	print("RESULT PASS")
