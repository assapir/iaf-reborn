# Dev helper (not run by tools/test.sh): one real-render run that measures the frame rate of the Graphics /
# Extras render options at fixed poses and saves a screenshot of each to BENCH_DIR (docs/rendering.md).
#   IAF_DEFAULT_SETTINGS=1 BENCH_DIR=/tmp/bench godot --path game --resolution 1920x1080 -s ../tests/godot/_visual_bench.gd
# BENCH_ONLY=name,name limits the configs; BENCH_POSES=name,name the poses.
extends "res://../tests/godot/base.gd"

## Poses: [name, altitude (m), heading, pitch (deg), external orbit [yaw, pitch, dist] or [] (cockpit), explosion].
const POSES := [
	["cruise2000", 2000.0, 40.0, -3.0, [], false],
	["explosion2000", 2000.0, 40.0, 0.0, [160.0, 10.0, 60.0], true],
	["low", 60.0, 40.0, -8.0, [], false],
	["near7000", 6900.0, 40.0, 0.0, [], false],
	["above9000", 9000.0, 40.0, -10.0, [], false],
]
## Configs: name -> Settings overrides (everything else at its default).
const CONFIGS := {
	"base": {},
	"no_clouds": {"textured_sky": false},
}


func run() -> void:
	var dir := OS.get_environment("BENCH_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var only := OS.get_environment("BENCH_ONLY").split(",", false)
	var poses := OS.get_environment("BENCH_POSES").split(",", false)
	var tv = await start_mission(312)
	tv.frozen = true
	tv.fm_stopped = true  # the poses move the rig itself
	await frames(30)
	var defaults := {}
	for c in CONFIGS.values():
		for k in c:
			defaults[k] = Settings().get(k)
	for p in POSES:
		if not poses.is_empty() and not poses.has(p[0]):
			continue
		for name in CONFIGS:
			if not only.is_empty() and not only.has(name):
				continue
			for k in defaults:
				Settings().set(k, CONFIGS[name].get(k, defaults[k]))
			seed(7)  # the same cloud texture every time
			if tv.clouds != null:
				tv.clouds.free()
				tv.clouds = null
			tv.apply_render_options()
			await _pose(tv, p)
			var vp := root.get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vp, true)
			var gpu := 0.0
			var f0 := Engine.get_frames_drawn()
			var m0 := Time.get_ticks_usec()
			for i in (60 if p[5] else 180):
				await process_frame
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			var fps := 1e6 * (Engine.get_frames_drawn() - f0) / (Time.get_ticks_usec() - m0)
			await RenderingServer.frame_post_draw
			var path := dir.path_join("%s_%s.png" % [p[0], name])
			root.get_viewport().get_texture().get_image().save_png(path)
			print("BENCH %-14s %-12s %6.1f fps  gpu %5.2f ms  %s" % [p[0], name, fps, gpu / (60 if p[5] else 180), path])


func _pose(tv, p: Array) -> void:
	var g: float = tv.terrain.height_at(tv.rig.position)
	tv.rig.position.y = maxf(p[1], g + 30.0) if p[1] > 100.0 else g + p[1]
	tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(p[3]), deg_to_rad(-p[2]), 0.0), EULER_ORDER_YXZ)
	var orbit: Array = p[4]
	tv.in_cockpit = orbit.is_empty()
	if not orbit.is_empty():
		tv.views.orbit_heading = deg_to_rad(orbit[0]) - PI
		tv.views.orbit_pitch = -deg_to_rad(orbit[1])
		tv.views.dist = orbit[2]
	tv._apply_view()
	# Let the terrain stream in around the pose.
	var t0 := Time.get_ticks_msec()
	await frames(20)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(30)
	if p[5]:
		var fwd: Vector3 = -tv.rig.basis.z
		tv.effects.explosion(tv.rig.position + fwd * 40.0, 0x58ba, 4.0, 95.0, g)
		await frames(20)
