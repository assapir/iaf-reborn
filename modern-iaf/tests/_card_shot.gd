# Dev helper (not run by tools/test.sh): every page of each jet's checklist card (modern-iaf/docs/training.md §12) on
# the raised notebook, in English and Hebrew, cropped to the board, from the start-up lesson after its first items (some
# ticked, one current); one PNG per page: card_<jet>_<lang>_<page>.png.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOW_OUT=<dir> -- --log-file <temp> --path modern-iaf \
#     -s ../modern-iaf/tests/_card_shot.gd
extends "res://tests/test_mvp.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	var shots := OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("iaf2026-card-shots-%d" % OS.get_process_id())
	settings().show_info = false
	for m in [["f16i", "ramon_startup"], ["f35i", "nevatim_startup"]]:
		var tv := await _start(m[1])
		Engine.time_scale = 1.0
		await fly(tv, 1.0)
		var kb: Node = tv.addon.kneeboard
		if kb._help != null:
			kb._help.queue_free()
			kb._help = null
		tv.addon.pick("startup")
		await _fly_card(tv, func(it): return it.id != "starter")
		for lang in ["en", "he"]:
			settings().language = lang
			kb.refresh()
			kb.board.open("startup")
			for p in kb.board.page_count():
				await frames(3)
				await RenderingServer.frame_post_draw
				var r: Rect2 = kb._holder.get_global_rect()
				var k: float = root.get_texture().get_size().y / float(tv.addon.ui.size.y)
				var img := root.get_texture().get_image()
				var crop := Rect2i(Vector2i(r.position * k), Vector2i(kb.board.W * k, kb.board.H * k))
				img = img.get_region(crop.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
				img.save_png(shots.path_join("card_%s_%s_%d.png" % [m[0], lang, p + 1]))
				kb.board.turn(1)
		settings().language = "en"
	check(true, "pictures in %s" % shots)
