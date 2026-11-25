# The first start's shader compiles, moved into the front end (docs/rendering.md §1.6 "The first start"): while the
# menus show, the materials a flight draws (shared/extra/flight_materials.tres, recorded by
# tests/godot/_flight_materials.gd) are put in the world once, unseen (far below the ground), so Godot compiles their
# shaders and pipelines and keeps them in its caches; the flight's own materials then find them there. The list loads
# on a loader thread (the shader materials' shaders compile there); the pipelines compile on Godot's worker threads.
# Freed when the flight's loading is done. The front ends call poll() every frame (TerrainPreload.follow). Nothing in
# the headless runs.
extends RefCounted

## In shared/extra, outside the .pck: a bake with this list stopped the macOS bundle (cause open, docs/release.md
## "Baked shaders"); a bundle has the folder beside the game (Settings.readable).
const PATH := "res://shared/extra/flight_materials.tres"
## Far below the ground: no view ever has them in its frustum.
const HIDE_AT := Vector3(0.0, -100000.0, 0.0)

enum { IDLE, LOADING, DONE }
static var _state := IDLE
static var _node: Node3D = null
static var _path := PATH


## Starts the list's load on a loader thread, then puts its materials in the world when it is loaded.
static func poll(tree: SceneTree) -> void:
	if _state == IDLE:
		_state = DONE
		_path = Settings.readable(PATH)
		if DisplayServer.get_name() != "headless" and ResourceLoader.exists(_path):
			ResourceLoader.load_threaded_request(_path, "", true)
			_state = LOADING
	if _state != LOADING or ResourceLoader.load_threaded_get_status(_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_state = DONE
	var res: Resource = ResourceLoader.load_threaded_get(_path)
	if res != null:
		_node = _instances(res.get_meta("materials", []))
		tree.root.add_child(_node)
		print("shader warm-up: %d materials" % _node.get_meta("count"))


## Waits for the list's load still running (at exit: no loader task left behind, Gltf.finish_ahead says why).
static func finish() -> void:
	if _state == LOADING:
		ResourceLoader.load_threaded_get(_path)
		_state = DONE


## Frees the warm-up's nodes (the flight's loading is done: the flight's own materials hold the shaders now).
static func stop() -> void:
	finish()
	if _node != null:
		_node.queue_free()
		_node = null


## A node with one tiny quad per spatial material (the shader and its pipelines; casting shadows, as the flight's, so
## their shadow pipelines too), a stopped particle emitter per process material, and every material kept as metadata
## (the sky's and the canvas items' shaders compile as they are made).
static func _instances(materials: Array) -> Node3D:
	var n := Node3D.new()
	n.name = "ShaderWarmUp"
	n.position = HIDE_AT
	n.set_meta("count", materials.size())
	n.set_meta("materials", materials)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.001, 0.001)
	for m in materials:
		if m is ParticleProcessMaterial:
			var p := GPUParticles3D.new()
			p.process_material = m
			p.emitting = false
			p.draw_pass_1 = quad
			n.add_child(p)
		elif m is BaseMaterial3D or m is ShaderMaterial and m.shader.get_mode() == Shader.MODE_SPATIAL:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = m
			n.add_child(mi)
	return n
