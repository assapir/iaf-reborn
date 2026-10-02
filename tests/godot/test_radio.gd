# The radio (docs/radio.md): the phrase engine (phrasetemplates.trx / phraseparticalsdata.trx), the tower's state
# machine (FUN_00550ed0) and Ctrl+T (FUN_0054fb40), the wingman commands (FUN_0043f8d0) and the waypoint report.
extends "res://../tests/godot/base.gd"


class FakeFlight:
	extends RefCounted
	var st := {"on_ground": false, "speed": 200.0, "heading": 0.0, "gear": 1.569}

	func state() -> Dictionary:
		return st


class FakeHost:
	extends Node
	var flight = FakeFlight.new()
	var runtime = null
	var ai = null
	var sounds = null
	var weapons = null
	var pos := Vector3.ZERO
	var lines: Array[String] = []

	func player_world() -> Vector3:
		return pos

	func _on_subtitle(t: String) -> void:
		lines.append(t)

	func enemy_of_player(_e: Dictionary) -> bool:
		return false


func texts(r) -> Array:
	return r.said.map(func(p): return p.text)


func send(tv: Node, k: Key, ctrl := false, alt := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.alt_pressed = alt
	tv._unhandled_input(e)


func wait_sim(tv: Node, s: float) -> void:
	var t0: float = tv._sim_time
	while tv._sim_time - t0 < s:
		await process_frame


var _r: Node
var _t := 0.0


## Runs the stand-in radio `dt` s of sim time in 0.25 s frames.
func step(dt: float) -> void:
	var t1 := _t + dt
	while _t < t1:
		_t = minf(_t + 0.25, t1)
		_r.update(_t)


func console_has(tv: Node, line: String) -> bool:
	return tv._console.has(line)


func run() -> void:
	# --- the phrase engine ----------------------------------------------------------------------
	var r = load("res://audio/radio.gd").new()
	r._ready()
	var p: Dictionary = r.expand("ACFT_TAXI_TO_RUNWAY", ["Alpha_t", "MORNING"], [27])
	check(p.text == "Alpha, good morning, taxi to runway 27", "taxi phrase text (%s)" % p.text)
	check(p.wavs == ["Alpha_t", "Pause", "GMorning", "Pause", "Taxi2rwy", "Num027"], "taxi phrase parts (%s)" % [p.wavs])
	check(r.expand("ACFT_CLEAR_TO_LINEUP", ["CHARLIE_t", "WI_KNOTS15"], [9]).text == "Charlie, clear to line up on runway 9, wind is 15 knots", "line-up phrase with wind")
	check(r.expand("PASS_WAYPT_PHRASE", ["ALPHALEADER", "G2"]).text == "Alpha leader is passing waypoint 2", "waypoint report phrase")
	check(r.expand("WINGMAN_REPLY_NEGATIVE", ["NEGATIVE"]).text == "I'm afraid that's a negative, sir!", "negative reply")
	check(r.bases.size() == 10 and r.bases[0].rwy == 230 and r.bases[1].hangars.size() == 8, "iaf.ibx bases (Ramon rwy 230, David 8 hangars)")
	r.free()

	# --- the tower's state machine on a stand-in host (Ramon: tower, lineup, runway 23) ------------
	var h := FakeHost.new()
	root.add_child(h)
	r = load("res://audio/radio.gd").new()
	r.host = h
	r._ready()
	var ramon: Dictionary = r.bases[0]
	var hd := deg_to_rad(-130.0)
	var fwd := Vector3(sin(hd), cos(hd), 0.0)
	h.pos = ramon.tower + Vector3(0, 0, 1000)
	_r = r
	step(1.5)  # the first tick 1 s after the start (54f8f0)
	check(r.state == 2 and r.base == 0, "airborne near Ramon: state 2, base 0 (state %d base %d)" % [r.state, r.base])
	r.contact_tower()
	check(texts(r).has("Alpha, proceed to runway 23") and r.state == 3, "Ctrl+T in the air: proceed to runway 23, state 3")
	check(r.said[-1].template == "ACFT_ROGER" and r.said[-1].text == "Roger" and not h.lines.has("Roger"), "the pilot's Roger is spoken, not printed")
	h.pos = ramon.lineup - fwd * 8000.0 + Vector3(0, 0, 400)
	h.flight.st.heading = -130.0
	step(1.0)
	check(texts(r).has("Alpha, your gear is not down"), "on the approach with the gear up: gear not down")
	h.flight.st.gear = 0.0
	step(1.0)
	check(texts(r).has("Alpha, you are cleared to land on runway 23, no wind"), "gear down: cleared to land (no wind)")
	var n: int = r.said.size()
	step(3.0)
	check(r.said.size() == n, "the clearance is said once")
	h.pos = ramon.lineup
	h.flight.st.on_ground = true
	h.flight.st.speed = 10.0
	step(1.0)
	check(texts(r).has("Alpha, nice to have you back taxi to hangar") and r.state == 1, "rolled out: taxi to hangar, state 1")
	# Airborne again, a new approach, then off the corridor's heading after the clearance: back to state 2.
	r.last = 0xb
	h.flight.st.on_ground = false
	h.flight.st.speed = 150.0
	step(1.0)
	r.contact_tower()
	h.pos = ramon.lineup - fwd * 8000.0 + Vector3(0, 0, 400)
	step(1.0)
	h.flight.st.heading = 50.0
	step(1.0)
	check(r.state == 2, "turned away after the clearance: state 2 (state %d)" % r.state)
	# On the ground (the last message reset, as after 30 s standing): 300 m beside the runway's lineup: clear to
	# line up; at the lineup, lined up: clear to take-off.
	h.flight.st.on_ground = true
	h.flight.st.speed = 0.0
	h.flight.st.heading = -130.0
	r.last = 0xb
	h.pos = ramon.lineup + Vector3(fwd.y, -fwd.x, 0) * 300.0
	step(2.0)
	check(texts(r)[-2] == "Alpha, clear to line up on runway 23, no wind", "300 m from the lineup: clear to line up (%s)" % texts(r)[-2])
	h.pos = ramon.lineup + Vector3(0, 0, 2)
	step(1.0)
	check(texts(r)[-2] == "Alpha, clear to take-off", "lined up at the lineup: clear to take-off (%s)" % texts(r)[-2])
	n = r.said.size()
	r.contact_tower()
	step(2.0)
	check(r.said.size() == n, "Ctrl+T on the ground at an Israeli base: nothing")
	step(31.0)
	check(r.said.size() == n + 2 and texts(r)[-2] == "Alpha, clear to take-off", "standing still 30 s: the tower repeats")
	# Far from every tower: Ctrl+T only clicks.
	h.pos = Vector3(100000, 100000, 3000)
	h.flight.st.on_ground = false
	step(5.0)
	check(r.base == -1, "far away: no base")
	n = r.said.size()
	r.contact_tower()
	check(r.said.size() == n + 1 and r.said[-1].template == "KCH2" and r.said[-1].text == "", "Ctrl+T far away: the radio click, no text")
	h.free()

	# --- in flight: the tower at a hangar (313, Ramat David), Hebrew mode keeps the data's text ------
	Settings().language = "he"
	var tv = await start_mission(313)
	await wait_sim(tv, 2.5)
	var line := "Alpha, good morning, taxi to runway 27"
	check(texts(tv.radio).has(line), "313 at the hangar: %s" % line)
	check(console_has(tv, line), "the subtitle is in the console (Hebrew mode: the data's English text)")
	for w in ["alpha_t.wav", "gmorning.wav", "taxi2rwy.wav", "num027.wav", "roger.wav"]:
		check(tv.sounds.played.has(w), "spoken: %s" % w)
	n = tv.radio.said.size()
	send(tv, KEY_T, true)
	await wait_sim(tv, 2.0)
	check(tv.radio.said.size() == n and not tv.sounds.played.has("kch2.wav"), "Ctrl+T on the ground at the base: no answer (the tower talks by itself)")
	Settings().language = "en"

	# --- 211: lined up on Ramat David's runway 27; the wingman still on the ground says negative -----
	tv = await start_mission(211)
	await wait_sim(tv, 2.5)
	check(texts(tv.radio).has("Alpha, clear to take-off"), "211 at the lineup: clear to take-off")
	var me: Dictionary = tv.runtime.player_entity()
	var wing: Dictionary = tv.ai.partner_of(me)
	check(not wing.is_empty() and wing.has("pilot") and tv.ai.on_ground(wing), "the wingman is an AI jet on the ground")
	send(tv, KEY_C, false, true)
	check(console_has(tv, "Close formation."), "Alt+C: the pilot says close formation")
	await wait_sim(tv, 3.2)
	check(console_has(tv, "I'm afraid that's a negative, sir!") and wing.pilot.brain.wingman_command == 0, "wingman on the ground: negative after 3 s, no command")

	# --- 221: airborne by Ramon; Ctrl+T, the wingman commands, the radio click far away ------------
	tv = await start_mission(221)
	await wait_sim(tv, 1.5)
	send(tv, KEY_T, true)
	check(texts(tv.radio).has("Alpha, proceed to runway 23") and tv.sounds.played.has("prcd2rwy.wav"), "221 Ctrl+T in the air: proceed to runway 23")
	me = tv.runtime.player_entity()
	wing = tv.ai.partner_of(me)
	var b = wing.pilot.brain
	# From a sub-brain the command goes back to the base list, which answers it (setRules keeps +0x48).
	var cmds := [[KEY_C, 6, "Close formation.", "Roger, closing formation.", 1], [KEY_T, 5, "Tactical formation.", "Roger, going tactical.", 3],
		[KEY_B, 2, "Bug out.", "Roger, bugging out.", 8]]
	for c in cmds:
		send(tv, c[0], false, true)
		check(console_has(tv, c[2]) and b.wingman_command == c[1], "Alt+%s: %s, the wingman's command %d" % [OS.get_keycode_string(c[0]), c[2], b.wingman_command])
		await wait_sim(tv, 4.5)
		check(console_has(tv, c[3]), "the wingman's brain answers: %s" % c[3])
		check(wing.pilot.mode == c[4], "the wingman's mode %d (%d)" % [c[4], wing.pilot.mode])
	# No threat, no radar target, nothing to engage: negative, the command is kept.
	for k in [KEY_P, KEY_E]:
		var was: int = b.wingman_command
		send(tv, k, false, true)
		await wait_sim(tv, 3.2)
		check(b.wingman_command == was and tv.radio.said[-1].text == "I'm afraid that's a negative, sir!", "Alt+%s without a target: negative" % OS.get_keycode_string(k))
	var any: Dictionary = tv.radio.engage_any(wing)
	await wait_sim(tv, 1.6)
	send(tv, KEY_W, false, true)
	# FUN_004a4cf0 is "another side": near Ramon the nearest such unit can be a side-0 object (original quirk).
	check((b.wingman_command == 4 and is_same(b.target, any)) == not any.is_empty(), "Alt+W: engage the nearest other-side unit within 9.27 km (%s)" % any.get("name", "none"))
	await wait_sim(tv, 3.2)
	# The player's waypoint report.
	tv.waypoint_passed(2)
	await wait_sim(tv, 3.2)
	check(console_has(tv, "Alpha leader is passing waypoint 2") and tv.sounds.played.has("gpaswpnt.wav"), "waypoint report 3 s later")
	# The ejection's report (EjectReport): "<callsign> ejected".
	tv.radio.ejected(me)
	check(console_has(tv, "Alpha leader ejected") and tv.sounds.played.has("gejected.wav"), "eject report: Alpha leader ejected")
	tv.player_world_override = Vector3(100000, 100000, 3000)
	await wait_sim(tv, 5.0)
	send(tv, KEY_T, true)
	check(tv.sounds.played.has("kch2.wav"), "Ctrl+T far from a tower: the radio click")
	tv.player_world_override = null
