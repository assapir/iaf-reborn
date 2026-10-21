# Dev helper (not run by tools/test.sh): a real-render capture of the mission editor on a fork of 512 Wild West, an
# SA-6 put in the sea (its red ring), zoomed in on Alpha, saved to ED_SHOT. The fork lives in user://missions_shot
# and is removed after.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 ED_SHOT=/tmp/ed.png -- --log-file /tmp/ed.log --path game \
#     --resolution 1600x1000 -s ../tests/godot/_mission_editor_shot.gd
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_shot"


func run() -> void:
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.add_child(ed)
	await frames(3)
	ed.open_original(512)
	ed.fork("Wild West 2")
	ed.add_unit(6, 376500, 451500, 2, 1)
	ed.tsd.select_flight(1)
	ed.tsd.zoom_by(ed.tsd.ZOOM_STEP)
	ed.tsd.zoom_by(ed.tsd.ZOOM_STEP)
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("ED_SHOT"))
	print("saved %s" % OS.get_environment("ED_SHOT"))
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)
