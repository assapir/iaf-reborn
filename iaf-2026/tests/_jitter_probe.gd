# Probe: mission 2012 parked at Ramon; the camera's transform for 300 frames (max step of position / basis).
extends "res://../tests/godot/base.gd"


func run() -> void:
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(30)
	var cam: Camera3D = tv.get_viewport().get_camera_3d()
	print(
		"origin ", tv.terrain.world_origin, " rig ", tv.rig.position, " cam ", cam.get_path(), " ", cam.global_position
	)
	var prev := cam.global_transform
	var mp := 0.0
	var mb := 0.0
	var mr := 0.0
	for i in 300:
		await process_frame
		var t := cam.global_transform
		mp = maxf(mp, (t.origin - prev.origin).length())
		mb = maxf(mb, (t.basis.z - prev.basis.z).length())
		mr = maxf(mr, (tv.rig.global_position - Vector3(0, tv.rig.global_position.y, 0)).length())
		if i % 60 == 0:
			print("f%d cam %s fwd %s rig %s" % [i, t.origin, -t.basis.z, tv.rig.global_transform])
		prev = t
	print(
		(
			"JITTER camera max position step %.6f m, max forward step %.8f rad, fps %d"
			% [mp, mb, Engine.get_frames_per_second()]
		)
	)
