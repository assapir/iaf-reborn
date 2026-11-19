# Dev helper (not run by tools/test.sh): the player's jet at its start spot (airbases.md §5: in a shelter where the
# base has them), the Sufa's start-up mission at Ramon (2011), the lesson's boxes hidden.
# SHOT_DIR/<SHOT_NAME>_<view>.jpg: cockpit (the pilot's view), outside (from 45 m ahead of the nose, 3 m up, looking
# back at the jet) and above (90 m up, 60 m behind, looking down the nose's way: the way out). The same script runs on
# main (before pictures). Night: `-- --hour 22`. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_NAME=<n> \
#     -- --log-file <temp> --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_shelter_shot.gd \
#     [-- --hour 22]
extends "res://../tests/godot/base.gd"

var _cam: Camera3D
var _xf := Transform3D.IDENTITY


func _pre_draw() -> void:
	if is_instance_valid(_cam):
		_cam.global_transform = _xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _xf)
		_cam.set_perspective(60.0, 0.05, 30000.0)


func _save(path: String) -> void:
	await frames(60)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(path, 0.9)


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	var stem := OS.get_environment("SHOT_NAME")
	DirAccess.make_dir_recursive_absolute(dir)
	settings().show_info = false
	load("res://flight/fly.gd").start(2011)
	var tv: Node = null
	await process_frame
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await ground_streamed(tv, 30000, 20)
	await create_timer(3.0).timeout
	tv.addon.ui.visible = false
	tv.in_cockpit = true
	await _save(dir.path_join(stem + "_cockpit.jpg"))
	# The free camera, placed in the world's frame round the jet.
	var w: Vector3 = tv.player_world()
	var h := deg_to_rad(float(tv.flight.state().heading))
	var fwd := Vector2(sin(h), cos(h))
	tv.in_cockpit = false
	_cam = tv.chase
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	for v in [["outside", 45.0, 3.0], ["above", -60.0, 90.0]]:
		var p := Vector3(w.x + fwd.x * v[1], w.y + fwd.y * v[1], w.z + v[2])
		var pos: Vector3 = tv.world_to_scene(p)
		var at: Vector3 = tv.world_to_scene(w)
		if v[0] == "above":
			at = tv.world_to_scene(Vector3(w.x + fwd.x * 40.0, w.y + fwd.y * 40.0, w.z))
		_xf = Transform3D(Basis.looking_at(at - pos, Vector3.UP), pos)
		await _save(dir.path_join("%s_%s.jpg" % [stem, v[0]]))
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
