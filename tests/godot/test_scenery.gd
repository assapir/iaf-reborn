# Scenery (docs/scenery.md §3): the switch only with the scenery files and a Survey 2 m Israel imagery (Settings
# read_config, Graphics → MORE), and the cells loaded and freed around the terrain's focus. The cells are our own test
# files (a 20 m house and a tree in the 3 × 3 cells around one of the layer's level-1 nodes), read by IafScenery.
extends "res://../tests/godot/base.gd"

const TMP := "user://test_scenery"


func run() -> void:
	var Scenery: GDScript = load("res://terrain/scenery.gd")
	var layer := load("res://terrain/imagery_layers.gd").manifest("mapi2015") as Dictionary
	if layer.is_empty():
		print("SKIP test_scenery: no mapi2015 imagery converted")
		return
	Scenery.base_dir = ProjectSettings.globalize_path(TMP)
	var meta: Dictionary = settings().load_json(
		settings().assets_dir().path_join("converted/terrain/theatre/meta.json")
	)
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
	_write_manifest([])

	# --- the gate: no files -> greyed and off ---
	check(not Scenery.available(), "no manifest: not available")
	_read({"imagery_israel": "mapi2015", "scenery": "on"})
	check(settings().scenery == "off", "read_config: no files -> off")
	var it: Array = await _row("scenery")
	check(
		it.size() == 2 and not it[1].available and it[1].label == "Not downloaded",
		"no files: On greyed, Not downloaded"
	)

	var cells := []
	for j in range(c.y - 4, c.y + 5):
		for i in range(c.x - 4, c.x + 5):
			cells.append("%d_%d" % [i, j])
			if absi(i - c.x) <= 1 and absi(j - c.y) <= 1:
				_write_cell(meta, Vector2i(i, j))
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
	check(
		_fe.pref_work.imagery_israel == "original" and _fe.pref_work.scenery == "off", "Original imagery: Scenery off"
	)
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
	var house := _house(meta, c)
	check(IafScenery.top(house) > 10.0, "IafScenery has the house (top %.1f m)" % IafScenery.top(house))
	var n0: int = t.scenery.loaded().size()
	# 30 km east: the old cells are freed.
	focus.position += Vector3(30000, 0, 0)
	await frames(10)
	check(not t.scenery.loaded().has(c) and not is_instance_valid(node), "moved 30 km: the old cell freed")
	check(IafScenery.top(house) == 0.0, "drop_cell: IafScenery forgot it")
	print("cells loaded at the start: %d" % n0)
	t.queue_free()
	focus.queue_free()
	await frames(2)
	Scenery.base_dir = ""
	settings().scenery = "off"
	settings().imagery_israel = "original"


## The north-west corner of cell `k` (world X east, Y north; IafScenery.cell_origin).
func _corner(meta: Dictionary, k: Vector2i) -> Vector2:
	var s := 2048.0 * float(meta.units_to_metres)
	return Vector2(k.x * s + float(meta.x_shift), float(meta.y_shift) - k.y * s)


## The house's centre, world frame, at 1000 m (top() reads the height above the ground there).
func _house(meta: Dictionary, k: Vector2i) -> Vector3:
	var o := _corner(meta, k)
	return Vector3(o.x + 110.0, o.y - 110.0, 1000.0)


## A cell file (crates/iaf-avionics/src/scenery.rs): one 20 m square house, 12 m high, plaster, and one pine.
func _write_cell(meta: Dictionary, k: Vector2i) -> void:
	var o := _corner(meta, k)
	DirAccess.make_dir_recursive_absolute(TMP.path_join("converted/scenery/L1"))
	var f := FileAccess.open(TMP.path_join("converted/scenery/L1/s_%d_%d.bin" % [k.x, k.y]), FileAccess.WRITE)
	f.store_buffer("IAFS".to_ascii_buffer())
	for v in [1, 1, 1]:  # version, buildings, trees
		f.store_32(v)
	f.store_16(4)
	f.store_buffer(PackedByteArray([0, 0]))  # flat roof, plaster
	f.store_float(12.0)
	f.store_buffer(PackedByteArray([180, 90, 70, 170, 100, 80, 0, 4]))  # roof 1998, modern, OSM, 4 levels
	for p in [Vector2(100, -120), Vector2(120, -120), Vector2(120, -100), Vector2(100, -100)]:
		f.store_float(o.x + p.x)
		f.store_float(o.y + p.y)
	for v in [o.x + 200.0, o.y - 200.0, 9.0]:
		f.store_float(v)
	f.store_buffer(PackedByteArray([0, 0, 0, 0]))
	f.close()


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
