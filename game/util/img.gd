# Small image, font and screenshot helpers shared by the menus, the cockpit and the tools.
extends RefCounted


## An image file as a texture (with mipmaps when asked); null when the file is missing.
static func load_texture(path: String, mipmaps := false) -> ImageTexture:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		return null
	if mipmaps:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The original's masked sprites: the top half is the sprite, the bottom half its AND mask
## (black = sprite). Returns the sprite as RGBA with the mask as alpha.
static func masked_sprite(img: Image) -> Image:
	if img.is_compressed():
		img.decompress()
	var h := img.get_height() / 2
	var out := Image.create(img.get_width(), h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = 1.0 - img.get_pixel(x, y + h).get_luminance()
			out.set_pixel(x, y, c)
	return out


## A Windows .cur (the menu's 32×32 monochrome cursors) as [RGBA Image, hotspot]; [] when unreadable.
## AND 0 / XOR 0 = black, 0 / 1 = white, 1 / 0 = transparent, 1 / 1 (screen invert) = black.
static func load_cursor(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var d := FileAccess.get_file_as_bytes(path)
	if d.size() < 22 + 40 or d.decode_u16(2) != 2:
		return []
	var hot := Vector2(d.decode_u16(10), d.decode_u16(12))
	var off := d.decode_u32(18)
	var w := d.decode_s32(off + 4)
	var h := d.decode_s32(off + 8) / 2
	if d.decode_u16(off + 14) != 1 or w <= 0 or h <= 0:
		return []
	var stride := ((w + 31) / 32) * 4
	var xor_at := off + d.decode_u32(off) + 8  # after the header and the 2-colour palette
	var and_at := xor_at + stride * h
	if and_at + stride * h > d.size():
		return []
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row := h - 1 - y  # bottom-up
		for x in w:
			var bit := 7 - x % 8
			var a := (d[and_at + row * stride + x / 8] >> bit) & 1
			var c := (d[xor_at + row * stride + x / 8] >> bit) & 1
			img.set_pixel(x, y, Color(0, 0, 0, 0) if a == 1 and c == 0 else (Color.WHITE if a == 0 and c == 1 else Color.BLACK))
	return [img, hot]


## Arial, the original's text font (docs/front-end.md §4); Liberation Sans is metric-compatible.
static func arial(weight := 400, italic := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial", "Liberation Sans"])
	f.font_weight = weight
	f.font_italic = italic
	return f


## `--screenshot` runs: after `frames` more frames, saves what `node`'s viewport shows as a PNG and quits.
static func screenshot_and_quit(node: Node, path: String, frames := 0) -> void:
	for i in frames:
		await node.get_tree().process_frame
	node.get_viewport().get_texture().get_image().save_png(path)
	node.get_tree().quit()
