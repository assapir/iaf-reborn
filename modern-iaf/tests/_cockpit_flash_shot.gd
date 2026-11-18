# Real-render check (not run by tools/test.sh: it needs a window): the 3D cockpit shows no flash at a Training
# lesson's start and while the head pans (the user, 17 Nov: "the cockpit goes white, brighter for a sec when it jumps
# for a sec when starting the first training", "also moving the view doing white flashs"). Each frame's mean brightness
# of the cockpit (the window's lower third) is measured from the start of the flight and through a 15 s pan left,
# right, up and down, then with the layer taken away for 20 frames and back (a view switch); a frame that differs
# from the one before by more than LIMIT fails, and those over JUMP are counted.
# SHOT_SET=key=value,... sets settings first (upscaling=quality, antialiasing=temporal); FLASH_LESSON=<mission file>
# picks the lesson (default ramon_startup, the first; ramon_takeoff is the second); FLASH_PROBE=1 leaves the sharp
# layer's picture out and prints the range of the exposure grey as the window shows it (cockpit_composite.gdshader:
# steady when the upscaler leaves it alone).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_SET=upscaling=quality \
#     -- --log-file <t> --resolution 1280x720 --path modern-iaf -s ../modern-iaf/tests/_cockpit_flash_shot.gd
extends "res://tests/test_mvp.gd"

## The largest frame-to-frame change of the cockpit's mean brightness (0..1) a slow pan and the auto exposure make
## (0.014 to 0.015 measured without the sharp layer), and the change that counts as a flash.
const LIMIT := 0.02
const JUMP := 0.04
## The pan's rate, rad/s: its legs (6.4 rad) in 15 s.
const PAN := 6.4 / 15.0


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	settings().show_info = false
	for kv in OS.get_environment("SHOT_SET").split(",", false):
		var p := kv.split("=")
		var cur = settings().get(p[0])
		settings().set(p[0], (p[1] == "true") if cur is bool else p[1])
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-flash-%d" % OS.get_process_id())
	var lesson := OS.get_environment("FLASH_LESSON")
	var tv := await _start(lesson if lesson != "" else "ramon_startup")
	var probe := OS.get_environment("FLASH_PROBE") == "1" and tv.cockpit_origin != null
	if probe:
		tv.cockpit_origin._sharp.get_child(1).visible = false  # the grey left in the picture
	var grey := Vector2(INF, -INF)
	Engine.time_scale = 1.0
	var log: Array = []
	var worst := 0.0
	var jumps := 0
	var last := -1.0
	var t0 := Time.get_ticks_msec()
	var t_last := Time.get_ticks_usec()
	var head := Vector2.ZERO
	var legs := [Vector2(-1, 0), Vector2(2, 0), Vector2(-1, 0), Vector2(0, 0.6), Vector2(0, -1.2), Vector2(0, 0.6)]
	var leg := -1
	var leg_left := 2.0  # the first 2 s still: the start
	var again := -1  # after the pan: the layer and its grey off for 20 frames, then on again (a view switch)
	while leg < legs.size() or again < 80:
		await RenderingServer.frame_post_draw
		if leg >= legs.size() and tv.cockpit_origin != null and not probe:
			again += 1
			var co: Node = tv.cockpit_origin
			co.set_process(again >= 20)
			if again < 20:
				co._probe.visible = false
				co._sharp.visible = false
		elif leg >= legs.size():
			again = 80
		var now := Time.get_ticks_usec()
		var dt := (now - t_last) / 1e6  # the real clock: the pan takes 15 s at any frame rate
		t_last = now
		if leg >= 0 and leg < legs.size():
			head += legs[leg].normalized() * PAN * dt
			tv.views.head = head
		leg_left -= dt
		if leg_left <= 0.0:
			leg += 1
			leg_left = legs[leg].length() / PAN if leg < legs.size() else 0.0
		var img := root.get_texture().get_image()
		var h := img.get_height()
		var w := img.get_width()
		if probe:
			var at := int(0.5 * tv.cockpit_origin.PROBE_PX / root.scaling_3d_scale)
			var g := img.get_pixel(at, at).g
			grey = Vector2(minf(grey.x, g), maxf(grey.y, g))
		var low := img.get_region(Rect2i(0, h * 2 / 3, w, h / 3))
		low.resize(64, 16, Image.INTERPOLATE_BILINEAR)
		var sum := 0.0
		for y in 16:
			for x in 64:
				sum += low.get_pixel(x, y).get_luminance()
		var m := sum / 1024.0
		if last >= 0.0:
			worst = maxf(worst, absf(m - last))
			if absf(m - last) > JUMP:
				jumps += 1
				print(
					(
						"JUMP frame %d t %d ms %.3f -> %.3f head %s"
						% [log.size(), Time.get_ticks_msec() - t0, last, m, head]
					)
				)
		log.append(m)
		last = m
	if OS.get_environment("SHOT_OUT") != "":
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	print("means ", log.slice(0, 5), " min %.3f max %.3f" % [log.min(), log.max()])
	if tv.cockpit_origin != null:
		print("sharp layer ", tv.cockpit_origin._sharp.visible)
	if probe:
		print("exposure grey seen %.4f to %.4f" % [grey.x, grey.y])
	print(
		(
			"frames %d worst jump %.4f over %.2f: %d scale %.2f mode %d"
			% [log.size(), worst, JUMP, jumps, root.scaling_3d_scale, root.scaling_3d_mode]
		)
	)
	check(worst <= LIMIT, "no cockpit flash: worst frame-to-frame change %.4f <= %.2f" % [worst, LIMIT])
