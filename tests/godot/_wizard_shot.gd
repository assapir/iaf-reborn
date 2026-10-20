# Real-render screenshots of every setup wizard page, with a real run on a scratch assets folder (the review gate):
#   tools/godot_window.sh IAF_ASSETS_DIR=<scratch> IAF_DEFAULT_SETTINGS=1 XDG_DATA_HOME=<scratch>/xdg \
#     SHOT_OUT=<dir> -- --log-file <log> --path game -s ../tests/godot/_wizard_shot.gd
# SHOT_PAGES=1: the pages only, no install run. Uses the English ISO, the v1.1 patch and Brief.zip / Menu.zip from
# ~/Downloads.
extends "res://../tests/godot/base.gd"

const DL := "Downloads"
var out := ""


func shot(name: String) -> void:
	await frames(8)
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot " + name)


func run() -> void:
	out = OS.get_environment("SHOT_OUT")
	var assets := OS.get_environment("IAF_ASSETS_DIR")
	if out == "" or assets == "":
		check(false, "SHOT_OUT and IAF_ASSETS_DIR are set")
		return
	DirAccess.make_dir_recursive_absolute(out)
	var dl := OS.get_environment("HOME").path_join(DL)
	change_scene_to_file("res://setup/wizard.tscn")
	await frames(10)
	var w: Control = current_scene
	await shot("1_welcome")
	w._on_next()
	await shot("2_requirements")
	w._on_next()
	w.set_row(
		w.cd_row, dl.path_join("Janes-Combat-Simulations-IAF-Israeli-Air-Force_Win_EN_ISO-Version/Jane's IAF.iso")
	)
	await shot("3_your_cd")
	w._on_next()
	w.set_row(w.patch_row, dl.path_join("Janes-Combat-Simulations-IAF-Israeli-Air-Force_Patch_Win_EN_Patch-v11.exe"))
	w.set_row(w.brief_row, dl.path_join("Brief.zip"))
	w.set_row(w.menu_row, dl.path_join("Menu.zip"))
	await shot("4_optional")
	w._on_next()
	await shot("5_extras")
	w._on_next()
	await shot("6_summary")
	w._on_next()
	await shot("7_install_ready")
	if OS.get_environment("SHOT_PAGES") != "":
		return
	w._on_next()
	await seconds(30.0)
	w.log_button.pressed.emit()
	await shot("8_install_running")
	while not w.finished:
		await process_frame
	await shot("9_install_finished")
	w._on_next()
	await shot("10_done")
	# Setup again: every step up to date.
	w.show_page(w.PAGES.find("Install"))
	w.finished = false
	w._on_next()
	while not w.finished:
		await process_frame
	await shot("11_second_run_up_to_date")
	check(w.failed == "", "both runs finished")
