# Dev helper (not run by tools/test.sh): a real-render capture of a Preferences page (PREF_PAGE: the tab's label,
# e.g. Devices, Extras, Physics, or Graphics+ for the Graphics page's MORE view; default Devices) in PREF_LANG (en /
# he), saved to PREF_SHOT; prints the labels that have no Hebrew text. PREF_ROW=<setting key> scrolls to that row.
#   PREF_PAGE=Devices PREF_LANG=he PREF_SHOT=/tmp/p.png IAF_DEFAULT_SETTINGS=1 godot --path game --resolution \
#     1920x1080 -s ../tests/godot/_prefs_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().language = OS.get_environment("PREF_LANG") if OS.get_environment("PREF_LANG") != "" else "en"
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
	# Our tabs answer to their lower-case keys; "Graphics+" is the Graphics page's MORE view.
	if page in ["Extras", "Physics"]:
		fe._on_button(page.to_lower())
	else:
		fe._on_button(fe._key_for_label("Graphics" if page == "Graphics+" else page))
	if page == "Graphics+":
		await frames(2)
		fe._pref_press(fe.PREF_MORE.get_center())
	# PREF_ROW=<setting key>: scrolled so that row is in view (e.g. scenery).
	if OS.get_environment("PREF_ROW") != "":
		await frames(2)
		var keys: Array = fe._extras_rows().map(func(r): return r[0])
		fe._extras_scroll(mini(keys.find(OS.get_environment("PREF_ROW")), fe._extras_max_top()))
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("PREF_SHOT"))
	print("saved %s; labels without Hebrew: %s" % [OS.get_environment("PREF_SHOT"), fe.missing_he.keys()])
