# Loads the ground around the player's start while the briefing / TSD / Arming screens are open
# (front_end.gd), so Fly starts almost at once: the flight's terrain adopts what was decoded
# (terrain.gd adopt()). One terrain node that draws nothing, under the scene tree's root (it
# survives the scene change); it keeps only what the flight itself would load there (same quadtree
# and eviction), and is freed when the flight takes it or the player leaves the mission screens.
extends RefCounted

const Terrain := preload("res://terrain/terrain.gd")
const GroundTextures := preload("res://terrain/ground_textures.gd")

## The preload's decode tasks at once (the flight's terrain runs 4).
const MENU_JOBS := 2

static var _terrain: Node3D = null
static var _focus: Node3D = null
static var _target := Vector3(INF, INF, INF)
## The flight scene, loaded on a loader thread meanwhile (its scripts and resources: ~0.9 s that froze Fly's frame).
const SCENE := "res://terrain/terrain_view.tscn"


## Loads around engine world `world` (X east, Y north, altitude m); a new target re-aims the same
## node (already decoded textures are kept, the old area's are evicted as unused).
static func target(tree: SceneTree, world: Vector3, flight := 0) -> void:
	GroundTextures.preload_async()  # the Ground textures, decoded meanwhile on a worker thread
	preload_scene()
	_flight = flight
	if world == _target and _alive():
		return
	if not _alive():
		_focus = Node3D.new()
		_focus.name = "TerrainPreloadFocus"
		_terrain = Terrain.new()
		_terrain.name = "TerrainPreload"
		_terrain.draw_nodes = false
		# The menus keep their frame rate (docs/rendering.md §1.5): MENU_JOBS decode tasks at once.
		_terrain.max_jobs = MENU_JOBS
		_terrain.focus = _focus
		# Its node lists and meshes on a worker thread; poll() puts it in the tree once they are made.
		_prepare_task = WorkerThreadPool.add_task(_terrain.prepare, true, "terrain prepare")
		_tree = tree
	_target = world
	_terrain.world_origin = Vector2(world.x, world.y)
	_focus.position = Vector3(0, world.z, 0)
	_terrain._last_focus = Vector3(INF, INF, INF)  # re-choose now


static var _prepare_task := -1
static var _tree: SceneTree = null


## Waits for the terrain's prepare() and adds it (and its focus) to the tree.
static func _enter_tree() -> void:
	if _prepare_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_prepare_task)
	_prepare_task = -1
	if _alive():
		_tree.root.add_child(_focus)
		_tree.root.add_child(_terrain)


## Every frame of the mission screens: once the flight scene is loaded (its scripts compiled on the loader thread),
## prefetch_flight() for the chosen flight.
static var _flight := 0


static func poll() -> void:
	if _prepare_task >= 0 and WorkerThreadPool.is_task_completed(_prepare_task):
		_enter_tree()
	if ResourceLoader.load_threaded_get_status(SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
		prefetch_flight(Settings.mission_id, _flight)


## Starts loading the flight scene on a loader thread (once; scene() takes it).
static func preload_scene() -> void:
	if ResourceLoader.load_threaded_get_status(SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(SCENE)


## Decodes on worker threads what the flight scene's first frame reads (once per mission, flight and jet): the loading
## screen's art, the cockpit art (the scene's default cockpit, which it loads at once, and the player's jet's), the
## player's jet model and its cockpit-view model; and parses the mission's unit models (mission_models). What the
## flight then takes differently is read there as before; a new choice drops the parses nobody took.
## Its scripts load here: after preload_scene()'s load, they are in the cache.
static var _prefetched := Vector3i(-1, -1, -1)


static func prefetch_flight(id: int, flight := 0) -> void:
	var key := Vector3i(id, flight, Settings.jet_id)
	if _prefetched == key:
		return
	_prefetched = key
	var MissionRuntime: GDScript = load("res://mission/mission_runtime.gd")
	var PlayerAircraft: GDScript = load("res://aircraft/player_aircraft.gd")
	var aircraft_model := _script("aircraft/aircraft_model")
	var gltf := _script("util/gltf")
	# The flight's OBJECT DETAIL level (terrain_view.gd), so the parses set their materials for it.
	gltf.object_level = gltf.detail_level(float(Settings.object_detail))
	var Cockpit: GDScript = load("res://cockpit/cockpit.gd")
	load("res://terrain/loading_screen.gd").prefetch()
	var default_cockpit: String = Cockpit.DEFAULT_DIR
	Cockpit.prefetch_art(default_cockpit)
	var files: Array = MissionRuntime.mission_files(id) if id >= 0 else []
	var obj := {}
	var models := []
	if not files.is_empty() and not files[0].data.is_empty():
		var e: Dictionary = MissionRuntime.player_flight(files[0].data, flight).get("entity", {})
		var bdb: Dictionary = MissionRuntime.load_bdb(files[0].data)
		obj = MissionRuntime.bdb_objects(bdb).get(int(e.get("0x2c6", -1)), {})
		models = mission_models(files, bdb)
	# As terrain_view.gd _choose_player.
	var jet := int(obj.get("0x5b4", PlayerAircraft.FALLBACK))
	if Settings.jet_id >= 0 and PlayerAircraft.jet_type(Settings.jet_id) >= 0:
		jet = PlayerAircraft.jet_type(Settings.jet_id)
	var p: Dictionary = PlayerAircraft.profile(jet)
	if p.cockpit_dir != default_cockpit:
		Cockpit.prefetch_art(p.cockpit_dir)
	# The player's jet first: the flight's build opens it (the pool runs the tasks in order).
	var d: Dictionary = aircraft_model.load_descriptor(p.plane)
	if not d.is_empty():
		models.push_front(_jet_model(p.plane, d))
	# The cockpit-view model: the install's, else an extra plane's (terrain_view.gd _build).
	var bc: String = gltf.objects_path("controllableplanes/%s/%s_bc.gltf" % [p.plane, p.plane])
	var extra_bc: String = aircraft_model.EXTRA_DIR.path_join(p.plane).path_join(p.plane + "_bc.gltf")
	models.push_front(bc if FileAccess.file_exists(bc) or not FileAccess.file_exists(extra_bc) else extra_bc)
	gltf.drop_ahead(models)  # the last choice's
	gltf.parse_ahead(models)


## The full paths of the models the flight's spawn draws (terrain_view.gd _spawn_mission_objects, ai_flights.gd):
## every placed unit's model with its LOD copies, and the AI's jets. Only those: the flight takes each one, nothing is
## left over (a wider list once held ≈ 340 MB more). Skipped: the unused player slots, the never-drawn classes. A model
## with a detailed stand-in (Models: Detailed) is listed as the stand-in, which parses with its LODs.
static func mission_models(files: Array, bdb: Dictionary) -> Array:
	var mission_runtime := _script("mission/mission_runtime")
	var aircraft_model := _script("aircraft/aircraft_model")
	var ai_flights := _script("ai/ai_flights")
	var gltf := _script("util/gltf")
	if files.is_empty() or bdb.is_empty():
		return []
	var out := {}
	var objs: Dictionary = mission_runtime.bdb_objects(bdb)
	var present := {}
	for pr in bdb.get("present", {}).get("items", []):
		present[int(pr.get("0x1e", -1))] = pr
	var planes: Dictionary = aircraft_model.index()
	var paths: Dictionary = Settings.load_json(Settings.assets_dir().path_join("converted/objects/objects.json")).get(
		String(files[0].data.get("bdb", "")).to_lower(), {}
	)
	for f in files:
		for e in f.data.get("entities", {}).get("items", []):
			var obj: Dictionary = objs.get(int(e.get("0x2c6", -1)), {})
			var path: String = paths.get(str(int(obj.get("0x53c", -1))), "")
			var klass := int(obj.get("0x5aa", -1))
			var unplaced := float(e.get("0x2e4", -1)) < 0 and float(e.get("0x2ee", -1)) < 0
			if path == "" or (unplaced and String(e.get("0x2bc", "")).to_lower().begins_with("player")):
				continue
			var plane := ""
			if klass in [0x1c, 3] and int(e.get("0x320", 0)) & 1 == 0:
				plane = ai_flights._plane_of(
					planes, String(present.get(int(obj.get("0x53c", -1)), {}).get("0x64a", ""))
				)
			if plane != "":
				# A jet the AI flies: its own model (ai_flights.gd setup).
				var d: Dictionary = aircraft_model.load_descriptor(plane)
				if not d.is_empty():
					out[_jet_model(plane, d)] = true
				continue
			if klass in [0x11, 0x12, 0x1b]:
				continue
			if gltf.detailed(path) != "":
				out[gltf.detailed(path)] = true  # Gltf.object's stand-in
				continue
			out[gltf.objects_path(path)] = true
			if path.ends_with("_h.gltf"):
				out[gltf.objects_path(path.trim_suffix("_h.gltf") + "_m.gltf")] = true
				out[gltf.objects_path(path.trim_suffix("_h.gltf") + "_l.gltf")] = true
	return out.keys()


## False while preload_scene()'s load or the first frame's art (prefetch_flight) is still on its threads: Fly waits
## for them over menu frames (polling) rather than in the flight scene's first frame.
static func ready_to_fly() -> bool:
	if ResourceLoader.load_threaded_get_status(SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return false
	poll()
	return not _script("util/img").prefetching()


## The full path of the model AircraftModel.create opens for `plane` (descriptor `d`): its detailed model with Models
## Detailed, else its own.
static func _jet_model(plane: String, d: Dictionary) -> String:
	var hd: String = _script("util/gltf").detailed(String(d.model))
	return hd if hd != "" else _script("aircraft/aircraft_model")._planes_dir(plane).path_join(plane).path_join(d.model)


## The flight scene: preload_scene()'s (waiting for it if still loading), else loaded here.
static func scene() -> PackedScene:
	if ResourceLoader.load_threaded_get_status(SCENE) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var ps := ResourceLoader.load_threaded_get(SCENE) as PackedScene
		if ps != null:
			return ps
	return load(SCENE)


## The flight's terrain takes over the preloaded textures; the preload ends (the models parsed ahead stay for the
## flight, which takes them).
static func hand_over(to: Node3D) -> void:
	_enter_tree()
	if _alive():
		to.adopt(_terrain)
	stop(false)


## Ends the preload: its terrain node goes and, with `drop_models` (the player left the mission screens), the models
## parsed ahead too.
static func stop(drop_models := true) -> void:
	_enter_tree()
	if drop_models and _prefetched.x != -1:
		_script("util/gltf").drop_ahead()
	if _alive():
		_terrain.queue_free()
		_focus.queue_free()
	_terrain = null
	_focus = null
	_target = Vector3(INF, INF, INF)
	_prefetched = Vector3i(-1, -1, -1)  # the next visit prefetches again (the flight takes each prefetch once)


## A game script by its path under res:// (without .gd), loaded on first use: the flight's scripts compile on the
## loader thread first (preload_scene).
static func _script(path: String) -> GDScript:
	return load("res://%s.gd" % path)


static func _alive() -> bool:
	return _terrain != null and is_instance_valid(_terrain) and not _terrain.is_queued_for_deletion()
