# Better physics "Wind and turbulence": the tower's runway into the wind (docs/autopilot.md §2.4). A wind at least 5 kt
# from behind a base's main runway turns the base to the runway's other end: the tower says that number (with a
# parallel runway's letter in World scale Real), the taxi signs show it, a mission's jets lined up on the runway
# move to the other end's lineup. Off: calm, the switch off, NO WIND or a training mission.
extends "res://../tests/godot/base.gd"

const DAVID_27 := Vector3(356483, 602383, 63)


func turned(name: String) -> PackedFloat64Array:
	return ClassDB.class_call_static("IafBases", "into_wind", name)


## The tower's taxi call at base `i` (a fresh radio over the bases as now turned).
func taxi_call(i: int) -> Dictionary:
	var r = load("res://audio/radio.gd").new()
	r._ready()
	var host := Node.new()  # no runtime, no AI: the callsign "Alpha", the morning
	r.host = host
	r.base = i
	r._say(0)
	var p: Dictionary = r.said[0]
	r.free()
	host.free()
	return p


func run() -> void:
	var s := settings()
	var mr: GDScript = load("res://mission/mission_runtime.gd")
	var tv: GDScript = load("res://terrain/terrain_view.gd")
	s.better["wind"] = true
	s.sync_bases()

	# --- Present: a 10 kt easterly turns Ramat David (27) to 09; TelNof (09) keeps its own -----------------------
	s.runway_wind(114, {"0x46a": 10, "0x474": 90})
	var d := turned("David")
	check(d.size() == 4 and int(d[3]) == 90 and absf(d[0] - 353563.0) < 30.0, "David turned to 09 (%s)" % d)
	check(turned("TelNof").is_empty(), "TelNof keeps 09")
	var p := taxi_call(1)
	check(p.text.ends_with("taxi to runway 9") and "Num009" in p.wavs, "the tower: taxi to runway 9 (%s)" % p.text)
	var sign := {"world": DAVID_27}
	check(tv._real_sign_label("stationary/rw_ul_1/signdvid.gltf", sign) == "09", "David's taxi signs show 09")
	# A jet lined up on 27 and its wingman 60 m behind move to 09's lineup, turned round.
	var m := {
		"entities":
		{
			"items":
			[
				{"0x2e4": DAVID_27.x, "0x2ee": DAVID_27.y, "0x2f8": 63.0, "0x302": 270.0},
				{"0x2e4": DAVID_27.x + 60.0, "0x2ee": DAVID_27.y, "0x2f8": 63.0, "0x302": 270.0},
				{"0x2e4": DAVID_27.x, "0x2ee": DAVID_27.y, "0x2f8": 2000.0, "0x302": 270.0},
			]
		}
	}
	mr._into_wind(114, m, false)
	var e: Array = m.entities.items
	check(
		absf(e[0]["0x2e4"] - d[0]) < 1.0 and int(e[0]["0x302"]) == 90 and absf(e[1]["0x2e4"] - (d[0] - 60.0)) < 1.0,
		"lined-up jets moved to 09's lineup (%.0f, %.0f)" % [e[0]["0x2e4"], e[1]["0x2e4"]]
	)
	check(e[2]["0x2e4"] == DAVID_27.x, "an airborne jet stays")

	# --- no turn: calm, NO WIND, a training mission, the switch off ---------------------------------------------
	s.clear_runway_wind()
	s.runway_wind(115, {"0x46a": 0, "0x474": 90})
	check(turned("David").is_empty(), "calm: David keeps 27")
	s.clear_runway_wind()
	s.no_wind = true
	s.runway_wind(115, {"0x46a": 10, "0x474": 90})
	check(turned("David").is_empty(), "NO WIND: David keeps 27")
	s.no_wind = false
	s.clear_runway_wind()
	s.runway_wind(312, {"0x46a": 10, "0x474": 90})
	check(turned("David").is_empty(), "training 312 keeps its runway")
	s.clear_runway_wind()
	s.better["wind"] = false
	s.runway_wind(115, {"0x46a": 10, "0x474": 90})
	check(turned("David").is_empty() and s.flight_wind.is_empty(), "the switch off: no turn, the radio picks")
	check(taxi_call(1).text.ends_with("taxi to runway 27"), "the switch off: taxi to runway 27")

	# --- World scale Real: Ramon's 25L turned to 07R, said "7 right" -------------------------------------------
	s.better["wind"] = true
	s.world_scale = "real"
	check(s.sync_bases(), "World scale Real set up")
	s.clear_runway_wind()
	s.runway_wind(115, {"0x46a": 15, "0x474": 70})
	check(not turned("Ramon").is_empty(), "Ramon turned")
	p = taxi_call(0)
	check(
		p.text.ends_with("taxi to runway 7 right") and p.wavs.slice(-2) == ["Num007", "RwyR"],
		"the tower: taxi to runway 7 right (%s %s)" % [p.text, p.wavs]
	)
	var ramon: PackedFloat64Array = s.base_moved(317547.0, 411215.0)
	check(
		tv._real_sign_label("stationary/rw_ul_1/signrmon.gltf", {"world": Vector3(ramon[0], ramon[1], 0)}) == "07R",
		"Ramon's taxi signs show 07R"
	)
	s.clear_runway_wind()
	check(taxi_call(0).text.ends_with("taxi to runway 25 left"), "Real, no turn: taxi to runway 25 left")
	s.world_scale = "original"
	s.sync_bases()
