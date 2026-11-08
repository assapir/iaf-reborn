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
## drew no taxiway or apron in the sim). The ground and model textures follow setup's download (_apply_profile).
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
	"cockpit_3d": "3d",
	"textured_sky": false,
	"hud_style": "real",
	"real_mfds": "real",
	"models": "detailed",
	"world_scale": "real",
	"flight_data": "real",
	"weapon_data": "real",
	"f15_variant": "raam",
}
## The sim's own planes data (merged over an aircraft definition, airframe_def).
const PLANES := "res://data/planes"
## Each flyable jet's cockpit dir (its definition's `cockpit`) under own_cockpits: the displays' data `iaf-sim own`
## compiles, no panel art (iaf-2026/docs/cockpit.md §4). The F-16s' read as the F-16's (cockpit_folder).
const COCKPITS := {"f16": "f16d", "f16i": "f16i", "f35i": "f35i"}
const F16_COCKPITS := ["f16d", "f16i"]
## The sim's display and UI font (the user's choice, 2026-11-03): Heebo (SIL OFL 1.1, data/fonts/OFL.txt), a variable
## font (wght 100-900). iaf-2026/docs/cockpit.md §5.
const UI_FONT := "data/fonts/Heebo-VariableFont_wght.ttf"
## PLACEHOLDER: the HUD / MFD / PCD face, Heebo until the user picks the real-looking one (Approvals A9): change it
## here.
const HUD_FONT := UI_FONT
## The only parts of assets/converted the sim reads (converted()): its compiled data, its terrain, its missions and
## object database, and objects.json (its "sim.bdb" key; iaf-2026/README.md "How the sim reads its data").
const OWN_CONVERTED := ["own/", "terrain/israel/", "iaf-2026/", "missions/sim.bdb.json", "objects/objects.json"]

## The original game's paths refused since the start (converted(), install()): the M0 probe fails on any.
var rejected: PackedStringArray = []

## The cockpit dirs' root: under assets/ (relative) or absolute (a test's).
var own_cockpits := "converted/own/cockpits"
var _sim_airframes := {}
## The plane the pilot picked on the front end: its unit id (f16i, f16d, f35i; settings.cfg [sim] jet); "" before the
## first pick.
var sim_jet := ""
## The debrief record the last flight wrote (flight/sim_flight.gd), for the front end to open when the flight ends.
var flown_debrief := ""
var _fonts := {}  # display_font's, by style


func _ready() -> void:
	super()
	_apply_profile()
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
	return load("res://menu/front_end.gd").new()


## Where the debrief records go: user://debriefs, or a temporary folder in isolated runs (tests).
func debriefs_dir() -> String:
	return OS.get_temp_dir().path_join("iaf2026-debriefs") if isolated() else "user://debriefs"


## The pilot log (training.md §9): the original game's pilot record shape, the default pilot 14.
func pilot_log_file() -> String:
	var dir := debriefs_dir().path_join("pilots") if isolated() else "user://pilots"
	return dir.path_join("%d.json" % (pilot_id if pilot_id >= 0 else 14))


func _apply_profile() -> void:
	for key in PROFILE:
		set(key, PROFILE[key])
	# The CC0 textures setup downloads (assets/thirdparty/ambientcg): ours whenever they are there.
	var ground: GDScript = load("res://shared/terrain/ground_textures.gd")
	ground_textures = "ambientcg" if ground.available() else "original"
	model_detail = "ambientcg" if load("res://shared/util/model_detail.gd").available() else "original"


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


func keys_file() -> String:
	return own_dir().path_join("keys.json")


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


## The shared definition with the sim's own file (res://data/planes/<id>.json) merged over it, key by key, and the
## jet's cockpit dir (COCKPITS).
func airframe_def(id: String) -> Dictionary:
	var own := load_json(PLANES.path_join(id + ".json"))
	if own.is_empty() and not COCKPITS.has(id):
		return super(id)
	if not _sim_airframes.has(id):
		var d: Dictionary = super(id).duplicate(true)
		d.merge(own, true)
		if COCKPITS.has(id):
			d.cockpit = own_cockpits.path_join(COCKPITS[id])
		d.make_read_only()
		_sim_airframes[id] = d
	return _sim_airframes[id]


## The sim's part of the flight scene: the radio menu and the training run (flight/sim_flight.gd).
func flight_addon(host: Node) -> Node:
	return load(_sim_res("flight/sim_flight.gd")).create(host)


## The recorder with the RPM and avionics columns (docs/blackbox.schema.json version 2).
func blackbox_version() -> int:
	return 2


## The engine starts by the Start engine command only (iaf-2026/docs/training.md §7).
func throttle_starts_engine() -> bool:
	return false


## Every base of the own iaf.ibx has a talking tower (iaf-2026/docs/airbases.md §9), in the file's order.
func tower_bases(sections: Dictionary) -> Array:
	return sections.keys().filter(func(k): return k != "")


## The Sufa's and the Barak's cockpit dirs key the shared cockpit tables as the F-16's ("f16": its HUD, the real MFD
## formats, the 3D cockpit).
func cockpit_folder(dir: String) -> String:
	if dir.get_base_dir() == own_cockpits and dir.get_file() in F16_COCKPITS:
		return "f16"
	return super(dir)


## Every HUD and display raster font is HUD_FONT (hud.gd load_original_font takes it as an outline font).
func hud_font_path(_name: String) -> String:
	return _sim_file(HUD_FONT)


## HUD_FONT on the HUD and the displays, UI_FONT ("ui") on the sim's screens: weight 600 on the displays (as the
## original's bold system fonts), 400 on the HUD and the screens.
func display_font(style: String) -> Font:
	if not _fonts.has(style):
		var f := FontFile.new()
		f.load_dynamic_font(_sim_file(UI_FONT if style == "ui" else HUD_FONT))
		var v := FontVariation.new()
		v.base_font = f
		var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
		v.variation_opentype = {wght: 400 if style in ["ui", "hud"] else 600}
		_fonts[style] = v
	return _fonts[style]


## The absolute path of the sim's file `rel` (under iaf-2026/): its folder is res:// in its own project and
## res://../iaf-2026 when a test of the original's project loads this script.
func _sim_file(rel: String) -> String:
	return ProjectSettings.globalize_path(_sim_res(rel))


## The res:// path of the sim's file `rel`, from either project (as _sim_file).
func _sim_res(rel: String) -> String:
	var s: Script = get_script()
	while s.resource_path == "":  # a test's subclass made at run time
		s = s.get_base_script()
	return s.resource_path.get_base_dir().path_join(rel)


## The sim's strings are its own: Hebrew needs no pack.
func hebrew_available() -> bool:
	return true


## The original's splash and icon are not the sim's (its own come with the front end, item E2).
func _update_splash() -> void:
	pass


func _set_icon() -> void:
	pass
