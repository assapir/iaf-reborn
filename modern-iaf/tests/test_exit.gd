# The game quits and its process ends (the user, 2026-11-15: "the godot process kept alive after I exited it", and
# "6 ObjectDB instances were leaked at exit"): the player's path in a child Godot (tests/_exit_run.gd: the front end,
# the mission page with the ground preloading, the flight paused; then the game's own quit, Settings.quit) for each
# place the player quits from. Each child must end within EXIT_S of asking to quit, with no instance or node leaked,
# no extension panic and no script error in its output (docs/rendering.md §1.5 "Pool tasks at exit").
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_exit.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## From the child's "EXIT_QUIT" to its process gone, s.
const EXIT_S := 5.0
## The child's whole run at most (the flight's load included), s.
const RUN_S := 240.0


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	for at in ["front", "mission", "flight"]:
		for pilot in [false, true] if at == "front" else [true]:
			await _child(at, pilot)
	var dir := _dir()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## The children's logs and outputs, removed at the end.
func _dir() -> String:
	return OS.get_temp_dir().path_join("modern-iaf-exit-%d" % OS.get_process_id())


## One child run quitting at `at`; `pilot`: with a pilot and flights (else the first start's Pilot screen).
func _child(at: String, pilot: bool) -> void:
	var what := "%s%s" % [at, " (a pilot)" if pilot else " (first start)"]
	var dir := _dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var out := dir.path_join("%s_%d.out" % [at, int(pilot)])
	var args := [
		OS.get_executable_path(),
		"--headless",
		"--verbose",
		"--audio-driver",
		"Dummy",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"-s",
		ProjectSettings.globalize_path("res://tests/_exit_run.gd"),
		"--log-file",
		dir.path_join("%s_%d.log" % [at, int(pilot)]),
		"--",
		"--exit-at",
		at,
	]
	if pilot:
		args.append("--pilot")
	# Through sh for the child's whole output (the leak report comes after its log file closes).
	var cmd := " ".join(args.map(func(a): return "'%s'" % a)) + " > '%s' 2>&1" % out
	var pid := OS.create_process("/bin/sh", ["-c", "exec " + cmd])
	check(pid > 0, "%s: the child started" % what)
	if pid <= 0:
		return
	var t0 := Time.get_ticks_msec()
	var asked := -1
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < RUN_S * 1000.0:
		if asked < 0 and "EXIT_QUIT" in FileAccess.get_file_as_string(out):
			asked = Time.get_ticks_msec()
		if asked >= 0 and Time.get_ticks_msec() - asked > EXIT_S * 1000.0:
			break
		await create_timer(0.1, true, false, true).timeout
	var alive := OS.is_process_running(pid)
	if alive:
		OS.kill(pid)
	var text := FileAccess.get_file_as_string(out)
	asked = asked if asked >= 0 or not "EXIT_QUIT" in text else Time.get_ticks_msec()
	check(asked >= 0, "%s: the child asked to quit" % what)
	check(not alive, "%s: the process ended within %.0f s of the quit" % [what, EXIT_S])
	var bad := Array(text.split("\n")).filter(
		func(l): return "leaked" in l or "Leaked instance" in l or "panic" in l or "SCRIPT ERROR" in l or "ORPHAN" in l
	)
	check(bad.is_empty(), "%s: nothing leaked, no panic, no script error %s" % [what, bad.slice(0, 6)])
