# In-flight sounds (docs/sound.md): the engine code / pitch rule, lever sounds, warnings, touchdown,
# crash, the Betty per-type flag, the Preferences volumes on the buses; then mission 311 in flight
# (engine off at the ground start, "1" starts it and the pitch rises with the RPM).
extends "res://../tests/godot/base.gd"

## Loaded at run time: scripts that use the Settings autoload do not compile before it exists.
var FlightSounds: GDScript
const SoundBuses := preload("res://audio/sound_buses.gd")


func _state(over := {}) -> Dictionary:
	var st := {"time": 0.0, "on_ground": false, "afterburner": 0, "rpm": 0.0, "gear": 1.569,
		"crashed": false, "drag_x": 0.0, "fuel_lbs": 5000.0}
	st.merge(over, true)
	return st


func _inp(over := {}) -> Dictionary:
	var i := {"gear_down": false, "flaps": 0.0, "flaps_state": 0, "brakes": false, "in_cockpit": true,
		"agl_m": 3000.0}
	i.merge(over, true)
	return i


func _count(fs, what: String) -> int:
	return fs.played.count(what)


func run() -> void:
	FlightSounds = load("res://audio/flight_sounds.gd")
	# The original table.
	var fs = FlightSounds.create(null, 100)
	root.add_child(fs)
	var r: Dictionary = fs.table.row("SFX_DRY_THRUST")
	check(r.get("file", "") == "Cock_Eng_Brnr" and is_equal_approx(r.vol_in, 0.75) and r.cyclic,
		"SoundProp.trx: dry thrust = Cock_Eng_Brnr, looped, 0.75 inside")
	check(fs.table.stream(fs.table.row("SFX_LANDING_GEAR")) != null, "gear.wav resolves case-insensitively")

	# Engine (FUN_004c35d0): off -> SFX_LANDING, running -> StartEngine with the RPM pitch, AB -> burner.
	fs.update(_state({"on_ground": true, "gear": 0.0}), _inp({"gear_down": true}))
	check(fs.engine_code == "SFX_LANDING", "engine off: SFX_LANDING (near-silent Landing.wav)")
	fs.update(_state({"on_ground": true, "gear": 0.0, "rpm": 0.6}), _inp({"gear_down": true}))
	check(fs.engine_code == "SFX_START_ENGINE" and is_equal_approx(fs.engine_pitch, 1.275),
		"engine running: StartEngine at (rpm + 0.5)·0.25 + 1 (%.3f)" % fs.engine_pitch)
	var p1: float = fs.engine_pitch
	fs.update(_state({"on_ground": true, "gear": 0.0, "rpm": 1.0}), _inp({"gear_down": true}))
	check(fs.engine_pitch > p1 and is_equal_approx(fs.engine_pitch, 1.375), "pitch rises with the RPM")
	fs.update(_state({"on_ground": true, "gear": 0.0, "rpm": 1.0, "afterburner": 1}), _inp({"gear_down": true}))
	check(fs.engine_code == "SFX_DRY_THRUST" and is_equal_approx(fs.engine_pitch, 0.8), "AB stage 1: burner at 0.8")
	fs.update(_state({"on_ground": true, "gear": 0.0, "rpm": 1.0, "afterburner": 2}), _inp({"gear_down": true}))
	check(fs.engine_code == "SFX_AFTERBURNER_THRUST" and is_equal_approx(fs.engine_pitch, 1.2), "AB stage 2: burner at 1.2")
	fs.queue_free()

	# Levers, warnings, touchdown.
	fs = FlightSounds.create(null, 100)
	root.add_child(fs)
	var t := 0.0
	fs.update(_state(), _inp())
	fs.update(_state(), _inp({"gear_down": true}))
	check(_count(fs, "SFX_LANDING_GEAR/None") == 1, "gear lever: SFX_LANDING_GEAR")
	fs.update(_state(), _inp({"gear_down": true, "flaps": 1.0}))
	check(_count(fs, "SFX_FLAPS/None") == 1, "flaps lever: SFX_FLAPS")
	fs.update(_state(), _inp({"gear_down": true, "flaps": 1.0, "brakes": true}))
	check(_count(fs, "SFX_SPEED_BREAKES/None") == 1 and _count(fs, "SFX_SPEED_BREAKES_LOOP/None") == 1,
		"air brake out in the air: open sound + loop")
	fs.update(_state({"drag_x": 1.2}), _inp({"gear_down": true}))
	check(_count(fs, "SFX_WARNING/WRN_AOA") == 1 and _count(fs, "SFX_SPEED_BREAKES/None") == 2,
		"dragX > 0.5 in the air: AoA tone; brake in: the open sound again")
	fs.update(_state({"drag_x": 1.2}), _inp({"gear_down": true}))
	check(_count(fs, "SFX_WARNING/WRN_AOA") == 1, "the AoA tone loops, not restarted")
	# Touchdown with the gear down and locked.
	fs.update(_state({"on_ground": true, "gear": 0.0}), _inp({"gear_down": true, "agl_m": 1.7}))
	check(_count(fs, "SFX_TOUCHDOWN/None") == 1, "touchdown: SFX_TOUCHDOWN (td.wav)")
	check(_count(fs, "VOC_BBETTY/BTY_ALT") == 0, "no altitude call with the gear handle down")
	# Betty "altitude": below 100 ft with the gear up, at once and every 4 s.
	for i in 5:
		fs.update(_state({"time": t}), _inp({"agl_m": 20.0}))
		t += 1.0
	check(_count(fs, "VOC_BBETTY/BTY_ALT") == 2, "altitude < 100 ft, gear up: Betty at 0 s and 4 s (%d)" % _count(fs, "VOC_BBETTY/BTY_ALT"))
	fs.update(_state({"time": t, "fuel_lbs": 900.0}), _inp())
	fs.update(_state({"time": t, "fuel_lbs": 800.0}), _inp())
	fs.update(_state({"time": t, "fuel_lbs": 400.0}), _inp())
	check(_count(fs, "VOC_BBETTY/BTY_FUEL") == 2, "fuel: once below 1000 lb, once below 500 lb")
	fs.update(_state({"time": t, "crashed": true}), _inp())
	check(_count(fs, "SFX_AIRCRAFT_EXPLODED/None") == 1 and fs.engine_code == "", "crash: explosion, engine stops")
	fs.queue_free()

	# Betty only on the types that carry it (FUN_00447280): the Mirage (190) has none.
	fs = FlightSounds.create(null, 190)
	root.add_child(fs)
	for i in 3:
		fs.update(_state({"time": float(i)}), _inp({"agl_m": 20.0}))
	check(_count(fs, "VOC_BBETTY/BTY_ALT") == 0, "Mirage: no Betty")
	fs.queue_free()

	# Preferences volumes and Mute on the buses.
	var s := Settings()
	s.engine_volume = 0.3
	s.sfx_volume = 0.5
	s.speech_volume = 0.7
	SoundBuses.apply()
	var ok := absf(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(SoundBuses.ENGINE)) - 0.3) < 0.01 \
		and absf(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(SoundBuses.SFX)) - 0.5) < 0.01 \
		and absf(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(SoundBuses.SPEECH)) - 0.7) < 0.01
	check(ok, "engine / effects / speech volumes follow the Preferences")
	SoundBuses.toggle_mute()
	check(s.mute and AudioServer.is_bus_mute(AudioServer.get_bus_index(SoundBuses.ENGINE)), "mute toggle mutes the buses")
	SoundBuses.toggle_mute()
	s.engine_volume = 0.8
	s.sfx_volume = 1.0
	s.speech_volume = 1.0
	SoundBuses.apply()

	# In flight: mission 311 starts on the ground with the engine off; "1" starts it.
	var tv = await start_mission(311)
	var node = tv.get_node_or_null("FlightSounds")
	check(node != null, "the flight scene has the sound component")
	if node == null:
		return
	await frames(2)
	check(node.engine_code == "SFX_LANDING", "ground start, engine off: no engine sound (%s)" % node.engine_code)
	key(tv, KEY_1)
	var t0 := Time.get_ticks_msec()
	while node.engine_code != "SFX_START_ENGINE" and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	check(node.engine_code == "SFX_START_ENGINE", "1 starts the engine sound")
	var pa: float = node.engine_pitch
	await frames(60)
	check(node.engine_pitch > pa, "engine pitch rises while the RPM spools up (%.3f -> %.3f)" % [pa, node.engine_pitch])
	check(tv._voice == null or tv._voice.bus == SoundBuses.SPEECH, "mission voices on the speech bus")
