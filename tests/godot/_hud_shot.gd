# Dev helper (not run by tools/test.sh): a real-render capture with the Jet list pick in HUD_JET (-1 = the
# mission's jet), saved to HUD_SHOT once the ground is loaded. Pose with terrain_view's user args, e.g.
#   HUD_JET=3 HUD_SHOT=/tmp/a.png godot --path game -s ../tests/godot/_hud_shot.gd -- --mission 312 --at X Y Z HDG PITCH --gear --freeze
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().jet_id = int(OS.get_environment("HUD_JET")) if OS.get_environment("HUD_JET") != "" else -1
	change_scene_to_file("res://terrain/terrain_view.tscn")
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("HUD_SHOT"))
	print("saved ", OS.get_environment("HUD_SHOT"))
