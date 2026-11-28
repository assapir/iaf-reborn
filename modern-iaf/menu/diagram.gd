# A lesson's diagram (modern-iaf/docs/training-plan.md §2.2, training.md §16.5; the approved mocks A132 / A134): a
# manoeuvre of a lesson file's `diagrams` drawn in the briefing map's vocabulary (the own path a line over a dark
# casing, numbered pins: an accent disc, a white ring, the number in navy; the runway as the map draws it; on the
# inline start the legend of the points), or with `paper` in the notebook's ink (the legend is the page's own table).
# A top view and a side view on their 0 to 100 frames, stretched to the box; never mirrored (the map's rule).
extends Control

const Look := preload("look.gd")
## The top view's share of the height.
const TOP := 0.70
## The briefing's legend: this share of the width at the inline start.
const LEGEND := 0.40
## Arrows along a path, at these fractions of its length.
const ARROWS := [0.1, 0.3, 0.5, 0.7, 0.9]

## The diagram (training.md §16.5), its texts in `lang`.
var def := {}
var lang := "en"
var paper := false
var font: Font
var bold: Font
## The runway in use's name, at the runway's first end.
var runway := ""
## The views' captions and the side view's ground: [top, side, ground] in the screen's language.
var captions: Array = []


## Diagram `d` in language `lang_id`, its captions from the screen's strings `s`.
func use(d: Dictionary, lang_id: String, s: Callable) -> void:
	def = d
	lang = lang_id
	captions = [s.call("dia_above"), s.call("dia_side"), s.call("dia_field")]
	tooltip_text = tr_text(d.get("title", {}))
	queue_redraw()


func tr_text(t) -> String:
	return str(t.get(lang, t.get("en", ""))) if t is Dictionary else ""


## Its points' legend lines: [name, what to hold] each.
static func legend(d: Dictionary, lang_id: String) -> Array:
	var out := []
	for p in d.get("points", []):
		out.append([str(p.get(lang_id, p.get("en", ""))), str(p.get("hold", {}).get(lang_id, ""))])
	return out


func _draw() -> void:
	if def.is_empty() or captions.size() < 3 or font == null or bold == null:
		return
	var w := size.x
	var top: Dictionary = def.get("top", {})
	var side: Dictionary = def.get("side", {})
	var top_h := size.y * (TOP if not side.is_empty() else 1.0)
	var line := Color("1b1b1b") if paper else Look.ACCENT
	var text := Color("1b1b1b") if paper else Look.TEXT
	var muted := Color("444444") if paper else Look.MUTED
	if not paper:
		draw_rect(Rect2(Vector2.ZERO, size), Look.BG)
		draw_rect(Rect2(Vector2.ZERO, size), Look.LINE, false, 1.0)
	var fs := 15 if paper else 17
	# On paper the drawing takes the whole width from a little before its leftmost point.
	var x0 := 0.0
	if paper:
		x0 = 100.0
		for pt in _all(top):
			x0 = minf(x0, float(pt[0]))
		x0 = maxf(x0 - 6.0, 0.0)
	var px := func(x: float) -> float: return (x - x0) / (100.0 - x0) * w
	var p := func(xy: Array) -> Vector2: return Vector2(px.call(float(xy[0])), float(xy[1]) / 100.0 * top_h)
	# The zones (a SAM's reach), the runway, the paths, the notes, the pins.
	for z in top.get("zones", []):
		var c: Vector2 = p.call(z.at)
		var r := float(z.r) / (100.0 - x0) * w
		draw_circle(c, r, Color(Look.WARN, 0.12) if not paper else Color(0, 0, 0, 0.06), true, -1.0, true)
		draw_circle(c, r, Look.WARN if not paper else muted, false, 2.0, true)
		draw_string(font, c + Vector2(-r * 0.5, -r + fs + 4), tr_text(z), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, text)
	if top.get("runway") is Array:
		var a: Vector2 = p.call(top.runway[0])
		var b: Vector2 = p.call(top.runway[1])
		draw_line(a, b, Color("6b675e") if paper else Color("c9ced6"), 10.0)
		_plate(a + Vector2(0, 12), runway, fs - 2, text)
	for path in top.get("paths", []):
		var pts := PackedVector2Array()
		for xy in path.track:
			pts.append(p.call(xy))
		_path(pts, str(path.get("kind", "own")) == "own", line, muted)
	for n in top.get("notes", []):
		draw_string(font, p.call(n.at) + Vector2(4, -8), tr_text(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, muted)
	var pins: Array = top.get("pins", [])
	for i in pins.size():
		_pin(p.call(pins[i]), str(i + 1), fs)
	# The legend at the inline start (the briefing's): each pin's number, its name and what to hold there.
	var lx := 10.0
	draw_string(bold, Vector2(lx, 24), captions[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
	var y := 34.0
	var lines: Array = [] if paper else legend(def, lang)
	for i in lines.size():
		_pin(Vector2(lx + 12, y + 14), str(i + 1), fs - 3, 11.0)
		draw_string(bold, Vector2(lx + 30, y + 19), lines[i][0], HORIZONTAL_ALIGNMENT_LEFT, LEGEND * w, fs, text)
		var hold_at := Vector2(lx + 30, y + 21 + fs)
		draw_string(font, hold_at, lines[i][1], HORIZONTAL_ALIGNMENT_LEFT, LEGEND * w, fs - 2, muted)
		y += 8 + 2 * (fs + 2)
	if side.is_empty():
		return
	# The side view: the height above the ground's line against the way.
	var y0 := top_h + 14.0
	var ground := size.y - 22.0
	var high := y0 + 30.0
	var q := func(xh: Array) -> Vector2:
		return Vector2(px.call(float(xh[0])), ground - float(xh[1]) / 100.0 * (ground - high))
	draw_line(Vector2(0, y0), Vector2(w, y0), Color(line, 0.25), 1.0)
	draw_string(bold, Vector2(lx, y0 + 18), captions[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, muted)
	var gx := w
	for xh in _all(side):
		gx = minf(gx, px.call(float(xh[0])) - 0.08 * w)
	draw_line(Vector2(gx, ground), Vector2(w - 8, ground), muted, 1.0)
	draw_string(font, Vector2(gx, ground + 17), captions[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, muted)
	for n in side.get("notes", []):
		draw_string(font, q.call(n.at) + Vector2(4, -8), tr_text(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, muted)
	for path in side.get("paths", []):
		var pts := PackedVector2Array()
		for xh in path.track:
			pts.append(q.call(xh))
		_path(pts, str(path.get("kind", "own")) == "own", line, muted, false)
	var sp: Array = side.get("pins", [])
	for i in sp.size():
		_pin(q.call(sp[i]), str(i + 1), fs - 3, 11.0)


## Every point of a view (its paths, pins, runway).
func _all(view: Dictionary) -> Array:
	var out := []
	for path in view.get("paths", []):
		out.append_array(path.track)
	out.append_array(view.get("pins", []))
	if view.get("runway") is Array:
		out.append_array(view.runway)
	return out


## A path: the own jet's a line over a dark casing (on paper the ink alone), another's a thinner dashed line; with
## `arrows`, arrows along it.
func _path(pts: PackedVector2Array, own: bool, line: Color, muted: Color, arrows := true) -> void:
	if pts.size() < 2:
		return
	if not own:
		for i in pts.size() - 1:
			draw_dashed_line(pts[i], pts[i + 1], muted, 2.0, 8.0, true, true)
	else:
		if not paper:
			draw_polyline(pts, Color(0, 0, 0, 0.5), 6.0, true)
		draw_polyline(pts, line, 3.0 if paper else 3.5, true)
	if not arrows:
		return
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	for f in ARROWS:
		var at: float = f * total
		for i in pts.size() - 1:
			var d := pts[i].distance_to(pts[i + 1])
			if at <= d:
				_arrow(pts[i].lerp(pts[i + 1], at / maxf(d, 0.001)), pts[i + 1] - pts[i], line if own else muted)
				break
			at -= d


func _arrow(m: Vector2, dir: Vector2, c: Color) -> void:
	var d := dir.normalized()
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
	var ink := Color("1b1b1b") if paper else Look.NAVY
	draw_string(bold, at + Vector2(-tw / 2.0, fs * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func _plate(at: Vector2, t: String, fs: int, text: Color) -> void:
	if t == "":
		return
	var sz := Vector2(font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12, fs + 10)
	if not paper:
		draw_rect(Rect2(at, sz), Color(Look.BG, 0.88))
	draw_string(font, at + Vector2(6, fs + 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text)
