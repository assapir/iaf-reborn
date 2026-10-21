# The TSD map's fills (menu/tsd_map.gd, IafEmf.fill_triangles; docs/front-end.md §8): every polygon is filled as GDI
# fills a polypolygon, all its rings as one region under ALTERNATE or WINDING. Samples known points of the 1982, 1967
# and 1973 maps through the fill meshes in drawing order: the Gulf of Suez is sea, the desert east of Jordan is the
# darker sand (the outer-ring-only triangulation drew the first as land and the second as the lighter sand).
extends "res://../tests/godot/base.gd"

const SEA := Color8(34, 34, 91)
const DESERT := Color8(152, 137, 121)
## Map units (454 x 590) -> the expected fill colour.
const POINTS := {Vector2(150, 425): SEA, Vector2(425, 100): DESERT}


class Stub:
	extends Control
	const MAP_SIZE := Vector2(454, 590)


## The colour of the last fill triangle over `p` (the one drawn on top).
func colour_at(batches: Array, p: Vector2) -> Color:
	var c := Color.BLACK
	for b in batches:
		if not b.has("mesh") or b.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = b.mesh.surface_get_arrays(0)
		var v: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in range(0, v.size(), 3):
			if Geometry2D.point_is_inside_triangle(p, v[i], v[i + 1], v[i + 2]):
				c = col[i]
	return c


func run() -> void:
	var dir: String = settings().assets_dir().path_join("converted/menu/emf")
	for name in ["82", "67", "73"]:
		var stub := Stub.new()
		var m = load("res://menu/tsd_map.gd").new()
		m.tsd = stub
		m.load_maps(settings().load_json(dir.path_join(name + ".json")), {}, {})
		for p in POINTS:
			var c := colour_at(m.map_batches, p)
			check(c.is_equal_approx(POINTS[p]), "%s.emf: %s filled %s (got %s)" % [name, p, POINTS[p], c])
		m.free()
		stub.free()
