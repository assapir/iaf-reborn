# Modern IAF's compiled data (iaf-sim, iaf-2026/docs/data-formats.md) through the shared readers, unchanged: every
# compiled mission and its object database (sim.bdb) load as the game reads them (MissionRuntime, PlayerAircraft,
# weapon_db.gd with the modern weapons on our bases), the own weapons.ibx parses, and the Ramat David start-up loads
# into a flight as the mission editor's Fly runs a mission (Settings.mission_files_override). Its places are the sim's
# UTM frame (iaf-2026/docs/terrain.md), so the flight streams the sim's theatre (IAF_THEATRE=israel, set by the test;
# NEEDS DATA without it); the M0 probe (iaf-2026/tests/test_m0_boot.gd) flies it on the sim's own bases.
# It compiles the data first with the release binary target/release/iaf-sim (tools/test.sh builds it; NEEDS DATA
# without it). That writes only Modern IAF's own output into the shared assets/ (iaf-2026/docs/data-formats.md):
# converted/missions/sim.bdb.json, the "sim.bdb" key of converted/objects/objects.json, the own weapons.ibx under
# converted/own/, converted/iaf-2026/missions/, and (iaf-sim own) about 6 MB of sound clips with their tables in
# converted/own/resource/soundfiles/ and the key table converted/own/keys.json.
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/iaf-2026/missions"
const IBX := "converted/own/resource/weaponsmotion/weapons.ibx"
## The mission loaded.
const FLY := "ramat_david_startup"


func run() -> void:
	await require_data()
	var a: String = settings().assets_dir()
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var bin := repo.path_join("target/release/iaf-sim" + (".exe" if OS.get_name() == "Windows" else ""))
	if not FileAccess.file_exists(bin):
		print("NEEDS DATA: build the compiler (cargo build --release -p iaf-tools --bin iaf-sim)")
		await _quit(2)
		return
	var out := []
	var code := OS.execute(bin, ["all", repo.path_join("iaf-2026/data"), a], out, true)
	check(code == 0, "iaf-sim all compiles the data: %s" % "".join(out).strip_edges())
	var list: Dictionary = settings().load_json(a.path_join(MISSIONS).path_join("missionlist.json"))
	var sources := Array(DirAccess.get_files_at(repo.path_join("iaf-2026/data/missions"))).filter(
		func(f): return f.ends_with(".json")
	)
	check(list.size() == sources.size() and list.size() > 0, "a compiled mission per data file: %d" % list.size())
	var MR = load("res://shared/mission/mission_runtime.gd")
	var PA = load("res://shared/aircraft/player_aircraft.gd")
	var Db = load("res://shared/weapons/weapon_db.gd")
	var first := {}
	for id in list:
		var name := String(list[id][0])
		var m: Dictionary = settings().load_json(a.path_join(MISSIONS).path_join(name + ".json"))
		var bdb: Dictionary = MR.load_bdb(m)
		check(String(bdb.get("_file", "")) == "sim.bdb", "%s: its bdb is sim.bdb" % name)
		var pf: Dictionary = MR.player_flight(m, 1)
		var obj: Dictionary = MR.bdb_objects(bdb).get(int(pf.get("entity", {}).get("0x2c6", -1)), {})
		check(int(obj.get("0x5aa", -1)) == 0x1c, "%s: the player's unit %s is a jet" % [name, obj.get("0x514", "?")])
		var want: String = {"ramon": "f16i", "ramat": "f16", "nevatim": "f35i"}[name.get_slice("_", 0)]
		check(
			String(obj.get("airframe", "")) == want and not settings().airframe_def(want).is_empty(),
			"%s: the jet's aircraft definition %s" % [name, want]
		)
		check(not PA.object_for(int(obj.get("0x5b4", -1)), bdb, false).is_empty(), "%s: its jet object" % name)
		check(MR.flight_slots(m).has(1), "%s: flight slot 1" % name)
		if first.is_empty() or name == FLY:
			first = {"name": name, "id": int(id), "data": m, "bdb": bdb}
	var db = Db.create(first.bdb, false)
	for w in [[25, "20 MM"], [33, "Chaff"], [34, "Flare"], [1001, "AIM-9X"], [1003, "GBU-31"]]:
		check(String(db.weapons.get(w[0], {}).get("name", "")) == w[1], "weapon %d = %s" % w)
	# The compiled weapons.ibx through weapon_db.gd's own reader (the game reads it there once A1's install_dir()
	# switch lands): every weapon of the bdb has its motion section.
	var motion = Db.new()
	motion._load_ibx(a.path_join(IBX))
	for w in first.bdb.weapons.items:
		if int(w.get("0x14", 1)) == 0:
			check(
				not motion.motion_for(int(w["0x780"]), int(w["0x762"])).is_empty(),
				"weapons.ibx: %s's motion (type %d)" % [w["0x708"], int(w["0x780"])]
			)
	var ibx: Dictionary = settings().load_ibx(a.path_join(IBX))
	var gun := {}
	for s in ibx.values():
		if String(s.get("type", "")).to_int() == 565:
			gun = s
	check(float(String(gun.get("_velocityJump", "0"))) == 1030.0, "own weapons.ibx: the gun's muzzle velocity 1030")

	# Load Ramat David's start-up: the compiled file is in the real frame ("frame": "real"), so no base move touches
	# its start.
	var start: Dictionary = MR.player_flight(first.data, 1).entity
	check(String(first.data.get("frame", "")) == "real", "the compiled mission is in the real frame")
	if not FileAccess.file_exists(a.path_join("converted/terrain/israel/meta.json")):
		print("NEEDS DATA: the sim's theatre (iaf-sim terrain)")
		await _quit(2)
		await create_timer(3600, true, false, true).timeout
	OS.set_environment("IAF_THEATRE", "israel")
	settings().mission_files_override = [{"name": first.name, "data": first.data}]
	var tv: Node = await start_mission(first.id)
	check(String(tv.mission_bdb.get("_file", "")) == "sim.bdb", "flight: the mission's bdb is sim.bdb")
	check(String(tv.mission_object.get("0x514", "")) == "f16d", "flight: the player's unit is the Barak")
	check(String(tv.mission_object.get("airframe", "")) == "f16", "flight: its aircraft definition is the Barak's")
	var e: Dictionary = tv.mission_entity
	check(
		["0x2e4", "0x2ee", "0x2f8", "0x302"].all(func(k): return float(e[k]) == float(start[k])),
		"flight: the start is the compiled one (%s, %s, %s m, %s°)" % [e["0x2e4"], e["0x2ee"], e["0x2f8"], e["0x302"]]
	)
	settings().mission_files_override = []
	OS.unset_environment("IAF_THEATRE")
