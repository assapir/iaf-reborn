# Dev helper (not run by tools/test.sh): the pilot's checklist notebook in a real render (modern-iaf/docs/training.md
# §11): stowed on the right thigh, raised in English and Hebrew, the training ring with the board slid off it, the
# edge pointer, the RADIO page, the page control (a section's second page, else the last page) and the first
# start-up's help line, the GUIDE tab at its first picture (guide_en, guide_he). NB_SHOTS picks some (comma-separated
# names).
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 900 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOW_OUT=<dir> [NB_SHOTS=raised_en,radio] [NB_SIZE=2560x1440] -- --log-file <temp> --display-driver x11 \
#     --path modern-iaf -s ../modern-iaf/tests/_notebook_shot.gd
extends "res://tests/test_mvp.gd"

var shots := ""
var only := []


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	shots = OS.get_environment("SHOW_OUT")
	# NB_SIZE (e.g. 2560x1440): the picture's size whatever the window's (the screen's panels cut a 1080-high window):
	# the root viewport drawn at that size and stretched into the window.
	var size := OS.get_environment("NB_SIZE").split("x")
	if size.size() == 2:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(int(size[0]), int(size[1]))
	only = Array(OS.get_environment("NB_SHOTS").split(",", false))
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("iaf2026-shots-%d" % OS.get_process_id())
	settings().show_info = false
	var tv := await _start("ramon_startup")
	Engine.time_scale = 1.0
	await fly(tv, 2.0)
	var kb: Node = tv.addon.kneeboard
	if kb._help != null:  # the first start-up's help line only in its own picture
		kb._help.queue_free()
		kb._help = null
	if OS.get_environment("NB_BENCH") != "":
		await _bench(tv, kb)
		return
	if _want("first_training"):
		kb._help_line()
		await _shot("first_training")
		kb._help.queue_free()
		kb._help = null
	tv._command([210, 0, 0])
	tv._command([211, 0, 0])
	await fly(tv, 0.5)
	# The training ring on the RPM gauge, the board slid down off it, the throttle below the view: its pointer.
	if _want("training"):
		tv.views.snap = Vector2(-0.22, -0.4)
		await fly(tv, 1.5)
		await _shot("training")
	if _want("edge"):
		tv.views.snap = Vector2(0.9, 0.15)
		await fly(tv, 1.5)
		await _shot("edge")
	tv.views.snap = Vector2.ZERO
	Engine.time_scale = TIME_SCALE
	await _until(tv, func(): return float(tv.flight.state().rpm) >= 0.2, 60.0)
	tv._command([5, 0, 0])  # the throttle up from OFF: the idle step
	await _until(tv, func(): return float(tv.flight.state().rpm) >= 0.55, 60.0)
	tv._command([213, 0, 0])
	Engine.time_scale = 1.0
	await fly(tv, 4.0)
	for lang in ["en", "he"]:
		if _want("raised_" + lang):
			settings().language = lang
			await fly(tv, 0.3)
			await _shot("raised_" + lang)
	settings().language = "en"
	await fly(tv, 0.3)
	if _want("radio"):
		kb.board.open("radio")
		await _shot("radio")
		kb.board.open("startup", kb._current())
	# The page control: the first section with more than one page, at its second page (‹ and › both live).
	if _want("pages"):
		for sec in kb.board.sections:
			kb.board.open(String(sec.id))
			if kb.board.page_count() > 1:
				kb.board.turn(1)
				break
		await fly(tv, 0.3)
		await _shot("pages")
		kb.board.open("startup", kb._current())
	# The GUIDE tab at the guide's first picture, in both languages.
	for lang in ["en", "he"]:
		if _want("guide_" + lang):
			settings().language = lang
			await fly(tv, 0.3)
			var blocks: Array = kb.guide_section().blocks
			var pic := blocks.find_custom(func(b): return b is Dictionary)
			kb.board.open("guide", maxi(pic, 0))
			await fly(tv, 0.3)
			await _shot("guide_" + lang)
			kb.board.open("startup", kb._current())
	settings().language = "en"
	await fly(tv, 0.3)
	if _want("stowed"):
		kb.set_raised(false)
		tv.views.snap = Vector2(-0.15, -1.05)
		await fly(tv, 1.5)
		await _shot("stowed")


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func _shot(name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := shots.path_join("build_%s_%d.png" % [name, img.get_height()])
	img.save_png(p)
	print("shot ", p)


## NB_BENCH=1: the notebook's cost per frame: its script (kneeboard.gd _process, timed alone, BENCH_N calls) and the
## GPU's render time of the window and the cockpit's world over BENCH_N frames, the notebook off and on at the same
## head: stowed looking ahead (the thigh out of view), stowed looking down at it, raised, raised with the ring in view.
func _bench(tv: Node, kb: Node) -> void:
	var vp := root.get_viewport_rid()
	var pit: RID = tv.cockpit_3d.get_viewport().get_viewport_rid()  # the 3D cockpit's own world (the thigh's board)
	for v in [vp, pit]:
		RenderingServer.viewport_set_measure_render_time(v, true)
	tv._command([210, 0, 0])  # the JFS current: its ring in view at the last case's head
	var n := 300
	for c in [
		["stowed", Vector2.ZERO, false],
		["stowed_in_view", Vector2(-0.15, -1.05), false],
		["raised", Vector2.ZERO, true],
		["raised_ring", Vector2(-0.22, -0.4), true],
	]:
		tv.views.snap = c[1]
		var gpu := []
		for on in [false, true]:
			kb.set_raised(c[2] and on)
			kb.set_process(on)
			kb._overlay.visible = on
			kb._holder.visible = on and c[2]
			if kb._quad != null:
				kb._quad.visible = on and not c[2]
			await fly(tv, 1.0)
			var g := 0.0
			for i in n:
				await process_frame
				g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				g += RenderingServer.viewport_get_measured_render_time_gpu(pit)
			gpu.append(g / n)
		var t0 := Time.get_ticks_usec()
		for i in n:
			kb._process(0.016)
		var script_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		print("BENCH %s gpu off %.2f on %.2f ms, script %.3f ms" % [c[0], gpu[0], gpu[1], script_ms])
