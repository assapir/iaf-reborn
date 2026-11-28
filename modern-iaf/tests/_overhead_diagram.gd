# Mock only (branch wt/train-mocks, never merged): the overhead break drawn for the training briefing's mock-up
# (modern-iaf/docs/training-plan.md §2.2) in the briefing map's drawing vocabulary: the route a line over a dark casing,
# numbered pins (an accent disc, a white ring, the number in navy), plates for the names, the runway as the map draws
# it. `paper`: the notebook's ink on paper instead. A top view and a side view; never mirrored (the map's rule).
extends Control

const Look := preload("res://menu/look.gd")

var paper := false
var font: Font
var bold: Font
## [title, top-view caption, side-view caption, ground, [pin names…]] in the screen's language.
var words: Array = []
var rtl := false


func _draw() -> void:
	var w := size.x
	var top_h := size.y * 0.70
	var line := Color("1b1b1b") if paper else Look.ACCENT
	var text := Color("1b1b1b") if paper else Look.TEXT
	var muted := Color("444444") if paper else Look.MUTED
	if not paper:
		draw_rect(Rect2(Vector2.ZERO, size), Look.BG)
		draw_rect(Rect2(Vector2.ZERO, size), Look.LINE, false, 1.0)
	var fs := 15 if paper else 17
	# On paper the legend is the page's own table: the drawing takes the whole width.
	var x0 := 0.36 if paper else 0.0
	var p := func(x: float, y: float) -> Vector2: return Vector2((x - x0) / (1.0 - x0) * w, y * top_h)
	# The runway (25R), the field's line.
	var rw := Rect2(p.call(0.42, 0.62) - Vector2(0, 5), Vector2(p.call(0.52, 0).x - p.call(0.42, 0).x, 10))
	draw_rect(rw, Color("6b675e") if paper else Color("c9ced6"))
	_plate(p.call(0.42, 0.62) + Vector2(0, 12), "25R", fs - 2, text, muted)
	# The path: the initial, the break, downwind, the final turn, final.
	var pts := PackedVector2Array()
	pts.append(p.call(0.99, 0.74))
	pts.append(p.call(0.64, 0.74))
	_arc(pts, p.call(0.64, 0.52), 0.22 * top_h, PI / 2.0, 1.5 * PI)  # the break: right, from westbound to east
	_arc(pts, p.call(0.82, 0.46), 0.16 * top_h, -PI / 2.0, PI / 2.0)  # the final turn, right
	pts.append(p.call(0.48, 0.62))
	if not paper:
		draw_polyline(pts, Color(0, 0, 0, 0.5), 6.0, true)
	draw_polyline(pts, line, 3.0 if paper else 3.5, true)
	for i in [0, 10, 22, 32, 43]:  # arrows along the way
		_arrow(pts[mini(i, pts.size() - 2)], pts[mini(i, pts.size() - 2) + 1], line)
	var pins := [
		p.call(0.92, 0.74),
		p.call(0.64, 0.74),
		p.call(0.73, 0.30),
		p.call(0.82, 0.46) + Vector2(0.16 * top_h, 0),
		p.call(0.48, 0.62)
	]
	for i in pins.size():
		_pin(pins[i], str(i + 1), fs)
	# The legend at the inline start: each pin's number and what to hold there.
	var names: Array = [] if paper else words[4]
	var lx := 10.0
	var y := 34.0
	draw_string(bold, Vector2(lx, 24), words[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
	for i in names.size():
		_pin(Vector2(lx + 12, y + 14), str(i + 1), fs - 3, 11.0)
		var lines: PackedStringArray = str(names[i]).split("\n")
		for k in lines.size():
			draw_string(
				bold if k == 0 else font,
				Vector2(lx + 30, y + 19 + k * (fs + 2)),
				lines[k],
				HORIZONTAL_ALIGNMENT_LEFT,
				0.40 * w,
				fs - (0 if k == 0 else 2),
				text if k == 0 else muted
			)
		y += 8 + lines.size() * (fs + 2)
	# The side view: height above the field against the same five points.
	var y0 := top_h + 14.0
	var hgt := size.y - y0 - 22.0
	draw_line(Vector2(0, y0), Vector2(w, y0), Color(line, 0.25), 1.0)
	draw_string(bold, Vector2(lx, y0 + 18), words[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, muted)
	var ground := y0 + hgt
	draw_line(Vector2(p.call(0.40, 0).x, ground), Vector2(w - 8, ground), muted, 1.0)
	draw_string(font, Vector2(p.call(0.40, 0).x, ground + 17), words[3], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, muted)
	var top_y := y0 + 30.0
	draw_string(font, Vector2(p.call(0.74, 0).x + 4, top_y - 8), words[5], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, muted)
	var prof := PackedVector2Array(
		[
			Vector2(p.call(0.48, 0).x, top_y),
			Vector2(p.call(0.60, 0).x, top_y),
			Vector2(p.call(0.72, 0).x, top_y),
			Vector2(p.call(0.84, 0).x, top_y + (ground - top_y) * 0.55),
			Vector2(p.call(0.96, 0).x, ground)
		]
	)
	if not paper:
		draw_polyline(prof, Color(0, 0, 0, 0.5), 6.0, true)
	draw_polyline(prof, line, 3.0 if paper else 3.5, true)
	for i in prof.size():
		_pin(prof[i], str(i + 1), fs - 3, 11.0)


## Points of an arc round `c`, radius `r` px, from angle `a0` to `a1` (radians, y down: clockwise on the screen).
func _arc(pts: PackedVector2Array, c: Vector2, r: float, a0: float, a1: float) -> void:
	for i in range(0, 21):
		var a := a0 + (a1 - a0) * i / 20.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)


func _arrow(a: Vector2, b: Vector2, c: Color) -> void:
	var d := (b - a).normalized()
	var m := (a + b) / 2.0
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([m + d * 9, m - d * 5 + n * 7, m - d * 5 - n * 7]), c)


func _pin(at: Vector2, n: String, fs: int, r := 14.0) -> void:
	if paper:
		draw_circle(at, r, Color("f3efe6"), true, -1.0, true)
		draw_circle(at, r, Color("1b1b1b"), false, 2.0, true)
	else:
		draw_circle(at, r, Look.ACCENT, true, -1.0, true)
		draw_circle(at, r, Color.WHITE, false, 2.5, true)
	var tw := bold.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(
		bold, at + Vector2(-tw / 2.0, fs * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color("1b1b1b") if paper else Look.NAVY
	)


func _plate(at: Vector2, t: String, fs: int, text: Color, _muted: Color) -> void:
	var sz := Vector2(font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12, fs + 10)
	if not paper:
		draw_rect(Rect2(at, sz), Color(Look.BG, 0.88))
	draw_string(font, at + Vector2(6, fs + 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text)
