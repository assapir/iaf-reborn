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


func keys_file() -> String:
	return own_dir().path_join("keys.json")


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
