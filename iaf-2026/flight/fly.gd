# Starts one of IAF 2026's missions without the front end (until item E2): `./iaf2026 -- --mission <id>` with the
# menu id (2011 Ramon start-up, 2012 Ramon take-off, 2021 / 2022 Ramat David, 2031 / 2032 Nevatim; terrain_view.gd
# reads the same argument as the mission id). The mission comes from converted/iaf-2026/missions (iaf-sim missions),
# the jet from its player unit (Settings.set_jet), then the flight scene.
extends Node

const MISSIONS := "converted/iaf-2026/missions"
const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--mission")
	var want := args[at + 1] if at >= 0 and at + 1 < args.size() else "2011"
	var dir := Settings.assets_dir().path_join(MISSIONS)
	var list := Settings.load_json(dir.path_join("missionlist.json"))
	var id := -1
	if list.has(want):
		id = int(want)
	if id < 0:
		push_error("no IAF 2026 mission %s in %s" % [want, dir])
		get_tree().quit(1)
		return
	var name := String(list[str(id)][0])
	var m := Settings.load_json(dir.path_join(name + ".json"))
	set_jet(m)
	Settings.mission_files_override = [{"name": name, "data": m}]
	Settings.mission_id = id
	get_tree().change_scene_to_file.call_deferred("res://shared/terrain/terrain_view.tscn")


## The F-16 switch from the mission's player unit (its Objects row's "airframe", as the M0 probe).
static func set_jet(m: Dictionary) -> void:
	Settings.set_jet(String(MissionRuntime.player_unit(m).get("airframe", "")))
