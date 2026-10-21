# Dev helper (not run by tools/test.sh): real-render captures of the mission editor's Scenario tab, saved to
# SCN_SHOT_DIR: 1.png a fork of 512 Wild West (its original rules), 2.png a New mission with three rules built on the
# tab (one with a unit still to pick). The missions live in user://missions_shot_scn and are removed after.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SCN_SHOT_DIR=/tmp -- --log-file /tmp/scn.log --path game \
#     --resolution 1600x1000 -s ../tests/godot/_scenario_shot.gd
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_shot_scn"


func _shot(name: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("SCN_SHOT_DIR").path_join(name)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved %s" % path)


func run() -> void:
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.add_child(ed)
	await frames(3)
	var tabs: TabContainer = ed._ui.scenario.get_parent()
	ed.open_original(512)
	ed.fork("Wild West 2")
	await _shot("0.png")
	tabs.current_tab = tabs.get_tab_count() - 1
	await _shot("1.png")
	ed.new_mission("Scenario shot", 1998.0, "Ramat David", 1, true)
	var sam: int = ed.add_unit(6, 350000, 600000, 2, 1)
	var tank: int = ed.add_unit(10, 348000, 600000, 2, 2)
	var sc = ed._ui.scenario
	var r: int = sc.add_rule("destroyed")
	sc.set_value([r, "when", "units", 0], sam)
	sc.drop_block(r, {"then": "message"})
	sc.set_value([r, "then", 0, "audio"], 2)
	sc.drop_block(r, {"then": "wait"})
	sc.drop_block(r, {"then": "goal"})
	r = sc.add_rule("enters")
	sc.set_value([r, "when", "who"], 2)
	sc.set_value([r, "when", "center"], tank)
	sc.drop_block(r, {"then": "message"})
	sc.set_value([r, "then", 0, "audio"], 496)
	r = sc.add_rule("start")
	sc.drop_block(r, {"then": "hide"})
	root.size = Vector2i(root.size.x, root.size.y * 2)  # tall enough to show the rules under the palettes
	await _shot("2.png")
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)
