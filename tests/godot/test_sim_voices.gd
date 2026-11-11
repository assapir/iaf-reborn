# Extras "Extra sounds" and "Real Betty" on Modern IAF's own sound set (docs/sound.md §7, docs/real-betty.md §7): the
# sim's effect clips for the codes it covers (the engine's kept) and the original's for the rest; Betty's calls per
# real jet; the sim's tower phrases over the original's, keyed, every base's tower talking. Both rows off: the
# original's table and radio.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn -s ../tests/godot/test_sim_voices.gd
extends "res://../tests/godot/base.gd"

var flight_sounds: GDScript


## The file a FlightSounds of bdb type `type` plays for VOC_BBETTY `sub` ("" silent).
func _betty(type: int, sub: String) -> String:
	var fs = flight_sounds.create(null, type)
	root.add_child(fs)
	var file := ""
	if fs.play("VOC_BBETTY", sub) != null:
		var r: Dictionary = fs.table.row("VOC_BBETTY", sub)
		if fs._betty_set != "original":
			r = fs.table.betty_rows.get(fs.betty_call(sub), {})
		file = String(r.file).to_lower()
	fs.free()
	return file


func run() -> void:
	await require_data()
	var s := settings()
	if s.sim_sounds() == "":
		print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
		await _quit(2)
		return
	flight_sounds = load("res://shared/audio/flight_sounds.gd")
	var table_script: GDScript = load("res://shared/audio/sound_table.gd")
	var orig = table_script.load_table()
	check(orig.betty_rows.is_empty(), "rows off: no Modern IAF Betty rows")
	check(not s.radio_key_clicks(), "rows off: the radio is not keyed")
	check(not String(orig._files.get("kch2.wav", "")).contains("converted/own"), "rows off: the original's files")
	# --- Extra sounds ---------------------------------------------------------------------------
	s.extra_sounds = "modern"
	var fx = table_script.load_table()
	check(String(fx.row("SFX_FLAPS").file).to_lower().begins_with("sfx_flaps"), "Extra sounds: the sim's flaps clip")
	check(fx.stream(fx.row("SFX_FLAPS")) != null, "Extra sounds: the sim's flaps clip loads")
	check(fx.stream_file("cock_g_02.wav") is AudioStreamOggVorbis, "Extra sounds: the sim's G strain by its .wav name")
	check(fx.row("SFX_DRY_THRUST") == orig.row("SFX_DRY_THRUST"), "Extra sounds: the original's engine loop")
	var bad := []
	for key in orig.rows:
		if not fx.rows.has(key) or (orig.rows[key].category in ["V", "S"] and fx.rows[key] != orig.rows[key]):
			bad.append(key)
	check(bad.is_empty(), "Extra sounds: every original row kept or replaced, the voices untouched %s" % [bad])
	check(fx.betty_rows.is_empty(), "Extra sounds: the game's Betty")
	s.extra_sounds = "original"
	# --- Real Betty -----------------------------------------------------------------------------
	s.real_betty = "modern"
	check(s.radio_key_clicks(), "Real Betty: the radio is keyed")
	check(_betty(100, "BTY_FIRE") == "voc_bbetty_warning.ogg", "Real Betty F-16: fire is WARNING")
	check(_betty(100, "BTY_MISS") == "", "Real Betty F-16: no missile call")
	check(_betty(1000, "BTY_PULL_UP") == "voc_bbetty_pull_up.ogg", "Real Betty F-35I: PULL UP")
	check(_betty(110, "BTY_CAUTION") == "voc_bbetty_caution.ogg", "Real Betty F-15: CAUTION")
	check(_betty(110, "BTY_ALT") == "", "Real Betty F-15: no altitude call")
	check(_betty(190, "BTY_FUEL") == "", "Real Betty Mirage: no voice")
	var lavi := _betty(140, "BTY_ALT")
	check(lavi != "" and not lavi.begins_with("voc_"), "Real Betty Lavi: the game's Betty (%s)" % lavi)
	var radio_script: GDScript = load("res://shared/audio/radio.gd")
	var radio = radio_script.new()
	radio._ready()
	check(radio.tower_count == radio.bases.size() and radio.bases.size() >= 10, "Real Betty: every base's tower talks")
	var p: Dictionary = radio.expand("ACFT_TAXI_TO_RUNWAY", ["Alpha_t", "MORNING"], [27])
	check(
		p.wavs.size() > 0 and String(p.wavs[0]).begins_with("twr_"), "Real Betty: the sim's taxi call (%s)" % [p.wavs]
	)
	check(radio.templates.has("SHOT_ENEMY"), "Real Betty: the original's other phrases stay")
	radio.free()
	s.real_betty = "original"
	radio = radio_script.new()
	radio._ready()
	check(radio.tower_count == 4, "Real Betty off: the original's four talking towers")
	radio.free()
