# The start-up before the main menu (docs/front-end.md §18), the game's main scene:
#   1. ours, Extras → CD launcher: the CD's autorun poster (menu/autorun.gd); PLAY goes on, QUIT / Esc quits;
#   2. the intro videos as the exe plays them (FUN_004e2130 → FUN_004e2960): Resource\Avi\janes.avi, then
#      intro.avi, each 320x240 stretched to the 640x480 screen (MCI_PUT destination 0,0,640,480) on black, with
#      its sound, the cursor hidden over it (WM_SETCURSOR → SetCursor(NULL)). Only the end of a video moves on (the
#      MM_MCINOTIFY "successful" notification posts 0x554); keys and clicks do nothing. A file that does not open is
#      passed over at once. Ours: Esc ends the current video in every mode; Extras → Intro videos: "skippable" (any key
#      or click ends it) or "off";
#   3. the main menu (menu/front_end.tscn; the exe's state 2 draws Bmp\Back0.bmp and opens it).
# Our command-line runs (--mission, --screenshot, --hover) go straight to the menu.
extends Control

const VIDEOS := ["janes.avi", "intro.avi"]
const FRONT_END := "res://menu/front_end.tscn"
const W := 640.0
const H := 480.0
const DEV_ARGS := ["--mission", "--screenshot", "--hover"]

## The video being shown (IafVideo) and its texture; null between videos.
var video: RefCounted
## The path of the video being shown ("" none).
var playing := ""
var texture: ImageTexture
var started_ms := 0
var shown_frame := -1
var skipped := false
var audio: AudioStreamPlayer
signal video_done


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio = AudioStreamPlayer.new()
	add_child(audio)
	if Array(OS.get_cmdline_user_args()).any(func(a): return a in DEV_ARGS):
		_menu.call_deferred()
		return
	run()


func run() -> void:
	if Settings.cd_launcher and not await launcher():
		Settings.quit()
		return
	if Settings.intro_videos != "off":
		for v in VIDEOS:
			await play_video(Settings.assets_dir().path_join("install/resource/avi").path_join(v))
	_menu()


## The CD launcher: true for PLAY (or when its files are missing), false for QUIT.
func launcher() -> bool:
	var a: Control = preload("res://menu/autorun.gd").new()
	add_child(a)
	if not a.available():
		a.queue_free()
		return true
	var result := [true]
	a.quit.connect(func(): result[0] = false; a.play.emit())
	await a.play
	a.queue_free()
	return result[0]


## Plays one video to its end (or until skipped); returns at once when it does not open.
func play_video(path: String) -> void:
	var v := IafVideo.new()
	if not v.open(path) or v.frame_count() == 0:
		return
	video = v
	playing = path
	texture = null
	shown_frame = -1
	skipped = false
	var pcm: PackedByteArray = v.audio_pcm16()
	if not pcm.is_empty():
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = v.audio_rate()
		s.stereo = v.audio_channels() == 2
		s.data = pcm
		audio.stream = s
		audio.play()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	started_ms = Time.get_ticks_msec()
	set_process(true)
	await video_done
	set_process(false)
	audio.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	video = null
	playing = ""
	queue_redraw()


## The video's frame for now (wall clock from its start).
func current_frame() -> int:
	return int((Time.get_ticks_msec() - started_ms) / 1000.0 * video.fps())


func _process(_delta: float) -> void:
	if video == null:
		return
	var f := current_frame()
	if skipped or f >= video.frame_count():
		video_done.emit()
		return
	if f != shown_frame:
		var img := Image.create_from_data(video.width(), video.height(), false, Image.FORMAT_RGB8, video.frame_rgb(f))
		if texture == null:
			texture = ImageTexture.create_from_image(img)
		else:
			texture.update(img)
		shown_frame = f
		queue_redraw()


func _input(e: InputEvent) -> void:
	if video == null or not e.is_pressed() or e.is_echo():
		return
	# Ours: Esc ends the current video in every mode; "skippable" also takes any key or click.
	var esc: bool = e is InputEventKey and e.keycode == KEY_ESCAPE
	if esc or (Settings.intro_videos == "skippable" and (e is InputEventKey or e is InputEventMouseButton)):
		skipped = true
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if video != null and texture != null:
		var s: float = min(size.x / W, size.y / H)
		draw_texture_rect(texture, Rect2((size - Vector2(W, H) * s) / 2.0, Vector2(W, H) * s), false)


func _menu() -> void:
	get_tree().change_scene_to_file(FRONT_END)
