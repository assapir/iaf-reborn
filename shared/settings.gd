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
	"fbw_departure": "Fly-by-wire deep stall",
	"lift_rate_floor": "Low-speed lift rate fix",
	"low_speed_roll": "No reversed roll at low speed",
	"no_nose_wheel_lift": "No nose-wheel lift quirk",
	"ground_effect": "Ground effect",
	"ground_idle": "Real idle thrust on the ground (taxi speed)",
	"brake_pitch": "Nose dips under braking",
	"asymmetric_stores": "Unbalanced stores roll the jet",
	"wind": "Wind and turbulence",
	"engine_spool": "Engine spool-up per real engine",
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
	"smooth_needles": "Needles follow with an instrument's lag",
	"metric_gauges": "Metric units on the MiGs' Russian dials",
	"uua": "MiG-29 AoA / g meter",
	"radar_alt": "MiG-29 radar altimeter",
	"rsbn_counter": "MiG-23 range counter shows the waypoint distance",
	"spo15": "MiG-23 SPO-15 warning lamps",
	"pnp_bars": "MiG-23 HSI bars follow the ILS",
	"hyd_gauge": "MiG-23 hydraulic pressure gauge",
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
		"vsync",
		"hud_brightness",
		"mfd_brightness"
	],
	"devices":
	["flight_controls", "rudder", "throttle", "joy_axes", "throttle_detent", "stick_response", "rocker_trim"],
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
		"hud_view",
		"bingo_lbs",
		"show_all_keys",
		"fullscreen",
		"imagery_israel",
		"imagery_outside",
		"antialiasing",
		"terrain_closeup",
		"sky",
		"colour_grading",
		"upscaling",
		"night_lights",
		"water",
		"f35i_slot",
		"harm_targets",
		"models",
		"model_detail",
		"rolling_wheels",
		"particle_effects",
		"rain",
		"clouds",
		"airbases",
		"ground_textures",
		"ground_roads",
		"scenery",
		"scenery_far",
		"building_palette",
		"shadow_reach",
		"town_labels",
		"cd_launcher",
		"wheel_scroll",
		"better_cockpit",
		"better_mc",
		"rwr_search",
		"briefing_map",
		"night_vision",
		"world_scale",
		"f16_variant",
		"f15_variant",
		"modern_weapons",
		"bomb_release",
		"real_mfds",
		"cockpit_3d",
		"flight_model"
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
## Graphics page: the defaults the original's hardware detection gives a top-tier machine (FUN_00402510 /
## FUN_00402330; docs/deviations.md): TERRAIN DETAIL (det − 1) · 0.25 = 1.0 (the ctor's 0.75 before it).
var terrain_detail := 1.0
## The HUD symbols' day brightness, 0..1 (Modern IAF, hud_daylight): the F-16's SYM wheel (cockpit_controls) and the key
## Change HUD colour set it; stored like a physical knob's position, with no Preferences row. The original game never
## reads it.
var hud_brightness := 1.0
## The 3D cockpit's displays' brightness, 0.1..1 (Modern IAF, cockpit_controls): the F-35I's MFD BRT knob sets it
## (command 216); stored like a physical knob's position, with no Preferences row. The original game never reads it.
var mfd_brightness := 1.0
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
## Real HUD view: "original" (the 50° cockpit view) or "real" (ours: with the Real HUD, the cockpit view widens so
## the HUD glass spans the jet's real HUD field of view; cockpit.gd focal_length, docs/real-hud.md "Real view").
var hud_view := "original"
## Bingo fuel (lb, ours): the Real HUD's FUEL cue below it (the F-16, the Kurnass 2000); the real pilot sets it.
var bingo_lbs := 1500
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
## Ours (Devices page "Stick response"): "linear" = the original's stick, "soft" = a 5 % dead zone and an expo curve
## (joystick.gd `stick_curve`).
var stick_response := "linear"
## Ours (Devices page "Throttle rocker"): false = the original's four axes, true = the rocker on a 5th axis trims roll
## (joystick.gd `rocker`).
var rocker_trim := false
## Render options for high resolutions (ours, Extras page; docs/rendering.md, terrain/render_options.gd):
## anti-aliasing "msaa4" (as before) / "msaa4_fxaa" / "taa" (TAA instead of MSAA) / "temporal" (the temporal upscaler
## anti-aliases: FSR 2.2, MetalFX temporal on Metal; at the Upscaling row's scale); the terrain close up (detail
## texture, normal detail, 16× anisotropic filtering); the sky "original" (gradient) or "atmospheric" (physical
## scattering, sun disc) or "levant" (the same, tuned toward a dusty Levant summer).
var antialiasing := "msaa4"
var terrain_closeup := false
var sky := "original"
## Colour grading (ours, Graphics → MORE; docs/rendering.md §1.9, terrain/render_options.gd): "original" (the photo
## lit as it is) or "natural" (the photo's albedo toward a real ground's reflectance, a little contrast and saturation
## after the tone mapper, the auto-exposure taken from the ground).
var colour_grading := "original"
## Upscaling: "off" (native), "quality" (3D at 0.77 of the window) or "balanced" (0.67); MetalFX spatial on Metal, FSR 1
## on other drivers, or the temporal upscaler with anti-aliasing "temporal".
var upscaling := "off"
## Night lights (ours, Extras page; docs/rendering.md §5): "original" (the LT_ light sets as 1-px points) or
## "detailed" (glowing lights, the home airbases lit, the jets' navigation lights and strobes, stars, a moon,
## moonlight).
var night_lights := "original"
## Night vision (ours, Graphics → MORE; docs/rendering.md §8): Shift+N puts on / takes off the goggles (a green
## image-intensified 3D view under the cockpit).
var night_vision := false
## Water (ours, Graphics → MORE; docs/rendering.md §1.3): false = the original flat-shaded water, true = waves, sun
## glint and sky reflection.
var water := false
## Models (ours, Extras page; docs/aircraft-models.md): "original" (the 1998 models) or "detailed" (our detailed
## models where there is one, util/gltf.gd DETAILED: the F-16D; visual only).
var models := "original"
## F-16 (ours, Extras page; docs/f16i.md): "barak" (the game's early-1990s F-16D) or "sufa" (the IAF's F-16I
## Block 52+ with conformal fuel tanks: flight data, radar, model, arming art and weapons). Every F-16 in a mission,
## the player's and the AI's, follows it.
var f16_variant := "barak"
## F-15 (ours, Extras page; docs/f15i.md): "baz" (the game's F-15C) or "raam" (the IAF's F-15I Ra'am with conformal
## fuel tanks: flight data, radar, gun, weapons, arming art and the model setup makes). Every F-15 in a mission, the
## player's and the AI's, follows it.
var f15_variant := "baz"
## Weapons (ours, Extras page; docs/weapons.md §13): false = the original 1998 arming lists; true = the modern weapons
## (shared/weapons/modern_weapons.gd) also on every jet a public source shows carrying them. The F-16I Sufa and the
## F-35I always have theirs.
var modern_weapons := false
## Model detail (ours, Graphics → MORE; docs/rendering.md §9, util/model_detail.gd): "original" or
## "ambientcg" (the original models with fine CC0 surface detail up close: painted metal, rubber, concrete). Read when a
## model loads.
var model_detail := "original"
## Rolling wheels (ours, Graphics → MORE; docs/part-animation.md §2.2): false = the wheels stand still, as on the
## original; true = the wheels of a model with separate wheel frames (the F-35I) roll with the ground speed.
var rolling_wheels := false
## Effects (ours, Graphics → MORE; docs/rendering.md §6, mission/gpu_fx.gd): false = the original
## billboards and ribbons; true = GPU particle explosions, smoke, missile trails, contrails, engine heat haze and
## condensation on the jets (mission/vapour_fx.gd).
var particle_effects := false
## Rain (ours, Graphics → MORE; docs/rendering.md §10, terrain/weather.gd): "off" (the original: no weather, whatever
## the mission says), "light" or "heavy" (falling rain, drops on the canopy, wet ground, a shorter visibility). A
## mission with a weather of its own (flight_weather) rains at that instead; the others at this level.
var rain := "off"
## Clouds (ours, Graphics → MORE; docs/rendering.md §2.1, terrain/volumetric_clouds.gd): "original" (the 1998 flat layer
## of TEXTURED SKY) or "volumetric" (raymarched cumulus, and the rain's deck in the rain; for strong GPUs).
var clouds := "original"
## Airbases (ours, Graphics → MORE; docs/rendering.md §7, terrain/airbases.gd): "original" (the 1998 imagery) or
## "detailed" (near the ground, a procedural runway, taxiway and apron surface with markings; visual only).
var airbases := "original"
## Ground textures (ours, Graphics → MORE; docs/rendering.md §1.4, terrain/ground_textures.gd): "original" (the close
## up's noise, the procedural pavement) or "ambientcg" (CC0 asphalt, concrete, sand, gravel, grass, soil and rock
## textures near the camera; downloaded by setup, else the row's choice is greyed out and the look stays Original).
var ground_textures := "original"
## Roads (ours, Graphics → MORE; docs/rendering.md §1.8, terrain/ground_roads.gd): "original" (the imagery's own) or
## "detailed" (OpenStreetMap's roads drawn on the ground near the camera where the imagery is too coarse to show them,
## and with Night lights Detailed lamps along the lit roads). Needs setup's road layer (docs/scenery.md §6).
var ground_roads := "original"
## Scenery (ours, Graphics → MORE; docs/scenery.md §3, terrain/scenery.gd): "off", "on" (buildings and trees over the
## Survey 2 m photo) or "detailed" (the same with the facades, the streets' occlusion and the roof clutter, §3.3);
## only with setup's scenery and a Survey 2 m layer as the Israel imagery, else it stays off.
var scenery := "off"
## Far towns (ours, Graphics → MORE; docs/scenery.md §3.1): "full" (every building to the scenery's far end) or
## "light" (beyond the near model's 2.5 km a dense town keeps its tall and large buildings only: cheaper, the low
## houses show from 2.5 km in).
var scenery_far := "full"
## Building colours (ours, Graphics → MORE; docs/scenery.md §3.4): false = Photo (the walls fade to the photo's colour
## far away), true = Palette (every wall keeps its own palette colour, warmed toward cream and lit brighter, the light
## flat and gabled roofs lifted out of the photo's grey).
var building_palette := false
## Shadow reach (ours, Graphics → MORE; docs/rendering.md §3.1): "original" (the sun's shadows to 400 m from the
## camera) or "far" (to 2.5 km: the towns' buildings cast shadows on the streets below a flying jet; the first split
## stays 40 m, the cockpit's own 4 m).
var shadow_reach := "original"
## Town labels (ours, Extras page; docs/scenery.md §3.5, terrain/town_labels.gd): the towns' names over the view at
## their places. Needs the places setup's scenery step writes.
var town_labels := false
## CD launcher (ours, Extras page; docs/front-end.md §18.1): the CD's autorun poster (Jauto.exe) before the main menu.
var cd_launcher := false
## Mouse wheel (ours, Extras page; docs/front-end.md §12.9): "regular" (wheel down scrolls down) or "natural"
## (reversed, as on macOS trackpads). The wheel scrolls a list or text by its scroll arrows' step.
var wheel_scroll := "regular"
var _pan_rest := 0.0  # the trackpad pan not yet turned into a step
var _airframes := {}  # airframe_def's: id -> the resolved definition
var _airframe_ids := {}  # airframe_id's: type code -> id, for the switches _airframe_ids_for
var _airframe_ids_for := []
## Better cockpit (ours, Extras page): false = the original cockpit; true = the BETTER_COCKPIT items whose own flag
## (cockpit_items: id -> on) is on.
var better_cockpit := false
var cockpit_items := {}
## Mission Creator: Better (ours, Extras page; docs/front-end.md §19.4): false = the original screen; true = its WIND
## and FROM combos, whose wind FLY writes into mission 0x29a.
var better_mc := false
## RWR: Real (ours, Extras page; docs/rwr.md §7): the RWR also shows the SAM / AAA radars searching the jet.
var rwr_search := false
## Briefing map (ours, Extras page; docs/front-end.md "Modern map"): "original" (the 1998 map) or "modern" (the
## cities at their real places on the TSD / briefing / mission editor map, menu/tsd_map.gd; the OpenStreetMap map
## there and on the cockpit's TSD and ground map, `cockpit_extra`).
var briefing_map := "original"
## Bomb release (ours, Extras page; docs/weapons.md §9.10): "original" (one store per ripple tick, FUN_0053b680's
## station order) or "real" (the real stores management: SGL / PAIRS, the quantity in release pulses).
var bomb_release := "original"
## MFDs (ours, Extras page; docs/mfd.md §9): "original" (the 1998 pages) or "real" (the F-16D Barak's real head-down
## formats, in green; with them Modern IAF's RWR symbols and ADI ball, `cockpit_extra`). The F-16I Sufa always draws
## them, in colour (`real_mfd`).
var real_mfds := "original"
## Cockpit (ours, Extras page; docs/cockpit.md "3D cockpit"): "original" (the 1998 2D panel) or "3d" (a 3D cockpit
## with our live displays and HUD, cockpit/cockpit3d.gd): the FlightGear F-16's front cockpit for the Barak and the
## Sufa, ours for the F-35I.
## Read at mission load.
var cockpit_3d := "original"
## Flight model (ours, Physics page; docs/deviations.md §2): "original" or "6dof": the player's modern jet (its
## aircraft definition's `sixdof`) flies Modern IAF's 6-DoF from the sim's own data (sixdof_data). Read at mission load.
var flight_model := "original"
## World scale (ours, Extras page; docs/world-scale.md): "original" (the models at their Present scale, ×2 for
## the jets) or "real" (true size, model_scale). Read at mission load.
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
## The Mission Creator's state (the exe's global record DAT_0083ca10, docs/formats/mcr.md; IafMcr's Dictionary):
## zeroed when the MC screen opens, read by the mission 0x29a it builds (Replay builds it again).
var mc := {}
## Mission 0x29a as FLY built it from `mc` ([{name, data}], IafMcr.build); MissionRuntime.mission_files(0x29a) reads it.
var mc_files: Array = []
## The mission editor's Fly (fly_edited, docs/mission-editor.md), run time only: the edited mission's files ([{name,
## data}], the main file first, then its base missions), which MissionRuntime.mission_files gives for any id while set;
## its briefing ({en, he} plain text, the TSD's), the flight to select on the TSD (1..4, 0 the default), and the user://
## file the editor reopens after.
var mission_files_override: Array = []
var briefing_override := {}
var return_to_editor := false
var editor_flight := 0
var editor_file := ""
## The edited mission's year while it flies (0 = none; mission-editor.md §12).
var editor_year := 0.0


## The year the flight is set in: the edited mission's own, else the original's by its id (mission_year.rs
## default_year: 1967, 1973, 1982 or 1998).
func mission_year() -> float:
	if return_to_editor and editor_year > 0.0:
		return editor_year
	if not ClassDB.class_exists("IafMissionEdit"):
		return 1998.0
	return float(ClassDB.class_call_static("IafMissionEdit", "default_year", mission_id))


## Flight picked on the TSD (1..4 = Alpha..Delta; Fly / double-click makes its leader the player);
## 0 = the mission's default flight (mission_runtime.gd player_flight()).
var player_flight := 0
## Pylon loads the Arming screen put on the aircraft of each flight (docs/front-end.md §15):
## {Arming table slot 1..10 (MissionRuntime.flight_slots): [[weapon id, count] × 9]}; a flight not listed keeps the
## mission's own. Cleared when a mission loads.
var arm_loadouts := {}
## Ours (docs/weapons.md §13.2): the GPS bombs' pre-planned targets set on the briefing TSD, {flight number: {station
## 0..8: [world x, world y]}}; a station not listed takes the route's target waypoint. Cleared when a mission loads.
var gps_targets := {}
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
	_install_log()
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
		_log_startup()
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		read_config(cfg)
	if language == "he" and not hebrew_available():
		language = "en"
	_log_startup()
	apply_display()
	_update_splash()
	_set_icon()


## The original icon (setup: iaf-convert icon) for compositors / desktops that take the window icon.
func _set_icon() -> void:
	var icon := converted("icon.png")
	if FileAccess.file_exists(icon):
		DisplayServer.set_icon(Image.load_from_file(icon))


## The game log's first lines (docs/logs.md): the build, the machine, this log file and the settings changed from the
## defaults, so a log sent in names everything needed to reproduce it.
func _log_startup() -> void:
	var info = ClassDB.instantiate("IafInfo") if ClassDB.class_exists("IafInfo") else null
	var mem: Dictionary = OS.get_memory_info()
	var win := get_window()
	print(
		(
			"%s %s | Godot %s | %s %s, %s, %d cores, %d GB RAM"
			% [
				ProjectSettings.get_setting("application/config/name"),
				info.commit() if info != null else "(no extension)",
				Engine.get_version_info().string,
				OS.get_name(),
				OS.get_version_alias() if OS.get_version_alias() != "" else OS.get_version(),
				OS.get_processor_name(),
				OS.get_processor_count(),
				int(mem.get("physical", 0) / 1073741824.0 + 0.5)
			]
		)
	)
	print(
		(
			"gpu: %s (%s), %s %s | window %s, scale %.2f"
			% [
				RenderingServer.get_video_adapter_name(),
				RenderingServer.get_video_adapter_vendor(),
				RenderingServer.get_current_rendering_method(),
				RenderingServer.get_video_adapter_api_version(),
				win.size,
				win.content_scale_factor
			]
		)
	)
	var log_path: String = ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")
	# The game's own log (a --log-file run writes elsewhere; Godot does not show scripts that argument).
	print("game log: %s | assets: %s" % [ProjectSettings.globalize_path(log_path), assets_dir()])
	print("settings changed from the defaults: %s" % [changed_settings()])


## The preferences that differ from the defaults, {key: value}, plus the Physics switches on (`physics`) and the
## Better cockpit items off (`cockpit_off`); only the settings the game has (has_setting).
func changed_settings() -> Dictionary:
	var out := {}
	for key in _defaults:
		if get(key) != _defaults[key] and has_setting(key):
			out[key] = get(key)
	var on := better.keys().filter(func(id): return better[id])
	if not on.is_empty() and has_setting("better"):
		out["physics"] = on
	var off := cockpit_items.keys().filter(func(id): return not cockpit_items[id])
	if not off.is_empty() and has_setting("cockpit_items"):
		out["cockpit_off"] = off
	return out


## True for a setting this game has: the logs (changed_settings, the recorder) print only those. The original game:
## every one; Modern IAF answers for its own (sim_settings.gd).
func has_setting(_key: String) -> bool:
	return true


## {key: value} of `keys` this game has (has_setting).
func settings_of(keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		if has_setting(k):
			out[k] = get(k)
	return out


var _applied_fullscreen := false
var _applied_vsync = null  # null: not applied yet


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


## The command that starts the setup wizard: ./setup, on Windows .\setup.ps1 (tools/windows/launch.ps1).
static func setup_command() -> String:
	return ".\\setup.ps1" if OS.get_name() == "Windows" else "./setup"


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
	# else Disabled. Only on a change too: setting the mode rebuilds the swapchain, and save() runs in flight
	# (the SYM wheel's every step, Ctrl+F12).
	if vsync == _applied_vsync:
		return
	_applied_vsync = vsync
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
	# Ground textures and Model detail only with setup's download (docs/rendering.md §1.4, §9): a saved "ambientcg"
	# without it is Original.
	if ground_textures == "ambientcg" and not load("res://shared/terrain/ground_textures.gd").available():
		ground_textures = "original"
	if model_detail == "ambientcg" and not load("res://shared/util/model_detail.gd").available():
		model_detail = "original"
	# Scenery only with setup's files over a Survey 2 m layer (docs/scenery.md §3).
	var survey := imagery_israel in ["mapi2015", "mapi2015_modern"]
	if scenery not in ["off", "on", "detailed"]:
		scenery = "off"
	if scenery_far not in ["full", "light"]:
		scenery_far = "full"
	if (
		scenery != "off"
		and not ((survey or scenery_everywhere()) and load("res://shared/terrain/scenery.gd").available())
	):
		scenery = "off"


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


## Better physics "Wind and turbulence": the flight's tower wind [knots, from deg] (pick_wind), picked once per
## flight so the start, the AI, the tower and the taxi signs share the runway into the wind (docs/autopilot.md §2.4);
## [] with the switch off (the radio then picks at its start, as the original). terrain_view clears it at the end.
var flight_wind: Array = []
var _flight_wind_id := -1
## The training missions (basic 311–315, combat 321–326): the tower keeps their runway (their instructor markers and
## circuits are laid out for it); every one has a calm wind (misc 0x46a = 0), so they fly calm.
const TRAINING_MISSIONS := [311, 312, 313, 314, 315, 321, 322, 323, 324, 325, 326]


## FUN_00551320: the mission's wind [knots, from deg] from its misc: 0x46a of 0, 10, 15 or 20 kt as is, any other
## value a random one of those (rand() % 4); from: misc 0x474, or 0x46a itself above 60 (the pair stored swapped).
static func pick_wind(misc: Dictionary) -> Array:
	var w := int(misc.get("0x46a", 0))
	return [w if w in [0, 10, 15, 20] else [0, 10, 15, 20][randi() % 4], w if w > 60 else int(misc.get("0x474", 0))]


## Mission `id`'s tower wind with Better physics "Wind and turbulence" (`flight_wind`, picked from `misc` once per
## flight), and the bases the tower turns into it (IafBases.set_wind; none with the switch off, NO WIND, a calm or a
## training mission). Call after sync_bases.
func runway_wind(id: int, misc: Dictionary) -> Array:
	if not (better.get("wind", false) or OS.get_cmdline_user_args().has("--better")):
		flight_wind = []
	elif id != _flight_wind_id or flight_wind.is_empty():
		flight_wind = pick_wind(misc)
	_flight_wind_id = id
	var kt := 0.0 if flight_wind.is_empty() or no_wind or id in TRAINING_MISSIONS else float(flight_wind[0])
	if ClassDB.class_exists("IafBases"):
		IafBases.set_wind(kt, float(flight_wind[1]) if kt > 0.0 else 0.0, airbases_file(), own_dir())
	return flight_wind


## The flight's weather (ours, docs/rendering.md §10): "clear", "light" or "heavy" from the main file's misc `weather`
## (docs/formats/mis.md; the mission editor's and the Mission Creator's), "" for a mission without one (the originals:
## the Rain switch's level). "random" picks one of the three once per flight. terrain_view clears it at the end.
var flight_weather := ""
var _flight_weather_for := ""


## Mission `id`'s weather into `flight_weather` (MissionRuntime.mission_files, for the main file).
func mission_weather(id: int, misc: Dictionary) -> void:
	var w := String(misc.get("weather", ""))
	if w == "random":
		if _flight_weather_for != "%d random" % id:
			flight_weather = ["clear", "light", "heavy"][randi() % 3]
	else:
		flight_weather = w if w in ["clear", "light", "heavy"] else ""
	_flight_weather_for = "%d %s" % [id, w]


## The flight ended: the next one picks its wind and weather again, and no base stays turned.
func clear_runway_wind() -> void:
	flight_wind = []
	_flight_wind_id = -1
	flight_weather = ""
	_flight_weather_for = ""
	if ClassDB.class_exists("IafBases"):
		IafBases.set_wind(0.0, 0.0, airbases_file(), own_dir())


## World scale Real: every airbase at its real place (docs/world-scale.md §3.3). Sets up the extension's base moves
## for the current `world_scale` (once per change; the terrain, the mission data and the flight model read them) and
## returns true when the bases move.
var _bases_for := ""


func sync_bases() -> bool:
	if not ClassDB.class_exists("IafBases"):
		return false
	if _bases_for != world_scale:
		_bases_for = world_scale
		if not IafBases.setup(world_scale == "real", assets_dir(), own_dir()):
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


## Ours: the aircraft definition (shared/extra/planes/<id>/airframe.json, docs/adding-a-plane.md "Modern planes") a jet
## of bdb type `type_code` flies as with the Extras switches; {} for a 1998 jet without one (its tables decide).
## Shared and read-only.
func airframe(type_code: int) -> Dictionary:
	return airframe_def(airframe_id(type_code))


## The definition id a jet of bdb type `type_code` flies as (the adapter, IafAirframe.id_for), "" for none.
func airframe_id(type_code: int) -> String:
	if _airframe_ids_for != [f16_variant, f15_variant]:
		_airframe_ids.clear()
		_airframe_ids_for = [f16_variant, f15_variant]
	if not _airframe_ids.has(type_code):
		_airframe_ids[type_code] = ClassDB.class_call_static(
			"IafAirframe", "id_for", type_code, f16_variant, f15_variant
		)
	return _airframe_ids[type_code]


## The resolved definition `id` (IafAirframe.definition: its base merged in), {} for none; read once.
func airframe_def(id: String) -> Dictionary:
	if id == "":
		return {}
	if not _airframes.has(id):
		var d: Dictionary = ClassDB.class_call_static("IafAirframe", "definition", id)
		d.make_read_only()
		_airframes[id] = d
	return _airframes[id]


## The name the cockpit tables key a cockpit dir (or a Real HUD key) on: the F-16's "f16", the F-4E's "phantom" … (the
## HUD's, MFD's and gauges' tables, the 3D cockpit's F-16 check): the dir's own name. Modern IAF's Settings map its own
## dirs to the family's (modern-iaf/docs/cockpit.md §4).
func cockpit_folder(dir: String) -> String:
	return dir.get_file()


## The F-16's real MFD formats (docs/mfd.md §9): its aircraft definition's mfd ("colour" on the Sufa, always), "green"
## on the Barak with MFDs on Real, "" the original pages. `cockpit` is the cockpit's directory name (the F-16's is
## "f16").
func real_mfd(cockpit: String) -> String:
	if cockpit != "f16":
		return ""
	var own: String = airframe(100).get("mfd", "")
	if own != "":
		return own
	return "green" if real_mfds == "real" else ""


## Ours: the original game's Extras copy of a cockpit file (converted/extras/cockpit, made by setup's extras step from
## Modern IAF's display data; docs/deviations.md), in place of the cockpit `folder`'s own `name`; "" = its own. Briefing
## map on Modern: the OpenStreetMap TSD map and its ground-map picture (map.json, isr.png) on every jet, and the
## front-end TSD's (tsd.json, menu/tsd.gd). The F-16's
## real MFDs (`real_mfd`): its RWR symbols (rwrsymb.png) and ADI ball (f16adi.png, the [LENHORIZON] ball).
func cockpit_extra(folder: String, name: String) -> String:
	var own := ""
	if name in ["map.json", "tsd.json", "isr.png"] and briefing_map == "modern":
		own = name
	elif name in ["rwrsymb.png", "f16adi.png"] and real_mfd(folder) != "":
		own = "adi.png" if name == "f16adi.png" else name
	if own == "":
		return ""
	var path := converted("extras/cockpit").path_join(own)
	return path if FileAccess.file_exists(path) else ""


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
	return DirAccess.dir_exists_absolute(converted("menu_he"))


## The file of the HUD's and displays' raster font `name` ("hud", "mfd", "key"; hud.gd load_original_font): the
## original's, converted by `iaf-convert fonts`. Modern IAF's Settings return its own (modern-iaf/docs/cockpit.md §5).
func hud_font_path(name: String) -> String:
	return converted("fonts/%s.fnt" % name)


## The vector font of the real display formats' text: "mono" the F-16's MFD formats and its 3D cockpit's small screens
## (f16_mfd.gd, cockpit3d_display.gd), "narrow" the F-35I's panoramic and standby displays (pcd.gd), "hud" the Real
## HUD's texts (hud.gd _gdi), "ui" the lettering over the world (town_labels.gd). Here the installed system fonts,
## bold (the Real HUD's: the GDI's Arial); Modern IAF's Settings return its own (modern-iaf/docs/cockpit.md §5).
func display_font(style: String) -> Font:
	if style == "hud":
		return load("res://shared/util/img.gd").arial()
	var f := SystemFont.new()
	f.font_names = (
		PackedStringArray(
			["Arial Narrow", "Liberation Sans Narrow", "DejaVu Sans Condensed", "Arial", "Liberation Sans"]
		)
		if style == "narrow"
		else (
			PackedStringArray(["Arial", "Liberation Sans", "DejaVu Sans", "Helvetica"])
			if style == "ui"
			else PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Menlo", "Consolas", "Courier New"])
		)
	)
	f.font_weight = 600
	return f


## The assets folder: <repo>/assets, or $IAF_ASSETS_DIR (tests: the setup wizard on a scratch folder).
func assets_dir() -> String:
	if OS.get_environment("IAF_ASSETS_DIR") != "":
		return OS.get_environment("IAF_ASSETS_DIR")
	return ProjectSettings.globalize_path("res://").path_join("../assets").simplify_path()


## The path of `rel` under assets/converted: every shared reader of converted data asks here, so Modern IAF's answer
## (modern-iaf/sim_settings.gd) lets through only its own data. A leading "converted/" is taken off (the data's own
## assets-relative paths, e.g. an aircraft definition's "cockpit"). The original game: assets/converted/<rel>.
func converted(rel: String) -> String:
	return assets_dir().path_join("converted").path_join(rel.trim_prefix("converted/"))


## True when the file `rel` under assets/converted exists: the availability probes ask here (ground_roads.gd), so
## Modern IAF's answer for the original's data is a quiet false, never a refused read.
func has_converted(rel: String) -> bool:
	return FileAccess.file_exists(converted(rel))


## True where the 1998 game's effects art is there to draw (the flares', chaff's, trails', afterburner's and gun's
## muzzle-flash sprites): the original game. Modern IAF draws them with Img.soft_dot() until its own art comes.
func original_art() -> bool:
	return true


## True where the object database's counts are the real ones already (Modern IAF's, from its unit records): Weapon
## data Real keeps them rather than its per-type tables (real_weapons.gd gun_rounds). The original's bdb: false.
func real_bdb() -> bool:
	return false


## True where the player's jet starts with its master arm safe (player_weapons.gd master_arm; Modern IAF). The original
## has no master arm: false.
func starts_safe() -> bool:
	return false


## The folders under assets/converted holding the aircraft descriptors (aircraft_model.gd: `<plane>/aircraft.json` and
## the index `aircraft.json`) and the menu missions (mission_runtime.gd: `missionlist.json` and the missions): the
## original's converted ones; Modern IAF's own (sim_settings.gd).
func planes_folder() -> String:
	return "planes"


func missions_folder() -> String:
	return "missions"


## The object database a mission without its own falls back on (the player type's default load and model scale):
## the original's default6_1.bdb; Modern IAF's sim.bdb.
func default_bdb() -> String:
	return "default6_1.bdb"


## The script of the flight's loading screen (terrain_view.gd; a Control with `progress` 0..1 and a static
## prefetch()): the original's menu art; Modern IAF's own (modern-iaf/flight/loading_screen.gd).
func loading_screen_scene() -> String:
	return "res://shared/terrain/loading_screen.gd"


## The original game's install (the ISO's files, setup's extract step): assets/install.
func install_dir() -> String:
	return assets_dir().path_join("install")


## The path of `rel` under the install: every shared reader of the install asks here, so Modern IAF's answer
## (modern-iaf/sim_settings.gd) refuses it. The original game: assets/install/<rel>.
func install(rel: String) -> String:
	return install_dir().path_join(rel)


## The root of the resource layout the flight model, the sounds, the weapons' motion, iaf.ibx, terraintype.dat, the
## time of day's colours (defcolorset.tcs) and the missions' score file are read from (resource/md,
## resource/soundfiles, resource/weaponsmotion, resource/missions/scores.ibx…): the install here; Modern IAF's own
## copy of that layout in its project (modern-iaf/sim_settings.gd).
func own_dir() -> String:
	return install_dir()


## The folder IafFlight.start loads a modern jet's 6-DoF from (Physics "Flight model" on 6-DoF): Modern IAF's own
## data (`iaf-sim fm`, assets/converted/own); "" with the row on Original, or when setup has not built that data (the
## original model flies, with a log line). IafFlight picks the jets (data_set::sixdof).
func sixdof_data() -> String:
	if flight_model != "6dof":
		return ""
	if not sixdof_built():
		print("Flight model 6-DoF: Modern IAF's data is not built (./modern-iaf-setup): the original model flies")
		return ""
	return converted("own")


## Physics "Flight model" can choose 6-DoF: Modern IAF's own flight data is built.
func sixdof_built() -> bool:
	return has_converted("own/resource/md/bd.ibx")


## The flight-model name the player's jet `type` flies (PlayerAircraft.profile, IafFlight.start's section); "" = the
## converted aircraft descriptor's `fm_section` (the original game). Modern IAF answers from its own data
## (modern-iaf/sim_settings.gd).
func fm_section(_type: int) -> String:
	return ""


## Now as a file name's stamp: YYYY-MM-DD_HH-MM-SS, local (the recordings, the screenshots, Modern IAF's debriefs).
func file_stamp() -> String:
	return Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")


## The project's own node in the flight scene (terrain_view.gd `addon`, its child): null in the original game. IAF
## 2026's runs its training missions and its radio menu (modern-iaf/sim_settings.gd). `host` is the flight scene.
func flight_addon(_host: Node) -> Node:
	return null


## The flight recorder's format (docs/blackbox.schema.json `blackbox`): 1 here; Modern IAF's 2 adds the RPM and avionics
## columns (terrain_view.gd blackbox_columns).
func blackbox_version() -> int:
	return 1


## Any throttle command starts the engine (the original's rule, FUN_0059f7d0); Modern IAF's start is its own command.
func throttle_starts_engine() -> bool:
	return true


## An ejection ends the sortie at once: every sound and the radio stop, the view stays outside, an `eject` event is
## recorded (IAF 2026, modern-iaf/docs/training.md §3.0); the original game's ejection sequence runs as it is.
func eject_ends_sortie() -> bool:
	return false


## The talking towers' iaf.ibx sections (radio.gd), from the file's `sections`: [] for the original game's ten bases
## (radio.gd BASES, the first four talking). Modern IAF's: every base of its own iaf.ibx.
func tower_bases(_sections: Dictionary) -> Array:
	return []


## The theatre terrain.gd streams, under assets/: the original's map.ptt converted (`iaf-terrain theatre`). The
## environment variable IAF_THEATRE=<name> takes converted/terrain/<name> instead, e.g. Modern IAF's UTM theatre
## "israel" in the original game (modern-iaf/docs/terrain.md §6); the sim's own in its project (sim_settings.gd).
func theatre_dir() -> String:
	var t := OS.get_environment("IAF_THEATRE")
	return "converted/terrain".path_join(t if t != "" else "theatre")


## The scenery's folder under assets/converted (terrain/scenery.gd, docs/scenery.md): the original's; Modern IAF's
## beside its theatre, in its frame (modern-iaf/docs/scenery.md).
func scenery_dir() -> String:
	return "scenery"


## The road layer's folder under assets/converted (terrain/ground_roads.gd, docs/scenery.md §6).
func roads_dir() -> String:
	return "roads"


## The scenery stands wherever it has cells, whatever the imagery shown: Modern IAF (its theatre's ground is its own
## photo). The original game shows it over a Survey 2 m layer only (docs/scenery.md §3).
func scenery_everywhere() -> bool:
	return false


## The cockpit-view model drawn in its own world about the origin (cockpit_origin.gd): Modern IAF, whose flights go
## hundreds of km from their start, where the flight's float32 world rounds the cockpit to millimetres against the eye.
## The original game draws it in the flight's world (its jet stays within the 1998 theatre's few tens of km).
func cockpit_at_origin() -> bool:
	return false


## Ours, Modern IAF's bisect switch (sim_settings.gd SAFE, IAF_SAFE / `--safe`): true when the graphics feature `what`
## ("cockpit_origin", "glass", "hudglow", ...) is off for this run whatever the settings say. The original game: never.
func safe_off(_what: String) -> bool:
	return false


## Ours, Modern IAF: called once the flight's first frames are drawn (terrain_view.gd), with the flight scene; the sim
## checks the shaders in use (sim_settings.gd check_shaders). The original game: nothing.
func flight_drawn(_view: Node) -> void:
	pass


## The HUD's moving lines at sub-pixel positions: Modern IAF (whole-pixel steps jump on its wide 3D HUD glass). The
## original game draws the ILS lines at whole HUD pixels, 1/12° steps (hud.gd ils_lines, FUN_005309a0).
func hud_subpixel() -> bool:
	return false


## The HUD lit like a combiner (docs/real-hud.md "Modern IAF's HUD light"): the P43 phosphor's green at
## hud_brightness by day down to a night floor as the sun sets, added to the scene's light, a faint halo, a 0.08°
## stroke, the combiner glass at 14 % with a cool tint; the HUD key steps the brightness. Modern IAF. The original game
## keeps its eleven colours from the darkest green (the global 0x82f4c4), drawn over the scene, and its 7 % glass.
func hud_daylight() -> bool:
	return false


## The 3D cockpit's controls answer the mouse (shared/cockpit/cockpit3d_controls.gd, modern-iaf/docs/cockpit.md §5.1):
## hovering one lights it, a click, a drag or the wheel works it through the key commands. Modern IAF. The original
## game's 3D cockpit takes clicks on its MFD push buttons only.
func cockpit_controls() -> bool:
	return false


## The pilot's body in the 3D cockpit (shared/cockpit/cockpit3d.gd, <model>_pilot.glb): looking down shows the legs on
## the rudder pedals and the hands on the stick and throttle (modern-iaf/docs/cockpit.md §5.3). Modern IAF. The original
## game's 3D cockpit shows no body: looking down sees the seat and the floor.
func cockpit_pilot_body() -> bool:
	return false


## The afterburner lights and cuts like the real F-16's (modern-iaf/docs/sound.md §1.2): Modern IAF. The original game
## swaps the engine loop at once (flight_sounds.gd _update_engine, FUN_004c3e00).
func ab_sound_real() -> bool:
	return false


## The engine by its RPM, the JFS whine of the start and the wind (modern-iaf/docs/sound.md §1.3–§1.6): Modern IAF. The
## original game pitches its one engine loop by the RPM at a fixed level and plays no starter or wind
## (flight_sounds.gd _update_engine, FUN_004c3e00).
func core_sound_real() -> bool:
	return false


## The cockpit sound model (modern-iaf/docs/sound.md §1.9): from the cockpit the outside sounds (engine, airframe,
## weapons, the world) come through the canopy and the helmet, a low-pass and a level per class; the external views hear
## them unmuffled. Modern IAF. The original game plays each row at its table's inside volume (sound_buses.gd bus_for).
func cockpit_sound_model() -> bool:
	return false


## A radio call is keyed: key_on.ogg before its clips and key_off.ogg after them (modern-iaf/docs/sound.md §5.2): Modern
## IAF. The original game plays a phrase's particles alone (radio.gd say, FUN_004c5750).
func radio_key_clicks() -> bool:
	return false


## The airbases' runways, taxi lines and paved masks (airbases.gd, the tower's wind turn): the theatre's own
## `airbases.json` when it has one (Modern IAF's, `iaf-sim airbases`), else the original's converted one.
func airbases_file() -> String:
	var own := converted(theatre_dir().path_join("airbases.json"))
	return own if FileAccess.file_exists(own) else converted("terrain/airbases.json")


## The key table (key_table.gd): assets/converted/keys.json, converted from the exe by `iaf-convert keys`.
func keys_file() -> String:
	return converted("keys.json")


## The key table's contents (key_table.gd _load): the file at `path` as it is. Modern IAF merges the player's keys and
## buttons into it.
func key_table_data(path: String) -> Dictionary:
	return load_json(path)


## The folder of the joystick maps (joystick.gd _load_joy_map, the original's menu/joy/*.joy).
func joy_maps_dir() -> String:
	return install("resource/menu/joy")


## A joystick named `name` connected (joystick.gd _connected): nothing here; Modern IAF picks its device map.
func joystick_connected(_name: String) -> void:
	pass


## txt/msgs.trx lines for the current language. In Hebrew, a line the Hebrew pack leaves in English (the
## preflight.us menu pack keeps all of msgs.trx English) takes our Hebrew (iaf-reborn/menu/strings_he.json "msgs").
func msgs() -> PackedStringArray:
	var he := language == "he"
	var dir := converted("menu_he" if he else "menu")
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
	await wait_for_loads()
	_free_sounds()
	get_tree().paused = true
	await get_tree().create_timer(QUIT_AUDIO_S, true, false, true).timeout
	get_tree().quit()


## Waits while the flight scene still loads on its thread (terrain_preload.gd preload_scene): quitting under it
## aborts the load with parse errors.
func wait_for_loads() -> void:
	var scene: String = load("res://shared/terrain/terrain_preload.gd").SCENE
	while ResourceLoader.load_threaded_get_status(scene) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame


## The timed game log (util/timed_log.gd, docs/logs.md §2): installed when the project turns Godot's file log off
## (Modern IAF); null otherwise (the original game's log is Godot's own).
var timed_log: Logger
## The flight's loading step under way ("step / sub-step", terrain_view.gd), "" outside a flight's start: the hang
## line names it, and an error while it is set is a crash (crash()).
var loading_step := "":
	set(v):
		loading_step = v
		if timed_log != null:
			timed_log.step = v

## Once per run: a test's own Settings.new() installs none.
static var _log_installed := false


func _install_log() -> void:
	if _log_installed or ProjectSettings.get_setting_with_override("debug/file_logging/enable_file_logging"):
		return
	_log_installed = true
	timed_log = preload("res://shared/util/timed_log.gd").new()
	# Scripted runs (IAF_DEFAULT_SETTINGS, always with --log-file, which Godot writes itself) leave the player's logs.
	if not isolated():
		timed_log.open(
			ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"),
			ProjectSettings.get_setting("debug/file_logging/max_log_files", 5)
		)
	timed_log.on_error = _on_logged_error
	OS.add_logger(timed_log)
	timed_log.start_watch()


func _on_logged_error(what: String) -> void:
	if loading_step != "":
		crash(what, loading_step)


## A failure the game cannot go on from (`what` in one line, `step` the loading step it happened in). The original
## game: the error in the log is all (unchanged); Modern IAF shows its crash page (sim_settings.gd).
func crash(_what: String, _step := "") -> void:
	pass


## A stall in the game log (docs/logs.md): a frame longer than STALL_MS gets a line with its length, the scene (the
## front end's screen) and the last mouse click, so a freeze reported from play shows what led to it.
const STALL_MS := 250
var _frame_at := 0
var _last_click := "none"
var _click_at := 0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_click_at = Time.get_ticks_msec()
		_last_click = (
			"button %d%s at %s"
			% [event.button_index, " (double)" if event.double_click else "", Vector2i(event.position)]
		)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _frame_at > 0 and now - _frame_at > STALL_MS:
		var sc := get_tree().current_scene
		var where := String(sc.name) if sc != null else "?"
		if sc != null and sc.get("screen") != null:
			where += " / " + String(sc.screen)
		print(
			"stall: %d ms in %s; last click %s, %d ms before" % [now - _frame_at, where, _last_click, now - _click_at]
		)
	_frame_at = now


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		get_tree().auto_accept_quit = false
		# The hang watch's frame stamp on every frame, paused or not (a pause is no hang: the mission card's, the
		# player's).
		if timed_log != null:
			get_tree().process_frame.connect(func(): timed_log.frame_at = Time.get_ticks_msec())
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func _exit_tree() -> void:
	# No pool task left behind at exit (Gltf.finish_ahead says why).
	for f in [
		["res://shared/util/gltf.gd", "finish_ahead"],
		["res://shared/util/img.gd", "finish_prefetch"],
		["res://shared/util/model_detail.gd", "finish_packs"],
		["res://shared/terrain/ground_textures.gd", "finish_preload"],
		["res://shared/terrain/terrain_preload.gd", "finish_prepare"],
	]:
		load(f[0]).call(f[1])
	if timed_log != null:
		timed_log.stop_watch()  # its thread joined before the quit
		OS.remove_logger(timed_log)


func _free_sounds() -> void:
	for p in get_tree().root.find_children("*", "", true, false):
		if p is AudioStreamPlayer or p is AudioStreamPlayer2D or p is AudioStreamPlayer3D:
			p.stop()
			p.queue_free()


## The mission editor's Fly: mission `id` (the source mission: its bdb, bases and rules) with the edited `files` and
## The front end's scene (the original game's menus), where a flight ends. A project with its own front end
## overrides this and front_end_overlay().
func front_end_scene() -> String:
	return "res://menu/front_end.tscn"


## The front end drawn over the frozen flight (the FlyTSD, the in-flight Preferences); terrain_view.gd sets its
## `flight` and `screen`.
func front_end_overlay() -> Control:
	return load("res://menu/front_end.gd").new()


## `briefing`, opened on its TSD with `flight` selected; the debrief and the TSD's BACK come back to the editor.
func fly_edited(id: int, files: Array, briefing: Dictionary, flight: int, file: String, year := 0.0) -> void:
	editor_year = year
	mission_files_override = files.duplicate(true)
	briefing_override = briefing.duplicate()
	return_to_editor = true
	editor_flight = flight
	editor_file = file
	mission_id = id
	jet_id = -1
	debrief = {}
	(Engine.get_main_loop() as SceneTree).change_scene_to_file(front_end_scene())


## Back to the mission editor from the TSD or the debrief: the Fly state cleared (editor_file kept for it to reopen).
func back_to_editor() -> void:
	mission_files_override = []
	briefing_override = {}
	return_to_editor = false
	editor_flight = 0
	debrief = {}
	(Engine.get_main_loop() as SceneTree).change_scene_to_file("res://editor/mission_editor.tscn")
