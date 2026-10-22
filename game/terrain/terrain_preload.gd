# Loads the ground around the player's start while the briefing / TSD / Arming screens are open
# (front_end.gd), so Fly starts almost at once: the flight's terrain adopts what was decoded
# (terrain.gd adopt()). One terrain node that draws nothing, under the scene tree's root (it
# survives the scene change); it keeps only what the flight itself would load there (same quadtree
# and eviction), and is freed when the flight takes it or the player leaves the mission screens.
extends RefCounted

const Terrain := preload("res://terrain/terrain.gd")
const GroundTextures := preload("res://terrain/ground_textures.gd")

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


## Decodes on worker threads what the flight scene's first frame reads (once per mission and flight): the loading
## screen's art, the cockpit art (the scene's default cockpit, which it loads at once, and the player's jet's), the
## player's jet model and its cockpit-view model. What the flight then takes differently is read there as before.
## Its scripts load here: after preload_scene()'s load, they are in the cache.
static var _prefetched := Vector2i(-1, -1)


static func prefetch_flight(id: int, flight := 0) -> void:
	if _prefetched == Vector2i(id, flight):
		return
	_prefetched = Vector2i(id, flight)
	var MissionRuntime: GDScript = load("res://mission/mission_runtime.gd")
	var PlayerAircraft: GDScript = load("res://aircraft/player_aircraft.gd")
	var AircraftModel: GDScript = load("res://aircraft/aircraft_model.gd")
	var Gltf: GDScript = load("res://util/gltf.gd")
	var Cockpit: GDScript = load("res://cockpit/cockpit.gd")
	load("res://terrain/loading_screen.gd").prefetch()
	var default_cockpit: String = Cockpit.DEFAULT_DIR
	Cockpit.prefetch_art(default_cockpit)
	var files: Array = MissionRuntime.mission_files(id) if id >= 0 else []
	var obj := {}
	if not files.is_empty() and not files[0].data.is_empty():
		var e: Dictionary = MissionRuntime.player_flight(files[0].data, flight).get("entity", {})
		obj = MissionRuntime.bdb_objects(MissionRuntime.load_bdb(files[0].data)).get(int(e.get("0x2c6", -1)), {})
	# As terrain_view.gd _choose_player.
	var jet := int(obj.get("0x5b4", PlayerAircraft.FALLBACK))
	if Settings.jet_id >= 0 and PlayerAircraft.jet_type(Settings.jet_id) >= 0:
		jet = PlayerAircraft.jet_type(Settings.jet_id)
	var p: Dictionary = PlayerAircraft.profile(jet)
	if p.cockpit_dir != default_cockpit:
		Cockpit.prefetch_art(p.cockpit_dir)
	var d: Dictionary = AircraftModel.load_descriptor(p.plane)
	if not d.is_empty() and Gltf.detailed(String(d.model)) == "":
		Gltf.parse_file_ahead(AircraftModel._planes_dir(p.plane).path_join(p.plane).path_join(d.model))
	Gltf.parse_ahead(["controllableplanes/%s/%s_bc.gltf" % [p.plane, p.plane]])


## The flight scene: preload_scene()'s (waiting for it if still loading), else loaded here.
static func scene() -> PackedScene:
	if ResourceLoader.load_threaded_get_status(SCENE) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var ps := ResourceLoader.load_threaded_get(SCENE) as PackedScene
		if ps != null:
			return ps
	return load(SCENE)


## The flight's terrain takes over the preloaded textures; the preload ends.
static func hand_over(to: Node3D) -> void:
	_enter_tree()
	if _alive():
		to.adopt(_terrain)
	stop()


static func stop() -> void:
	_enter_tree()
	if _alive():
		_terrain.queue_free()
		_focus.queue_free()
	_terrain = null
	_focus = null
	_target = Vector3(INF, INF, INF)
	_prefetched = Vector2i(-1, -1)  # the next visit prefetches again (the flight takes each prefetch once)


static func _alive() -> bool:
	return _terrain != null and is_instance_valid(_terrain) and not _terrain.is_queued_for_deletion()
