# Dev helper (not run by tools/test.sh): the front-end TSD of mission 311 with Briefing map Original and Modern (the
# OpenStreetMap map of setup's extras step, docs/front-end.md §8 "Modern map") into SHOT_DIR: tsd_<state>_<zoom>.png,
# the whole theatre (zoom 1) and centred on Israel two zoom steps in.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=$PWD/.shots -- \
#     --log-file /tmp/s.log --path iaf-reborn -s ../tests/godot/_tsd_modern_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	await require_data()
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	settings().mission_id = 311
	for state in ["original", "modern"]:
		settings().briefing_map = state
		var fe = load("res://menu/front_end.tscn").instantiate()
		root.add_child(fe)
		await frames(3)
		fe._reset_tsd_checks()
		fe.screen = "tsd"
		fe._enter_screen()
		await frames(5)
		fe.tsd_checks["briefing"] = false
		fe.tsd.open_briefing(false)
		var tsd = fe.tsd
		for zoom in [1, 3]:
			if zoom == 3:
				tsd.zoom_by(tsd.ZOOM_STEP)
				tsd.zoom_by(tsd.ZOOM_STEP)
				tsd.centre_on(tsd.world_to_map(330000, 560000))  # Israel and the West Bank
			await frames(5)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png(dir.path_join("tsd_%s_%d.png" % [state, zoom]))
			print("tsd %s zoom %d" % [state, zoom])
		fe.queue_free()
		await frames(3)
	settings().briefing_map = "original"
	print("RESULT PASS")
