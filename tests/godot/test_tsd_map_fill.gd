# The TSD map's fills (menu/tsd_map.gd, IafEmf.fill_triangles; docs/front-end.md §8): every polygon is filled as GDI
# fills a polypolygon, all its rings as one region under ALTERNATE or WINDING. Samples known points of the 1982, 1967
# and 1973 maps through the fill meshes in drawing order: the Gulf of Suez is sea, the desert east of Jordan is the
# darker sand (the outer-ring-only triangulation drew the first as land and the second as the lighter sand).
# Briefing map on Modern (Settings.cockpit_extra, docs/front-end.md §8 "Modern map"): the front-end TSD and the cockpit
# read the OpenStreetMap map and ground-map picture from converted/extras/cockpit (Tel Aviv Israel's grey, the sea
# navy; the ground-map picture's land shaded by the original's isr.bmp), on Original the 1998 files; MFDs (F-16) on Real
# gives the F-16 the extras' RWR symbols and ADI ball.
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
	await require_data()
	var tsd_map: Script = load("res://menu/tsd_map.gd")  # not preloaded: it names the Settings autoload
	var dir: String = settings().assets_dir().path_join("converted/menu/emf")
	for name in ["82", "67", "73"]:
		var stub := Stub.new()
		var m = tsd_map.new()
		m.tsd = stub
		m.load_maps(settings().load_json(dir.path_join(name + ".json")), {}, {})
		for p in POINTS:
			var c := colour_at(m.map_batches, p)
			check(c.is_equal_approx(POINTS[p]), "%s.emf: %s filled %s (got %s)" % [name, p, POINTS[p], c])
		m.free()
		stub.free()

	# Briefing map: Original reads the 1998 files, Modern the extras' copy.
	var s = settings()
	var extras: String = s.assets_dir().path_join("converted/extras/cockpit")
	check(FileAccess.file_exists(extras.path_join("map.json")), "setup's extras step has run (%s)" % extras)
	var f16: String = s.assets_dir().path_join("converted/cockpits/f16")
	var lay: Dictionary = s.load_json(f16.path_join("cockpit.json"))
	var cockpit: Script = load("res://shared/cockpit/cockpit.gd")
	var keep := [s.briefing_map, s.real_mfds]
	s.briefing_map = "original"
	s.real_mfds = "original"
	for name in ["map.json", "isr.png", "rwrsymb.png", "f16adi.png"]:
		check(cockpit._file_in(f16, lay, name) == f16.path_join(name), "Original: the cockpit's own %s" % name)
	check(s.cockpit_extra("", "tsd.json") == "", "Original: the front-end TSD's own map")
	s.briefing_map = "modern"
	for name in ["map.json", "isr.png"]:
		check(cockpit._file_in(f16, lay, name) == extras.path_join(name), "Modern: the extras' %s" % name)
	check(cockpit._file_in(f16, lay, "rwrsymb.png") == f16.path_join("rwrsymb.png"), "Modern: the own RWR symbols")
	# The ground-map picture keeps the original's terrain (setup's extras step with the install's isr.bmp): a 16 px
	# square of land 30 km east of Tel Aviv holds many brightnesses, the sea 50 km west of it none.
	var isr := Image.load_from_file(extras.path_join("isr.png"))
	var mfd: GDScript = load("res://shared/cockpit/mfd.gd")
	var q: Vector2 = mfd.isr_px(Vector2(344336.0, 544152.0))
	var shades := {}
	for dy in 16:
		for dx in 16:
			shades[isr.get_pixel(int(q.x) + dx - 8, int(q.y) + dy - 8).g8] = true
	var sea := Vector2i(mfd.isr_px(Vector2(264336.0, 544152.0)))
	check(
		shades.size() > 8 and isr.get_pixelv(sea).g8 == 0,
		"Modern: the GM picture's land shaded (%d brightnesses), the sea dark" % shades.size()
	)
	var stub := Stub.new()
	var m = tsd_map.new()
	m.tsd = stub
	var modern: String = s.cockpit_extra("", "tsd.json")
	s.briefing_map = "original"  # the fills alone: Modern's roads read the TSD (tsd.gd), which the stub is not
	m.load_maps(s.load_json(modern), {}, {})
	# Map units of tsd.gd world_to_map: Tel Aviv (34.7818 E, 32.0853 N through the
	# georeference: engine 314336, 544152, as sim_cockpit.rs's test).
	var tel_aviv: Vector2 = load("res://menu/tsd.gd").world_to_map(314336.0, 544152.0)
	check(colour_at(m.map_batches, tel_aviv).is_equal_approx(Color8(200, 199, 199)), "Modern: Tel Aviv is Israel")
	check(colour_at(m.map_batches, Vector2(150, 425)).is_equal_approx(SEA), "Modern: the Gulf of Suez is sea")
	m.free()
	stub.free()
	s.real_mfds = "real"
	check(cockpit._file_in(f16, lay, "rwrsymb.png") == extras.path_join("rwrsymb.png"), "Real MFDs: the RWR symbols")
	check(cockpit._file_in(f16, lay, "f16adi.png") == extras.path_join("adi.png"), "Real MFDs: the ADI ball")
	var mig: String = s.assets_dir().path_join("converted/cockpits/mig29")
	check(cockpit._file_in(mig, {}, "rwrsymb.png") == mig.path_join("rwrsymb.png"), "Real MFDs: other jets keep theirs")
	s.briefing_map = keep[0]
	s.real_mfds = keep[1]
