# The player's files out of the game and back in, for both games (reborn's Extras SETTINGS FILE and debrief Export
# flight data, iaf-reborn/menu/front_end.gd; Modern IAF's Settings and debrief, modern-iaf/menu/front_end.gd): a native
# file dialog, the settings file written or read by the game's own Settings rules, a flight recording copied.
extends RefCounted

const SETTINGS_FILTER := "*.cfg ; IAF settings"
const FLIGHT_FILTER := "*.jsonl ; Flight data"


## A native file dialog under `parent`: save or open one file of `filter` ("" any file), `done(path)` on a pick;
## `title` and the folder `dir` when given (reborn's Mission Creator LOAD).
static func dialog(
	parent: Node, saving: bool, filter: String, file: String, done: Callable, title := "", dir := ""
) -> FileDialog:
	var dlg := FileDialog.new()
	dlg.use_native_dialog = true
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	if filter != "":
		dlg.filters = PackedStringArray([filter])
	dlg.current_file = file
	if title != "":
		dlg.title = title
	if dir != "":
		dlg.current_dir = dir
	dlg.file_selected.connect(
		func(path: String) -> void:
			dlg.queue_free()
			done.call(path)
	)
	dlg.canceled.connect(dlg.queue_free)
	parent.add_child(dlg)
	dlg.popup_centered()
	return dlg


## Export: `values` (Settings.write_config's: {} = the settings as they are) as a settings file named `file` where the
## player picks. Import: `opened(path)` with the picked file (the game's own import_settings, then its screen again).
static func settings_file(parent: Node, saving: bool, file: String, values: Dictionary, opened: Callable) -> void:
	dialog(
		parent,
		saving,
		SETTINGS_FILTER,
		file,
		func(path: String) -> void:
			if saving:
				Settings.write_config(values).save(path)
			else:
				opened.call(path)
	)


## Reads the settings file at `path` into Settings and saves it; Hebrew without its font falls back to English.
## False when the file does not read.
static func import_settings(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	Settings.read_config(cfg)
	if Settings.language == "he" and not Settings.hebrew_available():
		Settings.language = "en"
	Settings.save()
	return true


## The flight recording `src` (JSON lines) copied where the player picks, named "iaf-<its name>".
static func export_flight(parent: Node, src: String) -> void:
	dialog(
		parent,
		true,
		FLIGHT_FILTER,
		"iaf-" + src.get_file(),
		func(path: String) -> void: DirAccess.copy_absolute(ProjectSettings.globalize_path(src), path)
	)
