# Scenery (docs/scenery.md §3): the switch only with the scenery files and a Survey 2 m Israel imagery (Settings
# read_config, Graphics → MORE), and the cells loaded and freed around the terrain's focus. The Rust side is a stub
# here (a box per cell, Stub below) unless the extension has IafScenery and setup made assets/converted/scenery
# (SCENERY_REAL=1 uses them).
extends "res://../tests/godot/base.gd"

const TMP := "user://test_scenery"


## IafScenery's static funcs, faked: a 20 m box per cell at its north-west corner, one tree.
class Stub:
	static var loaded := {}
	static var dropped := []
	static var meta := {}

	static func load_cell(_path: String, i: int, j: int) -> bool:
		loaded[Vector2i(i, j)] = true
		return true

	static func drop_cell(i: int, j: int) -> void:
		loaded.erase(Vector2i(i, j))
		dropped.append(Vector2i(i, j))

	static func cell_origin(i: int, j: int) -> Vector3:
		var s := 2048.0 * float(meta.units_to_metres)
		return Vector3(i * s + float(meta.x_shift), float(meta.y_shift) - j * s, 0.0)

	static func mesh_arrays(_i: int, _j: int, _near: bool, _modern: bool) -> Array:
		var box := BoxMesh.new()
		box.size = Vector3(20, 12, 20)
		var a := box.get_mesh_arrays()
		var n: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var uv2 := PackedVector2Array()
		var col := PackedColorArray()
		for k in n:
			uv2.append(Vector2(0, 1.0 if a[Mesh.ARRAY_NORMAL][k].y > 0.5 else 0.0))
			col.append(Color(0.7, 0.4, 0.3, 1.0 / 255.0))
			a[Mesh.ARRAY_TEX_UV][k] *= 20.0
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_COLOR] = col
		return a

	static func trees(_i: int, _j: int) -> Dictionary:
		return {0: PackedFloat32Array([1, 0, 0, 30, 0, 1, 0, 0, 0, 0, 1, 30])}

	static func top(_p: Vector3) -> float:
		return 0.0

	static func damage_index(_i: int, _j: int) -> PackedByteArray:
		return PackedByteArray([0])


func run() -> void:
	var Scenery: GDScript = load("res://terrain/scenery.gd")
	var real: bool = OS.get_environment("SCENERY_REAL") == "1" and Scenery.available()
	var layer := load("res://terrain/imagery_layers.gd").manifest("mapi2015") as Dictionary
	if layer.is_empty():
		print("SKIP test_scenery: no mapi2015 imagery converted")
		return
	if not real:
		Stub.meta = settings().load_json(settings().assets_dir().path_join("converted/terrain/theatre/meta.json"))
		Scenery.backend = Stub
		Scenery.base_dir = ProjectSettings.globalize_path(TMP)
	# A cell with all eight neighbours in the layer, its manifest (stub) listing them.
	var have := {}
	for ij in layer.nodes["1"]:
		have[Vector2i(int(ij[0]), int(ij[1]))] = true
	var c := Vector2i(-1, -1)
	for k in have:
		var all := true
		for d in [Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1)]:
			all = all and have.has(k + d)
		if all:
			c = k
			break
	if not real:
		_write_manifest([])

	# --- the gate: no files -> greyed and off ---
	check(not Scenery.available(), "no manifest: not available")
	_read({"imagery_israel": "mapi2015", "scenery": "on"})
	check(settings().scenery == "off", "read_config: no files -> off")
	var it: Array = await _row("scenery")
	check(it.size() == 2 and not it[1].available and it[1].label == "Not downloaded", "no files: On greyed, Not downloaded")

	if not real:
		var cells := []
		for j in range(c.y - 4, c.y + 5):
			for i in range(c.x - 4, c.x + 5):
				cells.append([i, j])
		_write_manifest(cells)
	check(Scenery.available(), "manifest: available")
	_read({"imagery_israel": "original", "scenery": "on"})
	check(settings().scenery == "off", "read_config: Original imagery -> off")
	_read({"imagery_israel": "mapi2015_modern", "scenery": "on"})
	check(settings().scenery == "on", "read_config: Survey 2 m modern -> stays on")
	_fe.pref_work["imagery_israel"] = "original"
	it = await _row("scenery")
	check(not it[1].available and it[1].label == "Needs Survey 2 m", "Original imagery (unsaved): Needs Survey 2 m")
	_fe.pref_work["imagery_israel"] = "mapi2015"
	it = await _row("scenery")
	check(it[1].available and it[1].label == "On", "Survey 2 m picked (unsaved): On available")
	_click(it[1])
	check(_fe.pref_work.scenery == "on", "a click turns Scenery on")
	var im: Array = await _row("imagery_israel")
	_click(im[0])
	check(_fe.pref_work.imagery_israel == "original" and _fe.pref_work.scenery == "off", "Original imagery: Scenery off")
	_fe.queue_free()

	# --- the cells around the focus ---
	settings().scenery = "on"
	var T: GDScript = load("res://terrain/terrain.gd")
	var t: Node3D = T.new()
	var ids: Array[String] = ["mapi2015"]
	t.set_layers(ids)
	var focus := Node3D.new()
	root.add_child(focus)
	t.focus = focus
	root.add_child(t)
	check(t.scenery != null, "terrain made its scenery")
	var span: float = t._span(1)
	focus.position = t.terrain_to_godot((c.x + 0.5) * span, (c.y + 0.5) * span) + Vector3(0, 500, 0)
	var t0 := Time.get_ticks_msec()
	while not (t.ground_ready() and t.scenery.drawn().has(c)) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	check(t.scenery.drawn().has(c), "the focus' cell is drawn")
	check(t.ground_ready(), "ground_ready with the near scenery")
	var far: Array = t.scenery.loaded().filter(func(k): return t.scenery._dist(k, focus.position) > Scenery.RANGE)
	check(far.is_empty(), "nothing loaded beyond %d m (%s)" % [Scenery.RANGE, far])
	var node: Node3D = t.scenery._cells[c].node
	check(node.get_child_count() >= 2, "near + far meshes and trees (%d nodes)" % node.get_child_count())
	var n0: int = t.scenery.loaded().size()
	# 30 km east: the old cells are freed.
	focus.position += Vector3(30000, 0, 0)
	await frames(10)
	check(not t.scenery.loaded().has(c) and not is_instance_valid(node), "moved 30 km: the old cell freed")
	if not real:
		check(Stub.dropped.has(c), "drop_cell called for it")
	print("cells loaded at the start: %d" % n0)
	t.queue_free()
	focus.queue_free()
	await frames(2)
	if not real:
		check(Stub.loaded.is_empty(), "terrain freed: every cell dropped")
	Scenery.backend = null
	Scenery.base_dir = ""
	settings().scenery = "off"
	settings().imagery_israel = "original"


func _write_manifest(cells: Array) -> void:
	DirAccess.make_dir_recursive_absolute(TMP.path_join("converted/scenery"))
	var p := TMP.path_join("converted/scenery/manifest.json")
	if cells.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"attribution": "test", "cells": cells}))
	f.close()


func _read(prefs: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for k in prefs:
		cfg.set_value("gameplay", k, prefs[k])
	settings().read_config(cfg)


var _fe: Node


## The items of row `key` on Graphics → MORE (the front end made once; as test_ground_textures.gd).
func _row(key: String) -> Array:
	if _fe == null:
		_fe = load("res://menu/front_end.tscn").instantiate()
		root.add_child(_fe)
		await frames(3)
		_fe.screen = "pref"
		_fe._enter_screen()
		await frames(3)
	settings().pref_page = _fe.GFX_MORE
	await frames(2)
	var keys: Array = _fe._extras_rows().map(func(r): return r[0])
	_fe._extras_scroll(mini(keys.find(key), _fe._extras_max_top()))
	await frames(2)
	return _fe._extras_items().filter(func(i): return i.key == key)


func _click(item: Dictionary) -> void:
	var q: Vector2 = _fe._to_screen(_fe.CONTENT.position + item.rect.get_center())
	_fe._gui_input(mouse_button(q, true))
	_fe._gui_input(mouse_button(q, false))
