# Dev helper (not run by tools/test.sh): a real-render capture of the mission editor on a fork of 512 Wild West, an
# SA-6 put in the sea (its red ring), zoomed in on Alpha, saved to ED_SHOT. The fork lives in user://missions_shot
# and is removed after.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 ED_SHOT=/tmp/ed.png -- --log-file /tmp/ed.log --path game \
#     --resolution 1600x1000 -s ../tests/godot/_mission_editor_shot.gd
# ED_SCENERY=menu: zoomed in on a town of the scenery (docs/scenery.md §5) with a building picked and its Set as target
# menu open; ED_SCENERY=target: that building set as a target (its marker selected). ED_TAB=<title>: that side tab
# shown (e.g. Mission: the wind and weather rows). ED_MAP=original|modern: that Extras "Briefing map", the whole
# map from Cairo to Damascus shown, no zoom; with ED_ZOOM=<zoom> and ED_AT=<x>,<y> (engine metres) that zoom centred
# there instead (e.g. ED_ZOOM=12 ED_AT=334000,526900: Tel Aviv to Jerusalem, the roads of docs/front-end.md §8).
# ED_ROUTE=given: a convoy at Tel Aviv given a route to Jerusalem with Follow roads (selected: its route drawn);
# ED_ROUTE=draw: the route being drawn, a click at Tel Aviv and one at Latrun, the mouse at Jerusalem.
# ED_ROUTE_AB=<x0>,<y0>,<x1>,<y1>: that route's ends instead (e.g. 318500,545000,321500,541000: across Tel Aviv).
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
		if OS.get_environment("ED_ZOOM") != "":
			var at := OS.get_environment("ED_AT").split_floats(",")
			ed.tsd.zoom = float(OS.get_environment("ED_ZOOM"))
			ed.tsd.centre_on(ed.Tsd.world_to_map(at[0], at[1]))
	else:
		ed.tsd.zoom_by(ed.tsd.ZOOM_STEP)
		ed.tsd.zoom_by(ed.tsd.ZOOM_STEP)
	var route := OS.get_environment("ED_ROUTE")
	if route != "":
		_route(ed, route)
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


func _route(ed, how: String) -> void:
	var a := Vector2(317000, 541300)
	var b := Vector2(352900, 511300)
	if OS.get_environment("ED_ROUTE_AB") != "":
		var ab := OS.get_environment("ED_ROUTE_AB").split_floats(",")
		a = Vector2(ab[0], ab[1])
		b = Vector2(ab[2], ab[3])
	var id: int = ed.add_unit(10, a.x, a.y, 2, 2)
	for i in ed._ui.units.item_count:
		if int(ed._ui.units.get_item_metadata(i)) == id:
			ed._ui.units.select(i)
	ed._set_mode("route")
	ed._on_map_clicked(ed.Tsd.world_to_map(a.x, a.y))
	if how == "draw":
		ed._on_map_clicked(ed.Tsd.world_to_map(334500, 525800))
		ed.hover_at((ed.Tsd.world_to_map(b.x, b.y) - ed.tsd.scroll) * ed.tsd.zoom)
		ed._road_ghost()
	else:
		ed._on_map_clicked(ed.Tsd.world_to_map(b.x, b.y))
		ed.apply_route()
