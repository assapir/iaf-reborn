# Dev helper (not run by tools/test.sh): the 3D cockpit's lean (views.gd lean, the Shift + arrow keys) in each jet's
# cold start-up flight: the left console past the throttle, the right console, the lower pedestal, and the lean's limits
# against the canopy and the seat (modern-iaf/docs/cockpit.md §2). SHOW_SIZE (e.g. 2560x1440): the picture's size.
# Files SHOW_OUT/<jet>_<pose>_<height>.png.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> [SHOW_JETS=f35i] \
#     -- --log-file <temp> --resolution 1280x720 --path modern-iaf -s ../modern-iaf/tests/_lean_shot.gd
extends "res://../tests/godot/base.gd"

const JETS := {"f16i": 2011, "f35i": 2031}
## [name, lean (m: x right, y up, z aft; LEAN_MIN / LEAN_MAX by sign), head yaw, head pitch (deg), zoom]
const POSES := [
	["left_seat", Vector3.ZERO, -40.0, -50.0, 0.6],
	["left_lean", Vector3(-1, 0, -1), -20.0, -60.0, 0.6],
	["left_lean_zoom", Vector3(-1, 0, -1), -15.0, -60.0, 1.2],
	["right_lean", Vector3(1, 0, -1), 25.0, -60.0, 0.6],
	["pedestal", Vector3(0, -1, -1), 0.0, -60.0, 0.6],
	["limit_left_up", Vector3(-1, 1, 1), -90.0, 10.0, 0.6],
	["limit_right_up", Vector3(1, 1, 1), 90.0, 10.0, 0.6],
	["limit_up_ahead", Vector3(0, 1, -1), 0.0, 30.0, 0.6],
	["limit_back", Vector3(0, 1, 1), 170.0, 0.0, 0.6],
]


func run() -> void:
	var out := OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var size := OS.get_environment("SHOW_SIZE").split("x")
	if size.size() == 2:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(int(size[0]), int(size[1]))
	settings().show_info = false
	var only := OS.get_environment("SHOW_JETS").split(",", false)
	for jet in JETS:
		if not only.is_empty() and not jet in only:
			continue
		load("res://flight/fly.gd").start(JETS[jet])
		await frames(2)
		var tv: Node = null
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		await frames(30)
		tv.addon.kneeboard.set_raised(false)
		var v = tv.views
		for p in POSES:
			var l: Vector3 = p[1]
			v.lean = Vector3(
				v.LEAN_MIN.x if l.x < 0 else v.LEAN_MAX.x if l.x > 0 else 0.0,
				v.LEAN_MIN.y if l.y < 0 else v.LEAN_MAX.y if l.y > 0 else 0.0,
				v.LEAN_MIN.z if l.z < 0 else v.LEAN_MAX.z if l.z > 0 else 0.0
			)
			v.snap = Vector2(deg_to_rad(p[2]), deg_to_rad(p[3]))
			tv.cockpit.zoom = p[4]
			await frames(20)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png(out.path_join("%s_%s_%d.png" % [jet, p[0], img.get_height()]))
		v.snap = null
		v.lean = Vector3.ZERO
	check(true, "shots in %s" % out)
