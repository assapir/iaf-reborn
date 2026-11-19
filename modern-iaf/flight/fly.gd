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
## mission's own load (own_loadout), else the record's own pylons. A stored load the one load rule blocks on this
## mission (IafBriefing.arming: a laser bomb with no pod, no bombs for a lesson's ground kills; a `--mission` run, the
## front end never flies one) gives way to the mission's own.
static func arm(m: Dictionary, readable: Dictionary) -> void:
	Settings.arm_loadouts = {}
	Settings.gps_targets = {}
	var unit := str(readable.get("start", {}).get("unit", ""))
	var unit_file := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var weapons := ProjectSettings.globalize_path("res://data/db/weapons")
	var mission := ProjectSettings.globalize_path("res://data/missions/%s.json" % str(readable.get("id", "")))
	var lo := IafPilotLog.loadout(Settings.records_db(), Settings.pilot(), unit)
	if lo != "":
		var a = JSON.parse_string(IafBriefing.arming(unit_file, weapons, lo, mission))
		if a is Dictionary and bool(a.get("blocked", false)):
			push_warning("the stored loadout cannot fly this mission (%s): the mission's own flies" % [a.get("unmet")])
			lo = ""
	if lo == "" or bool(readable.get("fixed_loadout", false)):
		lo = own_loadout(readable)
	if lo == "":
		return
	var load = JSON.parse_string(IafBriefing.sim_load(unit_file, weapons, lo))
	var pf: Dictionary = MissionRuntime.player_flight(m, Settings.player_flight)
	if load is Array and not pf.is_empty():
		Settings.arm_loadouts = {int(pf.flight): load}
		Settings.gps_targets = {int(pf.flight): pre_targets(unit_file, weapons, lo, mission)}


## The GPS stores' PRE picks of loadout `lo` (its `pre`, made on the briefing's PRE targets panel or the mission's
## own; A61) that pass the one rule on the readable mission file `mission` (IafBriefing.pre) as the flight's targets
## (Settings.gps_targets' shape, player_weapons.gd pre_targets): {pylon: [x, y, label], Vector2i(pylon, bomb): [x,
## y, label]}. A station without a pick aims at the route's target steerpoint, a bomb without one at its station's.
static func pre_targets(unit_file: String, weapons: String, lo: String, mission: String) -> Dictionary:
	var out := {}
	var d = JSON.parse_string(IafBriefing.pre(unit_file, weapons, lo, mission))
	for r in d.get("rows", []) if d is Dictionary else []:
		var a = r.aim
		if not a is Dictionary or r.pylon == null:
			continue
		var label := "PT"
		if a.kind == "target":
			label = "TGT %d" % int(a.n)
		elif a.kind == "steer":
			label = "STPT %d" % int(a.n)
		var key = int(r.pylon) if int(r.bomb) < 0 else Vector2i(int(r.pylon), int(r.bomb))
		out[key] = [float(a.x), float(a.y), label]
	return out


## The load the readable mission gives its player's jet (its "loadout", station -> store, the shape of a pilot's
## loadout; modern-iaf/docs/data-formats.md §5) as JSON text; "": the unit record's own pylons.
static func own_loadout(readable: Dictionary) -> String:
	var lo = readable.get("loadout")
	return JSON.stringify(lo) if lo is Dictionary and not lo.is_empty() else ""


## The F-16 switch from the mission's player unit (its Objects row's "airframe", as the M0 probe).
static func set_jet(m: Dictionary) -> void:
	Settings.set_jet(String(MissionRuntime.player_unit(m).get("airframe", "")))
