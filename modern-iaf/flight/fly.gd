# Starts a Modern IAF mission: the front end's Fly (menu/front_end.gd), and `./start-modern-iaf -- --mission <id>` with
# the menu id (2011 Ramon start-up, 2012 Ramon take-off, 2021 / 2022 Ramat David, 2031 / 2032 Nevatim; terrain_view.gd
# reads the same argument as the mission id). The mission comes from converted/modern-iaf/missions (iaf-sim missions),
# flown in the Hangar's jet (for_jet; a `--mission` run: the mission's own), then the flight scene.
extends Node

const MissionRuntime := preload("res://shared/mission/mission_runtime.gd")
## The parts of a training mission that belong to its jet (for_jet).
const LESSON := ["training", "briefing", "win", "lose", "fixed_loadout"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--mission")
	var want := args[at + 1] if at >= 0 and at + 1 < args.size() else "2011"
	start(int(want) if want.is_valid_int() else -1)  # a failure opens the crash page


## Loads mission `id` (its menu id), flown in jet `unit` ("" the mission's own: for_jet), and changes to the flight
## scene; false when the compiled missions lack it.
static func start(id: int, unit := "") -> bool:
	if not prepare(id, unit):
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


## Sets up mission `id` for the flight scene, flown in jet `unit` ("" the mission's own): its files, the jet, the
## loadout, the mission id; false when the compiled missions lack it. The front end's mission page calls it too, for
## the ground's preload (TerrainPreload). Another jet than the mission's takes the player's slot (the Player1 entity's
## unit, at the mission's own spot) and the mission's readable data for that jet (for_jet) rides along in the compiled
## data as `readable` (sim_flight.gd reads it there).
static func prepare(id: int, unit := "") -> bool:
	var dir: String = Settings.converted(Settings.missions_folder())
	var list := Settings.load_json(dir.path_join("missionlist.json"))
	if not list.has(str(id)):
		return false
	var name := String(list[str(id)][0])
	var m := Settings.load_json(dir.path_join(name + ".json"))
	var own := Settings.load_json("res://data/missions/%s.json" % name)
	var readable := for_jet(own, unit)
	if str(readable.get("start", {}).get("unit")) != str(own.get("start", {}).get("unit")):
		var number = Settings.load_json("res://data/db/units/%s.json" % unit).get("number")
		var player: Dictionary = MissionRuntime.player_flight(m, 1).get("entity", {})
		if number == null or player.is_empty():
			return false
		player["0x2c6"] = int(number)  # player_flight hands out the entity itself
		m["readable"] = readable
	set_jet(m)
	# The picked plane follows the jet flown (a `--mission` run flies the mission's own).
	unit = str(readable.get("start", {}).get("unit", ""))
	if unit != "" and unit != Settings.sim_jet:
		Settings.sim_jet = unit
		Settings.save()
	arm(m, readable)
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


## Missions are shared by the jets (front-end.md §2): readable mission `m` flown in jet `unit` ("" or its own: `m`
## itself). Its place stays (base, start spot, runway, route, time, wind, its id for the records); the start's unit
## becomes `unit` and a training mission takes its lesson, which is the jet's own (the start-up's checklist, the
## take-off's weights and speeds, the briefing's and the result's texts: LESSON), from that jet's own mission of the
## same kind (the one whose start is that jet; a jet without one keeps the mission's lesson). `all`: the readable
## missions to look in (default: data/missions). An empty `m` (a record's mission file gone) comes back as it is.
static func for_jet(m: Dictionary, unit: String, all: Array = []) -> Dictionary:
	if m.is_empty() or unit == "" or str(m.get("start", {}).get("unit", "")) == unit:
		return m
	var out := m.duplicate(true)
	out.start.unit = unit
	var kind = m.get("training", {}).get("kind")
	if kind == null:
		return out
	if all.is_empty():
		all = readable_missions()
	for o in all:
		if str(o.get("start", {}).get("unit", "")) == unit and o.get("training", {}).get("kind") == kind:
			for k in LESSON:
				if o.has(k):
					out[k] = o[k].duplicate(true) if o[k] is Dictionary or o[k] is Array else o[k]
			break
	return out


## Every readable mission (res://data/missions), by file name order.
static func readable_missions() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://data/missions"):
		if f.get_extension() == "json":
			out.append(Settings.load_json("res://data/missions/" + f))
	return out


## The F-16 switch from the mission's player unit (its Objects row's "airframe", as the M0 probe).
static func set_jet(m: Dictionary) -> void:
	Settings.set_jet(String(MissionRuntime.player_unit(m).get("airframe", "")))
