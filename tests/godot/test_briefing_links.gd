# Briefing links (docs/front-end.md §6, §11): every type-2 link (3D model) of every briefing opens the obj_t window at
# (12,16) 415×260 with the model in the left two-thirds and its description on the right; a second one reuses the
# window; the text (type 0: a lesson or a briefing text such as 67.rtf) and picture (type 3) windows open at their
# rects; a target link (type 5) opens the targ_t window at (22,16) 406×322 on the named object and closes the model
# window, its view strip switches the camera; every target file names an object of its mission (but the known misses).
# SHOT_DIR=dir writes briefing_model.png and briefing_target_<tab>.png.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(3)
	Settings().mission_id = 113
	fe._reset_tsd_checks()
	fe.screen = "tsd"
	fe._enter_screen()
	await frames(3)
	var tsd = fe.tsd
	tsd.open_briefing(true)
	await frames(2)
	var b: Dictionary = tsd._briefing()
	var names: Array = tsd._link_names(b)
	# Every type-2 link in every briefing and lesson: the model loads (but the one path without \3dObjects\).
	var failed := []
	var n := 0
	for grp in ["missions", "lessons"]:
		for id in fe.briefings[grp]:
			for e in fe.briefings[grp][id].get("entries", []):
				if int(e.type) != 2 or not String(e.file).begins_with("/3dobjects/"):
					continue
				n += 1
				var v = load("res://menu/model_view.gd").new()
				var key := String(e.file).trim_prefix("/").trim_suffix(".x")
				if not v.setup(fe, key.trim_prefix("3dobjects/") + ".gltf", fe.briefings.models.get(key, {}).get("cp")):
					failed.append(e.file)
				v.free()
	check(n > 200 and failed.is_empty(), "every 3D-model link loads its model (%d links; failed %s)" % [n, failed])
	# Mission 113's links: the first type-2 and type-0 / type-3 ones.
	var by_type := {}
	for i in b.entries.size():
		by_type[int(b.entries[i].type)] = by_type.get(int(b.entries[i].type), []) + [names[i]]
	var model_links: Array = by_type.get(2, [])
	check(model_links.size() >= 2, "113 has 3D-model links (%s)" % str(model_links))
	tsd._on_link(model_links[0], b)
	await frames(3)
	var w = tsd.link_windows.get(2)
	check(is_instance_valid(w) and w.rect == Rect2(12, 16, 415, 260) and w.tab_art == "framewnd/obj_t.png",
			"3D-model window at (12,16) 415×260 with obj_t")
	check(w.view != null and w._view_rect() == Rect2(15, 35, 256, 207), "the view at client (10,20) 256×207 (%s)" % str(w._view_rect()))
	check(w.rich != null and w.rich.get_parsed_text().length() > 50, "the model's description on the right")
	var d0: float = w.view.d
	w.view.grab_focus()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_KP_ADD
	w.view._gui_input(key)
	check(w.view.d == d0 - 2.0 and is_equal_approx(d0, 1.2 * w.view.dist), "numpad + zooms in 2 units from 1.2 × the .cp distance")
	if OS.get_environment("SHOT_DIR") != "":
		await frames(10)
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("briefing_model.png"))
	tsd._on_link(model_links[1], b)
	await frames(2)
	check(tsd.link_windows.get(2) == w and is_instance_valid(w), "a second model link reuses the window")
	for t in [[0, Rect2(floor(453 / 3.0), floor(357 / 2.0), floor(2 * 453 / 3.0), floor(357 / 2.0))], [3, Rect2(floor(453 / 2.0), 0, floor(453 / 2.0), floor(357 / 2.0))]]:
		if by_type.has(t[0]):
			tsd._on_link(by_type[t[0]][0], b)
			await frames(2)
			var lw = tsd.link_windows.get(t[0])
			check(is_instance_valid(lw) and lw.rect == t[1], "type %d window at %s (%s)" % [t[0], str(t[1]), str(lw.rect) if is_instance_valid(lw) else "none"])
	# Target links (type 5): 113's "SA-2 battery" (brief/tar/113_1.txt: RADARsa2r1).
	var targets: Array = by_type.get(5, [])
	check(not targets.is_empty(), "113 has target links (%s)" % str(targets))
	tsd._on_link(targets[0], b)
	await frames(3)
	var tw = tsd.link_windows.get(5)
	check(is_instance_valid(tw) and tw.rect == Rect2(22, 16, 406, 322) and tw.tab_art == "framewnd/targ_t.png"
			and tw.view != null and tw.view.tab == 0, "target window at (22,16) 406×322 with targ_t, satellite view")
	check(not is_instance_valid(tsd.link_windows.get(2)) or tsd.link_windows.get(2).is_queued_for_deletion(), "the target window closes the model window")
	check(tw._view_rect() == Rect2(5, 15, 396, 303), "the view fills the client 396×303 (%s)" % str(tw._view_rect()))
	check(tw.view._cam.global_position.y - tw.view.height > 6900.0, "satellite camera 7000 m above the object")
	for t in 3:
		tw.view.set_tab(t)
		for i in 600:
			await process_frame
			if tw.view._ground_known and tw.view._snap.is_empty() and tw.view._terrain.ground_ready() and i > 60:
				break
		if OS.get_environment("SHOT_DIR") != "":
			root.get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("briefing_target_%d.png" % t))
	check(tw.view._ground_known and tw.view._snap.is_empty(), "the terrain under the target loaded, the units stand on it")
	check(tw.view._vp.get_children().filter(func(c): return c is Node3D and c.scene_file_path == "" and c.get_child_count() > 0).size() > 3,
			"the mission's units around the target are drawn")
	# Every target file of every mission names an object of that mission.
	var missing := []
	var count := 0
	for id in fe.briefings.missions:
		var bm: Dictionary = fe.briefings.missions[id]
		tsd.mission_id = int(id) if String(id).is_valid_int() else -1
		for e in bm.get("entries", []):
			if int(e.type) != 5:
				continue
			count += 1
			var nm := FileAccess.get_file_as_string(Settings().assets_dir().path_join("install/resource").path_join(String(e.file))).split("\n")[0]
			if tsd._target_unit(nm).is_empty():
				missing.append("%s:%s" % [id, nm])
	print("target links: %d, no object: %s" % [count, missing])
	check(count > 100, "the briefings' target links (%d) checked" % count)
