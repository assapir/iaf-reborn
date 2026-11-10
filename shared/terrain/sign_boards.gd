# World scale Real (docs/world-scale.md §4.3): the yellow taxi signs re-lettered with the real runway's designation.
# The sign models show a board of parts.png (`<27>`, `<09>` or `<23>`); a re-lettered sign gets a copy of that texture
# whose board has its two digits cleared with the board's own yellow (the clean strip between the left arrow and the
# digits, stretched over them) and the label drawn in black at the digits' height in the game's menu font (Gill Sans
# Condensed, the install's resource/menu/fnt/cr1.ttf). The arrows stay.
# Modern IAF's bases have no sign models: board() builds a sign of airbases.json's `signs` (iaf-sim airbases, ICAO
# Annex 14 colours) with the Settings.display_font("ui") lettering (modern-iaf/docs/airbases.md §9).
extends RefCounted

const ModelDetail := preload("res://shared/util/model_detail.gd")

## The boards in parts.png (1024 × 1024): the sign's number → [the board's top and bottom row, the digits' top and
## bottom row].
const BOARDS := {27: [0, 133, 14, 111], 9: [132, 268, 149, 247], 23: [530, 665, 550, 647]}
## The digits' columns (cleared, the label centred in them) and a clean yellow strip left of the digits.
const DIGITS_X := Vector2i(106, 297)
const CLEAN_X := Vector2i(106, 126)
## The label's spacing between glyphs, in digit heights.
const SPACING := 0.12
const FONT := "menu/cr1.ttf"
const SIZE := 1024

## A built sign's face: its height, the gap under it (m; Annex 14 Table 5-5: a face of 0.8–1.1 m on code D–F
## taxiways, the top at most 1.1 m above the ground; inferred: 0.9 m and 0.2 m), the legend's height and a character's
## advance (m), the arrow's length.
const FACE_H := 0.9
const LIFT := 0.2
const LEGEND_H := 0.45
const CHAR_W := 0.34
const ARROW_W := 0.6
## A board's colours by style: [background, legend] (Annex 14 5.4.1: mandatory white on red, direction black on yellow,
## location yellow on black).
const STYLES := {
	"mandatory": [Color(0.72, 0.05, 0.05), Color(0.95, 0.95, 0.95)],
	"direction": [Color(0.95, 0.75, 0.05), Color(0.03, 0.03, 0.03)],
	"location": [Color(0.03, 0.03, 0.03), Color(0.95, 0.75, 0.05)],
}

static var _font: FontFile
static var _textures := {}
static var _materials := {}


## Re-letters the sign `node` showing board `n` to `label` ("25L"): each surface takes a copy of its material with the
## re-lettered texture. False when it cannot (no such board, no font, a missing glyph, a texture not parts.png's
## size): the sign then keeps its original number.
static func reletter(node: Node3D, n: int, label: String) -> bool:
	var done := false
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := ModelDetail.base_material(mi.get_active_material(i)) as BaseMaterial3D
			var tex := texture(m.albedo_texture if m != null else null, n, label)
			if tex == null:
				return false
			var copy := m.duplicate() as BaseMaterial3D
			copy.albedo_texture = tex
			mi.set_surface_override_material(i, copy)
			done = true
	return done


## parts.png (`src`) with board `n` re-lettered to `label`, cached; null when it cannot be made.
static func texture(src: Texture2D, n: int, label: String) -> Texture2D:
	var key := "%d %s" % [n, label]
	if _textures.has(key):
		return _textures[key]
	var img := relettered(src.get_image() if src != null else null, n, label)
	var tex: Texture2D = null
	if img != null:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## A copy of parts.png's image with board `n` re-lettered; null when it cannot be made.
static func relettered(src: Image, n: int, label: String) -> Image:
	var b: Array = BOARDS.get(n, [])
	if src == null or b.is_empty() or src.get_width() != SIZE or src.get_height() != SIZE or label.is_empty():
		return null
	var glyphs := []
	for c in label:
		var g := glyph(c)
		if g == null:
			return null
		glyphs.append(g)
	var img := src.duplicate() as Image
	img.clear_mipmaps()
	if img.is_compressed():
		return null
	img.convert(Image.FORMAT_RGBA8)
	# The digits cleared: the clean strip stretched over them, every row of the board.
	var top: int = b[0]
	var rows: int = b[1] - b[0] + 1
	var strip := img.get_region(Rect2i(CLEAN_X.x, top, CLEAN_X.y - CLEAN_X.x, rows))
	strip.resize(DIGITS_X.y - DIGITS_X.x, rows, Image.INTERPOLATE_BILINEAR)
	img.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i(DIGITS_X.x, top))
	# The label at the digits' height, narrowed to fit between the arrows.
	var h: int = b[3] - b[2] + 1
	var widths := []
	var total := 0.0
	for g: Image in glyphs:
		widths.append(g.get_width() * float(h) / g.get_height())
		total += widths[-1]
	total += SPACING * h * (glyphs.size() - 1)
	var room := float(DIGITS_X.y - DIGITS_X.x) - 6.0
	var sx := minf(1.0, room / total)
	var x := DIGITS_X.x + 0.5 * (DIGITS_X.y - DIGITS_X.x - total * sx)
	var black := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	for i in glyphs.size():
		var g: Image = (glyphs[i] as Image).duplicate()
		var w := maxi(1, roundi(widths[i] * sx))
		g.resize(w, h, Image.INTERPOLATE_LANCZOS)
		black.resize(w, h)
		black.fill(Color(0.02, 0.02, 0.02))
		img.blend_rect_mask(black, g, Rect2i(0, 0, w, h), Vector2i(roundi(x), b[2]))
		x += (widths[i] + SPACING * h) * sx
	return img


## The menu font's glyph `c` cropped to its ink, white with the coverage in alpha (RGBA8); null without the font or
## the glyph.
static func glyph(c: String) -> Image:
	if _font == null:
		var path := Settings.converted(FONT)
		if not FileAccess.file_exists(path):
			return null
		_font = FontFile.new()
		if _font.load_dynamic_font(path) != OK:
			_font = null
			return null
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font.generate_mipmaps = false
	var size := Vector2i(256, 0)
	var idx := _font.get_glyph_index(size.x, c.unicode_at(0), 0)
	if idx == 0:
		return null
	_font.render_glyph(0, size, idx)
	var t := _font.get_glyph_texture_idx(0, size, idx)
	var r := _font.get_glyph_uv_rect(0, size, idx)
	if t < 0 or r.size.x < 1 or r.size.y < 1:
		return null
	var page := _font.get_texture_image(0, size, t)
	if page == null:
		return null
	var g := page.get_region(Rect2i(r))
	g.convert(Image.FORMAT_RGBA8)
	var used := g.get_used_rect()
	return g.get_region(used) if used.size.x > 0 else null


## A taxiway sign of `panels` ([{style, text, arrow}], left to right; `arrow` the turn in degrees, positive right, or
## null): a dark frame on two legs with one coloured board per panel, its face toward local +Z, the ground at y = 0.
static func board(panels: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Sign"
	var widths: Array[float] = []
	var total := 0.0
	for p: Dictionary in panels:
		var w := 0.3 + CHAR_W * String(p.get("text", "")).length() + (ARROW_W if p.get("arrow") != null else 0.0)
		widths.append(w)
		total += w
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(total + 0.1, FACE_H + 0.1, 0.25)
	frame.mesh = box
	frame.material_override = _material(Color(0.08, 0.08, 0.08))
	frame.position.y = LIFT + FACE_H * 0.5
	root.add_child(frame)
	for x in [-0.35 * total, 0.35 * total]:
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.08, LIFT + 0.05, 0.08)
		leg.mesh = lb
		leg.material_override = frame.material_override
		leg.position = Vector3(x, (LIFT + 0.05) * 0.5, 0)
		root.add_child(leg)
	var x0 := -total * 0.5
	for i in panels.size():
		var p: Dictionary = panels[i]
		var colours: Array = STYLES.get(String(p.get("style", "")), STYLES.direction)
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(widths[i] - 0.04, FACE_H - 0.04)
		face.mesh = q
		face.material_override = _material(colours[0])
		face.position = Vector3(x0 + widths[i] * 0.5, LIFT + FACE_H * 0.5, 0.126)
		root.add_child(face)
		var arrow = p.get("arrow")
		var text_x := x0 + widths[i] * 0.5
		if arrow != null:
			# The arrow on the side it points to (straight on: before the designator, Annex 14 5.4.3.32).
			var right := float(arrow) > 0.0
			var ax := x0 + (widths[i] - 0.15 - ARROW_W * 0.5 if right else 0.15 + ARROW_W * 0.5)
			text_x += -ARROW_W * 0.5 if right else ARROW_W * 0.5
			var a := MeshInstance3D.new()
			a.mesh = _arrow_mesh()
			a.material_override = _material(colours[1])
			a.position = Vector3(ax, LIFT + FACE_H * 0.5, 0.128)
			a.rotation.z = -deg_to_rad(float(arrow))
			root.add_child(a)
		var label := Label3D.new()
		label.text = String(p.get("text", ""))
		label.font = Settings.display_font("ui")
		label.font_size = 128
		label.pixel_size = LEGEND_H / 128.0 * 1.3
		label.modulate = colours[1]
		label.outline_size = 0
		label.shaded = true
		label.double_sided = false
		label.position = Vector3(text_x, LIFT + FACE_H * 0.5, 0.13)
		root.add_child(label)
		x0 += widths[i]
	return root


## An arrow LEGEND_H long pointing up (+Y), centred, in the XY plane facing +Z.
static func _arrow_mesh() -> ArrayMesh:
	var h := LEGEND_H
	var pts := PackedVector2Array(
		[
			Vector2(0, h * 0.5),
			Vector2(-h * 0.35, h * 0.1),
			Vector2(-h * 0.1, h * 0.1),
			Vector2(-h * 0.1, -h * 0.5),
			Vector2(h * 0.1, -h * 0.5),
			Vector2(h * 0.1, h * 0.1),
			Vector2(h * 0.35, h * 0.1),
		]
	)
	var idx := Geometry2D.triangulate_polygon(pts)
	var verts := PackedVector3Array()
	for k in idx:
		verts.append(Vector3(pts[k].x, pts[k].y, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.BACK)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]
