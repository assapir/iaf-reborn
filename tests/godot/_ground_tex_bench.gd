# Dev helper (not run by tools/test.sh): hitches and frame rate of one Settings configuration (docs/rendering.md §1.4).
# GT_SET="key=value,…" sets Settings keys (str_to_var values); GT_PRELOAD=1 first starts the mission screens'
# preload (terrain/ground_textures.gd preload_async), waits 3 s as a briefing would, and times the upload that is left
# for the flight's start (load_globals; a no-op when the switch is off). Then it starts the flight
# (terrain_view's args), prints the mission start time (scene change to the first flying frame), the worst frame and
# the average fps over the first 30 s, then 15 s in the external view where the jet stands (its stores, the wingmen,
# the base: Model detail's busy view), then a low pass (frozen flight model, cockpit: down to GT_ALT m above the
# ground, default 60, in 5 s, then 25 s at 150 m/s along the heading) with its worst frame and fps. Vsync off.
# GT_PRELOAD also starts Model detail's preload (util/model_detail.gd preload_packs), as the front end does.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 GT_SET='ground_textures="ambientcg"' GT_PRELOAD=1 -- \
#     --log-file /tmp/g.log --path game --resolution 2560x1440 -s ../tests/godot/_ground_tex_bench.gd -- --mission 311
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kv in OS.get_environment("GT_SET").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]))
	if OS.get_environment("GT_PRELOAD") == "1":
		var gt: GDScript = load("res://terrain/ground_textures.gd")
		gt.preload_async()
		load("res://util/model_detail.gd").preload_packs()
		await create_timer(3.0).timeout
		var u0 := Time.get_ticks_usec()
		if settings().ground_textures == "ambientcg":
			gt.load_globals()
		print("GT upload %.1f ms (after the preload)" % ((Time.get_ticks_usec() - u0) / 1000.0))
	var t0 := Time.get_ticks_usec()
	change_scene_to_file("res://terrain/terrain_view.tscn")
	await frames(2)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	print("GT start %.2f s" % ((Time.get_ticks_usec() - t0) / 1e6))
	var r := await _measure(30.0, Callable())
	print("GT first30 worst %.1f ms  avg %.1f fps" % [r[0], r[1]])
	tv.frozen = true
	tv.fm_stopped = true
	tv.in_cockpit = false
	tv._apply_view()
	r = await _measure(15.0, Callable())
	print("GT external worst %.1f ms  avg %.1f fps" % [r[0], r[1]])
	tv.in_cockpit = true
	tv._apply_view()
	var alt := float(OS.get_environment("GT_ALT")) if OS.get_environment("GT_ALT") != "" else 60.0
	var fwd: Vector3 = -tv.rig.basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	tv.rig.basis = Basis.looking_at(fwd, Vector3.UP)
	var y0: float = tv.rig.position.y
	var step := func(t: float, dt: float) -> void:
		tv.rig.position += fwd * 150.0 * dt
		var g: float = tv.terrain.height_at(tv.rig.position) + alt
		tv.rig.position.y = lerpf(y0, g, clampf(t / 5.0, 0.0, 1.0)) if t < 5.0 else g
	r = await _measure(30.0, step)
	print("GT pass worst %.1f ms  avg %.1f fps" % [r[0], r[1]])
	print("GT textures %.1f MB" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0))
	print("RESULT PASS")
	quit()


## [worst frame ms, average fps] over `secs`; `step(t, dt)` moves the rig each frame when given.
func _measure(secs: float, step: Callable) -> Array:
	var worst := 0.0
	var n := 0
	var start := Time.get_ticks_usec()
	var last := start
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		var t := (now - start) / 1e6
		if t > secs:
			break
		worst = maxf(worst, dt * 1000.0)
		n += 1
		if step.is_valid():
			step.call(t, dt)
	return [worst, n / secs]
