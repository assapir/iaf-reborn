# Dev helper (not run by tools/test.sh): a real-render capture of a Preferences page (PREF_PAGE: the tab's label,
# e.g. Devices, Extras, Physics; default Devices) in PREF_LANG (en / he), saved to PREF_SHOT; prints the labels
# that have no Hebrew text.
#   PREF_PAGE=Devices PREF_LANG=he PREF_SHOT=/tmp/p.png IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1920x1080 -s ../tests/godot/_prefs_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	Settings().language = OS.get_environment("PREF_LANG") if OS.get_environment("PREF_LANG") != "" else "en"
	var page := OS.get_environment("PREF_PAGE") if OS.get_environment("PREF_PAGE") != "" else "Devices"
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "main"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Preferences"))
	await frames(2)
	while fe.busy:
		await process_frame
	fe._on_button(fe._key_for_label(page))
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("PREF_SHOT"))
	print("saved %s; labels without Hebrew: %s" % [OS.get_environment("PREF_SHOT"), fe.missing_he.keys()])
