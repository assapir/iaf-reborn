# The debrief's graphs of a flight (modern-iaf/docs/front-end.md §13): the phase band over three graphs, speed (kt),
# height above the ground (ft) and load (g), against the mission clock, each with its marked events (IafTraining.track:
# its `marks`, a dot and "lift-off 172"). The clock runs left to right in both languages, as numbers and clock times
# read in Hebrew too (the approved Hebrew mock, r3_debrief_he); the titles and the names are the game's language.
extends Control

const Look := preload("look.gd")
## The room for the value axis at the left, the band's height, the clock axis's room at the bottom, a title's room
## (px).
const AXIS_W := 58.0
const BAND_H := 20.0
const CLOCK_H := 26.0
const TITLE_H := 24.0
## The clock's tick steps to pick from (s): the shortest giving at most 8 ticks.
const STEPS := [30, 60, 120, 300, 600, 900, 1800, 3600]

## IafTraining.track's JSON; the phases' colours; the phases' and the marks' names (its `strings` in the game's
## language); the graphs' titles (speed, height, load); the mission clock at t s from the start, with the seconds
## (Callable(float, bool) -> String).
var flight := {}
var colors: Array = []
var names := {}
var titles: Array = ["", "", ""]
var clock := Callable()


func _ready() -> void:
	resized.connect(queue_redraw)


## The time span of the track (s).
func _span() -> float:
	var t: Array = flight.get("t", [])
	return maxf(float(t[-1]) if not t.is_empty() else 0.0, 1.0)


## The x of time `t` (s).
func _x(t: float) -> float:
	return AXIS_W + t / _span() * (size.x - AXIS_W - 12.0)


## A round top for the value axis at or above `v`: 1, 1.5, 2, 3, 4, 5, 6 or 8 times a power of ten.
static func nice(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var p := pow(10.0, floorf(log(v) / log(10.0)))
	for m in [1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]:
		if m * p >= v:
			return m * p
	return 10.0 * p


func _draw() -> void:
	var t: Array = flight.get("t", [])
	if t.size() < 2:
		return
	var font := get_theme_font("font", "Label")
	# The phase band.
	for r in flight.get("runs", []):
		var x0 := _x(float(r.from))
		var x1 := _x(float(r.to))
		var p := int(r.phase)
		draw_rect(Rect2(x0, 0, maxf(x1 - x0, 1.0), BAND_H), colors[p] if p < colors.size() else Look.MUTED)
		var nm := str(names.get("ph_" + str(flight.phases[p]), ""))
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if w + 8.0 < x1 - x0:
			draw_string(font, Vector2(x0 + 4, 15), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Look.NAVY)
	var g: Array = flight.get("g", [])
	var series := [
		["speed", flight.get("speed_kt", []), Color.WHITE], ["agl", flight.get("agl_ft", []), Color("7fd18b")]
	]
	if not g.is_empty():
		series.append(["g", g, Color("ffc04d")])
	var top := BAND_H + 6.0
	var h := (size.y - top - CLOCK_H) / series.size()
	for i in series.size():
		_graph(
			font,
			series[i],
			str(titles[i]),
			Rect2(AXIS_W, top + i * h + TITLE_H, size.x - AXIS_W - 12.0, h - TITLE_H - 8)
		)
	# The events of no one graph (a touchdown, a crash, a hit, an ejection): a line across the graphs, named at its top.
	for m in flight.get("marks", []):
		if str(m.graph) == "":
			var x := _x(float(m.t))
			draw_dashed_line(Vector2(x, top), Vector2(x, size.y - CLOCK_H), Look.ACCENT, 1.5, 5.0)
			var lbl := str(names.get("ev_" + str(m.id), m.id))
			var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(
				font, Vector2(minf(x + 4, size.x - w - 4), top + 14), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Look.TEXT
			)
	# The clock axis.
	var span := _span()
	var step: int = STEPS[-1]
	for s in STEPS:
		if span / s <= 8.0:
			step = s
			break
	var y := size.y - CLOCK_H
	draw_line(Vector2(AXIS_W, y), Vector2(size.x - 12.0, y), Look.LINE, 1.0)
	for k in int(span / step) + 1:
		var x := _x(k * step)
		var lbl: String = clock.call(float(k * step), step < 60) if clock.is_valid() else str(k * step)
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_line(Vector2(x, y), Vector2(x, y + 4), Look.LINE, 1.0)
		draw_string(font, Vector2(x - w / 2.0, y + 20), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Look.MUTED)


## One graph in `r`: its title above, the value axis's 0, middle and top, the line and its marks.
func _graph(font: Font, ser: Array, title: String, r: Rect2) -> void:
	var t: Array = flight.t
	var v: Array = ser[1]
	var lo := 0.0  # every value axis starts at 0 (a load below 0 g clamps to it)
	var hi := 0.0
	for x in v:
		hi = maxf(hi, float(x))
	hi = nice(hi)
	if ser[0] == "g":
		hi = maxf(nice(hi), 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y - 6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Look.TEXT)
	for k in 3:
		var val := lo + (hi - lo) * k / 2.0
		var y := r.end.y - r.size.y * k / 2.0
		draw_dashed_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(Look.LINE, 0.6), 1.0, 4.0)
		var lbl := Look.group(val) if ser[0] != "g" else str(snappedf(val, 0.1))
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(r.position.x - w - 8, y + 5), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Look.MUTED)
	var at := func(i: int) -> Vector2:
		return Vector2(_x(float(t[i])), r.end.y - clampf((float(v[i]) - lo) / (hi - lo), 0.0, 1.0) * r.size.y)
	var pts := PackedVector2Array()
	for i in mini(t.size(), v.size()):
		pts.append(at.call(i))
	draw_polyline(pts, ser[2], 2.0, true)
	var placed: Array[Rect2] = []
	for m in flight.get("marks", []):
		if m.graph != ser[0]:
			continue
		var p := Vector2(_x(float(m.t)), r.end.y - clampf((float(m.value) - lo) / (hi - lo), 0.0, 1.0) * r.size.y)
		draw_circle(p, 4.5, ser[2], true, -1.0, true)
		# The figure kept whole and left to right inside a Hebrew name ("1.4 g").
		var num := str(roundi(float(m.value))) if ser[0] != "g" else "%.1f g" % float(m.value)
		var lbl := "%s \u2066%s\u2069" % [str(names.get("ev_" + str(m.id), m.id)), num]
		var w := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		# On a dark plate off the line: above the dot, else beside it (right, left), clear of the graph's title and
		# of the labels already placed; above the dot as a last resort.
		var tries := [
			Vector2(p.x - w / 2.0, p.y - 27.0), Vector2(p.x + 10.0, p.y - 8.0), Vector2(p.x - w - 18.0, p.y - 8.0)
		]
		var room := Rect2(r.position.x, r.position.y, r.size.x, r.size.y + 8.0)
		var plate := Rect2(tries[0] - Vector2(4, 0), Vector2(w + 8, 17))
		for o in tries:
			var c := Rect2(o - Vector2(4, 0), Vector2(w + 8, 17))
			if room.encloses(c) and not placed.any(func(q): return q.intersects(c)):
				plate = c
				break
		placed.append(plate)
		draw_rect(plate, Color(Look.PANEL, 0.85))
		draw_string(font, plate.position + Vector2(4, 13), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Look.TEXT)
