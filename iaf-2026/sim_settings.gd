# Modern IAF's Settings (autoload, iaf-2026/README.md): the shared settings with the sim's data roots and profile.
# The sim reads its own data only: the readers of the original game's resource layout take converted/own (the same
# layout, compiled by iaf-sim), and the install is a path that does not exist, so a shared reader that still reaches
# for the original's files finds nothing. The 1998-only switches are fixed (PROFILE).
extends "res://shared/settings.gd"

## The switches between the 1998 game and our replacements, fixed to ours (no preferences row in the sim; plan.md
## "physics", "options"). The F-16 switch follows the jet flown (set_jet). The cockpit (iaf-2026/docs/cockpit.md): the
## 3D cockpit, the Real HUD and the real MFD formats (the Sufa's in colour by its definition, the Barak's green). No
## textured sky: its cloud layer is the original's art (Clouds Volumetric, ours, stays a choice). The look switches
## whose "original" is the 1998 art the sim does not have are ours too: the airbases (the sim's own runways, taxiways
## and aprons, airbases_file()), the sky, the water, the night lights, the effects (2026-11-08: "original" airbases
## drew no taxiway or apron in the sim). The ground and model textures, the roads and the scenery follow their data
## (_apply_profile). No aids: the original Gameplay page's switches are off (the user, 2026-11-08).
const PROFILE := {
	"airbases": "detailed",
	"sky": "atmospheric",
	"terrain_closeup": true,
	"water": true,
	"night_lights": "detailed",
	"particle_effects": true,
	"rolling_wheels": true,
	"hud_ladder": "conformal",
	"bomb_release": "real",
	"briefing_map": "modern",
	# The weather is the mission's (no Rain row): "off" until a mission brings its own.
	"rain": "off",
	"cockpit_3d": "3d",
	"textured_sky": false,
	"hud_style": "real",
	"real_mfds": "real",
	"models": "detailed",
	"world_scale": "real",
	"flight_data": "real",
	"weapon_data": "real",
	"f15_variant": "raam",
	# Its towns are denser over the whole theatre (iaf-2026/docs/scenery.md §6).
	"scenery_far": "light",
}
## No aids (the user, 2026-11-08): the original's Gameplay page's switches, all off (easy_landing's default is on).
## Applied with PROFILE; never logged (has_setting): the sim has no such switch.
const NO_AIDS := {
	"no_wind": false,
	"no_blackouts": false,
	"no_spins": false,
	"no_stalls": false,
	"easy_landing": false,
	"easy_aiming": false,
	"no_malfunctions": false,
	"invulnerable": false,
	"no_crashes": false,
	"unlimited_ammo": false,
	"unlimited_fuel": false,
}
## The sim's front end script (front_end_overlay, has_setting).
const FRONT_END := "res://menu/front_end.gd"
## The sim's own planes data (under iaf-2026/: merged over an aircraft definition, airframe_def; the cockpit folders).
const PLANES := "data/planes"
## The sim's display and UI font (the user's choice, 2026-11-03): Heebo (SIL OFL 1.1, data/fonts/OFL.txt), a variable
## font (wght 100-900). iaf-2026/docs/cockpit.md §5.
const UI_FONT := "data/fonts/Heebo-VariableFont_wght.ttf"
## The HUD / MFD / PCD face (Approvals A9: a stroke font): Hershey's Roman Simplex as a TTF
## (tools/iaf-2026/hershey_font.py; the notice in data/fonts/HERSHEY.txt). iaf-2026/docs/cockpit.md §5.
const HUD_FONT := "data/fonts/HersheySimplex.ttf"
## The only parts of assets/converted the sim reads (converted()): its compiled data, its terrain, its missions and
## object database, and objects.json (its "sim.bdb" key; iaf-2026/README.md "How the sim reads its data").
## The joystick's axis roles in the order of joy_axes (x, y, throttle, rudder, the rocker; iaf_tools::devices ROLES).
const JOY_ROLES := ["roll", "pitch", "throttle", "rudder", "trim"]
## The known joysticks' default maps (iaf-2026/docs/front-end.md §9.3).
const DEVICE_MAPS := "data/devices"
const OWN_CONVERTED := ["own/", "terrain/israel/", "iaf-2026/", "missions/sim.bdb.json", "objects/objects.json"]

## The original game's paths refused since the start (converted(), install()): the M0 probe fails on any.
var rejected: PackedStringArray = []

## The cockpit dirs' root: under assets/ (relative) or absolute (a test's).
var own_cockpits := "converted/own/cockpits"
var _sim_airframes := {}
var _sim_planes := {}  # _planes()'s
## The plane the pilot picked on the front end: its unit id (f16i, f16d, f35i; settings.cfg [sim] jet); "" before the
## first pick.
var sim_jet := ""
## The sortie the last flight stored (flight/sim_flight.gd), for the front end to open its debrief when the flight
## ends; 0 = none.
var flown_sortie := 0
var _fonts := {}  # display_font's, by style
var _keys: Array = []  # has_setting's
## The player's keys, buttons and axes (devices_file); a test sets its own.
var devices_path := ""
## The laptop key map (front-end.md §9.1: no numpad keys), picked on a platform without a numpad: macOS. A Mac with a
## full keyboard gets it too; its player can put any command on the numpad on the Keys screen. A test sets it.
var laptop_keys := OS.get_name() == "macOS"


func _init() -> void:
	super()
	scenery = "on"  # the sim's default (the DEFAULT button's too)


func _ready() -> void:
	super()
	_apply_profile()
	apply_devices.call_deferred()  # after the Joystick autoload is in the tree
	ThemeDB.get_default_theme().default_font = display_font("ui")  # every Control's text unless it sets its own


func read_config(cfg: ConfigFile) -> void:
	super(cfg)
	sim_jet = str(cfg.get_value("sim", "jet", ""))
	_apply_profile()


func write_config(values := {}) -> ConfigFile:
	var cfg := super(values)
	cfg.set_value("sim", "jet", sim_jet)
	return cfg


## The sim's front end (menu/front_end.gd, iaf-2026/docs/front-end.md): where the game starts and a flight ends.
func front_end_scene() -> String:
	return "res://main.tscn"


## Over the frozen flight: the pause menu (Esc) or the Preferences.
func front_end_overlay() -> Control:
	return load(FRONT_END).new()


## The records' folder: user://, or a temporary folder in isolated runs (tests). The records database is in it and
## the JSON records from before it (debriefs/, pilots/) that its first open imports (storage.md §5).
func records_dir() -> String:
	return OS.get_temp_dir().path_join("modern-iaf-records") if isolated() else "user://"


## The records database (IafPilotLog, storage.md §5), an absolute path.
func records_db() -> String:
	return ProjectSettings.globalize_path(records_dir().path_join("modern-iaf.sqlite"))


## The pilot whose sorties the log holds: Settings.pilot_id, else the default pilot 14.
func pilot() -> int:
	return pilot_id if pilot_id >= 0 else IafPilotLog.default_pilot()


func _apply_profile() -> void:
	for key in PROFILE:
		set(key, PROFILE[key])
	for key in NO_AIDS:
		set(key, NO_AIDS[key])
	# The stores in kg (data-formats.md §3): without it a tank-370's 2470 lb would load as 2470 kg of fuel.
	better["fix_stores_weight"] = true
	# The CC0 textures setup downloads (assets/thirdparty/ambientcg): ours whenever they are there.
	var ground: GDScript = load("res://shared/terrain/ground_textures.gd")
	ground_textures = "ambientcg" if ground.available() else "original"
	model_detail = "ambientcg" if load("res://shared/util/model_detail.gd").available() else "original"
	# The roads: the sim's own once it has them. The scenery is the player's (Preferences → Graphics, On by default,
	# _init), Off without setup's files.
	ground_roads = "detailed" if load("res://shared/terrain/ground_roads.gd").available() else "original"
	if not load("res://shared/terrain/scenery.gd").available():
		scenery = "off"


## The settings the sim has, for the logs: its profile, its Preferences rows (menu/front_end.gd PREFS) and the
## recorder; the rest of the shared settings mean nothing here.
func has_setting(key: String) -> bool:
	if _keys.is_empty():
		_keys = PROFILE.keys() + ["blackbox", "show_info", "ground_textures", "model_detail", "ground_roads"]
		for g in load(FRONT_END).PREFS:
			for row in g[1]:
				_keys.append(row[0])
	return key in _keys


## A path that does not exist: the sim reads nothing of the original game's install.
func install_dir() -> String:
	return assets_dir().path_join("iaf-2026-reads-no-install")


## The gate on the original game's converted data: `rel` under assets/converted when it is the sim's own
## (OWN_CONVERTED), else a path that does not exist, refused (_refuse), so a shared reader that still reaches for the
## original's files fails loudly.
func converted(rel: String) -> String:
	rel = rel.trim_prefix("converted/")
	for own in OWN_CONVERTED:
		if rel.begins_with(own) or rel == own.trim_suffix("/"):
			return super(rel)
	_refuse("converted/" + rel)
	return install_dir().path_join("converted").path_join(rel)


## Only the sim's own data exists for it: false for the rest, without a refusal (a probe, not a read).
func has_converted(rel: String) -> bool:
	rel = rel.trim_prefix("converted/")
	for own in OWN_CONVERTED:
		if rel.begins_with(own) or rel == own.trim_suffix("/"):
			return super(rel)
	return false


## The gate on the original game's install: every read refused (_refuse), the answer a path that does not exist
## (the readers then take their no-file case).
func install(rel: String) -> String:
	_refuse("install/" + rel)
	return install_dir().path_join(rel)


## A refused read: counted in `rejected` (as converted/<rel> or install/<rel>), an error naming the caller the first
## time a path is asked.
func _refuse(what: String) -> void:
	if not what in rejected:
		var stack := get_stack()
		var caller: Dictionary = stack[2] if stack.size() > 2 else {}
		push_error(
			(
				"Modern IAF reads none of the original game's data: %s asked by %s:%s %s()"
				% [what, caller.get("source", "?"), caller.get("line", "?"), caller.get("function", "?")]
			)
		)
	rejected.append(what)


## The sim draws its effects without the original's sprites (Img.soft_dot) until its own art comes.
func original_art() -> bool:
	return false


## The sim's bdb holds each jet's real gun rounds (its unit record's loadout, iaf-2026/docs/weapons.md §1).
func real_bdb() -> bool:
	return true


## Every flight starts with the master arm safe (iaf-2026/docs/weapons.md §3).
func starts_safe() -> bool:
	return true


## The sim's aircraft descriptors (`iaf-sim own`: the F-16's from our model) and its compiled missions.
func planes_folder() -> String:
	return "own/planes"


func missions_folder() -> String:
	return "iaf-2026/missions"


## The original's message table (msgs.trx) is not the sim's: no in-flight message texts until its own table.
func msgs() -> PackedStringArray:
	return PackedStringArray()


## The sim's object database stands in for the original's default6_1.bdb.
func default_bdb() -> String:
	return "sim.bdb"


## The sim's own loading screen (the front end's look, the mission's title and base in the sim's language).
func loading_screen_scene() -> String:
	return _sim_res("flight/loading_screen.gd")


## The sim's own copy of the original's resource layout (resource/md, resource/soundfiles, resource/weaponsmotion,
## iaf.ibx, terraintype.dat), compiled by `iaf-sim`.
func own_dir() -> String:
	return converted("own")


## Modern IAF's theatre: UTM 36N at 1:1 from open data (`iaf-sim terrain`, iaf-2026/docs/terrain.md).
func theatre_dir() -> String:
	return "converted/terrain/israel"


## The scenery and the road layer of the theatre, in its frame, under assets/converted (`iaf-sim scenery`,
## iaf-2026/docs/scenery.md).
func scenery_dir() -> String:
	return "terrain/israel/scenery"


func roads_dir() -> String:
	return "terrain/israel/roads"


## The theatre's ground is its own photo everywhere: the scenery stands on all of it.
func scenery_everywhere() -> bool:
	return true


## The ILS lines glide: the original's whole-pixel steps (1/12°) jump on the 3D cockpit's wide HUD glass (the Mac
## play test's finding 24).
func hud_subpixel() -> bool:
	return true


## The burner rises over 1.5 s with a thump and dies away (the Mac play test's finding 27, iaf-2026/docs/sound.md §1.2).
func ab_sound_real() -> bool:
	return true


func keys_file() -> String:
	var laptop := own_dir().path_join("keys_laptop.json")
	return laptop if laptop_keys and FileAccess.file_exists(laptop) else own_dir().path_join("keys.json")


## The player's device store (iaf_tools::devices, front-end.md §9): user://devices.json; in isolated runs (tests) a
## temporary file of this process, so no run reads another's, or `devices_path` when set.
func devices_file() -> String:
	if devices_path != "":
		return devices_path
	if isolated():
		return OS.get_temp_dir().path_join("iaf2026-devices-%d.json" % OS.get_process_id())
	return ProjectSettings.globalize_path("user://devices.json")


## The connected joystick's device map (DEVICE_MAPS), "" = none.
func devices_map() -> String:
	var js := _joystick()
	if js == null or not ClassDB.class_exists("IafDevices") or js.device() < 0:
		return ""
	return IafDevices.find_map(joy_maps_dir(), Input.get_joy_name(js.device()))


## The key table the flight reads: the sim's own with the device map's buttons and the player's keys and buttons.
func key_table_data(path: String) -> Dictionary:
	if not ClassDB.class_exists("IafDevices"):
		return super(path)
	var d = JSON.parse_string(IafDevices.keys(ProjectSettings.globalize_path(path), devices_file(), devices_map()))
	return d if d is Dictionary else {}


## The sim's own maps (JSON, DEVICE_MAPS): the shared reader finds no .joy there, so it reads no install.
func joy_maps_dir() -> String:
	return _sim_file(DEVICE_MAPS)


func joystick_connected(_name: String) -> void:
	apply_devices()


## The store's axes to the joystick: joy_axes, the invert and dead zone of each (Joystick.tune), the trim rocker on
## while the trim role has an axis; the hat as buttons (Joystick.hat_buttons).
func apply_devices() -> void:
	var js := _joystick()
	if js == null or not ClassDB.class_exists("IafDevices"):
		return
	var a = JSON.parse_string(IafDevices.axes(devices_file(), devices_map(), stick_response == "soft"))
	if not a is Dictionary:
		return
	joy_axes = []
	js.tune = []
	for r in JOY_ROLES:
		joy_axes.append(int(a[r].axis))
		js.tune.append([bool(a[r].invert), float(a[r].dead)])
	rocker_trim = joy_axes[4] >= 0
	js.hat_buttons = true


func save() -> void:
	apply_devices()  # the dead zones follow Stick response
	super()


func _joystick() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Joystick") if tree != null else null


## The flight-model name by type code on the sim's own bd.ibx (IafFlight.fm_type, iaf_flight::fm_name_in: 100 F-16,
## 110 F-15, 1000 F-35I; the F-16 / F-15 switches then pick the Sufa / Ra'am), never the original's converted
## descriptor. A code the own bd.ibx has no section for flies as the F-16 (iaf-2026/docs/flight-model.md §1).
func fm_section(type: int) -> String:
	var t := ""
	if ClassDB.class_exists("IafFlight"):
		t = ClassDB.class_call_static("IafFlight", "fm_type", own_dir(), type, real_data())
	if t == "":
		push_warning("type %d has no section in the sim's bd.ibx (%s): it flies as the F-16" % [type, own_dir()])
		t = "F-16"
	return t


## The sim's bases stand at their real places already (its frame is 1:1, iaf-2026/docs/terrain.md): World scale
## Real's base move is the original game's and never runs here (the extension's moves cleared).
func sync_bases() -> bool:
	if ClassDB.class_exists("IafBases") and IafBases.active():
		IafBases.setup(false, assets_dir(), own_dir())
	return false


## The F-16 switch from the player's jet: the aircraft definition of its Objects row ("airframe",
## iaf-2026/docs/data-formats.md §3). f16i flies as the Sufa, any other as the Barak (f16).
func set_jet(airframe_id: String) -> void:
	f16_variant = "sufa" if airframe_id == "f16i" else "barak"


## The shared definition with the sim's own file (data/planes/<id>.json) merged over it, key by key, and the
## jet's cockpit dir (_planes).
func airframe_def(id: String) -> Dictionary:
	var own := load_json(_sim_file(PLANES).path_join(id + ".json"))
	if own.is_empty() and not _planes().has(id):
		return super(id)
	if not _sim_airframes.has(id):
		var d: Dictionary = super(id).duplicate(true)
		d.merge(own, true)
		if _planes().has(id):
			d.cockpit = own_cockpits.path_join(_planes()[id].unit)
		d.make_read_only()
		_sim_airframes[id] = d
	return _sim_airframes[id]


## The sim's flyable planes by aircraft definition id, read once from their definitions: {id: {unit, family}}. A plane
## is a unit (data/db/units/<unit>.json, its "airframe" the id) with a cockpit folder (data/planes/<unit>/cockpit/),
## which `iaf-sim own` compiles into own_cockpits/<unit>, the jet's cockpit dir (iaf-2026/docs/cockpit.md §4). Its
## family is its aircraft definition's base (shared/extra/planes/<id>/airframe.json "base"), else the id: the name the
## shared cockpit tables key it on (cockpit_folder; the Sufa's and the Barak's "f16").
func _planes() -> Dictionary:
	if _sim_planes.is_empty():
		var units := _sim_file("data/db/units")
		for f in DirAccess.get_files_at(units):
			var u := load_json(units.path_join(f))
			var id := String(u.get("airframe", ""))
			if id != "" and DirAccess.dir_exists_absolute(_sim_file(PLANES).path_join(u.id).path_join("cockpit")):
				var shared := load_json("res://shared/extra/planes".path_join(id).path_join("airframe.json"))
				_sim_planes[id] = {"unit": String(u.id), "family": String(shared.get("base", id))}
	return _sim_planes


## The sim's part of the flight scene: the radio menu and the training run (flight/sim_flight.gd).
func flight_addon(host: Node) -> Node:
	return load(_sim_res("flight/sim_flight.gd")).create(host)


## The recorder with the RPM and avionics columns (docs/blackbox.schema.json version 2).
func blackbox_version() -> int:
	return 2


## The engine starts by the Start engine command only (iaf-2026/docs/training.md §7).
func throttle_starts_engine() -> bool:
	return false


## An ejection ends the sortie (training.md §3.0): the sounds and the radio stop, the view stays outside.
func eject_ends_sortie() -> bool:
	return true


## Every base of the own iaf.ibx has a talking tower (iaf-2026/docs/airbases.md §9), in the file's order.
func tower_bases(sections: Dictionary) -> Array:
	return sections.keys().filter(func(k): return k != "")


## A sim cockpit dir keys the shared cockpit tables by its plane's family (_planes): the Sufa's and the Barak's as the
## F-16's ("f16": its HUD, the real MFD formats, the 3D cockpit).
func cockpit_folder(dir: String) -> String:
	if dir.get_base_dir() == own_cockpits:
		for p in _planes().values():
			if p.unit == dir.get_file():
				return p.family
	return super(dir)


## Every HUD and display raster font is HUD_FONT (hud.gd load_original_font takes it as an outline font).
func hud_font_path(_name: String) -> String:
	return _sim_file(HUD_FONT)


## HUD_FONT on the HUD and the displays, UI_FONT ("ui") on the sim's screens (weight 400): the displays' strokes
## emboldened (as the original's bold system fonts), the HUD's thin.
func display_font(style: String) -> Font:
	if not _fonts.has(style):
		var f := FontFile.new()
		f.load_dynamic_font(_sim_file(UI_FONT if style == "ui" else HUD_FONT))
		var v := FontVariation.new()
		v.base_font = f
		if style == "ui":
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 400}
		elif style != "hud":
			v.variation_embolden = 0.4
		_fonts[style] = v
	return _fonts[style]


## The absolute path of the sim's file `rel` (under iaf-2026/): its folder is res:// in its own project and
## res://../iaf-2026 when a test of the original's project loads this script (which globalize_path and DirAccess do
## not resolve: joined to the project's folder by hand).
func _sim_file(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(_sim_res(rel).trim_prefix("res://")).simplify_path()


## The res:// path of the sim's file `rel`, from either project (as _sim_file).
func _sim_res(rel: String) -> String:
	var s: Script = get_script()
	while s.resource_path == "":  # a test's subclass made at run time
		s = s.get_base_script()
	return s.resource_path.get_base_dir().path_join(rel)


## The sim's cockpit dirs hold its own display data (the original game's Extras copy is in the 1998 frame).
func cockpit_extra(_folder: String, _name: String) -> String:
	return ""


## The sim's strings are its own: Hebrew needs no pack.
func hebrew_available() -> bool:
	return true


## The original's splash and icon are not the sim's (its own come with the front end, item E2).
func _update_splash() -> void:
	pass


func _set_icon() -> void:
	pass
