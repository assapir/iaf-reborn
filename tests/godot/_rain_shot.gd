# Dev helper (not run by tools/test.sh): real-render pictures and frame times of the rain (terrain/weather.gd,
# Preferences > Graphics → MORE "Rain", docs/rendering.md §10). Mission 311 at Ramat David, the flight model stopped.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 RAIN_OUT=/tmp/rain -- --log-file /tmp/r.log --path game \
#     --resolution 2560x1440 -s ../tests/godot/_rain_shot.gd
# RAIN_LEVELS=off,light,heavy (default) picks the levels; per level the pictures <tag><level>_<view>.png: the cockpit
# on the runway, the cockpit at 400 kt 150 m over the desert, the chase view there and on the runway, the wet runway
# close from 2 m (RAIN_ONLY=runway_cockpit,... picks views). RAIN_TAG prefixes the names. RAIN_BEST=1: every
# graphics option at its best (RAIN_IMAGERY=israel,outside picks the imagery). RAIN_BENCH=secs: instead of pictures,
# the frame rate per level in three poses (the cockpit on the runway, the cockpit at 300 m over the desert at 200 m/s,
# the chase view there);
# vsync off; RAIN_HIDE=streaks,canopy leaves those parts out. Run it under `flock ~/.cache/iaf-gpu-bench.lock`.
extends "res://../tests/godot/base.gd"

## The desert: the Halutza sands (engine metres X east, Y north; docs/rendering.md §9's bench spot).
const DESERT := Vector2(307000.0, 446000.0)

var tv: Node
var out := ""
var _vel := Vector3.ZERO


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	out = OS.get_environment("RAIN_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var s := settings()
	s.show_info = false
	if OS.get_environment("RAIN_BEST") == "1":
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
		var im := OS.get_environment("RAIN_IMAGERY").split(",", false)
		if im.size() == 2:
			s.imagery_israel = im[0]
			s.imagery_outside = im[1]
	seed(1)
	tv = await start_mission(311)
	# The flight model sets the jet on its wheels over the first frames (it starts 4 m low); freeze it after.
	await frames(60)
	tv.frozen = true
	tv.fm_stopped = true
	process_frame.connect(_move)
	tv.text_messages = false  # the mission's instructor text
	var start: Transform3D = tv.rig.transform
	var levels := OS.get_environment("RAIN_LEVELS").split(",", false)
	if levels.is_empty():
		levels = PackedStringArray(["off", "light", "heavy"])
	var bench := float(OS.get_environment("RAIN_BENCH"))
	if bench > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for level in levels:
		s.rain = level
		tv.apply_render_options()
		# RAIN_HIDE=streaks,canopy: leave those parts out (their cost).
		var hide := OS.get_environment("RAIN_HIDE").split(",", false)
		if tv.weather != null:
			tv.weather.streaks.visible = not "streaks" in hide
			tv.weather._layer.visible = not "canopy" in hide
		if bench > 0.0:
			await _pose(start, Vector2.INF, 0.0, true, false)
			await _measure(level, "runway_cockpit", bench)
			await _pose(start, DESERT, 300.0, true, true)
			await _measure(level, "desert300_cockpit", bench)
			await _pose(start, DESERT, 300.0, false, true)
			await _measure(level, "desert300_external", bench)
			continue
		var tag: String = OS.get_environment("RAIN_TAG") + level + "_"
		if _want("runway_cockpit"):
			await _pose(start, Vector2.INF, 0.0, true, false)
			await _shot(tag + "runway_cockpit")
		if _want("runway_external"):
			await _pose(start, Vector2.INF, 0.0, false, false)
			await _shot(tag + "runway_external")
		if _want("runway_close"):
			await _close(start, tag + "runway_close")
		if _want("lowlevel_cockpit"):
			await _pose(start, DESERT, 150.0, true, true, 206.0)
			await _shot(tag + "lowlevel_cockpit")
		if _want("lowlevel_external"):
			await _pose(start, DESERT, 150.0, false, true, 206.0)
			await _shot(tag + "lowlevel_external")


## RAIN_ONLY=view,...: only those pictures.
func _want(view: String) -> bool:
	var only := OS.get_environment("RAIN_ONLY")
	return only == "" or view in only.split(",")


## The jet at the start (or at engine point `at`, `alt` m above the ground when `air`), the cockpit or the chase view,
## flying level along its heading at `speed` m/s (the rig moved each frame); waits for the ground and the drops.
func _pose(start: Transform3D, at: Vector2, alt: float, cockpit: bool, air: bool, speed := 200.0) -> void:
	tv.rig.transform = start
	if at != Vector2.INF:
		var o: Vector2 = tv.terrain.world_origin
		tv.rig.position = Vector3(at.x - o.x, 0.0, o.y - at.y)
	var fwd: Vector3 = -start.basis.z
	fwd.y = 0.0
	_vel = fwd.normalized() * speed if air else Vector3.ZERO
	if air:
		var g = tv.terrain.height_at(tv.rig.position)
		tv.rig.position.y = (g if g != null else 0.0) + alt
		tv.rig.basis = Basis.looking_at(fwd.normalized(), Vector3.UP)
	tv.in_cockpit = cockpit
	tv._apply_view()
	var t0 := Time.get_ticks_msec()
	await frames(5)
	while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
		await _step()
	for i in 90:
		await _step()


func _step() -> void:
	await process_frame


## Each frame, before the scene's: the rig flies on at `_vel` (also while a picture is taken).
func _move() -> void:
	if tv != null and is_instance_valid(tv):
		tv.rig.position += _vel * tv.get_process_delta_time()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, "  camera speed %.0f m/s" % (tv.weather._cam_vel.length() if tv.weather != null else 0.0))


## The runway from 2 m above it, 25 m beside the jet, looking along the runway past it.
func _close(start: Transform3D, name: String) -> void:
	await _pose(start, Vector2.INF, 0.0, false, false)
	var keep := GDScript.new()
	keep.source_code = "extends Camera3D\nfunc _process(_d):\n\tmake_current()\n"
	keep.reload()
	var cam := Camera3D.new()
	cam.set_script(keep)
	cam.process_priority = 1000
	cam.far = 60000.0
	cam.fov = 50.0
	tv.add_child(cam)
	var fwd: Vector3 = -start.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var p: Vector3 = start.origin - fwd * 30.0 + side * 6.0
	var g = tv.terrain.height_at(p)
	p.y = (g if g != null else start.origin.y) + 2.0
	cam.look_at_from_position(p, p + fwd * 40.0 - side * 6.0 + Vector3.DOWN * 3.0, Vector3.UP)
	for i in 60:
		await process_frame
	await _shot(name)
	cam.queue_free()
	await frames(2)


func _measure(level: String, pose: String, secs: float) -> void:
	var times: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(secs * 1e6):
		await _step()
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	print(
		(
			"RAIN %-6s %-20s %5.1f fps  frame %5.2f ms  p95 %5.2f  max %6.2f"
			% [level, pose, 1000.0 / avg, avg, times[int(times.size() * 0.95)], times[-1]]
		)
	)
