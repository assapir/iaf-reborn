# Probe: the sim's 6-DoF airborne (run with -- --mission 2012 --at x y alt hdg pitch roll): per frame the process
# delta, the wall-clock frame time, the camera and rig positions and the ILS, 600 frames.
extends "res://../tests/godot/base.gd"


func run() -> void:
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(30)
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	var us := Time.get_ticks_usec()
	for i in 600:
		await process_frame
		var now := Time.get_ticks_usec()
		var c: Vector3 = cam.global_position
		var r: Vector3 = tv.rig.global_position
		var il: Vector2 = tv.flight.ils()
		print(
			(
				"F %d %.6f %.6f %.5f %.5f %.5f %.5f %.5f %.5f %.6f %.6f"
				% [i, tv.get_process_delta_time(), (now - us) / 1e6, c.x, c.y, c.z, r.x, r.y, r.z, il.x, il.y]
			)
		)
		us = now
