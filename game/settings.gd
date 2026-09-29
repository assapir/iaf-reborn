# Persistent player preferences (autoload "Settings"), saved to user://settings.cfg.
extends Node

const PATH := "user://settings.cfg"

## Flight data: "original" (Jane's IAF 1998 numbers) or "real" (corrected real-world F-16 data).
var flight_data := "original"
## Briefing language: "en" or "he" (Hebrew only when the Hebrew pack is installed).
var language := "en"
## Mission picked in the front end (briefing id, e.g. 311), -1 = free flight.
var mission_id := -1
## Aircraft picked on the Jet list (original ids, FUN_00508470): 0 F-15, 1 F-16, 2 F-4E,
## 3 F-4 2000, 4 Lavi, 5 Kfir, 6 Mirage.
var jet_id := 1


## Tests and captures run with IAF_DEFAULT_SETTINGS=1: defaults only, the player's settings file
## is neither read nor written.
func isolated() -> bool:
	return OS.get_environment("IAF_DEFAULT_SETTINGS") == "1"


func _ready() -> void:
	if isolated():
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		flight_data = cfg.get_value("gameplay", "flight_data", flight_data)
		language = cfg.get_value("gameplay", "language", language)
	if language == "he" and not hebrew_available():
		language = "en"


func save() -> void:
	if isolated():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "flight_data", flight_data)
	cfg.set_value("gameplay", "language", language)
	cfg.save(PATH)


func real_data() -> bool:
	return flight_data == "real"


## True when the Hebrew packs are installed and converted (menus: assets/converted/menu_he;
## see docs/packs.md).
func hebrew_available() -> bool:
	return DirAccess.dir_exists_absolute(assets_dir().path_join("converted/menu_he"))


func assets_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()
