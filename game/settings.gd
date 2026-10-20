# Persistent player preferences (autoload "Settings"), saved to user://settings.cfg.
extends Node

const PATH := "user://settings.cfg"
## The blackbox (terrain_view.gd _record): one file per flight, flight-<date>_<time>-m<mission>.jsonl, the newest
## BLACKBOX_KEEP kept; the debrief screen exports the last one (blackbox_file, this session's).
const BLACKBOX_DIR := "user://flights"
const SCREENSHOT_DIR := "user://screenshots"
const BLACKBOX_KEEP := 10
var blackbox_file := ""
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
	"ground_idle": "Real idle thrust on the ground (taxi speed)",
	"fix_fall_heading": "Falling jets keep their heading",
	"fix_skill_damage": "No tougher enemies on easy AI levels",
	"fix_lock_threat": "Locked enemies know who locked them",
	"fix_stores_weight": "Stores weight fix",
	"fix_bomb_burst": "Bombs burst at the ground",
	"fix_ghost_collision": "No collisions with hidden units / wrecks",
}
## "Better cockpit" (Extras page, one switch: Original / Better; docs/cockpit.md "Better cockpit"): id -> label, the
## cockpit improvements it turns on. Each one also has its own flag (cockpit_items, on by default), stored in the
## [cockpit] section as bc_<id>.
const BETTER_COCKPIT := {
	"turning_compass": "Turning panel compass / HSI",
	"aoa_indexer": "AoA indexer lights",
	"standby_instruments": "Live painted instruments",
	"warning_lamps": "Warning lamps for every failure",
	"engine_rpm": "RPM gauge from the engine's real RPM",
	"engine_temp": "Engine temperature gauge",
	"throttle_ab": "Throttle gauge shows the afterburner stages",
	"fuel_total": "Fuel gauge with the drop tanks, live fuel counter",
	"panel_clock": "Panel clock shows the mission time",
	"crisp_mfd": "Crisp MFD pages",
	"dials_by_label": "Gauges on their labelled dials",
	"ar_nws_lights": "AR/NWS lamp shows nose-wheel steering",
}
## Stored preferences by config section: the original pages, then our own options (Extras tab).
const PREFS := {
	"sound": ["mute", "music_volume", "engine_volume", "sfx_volume", "speech_volume"],
	"graphics":
	[
		"terrain_detail",
		"object_detail",
		"visual_effects",
		"smoke_trails",
		"textured_sky",
		"shadows",
		"external_stores",
		"vsync"
	],
	"devices": ["flight_controls", "rudder", "throttle", "joy_axes", "throttle_detent"],
	"gameplay":
	[
		"no_wind",
		"no_blackouts",
		"no_spins",
		"no_stalls",
		"easy_landing",
		"easy_aiming",
		"no_malfunctions",
		"ai_level",
		"invulnerable",
		"no_crashes",
		"unlimited_ammo",
		"unlimited_fuel",
		"flight_data",
		"weapon_data",
		"language",
		"show_info",
		"blackbox",
		"hud_ladder",
		"hud_style",
		"show_all_keys",
		"fullscreen",
		"imagery_israel",
		"imagery_outside",
		"antialiasing",
		"terrain_closeup",
		"sky",
		"upscaling",
		"night_lights",
		"water",
		"f35i_slot",
		"harm_targets",
		"models",
		"rolling_wheels",
		"particle_effects",
		"airbases",
		"cd_launcher",
		"wheel_scroll",
		"better_cockpit",
		"world_scale"
	],
}

## Flight data: "original" (Jane's IAF 1998 numbers) or "real" (corrected real-world data for every flyable jet,
## docs/real-aircraft.md).
var flight_data := "original"
## Weapon data: "original" (the 1998 numbers of the bdb Weapons table and weapons.ibx) or "real"
## (public real-world data per weapon, docs/real-weapons.md). Separate from the flight data.
var weapon_data := "original"
## HARM targets: "original" (the HARM sensor's own scan, docs/mfd.md "HARM (10)") or "rwr" (ours: the RWR's active
## emitters inside its cone, docs/deviations.md).
var harm_targets := "original"
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
## Ours (no page; settings.cfg [devices]): the Godot axis numbers of the original's DirectInput lX (stick x),
## lY (stick y), lZ (throttle) and lRz (rudder), docs/controls.md §4.2.
var joy_axes := [0, 1, 2, 3]
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
## Blackbox: the flight recorder user://flights/flight-<date>_<time>-m<mission>.jsonl, the newest BLACKBOX_KEEP kept.
var blackbox := true
## HUD pitch ladder: "original" (v1.1: 12 px/deg hung on the flight path marker, docs/cockpit.md) or
## "conformal" (ours: rungs projected through the camera, on the world's horizon).
var hud_ladder := "original"
## HUD symbology: "original" (the 1998 HUD) or "real" (ours: an F-16 Block 30/40 style HUD from public references,
## iaf_avionics::real_hud; docs/cockpit.md "Real HUD").
var hud_style := "original"
## Keyboard page: false = the original list (92 records); true (ours) also lists the hidden records
## (stick, rudder, RPM ± 5, pans, cheats, screen capture) so they can be rebound, e.g. on keyboards without a numpad.
var show_all_keys := false
## Window (ours, Extras page): false = a framed window, true = full screen (no window frame).
var fullscreen := false
## VSync (ours, on the Graphics page): frames in step with the display (no tearing, frame rate capped).
var vsync := true
## Terrain imagery per region (ours, Extras page; docs/imagery.md): "original" or a converted layer
## (terrain/imagery_layers.gd), e.g. "sentinel2" / "sentinel2_modern" outside Israel.
var imagery_israel := "original"
var imagery_outside := "original"
## Ours (Devices page): the throttle lever's detent (raw 0..100) that maps to MIL; −1 = off, the original's linear
## lever.
var throttle_detent := -1
## Render options for high resolutions (ours, Extras page; docs/rendering.md, terrain/render_options.gd):
## anti-aliasing "msaa4" (as before) / "msaa4_fxaa" / "taa" (TAA instead of MSAA); the terrain close up (detail texture,
## normal detail, 16× anisotropic filtering); the sky "original" (gradient) or "atmospheric" (physical scattering, sun
## disc).
var antialiasing := "msaa4"
var terrain_closeup := false
var sky := "original"
## Upscaling: "off" (native), "quality" (3D at 0.77 of the window) or "balanced" (0.67); MetalFX spatial on Metal, FSR 1
## on other drivers.
var upscaling := "off"
## Night lights (ours, Extras page; docs/rendering.md §5): "original" (the LT_ light sets as 1-px points) or
## "detailed" (glowing lights, the home airbases lit, the jets' navigation lights and strobes, stars, a moon,
## moonlight).
var night_lights := "original"
## Water (ours, Graphics → MORE; docs/rendering.md §1.3): false = the original flat-shaded water, true = waves, sun
## glint and sky reflection.
var water := false
## Models (ours, Extras page; docs/aircraft-models.md): "original" (the 1998 models) or "detailed" (our detailed
## models where there is one, util/gltf.gd DETAILED: the F-16D; visual only).
var models := "original"
## Rolling wheels (ours, Graphics → MORE; docs/part-animation.md §2.2): false = the wheels stand still, as on the
## original; true = the wheels of a model with separate wheel frames (the F-35I) roll with the ground speed.
var rolling_wheels := false
## Effects (ours, Graphics → MORE; docs/rendering.md §6, mission/gpu_fx.gd): false = the original
## billboards and ribbons; true = GPU particle explosions, smoke, missile trails, contrails and engine heat haze.
var particle_effects := false
## Airbases (ours, Graphics → MORE; docs/rendering.md §7, terrain/airbases.gd): "original" (the 1998 imagery) or
## "detailed" (near the ground, a procedural runway, taxiway and apron surface with markings; visual only).
var airbases := "original"
## CD launcher (ours, Extras page; docs/front-end.md §18.1): the CD's autorun poster (Jauto.exe) before the main menu.
var cd_launcher := false
## Mouse wheel (ours, Extras page; docs/front-end.md §12.9): "regular" (wheel down scrolls down) or "natural"
## (reversed, as on macOS trackpads). The wheel scrolls a list or text by its scroll arrows' step.
var wheel_scroll := "regular"
var _pan_rest := 0.0  # the trackpad pan not yet turned into a step
## Better cockpit (ours, Extras page): false = the original cockpit; true = the BETTER_COCKPIT items whose own flag
## (cockpit_items: id -> on) is on.
var better_cockpit := false
var cockpit_items := {}
## World scale (ours, Extras page; docs/world-scale.md): "original" (the models at their Present scale, ×2 for
## the jets) or "real" (true size, model_scale). Read at mission load. Its Extras row shows only with the dev flag
## IAF_DEV_WORLD_SCALE=1 until the airbases shrink too (the plan's step 9).
var world_scale := "original"
## Key bindings changed on the Controls page (docs/controls.md): {record index: [key, joystick
## button]}, key = DIK | modifier << 16; records not listed keep the original default. Stored in the
## [keys] section as r<index> = [key, button].
var key_bindings := {}
## Mission picked in the front end (briefing id, e.g. 311), -1 = free flight.
var mission_id := -1
## Aircraft picked on the Jet list (original ids, FUN_00509d60): 0 F-15, 1 F-16, 2 F-4E,
## 3 F-4 2000, 4 Lavi, 5 Kfir, 6 Mirage; -1 = the mission's own jet (missions not started from the Jet list).
var jet_id := -1
## Ours (Extras): the Jet list id whose button flies the F-35I instead (docs/f35i.md); -1 = off (the original's list).
var f35i_slot := -1
## The player's route as set on the TSD ([Vector2 world]); empty = the mission's own.
var route_override: Array = []
## Flight picked on the TSD (1..4 = Alpha..Delta; Fly / double-click makes its leader the player);
## 0 = the mission's default flight (mission_runtime.gd player_flight()).
var player_flight := 0
## Pylon loads the Arming screen put on the aircraft of each flight (docs/front-end.md §15):
## {Arming table slot 1..10 (MissionRuntime.flight_slots): [[weapon id, count] × 9]}; a flight not listed keeps the
## mission's own. Cleared when a mission loads.
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
	for id in BETTER_COCKPIT:
		cockpit_items[id] = true


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
		read_config(cfg)
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
		DisplayServer.window_set_mode.call_deferred(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
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
	write_config().save(PATH)


## The stored preferences as settings.cfg holds them; `values` (the Preferences working copy, for Export) overrides
## them.
func write_config(values := {}) -> ConfigFile:
	var cfg := ConfigFile.new()
	for section in PREFS:
		for key in PREFS[section]:
			cfg.set_value(section, key, values.get(key, get(key)))
	var bp: Dictionary = values.get("better", better)
	for id in BETTER:
		cfg.set_value("physics", "bp_" + id, bp[id])
	for id in BETTER_COCKPIT:
		cfg.set_value("cockpit", "bc_" + id, cockpit_items[id])
	var keys: Dictionary = values.get("key_bindings", key_bindings)
	for i in keys:
		cfg.set_value("keys", "r%d" % i, keys[i])
	return cfg


## Takes the stored preferences from a settings.cfg (values of the wrong type are ignored).
func read_config(cfg: ConfigFile) -> void:
	for section in PREFS:
		for key in PREFS[section]:
			var value = cfg.get_value(section, key, get(key))
			if typeof(value) == typeof(get(key)):
				set(key, value)
	for id in BETTER:
		var on = cfg.get_value("physics", "bp_" + id, false)
		if on is bool:
			better[id] = on
	for id in BETTER_COCKPIT:
		var on = cfg.get_value("cockpit", "bc_" + id, true)
		if on is bool:
			cockpit_items[id] = on
	key_bindings = {}
	if cfg.has_section("keys"):
		for k in cfg.get_section_keys("keys"):
			var v = cfg.get_value("keys", k)
			if k.begins_with("r") and k.substr(1).is_valid_int() and v is Array and v.size() == 2:
				key_bindings[int(k.substr(1))] = [int(v[0]), int(v[1])]


## The original default of a stored preference (the DEFAULT button, §12.2).
func default_value(key: String) -> Variant:
	return _defaults.get(key)


var _defaults := {}


## True when the "Better cockpit" switch and its item `id` (a BETTER_COCKPIT id) are both on.
func better_cockpit_on(id: String) -> bool:
	return better_cockpit and cockpit_items.get(id, false)


## The drawn scale of a model whose Present scale (bdb 0x65e) is `present` (docs/world-scale.md §3.2): `present`
## in Original; in Real 1:1 the true size 1, except a model that `keeps_present` (`keep`).
func model_scale(present: float, keep := false) -> float:
	return present if keep or world_scale != "real" else 1.0


## The multi-part layouts spread over a base or site: the bases' sign groups and the SA-5 site's cables.
const KEPT_LAYOUTS := ["signtlnf", "signrmon", "signrfid", "signdvid", "cabels"]


## A model that keeps its Present scale in Real 1:1 (docs/world-scale.md §3.2, §5): the ground layouts drawn on the
## base's ×2 picture (a light set LT_, a flat underlay: its Original height under `flat` m, KEPT_LAYOUTS), the
## effects (the cloud ×8, the crater ×7) and any ship not in SHIP_LENGTHS (bdb class 15, 16). Buildings, shelters and
## hangars are objects: true size.
static func keeps_present(path: String, raw_box: AABB, present: float, klass: int, flat: float) -> bool:
	var f := path.get_file().to_lower()
	return (
		f.begins_with("lt_")
		or f.get_basename() in KEPT_LAYOUTS
		or raw_box.size.y * present < flat
		or present >= 7.0
		or klass in [15, 16]
	)


## World scale Real 1:1: the ships' real hull lengths (m) by model (docs/world-scale.md §1.1): the Osa ("osa", and its
## light set LT_OSSA) 38.6 m, the small Osa ("smallosa", inferred: a Komar) 25.5 m, the Israeli missile boat ("satil",
## inferred: a Sa'ar 4.5) 61.7 m. Each model's hull runs its whole box.
const SHIP_LENGTHS := {"enmysp_h": 38.6, "lt_ossa": 38.6, "boat_h": 25.5, "isrlsp_h": 61.7}


## A ship's drawn scale in Real 1:1: its box's length to the real hull's; 0 for any other model or in Original.
func ship_scale(path: String, raw_box: AABB) -> float:
	var l: float = SHIP_LENGTHS.get(path.get_file().get_basename().to_lower(), 0.0)
	return l / maxf(raw_box.size.x, raw_box.size.z) if l > 0.0 and world_scale == "real" else 0.0


## World scale Real: every airbase at its real place (docs/world-scale.md §3.3). Sets up the extension's base moves
## for the current `world_scale` (once per change; the terrain, the mission data and the flight model read them) and
## returns true when the bases move.
var _bases_for := ""


func sync_bases() -> bool:
	if not ClassDB.class_exists("IafBases"):
		return false
	if _bases_for != world_scale:
		_bases_for = world_scale
		if not IafBases.setup(world_scale == "real", assets_dir()):
			push_warning("world scale real: the base data is missing (iaf.ibx, airbases.json): the bases stay")
	return IafBases.active()


## A world point (engine X, Y) moved with its base in World scale Real: [x, y, turn (deg, clockwise), scale, dz], or
## [] when it stays (Original, or away from every base).
func base_moved(x: float, y: float) -> PackedFloat64Array:
	return IafBases.map(x, y) if sync_bases() else PackedFloat64Array()


func real_data() -> bool:
	return flight_data == "real"


func real_weapons() -> bool:
	return weapon_data == "real"


## Scroll steps for a wheel or trackpad pan event (ours, the original has no wheel): +1 = one step down, -1 = up,
## 0 = none; "natural" reverses them. A pan adds up its delta.y (+ = down, as Godot's ScrollContainer reads it) and
## steps once per whole unit.
func wheel_steps(event: InputEvent) -> int:
	var n := 0
	if event is InputEventMouseButton and event.pressed:
		n = {MOUSE_BUTTON_WHEEL_DOWN: 1, MOUSE_BUTTON_WHEEL_UP: -1}.get(event.button_index, 0)
	elif event is InputEventPanGesture:
		_pan_rest += event.delta.y
		n = int(_pan_rest)  # ponytail: one step per pan unit; scale it if trackpads feel slow / fast
		_pan_rest -= n
	return -n if wheel_scroll == "natural" else n


## True when the Hebrew packs are installed and converted (menus: assets/converted/menu_he;
## see docs/packs.md).
func hebrew_available() -> bool:
	return DirAccess.dir_exists_absolute(assets_dir().path_join("converted/menu_he"))


## The assets folder: <repo>/assets, or $IAF_ASSETS_DIR (tests: the setup wizard on a scratch folder).
func assets_dir() -> String:
	if OS.get_environment("IAF_ASSETS_DIR") != "":
		return OS.get_environment("IAF_ASSETS_DIR")
	return ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()


## txt/msgs.trx lines for the current language. In Hebrew, a line the Hebrew pack leaves in English (the
## preflight.us menu pack keeps all of msgs.trx English) takes our Hebrew (game/menu/strings_he.json "msgs").
func msgs() -> PackedStringArray:
	var he := language == "he"
	var dir := assets_dir().path_join("converted/menu_he" if he else "converted/menu")
	var lines: PackedStringArray = String(load_json(dir.path_join("strings.json")).get("msgs", "")).split("\n")
	if he:
		var tr: Dictionary = load_json("res://menu/strings_he.json").get("msgs", {})
		for i in lines.size():
			lines[i] = tr.get(lines[i].strip_edges(), lines[i])
	return lines


## A JSON file's top-level object; {} when the file is missing or holds something else.
func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## An original .ibx (INI) file: {section: {key: value}}, the values unquoted strings, ';' starting a
## comment, keys before any section under "". ConfigFile can't read the unquoted values. {} when missing.
func load_ibx(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var cur := {}
	var sections := {"": cur}
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var l := raw.get_slice(";", 0).strip_edges()
		if l.begins_with("["):
			cur = {}
			sections[l.substr(1, l.find("]") - 1)] = cur
		elif "=" in l:
			var eq := l.find("=")
			cur[l.substr(0, eq).strip_edges()] = l.substr(eq + 1).strip_edges()
	return sections


## Quits the game (also the window's close button). Every audio player is freed first and the audio thread gets
## QUIT_AUDIO_S to drop their playbacks on its next mix (~0.1 s measured): a player that ever played still holds its
## playback when the audio server shuts down before the scene, reported as leaked at exit.
const QUIT_AUDIO_S := 0.15


func quit() -> void:
	_free_sounds()
	get_tree().paused = true
	await get_tree().create_timer(QUIT_AUDIO_S, true, false, true).timeout
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		get_tree().auto_accept_quit = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func _free_sounds() -> void:
	for p in get_tree().root.find_children("*", "", true, false):
		if p is AudioStreamPlayer or p is AudioStreamPlayer2D or p is AudioStreamPlayer3D:
			p.stop()
			p.queue_free()
