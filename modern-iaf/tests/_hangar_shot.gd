# Real-render pictures of the Hangar (modern-iaf/docs/front-end.md §12) and two screens in its theme, and the
# turntable's frame cost:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <log> --path modern-iaf \
#     -s ../modern-iaf/tests/_hangar_shot.gd
# Writes SHOT_DIR/build_hangar_<unit>_<lang>_<width>.png for the three jets, build_briefing_* and build_prefs_*, at
# 1920 × 1080 and 2560 × 1440 (the front end in a viewport of that size laid out on its 1080-high canvas), with the
# sample pilot log of test_front_end.gd. STILLS=1 also writes SHOT_DIR/still_<unit>.png, the jet alone on a clear
# ground at 1920 × 1080 (the Hangar's still when a model does not load: data/hangar/<unit>.webp). Prints the
# turntable's measured render time ("turntable ms"); COST_ONLY=1 stops after the first measurement (1920 × 1080).
extends "res://../tests/godot/base.gd"

## The turntable script, loaded once the autoloads exist (its model loader reads Settings).
var turntable: GDScript
const SIZES := [Vector2i(1920, 1080), Vector2i(2560, 1440)]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	turntable = load("res://shared/aircraft/turntable.gd")
	s.sim_jet = "f16i"
	for sz in SIZES.slice(0, 1) if OS.get_environment("COST_ONLY") != "" else SIZES:
		var vp := SubViewport.new()
		vp.size = sz
		vp.size_2d_override = Vector2i(1920, 1080)
		vp.size_2d_override_stretch = true
		vp.oversampling_override = sz.y / 1080.0
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var fe: Control = load("res://main.tscn").instantiate()
		vp.add_child(fe)
		await frames(5)
		for lang in ["en", "he"]:
			s.language = lang
			s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
			for unit in ["f16i", "f16d", "f35i"]:
				s.sim_jet = unit
				# Its nose toward the list, the inline start (the mock-ups').
				turntable.yaw = _yaw(lang)
				fe.show_page("hangar")
				var tt: TextureRect = fe.find_child("Turntable", true, false)
				check(tt != null and not tt.failed, "%s: the model loaded" % unit)
				tt.turning = false
				# A hidden app's window may report itself minimised: the pictures render the turntable anyway.
				tt.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				tt.set_process(true)
				await frames(12)
				if unit == "f35i" and lang == "en":
					await _cost(tt, vp, sz)  # every model parsed and drawn once by now: no first-time work in it
					if OS.get_environment("COST_ONLY") != "":
						return
				if OS.get_environment("STILLS") != "" and lang == "en" and sz.x == 1920:
					var still: String = dir.path_join("still_%s.png" % unit)
					check(tt.vp.get_texture().get_image().save_png(still) == OK, "saved " + still)
				await _shot(vp, dir, "build_hangar_%s_%s_%d" % [unit, lang, sz.x])
			s.sim_jet = "f16i"
			fe.mission_i = 1
			fe.show_page("mission")
			await _shot(vp, dir, "build_briefing_%s_%d" % [lang, sz.x])
			fe.pref_group = "graphics"
			fe.show_page("prefs")
			await _shot(vp, dir, "build_prefs_%s_%d" % [lang, sz.x])
		vp.queue_free()
		await frames(2)
	s.language = "en"
	s.pilot_name = ""


## The turntable's cost: the renderer's own CPU time for its viewport, and the GPU's from wall-clock time: 120 frames
## drawn without presenting (no vsync wait), each read back from `vp` so the GPU has finished it, three times with the
## turntable rendering and three with it stopped; the medians' difference is its cost.
func _cost(tt: TextureRect, vp: SubViewport, sz: Vector2i) -> void:
	var rid: RID = tt.vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var ms := []
	for on in [true, false, true, false, true, false]:
		tt.turning = on
		tt.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		await frames(10)
		var cpu := 0.0
		var t0 := Time.get_ticks_usec()
		for i in 120:
			tt._process(1.0 / 60.0)
			RenderingServer.force_draw(false)
			vp.get_texture().get_image()
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		ms.append([(Time.get_ticks_usec() - t0) / 120000.0, cpu / 120])
	tt.turning = false
	tt.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	turntable.yaw = _yaw("en")
	tt._process(0.0)
	await frames(3)
	var px: Vector2i = tt.vp.size
	var with := [ms[0][0], ms[2][0], ms[4][0]]
	var without := [ms[1][0], ms[3][0], ms[5][0]]
	with.sort()
	without.sort()
	print(
		(
			"turntable ms at %dx%d (%dx%d px): median %.2f a frame with it, %.2f without: %.2f (runs %s / %s); CPU %.2f"
			% [sz.x, sz.y, px.x, px.y, with[1], without[1], with[1] - without[1], with, without, ms[0][1]]
		)
	)


## The pictures' turn (degrees): the turntable's start, else YAW (English) and YAW_HE.
func _yaw(lang: String) -> float:
	var en := OS.get_environment("YAW")
	var he := OS.get_environment("YAW_HE")
	if lang == "en":
		return float(en) if en != "" else turntable.START
	return float(he) if he != "" else turntable.START_RTL


func _shot(vp: SubViewport, dir: String, name: String) -> void:
	await frames(10)
	var path: String = dir.path_join(name + ".png")
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
