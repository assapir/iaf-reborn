# Dev helper (not run by tools/test.sh): the TSD's frames while the mission screens' preload runs (the start's
# terrain, the flight scene, its first frame's art and models; terrain/terrain_preload.gd, docs/rendering.md §1.5).
# Basic -> Takeoff (mission 311) -> F-16 -> TSD, then 20 s on the TSD with a click every 2 s (select the next flight
# and back); prints every frame over 25 ms with what had finished by then, the worst frame and the preload's state.
# ST_DDS=0 loads the terrain's JPEGs and compresses them (the path without setup's bc1 step). Vsync off.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file /tmp/t.log --path game --resolution 2560x1440 \
#     -s ../tests/godot/_tsd_bench.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var tp: GDScript = load("res://terrain/terrain_preload.gd")
	load("res://terrain/terrain.gd").precompressed = OS.get_environment("ST_DDS") != "0"
	settings().vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kv in OS.get_environment("GT_SET").split(",", false):
		var p := kv.split("=")
		settings().set(p[0], str_to_var(p[1]))
	var fe = load("res://menu/front_end.tscn").instantiate()
	root.add_child(fe)
	await frames(2)
	fe.screen = "basic"
	fe._enter_screen()
	fe._on_button(fe._key_for_label("Takeoff"))
	await frames(90)
	fe._on_button(fe._key_for_label("F16"))
	while fe.screen != "tsd" or fe.tsd == null:
		await process_frame
	var start := Time.get_ticks_usec()
	var last := start
	var worst := 0.0
	var slow := 0
	var next_click := 2.0
	var ground_at := -1.0
	var scene_at := -1.0
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		var t := (now - start) / 1e6
		if t > 20.0:
			break
		var tr = tp._terrain
		if scene_at < 0 and ResourceLoader.load_threaded_get_status(tp.SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
			scene_at = t
		if ground_at < 0 and tr != null and not tr.missing_after_frame():
			ground_at = t
		worst = maxf(worst, dt)
		if dt > 25.0:
			slow += 1
			print("TSD slow frame %.0f ms at %.2f s (scene %s, ground %s)" % [dt, t, scene_at >= 0, ground_at >= 0])
		if t >= next_click:
			next_click += 2.0
			fe.tsd.select_flight(1 if int(t / 2.0) % 2 == 1 else 0)
	print(
		(
			"TSD worst %.0f ms, %d frames over 25 ms; flight scene loaded at %.1f s, ground at %.1f s"
			% [worst, slow, scene_at, ground_at]
		)
	)
	print("RESULT PASS")
	quit()
