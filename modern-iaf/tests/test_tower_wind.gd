# The runway for the wind in Modern IAF (docs/autopilot.md §2.4; the user, 21 Oct 2026: "can we do that the tower will
# give us the right runway for the wind?"): a 15 kt wind from 066° turns Ramon's 25R to 07L. The tower names 07L in
# its calls (the take-off clearance with the wind), the player reads it back, the kneeboard and the front end name it,
# and the bases the AI flies are turned. The four-ship's ground run on the turned runway is
# crates/iaf-ai/tests/four_ship.rs ground_run_at_ramon_into_the_wind.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_tower_wind.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	# The front end: a mission's runway turned into its wind (IafBriefing.runway_in_use, the tower's rule).
	var fe: GDScript = load("res://menu/front_end.gd")
	var m := {"runway": "25R", "wind_kt": 15, "wind_from": 66, "start": {"base": "Ramon"}}
	check(fe.into_wind(m.duplicate(true)).runway == "07L", "the front end: 25R in a wind from 066° is 07L")
	m.wind_from = 246
	check(fe.into_wind(m.duplicate(true)).runway == "25R", "a headwind on 25R keeps it")
	m.wind_from = 336
	check(fe.into_wind(m.duplicate(true)).runway == "25R", "exactly 90° off keeps it")
	# The flight: the four-ship at Ramon with the wind set for it (Settings.runway_wind keeps a wind picked for the id).
	s.flight_wind = [15, 66]
	s._flight_wind_id = 2014
	load("res://flight/fly.gd").start(2014)  # ramon_four_ship
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	var iw: PackedFloat64Array = IafBases.into_wind("Ramon")
	check(iw.size() == 4 and int(iw[3]) == 66, "the tower turned Ramon: lineup and heading %s" % iw)
	var r: Node = tv.radio
	var at: int = r.bases.map(func(b): return b.name).find("Ramon")
	check(at >= 0 and r.bases[at].turned and r.bases[at].designator == "07L", "the radio's Ramon flies 07L")
	check(tv.addon.runway_in_use() == "07L", "the kneeboard's runway: %s" % tv.addon.runway_in_use())
	var taxi: Dictionary = r._speak(at, 0)
	var back: Dictionary = r.said[-1]
	check(taxi.text.ends_with("taxi to runway 7 left"), "the tower: %s" % taxi.text)
	check(
		back.text == "Taxi to runway 7 left, Kidon 1" and back.wavs == ["plt_rb_taxi_07l_kidon1.ogg"],
		"the readback: %s %s" % [back.text, back.wavs]
	)
	var to: Dictionary = r._speak(at, 4)
	check(
		to.text == "Kidon 1, wind 070 degrees, 15 knots, runway 7 left, cleared for take-off",
		"the take-off clearance: %s" % to.text
	)
	check("twr_wdir070.ogg" in to.wavs and "twr_wind15.ogg" in to.wavs, "the wind's clips: %s" % [to.wavs])
	check(r.said[-1].wavs == ["plt_rb_takeoff_07l_kidon1.ogg"], "its readback: %s" % [r.said[-1].wavs])
	# The landing clearance with the wind as well; a wind from 002° is "360" (north, ICAO's form).
	var keep: int = r.wind_from
	r.wind_from = 2
	var land: Dictionary = r._speak(at, 6)
	check(land.text == "Kidon 1, cleared to land runway 7 left, wind 360 degrees, 15 knots", "landing: %s" % land.text)
	r.wind_from = keep
	# The line-up call is made at the holding point of the runway's entry (25R's lineup), where the backtrack down the
	# runway to 07L starts; far from both ends the tower holds the jet.
	var entry: Vector3 = r.entry_of(at)
	check(entry.distance_to(r.bases[at].lineup) > 2000.0, "the entry is the runway's other end (%s)" % entry)
	tv.player_world_override = entry + Vector3(0, 90, 0)
	check(r.request("lineup").template == "ACFT_CLEAR_TO_LINEUP", "line-up cleared at the entry: %s" % r.said[-2].text)
	tv.player_world_override = entry + Vector3(1500, 1500, 0)
	check(r.request("lineup").template == "ACFT_HOLD_POS", "held far from the runway: %s" % r.said[-2].text)
	tv.player_world_override = null
	s.clear_runway_wind()
