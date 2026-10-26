# Dev helper (not run by tools/test.sh): a real-render capture of the Mission Creator (docs/front-end.md §19) in
# MC_LANG (en / he) after RANDOM, with combo MC_OPEN (an index into mission_creator.gd combos, default none) open,
# saved to MC_SHOT. MC_BETTER=1 turns Extras "Mission Creator: Better" on (the WIND / FROM / WEATHER
# combos, 20 to 22).
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 MC_OPEN=7 MC_SHOT=/tmp/mc.png -- --log-file /tmp/mc.log --path game \
#     --resolution 1280x960 -s ../tests/godot/_mc_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().language = OS.get_environment("MC_LANG") if OS.get_environment("MC_LANG") != "" else "en"
	settings().better_mc = OS.get_environment("MC_BETTER") == "1"
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("MissionCreator"))
	await frames(2)
	while fe.busy:
		await process_frame
	fe.mc_view.button("random")
	settings().mc.notes = "Two MiG-21 sections over Ramon at sunset."
	if OS.get_environment("MC_OPEN") != "":
		fe.mc_view.open = int(OS.get_environment("MC_OPEN"))
		fe.mc_view.current[fe.mc_view.open] = 2
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("MC_SHOT"))
	print("saved %s" % OS.get_environment("MC_SHOT"))
