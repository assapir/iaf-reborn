# Dev helper (not run by tools/test.sh): the start-up checklist card and the end banner in a real render
# (modern-iaf/docs/training.md §7.1, §9), English and Hebrew: the card at the start (the start-up call in the band),
# mid-sequence and done, the "Mission complete" banner, and a step out of order (the JFS before the main power) with
# its Fail banner.
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOW_OUT=<dir> -- --log-file <temp> --display-driver x11 --resolution 1920x1080 --path modern-iaf \
#     -s ../modern-iaf/tests/_checklist_shot.gd
extends "res://tests/test_mvp.gd"

var shots := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	shots = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("iaf2026-shots-%d" % OS.get_process_id())
	settings().show_info = false
	var tv := await _start("ramon_startup")
	Engine.time_scale = 1.0
	await fly(tv, 2.0)
	tv.addon.pick("startup")  # the start-up call: a line in the band (front-end.md §8)
	await fly(tv, 0.5)
	await _both(tv, "card_start")
	tv._command([210, 0, 0])
	tv._command([211, 0, 0])
	await fly(tv, 1.0)
	await _both(tv, "card_mid")
	Engine.time_scale = TIME_SCALE
	await _until(tv, func(): return float(tv.flight.state().rpm) >= 0.2, 60.0)
	tv._command([5, 0, 0])  # the throttle up from OFF: the idle step
	await _until(tv, func(): return float(tv.flight.state().rpm) >= 0.55, 60.0)
	for c in [213, 214, 215]:
		tv._command([c, 0, 0])
	await _until(tv, func(): return tv.addon._pass_at < INF, 200.0)
	Engine.time_scale = 1.0
	await _both(tv, "card_done")
	# A step out of order: the JFS before the main power.
	tv = await _start("ramon_startup")
	Engine.time_scale = 1.0
	await fly(tv, 2.0)
	tv._command([211, 0, 0])
	await frames(5)
	await _both(tv, "card_fault")


## The view in English and in Hebrew (the card and the banner rebuilt in each).
func _both(tv: Node, name: String) -> void:
	for lang in ["en", "he"]:
		settings().language = lang
		tv.addon._fill_card()
		var d: Dictionary = tv.addon.result
		if tv.addon._pass_at < INF and d.is_empty() or bool(d.get("pass", false)):
			tv.addon._show_banner(tv.addon.COMPLETE[lang], "")
		elif not d.is_empty():
			var s: Dictionary = d.strings[lang]
			tv.addon._show_banner(String(s.fail), String(s.get(d.reasons[0], "")))
		await frames(3)
		await RenderingServer.frame_post_draw
		var p := shots.path_join("%s_%s.png" % [name, lang])
		root.get_texture().get_image().save_png(p)
		print("shot ", p)
	settings().language = "en"
