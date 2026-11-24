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
	var unit_file := Settings.disk_path("res://data/db/units/%s.json" % unit)
	var weapons := Settings.disk_path("res://data/db/weapons")
	var mission := Settings.disk_path("res://data/missions/%s.json" % str(readable.get("id", "")))
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


## Scramble (front-end.md §2.1): sets up the jet's Scramble start, mission `id` (category fly_now: a flight of four
## parked cold at the jet's base), with the picks `fc` (FreeCombatPage.picks and fly_free's area: flight 1, 2 or 4,
## home, area, start): the flight cut to its first `flight` jets; for start "air" put in the air round the area
## (IafFreeCombat air_start: each jet's place, its route one point over the area), for "runway" lined up in pairs on
## the home base's runway with the engines running (IafFreeCombat runway_start, the start rule's 100 m of the lineup
## point); false as prepare. The enemy comes in flight (free_combat.gd).
static func prepare_free(id: int, fc: Dictionary) -> bool:
	if not prepare(id):
		return false
	var count := int(fc.get("flight", 2))
	var m: Dictionary = Settings.mission_files_override[0].data
	var members: Array = m.formations.items[0].members
	var gone: Array = members.slice(count).map(func(x): return int(x["0x41a"])).filter(func(x): return x >= 0)
	for k in gone:  # the jet out of the formation and the mission (mission_edit.rs remove_entity)
		m = JSON.parse_string(IafMissionEdit.remove_entity(JSON.stringify(m), k))
	count = mini(count, members.size())
	m.sim.flights[0].count = count
	var start := String(fc.get("start", "air"))
	if start in ["air", "runway"]:
		m = _free_start(m, start, String(fc.get("home", "")), String(fc.get("area", "")), count)
	Settings.mission_files_override = [{"name": Settings.mission_files_override[0].name, "data": m}]
	return true


## The fight's base for a Scramble from base `home` (iaf.ibx sections): IafFreeCombat.area's draw from `seed` among
## the theatre's bases within reach; "" for none.
static func free_area(home: String, seed: int) -> String:
	var ibx := _ibx()
	if not ibx.has(home):
		return ""
	var names: Array = ibx.keys().filter(func(b): return ibx[b].has("LineupLocX"))
	var i: int = IafFreeCombat.area(
		seed, _lineup(ibx, home), PackedVector3Array(names.map(func(b): return _lineup(ibx, b)))
	)
	return String(names[i]) if i >= 0 else ""


## Mission `m` with its flight 1 (`count` jets) at the Scramble's `start` from base `home` (iaf.ibx sections): "air"
## round base `area` (IafFreeCombat.air_start: airborne above 800 m away from a base, the start rule; its route one
## point over the area at the start's height), "runway" on `home`'s lineup point facing down its runway
## (IafFreeCombat.runway_start), through IafMissionEdit.set_flight. `m` as it was for an unknown base.
static func _free_start(m: Dictionary, start: String, home: String, area: String, count: int) -> Dictionary:
	var ibx := _ibx()
	if not ibx.has(home) or (start == "air" and not ibx.has(area)):
		push_warning("scramble: no %s start (%s -> %s)" % [start, home, area])
		return m
	var at: Array
	var points := []
	if start == "runway":
		at = IafFreeCombat.runway_start(_lineup(ibx, home), float(ibx[home].get("RunwayNumber", "0")), count)
	else:
		var bases := PackedVector3Array(
			ibx.keys().filter(func(b): return ibx[b].has("LineupLocX")).map(func(b): return _lineup(ibx, b))
		)
		var a := _lineup(ibx, area)
		at = IafFreeCombat.air_start(_lineup(ibx, home), a, bases, count)
		if not at.is_empty():
			var p: Vector3 = at[0].pos
			points = [[a.x, a.y, p.z, a.distance_to(Vector3(p.x, p.y, a.z)) / 250.0]]
	if at.is_empty():
		return m
	var lead: Dictionary = at[0]
	var spec := {
		"type": int(MissionRuntime.player_flight(m, 1).get("entity", {}).get("0x2c6", 0)),
		"count": count,
		"slot_x": lead.pos.x,
		"slot_y": lead.pos.y,
		"alt": lead.pos.z,
		"heading": lead.heading,
		"wings": at.slice(1).map(func(w): return [w.pos.x, w.pos.y, w.heading]),
	}
	if not points.is_empty():
		spec.points = points
	return JSON.parse_string(IafMissionEdit.set_flight(JSON.stringify(m), 1, JSON.stringify(spec)))


static func _ibx() -> Dictionary:
	return Settings.load_ibx(Settings.own_dir().path_join("iaf.ibx"))


## Base `section`'s lineup point (world, on the ground) in `ibx`.
static func _lineup(ibx: Dictionary, section: String) -> Vector3:
	var b: Dictionary = ibx.get(section, {})
	return Vector3(float(b.get("LineupLocX", 0)), float(b.get("LineupLocY", 0)), float(b.get("LineupLocZ", 0)))
