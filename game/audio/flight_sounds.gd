# In-flight sounds of the player's own aircraft (docs/sound.md): a port of the original sound
# manager's rules for the player (engine object sound FUN_004c3c10 / FUN_004c3e00, player
# controller FUN_00448b20 / FUN_0044a240, engine object FUN_0045aa80, flight-model touchdown
# FUN_005bb9f0, unit destroy FUN_004a86b0, eject FUN_004a8100). Which sound plays, its file, loop,
# volume, 3-D distances and logical channel come from the original table SoundProp.trx
# (game/audio/sound_table.gd); the rules below only pick the sound code.
# Generic for every aircraft: the engine set is the same for all types (the engine rule applies to
# every object of class 0x1e); the only per-type data is whether the jet has the Betty voice
# warnings (BETTY_TYPES).
# Better than 1998 (allowed): Godot's resampler for the pitch changes and positional panning of the
# 3-D sounds; the distance rule itself is DirectSound's (min / max distance of the table).
#
# Host: terrain_view (flight, rig, terrain, gear_down, flaps, flaps_state, brakes, in_cockpit); the
# node polls it every frame. Tests call update() directly.
extends Node3D

const SoundBuses := preload("res://audio/sound_buses.gd")
const SoundTable := preload("res://audio/sound_table.gd")

## Aircraft types whose player controller carries the Betty voice warnings: ctl+0x964, set per type
## code in FUN_00447e70 (switch @447e95, byte table 0x448094): F-16 100, F-15 110, Lavi 140,
## MiG-29 180, F-4 200 = 1; F-4 120, Kfir 130, MiG-21 150, MiG-23 160, MiG-25 170, Mirage 190,
## 210 / 220 / 225 = 0.
const BETTY_TYPES := [100, 110, 140, 180, 200, 1000]
## [Sound] registry values read by FUN_004c3ac0 (defaults; the install sets none):
## PitchIntrPercent, PitchIntrShift, Ab1PitchPerc, Ab2PitchPerc. (InsideReduceVolume 0.75 is read
## too but never used.)
const PITCH_INTR_PERCENT := 0.25
const PITCH_INTR_SHIFT := 0.5
const AB1_PITCH := 0.8
const AB2_PITCH := 1.2
## MCockpitSoundEvent repeat period (DAT_0082f468 = 4.0, initialiser @446c40).
const BETTY_PERIOD := 4.0
## "Altitude" below 100 ft above the terrain with the gear handle up (FUN_0044fe30, 0x600aa8).
const ALT_WARN_FT := 100.0
const FT_PER_M := 3.281  # 0x600b34
## AoA / stall warning tone while the flight model's dragX (getter 0x12, S+0x2f0) > 0.5 in the air (@449247).
const AOA_DRAG_X := 0.5
## Betty "Fuel" once below 1000 lb and once more below 500 lb (FUN_0045aa80, 0x6010b4 / 0x6010b8).
const FUEL_LOW_LB := 1000.0
const FUEL_VERY_LOW_LB := 500.0
## Gear ramp value below which the gear counts as fully down at touchdown (0x6124e0).
const GEAR_DOWN_EPS := 1e-5

var host: Node
var type_code := 100
var betty := true
## Runway under the wheels (terrain flag f & 0x30); our terrain has no type data, so a belly landing
## never screeches (docs/sound.md §4).
var on_runway := false
var table: RefCounted

## Engine object sound (slot 0): the current code and pitch (FUN_004c3e00).
var engine_code := ""
var engine_pitch := 1.0
var _engine_last := 0.0  # param_1[10]: the last RPM or AB pitch the pitch was set from
var _engine: AudioStreamPlayer3D
var _engine_row := {}
## Handles of the controller's loops / timers.
var _speed_brake_loop: Node = null  # ctl+0x8cc
var _aoa_loop: Node = null  # ctl+0x8c4
var _alt_timer := -1.0  # ctl+0x904: next Betty "altitude" time, < 0 = off
var _fuel_flags := [true, true]  # engine object +0x40 / +0x44
var _was := {}
var _crashed := false
## Logical channels (soundprop column "channel"): the sound playing and those waiting.
var _channels := {}
## 3-D players and their rows (distance rule each frame).
var _players3d: Array = []
## For tests: every sound started, as "CODE/SUB1" (or the file for plain wavs).
var played: Array[String] = []


static func create(host_node: Node, type: int) -> Node:
	var n = load("res://audio/flight_sounds.gd").new()
	n.name = "FlightSounds"
	n.host = host_node
	n.type_code = type
	return n


func _ready() -> void:
	SoundBuses.ensure()
	betty = type_code in BETTY_TYPES
	table = SoundTable.load_table()
	_engine = AudioStreamPlayer3D.new()
	_engine.bus = SoundBuses.ENGINE
	_setup_3d(_engine)
	add_child(_engine)


func _process(_delta: float) -> void:
	if host != null:
		var f = host.get("flight")
		if f != null:
			var st: Dictionary = f.state()
			if not st.is_empty():
				global_position = host.rig.global_position
				var ground = host.terrain.height_at(host.rig.position)
				update(st, {
					"gear_down": host.gear_down, "flaps": host.flaps, "flaps_state": host.flaps_state,
					"brakes": host.brakes, "in_cockpit": host.in_cockpit,
					"agl_m": st.position.y - ground if ground != null else 1.0e6,
				})
	_update_3d()


## One frame: `st` = IafFlight.state(), `inp` = the host's levers and view (gear_down, flaps,
## flaps_state, brakes, in_cockpit, agl_m).
func update(st: Dictionary, inp: Dictionary) -> void:
	var now: float = st.get("time", 0.0)
	var airborne: bool = not st.on_ground
	var inside: bool = inp.get("in_cockpit", true)
	if _crashed:
		return
	if st.get("crashed", false):
		_crash()
		return
	_update_engine(int(st.afterburner), float(st.rpm), inside)
	# Levers: the host changes them only when the original accepts the command.
	if _was.has("gear_down"):
		if inp.gear_down != _was.gear_down:
			play("SFX_LANDING_GEAR")  # GEV 0xe (@44d26e): gear lever, both ways
		if inp.flaps != _was.flaps and _was.flaps_state != 1:
			play("SFX_FLAPS")  # GEV 0xc (@44cc36): flaps lever while not moving
		if inp.brakes != _was.brakes:
			_speed_brake_toggle(inp.brakes, airborne)
		if airborne != _was.airborne and not airborne:
			_touchdown(float(st.gear))
	# Per frame (FUN_00448b20).
	_aoa_warning(float(st.get("drag_x", 0.0)) > AOA_DRAG_X and airborne)
	if inp.brakes:
		if airborne:
			if _speed_brake_loop == null:
				_speed_brake_loop = play("SFX_SPEED_BREAKES_LOOP")
		elif _speed_brake_loop != null:
			_stop(_speed_brake_loop)
			_speed_brake_loop = null
	_altitude_warning(float(inp.get("agl_m", 1.0e6)) * FT_PER_M, inp.gear_down, now)
	_fuel_warning(float(st.get("fuel_lbs", 1.0e6)))
	_was = {"gear_down": inp.gear_down, "flaps": inp.flaps, "flaps_state": inp.get("flaps_state", 0),
		"brakes": inp.brakes, "airborne": airborne}
	_inside = inside


var _inside := true


# --- engine (FUN_004c3e00 via FUN_004c3c10, every frame and on throttle events) -----------------

func _update_engine(stage: int, rpm: float, inside: bool) -> void:
	var code := engine_code
	if stage < 1:
		if rpm != _engine_last:
			code = "SFX_LANDING"
			if rpm > 0.0:
				engine_pitch = (rpm + PITCH_INTR_SHIFT) * PITCH_INTR_PERCENT + 1.0
				code = "SFX_START_ENGINE"
			_engine_last = rpm
		if rpm <= 0.0:
			code = "SFX_LANDING"
	elif stage == 1:
		code = "SFX_DRY_THRUST"
		if _engine_last != AB1_PITCH:
			engine_pitch = AB1_PITCH
			_engine_last = AB1_PITCH
	elif stage == 2:
		code = "SFX_AFTERBURNER_THRUST"
		if _engine_last != AB2_PITCH:
			engine_pitch = AB2_PITCH
			_engine_last = AB2_PITCH
	if code != engine_code:
		# A new code stops the slot's sound and starts the new one (FUN_004c42a0 + FUN_004c4ea0).
		engine_code = code
		_engine.stop()
		_engine_row = table.row(code)
		var s: AudioStreamWAV = table.stream(_engine_row)
		_engine.stream = _looped(s) if s != null and _engine_row.cyclic else s
		if s != null:
			# SFX_LANDING (engine off) is landing.wav, 86 samples of near-silence; looped that short it
			# becomes an audible tone here, so it is not played (silence, as intended; docs/deviations.md).
			if code != "SFX_LANDING":
				_engine.play()
			played.append(code + "/None")
	_engine.pitch_scale = engine_pitch
	_engine.set_meta("base_volume", _row_volume(_engine_row, inside))


# --- controller rules ---------------------------------------------------------------------------

## GEV 0x11 (@44c97b): the air brake sound on every toggle; the loop starts when the brake comes out
## in the air, otherwise a running loop stops.
func _speed_brake_toggle(on: bool, airborne: bool) -> void:
	play("SFX_SPEED_BREAKES")
	if on and _speed_brake_loop == null:
		if airborne:
			_speed_brake_loop = play("SFX_SPEED_BREAKES_LOOP")
			return
	if _speed_brake_loop != null:
		_stop(_speed_brake_loop)
		_speed_brake_loop = null


## AoA warning tone (SFX_WARNING / WRN_AOA, cyclic): on while the condition holds (@449247).
func _aoa_warning(on: bool) -> void:
	if on:
		if _aoa_loop == null:
			_aoa_loop = play("SFX_WARNING", "WRN_AOA")
	elif _aoa_loop != null:
		_stop(_aoa_loop)
		_aoa_loop = null


## FUN_0044fe30: below 100 ft above the terrain with the gear handle up, Betty "altitude" at once
## and every 4 s (only on jets with Betty). "Pull up" needs an air-to-ground HUD mode (not built).
func _altitude_warning(h_ft: float, gear_down: bool, now: float) -> void:
	if h_ft < ALT_WARN_FT and not gear_down:
		if betty and _alt_timer < 0.0:
			_alt_timer = now
		if _alt_timer >= 0.0 and now >= _alt_timer:
			play("VOC_BBETTY", "BTY_ALT")
			_alt_timer += BETTY_PERIOD
			if _alt_timer <= now:
				_alt_timer = now + BETTY_PERIOD
	else:
		_alt_timer = -1.0


## FUN_0045aa80 (every fuel update): Betty "fuel" once between 1000 and 500 lb, and once below 500.
func _fuel_warning(lbs: float) -> void:
	if lbs < FUEL_LOW_LB and lbs > FUEL_VERY_LOW_LB and _fuel_flags[0]:
		play("VOC_BBETTY", "BTY_FUEL")
		_fuel_flags[0] = false
	if lbs < FUEL_VERY_LOW_LB and _fuel_flags[1]:
		play("VOC_BBETTY", "BTY_FUEL")
		_fuel_flags[0] = false
		_fuel_flags[1] = false


## FUN_005bb9f0 @5bbd1e: touchdown with the landing check passed (a failed one is a crash). Gear
## fully down: SFX_TOUCHDOWN; belly: SFX_SCREECH only on a runway.
func _touchdown(gear: float) -> void:
	if absf(gear) < GEAR_DOWN_EPS:
		play("SFX_TOUCHDOWN")
	elif on_runway:
		play("SFX_SCREECH")


## Destroyed (unit state 5 -> FUN_004a86b0): the explosion effect of an aircraft (FUN_0059df20,
## classes 1/2/3/0x1c -> SFX_AIRCRAFT_EXPLODED, 3-D at the jet) and the object's sounds stop
## (FUN_004c4310). The controller's loops end with the player.
func _crash() -> void:
	_crashed = true
	_engine.stop()
	engine_code = ""
	for h in [_speed_brake_loop, _aoa_loop]:
		if h != null:
			_stop(h)
	_speed_brake_loop = null
	_aoa_loop = null
	_alt_timer = -1.0
	play("SFX_AIRCRAFT_EXPLODED")


## The ejection (unit state 3 -> FUN_004a8100): "Eject! Eject!" (VOC_WINGMAN / WINGMAN_EJECT_EJECT,
## eject.wav) for the player. Called by the ejection code.
func play_eject() -> Node:
	return play("VOC_WINGMAN", "WINGMAN_EJECT_EJECT")


# --- playing a table sound (FUN_004c4ea0) --------------------------------------------------------

## Plays the row of `code` / `sub1`; returns its player (null when the row or its file is missing).
## Resident rows: volume = table volume (inside / outside the cockpit) × the category bus; 3-D rows
## sit at the jet. Non-resident rows go through FUN_004c5450 -> FUN_004c5470: plain wav, speech
## volume, no table volume (quirk kept: e.g. the touchdown and screech follow the speech slider);
## channel 101 is the phrase channel of the mission voices.
func play(code: String, sub1 := "None") -> Node:
	var r: Dictionary = table.row(code, sub1) if table != null else {}
	if r.is_empty():
		return null
	var s: AudioStreamWAV = table.stream(r)
	if s == null:
		return null
	played.append("%s/%s" % [code, sub1])
	var p: Node
	var resident: bool = r.resident
	if resident and r.is3d:
		var p3 := AudioStreamPlayer3D.new()
		_setup_3d(p3)
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.bus = SoundBuses.BY_CATEGORY.get(r.category, SoundBuses.SFX) if resident else SoundBuses.SPEECH
	p.stream = _looped(s) if resident and r.cyclic else s
	var vol := _row_volume(r, _inside) if resident else 1.0
	p.set_meta("base_volume", vol)
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	add_child(p)
	if resident and r.is3d:
		_players3d.append([p, r])
	if not (resident and r.cyclic):
		p.finished.connect(_on_finished.bind(p))
	var ch: int = r.channel if resident else (101 if r.channel == 101 else 0)
	if ch != 0:
		_channel_play(ch, p)
	else:
		p.play()
	return p


## A plain wav of resource/soundfiles on the phrase channel (FUN_004c5470(file, 0, 1) and every part of a
## radio phrase, FUN_004c5750 → FUN_005448b0): speech volume, not 3-D, queued behind the sound on channel 101
## (docs/radio.md §1). Null when the file is not shipped (silent, as in the original).
func play_phrase_wav(file: String) -> Node:
	var name := file.to_lower()
	if not "." in name:
		name += ".wav"
	var s: AudioStreamWAV = table.stream_file(name) if table != null else null
	if s == null:
		return null
	played.append(name)
	var p := AudioStreamPlayer.new()
	p.bus = SoundBuses.SPEECH
	p.stream = s
	add_child(p)
	p.finished.connect(_on_finished.bind(p))
	_channel_play(101, p)
	return p


func _row_volume(r: Dictionary, inside: bool) -> float:
	if r.is_empty():
		return 1.0
	return r.vol_in if inside else r.vol_out


## A logical channel plays one sound at a time; a new one waits for the current (UNCERTAIN: queue
## vs replace, docs/sound.md §2).
func _channel_play(ch: int, p: Node) -> void:
	var c: Dictionary = _channels.get(ch, {"cur": null, "queue": []})
	_channels[ch] = c
	if c.cur != null and is_instance_valid(c.cur) and c.cur.playing:
		c.queue.append(p)
	else:
		c.cur = p
		p.play()


func _on_finished(p: Node) -> void:
	for ch in _channels:
		var c: Dictionary = _channels[ch]
		if c.cur == p:
			c.cur = null
			while not c.queue.is_empty():
				var n: Node = c.queue.pop_front()
				if is_instance_valid(n):
					c.cur = n
					n.play()
					break
	_players3d = _players3d.filter(func(e): return e[0] != p)
	p.queue_free()


## Stops a sound started by play() (loops: the gun, the IR tones).
func stop(p: Node) -> void:
	_stop(p)


func _stop(p: Node) -> void:
	if p != null and is_instance_valid(p):
		p.stop()
		_players3d = _players3d.filter(func(e): return e[0] != p)
		p.queue_free()


func _looped(s: AudioStreamWAV) -> AudioStreamWAV:
	var l: AudioStreamWAV = s.duplicate()
	l.loop_mode = AudioStreamWAV.LOOP_FORWARD
	l.loop_begin = 0
	var frame_bytes := (2 if l.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if l.stereo else 1)
	l.loop_end = l.data.size() / frame_bytes
	return l


# --- 3-D: DirectSound's distance rule, Godot's panning --------------------------------------------

func _setup_3d(p: AudioStreamPlayer3D) -> void:
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.max_distance = 0.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED


## Gain = min / clamp(distance, min, max) (DirectSound 3-D, rolloff 1) from the listening camera.
func _update_3d() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var list: Array = _players3d.duplicate()
	if _engine != null and not _engine_row.is_empty():
		list.append([_engine, _engine_row])
	for e in list:
		var p: AudioStreamPlayer3D = e[0]
		if not is_instance_valid(p):
			continue
		var r: Dictionary = e[1]
		var d := cam.global_position.distance_to(p.global_position) if cam != null else 0.0
		var gain: float = r.min_d / clampf(d, r.min_d, maxf(r.max_d, r.min_d)) if r.min_d > 0.0 else 1.0
		p.volume_db = linear_to_db(maxf(float(p.get_meta("base_volume", 1.0)) * gain, 0.0001))
