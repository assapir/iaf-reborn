# Modern IAF's Settings (autoload, iaf-2026/README.md): the shared settings with the sim's data roots and profile.
# The sim reads its own data only: the readers of the original game's resource layout take converted/own (the same
# layout, compiled by iaf-sim), and the install is a path that does not exist, so a shared reader that still reaches
# for the original's files finds nothing. The 1998-only switches are fixed (PROFILE).
extends "res://shared/settings.gd"

## The switches between the 1998 game and our replacements, fixed to ours (no preferences row in the sim; plan.md
## "physics", "options"). The F-16 switch follows the jet flown (set_jet).
const PROFILE := {
	"cockpit_3d": "3d",
	"models": "detailed",
	"world_scale": "real",
	"flight_data": "real",
	"weapon_data": "real",
	"f15_variant": "raam",
}
## The sim's own planes data (merged over an aircraft definition, airframe_def).
const PLANES := "res://data/planes"

var _sim_airframes := {}
## The plane the pilot picked on the front end: its unit id (f16i, f16d, f35i; settings.cfg [sim] jet); "" before the
## first pick.
var sim_jet := ""
## The debrief record the last flight wrote (flight/sim_flight.gd), for the front end to open when the flight ends.
var flown_debrief := ""


func _ready() -> void:
	super()
	_apply_profile()


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


## A path that does not exist: the sim reads nothing of the original game's install.
func install_dir() -> String:
	return assets_dir().path_join("iaf-2026-reads-no-install")


## The sim's own copy of the original's resource layout (resource/md, resource/soundfiles, resource/weaponsmotion,
## iaf.ibx, terraintype.dat), compiled by `iaf-sim`.
func own_dir() -> String:
	return assets_dir().path_join("converted/own")


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


## The shared definition with the sim's own file (res://data/planes/<id>.json) merged over it, key by key.
func airframe_def(id: String) -> Dictionary:
	var own := load_json(PLANES.path_join(id + ".json"))
	if own.is_empty():
		return super(id)
	if not _sim_airframes.has(id):
		var d: Dictionary = super(id).duplicate(true)
		d.merge(own, true)
		d.make_read_only()
		_sim_airframes[id] = d
	return _sim_airframes[id]


## The sim's part of the flight scene: the radio menu and the training run (flight/sim_flight.gd).
func flight_addon(host: Node) -> Node:
	return load("res://flight/sim_flight.gd").create(host)


## The recorder with the RPM and avionics columns (docs/blackbox.schema.json version 2).
func blackbox_version() -> int:
	return 2


## The engine starts by the Start engine command only (iaf-2026/docs/training.md §7).
func throttle_starts_engine() -> bool:
	return false


## Every base of the own iaf.ibx has a talking tower (iaf-2026/docs/airbases.md §9), in the file's order.
func tower_bases(sections: Dictionary) -> Array:
	return sections.keys().filter(func(k): return k != "")


## The sim's strings are its own: Hebrew needs no pack.
func hebrew_available() -> bool:
	return true


## The original's splash and icon are not the sim's (its own come with the front end, item E2).
func _update_splash() -> void:
	pass


func _set_icon() -> void:
	pass
