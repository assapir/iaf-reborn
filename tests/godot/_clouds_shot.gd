# Dev helper (not run by tools/test.sh): real-render pictures and frame times of the clouds (docs/rendering.md §2.1,
# §10.1): the rain's deck from below, inside and above it, and the fair-weather cumulus, at Ramat David (mission 311),
# the flight model stopped.
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 300 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOT_DIR=/tmp/clouds -- --log-file /tmp/c.log --path game --resolution 1920x1080 -s ../tests/godot/_clouds_shot.gd
# CLOUD_SET="key=value,..." sets Settings first (e.g. clouds=volumetric); CLOUD_BEST=1 every graphics option at its
# best (as _rain_shot.gd RAIN_BEST). CLOUD_ONLY=name,... picks shots; CLOUD_TAG prefixes the file names
# (SHOT_DIR/<tag><name>.png). CLOUD_BENCH=secs: the average frame time and the GPU's render time of each shot's view
# instead of pictures (vsync off). CLOUD_FX_FLAGS: the explosions' flags (damage_effects.gd F_*, e.g. 0x42 the debris
# alone). Each wait counts drawn frames (_drawn: a window the desktop does not show draws seldom). Shots: [name, rain,
# m above the ground, hour, pitch (deg, + up), turn from the sun's azimuth (deg), view, and "fx": an explosion in the
# air above the deck and one inside it, 36 frames before the picture, "auto" (_explode_auto), or a list of [m along
# the view, m to the side]: explosions there].
extends "res://../tests/godot/base.gd"

const TimeOfDay := preload("res://terrain/time_of_day.gd")
const SHOTS := [
	["rain_below_cockpit", "light", 400.0, 12.5, 4.0, 40.0, "cockpit"],
	["rain_below_external", "light", 400.0, 12.5, 4.0, 40.0, "external"],
	["rain_inside", "light", 1900.0, 12.5, 0.0, 40.0, "cockpit"],
	["rain_above_down", "light", 3450.0, 12.5, -12.0, 120.0, "external"],
	["rain_above_nadir", "light", 3450.0, 12.5, -80.0, 120.0, "external"],
	["rain_above_sun", "light", 3450.0, 16.5, -2.0, 0.0, "cockpit"],
	["rain_above_fx", "light", 3450.0, 12.5, -45.0, 120.0, "external", "fx"],
	["clear_above_sun", "off", 3450.0, 16.5, -2.0, 0.0, "cockpit"],
	["heavy_above", "heavy", 6000.0, 12.5, -8.0, 60.0, "external"],
	["cumulus_noon", "off", 600.0, 12.5, 6.0, 60.0, "external"],
	["cumulus_noon_cockpit", "off", 900.0, 12.5, 8.0, 150.0, "cockpit"],
	["cumulus_level", "off", 1900.0, 12.5, 0.0, 100.0, "external"],
	["cumulus_sunset", "off", 600.0, 19.6, 4.0, 10.0, "external"],
	["cumulus_night", "off", 600.0, 22.0, 6.0, 60.0, "external"],
	# Behind the clouds or in front of them: explosions (with sparks under Effects Detailed) and the night's lights.
	["cumulus_fx", "off", 900.0, 12.5, 8.0, 150.0, "cockpit", "auto"],
	["cumulus_fx_ext", "off", 1500.0, 12.5, 4.0, 100.0, "external", "auto"],
	["rain_below_fx", "light", 400.0, 12.5, 5.0, 40.0, "cockpit", "auto"],
	["rain_inside_fx", "light", 1900.0, 12.5, 0.0, 40.0, "cockpit", [[60.0, -15.0], [150.0, 0.0], [400.0, 60.0]]],
	["cumulus_night_above", "off", 3450.0, 22.0, -10.0, 0.0, "external"],
	["cumulus_night_above2", "off", 3450.0, 22.0, -10.0, 90.0, "external"],
	["cumulus_night_above3", "off", 3450.0, 22.0, -10.0, 180.0, "external"],
	["cumulus_night_above4", "off", 3450.0, 22.0, -10.0, 270.0, "external"],
]

var tv: Node
## terrain/weather.gd (loaded at run time: it needs the Settings autoload).
var weather: GDScript


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
	weather = load("res://terrain/weather.gd")
	tv = await start_mission(311)
	await frames(30)
	tv.frozen = true
	tv.fm_stopped = true
	tv.text_messages = false
	tv.cockpit.subtitles = [] as Array[String]
	var bench := float(_env("CLOUD_BENCH", "0"))
	if bench > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		load("res://terrain/volumetric_clouds.gd").Effect.timing = true
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
		await _drawn(90)
		if shot.size() > 7:
			# The same explosions in every run (before / after pictures).
			tv.effects._rng.seed = 7
			if tv.effects.gpu != null:
				tv.effects.gpu._rng.seed = 7
			if shot[7] is Array:
				_explode_along(shot[7])
			elif shot[7] == "auto":
				_explode_auto()
			else:
				_explode()
			await _drawn(36)
		if bench > 0.0:
			await _measure(shot[0], bench)
			continue
		await RenderingServer.frame_post_draw
		var path := dir.path_join(_env("CLOUD_TAG", "") + shot[0] + ".png")
		root.get_viewport().get_texture().get_image().save_png(path)
		var w := weather
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


## Two air kills' explosions where the camera's view meets 200 m over the deck's top (in front of it, left) and 800 m
## under it (inside the deck, behind its top: hidden, right).
func _explode() -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var f := -cam.global_basis.z
	var e: Dictionary = tv.effects.explosion_for(1, 0, false, false)
	for k in [[200.0, -150.0], [-800.0, 150.0]]:
		var y: float = weather.deck().y + k[0]
		var a: Vector3 = cam.global_position + f * (cam.global_position.y - y) / maxf(-f.y, 0.1)
		tv.effects.explosion(a + cam.global_basis.x * k[1], _fx_flags(e.flags), 6.0, e.duration, 0.0, 8.0)


## Air kills' explosions picked by the clouds' image now (Volumetric): behind a thick cloud, behind a thin edge (both
## 800 m past the cloud's mean distance) and in front of a thick cloud (at half its distance). Prints each spot.
func _explode_auto() -> void:
	var vc = tv.get("vclouds")
	if vc == null or vc.views.is_empty():
		return
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var ef = vc.views[0].effect
	var rd := RenderingServer.get_rendering_device()
	var dd := rd.texture_get_data(ef.a_dist, 0).to_float32_array()
	var cc := rd.texture_get_data(ef.a_color, 0)
	var vs := Vector2(root.get_viewport().get_visible_rect().size)
	# [want light-through min, max, distance share]: thick behind, thin behind, thick in front.
	var picks := [[0.0, 0.1, 1.0], [0.35, 0.75, 1.0], [0.0, 0.1, 0.5]]
	var used: Array[Vector2] = []
	var e: Dictionary = tv.effects.explosion_for(1, 0, false, false)
	for want in picks:
		var found := false
		for gy in range(2, 44):
			for gx in range(2, 38):
				var uv := Vector2(gx / 40.0, gy / 48.0)
				if uv.y > (0.5 if tv.in_cockpit else 0.9) or used.any(func(u): return u.distance_to(uv) < 0.15):
					continue
				var px := Vector2i(int(uv.x * ef.size.x), int(uv.y * ef.size.y))
				var i: int = px.y * ef.size.x + px.x
				var a := cc.decode_half(i * 8 + 6)
				var cd: float = dd[i * 2]
				if a < want[0] or a > want[1] or cd < 1000.0 or cd > 7000.0 or dd[i * 2 + 1] < cd + 2000.0:
					continue
				var d: float = cd + 800.0 if want[2] >= 1.0 else cd * want[2]
				var p := cam.project_position(uv * vs, d)
				p = cam.global_position + (p - cam.global_position).normalized() * d
				tv.effects.explosion(p, _fx_flags(e.flags), 6.0, e.duration, 0.0, 8.0)
				print("FX at screen %s: light through %.2f, cloud %.0f m, explosion %.0f m" % [uv, a, cd, d])
				used.append(uv)
				found = true
				break
			if found:
				break


## The explosion's flags; CLOUD_FX_FLAGS (a number) in their place, e.g. 0x42: only the debris, at once.
func _fx_flags(flags: int) -> int:
	var f := _env("CLOUD_FX_FLAGS", "")
	return flags if f == "" else f.hex_to_int() if f.begins_with("0x") else int(f)


## Air kills' explosions at [m along the view, m to its right].
func _explode_along(at: Array) -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var e: Dictionary = tv.effects.explosion_for(1, 0, false, false)
	for k in at:
		var a: Vector3 = cam.global_position - cam.global_basis.z * k[0] + cam.global_basis.x * k[1]
		tv.effects.explosion(a, _fx_flags(e.flags), 6.0, e.duration, 0.0, 8.0)


## n frames drawn: a window the desktop does not show (Wayland stops its frame callbacks) draws about one frame in 40,
## so the clouds' temporal history held the last shot's clouds (2026-11-02); such a frame is drawn here.
func _drawn(n: int) -> void:
	var last := Engine.get_frames_drawn()
	for i in n:
		await process_frame
		if Engine.get_frames_drawn() == last:
			RenderingServer.force_draw(false)
		last = Engine.get_frames_drawn()


func _measure(name: String, secs: float) -> void:
	var times: Array[float] = []
	var gpu := 0.0
	var march := 0.0
	var marches := 0
	var rd := RenderingServer.get_rendering_device()
	# CLOUD_PART: one part of the clouds left out, for its share: "noquad" (the composite), "nodispatch" (the march and
	# its copies; the effect stays, with the resolved depth), "noeffect" (the compositor effect and the quad).
	if OS.get_environment("CLOUD_MSAA") == "0":  # the 3D view without MSAA (for the share MSAA adds)
		root.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var part := OS.get_environment("CLOUD_PART")
	if part != "" and tv.vclouds != null:
		var v: Dictionary = tv.vclouds.views[0]
		v.quad.layers = 0
		if part == "nodispatch":
			v.effect._pipe = RID()
		elif part == "noeffect":
			for c in v.cams:
				c.compositor = null
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(secs * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		last = now
		var t0 := -1.0
		for i in rd.get_captured_timestamps_count():
			var n := rd.get_captured_timestamp_name(i)
			if n == "clouds march":
				t0 = rd.get_captured_timestamp_gpu_time(i)
			elif n == "clouds march end" and t0 >= 0.0:
				march += (rd.get_captured_timestamp_gpu_time(i) - t0) / 1e6  # ns
				marches += 1
	times.sort()
	var avg := 0.0
	for x in times:
		avg += x
	avg /= times.size()
	print(
		(
			"CLOUDS %-22s frame %6.2f ms  p95 %6.2f  gpu %6.2f ms  march %6.2f ms"
			% [name, avg, times[int(times.size() * 0.95)], gpu / times.size(), march / maxi(marches, 1)]
		)
	)
