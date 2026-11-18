# Dev helper (not run by tools/test.sh): the Sufa's 3D cockpit, real renders of the head looking about
# (modern-iaf/docs/cockpit.md §2, §5.2, §5.3), airborne on Ramon's final (the --at start of _ils_shot.gd: the HUD on):
# SHOT_OUT/dash_hud.png (looking down-left at the dash, the HUD's symbols on the combiner glass) and hands.png (looking
# down at the hands on the stick and the throttle).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_cockpit_look_shot.gd \
#     -- --at 666059.3 3409044.1 1179.1 246.0 -3
# SHOT_THROTTLE=<0-1>: the throttle set first (the left glove follows its grip: tools/f16d/pilot.py).
extends "res://../tests/godot/base.gd"

## Each picture's head (yaw right +, pitch up +, rad).
const SHOTS := {
	"dash_hud": Vector2(-0.3, -0.3),
	"hands": Vector2(-0.2, -0.8),
}


func run() -> void:
	settings().show_info = false
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	if OS.get_environment("SHOT_THROTTLE") != "":
		tv.throttle = float(OS.get_environment("SHOT_THROTTLE"))
		tv._throttle_event()
	await create_timer(3.0).timeout
	for name in SHOTS:
		tv.views.snap = SHOTS[name]
		await create_timer(0.5).timeout
		await _save(name)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join(name + ".png"))
