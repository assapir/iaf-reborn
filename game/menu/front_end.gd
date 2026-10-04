# The original Jane's IAF front end (docs/front-end.md), rebuilt from the converted menu data
# (`iaf-convert menu`): screens, panels and lists from menus.json, text from strings.json,
# original art and sounds. Everything is laid out in the original 640x480 space, scaled to the
# window height and centred (pillarboxed on wide screens).
extends Control

const W := 640.0
const H := 480.0
## Content window (FUN_004e8d70).
const CONTENT := Rect2(155, 42, 453, 357)
## Fixed frame pieces (docs/front-end.md §2, §3.2).
const TITLE_POS := Vector2(485, 16)
const UPCLIP_POS := Vector2(17, 18)
const LOWCLIP_POS := Vector2(17, 433)
const BACK_POS := Vector2(0, 458)
const MAIN_POS := Vector2(605, 421)
## Title tab frames are 50 ms apart.
const TITLE_FRAME := 0.05

## Arial sizes (FUN_004eee10: em = cy * p / 100 with cy = 112 for Arial) and list colours
## (FUN_00509e80).
const LIST_TITLE_PX := 12.0
const LIST_DESC_PX := 11.0
const LIST_TITLE := Color8(0, 255, 0)
const LIST_DESC := Color8(0, 128, 0)
const LIST_DESC_LIT := Color8(0, 255, 0)

## Preferences (docs/front-end.md §12). Page rects are (l, t, r, b) in page coordinates; a page
## covers the content window, so screen = page + CONTENT.position.
## Page art: <art>_0 unlit, <art>_1 lit (Controls: cntrl_2 only).
const PREF_ART := {"Sound": "sound", "Graphics": "graph", "Controls": "cntrl", "Devices": "cntrl", "Gameplay": "gamep"}
## Controls per page: [kind, setting, value (radio) / step (slider, 0 = continuous), rect].
const PREF_CONTROLS := {
	"Sound": [
		["slider", "master_volume", 0.0, [19, 17, 419, 32]],
		["slider", "music_volume", 0.0, [19, 78, 419, 93]],
		["slider", "engine_volume", 0.0, [19, 139, 419, 164]],
		["slider", "sfx_volume", 0.0, [19, 200, 419, 215]],
		["slider", "speech_volume", 0.0, [19, 261, 419, 276]],
		["check", "mute", true, [8, 307, 68, 327]],
	],
	"Graphics": [
		["slider", "terrain_detail", 0.25, [19, 62, 419, 77]],
		["slider", "object_detail", 0.5, [19, 148, 419, 163]],
		["slider", "visual_effects", 0.5, [19, 236, 419, 251]],
		["check", "smoke_trails", true, [7, 306, 112, 326]],
		["check", "textured_sky", true, [112, 306, 217, 326]],
		["check", "shadows", true, [217, 306, 303, 326]],
		["check", "external_stores", true, [303, 306, 423, 326]],
	],
	"Controls": [],
	"Devices": [
		["radio", "flight_controls", 1, [25, 73, 102, 92]],
		["radio", "flight_controls", 0, [25, 108, 109, 127]],
		["radio", "rudder", 1, [193, 73, 267, 92]],
		["radio", "rudder", 0, [193, 108, 276, 127]],
		["radio", "throttle", 1, [317, 73, 394, 92]],
		["radio", "throttle", 0, [317, 108, 399, 127]],
	],
	"Gameplay": [
		["check", "no_wind", true, [24, 45, 154, 78]],
		["check", "no_blackouts", true, [24, 78, 154, 113]],
		["check", "no_spins", true, [24, 113, 154, 148]],
		["check", "no_stalls", true, [24, 148, 154, 183]],
		["check", "easy_landing", true, [24, 183, 154, 218]],
		["check", "easy_aiming", true, [24, 218, 154, 253]],
		["check", "no_malfunctions", true, [24, 253, 154, 287]],
		["radio", "ai_level", 0, [164, 45, 275, 78]],
		["radio", "ai_level", 1, [164, 78, 275, 113]],
		["radio", "ai_level", 2, [164, 113, 275, 148]],
		["check", "invulnerable", true, [285, 45, 435, 78]],
		["check", "no_crashes", true, [285, 78, 435, 113]],
		["check", "unlimited_ammo", true, [285, 113, 435, 148]],
		["check", "unlimited_fuel", true, [285, 148, 435, 183]],
	],
}
## Slider thumb pref/slider.bmp (19x30: image over mask), drawn 15 high at x0 + fill - 6.
const PREF_THUMB := Vector2(19, 15)
## DEFAULT button (pref/defbut_0/_2), on every page except Devices.
const PREF_DEFAULT := Rect2(357, 330, 85, 23)
## Ours on the Graphics page: the VSync check in the empty strip left of DEFAULT (page coordinates).
const PREF_VSYNC := Rect2(8, 330, 110, 23)
## Ours on the Devices page, under THROTTLE on the page's 35 px row grid: the throttle detent (joystick.gd
## `detent_map`): OFF = the original's linear lever, SET AT LEVER stores the lever's position in its detent as MIL.
const PREF_DETENT := {"title": Rect2(317, 143, 115, 20), "off": Rect2(317, 178, 110, 20), "set": Rect2(317, 213, 115, 20), "note": Rect2(317, 245, 125, 60)}
## Gameplay scoring strip: pref/score.bmp, 25 frames of 151x34.
const PREF_SCORE := Rect2(290, 184, 151, 34)
## Live preview sounds while dragging (wav/pref, FUN_00544560).
const PREF_PREVIEW := {"engine_volume": "pref/engines", "sfx_volume": "pref/sfx", "speech_volume": "pref/speech"}
## Controls page (§12.7, FUN_00511580 / 511cf0): the key list over the page art (page (0,53)-(400,323),
## 9 rows of 30 px = the background height / 9, FUN_004f4470), text only (FUN_00512080: item.bmp /
## hiitem.bmp are loaded but never drawn): function (11,1)-(181,28) left, key (187,1)-(328,28) and
## joystick button (331,1)-(409,28) centred, Arial 11, RGB(0,255,0) selected, RGB(0,180,0) others.
const CTRL_LIST := Rect2(0, 53, 400, 270)
const CTRL_ROWS := 9
const CTRL_COLS := [Rect2(11, 1, 170, 27), Rect2(187, 1, 141, 27), Rect2(331, 1, 78, 27)]
const CTRL_TEXT := Color8(0, 180, 0)
const CTRL_TEXT_SEL := Color8(0, 255, 0)
## Scrollbar (FUN_004f3700): the bar (422,53)-(433,323), arrows 15x18 at its top (sldownb) and
## bottom (slupb), clipped to the bar, thumb pref/sldcntrl 10x23 between them. One row per arrow click.
const CTRL_BAR := Rect2(422, 53, 11, 270)
const CTRL_ARROW := Vector2(15, 18)
const CTRL_THUMB := Vector2(10, 23)
const KeyTable := preload("res://controls/key_table.gd")
const Img := preload("res://util/img.gd")
const Tsd := preload("res://menu/tsd.gd")
const Pilots := preload("res://menu/pilots.gd")
const ImageryLayers := preload("res://terrain/imagery_layers.gd")

## Our own "Extras" tab (not in the original): directly below Gameplay at the panel's spacing
## (44 px). Drawn from the pPref art: the band holding the Gameplay button (panel coordinates, inside
## the edge rulers) moved down 44 px, its label filled in row by row, our text on top.
const EXTRAS_TAB := Rect2(16, 287, 109, 39)
const EXTRAS_BAND := Rect2(12, 203, 116, 54)
const EXTRAS_LABEL := Rect2(42, 219, 62, 16)
const EXTRAS_STEP := 44.0
## Our tabs below Gameplay, 44 px apart: [page, English button label].
const OUR_TABS := [["Extras", "EXTRAS"], ["Physics", "PHYSICS"]]
## Physics page (ours): one row per Settings.BETTER option, PHYSICS_ROWS at a time, with the Keyboard
## page's scrollbar from the first row to the page bottom (mirrored to the left in Hebrew).
const PHYSICS_ROW := 20.0
const PHYSICS_ROWS := 15
const PHYSICS_BAR := Rect2(422, 45, 11, 300)
## Extras rows: the Gameplay page's 35 px, EXTRAS_ROWS at a time above DEFAULT (y 330), with the Physics /
## Keyboard scrollbar when there are more (mirrored to the left in Hebrew).
const EXTRAS_ROW := 35.0
const EXTRAS_ROWS := 8
const EXTRAS_BAR := Rect2(422, 45, 11, 280)
## Our options on the Extras page: [setting, label, [[choice label, value], ...]].
const EXTRAS := [
	["flight_data", "Flight data", [["Original (1998)", "original"], ["Real aircraft", "real"]]],
	["weapon_data", "Weapon data", [["Original (1998)", "original"], ["Real weapons", "real"]]],
	["language", "Language", [["English", "en"], ["Hebrew", "he"]]],
	["show_info", "Flight info (Ctrl+F12)", [["Show", true], ["Hide", false]]],
	["blackbox", "Blackbox", [["On", true], ["Off", false]]],
	["hud_ladder", "HUD pitch ladder", [["Original", "original"], ["Conformal", "conformal"]]],
	["hud_style", "HUD", [["Original (1998)", "original"], ["Real F-16", "real"]]],
	["show_all_keys", "All keys on the Keyboard page", [["Original", false], ["All", true]]],
	["fullscreen", "Window", [["Framed", false], ["Full screen", true]]],
	# Render options for high resolutions (terrain/render_options.gd, docs/rendering.md); first = as before.
	["antialiasing", "Anti-aliasing", [["MSAA 4x", "msaa4"], ["+ FXAA", "msaa4_fxaa"], ["TAA", "taa"]]],
	["terrain_closeup", "Terrain close up", [["Original", false], ["Detailed", true]]],
	["sky", "Sky", [["Original", "original"], ["Atmospheric", "atmospheric"]]],
	# Ours: the F-35I (docs/f35i.md) flies from the Jet list button it replaces; more than three choices cycle.
	["f35i_slot", "F-35I replaces", [["Off", -1], ["F-15", 0], ["F-16", 1], ["F-4E", 2], ["Kurnass 2000", 3],
		["Lavi", 4], ["Kfir", 5], ["Mirage", 6]]],
]


## The Extras rows: EXTRAS, then one terrain-imagery row per region (docs/imagery.md; layers not
## converted are greyed out and cannot be picked).
func _extras_rows() -> Array:
	var rows: Array = EXTRAS.duplicate()
	for key in ImageryLayers.REGIONS:
		rows.append([key, ImageryLayers.REGION_LABELS[key], ImageryLayers.REGIONS[key].map(func(o): return [o[1], o[0]])])
	return rows

## Button-release dispatcher FUN_004ec770: screen -> {button label -> next screen}.
## Basic/Combat mission buttons go to the Jet list; Jet and campaign mission buttons load the
## mission (-> TSD).
const FORWARD := {
	"main": {"training": "training", "campaigns": "camp", "preferences": "pref",
		"missioncreator": "mc", "pilotrecords": "log", "reference": "ref", "multiplayer": "ctype"},
	"training": {"basiccourse": "basic", "combatcourse": "combat"},
	"camp": {"historical": "his", "future": "fut"},
	"his": {"sixdaywar": "his1mis", "yomkipurwar": "his2mis", "lebanonwar": "his3mis"},
	"fut": {"syrianfront": "fut1mis", "iraqifront": "fut2mis", "lebanesefront": "fut3mis"},
}
const TO_JET := ["basic", "combat"]
const LOADS_MISSION := ["jet", "his1mis", "his2mis", "his3mis", "fut1mis", "fut2mis", "fut3mis"]
## BACK (FUN_004ed1b0). The Jet list goes back to where it came from (screen 9 / 10).
const BACK := {"pref": "main", "ref": "main", "training": "main", "ctype": "main",
	"basic": "training", "combat": "training", "camp": "main", "mc": "main",
	"his": "camp", "fut": "camp", "his1mis": "his", "his2mis": "his", "his3mis": "his",
	"fut1mis": "fut", "fut2mis": "fut", "fut3mis": "fut", "tcp": "ctype", "ipx": "ctype"}
## No BACK here (FUN_004ea2a0): its disabled plate, and the blank lower clip (lowclipc, which
## otherwise holds the BACK plate). QUIT replaces MAIN on QUIT_SCREENS.
const NO_BACK := ["log", "main", "deb", "jump"]
const QUIT_SCREENS := ["log", "main"]

## Jet buttons -> aircraft id (FUN_00509d60, DAT_0083b818).
const JET_IDS := {"mirage": 6, "kfir": 5, "f4": 2, "f42000": 3, "f15": 0, "f16": 1, "lavi": 4}
## Jets the original disables per mission (FUN_00509b80), by aircraft id.
const JETS_DISABLED := {314: [6, 5], 322: [6, 5, 0], 323: [6, 5, 2, 0], 325: [6, 5, 2, 1, 4]}
## Jet list ids -> flyable: aircraft/player_aircraft.gd (FLYABLE, JET_TYPES).
const PlayerAircraft := preload("res://aircraft/player_aircraft.gd")

var menus := {}
var strings := {}
## Labels for our own settings page in Hebrew.
var hebrew := {}
var textures := {}
var dir := ""
## Converted art is stored at this multiple of the original pixel size.
var art_scale := 1.0
var font: SystemFont
var font_bold: SystemFont
## Our own labels in the style of the original art's baked labels: bold italic condensed capitals.
var font_art: SystemFont

## The game starts on the Login / Pilot Records screen (screen 0, docs/front-end.md §13.1).
var screen := "log"
## Where TSD and the Jet list return to.
var jet_parent := "basic"
## Transition state: left/bottom panels 0 = hidden .. 1 = shown; title tab frame 0..2.
var panel_shown := 1.0
var title_frame := 2
var busy := false
var loading := false
## Button animation frames by key "panel/button" (0 normal, 1 anim, 2 pressed, 3 disabled).
var frames := {}
var checked := {}
var held := ""  # key of the button the mouse is holding down
var hover_key := ""
## Preferences working copy (§12.2): committed to Settings only on "Save changes?" Yes.
var pref_work := {}
## Slider being dragged ([setting, rect, step]) and whether DEFAULT is held down.
var pref_drag: Array = []
var pref_default_held := false
## Controls page: the key table, the selected list row, the first row shown, whether the list has
## the keyboard (after a click on a row), the arrow held down and a thumb drag offset (or -1); the
## last two are the Physics page's scrollbar's too.
var key_table: RefCounted
var ctrl_sel := 0
var ctrl_top := 0
var ctrl_focus := false
## Physics page: the first option row shown.
var phys_top := 0
var extras_top := 0
var ctrl_arrow := ""
var ctrl_drag := -1.0

## TSD (screen 0x1e): the map/briefing node, where BACK returns to, and its check buttons,
## which persist while the mission is loaded (DAT_0083b85c..d1c, defaults FUN_004f15a0).
var tsd: Control
var tsd_return := "jet"
var tsd_checks := {}
var briefings := {}
## Arming (screen 0x1f): its content node (game/menu/arming.gd) and the mission's loadout tables
## (game/weapons/mission_weapons.gd, the original's CMissionWeapons), kept while the mission is loaded.
var arm: Control
var mission_weapons: RefCounted
## The open message box (§3.3, game/mission/mission_box.gd), or null.
var msgbox: Control
## Pilot Records (screen 0): its content node (game/menu/pilot_records.gd), and the logged-in pilot's
## mission history for the list locks (§13.11), read on each screen change.
var records: Control
var history: Array = []
## In flight (docs/front-end.md §16): the flight scene that opened this front end over itself for the
## FlyTSD (Esc, screen 0x20) or the in-flight Preferences (screen 0x21); null in the menus. Set with
## `screen` before the node enters the tree; leaving those screens returns to the flight.
var flight: Node = null

var music: AudioStreamPlayer
var sfx: AudioStreamPlayer
var preview: AudioStreamPlayer
var sounds := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_menu_data()
	font = Img.arial(400)
	font_bold = Img.arial(700)
	font_art = Img.arial(800, true)
	font_art.font_stretch = 85
	music = AudioStreamPlayer.new()
	sfx = AudioStreamPlayer.new()
	preview = AudioStreamPlayer.new()
	add_child(music)
	add_child(sfx)
	add_child(preview)
	briefings = Settings.load_json(Settings.assets_dir().path_join("converted/briefings/briefings.json"))
	if flight != null:
		# The TSD layers as on mission load, the player's flight selected (not the Arming tables).
		var loads: Dictionary = Settings.arm_loadouts
		_reset_tsd_checks()
		Settings.arm_loadouts = loads
		_enter_screen()
		return
	var args := OS.get_cmdline_user_args()
	# Back from a flight with a debrief (docs/mission-runtime.md §5.3): the Debrief records the attempt
	# (FUN_004fe860 -> FUN_004f68b0) for the logged-in pilot.
	if not Settings.debrief.is_empty():
		screen = "deb"
		if Settings.pilot_id >= 0:
			var p := {}
			for k in Settings.PREFS.gameplay:
				p[k] = Settings.get(k)
			Pilots.record(Settings.pilot_id, Settings.mission_id, Settings.debrief, score_multiplier(p))
	var at := args.find("--mission")
	if at >= 0:
		Settings.mission_id = int(args[at + 1])
		_reset_tsd_checks()
	_enter_screen()
	_start_music()
	# On-The-Fly menu Restart / New mission (docs/front-end.md §16.3): the debrief screen 0x23 / 0x25
	# presses its Replay / New Mission button itself after 50 ms (SetTimer in FUN_004fef80).
	if screen == "deb" and Settings.debrief.has("auto"):
		var auto: String = Settings.debrief.auto
		get_tree().create_timer(0.05).timeout.connect(func(): _debrief_button(auto))
	at = args.find("--hover")
	if at >= 0:
		hover_key = _key_for_label(args[at + 1])
	var shot := args.find("--screenshot")
	if shot >= 0:
		Img.screenshot_and_quit(self, args[shot + 1], 5)


## (Re)load screens, strings and art for the current language. Hebrew uses the Hebrew menu
## pack (assets/converted/menu_he, see docs/packs.md) when it is installed.
func _load_menu_data() -> void:
	dir = Settings.assets_dir().path_join("converted/menu_he" if _he() else "converted/menu")
	textures.clear()
	menus = Settings.load_json(dir.path_join("menus.json"))
	strings = Settings.load_json(dir.path_join("strings.json"))
	if menus.is_empty():
		push_error("front end: run tools/setup.sh (menus not converted)")
	hebrew = Settings.load_json("res://menu/strings_he.json")
	var scale_file := dir.path_join("image_scale.txt")
	art_scale = float(FileAccess.get_file_as_string(scale_file).strip_edges()) if FileAccess.file_exists(scale_file) else 1.0
	sounds.clear()


func _he() -> bool:
	return Settings.language == "he"


## Labels of ours without a Hebrew text, collected while drawing in Hebrew (test_ui_smoke fails on any).
var missing_he := {}


func _t(english: String) -> String:
	if not _he():
		return english
	var labels: Dictionary = hebrew.get("labels", {})
	if not labels.has(english):
		missing_he[english] = true
	return labels.get(english, english)


func _string(key: String) -> String:
	return strings.get(key.to_lower(), "")


## Labels are compared without case, spaces or underscores ("Jump In" = "Jump_In").
static func _norm(label: String) -> String:
	return label.to_lower().replace(" ", "").replace("_", "")


# --- assets -----------------------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = Img.load_texture(dir.path_join("img").path_join(path), true)
	return textures[path]


func _sound(name: String) -> AudioStreamWAV:
	if not sounds.has(name):
		var path := dir.path_join("wav/%s.wav" % name)
		sounds[name] = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	return sounds[name]


func _sound_length(name: String) -> float:
	var s := _sound(name)
	return s.get_length() if s != null else 0.15


func _play(name: String) -> void:
	var s := _sound(name)
	if s != null:
		sfx.stream = s
		sfx.play()


## Menu_M.wav loops on every screen except TSD / Arm (FUN_004ea2a0).
func _start_music() -> void:
	if screen in ["tsd", "arm", "flytsd"] or flight != null or music.playing:
		return
	var s := _sound("menu_m")
	if s == null:
		return
	music.stream = _looped(s)
	_apply_music_volume()
	music.play()


## A sound set to loop over its whole length.
static func _looped(s: AudioStreamWAV) -> AudioStreamWAV:
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


## Music volume and Mute (Sound page); while on Preferences the working copy is previewed.
func _apply_music_volume() -> void:
	var w: Dictionary = pref_work if screen == "pref" else {}
	var vol: float = w.get("music_volume", Settings.music_volume)
	music.volume_db = -80.0 if w.get("mute", Settings.mute) or vol <= 0.0 else linear_to_db(vol)


# --- screen model -----------------------------------------------------------------------

func _def() -> Dictionary:
	return menus.get(screen, {})


## The list shown in the content window: dat/<sName>.trx.
func _list() -> Dictionary:
	var l: Dictionary = menus.get(String(_def().get("name", "")).to_lower(), {})
	return l if l.get("type", "") == "list" else {}


func _panels() -> Array:
	return _def().get("panels", [])


func _button(key: String) -> Dictionary:
	var parts := key.split("/")
	if parts.size() != 2:
		return {}
	var panels := _panels()
	var p := int(parts[0])
	var b := int(parts[1])
	if p >= panels.size() or b >= panels[p].buttons.size():
		return {}
	return panels[p].buttons[b]


func _key_for_label(label: String) -> String:
	var panels := _panels()
	for p in panels.size():
		for b in panels[p].buttons.size():
			if _norm(panels[p].buttons[b].label) == _norm(label):
				return "%d/%d" % [p, b]
	return ""


func _enter_screen() -> void:
	frames.clear()
	checked.clear()
	if screen == "pref":
		checked[_key_for_label(Settings.pref_page)] = true
		pref_work.clear()
		for section in Settings.PREFS:
			for k in Settings.PREFS[section]:
				pref_work[k] = Settings.get(k)
		pref_work["key_bindings"] = Settings.key_bindings.duplicate(true)
		pref_work["better"] = Settings.better.duplicate()
		ctrl_sel = 0  # FUN_00511580 selects the first row
		ctrl_top = 0
		ctrl_focus = false
		phys_top = 0
		extras_top = 0
	if screen in ["tsd", "arm", "flytsd"]:
		_restore_tsd_checks()
	if _is_tsd() and tsd == null:
		tsd = Tsd.new()
		add_child(tsd)
		tsd.setup(self, Settings.mission_id)
		if tsd_checks.get("player_flight", false):
			tsd_checks.erase("player_flight")
			var n: int = tsd.default_flight()
			if n >= 1 and n <= 4:
				tsd_checks[Tsd.FLIGHT_NAMES[n - 1]] = true
			_restore_tsd_checks()
		else:
			var n := _flight_number(_selected_flight())
			if n > 0:
				tsd.select_flight(n)
		# Briefing only when its file exists.
		tsd_checks["briefing"] = tsd_checks.get("briefing", false) and tsd.has_briefing()
		tsd.open_briefing(tsd_checks.briefing)
	elif not screen in ["tsd", "arm", "flytsd"] and tsd != null:
		tsd.queue_free()
		tsd = null
	_enter_arm()
	if screen == "log" and records == null:
		records = preload("res://menu/pilot_records.gd").new()
		add_child(records)
		records.setup(self)
	elif screen != "log" and records != null:
		records.queue_free()
		records = null
	history = Pilots.history(Settings.pilot_id) if Settings.pilot_id >= 0 else []


## The Arming screen (§15) is drawn over the TSD, which stays loaded (hidden) for its flights; the
## loadout tables live while the mission is loaded (created on first use).
func _enter_arm() -> void:
	if tsd != null:
		tsd.visible = _is_tsd()
	if screen != "arm":
		if arm != null:
			arm.queue_free()
			arm = null
		return
	if tsd == null:
		tsd = Tsd.new()
		add_child(tsd)
		tsd.setup(self, Settings.mission_id)
		tsd.visible = false
	if mission_weapons == null:
		mission_weapons = preload("res://weapons/mission_weapons.gd").create(Settings.mission_id, Settings.real_weapons())
	var n := _flight_number(_selected_flight())
	if n <= 0:
		n = tsd.default_flight()
	for f in Tsd.FLIGHT_NAMES:
		tsd_checks[f] = f == Tsd.FLIGHT_NAMES[n - 1] if n >= 1 and n <= 4 else false
	_restore_tsd_checks()
	if arm == null:
		arm = preload("res://menu/arming.gd").new()
		add_child(arm)
	arm.setup(self, mission_weapons, n)


## TSD defaults on mission load (FUN_004f15a0): every unit filter, Text, Waypoint, Grid and
## Briefing on; the flight holding the player is selected when the TSD opens. The Arming tables
## start again from the mission's loads (FUN_004efef0).
func _reset_tsd_checks() -> void:
	mission_weapons = null
	Settings.arm_loadouts = {}
	tsd_checks = {"waypoint": true, "text": true, "grid": true, "briefing": true, "player_flight": true}
	for kind in ["aircrafts", "vehicles", "ships", "samsites", "aaasites", "structures", "airports"]:
		for side in [1, 2]:
			tsd_checks["%s%d" % [kind, side]] = true


func _restore_tsd_checks() -> void:
	var panels := _panels()
	for p in panels.size():
		for b in panels[p].buttons.size():
			var btn: Dictionary = panels[p].buttons[b]
			if tsd_checks.get(_norm(btn.label), false) and btn.kind in ["Check", "CheckGroup"]:
				checked["%d/%d" % [p, b]] = true


func _button_enabled(label: String) -> bool:
	if screen == "deb" and _norm(label) == "nextmission":
		return next_mission(Settings.mission_id, Settings.debrief.get("passed", false) or _cheat()) != 0
	# List rows (FUN_00509e80 @50a5b9): a row with f1 set is locked until the row above has a pass (the
	# first row: never), unless the cheat is on. Only the Future fronts' Missions 2–7 have f1 set.
	var rows: Array = _list().get("rows", [])
	for i in rows.size():
		if _norm(rows[i].name) == _norm(label) and int(rows[i].get("flags", [0])[0]) != 0 and not _cheat():
			return i > 0 and Pilots.passes(history, int(rows[i - 1].id)) > 0
	if screen == "jet":
		var id: int = JET_IDS.get(_norm(label), -1)
		if id in JETS_DISABLED.get(Settings.mission_id, []):
			return false
		return PlayerAircraft.flyable(PlayerAircraft.jet_type(id))
	if flight != null and _norm(label) == "gameplay":
		return false  # the in-flight Preferences disable the Gameplay tab (§16.3)
	if _is_tsd() and tsd != null:
		match _norm(label):
			"briefing":
				return tsd.has_briefing()
			"zoomin":
				return tsd.can_zoom_in()
			"zoomout":
				return tsd.can_zoom_out()
			"arm":
				return _selected_flight() != "" and tsd.flights.has(_flight_number(_selected_flight()))
		if _norm(label) in Tsd.FLIGHT_NAMES:
			return tsd.flight_enabled(_flight_number(_norm(label)))
	# Arming's flight buttons: the TSD's rule (FUN_00507df0 = FUN_00505820 in single player).
	if screen == "arm" and _norm(label) in Tsd.FLIGHT_NAMES:
		return tsd != null and tsd.flight_enabled(_flight_number(_norm(label)))
	return true


## The "make sim" / "not war" cheat of the logged-in pilot (FUN_004f1610).
func _cheat() -> bool:
	return Pilots.cheat(Settings.pilot_name, Settings.pilot_callsign)


func _is_tsd() -> bool:
	return screen in ["tsd", "flytsd"]


func _flight_number(name: String) -> int:
	return Tsd.FLIGHT_NAMES.find(name) + 1


func _selected_flight() -> String:
	for f in Tsd.FLIGHT_NAMES:
		if tsd_checks.get(f, false):
			return f
	return ""


## Visible frame of a button: animation first, then checked / disabled.
func _frame(key: String, label: String) -> int:
	if not _button_enabled(label):
		return 3
	if frames.has(key):
		return frames[key]
	return 2 if checked.get(key, false) else 0


# --- drawing ----------------------------------------------------------------------------

func _scale() -> float:
	return min(size.x / W, size.y / H)


func _origin() -> Vector2:
	var s := _scale()
	return Vector2((size.x - W * s) / 2.0, (size.y - H * s) / 2.0)


## Original 640x480 coordinates -> window pixels.
func _to_screen(p: Vector2) -> Vector2:
	return _origin() + p * _scale()


func _to_menu(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


func _rect(r: Rect2) -> Rect2:
	return Rect2(_to_screen(r.position), r.size * _scale())


func _art_size(t: Texture2D) -> Vector2:
	return Vector2(t.get_width(), t.get_height()) / art_scale


## Draw a whole image at its original size, on `on` (default the front end; the Arming and Pilot
## Records screens pass themselves).
func _blit(path: String, pos: Vector2, on: CanvasItem = null) -> void:
	var t := _tex(path)
	if t != null:
		(on if on else self).draw_texture_rect(t, _rect(Rect2(pos, _art_size(t))), false)


## Draw part of an image (source in original pixels) at `dest` (original coordinates).
func _blit_region(path: String, src: Rect2, dest: Vector2, on: CanvasItem = null) -> void:
	var t := _tex(path)
	if t != null:
		(on if on else self).draw_texture_rect_region(t, _rect(Rect2(dest, src.size)), Rect2(src.position * art_scale, src.size * art_scale))


func _process(_delta: float) -> void:
	queue_redraw()
	_preload_ground()


## While the mission's screens are open (TSD / briefing / Arming), the ground around the chosen
## flight leader's start loads in the background (terrain/terrain_preload.gd) so Fly starts at once;
## a flight change on the TSD re-aims it, leaving the mission screens stops it.
var _preload_flight := -1


func _preload_ground() -> void:
	const TerrainPreload := preload("res://terrain/terrain_preload.gd")
	if flight != null:
		return
	if tsd != null:
		var n: int = tsd.default_flight()
		if n != _preload_flight:
			_preload_flight = n
			var w = preload("res://mission/mission_runtime.gd").player_start(Settings.mission_id, n)
			if w != null:
				TerrainPreload.target(get_tree(), w)
	elif _preload_flight != -1:
		_preload_flight = -1
		TerrainPreload.stop()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	_blit("back.png", Vector2.ZERO)
	var def := _def()
	if def.is_empty():
		return
	_draw_content(def)
	_draw_panels()
	_draw_frame_pieces()
	# Pillarbox: hide sliding panels outside the 640x480 frame.
	var o := _origin()
	var sz := Vector2(W, H) * _scale()
	draw_rect(Rect2(0, 0, o.x, size.y), Color.BLACK)
	draw_rect(Rect2(o.x + sz.x, 0, size.x - o.x - sz.x, size.y), Color.BLACK)
	draw_rect(Rect2(0, o.y + sz.y, size.x, size.y), Color.BLACK)


func _draw_frame_pieces() -> void:
	var def := _def()
	var title := String(def.get("title", "")).to_lower()
	if title != "":
		_blit("titles/%s_%d.png" % [title, title_frame], TITLE_POS)
	var clip := 1 + int(round(panel_shown * 4.0))
	_blit("misc/upclip%d.png" % clip, UPCLIP_POS)
	_blit("misc/%s%d.png" % ["lowclipc" if screen in NO_BACK else "lowclip", clip], LOWCLIP_POS)
	var back_frame: int = frames.get("back", 3 if screen in NO_BACK else 0)
	_blit("misc/backbut_%d.png" % back_frame, BACK_POS)
	var main_art := "quitbut" if screen in QUIT_SCREENS else "mainbut"
	_blit("misc/%s_%d.png" % [main_art, frames.get("main", 0)], MAIN_POS)


func _draw_panels() -> void:
	var panels := _panels()
	for p in panels.size():
		var panel: Dictionary = panels[p]
		var name := String(panel.name).to_lower()
		var base := _tex("palettes/%s_0.png" % name)
		if base == null:
			continue
		var pos := Vector2(panel.pos[0], panel.pos[1])
		var art := _art_size(base)
		# Left panels slide in from the left, bottom panels up from the bottom (§2).
		var hidden := 1.0 - panel_shown
		if panel.side == "left":
			pos.x -= art.x * hidden
		else:
			pos.y += art.y * hidden
		_blit("palettes/%s_0.png" % name, pos)
		var delta := pos - Vector2(panel.pos[0], panel.pos[1])
		for b in panel.buttons.size():
			var btn: Dictionary = panel.buttons[b]
			var f := _frame("%d/%d" % [p, b], btn.label)
			if f == 0:
				continue
			var path := "palettes/%s_%d.png" % [name, f]
			if _tex(path) == null:
				continue
			var r: Array = btn.rect
			var src := Rect2(r[0] - panel.pos[0], r[1] - panel.pos[1], r[2], r[3])
			_blit_region(path, src, Vector2(r[0], r[1]) + delta)
		if screen == "pref" and panel.side == "left":
			_draw_extras_tab(delta)
		if screen == "jet":
			_draw_f35i_slot(p, panel, delta)


func _draw_content(def: Dictionary) -> void:
	if loading:
		_blit("mis/wait.png", CONTENT.position)
		return
	if _is_tsd():
		return
	if screen == "deb":
		_draw_debrief()
		return
	var list := _list()
	if not list.is_empty():
		_draw_list(list)
	elif screen == "main":
		# Hovering an enabled main button shows main_N (FUN_004fc350).
		var hb := _button(hover_key)
		if not hb.is_empty() and _button_enabled(hb.label):
			_blit("main/main_%d.png" % (int(hover_key.split("/")[1]) + 1), CONTENT.position)
		else:
			_blit("screens/smain.png", CONTENT.position)
	else:
		var bg := "screens/%s.png" % String(def.name).to_lower()
		if _tex(bg) != null:
			_blit(bg, CONTENT.position)
		if screen == "pref":
			_draw_prefs()


## List screens (FUN_00509e80): rows copied from mis_1, the row of the hovered same-named
## button from mis_2; Arial title and description drawn over them.
func _draw_list(list: Dictionary) -> void:
	var prefix := "mis/mismp" if screen == "netaow" else "mis/mis"
	_blit(prefix + "_0.png", CONTENT.position)
	var hb := _button(hover_key)
	var lit_name := _norm(hb.label) if not hb.is_empty() and _button_enabled(hb.label) else ""
	for row in list.rows:
		var rr: Array = row.rect
		var lit := _norm(row.name) == lit_name
		var src := Rect2(rr[0], rr[1], rr[2], rr[3])
		_blit_region(prefix + ("_2.png" if lit else "_1.png"), src, CONTENT.position + src.position)
		var tb: Array = row.title_box
		var db: Array = row.desc_box
		var title := _string(row.title_key)
		if title == "":
			title = row.name
		var desc := _string(row.desc_key)
		# Ours: the Jet list row of the button the F-35I replaces describes the F-35I.
		if screen == "jet" and int(Settings.f35i_slot) >= 0 and JET_IDS.get(_norm(row.name), -1) == int(Settings.f35i_slot):
			title = "אדיר" if _he() else "F-35I"
			desc = _t(F35I_DESC)
		_text_line(Rect2(CONTENT.position + Vector2(tb[0], tb[1]), Vector2(tb[2] - tb[0], tb[3] - tb[1])), title, LIST_TITLE_PX, LIST_TITLE)
		_text_block(Rect2(CONTENT.position + Vector2(db[0], db[1]), Vector2(db[2] - db[0], db[3] - db[1])), desc, LIST_DESC_PX, LIST_DESC_LIT if lit else LIST_DESC)


## Single line, bottom-aligned (DT_SINGLELINE|DT_BOTTOM); right-aligned in Hebrew.
func _text_line(box: Rect2, text: String, px: float, color: Color, f: Font = null) -> void:
	f = f if f != null else font
	var r := _rect(box)
	var fs := int(round(px * _scale()))
	var align := HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(f, Vector2(r.position.x, r.end.y - f.get_descent(fs)), text, align, r.size.x, fs, color)


## `_text_line` with the size reduced (down to 60 %) until the text fits the box (our long labels).
func _text_fit(box: Rect2, text: String, px: float, color: Color, f: Font = null) -> void:
	f = f if f != null else font
	var p := px
	while p > px * 0.6 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(p * _scale()))).x > _rect(box).size.x:
		p -= 0.5
	_text_line(box, text, p, color, f)


## Word-wrapped block from the top (DT_WORDBREAK).
func _text_block(box: Rect2, text: String, px: float, color: Color) -> void:
	var r := _rect(box)
	var fs := int(round(px * _scale()))
	var align := HORIZONTAL_ALIGNMENT_RIGHT if _he() else HORIZONTAL_ALIGNMENT_LEFT
	var lines := maxi(1, int(r.size.y / font.get_height(fs)) + 1)
	draw_multiline_string(font, r.position + Vector2(0, font.get_ascent(fs)), text, align, r.size.x, fs, lines, color)


## Preferences page (§12.1): the page's _0 art, every control that is on copied from _1, sliders
## with their thumb, the Gameplay scoring strip and the DEFAULT button.
func _draw_prefs() -> void:
	var page: String = Settings.pref_page
	if page == "Extras":
		_draw_extras()
		return
	if page == "Physics":
		_draw_physics()
		return
	var art: String = PREF_ART.get(page, "")
	var at := CONTENT.position
	_blit("pref/%s_%d.png" % [art, 2 if page == "Controls" else 0], at)
	if page == "Controls":
		_draw_controls(at)
	var lit := "pref/%s_1.png" % art
	for c in PREF_CONTROLS.get(page, []):
		var r := _ltrb(c[3])
		match c[0]:
			"check", "radio":
				if pref_work.get(c[1]) == c[2]:
					_blit_region(lit, r, at + r.position)
			"slider":
				var fill := int(_pref_value(c[1]) * r.size.x)
				if fill > 0:
					_blit_region(lit, Rect2(r.position, Vector2(fill, r.size.y)), at + r.position)
				var thumb := _slider_thumb()
				if thumb != null:
					draw_texture_rect(thumb, _rect(Rect2(at + r.position + Vector2(fill - 6, 0), PREF_THUMB)), false)
	if page == "Gameplay":
		var src := Rect2(Vector2(0, PREF_SCORE.size.y * _score_frame(pref_work)), PREF_SCORE.size)
		_blit_region("pref/score.png", src, at + PREF_SCORE.position)
	if page != "Devices":
		_blit("pref/defbut_%d.png" % (2 if pref_default_held else 0), at + PREF_DEFAULT.position)
	if page == "Devices":
		var fs := int(round(LIST_TITLE_PX * _scale()))
		var tr := _rect(Rect2(at + PREF_DETENT.title.position, PREF_DETENT.title.size))
		draw_string(font_art, Vector2(tr.position.x, tr.end.y - font_art.get_descent(fs)), _art("Detent = MIL"), HORIZONTAL_ALIGNMENT_LEFT, tr.size.x, fs, LIST_TITLE)
		var d := int(pref_work.get("throttle_detent", -1))
		var has_joy := Joystick.device() >= 0
		for k in ["off", "set"]:
			var on := (d < 0) if k == "off" else (d >= 0)
			var r0: Rect2 = PREF_DETENT[k]
			_blit_region("pref/gamep_%d.png" % (1 if on else 0), Rect2(Vector2(28, 55), Vector2(11, 11)), at + r0.position + Vector2(4, 6))
			var r := _rect(Rect2(at + r0.position + Vector2(22, 0), Vector2(r0.size.x - 22, 20)))
			var col: Color = LIST_DESC_LIT if on else LIST_DESC
			if k == "set" and not has_joy:
				col = Color(LIST_DESC, 0.45)
			draw_string(font_art, Vector2(r.position.x, r.end.y - font_art.get_descent(fs)), _art("Off" if k == "off" else "Set at lever"), HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs, col)
		_text_block(Rect2(at + PREF_DETENT.note.position, PREF_DETENT.note.size), _t("Put the lever in its MIL click, then choose Set at lever."), LIST_DESC_PX, LIST_DESC)
	if page == "Graphics":
		# Not mirrored in Hebrew: the Graphics art is left-to-right in both languages (the Hebrew CD's too).
		var vs_on := bool(pref_work.get("vsync", true))
		_blit_region("pref/gamep_%d.png" % (1 if vs_on else 0), Rect2(Vector2(28, 55), Vector2(11, 11)), at + PREF_VSYNC.position + Vector2(4, 6))
		var r := _rect(Rect2(at + PREF_VSYNC.position + Vector2(22, 0), Vector2(PREF_VSYNC.size.x - 22, 20)))
		var fs := int(round(LIST_TITLE_PX * _scale()))
		draw_string(font_art, Vector2(r.position.x, r.end.y - font_art.get_descent(fs)), "VSYNC", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs, LIST_DESC_LIT if vs_on else LIST_DESC)


func _keys() -> RefCounted:
	if key_table == null:
		key_table = KeyTable.load_table()
	return key_table


## The records listed (shown flag set), in table order.
func _ctrl_rows() -> Array:
	return _keys().shown_records(bool(pref_work.get("show_all_keys", Settings.show_all_keys)))


func _ctrl_max_top() -> int:
	return maxi(0, _ctrl_rows().size() - CTRL_ROWS)


func _draw_controls(at: Vector2) -> void:
	var kt := _keys()
	var rows := _ctrl_rows()
	var binds: Dictionary = pref_work.get("key_bindings", {})
	var fs := int(round(11 * _scale()))
	var row_h := CTRL_LIST.size.y / CTRL_ROWS
	for n in CTRL_ROWS:
		var idx := ctrl_top + n
		if idx >= rows.size():
			break
		var rec: int = rows[idx]
		var colour := CTRL_TEXT_SEL if idx == ctrl_sel else CTRL_TEXT
		var texts := [kt.label(rec, _he()), kt.key_name(kt.key_of(rec, binds)), kt.button_name(kt.joystick_of(rec, binds))]
		for c in 3:
			var cell: Rect2 = CTRL_COLS[c]
			cell.position += at + CTRL_LIST.position + Vector2(0, row_h * n)
			# The list window clips at its right edge (x 400).
			cell.size.x = minf(cell.size.x, at.x + CTRL_LIST.end.x - cell.position.x)
			var r := _rect(cell)
			var base := r.position.y + (r.size.y + font.get_ascent(fs) - font.get_descent(fs)) / 2.0
			draw_string(font, Vector2(r.position.x, base), texts[c], HORIZONTAL_ALIGNMENT_LEFT if c == 0 else HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, colour)
	_draw_bar(at, CTRL_BAR, ctrl_top, _ctrl_max_top())


## The Keyboard page's scrollbar at page rect `bar`, showing first row `top` of `max_top`: arrows at the
## ends (frame 2 while held), the thumb in between.
func _draw_bar(at: Vector2, page_bar: Rect2, top: int, max_top: int) -> void:
	var bar := Rect2(at + page_bar.position, page_bar.size)
	var clip := CTRL_ARROW  # the whole 15×18 arrow (clipping it to the 11 px bar cropped its right side)
	# FUN_004f3700 moves the first button (SlUpB, a down-pointing arrow) to the bottom and leaves the
	# second (SlDownB, pointing up) at the top.
	var ax := bar.position.x - (CTRL_ARROW.x - CTRL_BAR.size.x) / 2.0  # centred on the 11 px bar
	_blit_region("pref/sldownb_%d.png" % (2 if ctrl_arrow == "up" else 0), Rect2(Vector2.ZERO, clip), Vector2(ax, bar.position.y))
	_blit_region("pref/slupb_%d.png" % (2 if ctrl_arrow == "down" else 0), Rect2(Vector2.ZERO, clip), Vector2(ax, bar.end.y - CTRL_ARROW.y))
	_blit("pref/sldcntrl.png", Vector2(bar.position.x, at.y + _bar_thumb_y(page_bar, top, max_top)))


## Thumb top (page y) of a scrollbar: between the arrows, proportional to the first row shown. Also the
## Arming and Pilot Records lists (their thumb is 15×35); ctrl_arrow / ctrl_drag hold whichever bar
## the mouse holds.
func _bar_thumb_y(bar: Rect2, top: int, max_top: int, thumb := CTRL_THUMB) -> float:
	var lo := bar.position.y + CTRL_ARROW.y
	var hi := bar.end.y - CTRL_ARROW.y - thumb.y
	return lo if max_top == 0 else lerpf(lo, hi, float(top) / max_top)


## Mouse down on a scrollbar (page coordinates): the new first row. The arrows scroll one row, the
## track a page of `rows` (UNCERTAIN: the page step), the thumb starts a drag.
func _bar_press(q: Vector2, bar: Rect2, top: int, max_top: int, rows: int, thumb := CTRL_THUMB) -> int:
	if q.y < bar.position.y + CTRL_ARROW.y:
		ctrl_arrow = "up"
		return top - 1
	if q.y >= bar.end.y - CTRL_ARROW.y:
		ctrl_arrow = "down"
		return top + 1
	var t := _bar_thumb_y(bar, top, max_top, thumb)
	if q.y >= t and q.y < t + thumb.y:
		ctrl_drag = q.y - t
		return top
	return top + rows * (1 if q.y > t else -1)


## The first row for a thumb dragged to page y `y`.
func _bar_drag_top(y: float, bar: Rect2, max_top: int, thumb := CTRL_THUMB) -> int:
	var lo := bar.position.y + CTRL_ARROW.y
	var hi := bar.end.y - CTRL_ARROW.y - thumb.y
	return roundi(clampf(inverse_lerp(lo, hi, y - ctrl_drag), 0.0, 1.0) * max_top)


func _ctrl_scroll(to: int) -> void:
	ctrl_top = clampi(to, 0, _ctrl_max_top())


## Selects list row `idx` and scrolls it into view (FUN_004f4700).
func _ctrl_select(idx: int) -> void:
	ctrl_sel = clampi(idx, 0, _ctrl_rows().size() - 1)
	if ctrl_sel < ctrl_top:
		ctrl_top = ctrl_sel
	elif ctrl_sel > ctrl_top + CTRL_ROWS - 1:
		ctrl_top = ctrl_sel - CTRL_ROWS + 1


## Mouse down on the Controls page (page coordinates): a row takes the selection and the keyboard,
## the arrows scroll one row, the track one page (UNCERTAIN: the page step), the thumb drags.
func _ctrl_press(q: Vector2) -> bool:
	if CTRL_LIST.has_point(q):
		var idx := ctrl_top + int((q.y - CTRL_LIST.position.y) / (CTRL_LIST.size.y / CTRL_ROWS))
		if idx < _ctrl_rows().size():
			_ctrl_select(idx)
			ctrl_focus = true
		return true
	if not CTRL_BAR.has_point(q):
		return false
	_ctrl_scroll(_bar_press(q, CTRL_BAR, ctrl_top, _ctrl_max_top(), CTRL_ROWS))
	return true


## A key pressed while the list has the keyboard (FUN_00511dc0): the arrow keys move in the list;
## any other key (with one modifier: Ctrl, Shift, Alt or Win) is assigned to the selected function.
## If another function has it, msg 36 asks; Yes takes it from that function.
func _ctrl_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_UP:
			_ctrl_select(ctrl_sel - 1)
			return
		KEY_DOWN:
			_ctrl_select(ctrl_sel + 1)
			return
		KEY_LEFT, KEY_RIGHT:
			return
	var kt := _keys()
	var key: int = kt.key_of_event(event)
	var rows := _ctrl_rows()
	if key == 0 or ctrl_sel >= rows.size():
		return
	var rec: int = rows[ctrl_sel]
	var binds: Dictionary = pref_work.key_bindings
	var other: int = kt.find_key(key, binds, rec)
	if other < 0:
		kt.set_binding(binds, rec, key, kt.joystick_of(rec, binds))
		return
	_message(36, [["yes", func():
		kt.set_binding(binds, other, 0, kt.joystick_of(other, binds))
		kt.set_binding(binds, rec, key, kt.joystick_of(rec, binds))], ["no", Callable()]])


## A joystick button pressed while the list has the keyboard (FUN_00511fb0, the poller's msg 0x555): it is
## assigned to the selected function; if another function has it, msg 37 asks and Yes takes it from that one.
func _ctrl_button(button: int) -> void:
	var kt := _keys()
	var rows := _ctrl_rows()
	if ctrl_sel >= rows.size():
		return
	var rec: int = rows[ctrl_sel]
	var binds: Dictionary = pref_work.key_bindings
	var other: int = kt.find_joystick(button, binds, rec)
	if other < 0:
		kt.set_binding(binds, rec, kt.key_of(rec, binds), button)
		return
	_message(37, [["yes", func():
		kt.set_binding(binds, other, kt.key_of(other, binds), -1)
		kt.set_binding(binds, rec, kt.key_of(rec, binds), button)], ["no", Callable()]])


static func _ltrb(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2] - a[0], a[3] - a[1])


## Slider value 0..1; the master volume is not stored (the original sets the system mixer).
func _pref_value(key: String) -> float:
	if key == "master_volume":
		return AudioServer.get_bus_volume_linear(0)
	return float(pref_work.get(key, 0.0))


## pref/slider.bmp: the top half drawn through the bottom half's mask (SRCAND, then SRCPAINT).
func _slider_thumb() -> Texture2D:
	var key := "pref/slider_thumb"
	if not textures.has(key):
		var src := _tex("pref/slider.png")
		textures[key] = ImageTexture.create_from_image(Img.masked_sprite(src.get_image())) if src != null else null
	return textures[key]


## Scoring strip frame (§12.3): 0 = 120 % ... 20 = 20 % ... 24 = no scoring.
static func _score_frame(p: Dictionary) -> int:
	return clampi(24 - int(20.0 * score_multiplier(p) + 0.5), 0, 24)


## The score multiplier of the Gameplay options (FUN_004f1120, DAT_0083b998), kept with each attempt.
static func score_multiplier(p: Dictionary) -> float:
	var m := 1.0 + (0.2 if p.get("ai_level") == 2 else 0.0)
	var costs := {"no_wind": 0.05, "no_blackouts": 0.1, "no_spins": 0.05, "no_stalls": 0.05,
		"easy_aiming": 0.1, "no_malfunctions": 0.05, "invulnerable": 1.0, "no_crashes": 0.5,
		"unlimited_ammo": 0.5, "unlimited_fuel": 0.25}
	for k in costs:
		if p.get(k, false):
			m -= costs[k]
	if p.get("ai_level") == 0:
		m -= 0.2
	return maxf(m, 0.0)


const TAB_SQUEEZE := 0.8


## Our tab buttons (EXTRAS_BAND moved down 44 px per tab) for the current frame, with our labels.
func _draw_extras_tab(delta: Vector2) -> void:
	for k in OUR_TABS.size():
		var page: String = OUR_TABS[k][0]
		var f: int = frames.get(page.to_lower(), 2 if Settings.pref_page == page else 0)
		var t := _extras_tab_tex(f)
		if t == null:
			return
		var step := Vector2(0, EXTRAS_STEP * (k + 1))
		var panel_pos := Vector2(0, 35)
		var dest := panel_pos + EXTRAS_BAND.position + step + delta
		draw_texture_rect(t, _rect(Rect2(dest, EXTRAS_BAND.size)), false)
		var label := Rect2(panel_pos + EXTRAS_LABEL.position + step + delta, EXTRAS_LABEL.size)
		# Like the labels baked into the original buttons: light grey on a dark shadow; English heavy and
		# condensed, Hebrew regular weight (as the Hebrew pack's buttons).
		var lf: Font = font if _he() else font_bold
		var fs := int(round(14 * _scale()))
		var box := _rect(label)
		var base := box.position.y + (box.size.y + lf.get_ascent(fs) - lf.get_descent(fs)) / 2.0
		var text: String = _t(page) if _he() else OUR_TABS[k][1]
		var sq := TAB_SQUEEZE if not _he() else 1.0
		var w := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * sq
		var x := box.position.x + (box.size.x - w) / 2.0
		draw_set_transform(Vector2(x, base), 0.0, Vector2(sq, 1.0))
		draw_string(lf, Vector2(_scale(), _scale()), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(25, 25, 25))
		draw_string(lf, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(205, 208, 212))
		draw_set_transform(Vector2.ZERO)


## Ours: the Jet list button the F-35I replaces (Settings.f35i_slot) relabelled "F-35I" in the baked-label style
## (its own frame's art with the label blended out, as our Extras tab).
func _draw_f35i_slot(p: int, panel: Dictionary, delta: Vector2) -> void:
	var slot := int(Settings.f35i_slot)
	if slot < 0:
		return
	for b in panel.buttons.size():
		var btn: Dictionary = panel.buttons[b]
		if JET_IDS.get(_norm(btn.label), -1) != slot:
			continue
		var f := _frame("%d/%d" % [p, b], btn.label)
		var r: Array = btn.rect
		var t := _jet_button_tex(String(panel.name).to_lower(), Rect2(r[0] - panel.pos[0], r[1] - panel.pos[1], r[2], r[3]), f)
		if t == null:
			return
		var box := _rect(Rect2(Vector2(r[0], r[1]) + delta, Vector2(r[2], r[3])))
		draw_texture_rect(t, box, false)
		# As the baked labels: English heavy and condensed; Hebrew regular weight, letter-spaced, a softer grey (the
		# Hebrew pack's buttons).
		var he := _he()
		var lf: Font = font if he else font_bold
		var fs := int(round(15 * _scale()))
		var text := "אדיר" if he else "F-35I"
		var sq := 1.0 if he else TAB_SQUEEZE
		var gap := 1.0 * _scale() if he else 0.0
		var w := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * sq + gap * (text.length() - 1)
		var base := box.position.y + (box.size.y + lf.get_ascent(fs) - lf.get_descent(fs)) / 2.0 - (_scale() if he else 0.0)
		# The baked labels' grey (sampled from the Jet list art), dimmer pressed / disabled.
		var col := Color8(188, 190, 194) if f < 2 else (Color8(160, 162, 166) if f == 2 else Color8(110, 112, 115))
		draw_set_transform(Vector2(box.position.x + (box.size.x - w) / 2.0, base), 0.0, Vector2(sq, 1.0))
		if gap == 0.0:
			draw_string(lf, Vector2(_scale(), _scale()), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(25, 25, 25))
			draw_string(lf, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			# Letter by letter (right to left for Hebrew), each a fixed gap apart.
			var x := w
			for ch in text:
				var cw := lf.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				x -= cw
				draw_string(lf, Vector2(x + _scale(), _scale()), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(25, 25, 25))
				draw_string(lf, Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				x -= gap
		draw_set_transform(Vector2.ZERO)


## The F-35I's Jet list description (Hebrew in strings_he.json).
const F35I_DESC := "The IAF's fifth-generation stealth fighter: internal weapon bays, sensor fusion, a helmet display."


## The baked label's area inside a Jet list button (button-relative, panel px).
const JET_LABEL := Rect2(14, 9, 81, 21)


## A Jet list button (panel-relative rect `src`) from palettes/<panel>_<f>, its baked label blended out.
func _jet_button_tex(panel: String, src: Rect2, f: int) -> Texture2D:
	var key := "jet_slot_%s_%d_%d" % [panel, int(src.position.y), f]
	if not textures.has(key):
		var path := dir.path_join("img/palettes/%s_%d.png" % [panel, f])
		var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null:
			textures[key] = null
			return null
		img.convert(Image.FORMAT_RGBA8)
		var band: Image = img.get_region(Rect2i(src.position * art_scale, src.size * art_scale))
		var a := Rect2i(JET_LABEL.position * art_scale, JET_LABEL.size * art_scale)
		for y in range(a.position.y, a.end.y):
			var c0 := band.get_pixel(a.position.x - 1, y)
			var c1 := band.get_pixel(a.end.x, y)
			for x in range(a.position.x, a.end.x):
				band.set_pixel(x, y, c0.lerp(c1, float(x - a.position.x + 1) / float(a.size.x + 1)))
		band.generate_mipmaps()
		textures[key] = ImageTexture.create_from_image(band)
	return textures[key]


## The band cut from palettes/ppref_<f>, label pixels replaced per row by a blend of the pixels
## left and right of the label.
func _extras_tab_tex(f: int) -> Texture2D:
	var key := "extras_tab_%d" % f
	if not textures.has(key):
		var imgs := []
		for n in [0, f]:
			var path := dir.path_join("img/palettes/ppref_%d.png" % n)
			var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
			if img == null:
				textures[key] = null
				return null
			img.convert(Image.FORMAT_RGBA8)
			imgs.append(img)
		# The panel from _0, the button rect (Gameplay: panel (16,208) 109x39) from _<f>.
		var band: Image = imgs[0].get_region(Rect2i(EXTRAS_BAND.position * art_scale, EXTRAS_BAND.size * art_scale))
		var button := Rect2(16, 208, 109, 39)
		band.blit_rect(imgs[1], Rect2i(button.position * art_scale, button.size * art_scale), Vector2i((button.position - EXTRAS_BAND.position) * art_scale))
		var a := Rect2i((EXTRAS_LABEL.position - EXTRAS_BAND.position) * art_scale, EXTRAS_LABEL.size * art_scale)
		for y in range(a.position.y, a.end.y):
			var c0 := band.get_pixel(a.position.x - 1, y)
			var c1 := band.get_pixel(a.end.x, y)
			for x in range(a.position.x, a.end.x):
				band.set_pixel(x, y, c0.lerp(c1, float(x - a.position.x + 1) / float(a.size.x + 1)))
		band.generate_mipmaps()
		textures[key] = ImageTexture.create_from_image(band)
	return textures[key]


## Extras page (ours): one row per option in the Gameplay page's grid (rows 35 apart from y 45,
## columns at x 24 / 164 / 285), LEDs copied from the Gameplay art. Mirrored in Hebrew.
func _extras_items() -> Array:
	var items := []
	var rows := _extras_rows()
	for i in range(extras_top, mini(rows.size(), extras_top + EXTRAS_ROWS)):
		var opt: Array = rows[i]
		var y := 45.0 + EXTRAS_ROW * (i - extras_top)
		var choices: Array = opt[2]
		if choices.size() > 3:
			# Too many for the columns: one cell shows the current choice and a click picks the next.
			var cur = pref_work.get(opt[0], choices[0][1])
			var k := 0
			for j in choices.size():
				if choices[j][1] == cur:
					k = j
			var cell := Rect2(164.0, y, 250.0, EXTRAS_ROW)
			if _he():
				cell.position.x = CONTENT.size.x - cell.end.x
			items.append({"rect": cell, "key": opt[0], "value": choices[(k + 1) % choices.size()][1],
				"label": choices[k][0], "available": true, "on": true})
			continue
		for j in choices.size():
			# Two choices in the Gameplay page's columns (x 164 / 285); three narrower; all left of the scrollbar.
			var r := Rect2(164.0 + 121.0 * j, y, 111.0 if j == 0 else 129.0, EXTRAS_ROW) if choices.size() < 3 \
					else Rect2([164.0, 240.0, 314.0][j], y, [74.0, 72.0, 100.0][j], EXTRAS_ROW)
			if _he():
				r.position.x = CONTENT.size.x - r.end.x
			var value = choices[j][1]
			var available: bool = not (typeof(value) == TYPE_STRING and value == "he" and not Settings.hebrew_available())
			if String(opt[0]).begins_with("imagery_"):
				available = ImageryLayers.available(String(value))
			items.append({"rect": r, "key": opt[0], "value": value, "label": choices[j][0], "available": available})
	return items


## Our pages (Extras, Physics): the general background and the header, as on the original pages.
func _draw_our_page(title: String) -> void:
	_blit("screens/sgeneral.png", CONTENT.position)
	_text_line(Rect2(CONTENT.position + Vector2(24, 12), Vector2(CONTENT.size.x - 48, 22)), _art(title), LIST_TITLE_PX + 2, LIST_TITLE, font_art)


## Our label text in the art's style: capitals (English); Hebrew as is.
func _art(text: String) -> String:
	return _t(text) if _he() else text.to_upper()


## A row separator across our pages at page height `y`: opaque and one page pixel thick, so it covers
## the background's grid lines and every rule looks the same whether or not it falls on one.
func _draw_rule(y: float) -> void:
	var at := CONTENT.position
	draw_line(_to_screen(at + Vector2(18, y)), _to_screen(at + Vector2(CONTENT.size.x - 18, y)), LIST_TITLE.darkened(0.55), maxf(1.0, _scale()))


## An option of our pages (page rect `r`): the LED with its frame from the Gameplay page's NO WIND
## row (page (28,55)), `led_y` into the row (lit when `on`; none when unavailable), then the label
## `text_y` into the row. Mirrored in Hebrew.
func _draw_option(r: Rect2, label: String, on: bool, led_y: float, text_y: float, available := true) -> void:
	var at := CONTENT.position
	var led := Rect2(Vector2(4, led_y), Vector2(11, 11))
	var led_x := r.end.x - led.end.x if _he() else r.position.x + led.position.x
	if available:
		_blit_region("pref/gamep_%d.png" % (1 if on else 0), Rect2(Vector2(28, 55), led.size), at + Vector2(led_x, r.position.y + led.position.y))
	var box := Rect2(at + Vector2(r.position.x + (0.0 if _he() else 22.0), r.position.y + text_y), Vector2(r.size.x - 22, 20))
	_text_fit(box, _art(label), LIST_TITLE_PX, (LIST_DESC_LIT if on else LIST_DESC) if available else Color(LIST_DESC, 0.5), font_art)


func _draw_extras() -> void:
	_draw_our_page("Extras")
	_blit("pref/defbut_%d.png" % (2 if pref_default_held else 0), CONTENT.position + PREF_DEFAULT.position)
	var rows := _extras_rows()
	var shown := mini(rows.size() - extras_top, EXTRAS_ROWS)
	for i in shown + 1:
		_draw_rule(45.0 + EXTRAS_ROW * i)
	if _extras_max_top() > 0:
		_draw_bar(CONTENT.position, _extras_bar(), extras_top, _extras_max_top())
	for k in shown:
		var i := extras_top + k
		var r := Rect2(24, 45.0 + EXTRAS_ROW * k + 4, 136, 20)
		if _he():
			r.position.x = CONTENT.size.x - r.end.x
		_text_fit(Rect2(CONTENT.position + r.position, r.size), _art(rows[i][1]), LIST_TITLE_PX, LIST_TITLE, font_art)
	for it in _extras_items():
		var on: bool = it.get("on", pref_work.get(it.key) == it.value)
		_draw_option(it.rect, it.label, on, 10, 4, it.available)


## Physics page (ours): one check per "Better physics" option (rows of 20 px from y 45, LEDs
## from the Gameplay art; the rows scrolled into view), plus ALL / NONE in the header. Mirrored in Hebrew.
func _physics_items() -> Array:
	var items := []
	var w := CONTENT.size.x
	var ids: Array = Settings.BETTER.keys()
	for i in range(phys_top, mini(ids.size(), phys_top + PHYSICS_ROWS)):
		var r := Rect2(24, 45.0 + PHYSICS_ROW * (i - phys_top), PHYSICS_BAR.position.x - 24 - 8, PHYSICS_ROW)
		if _he():
			r.position.x = w - r.end.x
		items.append({"rect": r, "key": ids[i], "label": Settings.BETTER[ids[i]]})
	for j in 2:
		var r := Rect2(w - 24 - 70 * (2 - j), 12, 64, 22)
		if _he():
			r.position.x = w - r.end.x
		items.append({"rect": r, "key": ["all", "none"][j], "label": ["All on", "All off"][j]})
	return items


## The Extras page's scrollbar (page rect), on the left in Hebrew.
func _extras_bar() -> Rect2:
	var bar := EXTRAS_BAR
	if _he():
		bar.position.x = CONTENT.size.x - bar.end.x
	return bar


func _extras_max_top() -> int:
	return maxi(0, _extras_rows().size() - EXTRAS_ROWS)


func _extras_scroll(to: int) -> void:
	extras_top = clampi(to, 0, _extras_max_top())


## The Physics page's scrollbar (page rect), on the left in Hebrew.
func _phys_bar() -> Rect2:
	var bar := PHYSICS_BAR
	if _he():
		bar.position.x = CONTENT.size.x - bar.end.x
	return bar


func _phys_max_top() -> int:
	return maxi(0, Settings.BETTER.size() - PHYSICS_ROWS)


func _phys_scroll(to: int) -> void:
	phys_top = clampi(to, 0, _phys_max_top())


func _draw_physics() -> void:
	_draw_our_page("Better physics")
	_draw_rule(45)
	_draw_bar(CONTENT.position, _phys_bar(), phys_top, _phys_max_top())
	for it in _physics_items():
		var r: Rect2 = it.rect
		if it.key == "all" or it.key == "none":
			_text_line(Rect2(CONTENT.position + r.position + Vector2(0, 3), r.size), _art(it.label), LIST_TITLE_PX, LIST_DESC_LIT, font_art)
		else:
			_draw_option(r, it.label, pref_work.get("better", Settings.better)[it.key], 7, 1)


# --- input ------------------------------------------------------------------------------

## Button under a point (menu coordinates): "panel/button", "back", "main" or "".
func _hit(p: Vector2) -> String:
	if Rect2(BACK_POS, Vector2(114, 22)).has_point(p):
		return "" if screen in NO_BACK else "back"
	if Rect2(MAIN_POS, Vector2(35, 59)).has_point(p):
		return "main"
	if screen == "pref":
		for k in OUR_TABS.size():
			if Rect2(EXTRAS_TAB.position + Vector2(0, EXTRAS_STEP * k), EXTRAS_TAB.size).has_point(p):
				return OUR_TABS[k][0].to_lower()
	var panels := _panels()
	for pi in panels.size():
		for bi in panels[pi].buttons.size():
			var btn: Dictionary = panels[pi].buttons[bi]
			var r: Array = btn.rect
			if Rect2(r[0], r[1], r[2], r[3]).has_point(p) and _button_enabled(btn.label):
				return "%d/%d" % [pi, bi]
	return ""


func _gui_input(event: InputEvent) -> void:
	if busy:
		return
	if event is InputEventMouseMotion:
		if not pref_drag.is_empty():
			_pref_slide(_to_menu(event.position).x - CONTENT.position.x)
		if ctrl_drag >= 0.0:
			var y := _to_menu(event.position).y - CONTENT.position.y
			if Settings.pref_page == "Physics":
				_phys_scroll(_bar_drag_top(y, _phys_bar(), _phys_max_top()))
			elif Settings.pref_page == "Extras":
				_extras_scroll(_bar_drag_top(y, _extras_bar(), _extras_max_top()))
			else:
				_ctrl_scroll(_bar_drag_top(y, CTRL_BAR, _ctrl_max_top()))
		var k := _hit(_to_menu(event.position))
		hover_key = k if "/" in k else ""
		# Dragging out of a held button releases it; back in presses it again (§3.1).
		if held != "":
			var inside := k == held
			if inside and frames.get(held, 0) != 2:
				frames[held] = 2
			elif not inside and frames.get(held, 0) == 2:
				frames.erase(held)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _to_menu(event.position)
		if event.pressed:
			if screen == "pref" and msgbox == null and _pref_press(p - CONTENT.position):
				return
			held = _hit(p)
			if held != "":
				_animate_press(held)
		elif ctrl_drag >= 0.0 or ctrl_arrow != "":
			ctrl_drag = -1.0
			ctrl_arrow = ""
		elif not pref_drag.is_empty() or pref_default_held:
			_pref_release(p - CONTENT.position)
		elif held != "":
			var key := held
			held = ""
			_animate_release(key, _hit(p) == key)


## Mouse down on a Preferences page (page coordinates): checks toggle, radios select, sliders
## start a drag (the hit area extends a thumb width past both ends), DEFAULT presses.
func _pref_press(q: Vector2) -> bool:
	var page: String = Settings.pref_page
	if not Rect2(Vector2.ZERO, CONTENT.size).has_point(q):
		return false
	if page == "Extras" and PREF_DEFAULT.has_point(q):
		pref_default_held = true
		_play("buttonin")
		return true
	if page == "Extras":
		if _extras_max_top() > 0 and _extras_bar().has_point(q):
			_extras_scroll(_bar_press(q, _extras_bar(), extras_top, _extras_max_top(), EXTRAS_ROWS))
			return true
		for it in _extras_items():
			if it.available and it.rect.has_point(q):
				pref_work[it.key] = it.value
				return true
		return false
	if page == "Physics":
		if _phys_bar().has_point(q):
			_phys_scroll(_bar_press(q, _phys_bar(), phys_top, _phys_max_top(), PHYSICS_ROWS))
			return true
		for it in _physics_items():
			if it.rect.has_point(q):
				if it.key == "all" or it.key == "none":
					for id in Settings.BETTER:
						pref_work.better[id] = it.key == "all"
				else:
					pref_work.better[it.key] = not pref_work.better[it.key]
				return true
		return false
	if page == "Devices":
		if PREF_DETENT.off.has_point(q):
			pref_work["throttle_detent"] = -1
			return true
		if PREF_DETENT.set.has_point(q) and Joystick.device() >= 0:
			pref_work["throttle_detent"] = Joystick.raw_throttle()
			return true
	if page == "Graphics" and PREF_VSYNC.has_point(q):
		pref_work["vsync"] = not bool(pref_work.get("vsync", true))
		return true
	if page != "Devices" and PREF_DEFAULT.has_point(q):
		pref_default_held = true
		_play("buttonin")
		return true
	if page == "Controls":
		return _ctrl_press(q)
	for c in PREF_CONTROLS.get(page, []):
		var r := _ltrb(c[3])
		match c[0]:
			"check":
				if r.has_point(q):
					pref_work[c[1]] = not pref_work[c[1]]
					if c[1] == "mute":
						_apply_music_volume()
					return true
			"radio":
				if r.has_point(q):
					pref_work[c[1]] = c[2]
					return true
			"slider":
				if r.grow_individual(PREF_THUMB.x, 0, PREF_THUMB.x, 0).has_point(q):
					pref_drag = [c[1], r, c[2]]
					_pref_slide(q.x)
					if PREF_PREVIEW.has(c[1]):
						var s := _sound(PREF_PREVIEW[c[1]])
						if s != null:
							preview.stream = _looped(s)
							preview.volume_db = linear_to_db(maxf(_pref_value(c[1]), 0.0001))
							preview.play()
					return true
	return false


## Slider drag: v = (x - x0) / (x1 - x0) clamped to [0, 1]; Graphics sliders snap to their step
## (UNCERTAIN: the original's rounding).
func _pref_slide(x: float) -> void:
	var key: String = pref_drag[0]
	var r: Rect2 = pref_drag[1]
	var step: float = pref_drag[2]
	var v := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	if step > 0.0:
		v = roundf(v / step) * step
	if key == "master_volume":
		AudioServer.set_bus_volume_linear(0, v)
		return
	pref_work[key] = v
	if key == "music_volume":
		_apply_music_volume()
	elif PREF_PREVIEW.has(key):
		preview.volume_db = linear_to_db(maxf(v, 0.0001))


func _pref_release(q: Vector2) -> void:
	if pref_default_held:
		pref_default_held = false
		if PREF_DEFAULT.has_point(q):
			_play("buttonout")
			_pref_defaults()
	pref_drag = []
	preview.stop()


## DEFAULT (§12.2): the page's settings back to the original defaults (Controls: the key table).
func _pref_defaults() -> void:
	for c in PREF_CONTROLS.get(Settings.pref_page, []):
		if c[1] != "master_volume":
			pref_work[c[1]] = Settings.default_value(c[1])
	if Settings.pref_page == "Controls":
		pref_work.key_bindings = {}  # the whole table from 0x64c3c8 (@511ca5)
	if Settings.pref_page == "Graphics":
		pref_work["vsync"] = Settings.default_value("vsync")
	if Settings.pref_page == "Extras":  # ours: every Extras option except the language
		for opt in _extras_rows():
			if opt[0] != "language":
				pref_work[opt[0]] = Settings.default_value(opt[0])
	_apply_music_volume()


func _pref_changed() -> bool:
	for k in pref_work:
		if pref_work[k] != Settings.get(k):
			return true
	return false


## Leaving a screen by BACK / MAIN / Esc. Preferences first asks msg 38 "Save changes?"
## (Yes / No / Cancel) when the working copy differs (FUN_004fe1b0).
func _leave(to: String) -> void:
	if screen == "pref" and _pref_changed():
		_message(38, [["yes", _pref_close.bind(to, true)], ["no", _pref_close.bind(to, false)], ["can", Callable()]])
		return
	_go(to)


## Yes commits the working copy (and saves it); No drops it and restores the previewed volumes.
func _pref_close(to: String, commit: bool) -> void:
	var language := Settings.language
	if commit:
		for k in pref_work:
			Settings.set(k, pref_work[k])
		Settings.save()
	pref_work.clear()
	_apply_music_volume()
	if Settings.language != language:
		_load_menu_data()
	_go(to)


## Press: frames _1, _2 with ButtonIn.wav, each held for half the sound (FUN_004e9760).
func _animate_press(key: String) -> void:
	_play("buttonin")
	var step := _sound_length("buttonin") / 2.0
	frames[key] = 1
	await get_tree().create_timer(step).timeout
	if held == key:
		frames[key] = 2


## Release: _2, _1, _0 with ButtonOut.wav, then the action if still inside the button.
func _animate_release(key: String, inside: bool) -> void:
	if not inside:
		frames.erase(key)
		return
	busy = true
	_play("buttonout")
	var step := _sound_length("buttonout") / 3.0
	for f in [2, 1]:
		frames[key] = f
		await get_tree().create_timer(step).timeout
	frames.erase(key)
	busy = false
	_on_button(key)


func _on_button(key: String) -> void:
	if key == "back":
		if screen == "tsd":
			_message(8, [["yes", _go.bind(tsd_return)], ["no", Callable()]])
		elif screen == "arm":  # the content's vfunc +0xd4 (FUN_005073e0): checks, then TSD
			arm.leave(3)
		else:
			_leave(_back_target())
		return
	if key == "main":
		if flight != null:
			# MAIN (FUN_004ecff0) on the FlyTSD / in-flight Preferences: the quit-mission box of Ctrl+Q
			# (FUN_004e2fa0(3)), as the flight shows it (game/terrain/terrain_view.gd _quit_key).
			_message(8, [["yes", flight._end_flight.bind(true)], ["no", Callable()]])
			return
		if screen in QUIT_SCREENS:
			_quit()
		elif screen in ["tsd", "arm"]:
			_message(8, [["yes", _go.bind("main")], ["no", Callable()]])
		else:
			_leave("main")
		return
	if key in ["extras", "physics"]:
		for k in checked.keys():
			checked[k] = false
		Settings.pref_page = key.capitalize()
		ctrl_focus = false
		return
	var btn := _button(key)
	if btn.is_empty():
		return
	match btn.kind:
		"Check":
			checked[key] = not checked.get(key, false)
		"CheckGroup":
			# Only the buttons of the same panel (Arming has two groups: AA / AG / Misc, the flights).
			for k in checked.keys():
				if k.get_slice("/", 0) == key.get_slice("/", 0):
					checked[k] = false
			checked[key] = true
	var label: String = btn.label
	if screen == "pref":
		Settings.pref_page = label
		ctrl_focus = false
		return
	if screen in ["tsd", "arm", "flytsd"]:
		_tsd_button(key, _norm(label), btn)
		return
	if screen == "deb":
		_debrief_button(_norm(label))
		return
	if screen == "log":
		match _norm(label):
			"login":
				if records.login():
					_go("main")
			"newpilot":
				records.new_pilot()
			"removepilot":
				records.remove_pilot()
		return
	var target: String = FORWARD.get(screen, {}).get(_norm(label), "")
	if target != "":
		_go(target)
		return
	var row := _row_for(label)
	if screen in TO_JET and not row.is_empty():
		Settings.mission_id = int(row.id)
		jet_parent = screen
		_go("jet")
	elif screen in LOADS_MISSION:
		if screen == "jet":
			Settings.jet_id = JET_IDS.get(_norm(label), 1)
		else:
			Settings.jet_id = -1  # the mission's own jet
			if not row.is_empty():
				Settings.mission_id = int(row.id)
		_load_mission()


## Debrief buttons (FUN_004ff440). New Mission: back to the mission's list (FUN_004ff620). Replay
## (same mission) and Next Mission (FUN_004ff7e0) then go through FUN_004ff540: a training mission
## 311–319 / 321–329 opens the Jet list (screen 9 / 10) so a plane is picked before each training
## flight (v1.1; v1.0 reloaded the mission), other 300–399 ids do nothing, the rest reload the mission
## (-> TSD).
func _debrief_button(label: String) -> void:
	var passed: bool = Settings.debrief.get("passed", false)
	Settings.debrief = {}
	var id: int = Settings.mission_id
	if label == "newmission":
		_go(new_mission_screen(id))
		return
	if label == "nextmission":
		id = next_mission(id, passed or _cheat())
		Settings.mission_id = id
	elif label != "replaymission":
		return
	if id >= 300 and id <= 399:
		if id >= 311 and id <= 319:
			jet_parent = "basic"
			_go("jet")
		elif id >= 321 and id <= 329:
			jet_parent = "combat"
			_go("jet")
		return
	screen = new_mission_screen(id)
	_load_mission()


## The list a mission belongs to (FUN_004ff620, single player): New Mission and the TSD's BACK go there.
static func new_mission_screen(id: int) -> String:
	for r in [[111, 117, "his1mis"], [121, 127, "his2mis"], [131, 137, "his3mis"], [211, 217, "fut1mis"],
			[221, 227, "fut2mis"], [231, 237, "fut3mis"], [311, 315, "basic"], [321, 326, "combat"]]:
		if id >= r[0] and id <= r[1]:
			return r[2]
	return "mc" if id == 0x213 or id == 0x29a else "main"


## The mission Next Mission flies (FUN_004ff7e0; 0 = none, the button is disabled): the next one of the
## war or course, a Future front's next only when this one was passed (FUN_004f6d40; or the "make sim" /
## "not war" cheat, passed in by the callers as `passed`). Not ported: the Jump_In pick for 401–407 (FUN_004f1650) and the
## multiplayer-only 511–516 rules (single player gets 1 / 0 there).
static func next_mission(id: int, passed: bool) -> int:
	match id:
		117:
			return 121
		127:
			return 131
		137:
			return 211
		315:
			return 321
		511, 512, 513, 514, 515:
			return 1
	if (id >= 111 and id <= 116) or (id >= 121 and id <= 126) or (id >= 131 and id <= 136) \
			or (id >= 311 and id <= 314) or (id >= 321 and id <= 325):
		return id + 1
	if (id >= 211 and id <= 216) or (id >= 221 and id <= 226) or (id >= 231 and id <= 236):
		return id + 1 if passed else 0
	return 0


## TSD / Arming buttons (§8; Fly FUN_005045b0, Arming FUN_005070c0).
func _tsd_button(key: String, label: String, btn: Dictionary) -> void:
	if screen == "arm":
		_arm_button(key, label)
		return
	if btn.kind in ["Check", "CheckGroup"]:
		if btn.kind == "CheckGroup":
			for f in Tsd.FLIGHT_NAMES:
				tsd_checks[f] = false
		tsd_checks[label] = checked.get(key, false)
	if label in Tsd.FLIGHT_NAMES:
		tsd.select_flight(_flight_number(label))
	match label:
		"fly" when flight != null:
			# FlyTSD Fly (FUN_005045b0, exit 4): back to the flight. Not ported: flying another
			# formation's aircraft (FUN_004d31f0); Visit (FUN_005046b0) is not ported either.
			_go("")
		"fly":
			if _selected_flight() == "":
				_message(25, [["ok", Callable()]])
			else:
				_fly()
		"arm":
			_go("arm")
		"tacticaldisplay":
			_go("tsd")
		"zoomin":
			tsd.zoom_by(tsd.ZOOM_STEP)
		"zoomout":
			tsd.zoom_by(1.0 / tsd.ZOOM_STEP)
		"briefing":
			tsd.open_briefing(tsd_checks.briefing)
		"waypoint", "text", "grid":
			tsd.set_layer(label, tsd_checks[label])


## Arming buttons (FUN_005070c0). A flight change runs the checks first; on failure the old flight
## button is checked again (FUN_00505a10). The flight picked here is the TSD's too (DAT_0083b8a4).
func _arm_button(key: String, label: String) -> void:
	var tab := ["aa", "ag", "misc"].find(label)
	if tab >= 0:
		arm.set_tab(tab)
		return
	if label in Tsd.FLIGHT_NAMES:
		var n := _flight_number(label)
		if arm.change_flight(n):
			for f in Tsd.FLIGHT_NAMES:
				tsd_checks[f] = f == label
			tsd.select_flight(n)
		else:
			checked.erase(key)
			_restore_tsd_checks()
		return
	match label:
		"fly":
			arm.leave(2)
		"tacticaldisplay":
			arm.leave(1)


## The briefing window's close button unchecks Briefing.
func tsd_briefing_closed() -> void:
	tsd_checks["briefing"] = false
	checked.erase(_key_for_label("Briefing"))


## A briefing diagram / card, from the Hebrew pack when the language is Hebrew.
func briefing_image(stem: String) -> Texture2D:
	var base := Settings.assets_dir().path_join("converted/briefings")
	for sub in (["img_he", "img"] if _he() else ["img"]):
		var t := Img.load_texture(base.path_join(sub).path_join(stem + ".png"), true)
		if t != null:
			return t
	return null


## Double-click on a flight leader in the TSD: select that flight and fly.
func tsd_fly_flight(n: int) -> void:
	for f in Tsd.FLIGHT_NAMES:
		tsd_checks[f] = false
	tsd_checks[Tsd.FLIGHT_NAMES[n - 1]] = true
	tsd.select_flight(n)
	_fly()


## Debrief: the mission's headline (misc 0x47e / 0x492) and the notes of the events that fired.
## (Where the original draws them on the Deb screen is UNCERTAIN; shown in the content window.)
func _draw_debrief() -> void:
	_blit("screens/sgeneral.png", CONTENT.position)
	var d: Dictionary = Settings.debrief
	var box := Rect2(CONTENT.position + Vector2(20, 20), CONTENT.size - Vector2(40, 40))
	_text_line(Rect2(box.position, Vector2(box.size.x, 16)), String(d.get("headline", "")), LIST_TITLE_PX, LIST_TITLE, font_bold)
	_text_block(Rect2(box.position + Vector2(0, 30), box.size - Vector2(0, 30)), String(d.get("notes", "")), LIST_DESC_PX + 1, LIST_DESC_LIT)


func _fly() -> void:
	# The route as left on the TSD (waypoints may have been dragged) and the flight picked there.
	Settings.player_flight = 0
	if tsd != null:
		Settings.route_override = tsd.selected_route()
		Settings.player_flight = tsd.default_flight()
	busy = true
	get_tree().change_scene_to_file("res://terrain/terrain_view.tscn")


func _row_for(label: String) -> Dictionary:
	for row in _list().get("rows", []):
		if _norm(row.name) == _norm(label):
			return row
	return {}


func _back_target() -> String:
	if screen == "jet":
		return jet_parent
	return BACK.get(screen, "main")


## Screen change (FUN_004eb760): title tab and panels out, new screen, panels and title in.
func _go(to: String) -> void:
	if flight != null and screen in ["flytsd", "pref"]:
		# BACK / Esc / Fly leave the FlyTSD (exit 4) and the in-flight Preferences (exit 5): the flight.
		flight.close_front_end()
		return
	if not menus.has(to) or busy:
		return
	busy = true
	hover_key = ""
	var old_panels := _panel_names(screen)
	for f in [1, 0]:
		title_frame = f
		await get_tree().create_timer(TITLE_FRAME).timeout
	var slide := old_panels != _panel_names(to)
	if slide:
		await _slide(0.0, "palettein")
	screen = to
	_enter_screen()
	_start_music()
	if slide:
		await _slide(1.0, "paletteout")
	for f in [0, 1, 2]:
		title_frame = f
		await get_tree().create_timer(TITLE_FRAME).timeout
	busy = false


## The panels of screen `of` (lower-case names): the panels slide only when they change.
func _panel_names(of: String) -> Array:
	var names: Array = []
	for p in menus.get(of, {}).get("panels", []):
		names.append(String(p.name).to_lower())
	return names


## Panels slide for the length of the wav that plays with them (§2).
func _slide(to: float, wav: String) -> void:
	_play(wav)
	var t := create_tween()
	t.tween_property(self, "panel_shown", to, _sound_length(wav))
	await t.finished


## Mission load (FUN_004edec0): wait.bmp in the content window, music fades out over 6 s,
## then the TSD.
func _load_mission() -> void:
	busy = true
	loading = true
	tsd_return = screen
	_reset_tsd_checks()
	var fade := create_tween()
	fade.tween_property(music, "volume_db", -60.0, 6.0)
	fade.tween_callback(music.stop)
	for i in 3:
		await get_tree().process_frame
	busy = false
	await _go("tsd")
	loading = false


func _unhandled_input(event: InputEvent) -> void:
	if screen == "pref" and Settings.pref_page == "Controls" and ctrl_focus and msgbox == null \
			and event is InputEventKey and event.pressed and not event.echo:
		_ctrl_key(event)
		return
	if screen == "pref" and Settings.pref_page == "Controls" and ctrl_focus and msgbox == null \
			and event is InputEventJoypadButton and event.pressed and Joystick.ours(event):
		if Joystick.physical_button(event.button_index) >= 0:
			_ctrl_button(Joystick.physical_button(event.button_index))
		return
	if busy or msgbox != null or not (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		return
	if screen in QUIT_SCREENS:
		_quit()
	elif screen == "arm":
		_on_button("back")
	elif not screen in NO_BACK:
		_leave(_back_target())


# --- quit (§3.2) ----------------------------------------------------------------------------

## The credits roll while quitting (game/menu/credits_roll.gd), or null.
var credits: Control
## What ends the game after the credits (tests replace it).
var exit_game := func() -> void: get_tree().quit()


## QUIT (FUN_004ecff0 -> WM_CLOSE -> 4e28b0), Esc on its screens and the window's close button: msg 7
## "Are you sure you want to quit the game?" Yes / No.
func _quit() -> void:
	if msgbox == null:
		_message(7, [["yes", _quit_yes], ["no", Callable()]])


## Yes (0x556, FUN_004e2e00): every sound stops (FUN_00544f00), then the credits roll if the game was
## started without a command line (m_lpCmdLine empty, _DAT_0064d9f4 set at startup; ours: no user
## arguments after --), then the game exits. A key or a mouse button ends the roll.
func _quit_yes() -> void:
	for p in [music, sfx, preview]:
		p.stop()
	if not OS.get_cmdline_user_args().is_empty():
		exit_game.call()
		return
	credits = preload("res://menu/credits_roll.gd").new()
	add_child(credits)
	credits.finished.connect(func(): exit_game.call())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if credits != null or flight != null:
			exit_game.call()
		else:
			_quit()


func _enter_tree() -> void:
	# The window's close button reaches the same OnClose as QUIT (4e28b0) while the menus are up.
	get_tree().auto_accept_quit = flight != null


func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


# --- message box (§3.3) ---------------------------------------------------------------------

## Shows txt/msgs.trx line `msg` with buttons [[art, action]] ("yes", "no", "can", "ok"); a button
## closes the box, then runs its action.
func _message(msg: int, buttons: Array) -> void:
	var arts: Array = buttons.map(func(b): return b[0])
	msgbox = preload("res://mission/mission_box.gd").new()
	add_child(msgbox)
	msgbox.setup(msg, arts)
	msgbox.on_click = _play
	msgbox.chosen.connect(func(art: String):
		var action: Callable = buttons[arts.find(art)][1]
		msgbox.queue_free()
		msgbox = null
		if action.is_valid():
			action.call())
