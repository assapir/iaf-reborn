# Dev helper (not run by tools/test.sh): real renders of the instructor's demonstration (modern-iaf/docs/training.md
# "The instructor flies"), as test_instructor_demo.gd / test_instructor_lead.gd start it. SHOT_JET=f16: the Sufa at
# Ramon, "My controls": the cockpit ahead with the subtitle, the hands on the stick and the throttle in the break, the
# jet in the break and on final from outside. SHOT_JET=f35: the Adir at Nevatim, "Follow me": the instructor's F-35I
# beside the player's (the chase), then from behind the player's jet with the subtitle, and from outside in its break.
# SHOT_DIR names the folder.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_JET=f16 -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_instructor_shot.gd
extends "res://../modern-iaf/tests/instructor_base.gd"

const HANDS := Vector2(-0.2, -0.8)  # the head looking down at the hands (views.gd snap; _cockpit_look_shot.gd)

var tv: Node
var _cam: Camera3D
var _follow: Node3D = null
var _look: Node3D = null  # the camera looks at this one (null: at _follow)
var _back := 30.0
var _up := 8.0
var _side := 14.0


func _pre_draw() -> void:
	if not is_instance_valid(_cam) or _follow == null:
		return
	# The drawn jet (its node: the scene's floating origin moves, the mission world's position lags it).
	var at: Vector3 = _follow.global_position
	var fwd: Vector3 = -_follow.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var e3: Vector3 = at + right * _side - fwd * _back + Vector3.UP * _up
	var to: Vector3 = _look.global_position if is_instance_valid(_look) else at
	var xf := Transform3D(Basis.looking_at(to - e3, Vector3.UP), e3)
	_cam.current = true
	_cam.global_transform = xf
	RenderingServer.camera_set_transform(_cam.get_camera_rid(), xf)
	_cam.set_perspective(50.0, 0.05, 30000.0)


func _shot(name: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
	print("saved ", name)


func _outside(node: Node3D, back: float, side: float, up: float, look: Node3D = null) -> void:
	tv.in_cockpit = false
	_follow = node
	_look = look
	_back = back
	_side = side
	_up = up
	_cam = tv.chase


func _cockpit(snap) -> void:
	_follow = null
	tv.in_cockpit = true
	tv.views.snap = snap


func _until(f: Callable, s: float) -> bool:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s and not f.call():
		await process_frame
	return f.call()


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	settings().show_info = false
	var f35 := OS.get_environment("SHOT_JET") == "f35"
	tv = await start_in_air("nevatim_takeoff" if f35 else "ramon_takeoff", "Nevatim" if f35 else "Ramon")
	if tv == null:
		return
	settings().invulnerable = true
	await ground_streamed(tv, 30000, 20)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	var ins = Instructor.of(tv)
	var me: Node3D = tv.rig
	if not f35:
		ins.demo()
		_cockpit(null)
		await _shot("f16_my_controls")
		Engine.time_scale = 4.0
		await _until(func(): return tv.flight.ap_landing_step() == 4, 300.0)
		Engine.time_scale = 1.0
		await fly(tv, 4.0)
		_cockpit(HANDS)
		await _shot("f16_break_hands")
		_outside(me, 30.0, -14.0, 6.0)
		await _shot("f16_break_outside")
		Engine.time_scale = 4.0
		await _until(func(): return tv.flight.ap_landing_step() == 13, 300.0)
		Engine.time_scale = 1.0
		await fly(tv, 6.0)
		_outside(me, 40.0, 18.0, 8.0)
		await _shot("f16_final_outside")
		_cockpit(HANDS)
		await _shot("f16_final_hands")
	else:
		tv.flight.ap_engage(1, 0)
		tv.autopilot._lamp()
		ins.chase()
		await fly(tv, 40.0)
		_outside(me, 60.0, 30.0, 25.0, ins.jet.node)
		await _shot("f35_chase_outside")
		ins.lead()
		await fly(tv, 3.0)
		# From behind the player's jet, looking at the instructor's.
		_outside(me, 50.0, 10.0, 20.0, ins.jet.node)
		await _shot("f35_follow_me")
		var f = ins.jet.pilot.flight
		Engine.time_scale = 4.0
		await _until(func(): return f.ap_landing_step() == 4, 400.0)
		Engine.time_scale = 1.0
		await fly(tv, 4.0)
		_outside(ins.jet.node, 40.0, -20.0, 10.0)
		await _shot("f35_lead_break_outside")
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
