# Probe: test_mvp's take-off (taxi, roll, climb-out) with the camera and state logged per frame.
#   … -s ../iaf-2026/tests/_roll_probe.gd -- --only takeoff --jet f16i
extends "res://../iaf-2026/tests/test_mvp.gd"


func _start(name: String) -> Node:
	var tv: Node = await super(name)
	Engine.time_scale = 1.0
	_log(tv)
	return tv


func _log(tv: Node) -> void:
	var i := 0
	while is_instance_valid(tv) and tv.is_inside_tree():
		await process_frame
		if not is_instance_valid(tv):
			return
		var cam: Camera3D = tv.get_viewport().get_camera_3d()
		if cam == null:
			continue
		var t := cam.global_transform
		var st: Dictionary = tv.flight.state()
		var r: Transform3D = tv.rig.global_transform
		print(
			(
				"R %d %.4f %.5f %.5f %.5f %.6f %.6f %.6f %.5f %.5f %.5f %.2f %d %.5f"
				% [
					i,
					tv._sim_time,
					t.origin.x,
					t.origin.y,
					t.origin.z,
					-t.basis.z.x,
					-t.basis.z.y,
					-t.basis.z.z,
					r.origin.x,
					r.origin.y,
					r.origin.z,
					st.speed_kt,
					int(st.on_ground),
					st.pitch
				]
			)
		)
		i += 1
