# Real-render pictures of the mission briefing (modern-iaf/docs/front-end.md §10), Ramon's two missions in English and
# Hebrew:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/br -- --log-file /tmp/br.log --path modern-iaf \
#     -s ../modern-iaf/tests/_briefing_shot.gd
# Writes SHOT_DIR/briefing_<menu id>_<lang>.png, map_<menu id>_<lang>.png and stores_<menu id>_<lang>.png (the three
# pages), map_zoom_<menu id>_<lang>.png (the map zoomed in on the start) and stores_<jet>_<lang>.png (each jet's
# Arming page at the take-off from its own base) at 1920×1080 (the front end in a viewport
# of that size).
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		s.sim_jet = "f16i"
		for i in 2:
			for tab in 4:
				fe.mission_i = i
				fe.brief_tab = mini(tab, 1) if tab == 3 else tab
				fe.show_page("mission")
				await frames(10)
				if tab == 3:
					# Zoomed in around the start: the base close up.
					var map: Control = fe.find_child("PageMap", true, false)
					var at: Vector2 = map._xf() * Vector2(float(map.data.start[0]), float(map.data.start[1]))
					for n in 12:
						map.zoom_at(map.ZOOM_STEP, at)
					await frames(5)
				var what: String = ["briefing", "map", "stores", "map_zoom"][tab]
				var path: String = dir.path_join("%s_%d_%s.png" % [what, 2011 + i, lang])
				check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
		# Each jet's Arming page at the take-off from its own base: stores_<jet>_<lang>.png.
		for jet in ["f16i", "f16d", "f35i"]:
			s.sim_jet = jet
			fe.brief_tab = 2
			fe.show_page("mission")
			fe.mission_i = fe.missions.map(func(x): return str(x.get("id", "")).ends_with("_takeoff")).find(true)
			fe.show_page("mission")
			await frames(10)
			var jet_path: String = dir.path_join("stores_%s_%s.png" % [jet, lang])
			check(vp.get_texture().get_image().save_png(jet_path) == OK, "saved " + jet_path)
	s.language = "en"
	s.pilot_name = ""
