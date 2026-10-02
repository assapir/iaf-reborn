# Dev helper (not run by tools/test.sh): a real-render capture of the credits roll (game/menu/credits_roll.gd)
# with our lines' first line CREDITS_Y px below the top (default 40), saved to CREDITS_SHOT, e.g.
#   CREDITS_LANG=he CREDITS_SHOT=/tmp/c.png godot --path game -s ../tests/godot/_credits_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().language = OS.get_environment("CREDITS_LANG") if OS.get_environment("CREDITS_LANG") != "" else "en"
	var Roll = load("res://menu/credits_roll.gd")
	var roll = Roll.new()
	root.add_child(roll)
	await frames(1)
	var y := float(OS.get_environment("CREDITS_Y")) if OS.get_environment("CREDITS_Y") != "" else 40.0
	roll.t_ms = (Roll.START_Y + roll.runs[roll.ours].y - y) * Roll.MS_PER_PX
	roll.set_process(false)
	roll.update()
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("CREDITS_SHOT"))
	print("saved ", OS.get_environment("CREDITS_SHOT"))
