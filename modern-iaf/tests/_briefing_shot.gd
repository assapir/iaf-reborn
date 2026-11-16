# Real-render pictures of the mission briefing (modern-iaf/docs/front-end.md §10) in English and Hebrew:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/br [SHOT_SIZE=1280x720] -- --log-file /tmp/br.log \
#     --path modern-iaf -s ../modern-iaf/tests/_briefing_shot.gd
# Writes SHOT_DIR/briefing_<menu id>_<lang>.png (Ramon's start-up 2011 and take-off 2012 as the screen opens),
# briefing_<menu id>_text_<lang>.png (the explanation focused and scrolled by the keys: a start-up's switch pictures),
# briefing_2012_plain_<lang>.png (the take-off with its labels and photo off), briefing_2012_reset_<lang>.png (the
# mission's area, as a double click or 0 shows it), briefing_2012_theatre_<lang>.png (zoomed
# out to the whole theatre), briefing_2012_far_<lang>.png and briefing_2012_far_close_<lang>.png (the theatre's middle,
# about 100 km north of Ramon, at 2× and 24× the mission's area) and, per jet, startup_<jet>_<lang>.png (its start-up,
# the explanation scrolled), briefing_two_flights[_bravo]_<lang>.png (the two-flight sample
# modern-iaf/tests/data/two_flights.json, Alpha then Bravo picked), at SHOT_SIZE (1920x1080 by default; the front end in
# a viewport of that size, its 1920 × 1080 canvas stretched to it as the window's is).
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
				# The explanation with the focus, scrolled down by the keys to its middle (a start-up's switch pictures).
				var how: ScrollContainer = fe.find_child("HowScroll", true, false)
				how.grab_focus()
				for n in 4:
					how.gui_input.emit(_key(KEY_DOWN))
				await frames(6)
				if jet == "f16i":
					save.call("briefing_%d_text_%s" % [id, lang])
				if fe.kind(m) == "startup":
					save.call("startup_%s_%s" % [jet, lang])
					continue
				if jet == "f16i":
					await _views(fe, save, lang)
					fe.find_child("MapLabels", true, false).button_pressed = false
					fe.find_child("MapPhoto", true, false).button_pressed = false
					await frames(4)
					save.call("briefing_%d_plain_%s" % [id, lang])
		# The two-flight sample (test data): Alpha picked, then Bravo.
		var two: Dictionary = s.load_json("res://tests/data/two_flights.json")
		two["_file"] = "res://tests/data/two_flights.json"
		s.sim_jet = "f16i"
		fe.missions = [two]
		fe.mission_i = 0
		fe.show_page("mission")
		await frames(12)
		save.call("briefing_two_flights_%s" % lang)
		fe.find_child("Flight_Bravo", true, false).button_pressed = true
		await frames(4)
		save.call("briefing_two_flights_bravo_%s" % lang)
		fe.show_page("section")  # the section's own list again
	s.language = "en"
	s.pilot_name = ""


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	return e


## The take-off's map at the reset (the mission's area), zoomed out to the theatre, then far from the base at two zooms,
## each once its tiles are in.
func _views(fe: Control, save: Callable, lang: String) -> void:
	var map: Control = fe.find_child("PageMap", true, false)
	var c0: Vector2 = map.center
	var z0: float = map.zoom
	map.reset_view()
	await _settled(map)
	save.call("briefing_2012_reset_%s" % lang)
	for v in [
		["theatre", Vector2.INF, 0.0], ["far", map._bounds().get_center(), 2.0], ["far_close", Vector2.INF, 24.0]
	]:
		if v[1] != Vector2.INF:
			map.center = v[1]
		map.zoom = maxf(v[2], map._zoom_min())
		map._clamp()
		await _settled(map)
		save.call("briefing_2012_%s_%s" % [v[0], lang])
	map.center = c0
	map.zoom = z0
	map._clamp()


## Once the view's tiles are in.
func _settled(map: Control) -> void:
	for i in 600:
		await frames(1)
		if not map._view_dirty and map._want.is_empty() and map._jobs.is_empty():
			break
	await frames(3)
