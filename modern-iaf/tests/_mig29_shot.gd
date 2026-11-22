# Dev helper (not run by tools/test.sh): a picture of Modern IAF's MiG-29A (docs/ai.md §18) in flight over the Sufa's
# range, from a free camera beside it. The dev hook ai_flights.gd `spawn` puts it in the air ahead of the player on a
# straight route. SHOT_DIR names the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_mig29_shot.gd
extends "res://../tests/godot/base.gd"

var tv: Node
var _cam: Camera3D
var _xf := Transform3D.IDENTITY
var _follow := {}


func _pre_draw() -> void:
	if is_instance_valid(_cam):
		var at: Vector3 = tv.runtime._world_of(_follow)
		var h := deg_to_rad(float(_follow.heading))
		var fwd := Vector3(sin(h), cos(h), 0)
		var right := Vector3(cos(h), -sin(h), 0)
		var e3: Vector3 = tv.world_to_scene(at + right * 22.0 - fwd * 12.0 + Vector3(0, 0, 6.0))
		_xf = Transform3D(Basis.looking_at(tv.world_to_scene(at) - e3, Vector3.UP), e3)
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(40.0, 0.05, 30000.0)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("SHOT_DIR"))
	await require_data()
	var s := settings()
	s.show_info = false
	var id := sim_mission("ramon_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-mig29-shot", false).get_current_dir()
	tv.addon.result = {"pass": true}  # the range's scorer would end the flight into the debrief
	s.invulnerable = true
	tv.addon.ui.visible = false
	var j: Vector3 = tv.player_world()
	var g = tv.mission_ground(j)
	var at := Vector3(j.x, j.y + 3000.0, float(g if g != null else 0.0) + 1500.0)
	var route := [[at.x, at.y + 60000.0, at.z, 3]]
	var ent: Dictionary = tv.ai.spawn("mig29a", at, 0.0, route)
	if ent.is_empty():
		print("RESULT FAIL: no MiG-29A spawned")
		return
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 5.0)
	tv.in_cockpit = false
	_follow = ent
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await frames(60)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(OS.get_environment("SHOT_DIR").path_join("mig29_in_flight.png"))
	print("saved mig29_in_flight; on ground: ", ent.pilot.flight.state().on_ground)
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
