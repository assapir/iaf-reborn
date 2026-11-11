# Dev helper (not run by tools/test.sh): tests/godot/_flight_bench.gd in the sim, from one of its compiled missions
# (BENCH_SIM, default ramon_takeoff; converted/modern-iaf/missions) instead of an original's. The same BENCH_*
# variables; BENCH_BEST leaves the sim's own sky, clouds and imagery (best()); BENCH_AT takes UTM metres
# (modern-iaf/docs/scenery.md §5, the scenery's cost over Ramon and Tel Aviv). Keep blackbox=false in BENCH_SET:
# with the recorder on, the training check ends the flight when the bench moves the jet off the runway (scenery.md §6):
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 BENCH_BEST=1 \
#     BENCH_AT=668000,3550689 BENCH_LEGS=500:150:15 BENCH_SET=scenery=on,blackbox=false -- --log-file <temp> \
#     --display-driver x11 --path modern-iaf --resolution 2560x1440 -s ../modern-iaf/tests/_flight_bench.gd
extends "res://../tests/godot/_flight_bench.gd"


## BENCH_BEST in the sim: the sim's own values. Its fixed switches (sim_settings.gd PROFILE: the sky, no textured sky)
## and its own imagery stay; the original's (the textured sky's cloud art, the mapi2015 / sentinel2 layers) are data the
## sim refuses, and the refusal during the loading opens the crash page (2026-11-11: read as a hang at "frame").
static func best() -> Dictionary:
	var pick := super()
	var profile: Dictionary = load("res://sim_settings.gd").PROFILE
	for k in pick.keys():
		if k in profile or k.begins_with("imagery_"):
			pick.erase(k)
	return pick


## The sim reads no install: its own data is enough.
func require_data() -> void:
	pass


func start_mission(_id: int) -> Node:
	var s := settings()
	var name := OS.get_environment("BENCH_SIM") if OS.get_environment("BENCH_SIM") != "" else "ramon_takeoff"
	var m: Dictionary = s.load_json(s.assets_dir().path_join("converted/modern-iaf/missions").path_join(name + ".json"))
	load("res://flight/fly.gd").set_jet(m)
	s.mission_files_override = [{"name": name, "data": m}]
	var tv: Node = await super(int(m.sim.menu_id))
	s.mission_files_override = []
	return tv
