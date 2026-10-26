# Dev helper (not run by tools/test.sh): real-render captures of the Graphics → MORE sky (docs/rendering.md §1.2)
# from mission SKY_MISSION (default 311) at each hour of SKY_HOURS (default 12.5,17.5,19.8,22) and altitude of
# SKY_ALTS (m above the ground, default 300,5000; the cloud layer whites out above 6000 m), looking SKY_TURN degrees
# right of the sun's azimuth (default 25), from the cockpit and outside (orbit 150°, 12°, 40 m). SKY_SET="key=value,..."
# sets Settings first (default sky=atmospheric); SKY_SEED (default 3) fixes the cloud texture. Saved to
# SHOT_DIR/sky_<alt>_<hour>_{cockpit,external}.png.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/shots -- --log-file /tmp/s.log --path game \
#       --resolution 1920x1080 -s ../tests/godot/_sky_shot.gd
extends "res://../tests/godot/base.gd"

const TimeOfDay := preload("res://terrain/time_of_day.gd")


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


func run() -> void:
	var dir := _env("SHOT_DIR", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	for kv in _env("SKY_SET", "sky=atmospheric").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]) if str_to_var(p[1]) != null else p[1])
	settings().show_info = false  # no status line
	seed(int(_env("SKY_SEED", "3")))  # the cloud layer's texture (cloud_layer.gd randi() % 6): the same each run
	var tv = await start_mission(int(_env("SKY_MISSION", "311")))
	tv.frozen = true
	tv.fm_stopped = true
	tv.text_messages = false  # no instructor text over the pictures
	tv.cockpit.subtitles = [] as Array[String]
	for alt_s in _env("SKY_ALTS", "300,5000").split(","):
		var g = tv.terrain.height_at(tv.rig.position)
		tv.rig.position.y = (g if g != null else 0.0) + float(alt_s)
		for hour_s in _env("SKY_HOURS", "12.5,17.5,19.8,22").split(","):
			var t := float(hour_s) * 3600.0
			tv.runtime.misc["0x460"] = t - tv.runtime.now
			var az: float = TimeOfDay.sun(t).sun_az + float(_env("SKY_TURN", "25"))
			tv.rig.basis = Basis.from_euler(Vector3(deg_to_rad(-3.0), deg_to_rad(-az), 0.0), EULER_ORDER_YXZ)
			for view in ["cockpit", "external"]:
				tv.in_cockpit = view == "cockpit"
				if view == "external":
					tv.views.orbit_heading = deg_to_rad(150.0) - PI
					tv.views.orbit_pitch = -deg_to_rad(12.0)
					tv.views.dist = 40.0
				tv._apply_view()
				tv._tod_t = -INF
				var t0 := Time.get_ticks_msec()
				await frames(10)
				while tv.terrain.missing_after_frame() and Time.get_ticks_msec() - t0 < 30000:
					await process_frame
				# The sky's radiance (incremental) and any exposure adaptation settle.
				t0 = Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < 2500:
					await process_frame
				await RenderingServer.frame_post_draw
				var path := dir.path_join("sky_%s_%s_%s.png" % [alt_s, hour_s, view])
				root.get_viewport().get_texture().get_image().save_png(path)
				print("SHOT ", path)
	settings().sky = "original"
	print("RESULT PASS")
	quit()
