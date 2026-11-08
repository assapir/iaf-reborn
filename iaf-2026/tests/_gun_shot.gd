# Dev helper (not run by tools/test.sh): a burst of the Sufa's gun at Ramon in a real render (iaf-2026/docs/weapons.md
# §2): the cockpit view and the chase view, the graphics options at their best (_training_shot.gd ALL).
#   flock -o ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
#     SHOW_OUT=<dir> -- --log-file <temp> --display-driver x11 --resolution 1920x1080 --path iaf-2026 \
#     -s ../iaf-2026/tests/_gun_shot.gd
extends "res://tests/_training_shot.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	shots = OS.get_environment("SHOW_OUT")
	DirAccess.make_dir_recursive_absolute(shots)
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-shots-%d" % OS.get_process_id())
	settings().show_info = false
	for k in ALL:
		settings().set(k, ALL[k])
	var tv := await _start("ramon_takeoff")
	Engine.time_scale = 1.0
	_cockpit(tv, Vector2(0, deg_to_rad(-4)))
	await fly(tv, 3.0)
	tv.weapons.safety_off = true  # on the ground: past the gear-down rule
	tv._command([202, 0, 0])  # Master arm (Shift+A)
	await _burst(tv, "gun_burst_cockpit")
	tv.views.snap = null
	tv._command([28, 6, 0])  # F10: the chase view
	await fly(tv, 1.0)
	await _burst(tv, "gun_burst_chase")


## Holds the trigger 1.2 s, then takes `name` with the rounds in flight.
func _burst(tv: Node, name: String) -> void:
	tv.weapons.gun_trigger()
	await fly(tv, 1.2)
	await _shot(name)
	tv.weapons.gun_stop()
	await fly(tv, 3.0)
