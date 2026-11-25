# The first start's shader compiles, moved into the front end (docs/rendering.md §1.6 "The first start"): while the
# menus show, the materials a flight draws (shared/util/flight_materials.tres, recorded by
# tests/godot/_flight_materials.gd) are put in the world once, unseen (far below the ground), so Godot compiles their
# shaders and pipelines and keeps them in its caches; the flight's own materials then find them there. The list loads
# on a loader thread (the shader materials' shaders compile there); the pipelines compile on Godot's worker threads.
# Godot makes a built-in material's shader when the material is first used, and the menu frame waits for it: so the
# materials go in one at a time, each only after the menus have drawn a few quick frames, and the load starts once the
# menus have settled (a first start's menus make their own shaders in their first seconds). Freed when the flight's
# loading is done. The front ends call poll() every frame (TerrainPreload.follow). Nothing in the headless runs.
extends RefCounted

## In the .pck: the bundles' export bakes its materials' shaders (docs/release.md "Baked shaders").
const PATH := "res://shared/util/flight_materials.tres"
## Far below the ground: no view ever has them in its frustum.
const HIDE_AT := Vector3(0.0, -100000.0, 0.0)
## A quick menu frame, in seconds; the quick frames in a row before the list's load starts (2 s at 60 Hz: the first
## mission page's own shaders are made by then) and before each material.
const QUICK := 0.05
const SETTLED := 120
const BETWEEN := 3

enum { IDLE, LOADING, DONE }
static var _state := IDLE
static var _node: Node3D = null
static var _pending: Array = []
static var _quick := 0
static var _quad: QuadMesh = null


## Starts the list's load on a loader thread once the menus have settled, then puts its materials in the world when
## it is loaded, one per call after BETWEEN quick frames.
static func poll(tree: SceneTree) -> void:
	_quick = _quick + 1 if tree.root.get_process_delta_time() < QUICK else 0
	if _node != null and not _pending.is_empty() and _quick >= BETWEEN:
		_quick = 0
		_add(_node, _pending.pop_front())
	if _state == IDLE and _quick >= SETTLED:
		_state = DONE
		if DisplayServer.get_name() != "headless" and ResourceLoader.exists(PATH):
			ResourceLoader.load_threaded_request(PATH, "", true)
			_state = LOADING
	if _state != LOADING or ResourceLoader.load_threaded_get_status(PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_state = DONE
	var res: Resource = ResourceLoader.load_threaded_get(PATH)
	if res != null:
		_pending = res.get_meta("materials", []).duplicate()
		_node = _instances([])
		_node.set_meta("materials", _pending.duplicate())  # the sky's and the canvas items' too (they have no node)
		tree.root.add_child(_node)
		print("shader warm-up: %d materials" % _pending.size())


## Waits for the list's load still running (at exit: no loader task left behind, Gltf.finish_ahead says why) and ends
## the warm-up (a flight started before the menus settled has no warm-up after it).
static func finish() -> void:
	if _state == LOADING:
		ResourceLoader.load_threaded_get(PATH)
	_state = DONE
	_pending.clear()


## Frees the warm-up's nodes (the flight's loading is done: the flight's own materials hold the shaders now).
static func stop() -> void:
	finish()
	if _node != null:
		_node.queue_free()
		_node = null


## A node with one tiny quad per spatial material (the shader and its pipelines; casting shadows, as the flight's, so
## their shadow pipelines too) and a stopped particle emitter per process material (the sky's and the canvas items'
## shaders compile as they are made).
static func _instances(materials: Array) -> Node3D:
	var n := Node3D.new()
	n.name = "ShaderWarmUp"
	n.position = HIDE_AT
	for m in materials:
		_add(n, m)
	return n


## Adds the material's quad or emitter to the warm-up's node `n` (none for a sky or canvas item material).
static func _add(n: Node3D, m: Material) -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.001, 0.001)
	var quad := _quad
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
