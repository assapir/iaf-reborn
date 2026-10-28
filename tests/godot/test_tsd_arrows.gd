# The TSD map's scroll arrows (docs/front-end.md §8, FUN_004ffba0 / FUN_004f3700 / FUN_004f4110), in English and
# Hebrew: sldownb (pointing left / up) at the bar's start, slupb (pointing right / down) at its end; a click on the
# start arrow scrolls left / up, on the end arrow right / down, one step of 5 map units; the pressed arrow shows _1.
# SHOT_DIR=dir (a real render, tools/godot_window.sh) writes tsd_arrows_en.png / tsd_arrows_he.png.
# Also the text.emf labels: they scale with the map (501060 inside EnumEnhMetaFile, docs/front-end.md §8), so
# JERUSALEM's text ends just west of its city dot (x 289.2) at every zoom up to 32, and keeps its zoom-32 size beyond.
extends "res://../tests/godot/base.gd"


func press(tsd: Control, fe: Control, p: Vector2, down: bool) -> void:
	tsd._gui_input(mouse_button(fe._to_screen(p), down))


func check_labels(fe: Control, tsd: Control) -> void:
	var op: Dictionary = {}
	for o in tsd.map_canvas.text_ops:
		if o.text == "JERUSALEM":
			op = o
	# The text's length in map units, measured at 100 px per map unit.
	var end: float = op.pos.x + fe.font.get_string_size(op.text, HORIZONTAL_ALIGNMENT_LEFT, -1, op.px * 100).x / 100
	check(end > 286.5 and end < 290.0, "JERUSALEM ends at x %.1f, by its dot (289.2)" % end)
	var s: float = fe._scale()
	for z in [1.0, 3.375, 32.0]:
		tsd.zoom = z
		check(
			absf(tsd.label_px(op) - op.px * z * s) <= 0.5,
			"at zoom %s the label's font is %d px, its 4.97 map units at %.2f px each" % [z, tsd.label_px(op), z * s]
		)
	var px32: int = tsd.label_px(op)
	tsd.zoom = 64.0
	check(tsd.label_px(op) == px32, "beyond zoom 32 a label keeps its zoom-32 size (%d px)" % px32)


func run() -> void:
	for lang in ["en", "he"]:
		settings().language = lang
		var fe = load("res://menu/front_end.tscn").instantiate()
		root.add_child(fe)
		await frames(3)
		settings().mission_id = 113
		fe._reset_tsd_checks()
		fe.screen = "tsd"
		fe._enter_screen()
		await frames(3)
		var tsd = fe.tsd
		for i in 3:
			tsd.zoom_by(tsd.ZOOM_STEP)
		tsd.centre_on(tsd.MAP_SIZE / 2)
		for axis in 2:
			var name: String = ["horizontal", "vertical"][axis]
			var bar: Rect2 = tsd.BARS[axis]
			var a: String = tsd.BAR_ART[axis]
			var arrows: Array = tsd.bar_arrows(axis)
			var start_tex: Texture2D = fe._tex(arrows[0][0])
			var end_tex: Texture2D = fe._tex(arrows[1][0])
			check(
				arrows[0][0] == "tsd/%ssldownb_0.png" % a and arrows[0][1] == bar.position,
				"%s %s: sldownb (pointing %s) at the start %s" % [lang, name, ["left", "up"][axis], bar.position]
			)
			var end_at: Vector2 = bar.position
			end_at[axis] = bar.end[axis] - fe._art_size(end_tex)[axis]
			check(
				arrows[1][0] == "tsd/%sslupb_0.png" % a and arrows[1][1] == end_at,
				"%s %s: slupb (pointing %s) flush with the end, at %s" % [lang, name, ["right", "down"][axis], end_at]
			)
			check(
				fe._art_size(start_tex)[axis] == tsd.BAR_UP[axis] and fe._art_size(end_tex)[axis] == tsd.BAR_DOWN[axis],
				"%s %s: the thumb travels between the two arrows' art" % [lang, name]
			)
			var mid := bar.size / 2
			mid[axis] = tsd.BAR_UP[axis] / 2
			var s0: float = tsd.scroll[axis]
			press(tsd, fe, bar.position + mid, true)
			check(
				(
					is_equal_approx(tsd.scroll[axis], s0 - tsd.ARROW_STEP / tsd.zoom)
					and tsd.bar_arrows(axis)[0][0].ends_with("_1.png")
				),
				"%s %s: the start arrow scrolls %s one step, shown pressed" % [lang, name, ["left", "up"][axis]]
			)
			press(tsd, fe, bar.position + mid, false)
			mid[axis] = bar.size[axis] - tsd.BAR_DOWN[axis] / 2
			s0 = tsd.scroll[axis]
			press(tsd, fe, bar.position + mid, true)
			check(
				(
					is_equal_approx(tsd.scroll[axis], s0 + tsd.ARROW_STEP / tsd.zoom)
					and tsd.bar_arrows(axis)[1][0].ends_with("_1.png")
				),
				"%s %s: the end arrow scrolls %s one step, shown pressed" % [lang, name, ["right", "down"][axis]]
			)
			press(tsd, fe, bar.position + mid, false)
			check(tsd.pressed_arrow == "", "%s %s: released" % [lang, name])
		if OS.get_environment("SHOT_DIR") != "":
			tsd.queue_redraw()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := OS.get_environment("SHOT_DIR").path_join("tsd_arrows_%s.png" % lang)
			root.get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
		if lang == "en":
			check_labels(fe, tsd)
		fe.queue_free()
		await frames(2)
