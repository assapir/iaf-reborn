# Persistent player preferences (autoload "Settings"), saved to user://settings.cfg.
extends Node

const PATH := "user://settings.cfg"

## Flight data: "original" (Jane's IAF 1998 numbers) or "real" (corrected real-world F-16 data).
var flight_data := "original"
## Briefing language: "en" or "he" (Hebrew only when the Hebrew pack is installed).
var language := "en"
## Mission picked in the front end (briefing id, e.g. 311), -1 = free flight.
var mission_id := -1


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		flight_data = cfg.get_value("gameplay", "flight_data", flight_data)
		language = cfg.get_value("gameplay", "language", language)
	if language == "he" and not hebrew_available():
		language = "en"


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "flight_data", flight_data)
	cfg.set_value("gameplay", "language", language)
	cfg.save(PATH)


func real_data() -> bool:
	return flight_data == "real"


## True when the Hebrew briefing pack is installed (assets/packs/he, see docs/packs.md).
func hebrew_available() -> bool:
	return DirAccess.dir_exists_absolute(assets_dir().path_join("packs/he"))


func assets_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()
