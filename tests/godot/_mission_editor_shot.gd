# Dev helper (not run by tools/test.sh): a real-render capture of the mission editor on a fork of 512 Wild West, an
# SA-6 put in the sea (its red ring), zoomed in on Alpha, saved to ED_SHOT. The fork lives in user://missions_shot
# and is removed after.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 ED_SHOT=/tmp/ed.png -- --log-file /tmp/ed.log --path game \
#     --resolution 1600x1000 -s ../tests/godot/_mission_editor_shot.gd
# ED_SCENERY=menu: zoomed in on a town of the scenery (docs/scenery.md §5) with a building picked and its Set as target
# menu open; ED_SCENERY=target: that building set as a target (its marker selected). ED_TAB=<title>: that side tab
# shown (e.g. Mission: the wind and weather rows). ED_MAP=original|modern: that Extras "Briefing map", the whole
# map from Cairo to Damascus shown, no zoom.
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_shot"
const TOWN := Vector2(325000, 544300)  # the densest scenery cell's centre


func run() -> void:
	var map := OS.get_environment("ED_MAP")
	if map != "":
		settings().briefing_map = map
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.add_child(ed)
	await frames(3)
	ed.open_original(512)
	ed.fork("Wild West 2")
	ed.add_unit(6, 376500, 451500, 2, 1)
	ed.tsd.select_flight(1)
	if map != "":
		ed.tsd.selected = -1
		ed.tsd.zoom_by(0.01)
		ed.tsd.centre_on(Vector2(240, 300))
	else:
		ed.tsd.zoom_by(ed.tsd.ZOOM_STEP)
		ed.tsd.zoom_by(ed.tsd.ZOOM_STEP)
	var scenery := OS.get_environment("ED_SCENERY")
	if scenery != "":
		ed.tsd.selected = -1
		ed.tsd.zoom = 547.0
		ed.tsd.centre_on(ed.Tsd.world_to_map(TOWN.x, TOWN.y))
		ed.sel_building = ed.pick_building(TOWN.x, TOWN.y)
		var b: Dictionary = ed.sel_building
		print("picked %s" % b)
		if scenery == "target":
			ed.set_scenery_target(b.at.x, b.at.y, b.r)
		await frames(5)
		if scenery == "menu":
			ed._offer_building()
			var c: Vector2 = ed.tsd._to_client(ed.Tsd.world_to_map(b.at.x, b.at.y))
			ed._ui.building_menu.position = Vector2i(
				ed.host.global_position + ed.host._to_screen(ed.tsd.area.position + c)
			)
	var tab := OS.get_environment("ED_TAB")
	if tab != "":
		var tabs: TabContainer = ed.find_children("*", "TabContainer", true, false)[0]
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == tab:
				tabs.current_tab = i
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("ED_SHOT"))
	print("saved %s" % OS.get_environment("ED_SHOT"))
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)
