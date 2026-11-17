# The radar and the radar altimeter after a keyed start (avionics-plan.md §5.1 G1, G2; the user, 15 Nov: "radar isn't
# working? can't move out of stby?" and "no x on pull up?!"): the Sufa in the air with the SNSR PWR panel's FCR and
# RDR ALT off and the AVIONIC POWER switches off, as a start by the checklist's keys leaves them; the avionics key
# (command 213) then powers the FCR and RDR ALT with the four: Q takes the radar out of STBY into CRM, and the Real
# HUD gets the radar altitude its GAAF break X reads. G4: with the radar up, R puts it in GM (the real FCR's first A-G
# mode, MAP) and a MAP click designates the point a SPICE 1000 in VIS takes (player_weapons.gd gps_aim); without the
# FCR there was no MAP to click.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_radar.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


func run() -> void:
	await require_data()
	for unit in sim_f16s():
		print("-- %s" % unit)
		await _jet(unit, sim_f16s()[unit])


func _jet(unit: String, base: String) -> void:
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	IafPilotLog.set_loadout(db, s.pilot(), unit, IafBriefing.put(rec, "", 3, "spice-1000", true))
	var id := sim_mission(base + "_takeoff")
	load("res://flight/fly.gd").prepare(id)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.rules = {}  # unscored: no pass or fail ends the flight (test_switches_both_ways.gd)
	var st0: Dictionary = tv.flight.state()
	var g = tv.terrain.height_at(st0.position)
	var pos: Vector3 = st0.position + Vector3(0, 300.0 + float(g if g != null else 0.0) - st0.position.y, 0)
	tv.rig.position = pos
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, st0.heading), st0.forward * 200.0, airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.8
	await frames(5)
	# As the checklist's keys leave the jet: the four AVIONIC POWER switches and the SNSR PWR panel's two off.
	for c in [[213, 0, 0], [219, -1, 4], [219, -1, 5]]:
		tv._command(c)
		await frames(2)
	var w = tv.weapons
	check(not tv.cockpit.up("fcr") and not tv.cockpit.up("rdr_alt"), "FCR and RDR ALT off")
	# The avionics key.
	tv._command([213, 0, 0])
	await fly(tv, 4.0)
	check(tv.cockpit.up("fcr"), "the avionics key powers the FCR")
	check(tv.cockpit.up("rdr_alt"), "the avionics key powers RDR ALT")
	check(not w.radar.damaged, "the radar no longer held off")
	key(tv, KEY_Q)
	await frames(3)
	var names: PackedStringArray = ClassDB.class_call_static("IafF16Mfd", "fcr_mode", int(w.radar.mode))
	check(int(w.radar.mode) >= 2 and names[0] == "CRM", "Q: the radar out of STBY (%s %s)" % [names[0], names[1]])
	tv.cockpit.hud.real_hud()
	var agl = tv.cockpit.hud._real_in.get("agl_ft")
	check(agl != null and float(agl) > 100.0, "the Real HUD has the radar altitude its break X reads (%s ft)" % agl)
	# G4: a SPICE 1000 in VIS takes the radar's MAP designation.
	key(tv, KEY_R)  # A-G: the last A-G mode, the real FCR's GM at first (radar.rs)
	await frames(3)
	check(int(w.radar.mode) == 8, "R: the radar in GM, MAP (mode %d)" % w.radar.mode)
	var o: Dictionary = w.own()
	var aim: Vector3 = o.pos + Vector3(o.fwd.x, o.fwd.y, 0.0).normalized() * 8000.0
	w.radar_event(0x2f, Vector2(aim.x, aim.y))  # the MAP click (mfd.gd _click_map)
	key(tv, KEY_BRACKETLEFT)
	await frames(3)
	check(
		String(w.stores.current_name()).to_lower().contains("spice"), "[: the SPICE 1000 (%s)" % w.stores.current_name()
	)
	w.gps_mode_key()  # K: VIS
	var a: Array = w.gps_aim(Vector3.ZERO)
	check(
		a[1] and Vector2(a[0].x, a[0].y).distance_to(Vector2(aim.x, aim.y)) < 2.0,
		"VIS: the SPICE aims at the MAP designation (%s)" % [a]
	)
