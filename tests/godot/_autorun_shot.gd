# Dev helper (not run by tools/test.sh): a real-render capture of the CD launcher (game/menu/autorun.gd,
# docs/front-end.md §18.1) saved to AUTORUN_SHOT. AUTORUN_STATE: "start" (PLAY focused, default), "quit" (focus on
# QUIT) or "pressed" (the mouse held down on QUIT), e.g.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 AUTORUN_SHOT=/tmp/a.png -- --log-file /tmp/a.log --path game \
#     --resolution 1280x960 -s ../tests/godot/_autorun_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var a: Control = load("res://menu/autorun.gd").new()
	root.add_child(a)
	await frames(2)
	match OS.get_environment("AUTORUN_STATE"):
		"quit":
			a.focus = a.QUIT
		"pressed":
			var r: Rect2i = a.slot(a.QUIT)
			a._gui_input(mouse_button(a._poster_origin() + Vector2(r.get_center()) * a._scale(), true))
	a.queue_redraw()
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("AUTORUN_SHOT"))
	print("saved ", OS.get_environment("AUTORUN_SHOT"))
