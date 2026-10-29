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
