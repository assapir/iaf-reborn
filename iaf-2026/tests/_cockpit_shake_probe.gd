# Probe (real render): the 3D cockpit's steadiness against the distance from the scene origin. Mission 2012, the
# flight model stopped, the rig moved 0.5 mm a frame at D m from the origin; per D: the camera ↔ cockpit relative
# transform's change, and the mean pixel change between successive frames in the lower half and on the panel alone;
# the frame cost (the GPU time of the flight's viewport and the cockpit's). SHAKE_SHOT=<path prefix>: a picture at each
# distance and the worst frame-to-frame step there (the change 8× brighter).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <log> --path iaf-2026 \
#     -s ../iaf-2026/tests/_cockpit_shake_probe.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().blackbox = false  # no training check: it ends the flight once the jet leaves the base
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(30)
	tv.fm_stopped = true
	# The cockpit's eye: its own world's camera when the cockpit is drawn about the origin (cockpit_origin.gd).
	var cam: Camera3D = tv.cockpit_origin.camera if tv.cockpit_origin != null else tv.get_viewport().get_camera_3d()
	var ck: Node3D = tv.cockpit_3d
	var vps: Array[RID] = [tv.get_viewport().get_viewport_rid()]
	if tv.cockpit_origin != null:
		vps.append(tv.cockpit_origin.viewport.get_viewport_rid())
	for v in vps:
		RenderingServer.viewport_set_measure_render_time(v, true)
	await frames(60)
	var gpu := [0.0, 0.0]
	var t0 := Time.get_ticks_usec()
	for i in 120:
		await RenderingServer.frame_post_draw
		for k in vps.size():
			gpu[k] += RenderingServer.viewport_get_measured_render_time_gpu(vps[k]) / 120.0
	print(
		(
			"FRAME %.2f ms a frame; GPU: the flight's viewport %.2f ms, the cockpit's %.2f ms"
			% [(Time.get_ticks_usec() - t0) / 120e3, gpu[0], gpu[1]]
		)
	)
	var y: float = tv.rig.position.y + 1500.0  # clear of the hills around Ramon (no collision)
	for d in [0.0, 4000.0, 15000.0, 30000.0, 60000.0]:
		if not is_instance_valid(ck):
			print("SHAKE the cockpit is gone (crashed %s)" % tv.crashed)
			return
		var rel0: Transform3D = cam.global_transform.affine_inverse() * ck.global_transform
		var prev: PackedByteArray = []
		var diffs := []
		var panel := []
		var worst: Image = null
		var rel_max := 0.0
		for i in 40:
			tv.rig.position = Vector3(d + i * 0.0005, y, 0)
			await RenderingServer.frame_post_draw
			var rel: Transform3D = cam.global_transform.affine_inverse() * ck.global_transform
			rel_max = maxf(rel_max, (rel.origin - rel0.origin).length())
			var img := tv.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_L8)
			var data := img.get_data()
			var h := img.get_height()
			var w := img.get_width()
			if not prev.is_empty() and i > 4:
				var s := 0
				var n := 0
				for p in range(w * (h / 2), w * h, 7):
					s += absi(data[p] - prev[p])
					n += 1
				diffs.append(float(s) / n)
				# The panel alone (the middle 40 % across, the lowest 35 %): no terrain behind it.
				s = 0
				n = 0
				for row in range(int(h * 0.65), h, 3):
					for p in range(row * w + int(w * 0.3), row * w + int(w * 0.7), 5):
						s += absi(data[p] - prev[p])
						n += 1
				panel.append(float(s) / n)
				if OS.has_environment("SHAKE_SHOT") and panel[-1] >= panel.max():  # the worst step, 8× brighter
					var dd := PackedByteArray()
					dd.resize(data.size())
					for p in data.size():
						dd[p] = mini(absi(data[p] - prev[p]) * 8, 255)
					worst = Image.create_from_data(w, h, false, Image.FORMAT_L8, dd)
			prev = data
		if OS.has_environment("SHAKE_SHOT"):  # a picture at each distance: <SHAKE_SHOT>_<km>.png
			tv.get_viewport().get_texture().get_image().save_png(
				"%s_%02d.png" % [OS.get_environment("SHAKE_SHOT"), int(d / 1000.0)]
			)
			if worst != null:
				worst.save_png("%s_%02d_step.png" % [OS.get_environment("SHAKE_SHOT"), int(d / 1000.0)])
		diffs.sort()
		panel.sort()
		print(
			(
				"SHAKE d %6.0f m: cam-cockpit %.6f m; pixel change/frame: lower half %.3f max %.3f, panel %.3f / %.3f"
				% [d, rel_max, diffs[diffs.size() / 2], diffs[-1], panel[panel.size() / 2], panel[-1]]
			)
		)
