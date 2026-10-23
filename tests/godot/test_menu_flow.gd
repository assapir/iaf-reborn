# Menu flow: Basic -> Takeoff -> Jet (F-16) -> TSD with Alpha selected; dragging waypoint 1 changes
# the route handed to the flight; double-clicking the flight leader flies.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "basic"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Takeoff"))
	await frames(90)
	check(fe.screen == "jet", "Takeoff -> Jet list")
	check(settings().mission_id == 311, "mission 311 selected")
	check(fe._button_enabled("Mirage") and fe._button_enabled("F16"), "the Jet list jets are enabled (all seven fly)")
	fe._on_button(fe._key_for_label("F16"))
	await frames(90)
	check(fe.screen == "tsd" and fe.tsd != null, "F-16 -> TSD")
	check(fe._selected_flight() == "alpha", "player's flight (Alpha) selected")
	var tsd = fe.tsd
	tsd.open_briefing(false)
	var wp: Vector2 = tsd.flights[1].points[0]
	var before: Vector2 = tsd.map_to_world(wp)
	check(before.distance_to(Vector2(347870, 602383)) < 5.0, "waypoint 1 at the mission's Departure point")
	# At zoom 1 waypoint 1 lies inside the leader's icon, and a press on an icon selects the unit (FUN_00501e50):
	# zoom in until they part.
	var at: Vector2 = fe._to_screen(tsd.CLIENT.position + tsd._to_client(wp))
	tsd._gui_input(mouse_button(at, true))
	tsd._gui_input(mouse_button(at, false))
	check(tsd.drag_wp < 0 and tsd.selected == tsd.flights[1].leader, "a press on the leader's icon selects it, no drag")
	for i in 4:
		tsd.zoom_by(tsd.ZOOM_STEP)
	at = fe._to_screen(tsd.CLIENT.position + tsd._to_client(wp))
	tsd._gui_input(mouse_button(at, true))
	var mv := InputEventMouseMotion.new()
	mv.position = at + Vector2(10, 0) * fe._scale()
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	tsd._gui_input(mv)
	tsd._gui_input(mouse_button(mv.position, false))
	check(tsd.selected_route()[0].x > before.x + 1000.0, "waypoint drag moves the route east")
	# The press off the icons cleared the selection; Alpha selects its leader again, which the hit test tries first
	# (the runway's icon under it is a later record, found first otherwise).
	check(tsd.selected == -1, "a press off the icons clears the selection")
	tsd.select_flight(1)
	var leader: Vector2 = fe._to_screen(tsd.CLIENT.position + tsd._to_client(tsd.units[tsd.flights[1].leader].pos))
	tsd._gui_input(mouse_button(leader, true, true))
	# Fly waits for the flight scene's threaded load and its first frame's art (terrain_preload.gd ready_to_fly).
	for i in 3000:
		if current_scene != null and current_scene.name == "TerrainView":
			break
		await process_frame
	await frames(30)
	check(current_scene != null and current_scene.name == "TerrainView", "double-click on the leader flies")
	check(settings().route_override.size() == 1, "dragged route handed to the flight")
