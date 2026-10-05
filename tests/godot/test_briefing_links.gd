# Briefing links (docs/front-end.md §6, §11): every type-2 link (3D model) of every briefing opens the obj_t window at
# (12,16) 415×260 with the model in the left two-thirds and its description on the right; a second one reuses the
# window; the text (type 0: a lesson or a briefing text such as 67.rtf) and picture (type 3) windows open at their rects. SHOT_DIR=dir writes briefing_model.png.
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
				var v = preload("res://menu/model_view.gd").new()
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
