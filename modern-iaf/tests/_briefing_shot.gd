# Real-render pictures of the mission briefing (modern-iaf/docs/front-end.md §10) in English and Hebrew:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/br [SHOT_SIZE=1280x720] -- --log-file /tmp/br.log \
#     --path modern-iaf -s ../modern-iaf/tests/_briefing_shot.gd
# Writes SHOT_DIR/briefing_<menu id>_<lang>.png (Ramon's start-up 2011 and take-off 2012 as the screen opens),
# briefing_<menu id>_step_<lang>.png (a step opened: its state to wait for, a start-up's switch picture),
# briefing_2012_plain_<lang>.png (the take-off with its labels and photo off), stores_2012_<lang>.png (the loadout
# screen Edit opens) and, per jet, startup_<jet>_<lang>.png (its start-up, its second step opened) and
# stores_<jet>_<lang>.png (the loadout screen of its take-off), at SHOT_SIZE (1920x1080 by default; the front end in a
# viewport of that size, its 1920 × 1080 canvas stretched to it as the window's is).
extends "res://../tests/godot/base.gd"


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
	# The window's canvas scaling (front_end.gd: a 1920 × 1080 canvas stretched to the window), in the viewport.
	vp.size_2d_override = Vector2i(1920, 1080)
	vp.size_2d_override_stretch = true
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	var save := func(name: String) -> void:
		var path := dir.path_join(name + ".png")
		check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		for jet in ["f16i", "f16d", "f35i"]:
			s.sim_jet = jet
			for i in 2:
				fe.mission_i = i
				fe.show_page("mission")
				await frames(12)
				var m: Dictionary = fe.missions[i]
				var id := int(m.menu_id)
				if jet == "f16i":
					save.call("briefing_%d_%s" % [id, lang])
				# A step opened: the take-off's first (its state to wait for), the start-up's second (its switch).
				var step: Control = fe.find_child("Step%d" % (2 if fe.kind(m) == "startup" else 1), true, false)
				step.grab_focus()
				await frames(6)
				if jet == "f16i":
					save.call("briefing_%d_step_%s" % [id, lang])
				if fe.kind(m) == "startup":
					save.call("startup_%s_%s" % [jet, lang])
					continue
				if jet == "f16i":
					fe.find_child("MapLabels", true, false).button_pressed = false
					fe.find_child("MapPhoto", true, false).button_pressed = false
					await frames(4)
					save.call("briefing_%d_plain_%s" % [id, lang])
				fe.show_page("arming")
				await frames(10)
				save.call("stores_%s_%s" % [jet, lang])
				if jet == "f16i":
					save.call("stores_%d_%s" % [id, lang])
	s.language = "en"
	s.pilot_name = ""
