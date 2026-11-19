# Real-render pictures of the briefing's PRE targets panel (A61, modern-iaf/docs/front-end.md §10.2), English and
# Hebrew: the F-35I on Nevatim's weapons range with four GBU-39 on station 4 and a GBU-31 on station 8; station 4 on
# Target 2, its bomb 4-4 on a point of the map, station 8 on Target 3, bomb 4-3 armed.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/pre [SHOT_SIZE=1280x720] -- --log-file /tmp/pre.log \
#     --path modern-iaf -s ../modern-iaf/tests/_pre_targets_shot.gd
# Writes SHOT_DIR/pre_targets_<lang>.png.
extends "res://../tests/godot/base.gd"

const LOAD := '{"4": {"id": "gbu-39", "count": 4}, "8": {"id": "gbu-31", "count": 1}, "5": "aim-120", "7": "aim-120"}'


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var wh := OS.get_environment("SHOT_SIZE").split("x")
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(wh[0]), int(wh[1])) if wh.size() == 2 else Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size_2d_override = Vector2i(1920, 1080)
	vp.size_2d_override_stretch = true
	root.add_child(vp)
	s.sim_jet = "f35i"
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		fe.section = "training"
		fe.show_page("section")
		await frames(2)
		var i: int = fe.missions.map(func(m): return str(m.id)).find("nevatim_range")
		var m: Dictionary = fe.missions[i]
		var unit: String = fe._unit_file(m)
		var wdir := ProjectSettings.globalize_path("res://data/db/weapons")
		var mis: String = fe.mission_file(m)
		var pre: Dictionary = JSON.parse_string(IafBriefing.pre(unit, wdir, LOAD, mis))
		var t2: Dictionary = pre.aims[1]
		var lo: String = IafBriefing.pre_set(unit, wdir, LOAD, mis, 4, -1, '{"target": 2}')
		lo = IafBriefing.pre_set(unit, wdir, lo, mis, 8, -1, '{"target": 3}')
		var pt := JSON.stringify({"x": float(t2.x) + 600.0, "y": float(t2.y) - 900.0})
		lo = IafBriefing.pre_set(unit, wdir, lo, mis, 4, 3, pt)
		IafPilotLog.set_loadout(s.records_db(), s.pilot(), "f35i", lo)
		fe.open_mission(i)
		await frames(3)
		var chip := fe.find_child("MapPre", true, false) as Button
		chip.button_pressed = true
		await frames(2)
		(fe.find_child("PreRow_4_3", true, false) as Button).pressed.emit()
		await frames(2)
		for k in 90:  # the ground's tiles
			await process_frame
		var path := dir.path_join("pre_targets_%s.png" % lang)
		check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
	IafPilotLog.set_loadout(s.records_db(), s.pilot(), "f35i", "")
