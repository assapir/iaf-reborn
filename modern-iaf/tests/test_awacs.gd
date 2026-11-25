# The AWACS controller (docs/ai.md §24), headless, on the Sufa, from Ramon's Scramble start in the air:
# - the radio menu's AWACS page in English and Hebrew: its six requests, Declare off without a radar lock and Vector
#   to tanker off with no tanker in the air, each with its one-line reason;
# - Picture, Bogey dope, Vector to target and Vector home with a known MiG-29A 20 km ahead: the pilot's call ("Eitam,
#   Kidon 1, picture") then the controller's answer in brevity (two groups or one, BRAA, "home plate", "target");
# - the wingman holding the MiG in its radar reports "contact" after the answer named it;
# - the Eitam (docs/ai.md §24.3) on its station: 41,000 ft, Mach 0.80, off the flight's way to the fight, the fight
#   inside its radar; a known MiG 40 km from it: its call for help ("threat ... Eitam retrograding, commit") and its
#   retreat at Mach 0.85; shot down: the AWACS page all off ("The Eitam is lost"), no contact call, no AWACS track on
#   the data link.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_awacs.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const FC := {"flight": 2, "area": "Hatzerim", "home": "Ramon", "seed": 7, "start": "air"}
var fly_gd: GDScript


func run() -> void:
	fly_gd = load("res://flight/fly.gd")
	await require_data()
	var s := settings()
	var id := sim_mission("ramon_free")
	if id < 0:
		print("NEEDS DATA: the Scramble starts (iaf-sim missions)")
		return
	s.sim_jet = "f16i"
	check(fly_gd.prepare_free(id, FC), "the Scramble start")
	s.free_combat = FC
	var tv := await start_mission(id)
	s.mission_files_override = []
	var node: Node = tv.addon.get_node_or_null("FreeCombat")
	for i in 120:
		if node == null or not node.placed.is_empty():
			break
		await process_frame
	var start: Vector3 = tv.player_world()
	await fly(tv, 7.0)  # past the task call
	var sim: Node = tv.addon
	_station(tv, start)
	# A known MiG-29A 20 km ahead of the player, flying at it.
	var me: Vector3 = tv.player_world()
	var nose := deg_to_rad(float(tv.runtime.player_entity().get("heading", 0.0)))
	var at := me + Vector3(sin(nose), cos(nose), 0.0) * 20000.0
	var mig: Dictionary = tv.ai.spawn("mig29a", at, fposmod(rad_to_deg(nose) + 180.0, 360.0), [])
	check(not mig.is_empty(), "the MiG spawned")
	mig.known = true
	await fly(tv, 1.0)
	for lang in ["en", "he"]:
		s.language = lang
		_page(sim, lang)
	s.language = "en"
	var r: Node = tv.radio
	for req in ["picture", "bogey_dope", "vector_target", "vector_home"]:
		var n: int = r.said.size()
		var out: Array = sim.awacs_pick(req)
		var said: Array = r.said.slice(n)
		check(not said.is_empty() and said[0].template == "PILOT_CALL", "%s: the pilot's call first" % req)
		check(not out.is_empty(), "%s: answered" % req)
		var t: String = " ".join(out.map(func(p): return String(p.text)))
		print("%s -> %s" % [req, t])
		match req:
			"picture":
				check(out[0].template == "AWX_PICTURE" and t.begins_with("Kidon 1, "), "picture: the groups (%s)" % t)
				check(out.size() >= 2 and out[1].template == "AWX_GROUP", "picture: a group's BRAA (%s)" % t)
				check("hostile" in t and " thousand" in t, "picture: the MiG hostile with its height (%s)" % t)
			"bogey_dope":
				check(out[0].template == "AWX_BRAA" and t.begins_with("Kidon 1, group bearing"), "bogey dope (%s)" % t)
				check("hot" in t and "hostile" in t, "bogey dope: the MiG hot, hostile (%s)" % t)
			"vector_target":
				check(t.begins_with("Kidon 1, vector ") and t.ends_with("target"), "vector to target (%s)" % t)
			"vector_home":
				check(t.ends_with("home plate"), "vector home (%s)" % t)
	# The wingman reports the MiG the answers named.
	await fly(tv, 3.0)
	var contact: Array = tv.ai.flight_calls.filter(func(c): return c.id == "contact")
	check(not contact.is_empty(), "the wingman's contact call (%s)" % [tv.ai.flight_calls.map(func(c): return c.id)])
	_voice(tv)
	await _eitam(tv)


## The AWACS's English voice by the cast (sound.md §3): a woman's (af_bella) where the cast's Hebrew AWACS is a woman.
func _voice(tv: Node) -> void:
	var s := settings()
	var table = tv.sounds.get("table")
	var casts: Array = table._he.get("casts", [])
	var was: int = s.mission_id
	var both := {}
	for i in casts.size():
		s.mission_id = i
		var woman: bool = table._he.genders.get(String(casts[i].awacs), "") == "f"
		var path: String = table.english("awx_clean.ogg")
		check(("en/af_bella/" in path) == woman, "voice: cast %d's AWACS (%s): %s" % [i, casts[i].awacs, path])
		both[woman] = true
	check(both.size() == 2, "voice: a man in some casts, a woman in others")
	s.mission_id = was


## The Eitam on its station before any enemy comes near it.
func _station(tv: Node, start: Vector3) -> void:
	var r: Node = tv.radio
	check(r.eitam_flies(), "the Eitam placed with the Scramble")
	var e: Dictionary = r.awacs.eitam()
	if e.is_empty():
		return
	var area: Vector3 = fly_gd._lineup(fly_gd._ibx(), "Hatzerim")
	var home: Vector3 = fly_gd._lineup(fly_gd._ibx(), "Ramon")
	var flat := func(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.y - b.y).length()
	check(not e.retreating, "Eitam: on station (%s)" % e)
	check(absf(e.pos.z - 12496.8) < 5.0 and absf(e.speed - 236.06) < 1.0, "Eitam: 41,000 ft at Mach 0.80 (%s)" % e)
	check(flat.call(e.pos, area) < 300000.0, "Eitam: the fight inside its radar (%.0f m)" % flat.call(e.pos, area))
	for way in [[start, area], [home, area]]:
		var a: Vector2 = Vector2(way[0].x, way[0].y)
		var b: Vector2 = Vector2(way[1].x, way[1].y)
		var q := Geometry2D.get_closest_point_to_segment(Vector2(e.pos.x, e.pos.y), a, b)
		check(q.distance_to(Vector2(e.pos.x, e.pos.y)) > 15000.0, "Eitam: off the flight's way (%s)" % q)


## The Eitam threatened: the call for help and the retreat, then shot down.
func _eitam(tv: Node) -> void:
	var r: Node = tv.radio
	var e: Dictionary = r.awacs.eitam()
	if e.is_empty():
		return
	var ent: Dictionary = tv.runtime.entities.get("eitam", {})
	check(not ent.is_empty() and ent.side == tv.runtime.player_entity().side, "Eitam: an entity of our side")
	# A target in the enemy's picture (its radars, sites and fighters: air_defence.gd jets), with its own RCS.
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var enemy_side := 1 if int(ent.side) == 2 else 2  # the sides' convention (drones.gd spawn)
	var seen: Array = ad.jets(enemy_side).filter(func(j): return j.id == "eitam")
	check(seen.size() == 1 and seen[0].rcs.side_m2 == 40.0, "Eitam: in the enemy's picture (%s)" % [seen])
	# A known MiG 40 km from it: the call for help and the retreat.
	var at: Vector3 = e.pos + Vector3(40000.0, 0.0, -5000.0)
	var mig: Dictionary = tv.ai.spawn("mig29a", at, 270.0, [])
	mig.known = true
	await fly(tv, 2.0)
	# (The MiG ahead of the player, hot, may have threatened it first: one call for the episode either way.)
	var help: Array = r.said.filter(func(p): return p.template == "AWX_HELP")
	check(help.size() == 1, "Eitam: one call for help (%d)" % help.size())
	if not help.is_empty():
		var t: String = help[0].text
		check(t.begins_with("Kidon 1, threat, group bearing") and t.ends_with("Eitam retrograding, commit"), t)
	check(bool(r.awacs.eitam().retreating), "Eitam: retreating")
	await fly(tv, 20.0)
	check(r.awacs.eitam().speed > 245.0, "Eitam: at Mach 0.85 (%.0f m/s)" % r.awacs.eitam().speed)
	# The data link's AWACS tracks from its radar; shot down, the service ends.
	var ews = tv.weapons.get("ews")
	var hostiles := func() -> Array: return ews.state.get("link", []).filter(func(k): return k.kind == "hostile")
	if ews != null:
		ews.link_power(true)
		await fly(tv, 5.0)
		check(not hostiles.call().is_empty(), "Eitam: the MiGs on the data link")
	ent.state = 3
	await fly(tv, 1.0)
	check(not r.awacs.in_service(), "Eitam down: no service")
	var sim: Node = tv.addon
	sim.set_open(true)
	sim.choose(3)
	var off: Dictionary = sim._off()
	check(off.size() == 6, "Eitam down: every request off (%s)" % off)
	check(String(off.get(0, "")) == sim._bi(sim.ui.s("fl_awx_lost")), "Eitam down: the reason (%s)" % off.get(0))
	sim.set_open(false)
	check(r.awacs_request("picture").is_empty(), "Eitam down: no answer")
	if ews != null:
		await fly(tv, 5.0)
		check(hostiles.call().is_empty(), "Eitam down: no AWACS track on the data link (%s)" % [hostiles.call()])
	var n2: int = r.said.size()
	await fly(tv, 13.0)
	var calls: Array = r.said.slice(n2).filter(func(p): return p.template.begins_with("ACFT_FCTRL"))
	check(calls.is_empty(), "Eitam down: no contact call (%d)" % calls.size())


## The AWACS page in `lang`: the six requests, Declare and the tanker off with their reasons.
func _page(sim: Node, lang: String) -> void:
	sim.set_open(true)
	sim.choose(3)
	check(sim.page == "awacs", "%s: AWACS opens its page (%s)" % [lang, sim.page])
	check(sim.shown == sim.AWACS_ITEMS.map(func(x): return x[0]), "%s: the six requests %s" % [lang, sim.shown])
	var off: Dictionary = sim._off()
	var want := {2: "fl_awx_no_lock", 5: "fl_awx_no_tanker"}
	check(off.keys() == want.keys(), "%s: Declare and the tanker off (%s)" % [lang, off])
	for i in want:
		check(String(off.get(i, "")) == sim._bi(sim.ui.s(want[i])), "%s: the reason %s" % [lang, off.get(i)])
	var text: String = sim.menu_text()
	var label: String = sim.AWACS_ITEMS[0][2 if lang == "he" else 1]
	check(label in text, "%s: the page's lines (%s)" % [lang, text])
	sim.choose(3)  # Declare is off: the menu stays
	check(sim.open and sim.page == "awacs", "%s: an off line does nothing" % lang)
	sim.set_open(false)
