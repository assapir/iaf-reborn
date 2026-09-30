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
