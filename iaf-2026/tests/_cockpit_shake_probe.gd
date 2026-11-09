# Probe (real render): the 3D cockpit's steadiness against the distance from the scene origin. Mission 2012, the
# flight model stopped, the rig moved 0.5 mm a frame at D m from the origin; per D: the camera ↔ cockpit relative
# transform's change, and the mean pixel change between successive frames in the cockpit (the lower half).
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
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var ck: Node3D = tv.cockpit_3d
	var y: float = tv.rig.position.y + 1500.0  # clear of the hills around Ramon (no collision)
	for d in [0.0, 4000.0, 15000.0, 30000.0, 60000.0]:
		if not is_instance_valid(ck):
			print("SHAKE the cockpit is gone (crashed %s)" % tv.crashed)
			return
		var rel0: Transform3D = cam.global_transform.affine_inverse() * ck.global_transform
		var prev: PackedByteArray = []
		var diffs := []
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
			prev = data
		diffs.sort()
		print(
			(
				"SHAKE d %6.0f m: cam-cockpit rel moved %.6f m; cockpit pixel change per frame median %.3f max %.3f"
				% [d, rel_max, diffs[diffs.size() / 2], diffs[-1]]
			)
		)
