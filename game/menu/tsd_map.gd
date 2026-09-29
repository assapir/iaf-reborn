# The TSD map layer: the converted EMF metafiles (`iaf-convert menu` -> emf/*.json) turned into
# vertex-coloured meshes once, then drawn at the current zoom. Like PlayEnhMetaFile, each
# metafile's frame is stretched onto the map extent; cosmetic pens stay one pixel wide.
extends Control

var tsd: Control
## Draw batches in metafile order: {mesh, kind} or {polyline, color, width} for wide pens.
var map_batches: Array = []
var grid_batches: Array = []
var text_shape_batches: Array = []
## text.emf labels: {pos (map units), text, px (font px at zoom 1), color}.
var text_ops: Array = []


func load_maps(map: Dictionary, grid: Dictionary, text: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_batches = _batches(map)
	grid_batches = _batches(grid)
	text_shape_batches = _batches(text)
	var size_: Vector2 = tsd.MAP_SIZE
	for op in text.get("ops", []):
		if op.t == "text":
			text_ops.append({
				"pos": Vector2(op.pos[0], op.pos[1]) * size_,
				"text": op.text,
				"px": float(op.font.height) * size_.y,
				"color": Color8(op.color[0], op.color[1], op.color[2]),
			})
	queue_redraw()


## Groups consecutive fills / thin lines into meshes, keeping the metafile's drawing order.
var _out: Array
var _kind := ""
var _verts := PackedVector2Array()
var _colors := PackedColorArray()


func _batches(mf: Dictionary) -> Array:
	var size_: Vector2 = tsd.MAP_SIZE
	_out = []
	_kind = ""
	for op in mf.get("ops", []):
		match op.t:
			"polygon":
				if op.brush != null:
					_begin("fill")
					var c := Color8(op.brush[0], op.brush[1], op.brush[2])
					# Outer ring only (holes are rare in these maps and drawn over later).
					var pts := _points(op.rings[0], size_)
					for i in Geometry2D.triangulate_polygon(pts):
						_verts.append(pts[i])
						_colors.append(c)
				if op.pen != null:
					for ring in op.rings:
						var pts := _points(ring, size_)
						pts.append(pts[0])
						_add_line(op.pen, pts, size_)
			"polyline":
				_add_line(op.pen, _points(op.points, size_), size_)
	_flush()
	return _out


func _add_line(pen: Dictionary, pts: PackedVector2Array, size_: Vector2) -> void:
	var c := Color8(pen.color[0], pen.color[1], pen.color[2])
	var width := float(pen.width) * size_.x
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


static func _points(flat: Array, size_: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(flat.size() / 2)
	for i in pts.size():
		pts[i] = Vector2(flat[2 * i], flat[2 * i + 1]) * size_
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
