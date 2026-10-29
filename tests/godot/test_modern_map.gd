# The modern briefing map (ours, Extras "Briefing map" = Modern; menu/tsd_map.gd modern_text): each city's dot lands
# on the real city and its label moves with it; the 1998 text.emf stays as it was.
extends "res://../tests/godot/base.gd"

var tsd: Script


## A label op's map position (map units), found by its first op's text.
func label_at(text: Dictionary, first: String) -> Vector2:
	for op in text.ops:
		if op.t == "text" and op.text == first:
			return Vector2(op.pos[0], op.pos[1]) * tsd.MAP_SIZE
	return Vector2(-1, -1)


func run() -> void:
	# Loaded at run time: the scripts name the autoloads, which a -s script's preloads cannot see.
	var tsd_map: Script = load("res://menu/tsd_map.gd")
	tsd = load("res://menu/tsd.gd")
	var text: Dictionary = settings().load_json("res://../assets/converted/menu/emf/text.json")
	var before := JSON.stringify(text)
	var modern: Dictionary = tsd_map.modern_text(text)
	check(JSON.stringify(text) == before, "the original map data is untouched")
	var moved := 0
	for city in IafEmf.modern_cities():
		var real: Vector2 = tsd.world_to_map(city.pos.x, city.pos.y)
		var near := INF
		for op in modern.ops:
			var c: Vector2 = tsd_map._dot_centre(op, tsd.MAP_SIZE)
			if c.x >= 0.0:
				near = minf(near, (c * tsd.MAP_SIZE).distance_to(real))
		check(near < 0.5, "%s: a dot on the real city (%.2f map units off)" % [city.label, near])
	for pair in [["TEL-AVIV", 3.0], ["AMMAN", 3.0], ["D", 3.0], ["C", 3.0]]:
		var step := label_at(modern, pair[0]) - label_at(text, pair[0])
		if step.length() > pair[1]:
			moved += 1
		print("  %s label moved %.1f map units" % [pair[0], step.length()])
	check(moved == 4, "Tel Aviv, Amman, Damascus and Cairo labels moved with their dots")
	var j := label_at(modern, "JERUSALEM") - label_at(text, "JERUSALEM")
	check(j.length() < 3.0, "Jerusalem, already close, moves a little (%.1f)" % j.length())
	# The road layer (docs/scenery.md §6), when setup made it: the map's main roads and a route Tel Aviv – Jerusalem.
	if not IafRoads.open(settings().assets_dir().path_join("converted/roads")):
		print("  no road layer (setup's scenery step): roads skipped")
		return
	check(IafRoads.segments(0, 1).size() > 1000, "motorway and trunk segments for the map")
	var ta := Vector2(314164, 543565)  # Tel Aviv, Jerusalem: the georeference of 32.08 N 34.78 E, 31.77 N 35.21 E
	var jm := Vector2(354769, 509121)
	var r := IafRoads.route(ta, jm, 1)
	var km := 0.0
	for i in range(1, r.size()):
		km += r[i].distance_to(r[i - 1]) / 1000.0
	check(km > 55.0 and km < 110.0, "a motorway / trunk route Tel Aviv – Jerusalem (%.0f km)" % km)
	check(IafRoads.nearest(ta, 7).get("distance", INF) < 300.0, "a street near Tel Aviv's centre")
	var near: Array = IafRoads.roads_in_rect(ta - Vector2(500, 500), ta + Vector2(500, 500), 7)
	check(near.size() > 10 and near[0].has("lit"), "the blocks' streets around Tel Aviv (%d)" % near.size())
