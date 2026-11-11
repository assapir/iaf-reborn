# Dev helper (not run by tools/test.sh): the Sufa's SYM wheel worked with the mouse (modern-iaf/docs/cockpit.md §5.1), a
# real render of mission 2012 on Ramon's ILS final (_ils_shot.gd's --at), frozen 3 s after the start, looking a little
# down at the ICP under the HUD:
# SHOT_OUT/sym_rest.png (the pointer away), SHOT_OUT/sym_hover.png (the pointer over the wheel, the HUD at full),
# SHOT_OUT/sym_turned.png (the wheel turned down 24 notches through the input path, the pointer moved away, the HUD at
# 40 %):
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_sym_wheel_shot.gd \
#     -- --at 666059.3 3409044.1 1179.1 246.0 -3
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().show_info = false
	settings().hud_brightness = 1.0
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	tv.gear_down = true
	tv.throttle = 0.3
	tv._throttle_event()
	await create_timer(3.0).timeout
	Engine.time_scale = 0.0
	tv.views.snap = Vector2(0.0, deg_to_rad(-4.0))  # down at the ICP, the HUD still in view
	await frames(30)
	var c3d = tv.cockpit_3d
	var knob: MeshInstance3D = c3d.find_child("SYM", true, false)
	var at: Vector2 = c3d.camera.unproject_position(knob.global_transform * knob.get_aabb().get_center())
	print("SYM at ", at)
	await _save("sym_rest")
	var hover := InputEventMouseMotion.new()
	hover.position = at
	Input.parse_input_event(hover)
	await frames(10)
	check(knob.material_overlay != null, "the pointer over the wheel lights it")
	await _save("sym_hover")
	for i in 24:
		var e := InputEventMouseButton.new()
		e.position = at
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		Input.parse_input_event(e)
		await process_frame
	hover.position = Vector2.ZERO  # the pointer away: the wheel's turned teeth unlit
	Input.parse_input_event(hover)
	await frames(10)
	print("level ", settings().hud_brightness)
	await _save("sym_turned")
	Engine.time_scale = 1.0
	check(is_equal_approx(settings().hud_brightness, 0.4), "the wheel turned down to 40 %")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join(name + ".png"))
