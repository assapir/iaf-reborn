# Blackout / redout and the G warnings (docs/flight-model.md §13), for the player's own aircraft.
# Two accumulators integrate every frame (even when drawing is off):
#   B += 0.43·G·dt (≤ 24), B -= 2.5·dt (≥ 0);   R += 0.2·G·dt (clamped −3..0), R += 0.25·dt while R < 0
# Blackout (b = (B − 15)·0.125): black overlay alpha min(275·b, 255) plus a tunnel of up to 7 rings
# from radius W down to (2 − 2b)·W, 3 px narrower and 20 alpha lower each; solid black above b 0.95.
# Redout (r = (R + 1)·0.5 when R < 0): flat ARGB(−255·r, 0x7f, 0, 0) overlay. Blackout has priority.
# Voice "Over G" (cock_bty_over.wav) above the aircraft's OverGThresh at most every 4 s, and the G
# sound (cock_g_02.wav) above 6 g at most every 17 s (the latter not gated by "No blackouts").
# Whether the original overlay also covered the cockpit art is UNCERTAIN; drawn over everything.
extends Control

const SoundBuses := preload("res://audio/sound_buses.gd")

var g := 1.0
var over_g := false
## "No blackouts" preference: no integration or drawing (the G sound still plays).
var disabled := false
var blackout := 0.0
var redout := 0.0
var _voice_next := 0.0
var _gsound_next := 0.0
var _now := 0.0
## Voice (Betty, category V -> speech volume) and effect (SFX_G_EFFECT, category F -> effects volume)
## players on the sound buses (game/audio/sound_buses.gd, docs/sound.md).
var _voice: AudioStreamPlayer
var _player: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SoundBuses.apply()
	_voice = AudioStreamPlayer.new()
	_voice.bus = SoundBuses.SPEECH
	add_child(_voice)
	_player = AudioStreamPlayer.new()
	_player.bus = SoundBuses.SFX
	add_child(_player)


func _process(delta: float) -> void:
	# The original integrates the frame's real time (DAT_007d1980, timeGetTime), not the sim clock:
	# time compression (Engine.time_scale) does not speed it up.
	var dt := minf(delta / maxf(Engine.time_scale, 1e-6), 0.2)
	_now += delta
	if not disabled:
		blackout = minf(blackout + 0.43 * g * dt, 24.0)
		redout = clampf(redout + 0.2 * g * dt, -3.0, 0.0)
		blackout = maxf(blackout - 2.5 * dt, 0.0)
		if redout < 0.0:
			redout = minf(redout + 0.25 * dt, 0.0)
		if over_g and _now >= _voice_next:
			_voice_next = _now + 4.0
			_play(_voice, "cock_bty_over.wav")
	if g > 6.0 and _now >= _gsound_next:
		_gsound_next = _now + 17.0
		_play(_player, "cock_g_02.wav")
	queue_redraw()


func _play(player: AudioStreamPlayer, file: String) -> void:
	var path := Settings.assets_dir().path_join("install/resource/soundfiles").path_join(file)
	if FileAccess.file_exists(path):
		player.stream = AudioStreamWAV.load_from_file(path)
		player.play()


func _draw() -> void:
	if disabled:
		return
	var b := (blackout - 15.0) * 0.125
	var r := (redout + 1.0) * 0.5 if redout < 0.0 else 0.0
	var full := Rect2(Vector2.ZERO, size)
	if b >= 0.01:
		if b > 0.95:
			draw_rect(full, Color.BLACK)
			return
		var a := mini(int(275.0 * b), 275)
		draw_rect(full, Color(0, 0, 0, mini(a, 255) / 255.0))
		# Tunnel: rings from radius W inward; the render width is the reference as in the original.
		var centre := size / 2
		var w := size.x
		var outer := w
		var inner := (2.0 - 2.0 * b) * w
		for k in 7:
			if inner < 0.0:
				break
			var alpha := clampi(a - 20 * k, 0, 255) / 255.0
			_ring(centre, outer, inner, Color(0, 0, 0, alpha))
			outer = inner
			inner -= 3.0
	elif r <= 0.01:
		var a := mini(int(-255.0 * r), 255)
		if a >= 1:
			draw_rect(full, Color8(0x7f, 0, 0, a))


func _ring(c: Vector2, outer: float, inner: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var ang := TAU * i / n
		pts.append(c + Vector2(cos(ang), sin(ang)) * outer)
	for i in range(n, -1, -1):
		var ang := TAU * i / n
		pts.append(c + Vector2(cos(ang), sin(ang)) * inner)
	draw_colored_polygon(pts, color)
