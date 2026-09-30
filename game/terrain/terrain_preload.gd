# Loads the ground around the player's start while the briefing / TSD / Arming screens are open
# (front_end.gd), so Fly starts almost at once: the flight's terrain adopts what was decoded
# (terrain.gd adopt()). One terrain node that draws nothing, under the scene tree's root (it
# survives the scene change); it keeps only what the flight itself would load there (same quadtree
# and eviction), and is freed when the flight takes it or the player leaves the mission screens.
extends RefCounted

const Terrain := preload("res://terrain/terrain.gd")

static var _terrain: Node3D = null
static var _focus: Node3D = null
static var _target := Vector3(INF, INF, INF)


## Loads around engine world `world` (X east, Y north, altitude m); a new target re-aims the same
## node (already decoded textures are kept, the old area's are evicted as unused).
static func target(tree: SceneTree, world: Vector3) -> void:
	if world == _target and _alive():
		return
	if not _alive():
		_focus = Node3D.new()
		_focus.name = "TerrainPreloadFocus"
		_terrain = Terrain.new()
		_terrain.name = "TerrainPreload"
		_terrain.draw_nodes = false
		tree.root.add_child(_focus)
		tree.root.add_child(_terrain)
		_terrain.focus = _focus
	_target = world
	_terrain.world_origin = Vector2(world.x, world.y)
	_focus.position = Vector3(0, world.z, 0)
	_terrain._last_focus = Vector3(INF, INF, INF)  # re-choose now


## The flight's terrain takes over the preloaded textures; the preload ends.
static func hand_over(to: Node3D) -> void:
	if _alive():
		to.adopt(_terrain)
	stop()


static func stop() -> void:
	if _alive():
		_terrain.queue_free()
		_focus.queue_free()
	_terrain = null
	_focus = null
	_target = Vector3(INF, INF, INF)


static func _alive() -> bool:
	return _terrain != null and is_instance_valid(_terrain) and not _terrain.is_queued_for_deletion()
