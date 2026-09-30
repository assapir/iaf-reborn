# Small image helpers shared by the menus.
extends RefCounted


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
