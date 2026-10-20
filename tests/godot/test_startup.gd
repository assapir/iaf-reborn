# The start-up (game/menu/startup.gd, docs/front-end.md §18): the main scene opens the main menu at once; with
# Extras → CD launcher the poster shows first and PLAY goes on to the menu.
extends "res://../tests/godot/base.gd"


func wait_menu() -> bool:
	for i in 300:
		if current_scene != null and current_scene.scene_file_path == "res://menu/front_end.tscn":
			return true
		await process_frame
	return false


func run() -> void:
	var st = settings()
	change_scene_to_file("res://menu/startup.tscn")
	await frames(2)
	check(await wait_menu(), "the main menu at once")

	# CD launcher: the poster first; PLAY goes on to the menu.
	st.cd_launcher = true
	change_scene_to_file("res://menu/startup.tscn")
	await frames(3)
	var s: Node = current_scene
	var a: Control = s.get_child(s.get_child_count() - 1)
	check(a.has_signal("play") and s.scene_file_path == "res://menu/startup.tscn", "CD launcher shows first")
	a.press(a.PLAY)
	check(await wait_menu(), "PLAY: the main menu follows")
	st.cd_launcher = false
