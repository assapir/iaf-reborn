# The combat logbook's events (modern-iaf/docs/storage.md §5, docs/blackbox.schema.json), headless: mission
# ramon_four_ship with the flight in the air (the dev hook ai_flights.gd `flight_in_air`), then each event made through
# the game's own damage path (mission_runtime.gd apply_damage) and the gun:
#   - a MiG-29A destroyed by the player alone: an air kill; a second hit by the player, finished by Kidon 1-2: a
#     shared kill; a third one shoots Kidon 1-3 down: one wingman lost, by a fighter;
#   - an enemy S-300 search radar destroyed by the player: a ground kill of its part's type;
#   - a gun burst: one `fire` of the 20 mm's rounds at the gun's stop.
# The flight's score (sim_flight.gd score, IafTraining) carries the record: combat_log.rs counts the events.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_combat_log.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const ALT := 4000.0
const SPEED := 230.0


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
	tv.addon.rules = {}  # unscored: score() is called below
	var ai = tv.ai
	var w: Vector3 = tv.player_world()
	var pos: Vector3 = tv.world_to_scene(Vector3(w.x, w.y, ALT))
	tv.rig.position = pos
	tv.flight.start(s.own_dir(), tv.player.fm_section, pos, Vector3(0, 0, 0), Vector3(SPEED, 0, 0), airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.6
	await frames(2)
	check(ai.flight_in_air(0.0), "the flight in the air (dev hook)")
	var wing: Array = ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	check(wing.size() >= 2, "the four-ship's wingmen")
	if wing.size() < 2:
		return
	var rt = tv.runtime
	var me: Dictionary = rt.player_entity()
	var at := func(dy: float) -> Vector3: return Vector3(w.x, w.y + dy, ALT)
	var mig1: Dictionary = ai.spawn("mig29a", at.call(30000), 180.0, [])
	var mig2: Dictionary = ai.spawn("mig29a", at.call(32000), 180.0, [])
	var mig3: Dictionary = ai.spawn("mig29a", at.call(34000), 180.0, [])
	check(not mig1.is_empty() and tv.enemy_of_player(mig1), "an enemy MiG-29A spawned")
	check(String(mig1.get("unit", "")) == "mig29a", "the MiG's record id on its entity: %s" % mig1.get("unit"))
	# The player's kill, alone.
	rt.apply_damage(mig1, 1.0e6, "missile", me)
	# A shared kill: the player hits, Kidon 1-2 finishes it.
	rt.apply_damage(mig2, float(mig2.strength) * 0.3, "gun", me)
	check(int(mig2.state) < 3 and mig2.hit_by.has(String(me.key)), "the player's hit, not fatal")
	rt.apply_damage(mig2, 1.0e6, "missile", wing[0])
	# Kidon 1-3 shot down by the third MiG.
	rt.apply_damage(wing[1], 1.0e6, "missile", mig3)
	# An enemy S-300 search radar (the network's stand-in shapes) destroyed by the player.
	var ad: Node = load("res://shared/ai/air_defence.gd").of(tv)
	var radar: Dictionary = ad.spawn_net(at.call(40000), at.call(43000), [])[0]
	check(tv.enemy_of_player(radar) and String(radar.unit) != "", "an enemy radar with its part's type")
	rt.apply_damage(radar, 1.0e6, "bomb", me)
	await frames(2)
	# A gun burst.
	var wpn = tv.weapons
	wpn.master_arm = true
	var before: int = wpn.stores.displayed(9)
	check(wpn.gun_trigger(), "the gun fires")
	await fly(tv, 0.6)
	wpn.gun_stop()
	var fired: int = before - wpn.stores.displayed(9)
	check(fired > 0, "rounds fired: %d" % fired)
	var d: Dictionary = tv.addon.score()
	check(not d.has("error"), "scored: %s" % d.get("error", ""))
	var c: Dictionary = d.get("combat", {})
	print("combat: ", c)
	# JSON numbers come back as floats: compared by value, one key each.
	var kills: Dictionary = c.get("kills", {})
	var shared: Dictionary = c.get("shared", {})
	check(kills.size() == 1 and int(kills.get("mig29a", 0)) == 2, "two MiG-29 kills: %s" % kills)
	check(shared.size() == 1 and int(shared.get("mig29a", 0)) == 1, "one of them shared: %s" % shared)
	var ground: Dictionary = c.get("ground", {})
	check(ground.size() == 1 and int(ground.get(String(radar.unit), 0)) == 1, "one ground target: %s" % ground)
	var gun: Dictionary = c.get("weapons", {}).get(wpn.stores.name_of(9), {})
	check(int(gun.get("fired", 0)) == fired and gun.get("gun", false), "the burst's rounds: %s" % gun)
	var lost: Dictionary = c.get("lost", {})
	check(lost.size() == 1 and int(lost.get("fighter", 0)) == 1, "a jet lost, by a fighter: %s" % lost)
	check(int(c.get("wingmen_lost", 0)) == 1, "one wingman lost")
