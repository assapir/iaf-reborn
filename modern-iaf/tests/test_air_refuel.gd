# Air refuelling (modern-iaf/docs/research/air-refuelling.md §8), headless: mission ramon_four_ship, a KC-46A placed on
# its track by the hook shared/ai/tanker.gd `place`, the flight in the air beside it at 30,000 ft (ai_flights.gd
# `flight_in_air`).
#   - The player: the radio menu's Tanker page (only with a tanker), "Request refuelling" and the tanker's "cleared
#     pre-contact"; the door (Shift + F1, command 296; the F-16's AIR REFUEL switch and RDY lamp); held at
#     pre-contact (the test holds the jet: tanker.gd `test_player_state`): "cleared contact"; at the contact position
#     the boom latches ("contact", AR/NWS), the fuel rises at 3,000 lb a minute, the PDLs centred; A/R DISC (Shift
#     + F2, command 297): "disconnect" and the DISC lamp; full: "refuelling complete".
#   - The AI wingmen: "Refuel" to the flight from the radio menu; each acknowledges, refuels in turn on the 6-DoF
#     (cleared, contact, complete), and all rejoin the flight once the last is done.
#   - The tanker is a friendly contact on the radar's units.
#   - The notebook's AIR REFUEL tab (training.md §11) only with a tanker; its items tick: MASTER ARM OFF and the door
#     open (BEFORE CONTACT), the contact, the door closed (AFTER REFUELLING).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_air_refuel.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const TIME_SCALE := 4.0
## The track's speed, m/s (480 kt), its height, m (tanker.rs TRACK_SPEED, TRACK_ALT).
const SPEED := 246.9
const ALT := 9144.0
## Each wingman's room, kg (its fuel taken below its internal tanks' by this much).
const ROOM := 500.0

var _tv: Node


func run() -> void:
	var s := settings()
	var id := sim_mission("ramon_four_ship")
	if id < 0:
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	s.language = "en"
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground or tv.get("addon") == null:
		await process_frame
		tv = current_scene
	await frames(2)
	tv.addon.rules = {}  # unscored
	_tv = tv
	var ai = tv.ai
	if ai.flight_ai == null:
		check(false, "IafAi flies the four-ship")
		return
	check(not "m:tanker" in _top(tv), "no Tanker line without a tanker")
	check(not "refuel" in _tabs(tv), "no AIR REFUEL tab without a tanker (%s)" % [_tabs(tv)])
	# The tanker's track northbound from 20 km south of the jet; the jet 1 km behind it.
	var w: Vector3 = tv.player_world()
	var tk: Node = load("res://shared/ai/tanker.gd").place(tv, "kc46", Vector3(w.x, w.y - 20000.0, 0.0), 0.0)
	check(tk != null and tv.tanker == tk, "the tanker placed (hook)")
	if tk == null:
		return
	var pose: Dictionary = tk.tk.pose()
	var pos: Vector3 = pose.position - pose.forward * 1000.0 + Vector3(-300.0, -50.0, 0.0)
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 0), Vector3(SPEED, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.flaps = 0.0
	tv.throttle = 0.7
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	tv._command([292, 1, 1])  # ROLL: HDG SEL
	await frames(2)
	check(ai.flight_in_air(0.0), "the flight in the air (dev hook)")
	for m in ai._ai_members:
		if not m[1].player:
			m[1].shield = true
	s.invulnerable = true
	check("m:tanker" in _top(tv), "the radio's Tanker line with a tanker")
	check("refuel" in _tabs(tv), "the notebook's AIR REFUEL tab with a tanker (%s)" % [_tabs(tv)])
	_units(tv)
	await _far(tk)
	await _player(tv, tk)
	await _wingmen(tv, tk)
	s.invulnerable = false


func _tabs(tv: Node) -> Array:
	return tv.addon.kneeboard.board.sections.map(func(x): return x.id)


## The AIR REFUEL page's block of item `id`'s line (the notebook's text), "" when none.
func _ar_block(tv: Node, line: String) -> String:
	for sec in tv.addon.kneeboard._sections():
		if sec.id == "refuel":
			for b in sec.blocks:
				if line in String(b):
					return String(b)
	return ""


func _top(tv: Node) -> Array:
	tv.addon.set_open(true)
	var top: Array = tv.addon.shown.duplicate()
	tv.addon.set_open(false)
	return top


func _units(tv: Node) -> void:
	var seen := false
	for u in tv.weapons._units():
		if u.key == "tanker":
			seen = not bool(u.hostile)
	check(seen, "the tanker is a friendly unit for the radar")


## A receiver that asks from 60 km out stays in the queue on its way (it never came within 20 NM).
func _far(tk: Node) -> void:
	var me: int = tk._player_id()
	var p0: Dictionary = tk.tk.pose()
	var far: Vector3 = p0.position - p0.forward * 60000.0
	tk.test_player_state = func(_dt: float):
		return {"position": far, "velocity": p0.velocity, "forward": p0.forward, "right": p0.right, "up": p0.up}
	tk.tk.request(me)
	await frames(10)
	check(me in Array(tk.tk.receivers()), "asked from 60 km out: still in the queue")
	tk.tk.leave(me)
	tk.test_player_state = null


## The player's refuelling, the jet held on the tanker's stations by the test.
func _player(tv: Node, tk: Node) -> void:
	var me: int = tk._player_id()
	tv.addon.set_open(true)
	tv.addon.choose(tv.addon.shown.find("m:tanker") + 1)
	check(tv.addon.shown == ["tanker:request"], "the Tanker page: %s" % [tv.addon.shown])
	tv.addon.choose(1)
	check(_said(tk, "cleared_precontact", me), "the tanker: cleared pre-contact (%s)" % [tk.said])
	tv._command([296, 1, 0])  # Shift + F1: the door open
	check(tv.refuel_door, "the door open (command 296)")
	await frames(2)
	var card: Node = tv.addon.refuel_card
	check(card.done.has("ar_door_open"), "notebook: AIR REFUEL – OPEN ticked (%s)" % [card.done])
	check("✓" in _ar_block(tv, "AIR REFUEL – OPEN"), "notebook: its tick on the page")
	if tv.get("cockpit_3d") != null:
		check(card.done.has("ar_arm_off") and card.section == 1, "notebook: BEFORE CONTACT done (%d)" % card.section)
	var rc: Vector3 = tv.receptacle()
	check(rc != Vector3.INF, "the Sufa has a receptacle")
	var fuel0: float = float(tv.flight.state().fuel_lbs) * 0.45359
	# Room for 400 kg: the fuel below its internal tanks'.
	var internal: float = float(tv.flight.state().internal_fuel_kg)
	tv.flight.set_fuel(internal - 400.0)
	fuel0 = float(tv.flight.state().fuel_lbs) * 0.45359
	tk.test_player_state = func(dt: float): return _held(tk, rc, dt)
	var hold := func(): pass
	var cleared := func(): return _said(tk, "cleared_contact", me)
	check(await _while(tv, hold, cleared, 6.0), "held at pre-contact: cleared contact (%s)" % [tk.said])
	var contact := func(): return _said(tk, "contact", me)
	check(await _while(tv, hold, contact, 30.0), "the boom latched: contact")
	await frames(3)
	check(card.done.has("ar_contact"), "notebook: the contact ticked")
	var c3 = tv.get("cockpit_3d")
	if c3 != null:
		check(c3._lamp_on("ar_nws") and not c3._lamp_on("ar_rdy"), "AR/NWS lit, RDY out in contact")
	check(tk.tk.boom().get("pdl") == Vector2i(0, 0), "the PDLs centred: %s" % [tk.tk.boom().get("pdl")])
	var t0: float = tv._sim_time
	var f0: float = float(tv.flight.state().fuel_lbs) * 0.45359
	await _while(tv, hold, func(): return tv._sim_time - t0 > 4.0, 10.0)
	var rate: float = (float(tv.flight.state().fuel_lbs) * 0.45359 - f0) / (tv._sim_time - t0)
	print("player: %.1f kg/s taken (3,000 lb a minute: 22.7 less the burn)" % rate)
	check(rate > 20.0 and rate < 23.5, "the fuel at 3,000 lb a minute")
	# Fatally hit in contact: no longer a receiver, the boom unlatches (disconnect) and AR/NWS goes out.
	tv.fatal_hit = true
	check(await _while(tv, hold, func(): return not tk.in_contact(), 3.0), "fatally hit: off the boom (%s)" % [tk.said])
	check(["disconnect", me] in tk.said, "fatally hit: disconnect")
	tv.fatal_hit = false
	var n0: int = tk.said.size()
	tk.request(me)
	var again := func(): return tk.said.slice(n0).any(func(c): return c[0] == "contact" and int(c[1]) == me)
	check(await _while(tv, hold, again, 40.0), "asked again: contact (%s)" % [tk.said.slice(n0)])
	var n1: int = tk.said.size()
	tv._command([297, 0, 0])  # Shift + F2: A/R DISC
	check(await _while(tv, hold, func(): return ["disconnect", me] in tk.said.slice(n1), 2.0), "A/R DISC: disconnect")
	await frames(2)
	if c3 != null:
		check(c3._lamp_on("ar_disc") and not c3._lamp_on("ar_nws"), "DISC lit after the disconnect")
	var full := func(): return _said(tk, "complete", me)
	check(await _while(tv, hold, full, 60.0), "back in, and full: refuelling complete (%s)" % [tk.said])
	print("player: %.0f kg aboard from %.0f" % [float(tv.flight.state().fuel_lbs) * 0.45359, fuel0])
	check(tv.flight.fuel_room() < 10.0, "the tanks full")
	if c3 != null:
		await frames(2)
		check(not c3._lamp_on("ar_nws"), "AR/NWS out once off the boom")
	tk.test_player_state = null
	tv._command([296, -1, 0])
	check(not tv.refuel_door, "the door closed")
	await frames(2)
	check(card.done.has("ar_door_closed"), "notebook: AIR REFUEL – CLOSE ticked (%s)" % [card.done])


## The jet held with its receptacle on its station at the frame's end (`dt` on: the tanker's pose and velocity, level
## on its heading); on a wing station the jet's centre there.
func _held(tk: Node, rc: Vector3, dt: float) -> Dictionary:
	var st: Dictionary = tk.tk.station(tk._player_id())
	var p: Dictionary = tk.tk.pose()
	var fwd: Vector3 = Vector3(p.forward.x, 0.0, p.forward.z).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var at: Vector3 = st.get("at", p.position) + p.velocity * dt
	var centre: Vector3 = at
	if String(st.get("kind", "")) == "receptacle":
		centre = at - fwd * rc.x - right * rc.y - Vector3.UP * rc.z
	return {"position": centre, "velocity": p.velocity, "forward": fwd, "right": right, "up": Vector3.UP}


## The AI wingmen sent to the tanker: each in turn, then the rejoin.
func _wingmen(tv: Node, tk: Node) -> void:
	var fa = tv.ai.flight_ai
	for m in tv.ai._ai_members:
		if not m[1].player and m[1].get("pilot") != null:
			var f = m[1].pilot.flight
			f.set_fuel(float(f.state().internal_fuel_kg) - ROOM)
	var t0: float = tv.runtime.now
	check(_menu(tv, ["to:0", "refuel"]), "Refuel from the radio menu, to the flight")
	var acked := func(): return _ack(2, t0) and _ack(3, t0) and _ack(4, t0)
	check(await _until(tv, acked, 10.0), "each wingman acknowledges")
	Engine.time_scale = TIME_SCALE
	var done := func(): return [2, 3, 4].all(func(n): return _said(tk, "complete", n))
	var ok: bool = await _until(tv, func(): return _trace(tv, tk) or done.call(), 900.0)
	Engine.time_scale = 1.0
	print("wingmen: %s" % [tk.said])
	check(ok, "each wingman refuelled to full in turn")
	var order := []
	for c in tk.said:
		if c[0] == "contact" and int(c[1]) in [2, 3, 4] and not int(c[1]) in order:
			order.append(int(c[1]))
	check(order == [2, 3, 4], "in turn: %s" % [order])
	check(
		await _until(tv, func(): return [2, 3, 4].all(func(n): return not fa.state(n).refuelling), 10.0), "all rejoin"
	)
	await _shot_down(tv, tk)
	for m in tv.ai._ai_members:
		if not m[1].player:
			# Full when it left the boom; the engine has burnt some since (about 0.7 kg/s).
			check(
				m[1].pilot.flight.fuel_room() < 150.0,
				"#%d full (%.0f kg room)" % [int(m[0]), m[1].pilot.flight.fuel_room()]
			)


var _next_trace := 0.0


## Every 20 s: each wingman's distance to its station and its state (a failure's story).
func _trace(tv: Node, tk: Node) -> bool:
	if tv._sim_time < _next_trace:
		return false
	_next_trace = tv._sim_time + 20.0
	var p: Dictionary = tk.tk.pose()
	for m in tv.ai._ai_members:
		if m[1].player:
			continue
		var n := int(m[0])
		var st: Dictionary = tk.tk.station(n)
		var me: Vector3 = m[1].pilot.state().position
		var fs: Dictionary = tv.ai.flight_ai.state(n)
		print(
			(
				"  t %.0f #%d %s %.0f m off, %.0f m from the tanker, %.1f m/s (tanker %.1f), throttle %.2f ab %d, %s"
				% [
					tv._sim_time,
					n,
					st.get("kind", "-"),
					me.distance_to(st.get("at", me)),
					me.distance_to(p.position),
					float(m[1].pilot.state().speed),
					p.velocity.length(),
					float(m[1].pilot.state().throttle),
					int(m[1].pilot.state().afterburner),
					fs.get("stage", "")
				]
			)
		)
	return false


func _said(tk: Node, name: String, n: int) -> bool:
	return tk.said.any(func(c): return c[0] == name and int(c[1]) == n)


func _ack(n: int, t0: float) -> bool:
	for c in _tv.ai.flight_calls:
		if int(c.from) == n and String(c.id) == "ack" and float(c.get("t", 0.0)) >= t0:
			return true
	return false


## The radio menu (Ctrl+T, sim_flight.gd): opened, each id of `path` picked by its number as the keys do.
func _menu(tv: Node, path: Array) -> bool:
	tv.addon.set_open(true)
	for id in ["m:wingmen"] + path:
		if not id in tv.addon.shown and "m:more" in tv.addon.shown:
			tv.addon.choose(tv.addon.shown.find("m:more") + 1)
		var i: int = tv.addon.shown.find(id)
		if i < 0:
			tv.addon.set_open(false)
			return false
		tv.addon.choose(i + 1)
	return true


func _until(tv: Node, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		await process_frame
	return true


## `each` every frame until `cond` or `limit` s.
func _while(tv: Node, each: Callable, cond: Callable, limit: float) -> bool:
	var t0: float = tv._sim_time
	while not cond.call():
		if tv._sim_time - t0 > limit:
			return false
		each.call()
		await process_frame
	return true


## Kidon 1-2 sent again, then the tanker fatally hit: no tanker, and the wingman rejoins.
func _shot_down(tv: Node, tk: Node) -> void:
	var fa = tv.ai.flight_ai
	check(_menu(tv, ["to:2", "refuel"]), "Refuel again to Kidon 1-2")
	check(await _until(tv, func(): return bool(fa.state(2).refuelling), 10.0), "Kidon 1-2 refuelling")
	tv.runtime.set_damage_level(tk.ent, 3)
	check(
		await _until(tv, func(): return tv.tanker == null and not fa.state(2).refuelling, 5.0),
		"shot down: no tanker, #2 back"
	)
	check(not "m:tanker" in _top(tv), "no Tanker line once it is down")
