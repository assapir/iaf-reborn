# The jet's checklist card (modern-iaf/docs/training.md §12; the user, 17 Nov: "ok so all of this should be part of the
# checklist, ya? turning radar on etc"), headless, per jet: its take-off lesson flown from a cold jet by exactly the
# card's items, each by real clicks on the 3D cockpit's controls (test_mvp.gd _fly_card), the taxi, the take-off and
# AFTER TAKEOFF; then every modelled system is powered, aligned and ready: the radar radiating, the INS in NAV with its
# steerpoints, no ALIGN on the HUD, RDR ALT giving a radar altitude, the targeting pod working (F-16s), no caution lit.
# Then the card in an ordinary mission (a weapons range, hot): it opens at BEFORE TAXI and ticks a switch, in English
# and Hebrew.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_checklist_card.gd --log-file <temp> [-- --jet f16i]
extends "res://tests/test_mvp.gd"


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-mvp-card-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--jet") + 1] if args.has("--jet") else ""
	for id in JETS:
		if only == "" or id == only:
			await _ready_to_fight(id)
	if only in ["", "f16i"]:
		await _ordinary()
	Engine.time_scale = 1.0


func _ready_to_fight(id: String) -> void:
	var tv := await _card_flight(id, id != "f35i")
	var card = tv.addon.card
	check(String(card.sections[card.section].id) == "before_landing", "%s: AFTER TAKEOFF done" % id)
	var left: Array = card.flat.filter(func(it): return it.has("check") and int(it.section) < card.section)
	left = left.filter(func(it): return not card.done.has(it.id))
	check(left.is_empty(), "%s: every checked item up to here ticked (%s)" % [id, left.map(func(it): return it.id)])
	var w = tv.weapons
	var c = tv.cockpit
	var radiating := func() -> bool: return not w.radar.damaged and int(w.radar.mode) >= 2 and bool(w.radar.emit)
	check(await _until(tv, radiating, 10.0), "%s: airborne, the radar radiates (mode %d)" % [id, w.radar.mode])
	check(
		tv.flight.ins_knob() == tv.addon.INS_NAV and bool(tv.flight.ins_status()[2]) or id == "f35i",
		"%s: the INS in NAV, aligned" % id
	)
	check(c.ins_nav() and not c.steer_route().is_empty(), "%s: steering to the route's steerpoints" % id)
	check(c.up("rdr_alt"), "%s: RDR ALT powered" % id)
	if id != "f35i":
		var h = c.hud
		tv.views.snap = Vector2.ZERO
		h._real_frame = -1
		var r: Dictionary = h.real_hud()
		var texts: Array = (r.get("field", []) + r.get("outer", [])).filter(func(p): return p.k == "text")
		check(not texts.any(func(p): return String(p.text) == "ALIGN"), "%s: no ALIGN on the HUD" % id)
		check(h._real_in.get("agl_ft") != null, "%s: RDR ALT gives the HUD the radar altitude" % id)
		check(c.up("r_hdpt") and c.up("l_hdpt"), "%s: both hardpoints powered" % id)
		check(w.flir_pod, "%s: the Litening carried" % id)
		# The pod's 180 s cool-down from RIGHT HDPT, if not over yet.
		print(
			(
				"%s pod: state %d, powered %.0f s, paused %s, crashed %s"
				% [id, w.pod_state(), w.now - w.pod_power_at, paused, tv.crashed]
			)
		)
		Engine.time_scale = TIME_SCALE
		var t0 := Time.get_ticks_msec()
		while w.pod_state() != 3 and Time.get_ticks_msec() - t0 < 60000 and not tv.crashed:
			await process_frame
		Engine.time_scale = 1.0
		check(w.pod_state() == 3, "%s: the targeting pod works (%.0f s powered)" % [id, w.now - w.pod_power_at])
	var c3d = tv.cockpit_3d
	var lit: Array = c3d._cautions.keys()
	check(lit.is_empty() and not bool(c3d.lamps_lit.get("master_caution", false)), "%s: no caution lit %s" % [id, lit])
	tv.scripted_stick = null
	tv.scripted_rudder = null
	Engine.time_scale = TIME_SCALE


## An ordinary mission (the Sufa's weapons range flown as a sortie, its rules off): the card is the jet's, opens on
## the notebook's CHECKLIST page with the current item on it in English and Hebrew (a hot start: the sections before
## BEFORE TAXI done), and the current item's control clicked to its position ticks it; no ring outside a lesson.
func _ordinary() -> void:
	var tv := await _start("ramon_range")
	tv.addon.rules = {}
	tv.addon.checklist = []
	await fly(tv, 1.0)
	var card = tv.addon.card
	var kb = tv.addon.kneeboard
	check(card.flat.size() > 40 and tv.addon.plane == "f16i", "range: the Sufa's card (%d items)" % card.flat.size())
	var sec := String(card.sections[card.section].id)
	check(
		sec == ("before_taxi" if tv.start_engine_on else "before_start"),
		"range: the card starts at %s (hot %s)" % [sec, tv.start_engine_on]
	)
	kb.refresh()
	kb.set_raised(true)
	await frames(2)
	check(kb.board.current_id() == "startup", "range: the notebook opens at CHECKLIST")
	for lang in ["en", "he"]:
		settings().language = lang
		kb.refresh()
		var it: Dictionary = card.current()
		var shown: bool = not it.is_empty() and String(it[lang]).split(" – ")[0] in kb.board.page_text()
		check(shown, "range %s: the current item on the page (%s)" % [lang, it.get(lang)])
	settings().language = "en"
	kb.refresh()
	var it: Dictionary = card.current()
	var want: Dictionary = it.get("check", {}).get("set", {})
	check(not want.is_empty(), "range: the current item %s is a switch's" % it.get("id"))
	for n in want:
		for k in 6:
			if card.at(n, want[n]):
				break
			await _click_control(tv, n, _moves(tv, n))
	await frames(2)
	check(card.done.has(it.id), "range: clicks tick %s" % it.get("id"))
	check(kb._marks().is_empty(), "range: no ring outside a lesson")
