# Dev helper (not run by tools/test.sh): the radio menu in the four-ship lesson (ramon_four_ship, ai-plan.md F5) in a
# real render, English then Hebrew: the first page (the tower's calls, then the flight's addressees), the flight's
# commands, the formation's shapes and the element's commands; a page the build has not is skipped (the "before").
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOW_OUT=<dir> -- --log-file <temp> --display-driver x11 --resolution 1920x1080 --path modern-iaf \
#     -s ../modern-iaf/tests/_radio_menu_shot.gd
extends "res://tests/_training_shot.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	shots = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-shots-%d" % OS.get_process_id())
	settings().show_info = false
	var tv := await _start("ramon_four_ship")
	Engine.time_scale = 1.0
	_cockpit(tv, Vector2.ZERO)
	await fly(tv, 3.0)
	for lang in ["en", "he"]:
		settings().language = lang
		await _pages(tv, lang)
	settings().language = "en"


## Each page of the menu, opened as the keys do (sim_flight.gd choose).
func _pages(tv: Node, lang: String) -> void:
	for path in [
		[], ["m:tower"], ["m:wingmen"], ["m:wingmen", "to:0"], ["m:wingmen", "to:0", "formation"], ["m:wingmen", "to:5"]
	]:
		tv.addon.set_open(true)
		var ok := true
		for id in path:
			var i: int = tv.addon.shown.find(id)
			ok = ok and i >= 0
			if ok:
				tv.addon.choose(i + 1)
		if ok and tv.addon.open:
			await fly(tv, 0.5)
			await _shot("radio_%s_%s" % ["_".join(["top"] + path).replace("m:", "").replace(":", ""), lang])
		tv.addon.set_open(false)
