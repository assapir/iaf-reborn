# Persistent player preferences (autoload "Settings"), saved to user://settings.cfg.
extends Node

const PATH := "user://settings.cfg"
## "Better physics" (Preferences > Physics), id -> label, in page order: the flight-model options
## (ids of iaf_flight::BetterPhysics::OPTIONS, docs/flight-model.md §10), then fixes of original
## gameplay bugs outside the flight model (docs/damage.md). All off = the original. Stored in the
## [physics] section as bp_<id>.
const BETTER := {
	"flight_path_hold": "Flight-path hold (neutral stick)",
	"force_angles": "Forces at current AoA / sideslip",
	"start_lift": "Air start without jolt",
	"start_rpm": "Air start with engine spooled up",
	"start_alpha": "Air start trimmed",
	"landing_limits": "Real landing limits (sink, tail strike)",
	"spin_fixes": "Realistic spins",
	"fbw_departure": "F-16 / Lavi deep stall",
	"lift_rate_floor": "Low-speed lift rate fix",
	"low_speed_roll": "No reversed roll at low speed",
	"no_nose_wheel_lift": "No nose-wheel lift quirk",
	"ground_effect": "Ground effect",
	"fix_fall_heading": "Falling jets keep their heading",
	"fix_skill_damage": "No tougher enemies on easy AI levels",
	"fix_lock_threat": "Locked enemies know who locked them",
	"fix_stores_weight": "Stores weight fix",
}
## Stored preferences by config section: the original pages, then our own options (Extras tab).
const PREFS := {
	"sound": ["mute", "music_volume", "engine_volume", "sfx_volume", "speech_volume"],
	"graphics": ["terrain_detail", "object_detail", "visual_effects", "smoke_trails", "textured_sky",
		"shadows", "external_stores", "vsync"],
	"devices": ["flight_controls", "rudder", "throttle"],
	"gameplay": ["no_wind", "no_blackouts", "no_spins", "no_stalls", "easy_landing", "easy_aiming",
		"no_malfunctions", "ai_level", "invulnerable", "no_crashes", "unlimited_ammo", "unlimited_fuel",
		"flight_data", "weapon_data", "language", "show_info", "blackbox", "hud_ladder", "show_all_keys", "fullscreen"],
}

## Flight data: "original" (Jane's IAF 1998 numbers) or "real" (corrected real-world data for every flyable jet, docs/real-aircraft.md).
var flight_data := "original"
## Weapon data: "original" (the 1998 numbers of the bdb Weapons table and weapons.ibx) or "real"
## (public real-world data per weapon, docs/real-weapons.md). Separate from the flight data.
var weapon_data := "original"
## Briefing language: "en" or "he" (Hebrew only when the Hebrew pack is installed).
var language := "en"

## --- Original preferences (docs/front-end.md §12), original defaults (FUN_004f0750) ---------
## Sound page. The master volume is not stored (the original sets the Windows mixer).
var mute := false
var music_volume := 1.0
var engine_volume := 0.8
var sfx_volume := 1.0
var speech_volume := 1.0
## Graphics page (the original then overwrites these defaults from hardware detection).
var terrain_detail := 0.75
var object_detail := 1.0
var visual_effects := 1.0
var smoke_trails := true
var textured_sky := true
var shadows := true
var external_stores := true
## Devices page: 1 = joystick / pedals, 0 = keyboard.
var flight_controls := 1
var rudder := 0
var throttle := 0
## Gameplay page. ai_level: 0 Rookie, 1 Normal, 2 Expert.
var no_wind := false
var no_blackouts := false
var no_spins := false
var no_stalls := false
var easy_landing := true
var easy_aiming := false
var no_malfunctions := false
var ai_level := 1
var invulnerable := false
var no_crashes := false
var unlimited_ammo := false
var unlimited_fuel := false
## Preferences page shown when the screen opens (DAT_0083b8b4: zero = Sound on the first visit,
## then the last page used; not saved).
var pref_page := "Sound"
## "Better physics" (Preferences > Physics): BETTER id -> on.
var better := {}
## Our flight-info line at the bottom left (not in the original); Ctrl+F12 toggles it.
var show_info := true
## Blackbox: the flight recorder user://last_flight.csv (for diagnosing flights; on for now).
var blackbox := true
## HUD pitch ladder: "original" (v1.1: 12 px/deg hung on the flight path marker, docs/cockpit.md) or
## "conformal" (ours: rungs projected through the camera, on the world's horizon).
var hud_ladder := "original"
## Keyboard page: false = the original list (92 records); true (ours) also lists the hidden records
## (stick, rudder, RPM ± 5, pans, cheats, screen capture) so they can be rebound, e.g. on keyboards without a numpad.
var show_all_keys := false
## Window (ours, Extras page): false = a framed window, true = full screen (no window frame).
var fullscreen := false
## VSync (ours, on the Graphics page): frames in step with the display (no tearing, frame rate capped).
var vsync := true
## Key bindings changed on the Controls page (docs/controls.md): {record index: [key, joystick
## button]}, key = DIK | modifier << 16; records not listed keep the original default. Stored in the
## [keys] section as r<index> = [key, button].
var key_bindings := {}
## Mission picked in the front end (briefing id, e.g. 311), -1 = free flight.
var mission_id := -1
## Aircraft picked on the Jet list (original ids, FUN_00509d60): 0 F-15, 1 F-16, 2 F-4E,
## 3 F-4 2000, 4 Lavi, 5 Kfir, 6 Mirage.
var jet_id := 1
## The player's route as set on the TSD ([Vector2 world]); empty = the mission's own.
var route_override: Array = []
## Flight picked on the TSD (1..4 = Alpha..Delta; Fly / double-click makes its leader the player);
## 0 = the mission's default flight (mission_runtime.gd player_flight()).
var player_flight := 0
## Pylon loads the Arming screen put on the aircraft of each flight (docs/front-end.md §15):
## {flight 1..6: [[weapon id, count] × 9]}; a flight not listed keeps the mission's own. Cleared when
## a mission loads.
var arm_loadouts := {}
## Result of the last flight for the debrief screen: {passed, headline, notes} and what the pilot records
## keep {result, bonus, kills, losses} (mission_runtime.gd debrief_text()); empty = none.
var debrief := {}
## The pilot logged in on the Pilot Records screen (FUN_0051d940, not saved): id (DAT_0083b814, -1 none),
## name (DAT_0083b834), callsign (DAT_0083b848) and rank (DAT_0083b820, from the pilot's score).
var pilot_id := -1
var pilot_name := ""
var pilot_callsign := ""
var pilot_rank := ""


## Tests and captures run with IAF_DEFAULT_SETTINGS=1: defaults only, the player's settings file
## is neither read nor written.
func isolated() -> bool:
	return OS.get_environment("IAF_DEFAULT_SETTINGS") == "1"


func _init() -> void:
	for id in BETTER:
		better[id] = false


func _ready() -> void:
	# The original defaults, for the DEFAULT button (§12.2).
	for section in PREFS:
		for key in PREFS[section]:
			_defaults[key] = get(key)
	if isolated():
		# Test windows must never take the player's keyboard focus.
		get_window().unfocusable = true
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for section in PREFS:
			for key in PREFS[section]:
				var value = cfg.get_value(section, key, get(key))
				if typeof(value) == typeof(get(key)):
					set(key, value)
		for id in BETTER:
			var on = cfg.get_value("physics", "bp_" + id, false)
			if on is bool:
				better[id] = on
		if cfg.has_section("keys"):
			for k in cfg.get_section_keys("keys"):
				var v = cfg.get_value("keys", k)
				if k.begins_with("r") and k.substr(1).is_valid_int() and v is Array and v.size() == 2:
					key_bindings[int(k.substr(1))] = [int(v[0]), int(v[1])]
	if language == "he" and not hebrew_available():
		language = "en"
	apply_display()
	_update_splash()
	# The original icon (setup: iaf-convert icon) for compositors / desktops that take the window icon.
	var icon := assets_dir().path_join("converted/icon.png")
	if FileAccess.file_exists(icon):
		DisplayServer.set_icon(Image.load_from_file(icon))


var _applied_fullscreen := false


## The boot splash (project.godot: the English back0) follows the language: Godot reads override.cfg
## next to project.godot before drawing it, so in Hebrew it points at the Hebrew CD's back0 (setup
## --hebrew-iso; the Hebrew v1.1 patch itself put the English one back, docs/packs.md).
func _update_splash() -> void:
	if isolated():
		return
	var path := ProjectSettings.globalize_path("res://override.cfg")
	var he_splash := "res://../assets/converted/menu_he/img/back0.png"
	if language == "he" and FileAccess.file_exists(ProjectSettings.globalize_path(he_splash)):
		var cfg := ConfigFile.new()
		cfg.set_value("application", "boot_splash/image", he_splash)
		cfg.save(path)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Display settings that act at once (VSync, full screen).
func apply_display() -> void:
	# Only on a change, so a window made full screen by hand (macOS green button) is left alone. Deferred:
	# save() runs inside a click handler (the "Save changes?" box), and macOS resizes the window at once,
	# which freed the box mid-signal and crashed.
	if fullscreen != _applied_fullscreen:
		_applied_fullscreen = fullscreen
		DisplayServer.window_set_mode.call_deferred(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	# Off = uncapped: Mailbox (no tearing) where the platform offers it (Wayland has no Disabled mode),
	# else Disabled.
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	elif DisplayServer.get_name() == "Wayland":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func save() -> void:
	apply_display()
	if isolated():
		return
	_update_splash()
	var cfg := ConfigFile.new()
	for section in PREFS:
		for key in PREFS[section]:
			cfg.set_value(section, key, get(key))
	for id in BETTER:
		cfg.set_value("physics", "bp_" + id, better[id])
	for i in key_bindings:
		cfg.set_value("keys", "r%d" % i, key_bindings[i])
	cfg.save(PATH)


## The original default of a stored preference (the DEFAULT button, §12.2).
func default_value(key: String) -> Variant:
	return _defaults.get(key)


var _defaults := {}


func real_data() -> bool:
	return flight_data == "real"


func real_weapons() -> bool:
	return weapon_data == "real"


## True when the Hebrew packs are installed and converted (menus: assets/converted/menu_he;
## see docs/packs.md).
func hebrew_available() -> bool:
	return DirAccess.dir_exists_absolute(assets_dir().path_join("converted/menu_he"))


func assets_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()


## A JSON file's top-level object; {} when the file is missing or holds something else.
func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
