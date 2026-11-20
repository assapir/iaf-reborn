# Modern IAF's radio menu calls (modern-iaf/docs/training.md §8, sound.md §3): the pilot's own call in the pilot's
# voice first (key_on, its clip, key_off), the 0.6 s gap (radio_gap.ogg), then the tower's answer; the band shows the
# pilot's line then the tower's. The taxi greeting follows the mission's clock (misc 0x460 + the sim time, docs/radio.md
# §2 code 0; the sim's table, Settings.tower_greeting): 08:00 good morning, 14:00 and 16:00 good afternoon, 20:00
# and 23:00 good evening, 04:00 good evening.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_radio_calls.gd --log-file <temp>
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
	var r: Node = tv.radio
	var played: Array = tv.sounds.played
	var n0 := played.size()
	var said0: int = r.said.size()
	check(tv.addon.pick("startup") == "ACFT_CLEAR_TO_START", "start-up: the tower clears the start")
	var said: Array = r.said.slice(said0)
	check(said.size() >= 2 and said[0].template == "PILOT_CALL", "the pilot's call is said first: %s" % [said])
	check(
		said[0].wavs == ["plt_ramon_kidon1_start.ogg"],
		'the pilot says "Ramon tower, Kidon 1, request start-up" in one clip: %s' % [said[0].wavs]
	)
	var seq: Array = played.slice(n0)
	var want := ["key_on.ogg", "plt_ramon_kidon1_start.ogg", "key_off.ogg", "radio_gap.ogg", "key_on.ogg"]
	check(seq.slice(0, 5) == want, "call, key-off, the gap, then the tower keys on: %s" % [seq])
	check(seq.has("twr_kidon1_start.ogg"), "then the tower's answer: %s" % [seq])
	# The subtitles show as each voice starts (the user, 2026-11-13): the tower's not with the pilot's.
	var band: Array = tv.addon.ui.band_texts()
	check(
		not band.any(func(t): return "cleared to start" in t.to_lower()),
		"the tower's line waits for its voice: %s" % [band]
	)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		band = tv.addon.ui.band_texts()
		if band.size() >= 2 and "cleared to start" in band[-1].to_lower():
			break
		await process_frame
	check(
		band.size() >= 2 and "request start-up" in band[-2] and "cleared to start" in band[-1].to_lower(),
		"the band: the pilot's line, then the tower's as it speaks: %s" % [band]
	)
	# The taxi greeting by the mission's clock.
	var at: int = r.base_at(r._pos())
	# Every tower names its take-off end as painted and signed (iaf.ibx RunwayDesignator), not RunwayNumber / 10.
	var ends := {"Ramon": "25R", "David": "27", "TelNof": "33L", "Hatzerim": "28L", "Nevatim": "26L"}
	for b in r.bases:
		check(b.designator == ends.get(b.name), "%s tower: runway %s" % [b.name, b.designator])
	var keep: String = r.runway
	r.runway = ""
	var nv: Dictionary = r._speak(r.bases.map(func(b): return b.name).find("Nevatim"), 5)
	print("Nevatim clearance: ", nv.text)
	check("26" in String(nv.text) or "six" in String(nv.text).to_lower(), "Nevatim: %s" % nv.text)
	r.runway = keep
	for hg in [
		[8, "good morning"],
		[14, "good afternoon"],
		[16, "good afternoon"],
		[20, "good evening"],
		[23, "good evening"],
		[4, "good evening"]
	]:
		tv.runtime.misc["0x460"] = float(hg[0]) * 3600.0
		var p: Dictionary = r._speak(at, 0)
		check(String(hg[1]) in String(p.text).to_lower(), "%02d:00: %s" % [hg[0], p.text])
	_hebrew(tv, r, at)


## Hebrew (sound.md §3.1): every tower call and every wingman call plays a Hebrew clip in the voice the mission's cast
## gives its role (a wingman's own voice for his call), the callsign as its own clip; only the computed clicks, pause
## and gap are the same in both languages.
func _hebrew(tv: Node, r: Node, at: int) -> void:
	var table = tv.sounds.table
	if table._he.is_empty():
		print("NEEDS DATA: the Hebrew clips (iaf-sim own)")
		return
	settings().language = "he"
	var cast: Dictionary = table._he.casts[posmod(settings().mission_id, table._he.casts.size())]
	var plain := ["key_on.ogg", "key_off.ogg", "twr_pause.ogg", "radio_gap.ogg", "kch2.ogg"]
	var calls := [[0, ""], [1, ""], [3, ""], [4, ""], [5, ""], [6, ""], [8, ""], [9, ""], [10, ""], [12, ""]]
	for from in [2, 3, 4]:
		for id in ["ack", "lead_change", "fuel_state"] + r.WING_WORDS.keys():
			calls.append([from, id])
	var clips := 0
	for c in calls:
		var n0: int = r.said.size()
		if c[1] == "":
			r._speak(at, c[0])
		else:
			r.flight_call(c[0], c[1], 1800.0)
		for p in r.said.slice(n0):
			for w in p.wavs:
				var he: String = table.hebrew(w.to_lower())
				clips += 1
				check(w in plain or he != "", "%s %s: a Hebrew clip for %s" % [c, p.template, w])
				if c[1] != "" and he != "" and p.template.begins_with("WNG"):
					var v: String = cast.wingman[c[0] - 2]
					check(he.contains("/he/%s/" % v), "#%d's call in his voice %s: %s" % [c[0], v, he])
		if c[0] == 0 and c[1] == "":
			var w0: Array = r.said[n0].wavs
			check(
				w0.slice(0, 3) == ["twr_kidon1.ogg", "twr_pause.ogg", "twr_taxi_evening.ogg"],
				"callsign apart: %s" % [w0]
			)
			check(table.hebrew("twr_kidon1.ogg").contains("/he/%s/" % cast.tower), "the cast's tower voice")
	print("Hebrew: %d calls, %d clips" % [calls.size(), clips])
	settings().language = "en"
