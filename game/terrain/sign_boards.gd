# World scale Real (docs/world-scale.md §4.3): the yellow taxi signs re-lettered with the real runway's designation.
# The sign models show a board of parts.png (`<27>`, `<09>` or `<23>`); a re-lettered sign gets a copy of that texture
# whose board has its two digits cleared with the board's own yellow (the clean strip between the left arrow and the
# digits, stretched over them) and the label drawn in black at the digits' height in the game's menu font (Gill Sans
# Condensed, the install's resource/menu/fnt/cr1.ttf). The arrows stay.
extends RefCounted

## The boards in parts.png (1024 × 1024): the sign's number → [the board's top and bottom row, the digits' top and
## bottom row].
const BOARDS := {27: [0, 133, 14, 111], 9: [132, 268, 149, 247], 23: [530, 665, 550, 647]}
## The digits' columns (cleared, the label centred in them) and a clean yellow strip left of the digits.
const DIGITS_X := Vector2i(106, 297)
const CLEAN_X := Vector2i(106, 126)
## The label's spacing between glyphs, in digit heights.
const SPACING := 0.12
const FONT := "converted/menu/cr1.ttf"
const SIZE := 1024

static var _font: FontFile
static var _textures := {}


## Re-letters the sign `node` showing board `n` to `label` ("25L"): each surface takes a copy of its material with the
## re-lettered texture. False when it cannot (no such board, no font, a missing glyph, a texture not parts.png's
## size): the sign then keeps its original number.
static func reletter(node: Node3D, n: int, label: String) -> bool:
	var done := false
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
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
		var path := Settings.assets_dir().path_join(FONT)
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
