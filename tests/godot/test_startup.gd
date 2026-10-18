# The start-up (game/menu/startup.gd, docs/front-end.md §18): the main scene plays janes.avi then intro.avi (Indeo 5
# decoded by IafVideo, 320x240 at 15 fps, the sound as 16-bit PCM), the cursor hidden, then opens the main menu.
# Original: only Esc (ours) ends a video; Extras → Intro videos "skippable": any key or click ends it; "off": straight
# to the menu; a file that does not open is passed over. Extras → CD launcher: the poster first, PLAY goes on.
extends "res://../tests/godot/base.gd"


func key_down(code := KEY_ESCAPE) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func wait_video(s: Node, name: String) -> bool:
	for i in 300:
		if s.video != null and s.shown_frame >= 0 and String(s.playing).ends_with(name):
			return true
		await process_frame
	return false


func wait_menu() -> bool:
	for i in 300:
		if current_scene != null and current_scene.scene_file_path == "res://menu/front_end.tscn":
			return true
		await process_frame
	return false


func run() -> void:
	var st = Settings()
	# A file that does not open: passed over at once (the exe's FUN_005c4c00 fails, FUN_004e2960 goes on).
	var S = load("res://menu/startup.gd")
	var probe: Control = S.new()
	var t0 := Time.get_ticks_msec()
	await probe.play_video("/nonexistent/intro.avi")
	check(Time.get_ticks_msec() - t0 < 100 and probe.video == null, "missing video: passed over at once")
	probe.free()

	# Original: other keys do not skip.
	st.intro_videos = "original"
	change_scene_to_file("res://menu/startup.tscn")
	await frames(2)
	var s: Node = current_scene
	check(await wait_video(s, "janes.avi"), "janes.avi plays first")
	check(s.video.width() == 320 and s.video.height() == 240 and is_equal_approx(s.video.fps(), 15.0), "320x240, 15 fps")
	check(s.video.frame_count() > 400, "janes.avi: %d frames" % s.video.frame_count())
	check(s.texture != null and s.texture.get_size() == Vector2(320, 240), "frames stream into a 320x240 texture")
	check(s.audio.playing and s.audio.stream.mix_rate == 22050 and s.audio.stream.stereo, "its sound plays (22050 Hz stereo)")
	# The headless display server keeps the mouse mode visible; a real window hides it.
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "cursor hidden over the video")
	s._input(key_down(KEY_SPACE))
	await frames(3)
	check(s.video != null and String(s.playing).ends_with("janes.avi"), "original: Space does not skip")
	# Frame 30 shows a picture (not all black).
	var img := Image.create_from_data(320, 240, false, Image.FORMAT_RGB8, s.video.frame_rgb(30))
	var lit := 0
	for y in range(0, 240, 8):
		for x in range(0, 320, 8):
			lit += 1 if img.get_pixel(x, y).get_luminance() > 0.1 else 0
	check(lit > 50, "frame 30 has a picture (%d lit samples)" % lit)

	# Original: Esc ends janes.avi (ours); intro.avi follows.
	s._input(key_down())
	check(await wait_video(s, "intro.avi"), "original: Esc ends janes.avi, intro.avi follows")
	# Skippable: a click ends intro.avi, the menu opens.
	st.intro_videos = "skippable"
	s._input(mouse_button(Vector2(10, 10), true))
	check(await wait_menu(), "a click ends intro.avi; the main menu follows")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "cursor back")

	# Off: straight to the menu.
	st.intro_videos = "off"
	change_scene_to_file("res://menu/startup.tscn")
	await frames(2)
	check(await wait_menu(), "intro videos off: the menu at once")

	# CD launcher: the poster first; PLAY goes on into the videos.
	st.cd_launcher = true
	st.intro_videos = "skippable"
	change_scene_to_file("res://menu/startup.tscn")
	await frames(3)
	s = current_scene
	var a: Control = s.get_child(s.get_child_count() - 1)
	check(a.has_signal("play") and s.video == null, "CD launcher shows first")
	a.press(a.PLAY)
	check(await wait_video(s, "janes.avi"), "PLAY: the intro videos follow")
	st.cd_launcher = false
	st.intro_videos = "original"
