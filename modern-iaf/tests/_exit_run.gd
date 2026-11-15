# The child of test_exit.gd: the player's path through the front end, then the game's own quit (Settings.quit, the
# Quit button's and the window's close). `-- --exit-at front|mission|flight`: quit on the Hangar, on the mission page
# (the ground preloading) or in the flight (paused). Prints EXIT_QUIT when it asks to quit.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/_exit_run.gd --log-file <temp> -- --exit-at flight
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args[args.find("--exit-at") + 1] if args.has("--exit-at") else "front"
	await process_frame
	var s: Node = root.get_node("Settings")
	if args.has("--pilot"):  # a pilot with flights (the player's state), else the first start's Pilot screen
		load("res://tests/test_front_end.gd").fixture(s)
	s.sim_jet = "f16i"
	change_scene_to_file("res://main.tscn")
	for i in 5:
		await process_frame
	var fe: Node = current_scene
	if at != "front":
		fe.show_page("mission")
		var tp: GDScript = load("res://shared/terrain/terrain_preload.gd")
		var end := Time.get_ticks_msec() + 60000  # the flight scene loaded and its first frame's art prefetched
		while not tp.ready_to_fly() and Time.get_ticks_msec() < end:
			await process_frame
	if at == "flight":
		fe.fly_mission(fe.missions[fe.mission_i])
		var end := Time.get_ticks_msec() + 120000
		while Time.get_ticks_msec() < end:
			var tv: Node = current_scene
			if tv != null and tv.name == "TerrainView" and tv.get("flight") != null and not tv.waiting_for_ground:
				break
			await process_frame
		for i in 30:
			await process_frame
		paused = true
	# A node out of the tree and not about to be freed (a page's old nodes wait for their queue_free) leaks at exit.
	for id in Node.get_orphan_node_ids():
		var n = instance_from_id(id)
		if n == null:
			continue
		var top = n
		while top.get_parent() != null:
			top = top.get_parent()
		if top.is_queued_for_deletion():
			continue
		print(
			"ORPHAN %s %s %s parent=%s text=%s" % [n.get_class(), n.name, n.get_script(), n.get_parent(), n.get("text")]
		)
	print("EXIT_QUIT %s" % at)
	s.quit()
