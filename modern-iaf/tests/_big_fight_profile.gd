# The big fight under Godot's script profiler (docs/ai.md §22; not a test, tools/test.sh skips it): the scenario of
# big_fight.gd spawned, the sort given, then 20 s at time scale 1 profiled, native calls included. PROF_ALONE=1
# profiles our flight alone (nothing spawned). The data goes to the remote debugger, tools/gd_profile.py:
#   python3 -I tools/gd_profile.py 6200 <out.txt> &
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf --remote-debug tcp://127.0.0.1:6200 \
#     -s ../modern-iaf/tests/_big_fight_profile.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const PROFILE_S := 20.0

var sc


func run() -> void:
	sc = load("res://../modern-iaf/tests/big_fight.gd").new()
	if not await sc.start(self):
		return
	var tv: Node = sc.tv
	await fly(tv, 3.0)
	if OS.get_environment("PROF_ALONE") != "1":
		sc.spawn(self)
		var t0: float = tv._sim_time
		while not "sort" in sc.orders and tv._sim_time - t0 < 120.0:
			sc.step()
			await process_frame
	check(EngineDebugger.is_active(), "run with --remote-debug")
	for p in ["servers", "scripts"]:
		EngineDebugger.profiler_enable(p, true, [1000, true])  # up to 1000 functions a frame, native calls too
	var t1: float = tv._sim_time
	while tv._sim_time - t1 < PROFILE_S:
		if sc.spawned:
			sc.step()
		await process_frame
	for p in ["servers", "scripts"]:
		EngineDebugger.profiler_enable(p, false)
	sc = null
