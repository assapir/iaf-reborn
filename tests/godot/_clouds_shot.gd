# Dev helper (not run by tools/test.sh): real-render pictures and frame times of the clouds (docs/rendering.md §2.1,
# §10.1): the rain's deck from below, inside and above it, and the fair-weather cumulus, at Ramat David (mission 311),
# the flight model stopped.
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 300 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOT_DIR=/tmp/clouds -- --log-file /tmp/c.log --path game --resolution 1920x1080 -s ../tests/godot/_clouds_shot.gd
# CLOUD_SET="key=value,..." sets Settings first (e.g. clouds=volumetric); CLOUD_BEST=1 every graphics option at its
# best (as _rain_shot.gd RAIN_BEST). CLOUD_ONLY=name,... picks shots; CLOUD_TAG prefixes the file names
# (SHOT_DIR/<tag><name>.png). CLOUD_BENCH=secs: the average frame time and the GPU's render time of each shot's view
# instead of pictures (vsync off). Shots: [name, rain, m above the ground, hour, pitch (deg, + up), turn from the
# sun's azimuth (deg), view].
extends "res://../tests/godot/base.gd"

const TimeOfDay := preload("res://terrain/time_of_day.gd")
const SHOTS := [
	["rain_below_cockpit", "light", 400.0, 12.5, 4.0, 40.0, "cockpit"],
	["rain_below_external", "light", 400.0, 12.5, 4.0, 40.0, "external"],
	["rain_inside", "light", 1900.0, 12.5, 0.0, 40.0, "cockpit"],
	["rain_above_down", "light", 3450.0, 12.5, -12.0, 120.0, "external"],
	["rain_above_sun", "light", 3450.0, 16.5, -2.0, 0.0, "cockpit"],
	["clear_above_sun", "off", 3450.0, 16.5, -2.0, 0.0, "cockpit"],
	["heavy_above", "heavy", 6000.0, 12.5, -8.0, 60.0, "external"],
	["cumulus_noon", "off", 600.0, 12.5, 6.0, 60.0, "external"],
	["cumulus_noon_cockpit", "off", 900.0, 12.5, 8.0, 150.0, "cockpit"],
	["cumulus_level", "off", 1900.0, 12.5, 0.0, 100.0, "external"],
	["cumulus_sunset", "off", 600.0, 19.6, 4.0, 10.0, "external"],
	["cumulus_night", "off", 600.0, 22.0, 6.0, 60.0, "external"],
]

var tv: Node


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	var dir := _env("SHOT_DIR", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	s.show_info = false
	if OS.get_environment("CLOUD_BEST") == "1":
		var best := {
			"antialiasing": "taa",
			"upscaling": "quality",
			"sky": "atmospheric",
			"night_lights": "detailed",
			"water": true,
			"particle_effects": true,
			"airbases": "detailed",
			"models": "detailed",
			"terrain_closeup": true,
			"better_cockpit": true,
			"hud_style": "real",
		}
		for k in best:
			s.set(k, best[k])
		if load("res://terrain/ground_textures.gd").available():
			s.ground_textures = "ambientcg"
		if load("res://util/model_detail.gd").available():
			s.model_detail = "ambientcg"
	for kv in _env("CLOUD_SET", "").split(",", false):
		var p := kv.split("=")
		s.set(p[0], str_to_var(p[1]) if str_to_var(p[1]) != null else p[1])
	seed(3)
	tv = await start_mission(311)
	await frames(30)
	tv.frozen = true
	tv.fm_stopped = true
	tv.text_messages = false
	tv.cockpit.subtitles = [] as Array[String]
	var bench := float(_env("CLOUD_BENCH", "0"))
	if bench > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var only := _env("CLOUD_ONLY", "").split(",", false)
	var start: Vector3 = tv.rig.position
	for shot in SHOTS:
		if not only.is_empty() and not shot[0] in only:
			continue
		if s.rain != shot[1]:
			s.rain = shot[1]
			tv.apply_render_options()
		var t: float = shot[3] * 3600.0
		tv.runtime.misc["0x460"] = t - tv.runtime.now
		var g = tv.terrain.height_at(start)
		tv.rig.position = Vector3(start.x, (g if g != null else 0.0) + shot[2], start.z)
		var az: float = TimeOfDay.sun(t).sun_az + shot[5]
		tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(shot[4]), deg_to_rad(-az), 0.0), EULER_ORDER_YXZ)
		tv.in_cockpit = shot[6] == "cockpit"
		if not tv.in_cockpit:
			tv.views.orbit_heading = deg_to_rad(160.0) - PI
			tv.views.orbit_pitch = -deg_to_rad(8.0 - shot[4])
			tv.views.dist = 30.0
		tv._apply_view()
		tv._tod_t = -INF
		var t0 := Time.get_ticks_msec()
		await frames(10)
		while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		await frames(90)
		if bench > 0.0:
			await _measure(shot[0], bench)
			continue
		await RenderingServer.frame_post_draw
		var path := dir.path_join(_env("CLOUD_TAG", "") + shot[0] + ".png")
		root.get_viewport().get_texture().get_image().save_png(path)
		var w: GDScript = load("res://terrain/weather.gd")
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		print(
			"saved ",
			path,
			(
				"  camera %.0f m, deck %s, into %.2f out %.2f, fog %.5f"
				% [
					cam.global_position.y,
					w.deck(),
					w.into,
					w.out,
					tv.get_node("WorldEnvironment").environment.fog_density
				]
			)
		)


func _measure(name: String, secs: float) -> void:
	var times: Array[float] = []
	var gpu := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(secs * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		last = now
	times.sort()
	var avg := 0.0
	for x in times:
		avg += x
	avg /= times.size()
	print(
		(
			"CLOUDS %-22s frame %6.2f ms  p95 %6.2f  gpu %6.2f ms"
			% [name, avg, times[int(times.size() * 0.95)], gpu / times.size()]
		)
	)
