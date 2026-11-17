# Dev helper (not run by tools/test.sh): the left console from the eye turned to MAIN PWR (the F-16s) or BATT (the
# F-35I) in the take-off lesson, the pilot's body shown and hidden (cockpit3d.gd body_off, Alt + G):
# SHOT_OUT/<jet>_body_shown.png, <jet>_body_hidden.png.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> -- --log-file <t> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_body_shot.gd
extends "res://tests/test_mvp.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-body-%d" % OS.get_process_id())
	settings().show_info = false
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	for name in ["ramon_takeoff", "nevatim_takeoff"]:
		var tv := await _start(name)
		Engine.time_scale = 1.0
		await fly(tv, 1.0)
		var c3d = tv.cockpit_3d
		var mi: MeshInstance3D = c3d.find_child("MAIN_PWR", true, false)
		if mi == null:
			mi = c3d.find_child("BATT", true, false)
		var centre := func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center()
		await _aim(tv, centre, 0.25)
		await fly(tv, 0.5)
		print(name, " body covers ", mi.name, ": ", c3d.body_covers(centre.call()))
		var jet := "f35i" if name.begins_with("nevatim") else "f16i"
		for hide in [false, true]:
			c3d.body_off = hide
			await fly(tv, 0.3)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				dir.path_join("%s_body_%s.png" % [jet, "hidden" if hide else "shown"])
			)
		c3d.body_off = false
