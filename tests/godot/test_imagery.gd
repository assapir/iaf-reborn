# Terrain imagery layers (docs/imagery.md): a layer node replaces the original's texture for that
# node only; every other node keeps the original; the layer list follows the Graphics page choice
# and only converted layers count. Uses a one-node test layer written under
# assets/converted/imagery/ and removed again.
extends "res://../tests/godot/base.gd"

const ID := "_test_layer"
const NODE := Vector3i(25, 73, 3)  # a level-3 node at the head of the Gulf of Suez (outside Israel)
## A level-1 node in it (Survey of Israel layers are written at level 1, 2.5 m per pixel).
const FINE := Vector3i(100, 292, 1)


func run() -> void:
	var Layers = load("res://terrain/imagery_layers.gd")
	var dir: String = Layers.layer_dir(ID)
	DirAccess.make_dir_recursive_absolute(dir.path_join("L3"))
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 0, 1))
	img.save_jpg(dir.path_join("L3/c_%d_%d.jpg" % [NODE.x, NODE.y]))
	DirAccess.make_dir_recursive_absolute(dir.path_join("L1"))
	img.save_jpg(dir.path_join("L1/c_%d_%d.jpg" % [FINE.x, FINE.y]))
	var m := {"name": ID, "region": "outside_israel", "attribution": "test credit",
			"nodes": {"3": [[NODE.x, NODE.y]], "1": [[FINE.x, FINE.y]]}}
	FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(m))

	check(Layers.available("original") and Layers.available(ID) and not Layers.available("no_such_layer"), "available: original always, layers when converted")
	Settings().imagery_outside = "no_such_layer"
	check(Layers.selected().is_empty() and Layers.attributions(["no_such_layer"]).is_empty(), "a picked layer that is not converted is ignored")
	Settings().imagery_outside = ID
	check(Layers.selected() == [ID] and Layers.attributions([ID]) == ["test credit"], "the picked layer and its credit")

	# Terrain with the layer (from the setting) vs without.
	var t: Node3D = load("res://terrain/terrain.gd").new()
	root.add_child(t)
	var plain: Node3D = load("res://terrain/terrain.gd").new()
	plain.set_layers([] as Array[String])
	root.add_child(plain)
	await frames(1)
	var orig_dir: String = t.dir
	check(t.layers == [ID] and t.colour_dir(NODE) == dir, "the layer's node takes its texture from the layer")
	var nb := NODE + Vector3i(1, 0, 0)
	check(t.colour_dir(nb) == orig_dir and t._colour_source(nb) == plain._colour_source(nb), "the neighbour keeps the original")
	check(t._colour_source(NODE) == NODE and plain._colour_source(NODE).z == 6, "the layer adds a level-3 node where the original has only level 6")
	# A level-1 layer node: its level-2 parent splits near the focus (down to the layer's level), the
	# original's does not (it has nothing finer than level 3 there).
	var p2 := Vector3i(FINE.x >> 1, FINE.y >> 1, 2)
	check(t._should_split(p2, 100.0) and not plain._should_split(p2, 100.0), "a level-1 layer node is drawn near the focus")
	check(not t._should_split(FINE, 100.0) and t._colour_source(FINE) == FINE, "the level-1 node is a leaf with its own texture")
	check(t._path(Vector4i(0, NODE.x, NODE.y, 3)).begins_with(dir) and t._path(Vector4i(1, 3, 9, 6)).begins_with(orig_dir), "heights always from the original")
	var decoded: Image = t._decode(Vector4i(0, NODE.x, NODE.y, 3))
	decoded.decompress()
	var c := decoded.get_pixel(32, 32)
	check(c.r > 0.8 and c.g < 0.2 and c.b > 0.8, "the layer's texture is what loads (%s)" % c)
	# The preload's textures are not taken over by a terrain with other imagery.
	plain._res[Vector4i(0, 0, 0, 11)] = {"tex": null, "img": null, "used": 0}
	t.adopt(plain)
	check(not t._res.has(Vector4i(0, 0, 0, 11)), "adopt() skips textures loaded with other imagery")
	t.queue_free()
	plain.queue_free()
	Settings().imagery_outside = "original"
	for f in [dir.path_join("L3/c_%d_%d.jpg" % [NODE.x, NODE.y]), dir.path_join("L1/c_%d_%d.jpg" % [FINE.x, FINE.y]),
			dir.path_join("manifest.json")]:
		DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(dir.path_join("L3"))
	DirAccess.remove_absolute(dir.path_join("L1"))
	DirAccess.remove_absolute(dir)
	await frames(2)
