# What the original's GDI calls draw, in 640×480 units scaled by `s` (docs/front-end.md §16.2): Arial text with
# GDI's metrics and RoundRect. At s = 1 the pixels are GDI's; larger windows get the same shapes at their own
# resolution (crisp edges, no smoothing, as 1998 GDI drew).
#
# Text: GDI's Arial advances are the hinted widths the font stores per pixel size (its `hdmx` table), and the text
# cell is the font's `VDMX` ascent + descent; Godot shapes with the outline widths and the `hhea` height, which are
# wider and shorter (RESTART MISSION at 11 px: 91 px in GDI, 101 in Godot). So the glyphs come from Godot (bilevel,
# hinted) and the positions and the cell from the font file's own tables. Without those tables (a font other than
# Arial) Godot's rounded advances and heights stand in.
extends RefCounted

# font file path → {"hdmx": {ppem: PackedByteArray}, "vdmx": {ppem: Vector2i(ascent, descent)}}
static var _tables := {}


## Arial as GDI's CreateFont(weight) picks it (weight 900 → Arial Bold): bilevel, fully hinted.
static func arial(weight := 400) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial", "Liberation Sans"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


## FUN_004eee10(p, weight): lfHeight = -round(cy·p/100) with cy the cell height of "A…Za…z" at lfHeight -100 in
## that weight (VDMX: Arial 112, Arial Bold 115), so size 10 → 11 ppem, 11 → 12, bold 50 → 58.
static func ppem(p: int, weight := 400) -> int:
	var v: Dictionary = _font_tables(weight).vdmx
	var cy: int = v[100].x + v[100].y if v.has(100) else 112
	return int(cy * p / 100.0 + 0.5)


static func _u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


static func _s16(b: PackedByteArray, o: int) -> int:
	var v := _u16(b, o)
	return v - 65536 if v >= 32768 else v


static func _font_tables(weight: int) -> Dictionary:
	var path := OS.get_system_font_path("Arial", weight)
	if _tables.has(path):
		return _tables[path]
	var t := {"hdmx": {}, "vdmx": {}}
	_tables[path] = t
	var b := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	if b.size() < 12:
		return t
	var dir := {}
	for i in _u16(b, 4):
		var e := 12 + 16 * i
		dir[b.slice(e, e + 4).get_string_from_ascii()] = (_u16(b, e + 8) << 16) | _u16(b, e + 10)
	if dir.has("hdmx") and dir.has("maxp"):
		var o: int = dir.hdmx
		var glyphs := _u16(b, dir.maxp + 4)
		var rec := (_u16(b, o + 4) << 16) | _u16(b, o + 6)
		for i in _s16(b, o + 2):
			var r := o + 8 + i * rec
			t.hdmx[b[r]] = b.slice(r + 2, r + 2 + glyphs)
	if dir.has("VDMX"):
		var o: int = dir.VDMX
		var g := o + _u16(b, o + 6 + 4 * _u16(b, o + 4))  # the first ratio's group (1:1)
		for i in _u16(b, g):
			var e := g + 4 + 6 * i
			t.vdmx[_u16(b, e)] = Vector2i(_s16(b, e + 2), -_s16(b, e + 4))
	return t


## GDI's tmAscent / tmDescent of Arial at `px` ppem (VDMX), else Godot's.
static func metrics(font: Font, weight: int, px: int) -> Vector2i:
	var v: Dictionary = _font_tables(weight).vdmx
	return v[px] if v.has(px) else Vector2i(roundi(font.get_ascent(px)), roundi(font.get_descent(px)))


## The glyphs of `text` in visual order with their GDI advances at `px` ppem: [[font_rid, index, advance], …].
static func _glyphs(font: Font, weight: int, text: String, px: int) -> Array:
	var ts := TextServerManager.get_primary_interface()
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, text, font.get_rids(), px)
	var widths: PackedByteArray = _font_tables(weight).hdmx.get(px, PackedByteArray())
	var main: RID = font.get_rids()[0]
	var out := []
	for g in ts.shaped_text_get_glyphs(rid):
		var i: int = g.index
		var adv := roundi(g.advance)
		if g.font_rid == main and i < widths.size():
			adv = widths[i]
		out.append([g.font_rid, i, adv])
	ts.free_rid(rid)
	return out


## GetTextExtentPoint32: (width, cell height) at `px` ppem.
static func extent(font: Font, weight: int, text: String, px: int) -> Vector2i:
	var w := 0
	for g in _glyphs(font, weight, text, px):
		w += g[2]
	var m := metrics(font, weight, px)
	return Vector2i(w, m.x + m.y)


## TextOut at (x, y) in 640×480 units with GDI's alignment: TA_LEFT or TA_CENTER (`centre`; the text starts at
## x - width/2, integer division), TA_TOP or TA_BOTTOM (`bottom`: y is the cell's bottom). At scale `s` the text is
## Arial at round(px·s) ppem with that size's own GDI advances and cell, placed at the scaled anchor (at s = 1
## exactly GDI's pixels).
static func text_out(
	ci: CanvasItem,
	font: Font,
	weight: int,
	text: String,
	px: int,
	x: int,
	y: int,
	s: float,
	colour: Color,
	centre := false,
	bottom := false
) -> void:
	var ts := TextServerManager.get_primary_interface()
	var size := maxi(1, roundi(px * s))
	var glyphs := _glyphs(font, weight, text, size)
	var m := metrics(font, weight, size)
	var pen := roundi(x * s)
	if centre:
		var w := 0
		for g in glyphs:
			w += g[2]
		pen -= w / 2
	var baseline := roundi(y * s) + (-m.y if bottom else m.x)
	for g in glyphs:
		ts.font_draw_glyph(g[0], ci.get_canvas_item(), size, Vector2(pen, baseline), g[1], colour)
		pen += g[2]


## The pixel columns [x0, x1) of row `py` (a pixel centre) inside a GDI RoundRect over [l, r) × [t, b) with
## w × h corner ellipses; empty when the row misses it.
static func _span(py: float, l: float, t: float, r: float, b: float, w: float, h: float) -> Vector2i:
	if py < t or py >= b or r <= l:
		return Vector2i.ZERO
	var rx := w / 2.0
	var ry := h / 2.0
	var half := rx
	if ry > 0.0 and rx > 0.0:
		var dy := maxf(t + ry - py, py - (b - ry))
		if dy > 0.0:
			if dy > ry:
				return Vector2i.ZERO
			half = rx * sqrt(1.0 - (dy / ry) * (dy / ry))
	var x0 := maxi(ceili(l + rx - half - 0.5), ceili(l - 0.5))
	var x1 := mini(floori(r - rx + half - 0.5), ceili(r - 0.5) - 1) + 1
	return Vector2i(x0, x1) if x1 > x0 else Vector2i.ZERO


## RoundRect(l, t, r, b, w, h) (640×480 units) at scale `s`: the shape covers [l, r) × [t, b) with w × h corner
## ellipses (GDI's ellipse sizes are diameters); the pen, `pen_w` units wide, is drawn inside the shape
## (PS_INSIDEFRAME) as the band down to the shape inset by `pen_w`; the brush fills the rest (`brush` with alpha 0 =
## NULL_BRUSH). Runs of identical rows are drawn as one rectangle.
static func round_rect(
	ci: CanvasItem, rect: Rect2i, w: int, h: int, pen: Color, pen_w: int, brush: Color, s: float
) -> void:
	var l := rect.position.x * s
	var t := rect.position.y * s
	var r := rect.end.x * s
	var b := rect.end.y * s
	var p := pen_w * s
	var rows := []  # [y, outer, inner]
	for y in range(floori(t), ceili(b)):
		var py := y + 0.5
		var o := _span(py, l, t, r, b, w * s, h * s)
		if o == Vector2i.ZERO:
			continue
		rows.append([y, o, _span(py, l + p, t + p, r - p, b - p, (w - 2 * pen_w) * s, (h - 2 * pen_w) * s)])
	var i := 0
	while i < rows.size():
		var j := i + 1
		while (
			j < rows.size()
			and rows[j][1] == rows[i][1]
			and rows[j][2] == rows[i][2]
			and rows[j][0] == rows[j - 1][0] + 1
		):
			j += 1
		var y0: int = rows[i][0]
		var hh: int = rows[j - 1][0] + 1 - y0
		var o: Vector2i = rows[i][1]
		var n: Vector2i = rows[i][2]
		if n == Vector2i.ZERO:
			ci.draw_rect(Rect2(o.x, y0, o.y - o.x, hh), pen)
		else:
			ci.draw_rect(Rect2(o.x, y0, n.x - o.x, hh), pen)
			ci.draw_rect(Rect2(n.y, y0, o.y - n.y, hh), pen)
			if brush.a > 0.0:
				ci.draw_rect(Rect2(n.x, y0, n.y - n.x, hh), brush)
		i = j


## FUN_004f0680: the point lies in [l, r] × [t, b], both edges included (one pixel more than RoundRect paints).
static func hit(rect: Rect2i, p: Vector2i) -> bool:
	return p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y
