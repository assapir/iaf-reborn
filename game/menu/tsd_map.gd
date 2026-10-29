# The TSD map layer: the converted EMF metafiles (`iaf-convert menu` -> emf/*.json) turned into
# vertex-coloured meshes once, then drawn at the current zoom. Like PlayEnhMetaFile, each
# metafile's frame is stretched onto the map extent; cosmetic pens stay one pixel wide.
extends Control

var tsd: Control
## Draw batches in metafile order: {mesh, kind} or {polyline, color, width} for wide pens.
var map_batches: Array = []
var grid_batches: Array = []
var text_shape_batches: Array = []
## text.emf labels: {pos (map units), text, px (font px at zoom 1, scaled with the zoom), color}.
var text_ops: Array = []


func load_maps(map: Dictionary, grid: Dictionary, text: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_batches = _batches(map)
	grid_batches = _batches(grid)
	if Settings.briefing_map == "modern":
		text = modern_text(text)
	text_shape_batches = _batches(text)
	var map_size: Vector2 = tsd.MAP_SIZE
	for op in text.get("ops", []):
		if op.t == "text":
			(
				text_ops
				. append(
					{
						"pos": Vector2(op.pos[0], op.pos[1]) * map_size,
						"text": op.text,
						"px": float(op.font.height) * map_size.y,
						"color": Color8(op.color[0], op.color[1], op.color[2]),
					}
				)
			)
	queue_redraw()


## The modern map (Settings.briefing_map): text.emf with each city's dot (a small filled circle and its outline, the
## next op) and its label moved by the same step onto the real city (IafEmf.modern_cities, the georeference).
static func modern_text(text: Dictionary) -> Dictionary:
	text = text.duplicate(true)
	var ops: Array = text.get("ops", [])
	var tsd_script: Script = load("res://menu/tsd.gd")
	var map_size: Vector2 = tsd_script.MAP_SIZE
	for city in IafEmf.modern_cities():
		var real: Vector2 = tsd_script.world_to_map(city.pos.x, city.pos.y) / map_size
		var dot := -1
		var best := 30.0 / map_size.x
		for i in ops.size():
			var c := _dot_centre(ops[i], map_size)
			if c.x >= 0.0 and c.distance_to(real) < best:
				best = c.distance_to(real)
				dot = i
		var label := _label_ops(ops, city.label)
		if dot < 0 or label.is_empty():
			continue
		var step := real - _dot_centre(ops[dot], map_size)
		for ring in ops[dot].rings:
			_shift(ring, step)
		if dot + 1 < ops.size() and ops[dot + 1].t == "polyline":
			_shift(ops[dot + 1].points, step)
		for i in label:
			ops[i].pos = [ops[i].pos[0] + step.x, ops[i].pos[1] + step.y]
	return text


## A city dot's centre (map units / MAP_SIZE), or (-1, -1) for any other op.
static func _dot_centre(op: Dictionary, map_size: Vector2) -> Vector2:
	if op.t != "polygon" or op.brush == null or op.rings.size() != 1:
		return Vector2(-1, -1)
	var r: Array = op.rings[0]
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k in range(0, r.size(), 2):
		lo = lo.min(Vector2(r[k], r[k + 1]))
		hi = hi.max(Vector2(r[k], r[k + 1]))
	return (lo + hi) / 2.0 if (hi.x - lo.x) * map_size.x < 10.0 else Vector2(-1, -1)


## The consecutive text ops that spell `label` (spaces ignored: "B E I R U T", "D" + "AMASCUS").
static func _label_ops(ops: Array, label: String) -> Array:
	for i in ops.size():
		var spelt := ""
		var run := []
		var j := i
		while j < ops.size() and ops[j].t == "text" and spelt.length() < label.length():
			spelt += ops[j].text.replace(" ", "")
			run.append(j)
			j += 1
		if spelt == label:
			return run
	return []


static func _shift(flat: Array, step: Vector2) -> void:
	for k in range(0, flat.size(), 2):
		flat[k] += step.x
		flat[k + 1] += step.y


## Groups consecutive fills / thin lines into meshes, keeping the metafile's drawing order.
var _out: Array
var _kind := ""
var _verts := PackedVector2Array()
var _colors := PackedColorArray()


func _batches(mf: Dictionary) -> Array:
	var map_size: Vector2 = tsd.MAP_SIZE
	_out = []
	_kind = ""
	for op in mf.get("ops", []):
		match op.t:
			"polygon":
				if op.brush != null:
					_begin("fill")
					var c := Color8(op.brush[0], op.brush[1], op.brush[2])
					# GDI's fill: all rings as one region under the fill mode (rings cross and overlap).
					var rings: Array[PackedVector2Array] = []
					for ring in op.rings:
						rings.append(_points(ring, map_size))
					var tris := IafEmf.fill_triangles(rings, op.alternate)
					_verts.append_array(tris)
					var cs := PackedColorArray()
					cs.resize(tris.size())
					cs.fill(c)
					_colors.append_array(cs)
				if op.pen != null:
					for ring in op.rings:
						var pts := _points(ring, map_size)
						pts.append(pts[0])
						_add_line(op.pen, pts, map_size)
			"polyline":
				_add_line(op.pen, _points(op.points, map_size), map_size)
	_flush()
	return _out


func _add_line(pen: Dictionary, pts: PackedVector2Array, map_size: Vector2) -> void:
	var c := Color8(pen.color[0], pen.color[1], pen.color[2])
	var width := float(pen.width) * map_size.x
	if width >= 1.0:
		_flush()
		_kind = ""
		_out.append({"polyline": pts, "color": c, "width": width})
		return
	_begin("line")
	for i in range(pts.size() - 1):
		_verts.append(pts[i])
		_verts.append(pts[i + 1])
		_colors.append(c)
		_colors.append(c)


func _begin(kind: String) -> void:
	if _kind != kind:
		_flush()
		_kind = kind


func _flush() -> void:
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES if _kind == "fill" else Mesh.PRIMITIVE_LINES, arrays)
	_out.append({"mesh": mesh})
	_verts = PackedVector2Array()
	_colors = PackedColorArray()


static func _points(flat: Array, map_size: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(flat.size() / 2)
	for i in pts.size():
		pts[i] = Vector2(flat[2 * i], flat[2 * i + 1]) * map_size
	return pts


func _draw() -> void:
	var k: float = tsd.zoom * tsd.fe._scale()
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	_draw_batches(map_batches, k)
	if tsd.layers.grid:
		_draw_batches(grid_batches, k)
	if tsd.layers.text:
		_draw_batches(text_shape_batches, k)
	draw_set_transform(Vector2.ZERO)


func _draw_batches(batches: Array, k: float) -> void:
	for b in batches:
		if b.has("mesh"):
			draw_mesh(b.mesh, null)
		else:
			# Wide pens scale with the zoom (at least one pixel).
			draw_polyline(b.polyline, b.color, maxf(b.width, 1.0 / k), true)
