# The start-up before the main menu (docs/front-end.md §18), the game's main scene:
#   1. ours, Extras → CD launcher: the CD's autorun poster (menu/autorun.gd); PLAY goes on, QUIT / Esc quits,
#      INSTALL opens the setup wizard, UNINSTALL asks and removes the setup's data;
#   2. the main menu (menu/front_end.tscn; the exe's state 2 draws Bmp\Back0.bmp and opens it).
# The exe plays janes.avi and intro.avi before the menu; ours goes straight on (README "Intro videos").
# Our command-line runs (--mission, --screenshot, --hover) go straight to the menu. Without assets/converted: the
# setup wizard (setup/wizard.tscn).
extends Control

const FRONT_END := "res://menu/front_end.tscn"
const SETUP := "res://setup/wizard.tscn"
const DEV_ARGS := ["--mission", "--screenshot", "--hover"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Array(OS.get_cmdline_user_args()).any(func(a): return a in DEV_ARGS):
		_menu.call_deferred()
		return
	run()


func run() -> void:
	# No game data yet (a launch that bypassed ./setup and ./iafjets): the setup wizard.
	if not DirAccess.dir_exists_absolute(Settings.assets_dir().path_join("converted")):
		get_tree().change_scene_to_file.call_deferred(SETUP)
		return
	if Settings.cd_launcher:
		match await launcher():
			"quit":
				Settings.quit()
				return
			"install":
				get_tree().change_scene_to_file.call_deferred(SETUP)
				return
	_menu.call_deferred()


## The CD launcher: "play" (also when its files are missing), "quit" or "install".
func launcher() -> String:
	var a: Control = preload("res://menu/autorun.gd").new()
	add_child(a)
	if not a.available():
		push_warning("CD launcher: no files in assets/install/autorun (iaf-extract --autorun <iso> assets/install)")
		a.queue_free()
		return "play"
	var result := ["play"]
	a.quit.connect(
		func():
			result[0] = "quit"
			a.play.emit()
	)
	a.install.connect(
		func():
			result[0] = "install"
			a.play.emit()
	)
	a.uninstall.connect(uninstall)
	await a.play
	a.queue_free()
	return result[0]


## UNINSTALL (ours, docs/setup.md "Uninstall"): asks, then removes what the setup wrote under assets/
## (IafSetup.uninstall); the pilots and settings in the user folder stay. Without its data the game then quits.
func uninstall() -> void:
	var ask := ConfirmationDialog.new()
	ask.title = "Uninstall"
	ask.dialog_text = (
		"Remove the game data the setup made (the CD's files and the converted data in assets/)?\n"
		+ "Your pilots and settings stay. Run ./setup to install again."
	)
	ask.ok_button_text = "Uninstall"
	ask.confirmed.connect(_remove_data)
	add_child(ask)
	ask.popup_centered()


func _remove_data() -> void:
	var e: String = IafSetup.uninstall(Settings.assets_dir())
	var done := AcceptDialog.new()
	done.title = "Uninstall"
	done.dialog_text = (
		"The game data is removed. Run ./setup to install again." if e == "" else "Uninstall failed: " + e
	)
	done.confirmed.connect(Settings.quit)
	done.canceled.connect(Settings.quit)
	add_child(done)
	done.popup_centered()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)


func _menu() -> void:
	get_tree().change_scene_to_file(FRONT_END)
