# The voice cast (modern-iaf/docs/sound.md §3.2, the user, 25 Nov 2026: "for each mission, the voices not switched in
# the middle"): a mission's calls played interleaved (the tower, the player's calls, the wingmen #2-#4, the AWACS,
# another flight's friendly-fire call, the ejection), in English and Hebrew, for a pilot who picked a man's and a
# woman's radio voice: each speaker keeps one voice for the whole mission, the player's voice has the gender picked,
# no wingman speaks in the player's voice, and another mission may draw another cast.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_voice_cast.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	load("res://flight/fly.gd").start(2012)  # ramon_startup
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	var table = tv.sounds.table
	if table._he.is_empty() or table._he.get("en", {}).get("pilot", {}).is_empty():
		print("NEEDS DATA: the voices' casts with the player's English woman (iaf-sim own)")
		return
	var roles := {}  # clip file -> its role (voices.json: the same in both languages)
	var pilot_clips := []
	for c in settings().load_json("res://data/sounds/voices.json").clips:
		roles[String(c.file)] = String(c.get("role_he", c.voice))
		if c.voice == "pilot" and c.has("say") and c.has("say_he") and c.file.begins_with("plt_"):
			pilot_clips.append(String(c.file))
	check(pilot_clips.size() >= 10, "the player's calls in both languages: %d" % pilot_clips.size())
	var casts := {}
	for voice in [0, 1]:
		IafPilotLog.set_voice(s.records_db(), s.pilot(), voice)
		for mission in [2012, 2013, 2014, 2015]:
			for lang in ["en", "he"]:
				s.language = lang
				s.mission_id = mission
				table._cast = {}  # a new flight draws its cast (the pick changed on the Pilot screen)
				casts[[voice, mission]] = table.cast()
				_mission(tv, table, roles, pilot_clips.slice(0, 10), voice, "%s m%d %s" % [lang, mission, voice])
	check(casts[[0, 2012]] != casts[[1, 2012]], "the pick changes the cast")
	check(casts.values().any(func(c): return c != casts[[0, 2012]]), "another mission, another cast")
	IafPilotLog.set_voice(s.records_db(), s.pilot(), 0)
	s.language = "en"


## One mission's calls, three rounds of everyone, each clip's voice read from the path it plays.
func _mission(tv: Node, table, roles: Dictionary, pilot_clips: Array, voice: int, what: String) -> void:
	var r: Node = tv.radio
	table.heard = []
	for k in 3:
		r._speak(r.base_at(r._pos()), [0, 3, 6][k])
		tv.sounds.play_phrase_wav(pilot_clips[k * 3])
		for from in [2, 3, 4]:
			r.flight_call(from, ["ack", "lead_change", "fuel_state"][(from + k) % 3], 1800.0)
			tv.sounds.play_phrase_wav(pilot_clips[k * 3 + 1])
		tv.sounds.play_phrase_wav("awx_clean.ogg")
		tv.mission_voice("VOC_TARGET_SAY_FRIENDLY_HIT", {"key": "kidon 2-1"})
		tv.sounds.play_phrase_wav(pilot_clips[k * 3 + 2])
		tv.sounds.play_eject()
	var heard: Array = table.heard
	table.heard = null
	var by := {}  # speaker -> the voices heard
	for h in heard:
		var file := String(h[0]).get_basename() + ".ogg"
		var role: String = roles.get(file, "")
		if role in ["", "betty"]:
			continue  # the clicks, the gap, the pause
		var path := String(h[2])
		if settings().language == "he":
			check("/he/" in path, "%s: %s speaks Hebrew: %s" % [what, file, path])
		var v := "default"
		for part in ["/he/", "/en/"]:
			if part in path:
				v = path.get_slice(part, 1).get_slice("/", 0)
		var who := "%s#%d" % [role, h[1]] if role == "wingman" else role
		by[who] = by.get(who, {})
		by[who][v] = true
	for who in ["tower", "pilot", "awacs", "wingman#2", "wingman#3", "wingman#4"]:
		check(by.has(who), "%s: %s spoke: %s" % [what, who, by.keys()])
	for who in by:
		check(by[who].size() == 1, "%s: %s keeps one voice: %s" % [what, who, by[who].keys()])
	check(
		by.keys().filter(func(k): return k.begins_with("wingman#") and int(k.get_slice("#", 1)) >= 5).size() == 1,
		"%s: another flight's member speaks: %s" % [what, by.keys()]
	)
	var mine: String = by.get("pilot", {}).keys()[0] if by.has("pilot") else ""
	var he: bool = settings().language == "he"
	var want: Array = (["ariel"] if he else ["default"]) if voice == 0 else (["shira"] if he else ["af_sarah"])
	check(mine in want, "%s: the player's voice %s is the one picked (%s)" % [what, mine, want])
	if he:
		for who in by:
			if who.begins_with("wingman"):
				check(not by[who].has(mine), "%s: %s never in the player's voice %s" % [what, who, mine])
