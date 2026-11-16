# The graded runways (modern-iaf/docs/terrain.md "Graded airbases"), on the built theatre: along every runway of the
# five bases (its centreline and both edges, every 4 m) the height's second difference over a 64 m texel stays within
# a real runway's, and across the width (edge, centre, edge) within a 1.5 % crown's. The heights are the level-6 nodes
# read as the flight reads them (terrain.gd height_at: the texel's two triangles).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_runway_grade.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## FAA AC 150/5300-13B: at least 305 m of vertical curve per 1 % of grade change, 0.134 m over 64 m; plus the
## nodes' 0.1 m height step.
const ALONG_M := 0.24
## A 1.5 % crown each side of the centreline (the most transverse grade, the same circular), per metre of width.
const ACROSS := 0.015
const STEP_M := 64.0

var terrain_gd: GDScript
var meta: Dictionary
var nodes := {}


func run() -> void:
	await require_data()
	var s := settings()
	terrain_gd = load("res://shared/terrain/terrain.gd")
	meta = s.load_json(s.converted(s.theatre_dir()).path_join("meta.json"))
	var abf: String = s.airbases_file()
	if meta.is_empty() or not abf.contains("/israel/"):
		print("NEEDS DATA: the theatre and its airbases.json (./modern-iaf-setup)")
		await _quit(2)
		return
	var n := 0
	for b in s.load_json(abf).get("bases", []):
		for r in b.runways:
			var a := Vector2(r.ends[0][0], r.ends[0][1])
			var u := (Vector2(r.ends[1][0], r.ends[1][1]) - a).normalized()
			var side := Vector2(-u.y, u.x)
			var half := float(r.width) / 2.0
			var along := 0.0
			var across := 0.0
			var m := STEP_M
			while m < float(r.length) - STEP_M:
				var p := a + u * m
				for x in [-half, 0.0, half]:
					var q: Vector2 = p + side * x
					along = maxf(along, absf(_h(q - u * STEP_M) - 2.0 * _h(q) + _h(q + u * STEP_M)))
				across = maxf(across, absf(_h(p - side * half) - 2.0 * _h(p) + _h(p + side * half)) / float(r.width))
				m += 4.0
			check(
				along <= ALONG_M and across <= ACROSS,
				(
					"%s %s: along %.3f m (≤ %.2f), across %.4f per m (≤ %.3f)"
					% [b.name, "/".join(r.designators), along, ALONG_M, across, ACROSS]
				)
			)
			n += 1
	check(n >= 14, "%d runways checked (the five bases have 14)" % n)


## The height (m) at world (east, north) from the level-6 node under it.
func _h(w: Vector2) -> float:
	var span := float(meta.node_pixels) * 64.0
	var t := Vector2(w.x - float(meta.x_shift), float(meta.y_shift) - w.y) / float(meta.units_to_metres)
	var ij := Vector2i(floori(t.x / span), floori(t.y / span))
	if not nodes.has(ij):
		var path: String = settings().converted(settings().theatre_dir()).path_join("L6/h_%d_%d.png" % [ij.x, ij.y])
		nodes[ij] = Image.load_from_file(path)
	var img: Image = nodes[ij]
	var g := (t - Vector2(ij) * span) / 64.0
	var x0 := floori(g.x)
	var y0 := floori(g.y)
	var raw: float = terrain_gd._triangle(
		terrain_gd._raw(img, x0, y0),
		terrain_gd._raw(img, x0 + 1, y0),
		terrain_gd._raw(img, x0, y0 + 1),
		terrain_gd._raw(img, x0 + 1, y0 + 1),
		g.x - x0,
		g.y - y0
	)
	return (raw - float(meta.sea_level_raw)) / float(meta.height_scale) * float(meta.units_to_metres)
