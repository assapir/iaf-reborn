# Dev helper (not a test): the frame cost of the effects (docs/rendering.md §6, docs/graphics-research.md §3.4) under a
# scripted combat load in mission 231 (FX_MISSION): every 2 s a ground vehicle and an aircraft explode and a missile
# hits, two missile trails fly through the view, three units smoke. The effects' drawing is switched off and on every
# 120 frames in the same window (the water bench's method); prints the median of the on − off pairs. FX_DETAILED=1
# turns on "Particle effects: Detailed". Run at 4K with a render scale so the GPU, not the display's refresh, sets the frame
# (docs/graphics-research.md §1):
#   FX_DETAILED=1 FX_SCALE=1.6 IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 3840x2160 -s ../tests/godot/_fx_bench.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Settings().particle_effects = OS.get_environment("FX_DETAILED") == "1"
	Settings().show_info = false
	var mid := OS.get_environment("FX_MISSION")
	var tv = await start_mission(int(mid) if mid != "" else 231)
	tv.frozen = true
	tv.fm_stopped = true
	if OS.get_environment("FX_SCALE") != "":
		tv.get_viewport().scaling_3d_scale = float(OS.get_environment("FX_SCALE"))
	var fx: Node = tv.effects
	var g0 = tv.terrain.height_at(tv.rig.position)
	tv.rig.position.y = (g0 if g0 != null else 0.0) + 120.0
	tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(-8.0), 0.0, 0.0), EULER_ORDER_YXZ)
	tv._apply_view()
	var fwd: Vector3 = -tv.rig.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var t0 := Time.get_ticks_msec()
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(60)
	var smokers: Array = []
	for i in 3:
		var n := Node3D.new()
		tv.add_child(n)
		n.global_position = _ground(tv, tv.rig.position + fwd * (900.0 + 300.0 * i) + side * (i - 1) * 250.0)
		fx.set_smoke(n, true)
		smokers.append(n)
	var layers: Array = [fx.gpu] if fx.gpu != null else [fx._mm_smoke, fx._mm_fire]
	var start := Time.get_ticks_usec()
	var last := start
	var next_burst := 0.0
	var k := 0
	var frame := 0
	var on := true
	var window: Array[float] = []
	var means := {true: [], false: []}
	while Time.get_ticks_usec() - start < 40_000_000:
		var t := (Time.get_ticks_usec() - start) / 1e6
		if t >= next_burst:
			next_burst += 2.0
			k += 1
			var p := _ground(tv, tv.rig.position + fwd * (700.0 + 80.0 * (k % 4)) + side * (k % 3 - 1) * 200.0)
			var e: Dictionary = fx.explosion_for(8, 0, true, false)
			fx.explosion(p, e.flags, e.scale, e.duration, p.y, 6.0)
			var a: Vector3 = p + Vector3(0, 400, 0) + side * 300.0
			e = fx.explosion_for(1, 0, false, false)
			fx.explosion(a, e.flags, e.scale, e.duration, p.y, 8.0)
			var h := _ground(tv, p - side * 350.0)
			fx.explosion(h, fx.F_FIREBALL | fx.F_PUFF, 1.0, 5.0, h.y)
		if tv.trails != null:
			for m in 2:
				var head: Vector3 = tv.rig.position + fwd * (600.0 + 400.0 * m) + Vector3(0, 60.0 + 80.0 * m, 0) \
						+ side * (fposmod(t * 450.0, 1800.0) - 900.0) * (1 if m == 0 else -1)
				tv.trails.emit("bench%d" % m, head, tv.trails.MISSILE)
		await process_frame
		var now := Time.get_ticks_usec()
		if frame % 120 >= 10:  # settled after the switch
			window.append((now - last) / 1000.0)
		last = now
		frame += 1
		if frame % 120 == 0:
			var avg := 0.0
			for x in window:
				avg += x
			means[on].append(avg / window.size())
			window.clear()
			on = not on
			for l in layers:
				l.visible = on
	var diffs: Array = []
	for i in mini(means[true].size(), means[false].size()):
		diffs.append(means[true][i] - means[false][i])
	diffs.sort()
	var off_avg := 0.0
	for x in means[false]:
		off_avg += x
	off_avg /= maxi(means[false].size(), 1)
	print("FX %s: drawing on - off median %+.2f ms (quartiles %+.2f / %+.2f, %d pairs), frame with it off %.2f ms, emitted %s" % [
		"detailed" if Settings().particle_effects else "original", diffs[diffs.size() / 2], diffs[diffs.size() / 4],
		diffs[diffs.size() * 3 / 4], diffs.size(), off_avg, fx.gpu.emitted if fx.gpu != null else {}])
	for l in layers:
		l.visible = true
	if OS.get_environment("FX_SHOT") != "":
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("FX_SHOT"))


func _ground(tv, p: Vector3) -> Vector3:
	var h = tv.terrain.height_at(p)
	return Vector3(p.x, float(h) if h != null else p.y, p.z)
