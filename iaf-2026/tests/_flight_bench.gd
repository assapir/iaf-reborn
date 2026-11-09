# Dev helper (not run by tools/test.sh): tests/godot/_flight_bench.gd in the sim, from one of its compiled missions
# (BENCH_SIM, default ramon_takeoff; converted/iaf-2026/missions) instead of an original's. The same BENCH_* variables;
# BENCH_AT takes UTM metres (iaf-2026/docs/scenery.md §5, the scenery's cost over Ramon and Tel Aviv). Keep
# blackbox=false in BENCH_SET: with the recorder on, the training check ends the flight when the bench moves the jet
# off the runway (scenery.md §6):
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 BENCH_BEST=1 \
#     BENCH_AT=668000,3550689 BENCH_LEGS=500:150:15 BENCH_SET=scenery=on,blackbox=false -- --log-file <temp> \
#     --display-driver x11 --path iaf-2026 --resolution 2560x1440 -s ../iaf-2026/tests/_flight_bench.gd
extends "res://../tests/godot/_flight_bench.gd"


## The sim reads no install: its own data is enough.
func require_data() -> void:
	pass


func start_mission(_id: int) -> Node:
	var s := settings()
	var name := OS.get_environment("BENCH_SIM") if OS.get_environment("BENCH_SIM") != "" else "ramon_takeoff"
	var m: Dictionary = s.load_json(s.assets_dir().path_join("converted/iaf-2026/missions").path_join(name + ".json"))
	load("res://flight/fly.gd").set_jet(m)
	s.mission_files_override = [{"name": name, "data": m}]
	var tv: Node = await super(int(m.sim.menu_id))
	s.mission_files_override = []
	return tv
