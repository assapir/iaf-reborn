# Dev helper (not run by tools/test.sh): the Sufa's HUD at a display scale (docs/real-hud.md "Display scale"), a real
# render of mission 2012 started at an --at pose (the look study's Shoham pose below; _sym_wheel_shot.gd's Ramon final
# also works), frozen 3 s after the start, looking ahead:
# SHOT_OUT/hud_scale<SHOT_SCALE>.png. SHOT_SCALE (default 1) is the window's content_scale_factor, as a 2× (Retina)
# display's; give the window that many times the pixels (--resolution) for the same picture.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_SCALE=2 \
#     -- --log-file <t> --resolution 2560x1440 --path modern-iaf -s ../modern-iaf/tests/_hud_scale_shot.gd \
#     -- --at 672750 3537452 240 100 0
extends "res://../tests/godot/base.gd"


func run() -> void:
	var k := float(OS.get_environment("SHOT_SCALE")) if OS.get_environment("SHOT_SCALE") != "" else 1.0
	get_root().content_scale_factor = k
	settings().show_info = false
	settings().hud_brightness = 1.0
	load("res://flight/fly.gd").start(2012)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	tv.gear_down = true
	await create_timer(3.0).timeout
	Engine.time_scale = 0.0
	await frames(30)
	print("window ", get_root().size, " scale ", get_root().content_scale_factor, " canvas ", tv.cockpit.size)
	print("ui_scale ", tv.cockpit.ui_scale(), " focal ", tv.cockpit.focal_length())
	print("final ", get_root().get_final_transform(), " screen ", tv.cockpit.hud.get_screen_transform())
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join("hud_scale%s.png" % OS.get_environment("SHOT_SCALE")))
	Engine.time_scale = 1.0
	check(true, "shot")
