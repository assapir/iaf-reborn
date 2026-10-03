# Dev helper (not run by tools/test.sh): a real-render capture of the On-The-Fly menu (Ctrl+O, item 2 hovered) in
# mission 311, in MENU_LANG (en / he), saved to MENU_SHOT; with MENU_BOX=1 the "End mission" Yes/No box instead.
#   MENU_LANG=he MENU_SHOT=/tmp/m.png IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 -s ../tests/godot/_flymenu_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().language = OS.get_environment("MENU_LANG") if OS.get_environment("MENU_LANG") != "" else "en"
	var tv = await start_mission(311)
	await frames(30)
	var e := InputEventKey.new()
	e.keycode = KEY_O
	e.pressed = true
	e.ctrl_pressed = true
	tv._unhandled_input(e)
	tv.overlay.hover = 1
	await frames(5)
	if OS.get_environment("MENU_BOX") != "":
		tv.menu_choice("end")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("MENU_SHOT"))
	print("saved ", OS.get_environment("MENU_SHOT"))
