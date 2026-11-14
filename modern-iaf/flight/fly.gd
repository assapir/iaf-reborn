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
	if not prepare(id):
		Settings.crash(
			(
				"No Modern IAF mission %d in %s: run ./modern-iaf-setup"
				% [id, Settings.converted(Settings.missions_folder())]
			)
		)
		return false
	var tree := Engine.get_main_loop() as SceneTree
	tree.change_scene_to_file.call_deferred("res://shared/terrain/terrain_view.tscn")
	return true


## Sets up mission `id` for the flight scene (its files, the jet, the loadout, the mission id); false when the compiled
## missions lack it. The front end's mission page calls it too, for the ground's preload (TerrainPreload).
static func prepare(id: int) -> bool:
	var dir: String = Settings.converted(Settings.missions_folder())
	var list := Settings.load_json(dir.path_join("missionlist.json"))
	if not list.has(str(id)):
		return false
	var name := String(list[str(id)][0])
	var m := Settings.load_json(dir.path_join(name + ".json"))
	set_jet(m)
	# The picked plane follows the mission flown (a `--mission` run, Fly again on another jet's debrief).
	var unit := str(Settings.load_json("res://data/missions/%s.json" % name).get("start", {}).get("unit", ""))
	if unit != "" and unit != Settings.sim_jet:
		Settings.sim_jet = unit
		Settings.save()
	arm(m, Settings.load_json("res://data/missions/%s.json" % name))
	Settings.mission_files_override = [{"name": name, "data": m}]
	Settings.mission_id = id
	Settings.flown_sortie = 0
	return true


## The pilot's loadout for the mission's jet (IafPilotLog.loadout, the briefing's Arming page) on the player's flight
## (`Settings.arm_loadouts`, player_weapons.gd `_armed`: pylons A..I, IafBriefing.sim_load); the gun rounds, chaff and
## flares stay the record's. None stored, or a mission with `fixed_loadout` (its readable file `readable`): the
## record's own pylons.
static func arm(m: Dictionary, readable: Dictionary) -> void:
	Settings.arm_loadouts = {}
	var unit := str(readable.get("start", {}).get("unit", ""))
	var lo := IafPilotLog.loadout(Settings.records_db(), Settings.pilot(), unit)
	if lo == "" or bool(readable.get("fixed_loadout", false)):
		return
	var load = JSON.parse_string(
		IafBriefing.sim_load(
			ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit),
			ProjectSettings.globalize_path("res://data/db/weapons"),
			lo
		)
	)
	var pf: Dictionary = MissionRuntime.player_flight(m, Settings.player_flight)
	if load is Array and not pf.is_empty():
		Settings.arm_loadouts = {int(pf.flight): load}


## The F-16 switch from the mission's player unit (its Objects row's "airframe", as the M0 probe).
static func set_jet(m: Dictionary) -> void:
	Settings.set_jet(String(MissionRuntime.player_unit(m).get("airframe", "")))
