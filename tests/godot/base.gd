# Base for headless Godot tests (tools/test.sh): run with IAF_DEFAULT_SETTINGS=1 so the player's
# settings are never read or written. Prints PASS/FAIL lines and exits 1 on any failure.
# A test script compiles before the autoloads exist: game scripts that use Settings are load()ed in
# run(), not preloaded.
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	await run()
	print("RESULT %s" % ("FAIL" if failures > 0 else "PASS"))
	quit(1 if failures > 0 else 0)


func run() -> void:
	pass


func Settings() -> Node:
	return root.get_node("Settings")


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(target: Node, k: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.shift_pressed = shift
	target._unhandled_input(e)


func mouse_button(pos: Vector2, down: bool, double := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.double_click = double
	e.position = pos
	return e


## Loads the flight scene for a mission and waits until the aircraft stands on the terrain.
func start_mission(id: int) -> Node:
	Settings().mission_id = id
	change_scene_to_file("res://terrain/terrain_view.tscn")
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	return tv
