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
	# The readback (the user, 17 Nov 2026: "the readback and not only "roger""): the player's own voice reads the
	# clearance back, the callsign last, in one clip for Kidon 1; no "Roger" (sound.md §3).
	var rb: Array = said.filter(func(p): return p.template == "RB_ACFT_CLEAR_TO_START")
	check(
		rb.size() == 1 and rb[0].wavs == ["plt_rb_start_kidon1.ogg"] and rb[0].text == "Cleared to start, Kidon 1",
		"the readback: %s" % [rb]
	)
	check(not said.any(func(p): return p.template == "ACFT_ROGER"), "no roger after a clearance")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000 and band[-1] != "Cleared to start, Kidon 1":
		await process_frame
		band = tv.addon.ui.band_texts()
	check(band[-1] == "Cleared to start, Kidon 1", "the band: the readback as the player says it: %s" % [band])
	# The taxi greeting by the mission's clock.
	var at: int = r.base_at(r._pos())
	# Every clearance read back at Ramon's 25R; the take-off clearance with the wind and the runway (AMC-69 §3.6).
	var backs := {
		0: ["plt_rb_taxi_25r_kidon1.ogg", "Taxi to runway 25 right, Kidon 1"],
		1: ["plt_rb_lineup_25r_kidon1.ogg", "Line up runway 25 right, Kidon 1"],
		3: ["plt_rb_holding_kidon1.ogg", "Holding, Kidon 1"],
		4: ["plt_rb_takeoff_25r_kidon1.ogg", "Cleared for take-off runway 25 right, Kidon 1"],
		5: ["plt_rb_proceed_25r_kidon1.ogg", "Proceed to runway 25 right, Kidon 1"],
		6: ["plt_rb_land_25r_kidon1.ogg", "Cleared to land runway 25 right, Kidon 1"],
		8: ["plt_rb_go_around_kidon1.ogg", "Going around, Kidon 1"],
		9: ["plt_rb_park_kidon1.ogg", "Taxi to parking, Kidon 1"],
		10: ["acft_roger.ogg", ""],
	}
	for code in backs:
		var n1: int = r.said.size()
		var tw: Dictionary = r._speak(at, code)
		var back: Dictionary = r.said[-1]
		check(
			r.said.size() == n1 + 2 and back.wavs == [backs[code][0]] and back.text.begins_with(backs[code][1]),
			"%s read back: %s %s" % [tw.text, back.wavs, back.text]
		)
	var to: Dictionary = r._speak(at, 4)
	check(
		(
			to.text == "Kidon 1, wind calm, runway 25 right, cleared for take-off"
			and to.wavs == ["twr_to_kidon1_calm_rwy.ogg", "rwy25r.ogg", "twr_pause.ogg", "twr_takeoff.ogg"]
		),
		"the take-off clearance: %s %s" % [to.text, to.wavs]
	)
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
	_every_seat(tv, r)
	_hebrew(tv, r, at)


## Every seat (sound.md §3, Kidon 1 to 8): the pilot's call to a tower and the tower's calls each one clip; the
## callsign's particles for the tower, the pilot and the AWACS; in Hebrew each its own clip.
func _every_seat(tv: Node, r: Node) -> void:
	check(r.kidon("Hotel") == "Kidon 7" and r.kidon("India") == "Kidon 8", "Hotel and India are Kidon 7 and 8")
	for i in r.KIDONS.size():
		var cs: String = r.KIDONS[i]
		var n: int = i + 1
		var call: Dictionary = r.expand("PILOT_CALL", ["NEVATIM_TWR", cs + "_P", "REQ_TAKEOFF"])
		check(call.wavs == ["plt_nevatim_kidon%d_takeoff.ogg" % n], "Kidon %d's call in one clip: %s" % [n, call.wavs])
		for t in [["ACFT_HOLD_POS", []], ["ACFT_NEGATIVE", ["FIRST_TAXI"]], ["ACFT_NO_TAXI_CLEARANCE", []]]:
			var p: Dictionary = r.expand(t[0], [cs + "_t"] + t[1])
			check(p.wavs.size() == 1, "%s to Kidon %d in one clip: %s" % [t[0], n, p.wavs])
		var head: Dictionary = r.expand("ACFT_PROCEED_TO_RUNWAY", [cs + "_t"], [12])
		check(head.wavs == ["twr_kidon%d_proceed_rwy.ogg" % n, "num012.ogg"], "Kidon %d: head, runway" % n)
		check(String(r.particles.get(cs.to_upper() + "_R", [""])[0]) == "awx_kidon%d.ogg" % n, "AWACS Kidon %d" % n)
	if tv.sounds.table._he.is_empty():
		return
	settings().language = "he"
	for n in range(1, r.KIDONS.size() + 1):
		for f in ["twr_kidon%d.ogg", "plt_kidon%d.ogg", "awx_kidon%d.ogg"]:
			check(tv.sounds.table.hebrew(f % n) != "", "a Hebrew clip %s" % (f % n))
	settings().language = "en"


## Hebrew (sound.md §3.1): every tower call and every wingman call plays a Hebrew clip in the voice the mission's cast
## gives its role (a wingman's own voice for his call), the callsign as its own clip; only the computed clicks, pause
## and gap are the same in both languages.
func _hebrew(tv: Node, r: Node, at: int) -> void:
	var table = tv.sounds.table
	if table._he.is_empty():
		print("NEEDS DATA: the Hebrew clips (iaf-sim own)")
		return
	settings().language = "he"
	var cast: Dictionary = table.cast()  # sound_table.gd: the cast the pilot's radio voice and the mission id draw
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
