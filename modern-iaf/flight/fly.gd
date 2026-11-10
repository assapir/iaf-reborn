# Starts a Modern IAF mission: the front end's Fly (menu/front_end.gd), and `./start-modern-iaf -- --mission <id>` with
# the menu id (2011 Ramon start-up, 2012 Ramon take-off, 2021 / 2022 Ramat David, 2031 / 2032 Nevatim; terrain_view.gd
# reads the same argument as the mission id). The mission comes from converted/modern-iaf/missions (iaf-sim missions),
# the jet from its player unit (Settings.set_jet), then the flight scene.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--mission")
	var want := args[at + 1] if at >= 0 and at + 1 < args.size() else "2011"
	start(int(want) if want.is_valid_int() else -1)  # a failure opens the crash page


## Loads mission `id` (its menu id) and changes to the flight scene; false when the compiled missions lack it.
static func start(id: int) -> bool:
	var dir: String = Settings.converted(Settings.missions_folder())
	var list := Settings.load_json(dir.path_join("missionlist.json"))
	if not list.has(str(id)):
		Settings.crash("No Modern IAF mission %d in %s: run ./modern-iaf-setup" % [id, dir])
		return false
	var name := String(list[str(id)][0])
	var m := Settings.load_json(dir.path_join(name + ".json"))
	set_jet(m)
	# The picked plane follows the mission flown (a `--mission` run, Fly again on another jet's debrief).
	var unit := str(Settings.load_json("res://data/missions/%s.json" % name).get("start", {}).get("unit", ""))
	if unit != "" and unit != Settings.sim_jet:
		Settings.sim_jet = unit
		Settings.save()
	Settings.mission_files_override = [{"name": name, "data": m}]
	Settings.mission_id = id
	Settings.flown_sortie = 0
	var tree := Engine.get_main_loop() as SceneTree
	tree.change_scene_to_file.call_deferred("res://shared/terrain/terrain_view.tscn")
	return true


## The F-16 switch from the mission's player unit (its Objects row's "airframe", as the M0 probe).
static func set_jet(m: Dictionary) -> void:
	Settings.set_jet(String(MissionRuntime.player_unit(m).get("airframe", "")))
