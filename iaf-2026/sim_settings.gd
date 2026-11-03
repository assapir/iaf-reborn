# IAF 2026's Settings (autoload, iaf-2026/docs/README.md): the shared settings with the sim's data roots and profile.
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
var _said_no_bases := false


func _ready() -> void:
	super()
	_apply_profile()


func read_config(cfg: ConfigFile) -> void:
	super(cfg)
	_apply_profile()


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


## IAF 2026's theatre: UTM 36N at 1:1 from open data (`iaf-sim terrain`, iaf-2026/docs/terrain.md).
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


## World scale Real's base moves read the own iaf.ibx, which item B2b compiles: until it exists the sim flies with no
## base moved, said once in the log (the shared warning stays for data missing from a layout that has an iaf.ibx).
func sync_bases() -> bool:
	if FileAccess.file_exists(own_dir().path_join("iaf.ibx")):
		return super()
	if not _said_no_bases:
		_said_no_bases = true
		print("no own iaf.ibx yet (%s, item B2b): no base moves" % own_dir())
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


## The sim's strings are its own: Hebrew needs no pack.
func hebrew_available() -> bool:
	return true


## The original's splash and icon are not the sim's (its own come with the front end, item E2).
func _update_splash() -> void:
	pass


func _set_icon() -> void:
	pass
