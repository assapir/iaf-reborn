# Dev helper (not run by tools/test.sh): real-render pictures of the update on start (docs/release.md §7) in either
# game, English and Hebrew, at 1920x1080, into SHOT_DIR: update_line_<lang> (a newer nightly offered, from a local
# fake release), update_ticked_<lang> (the same, Don't ask me again ticked), setup_line_<lang> / setup_ticked_<lang>
# (setup steps to run again), prefs_<lang> (Modern IAF's Settings → Updates; the
# remake's Extras row: _prefs_shot.gd PREF_PAGE=Extras PREF_ROW=update_mode), wizard_<lang> (Update: the wizard runs
# the stale steps), back_<lang> (the front end after the run). IAF_ASSETS_DIR must be a scratch copy of the data: the
# wizard writes into it (WIZARD_CANCEL=1: cancelled after its picture; IAF_LAUNCHER_ROOT=<scratch folder> keeps a
# launcher step off the desktop; UPDATE_NO_WIZARD=1 skips the wizard). WIZARD_STAMP=<stamp under it, e.g.
# converted/terrain/theatre.stamp> is removed before each language, so its step runs. UPDATE_LIST=1 only prints the
# stale steps; UPDATE_FAKE_STALE=1 shows two made-up steps when the data has none.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 IAF_ASSETS_DIR=<scratch> SHOT_DIR=<dir> -- --resolution 1920x1080 \
#     --log-file <log> --path modern-iaf -s ../tests/godot/_update_shot.gd
extends "res://../tests/godot/base.gd"

const OLD := "0.1.0-nightly.20261101+aaaaaaa"
const NEW := "0.1.0-nightly.20261125+bbbbbbb"

var dir := OS.get_environment("SHOT_DIR")
var updater: GDScript
var modern := false


func shot(name: String) -> void:
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("saved ", name)


## An update line: `own` NEW shows setup's steps, OLD the fake release's newer nightly.
func line(own: String, release: String) -> CanvasLayer:
	var u: CanvasLayer = updater.new()
	u.own = own
	u.base = release
	root.add_child(u)
	for i in 1200:
		if not is_instance_valid(u) or (u.state == "" and u.bar.visible):
			break
		await process_frame
	return u


func run() -> void:
	updater = load("res://shared/util/updater.gd")
	modern = settings().project_folder() == "modern-iaf"
	if OS.get_environment("UPDATE_LIST") == "1":
		var u := await line(NEW, "/nonexistent")
		print("stale: ", u.stale if is_instance_valid(u) else [])
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var release := OS.get_cache_dir().path_join("iaf-update-shot")
	DirAccess.make_dir_recursive_absolute(release)
	var kind: String = {"Linux": "linux-x86_64.tar.gz", "Windows": "windows-x86_64.zip"}.get(
		OS.get_name(), "macos-arm64.dmg"
	)
	var asset := "%s-nightly-%s" % [settings().project_folder(), kind]
	var entry := {"name": asset, "version": NEW.replace("0.1.0", "0.1.0" if modern else "1.1.0"), "size": 177751374}
	entry.sha256 = "0".repeat(64)
	FileAccess.open(release.path_join("nightly.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"assets": [entry]})
	)
	var old := OLD if modern else OLD.replace("0.1.0", "1.1.0")
	for lang in ["en", "he"]:
		settings().language = lang
		_drop_stamp()
		settings().pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		var fe: Node = load(settings().front_end_scene()).instantiate()
		root.add_child(fe)
		current_scene = fe
		await frames(5)
		var u := await line(old, release)
		await shot("update_line_" + lang)
		if is_instance_valid(u) and u.dont_ask.visible:
			u.dont_ask.button_pressed = true
			await shot("update_ticked_" + lang)
		u.queue_free()
		u = await line(entry.version, release)
		if not is_instance_valid(u) and OS.get_environment("UPDATE_FAKE_STALE") == "1":
			# Data with nothing to run again: the dialog of two steps, one of them a 120 MB download.
			u = updater.new()
			u.state = "swap"
			root.add_child(u)
			await frames(2)
			u._on_stale([{"download": 0}, {"download": 120000000}])
		if is_instance_valid(u):
			await shot("setup_line_" + lang)
			u.dont_ask.button_pressed = true
			await shot("setup_ticked_" + lang)
			u.queue_free()
		if modern:
			fe.pref_group = "updates"
			fe.show_page("prefs")
			await shot("prefs_" + lang)
		fe.queue_free()
		await frames(2)
	if OS.get_environment("UPDATE_NO_WIZARD") == "1":
		return
	# Update on the setup dialog: the wizard runs the stale steps, then the front end.
	for lang in ["en", "he"]:
		settings().language = lang
		_drop_stamp()
		settings().setup_update = true
		change_scene_to_file("res://setup/wizard.tscn")
		await frames(30)
		for i in 600:
			if current_scene != null and current_scene.get("running"):
				break
			await process_frame
		await frames(30)
		await shot("wizard_" + lang)
		# WIZARD_CANCEL=1: cancelled after the picture (a scratch copy with long steps), else to the front end.
		if OS.get_environment("WIZARD_CANCEL") == "1":
			current_scene._on_back()
			for i in 36000:
				if not current_scene.running:
					break
				await process_frame
			continue
		for i in 36000:
			if current_scene != null and current_scene.scene_file_path == settings().front_end_scene():
				break
			await process_frame
		await frames(30)
		await shot("back_" + lang)


## WIZARD_STAMP (a stamp under IAF_ASSETS_DIR) removed, so setup's line and each language's run have a step to run.
func _drop_stamp() -> void:
	if OS.get_environment("WIZARD_STAMP") != "":
		DirAccess.remove_absolute(settings().assets_dir().path_join(OS.get_environment("WIZARD_STAMP")))
