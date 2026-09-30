# Player = default-flight leader (FUN_004bab1c, docs/mission-runtime.md §1.1): the leader of flight
# 1, else 2, 3, 4, or the flight picked on the TSD. 324 "All for One" has no Player1 (its leader is
# "Player", airborne at 2000 m); campaign 221 "Back to the Wall" flies alpha_1 (F-16); 136 picks
# Bravo when the TSD chose it.
extends "res://../tests/godot/base.gd"

const MissionRuntime := preload("res://mission/mission_runtime.gd")


func mission(id: int) -> Dictionary:
	var dir: String = Settings().assets_dir().path_join("converted/missions")
	var list = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("missionlist.json")))
	return JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(String(list[str(id)][0]) + ".json")))


func leader_name(id: int, wanted := 0) -> String:
	var pf: Dictionary = MissionRuntime.player_flight(mission(id), wanted)
	return "%s/%d" % [pf.entity.get("0x2bc", ""), pf.flight] if not pf.is_empty() else ""


func run() -> void:
	check(leader_name(311) == "Player1/1", "311: Player1 leads flight 1 (%s)" % leader_name(311))
	check(leader_name(324) == "Player/1", "324: the flight-1 leader 'Player' (%s)" % leader_name(324))
	check(leader_name(136) == "Alpha Leader/1", "136: Alpha Leader (%s)" % leader_name(136))
	check(leader_name(136, 2) == "Bravo Leader/2", "136 with Bravo picked on the TSD (%s)" % leader_name(136, 2))
	check(leader_name(136, 7) == "Alpha Leader/1", "a flight that does not exist falls back to the default")

	# 324: airborne start at the leader's position / altitude / heading, the runtime knows it.
	Settings().player_flight = 0
	var tv = await start_mission(324)
	var p: Dictionary = MissionRuntime.player_flight(mission(324)).entity
	check(tv.player_entity_id == int(p["0x1e"]), "324: flying entity %d" % tv.player_entity_id)
	check(tv.start_airborne, "324: airborne start (2000 m)")
	var w: Vector3 = tv.player_world()
	check(Vector2(w.x, w.y).distance_to(Vector2(369000, 673000)) < 300.0 and absf(w.z - 2000.0) < 100.0,
			"324: starts at the leader (%.0f, %.0f, %.0f)" % [w.x, w.y, w.z])
	check(absf(fposmod(tv.flight.state().heading - 30.0 + 180.0, 360.0) - 180.0) < 5.0, "324: heading 30 (%.1f)" % tv.flight.state().heading)
	var players: Array = tv.runtime.entities.values().filter(func(e): return e.player)
	check(players.size() == 1 and players[0].id == int(p["0x1e"]), "324: the runtime's player is that entity")

	# Campaign 221: alpha_1 (F-16) at 1200 m.
	tv = await start_mission(221)
	players = tv.runtime.entities.values().filter(func(e): return e.player)
	check(players.size() == 1 and players[0].name == "alpha_1", "221: the player is alpha_1")
	check(tv.start_airborne, "221: airborne start (1200 m)")

	# 136 with Bravo picked on the TSD: the runtime's player is Bravo Leader, Alpha Leader stays a unit.
	Settings().player_flight = 2
	tv = await start_mission(136)
	players = tv.runtime.entities.values().filter(func(e): return e.player)
	check(players.size() == 1 and players[0].name == "Bravo Leader", "136: TSD choice Bravo flies Bravo Leader")
	check(tv.route.size() > 0, "136: Bravo's route loaded (%d waypoints)" % tv.route.size())
	Settings().player_flight = 0
