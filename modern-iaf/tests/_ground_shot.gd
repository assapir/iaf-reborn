# Dev helper (not run by tools/test.sh): the game manual's pictures of the ground (modern-iaf/docs/manuals.md §4): a
# taxiway's signs and a runway's markings, taken from a free camera over Ramon, the lesson's boxes hidden.
# SHOT_POSE="x y up heading pitch fov" places the camera (UTM metres, its height above the ground in metres, then
# heading, pitch and view in degrees), SHOT_NAME names the picture, SHOT_DIR the folder. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_NAME=<n> \
#     SHOT_POSE="658872 3405362 2 334 0 60" -- --log-file <temp> --resolution 1600x900 \
#     --path modern-iaf -s ../modern-iaf/tests/_ground_shot.gd
extends "res://../tests/godot/base.gd"

var _cam: Camera3D
var _tv: Node
var _world := Vector3.ZERO  # the camera's UTM position and height
var _basis := Basis.IDENTITY
var _fov := 60.0


# The camera's place in the global frame each frame: the floating origin (docs/rendering.md §11) moves the scene.
func _pre_draw() -> void:
	if is_instance_valid(_cam) and is_instance_valid(_tv):
		var xf := Transform3D(_basis, _tv.world_to_global(_world))
		_cam.global_transform = xf
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), xf)
		_cam.set_perspective(_fov, 0.05, 30000.0)


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	settings().show_info = false
	load("res://flight/fly.gd").start(2011)
	var tv: Node = null
	await process_frame
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await create_timer(2.0).timeout
	tv.addon.ui.visible = false
	# SHOT_POSE: x y (UTM m), the camera's height above the ground (m), heading and pitch (degrees), the view (degrees).
	var at := OS.get_environment("SHOT_POSE").split(" ", false)
	var g = tv.mission_ground(Vector3(float(at[0]), float(at[1]), 0.0))
	_world = Vector3(float(at[0]), float(at[1]), float(g if g != null else 0.0) + float(at[2]))
	_tv = tv
	var pos: Vector3 = tv.world_to_scene(_world)
	tv.frozen = true
	var h := deg_to_rad(float(at[3]))
	tv.rig.position = pos
	tv.rig.rotation = Vector3(0.0, -deg_to_rad(float(at[3])), 0.0)
	tv.flight.start(
		settings().own_dir(),
		tv.player.fm_section,
		pos,
		Vector3(0, 0, float(at[3])),
		Vector3.ZERO,
		{"airborne": true, "engine_on": false, "real_data": false, "f16_variant": settings().f16_variant}
	)
	tv.jet_gone = true  # no jet in the picture
	tv.in_cockpit = false
	_cam = tv.chase
	_fov = float(at[5]) if at.size() > 5 else 60.0
	var dir_v := Vector3(
		sin(h) * cos(deg_to_rad(float(at[4]))), sin(deg_to_rad(float(at[4]))), -cos(h) * cos(deg_to_rad(float(at[4])))
	)
	_basis = Basis.looking_at(dir_v, Vector3.UP)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await ground_streamed(tv, 30000, 20)
	await frames(90)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(dir.path_join(OS.get_environment("SHOT_NAME") + ".jpg"), 0.9)
	print("RESULT PASS")
	tv.queue_free()
	await frames(3)
