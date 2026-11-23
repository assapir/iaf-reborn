# Ours: each jet's own tail number, drawn as decals from our digits (docs/aircraft-models.md §1.6). A model with
# numbers has them in `<model>.tail.json` beside it, and its texture holds none: the player's jet takes its `number`,
# every other jet its own from the list, never the player's (the user, 19 Nov 2026: "other planes shouold
# have different tale numbers").
#
# <model>.tail.json: {number: the player's jet's, others: [the other jets', real ones, in order], bases:
# {ICAO: [the numbers of the jets parked at that base, real ones of its own squadrons, in order]}, marks: [{foot:
# [y, z] the middle of the number's foot in the model's frame (m; y up, z aft), height: a digit's (m), pitch: from one
# digit to the next (m), x: [inner, outer] the decal's reach out from the centre plane on each side (m), colour:
# [r, g, b], digits: how many of the number's last digits (all if absent), atlas: the digits' atlas (DIGITS if
# absent)}], squadrons: [{squadron, tails: [its jets' numbers], marks: [the marks its jets wear instead]}]}; a mark
# with `art` (a picture's path) is a squadron's painted art in place of a number, its width from the picture's
# shape; each mark is drawn on both sides, a number reading front to back on the left, art mirrored on the right (the
# same paint seen from the other side): as decals, or, with `normal`, as quads (_quads).
extends RefCounted

const DIGITS := "res://shared/extra/models/tail_digits.png"  # tools/f16/digits.py: 0..9 in cells of equal width
## A number fades out from this far (m): a 0.4 m digit is under a pixel there.
const FADE := 1200.0

static var _atlases := {}  # atlas path -> Image
static var _arts := {}  # "art path L/R" -> ImageTexture (R: mirrored)
static var _specs := {}  # model path -> its tail.json ({} none), with "pool": the other jets' numbers
static var _textures := {}  # "number pitch/height atlas" -> ImageTexture
static var _taken := {}  # model path (or "model path ICAO": a base's own list) -> the jets numbered so far (next())
static var _ids := {}  # "model path id" -> its k: a jet numbered once keeps its number for the flight (next())


## A new flight: the other jets' numbers start again from the first.
static func reset() -> void:
	_taken.clear()
	_ids.clear()
	_textures.clear()
	_arts.clear()


## The next other jet's k on `model` in this flight (1, 2, … in the order the jets are made: the AI's, the mission's
## other units' and the parked ones alike), so no two jets show the same number while the list lasts. A jet parked at
## a base with its own list (`bases`, by ICAO `base`) takes that list's next instead, counted per base. A jet made
## again (a parked one when its base's furniture is built again) passes the same `id` and keeps its k.
static func next(model: String, id := "", base := "") -> int:
	var key := model.get_basename()
	var known := "%s %s" % [key, id]
	if id != "" and _ids.has(known):
		return _ids[known]
	var spec := _spec(model)
	var own: Array = spec.get("bases", {}).get(base, [])
	var count := key if own.is_empty() else "%s %s" % [key, base]
	var n := int(_taken.get(count, 0))
	_taken[count] = n + 1
	var k: int = n + 1 if own.is_empty() else spec.pool.find(String(own[n % own.size()])) + 1
	if id != "":
		_ids[known] = k
	return k


## The number of jet `k` on `model`: 0 the player's (`number`), k ≥ 1 the k-th other jet's ("" none).
static func number(model: String, k: int) -> String:
	var spec := _spec(model)
	if spec.is_empty():
		return ""
	var pool: Array = spec.pool
	# Past the list the numbers repeat: only real numbers are drawn (docs/aircraft-models.md §1.6).
	return String(spec.number) if k <= 0 or pool.is_empty() else String(pool[(k - 1) % pool.size()])


## The marks of jet `k` (number()) on `scene`, whose frame is the model's (its glTF instance, or the root frame that
## turns as the jet sits on its wheels): its number and, for a jet of a squadron with art, that art.
static func mark(scene: Node3D, model: String, k: int) -> void:
	var full := number(model, k)
	if full == "":
		return
	var marks := _marks(_spec(model), full)
	for i in marks.size():
		var m: Dictionary = marks[i]
		var art := String(m.get("art", ""))
		var h := float(m.height)
		var tex: Texture2D
		if art == "":
			tex = _texture(full.right(int(m.get("digits", full.length()))), float(m.pitch) / h, m.get("atlas", DIGITS))
		else:
			tex = _art(art, false)
		var w := h * tex.get_width() / tex.get_height()
		if m.has("normal"):
			_quads(scene, m, i, full, tex, Vector2(w, h))
			continue
		var x0 := float(m.x[0])
		var x1 := float(m.x[1])
		for side in [-1.0, 1.0]:
			var d := Decal.new()
			d.name = "tail_%s_%d%s" % ["number" if art == "" else "art", i, "L" if side < 0 else "R"]
			d.set_meta("tail", full)
			if art != "":
				d.set_meta("art", art)
			d.texture_albedo = tex if art == "" or side < 0 else _art(art, true)
			var c: Array = m.get("colour", [1, 1, 1])
			d.modulate = Color(c[0], c[1], c[2])
			d.size = Vector3(w, x1 - x0, h)
			d.upper_fade = 0.0
			d.lower_fade = 0.0
			d.normal_fade = 0.5  # only the faces looking out on its side: not the far side of the fin
			d.distance_fade_enabled = true
			d.distance_fade_begin = FADE
			d.distance_fade_length = FADE / 4
			var out := Vector3(side, 0, 0)
			var basis := Basis(out.cross(Vector3.DOWN), out, Vector3.DOWN)  # the texture's top up, read from outside
			d.transform = Transform3D(basis, Vector3(side * (x0 + x1) / 2, float(m.foot[0]) + h / 2, float(m.foot[1])))
			scene.add_child(d)


## Mark `m` on a face of one surface seen from both sides (the F-35I's thin fins: a decal would show on both, the
## far one mirrored): a quad on each side, 5 mm off the face (`foot` [x, y, z] on the left side, the face's outward
## `normal` [x, y] there; the right side its mirror image), seen from outside only.
static func _quads(scene: Node3D, m: Dictionary, i: int, full: String, tex: Texture2D, size: Vector2) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(m.colour[0], m.colour[1], m.colour[2])
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.roughness = 0.75
	mat.metallic = 0.15
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	for side in [-1.0, 1.0]:
		var n := Vector3(-side * float(m.normal[0]), float(m.normal[1]), 0).normalized()
		var along := Vector3(0, 0, -side)  # the texture's left to right: front to back on the left side
		var up := n.cross(along)
		var foot := Vector3(-side * float(m.foot[0]), float(m.foot[1]), float(m.foot[2]))
		var mi := MeshInstance3D.new()
		mi.name = "tail_number_%d%s" % [i, "L" if side < 0 else "R"]
		mi.set_meta("tail", full)
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = FADE
		mi.transform = Transform3D(Basis(along, up, n), foot + up * size.y / 2 + n * 0.005)
		scene.add_child(mi)


## The marks jet `full` wears: its squadron's (the `squadrons` entry whose `tails` hold its number), else the model's.
static func _marks(spec: Dictionary, full: String) -> Array:
	for sq: Dictionary in spec.get("squadrons", []):
		if full in sq.tails:
			return sq.marks
	return spec.get("marks", [])


## The art picture at `path` (ours, white or coloured on clear), mirrored left to right for the right side.
static func _art(path: String, mirrored: bool) -> ImageTexture:
	var key := "%s %s" % [path, "R" if mirrored else "L"]
	if not _arts.has(key):
		var img := Image.load_from_file(Settings.readable(path))
		img.convert(Image.FORMAT_RGBA8)
		img.fix_alpha_edges()  # its clear pixels take the paint's colour: no dark rim in the mipmaps
		if mirrored:
			img.flip_x()
		img.generate_mipmaps()
		_arts[key] = ImageTexture.create_from_image(img)
	return _arts[key]


static func _spec(model: String) -> Dictionary:
	var key := model.get_basename()
	if not _specs.has(key):
		var path := Settings.readable(key + ".tail.json")
		var v = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var spec: Dictionary = v if v is Dictionary else {}
		if not spec.is_empty():
			var pool: Array = spec.get("others", []).duplicate()
			for own: Array in spec.get("bases", {}).values():
				for s in own:
					if not s in pool:
						pool.append(s)
			spec.pool = pool
		_specs[key] = spec
	return _specs[key]


## `number` in our digits (the atlas at `atlas`), `pitch` (from one digit to the next) in digit heights apart: white,
## the strokes' alpha.
static func _texture(number: String, pitch: float, atlas: String) -> ImageTexture:
	var key := "%s %.3f %s" % [number, pitch, atlas]
	if _textures.has(key):
		return _textures[key]
	if not _atlases.has(atlas):
		var a := Image.load_from_file(Settings.readable(atlas))
		a.convert(Image.FORMAT_RGBA8)
		_atlases[atlas] = a
	var at: Image = _atlases[atlas]
	var ch := at.get_height()
	var cw := at.get_width() / 10
	var step := roundi(pitch * ch)
	var img := Image.create_empty(step * (number.length() - 1) + cw, ch, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))  # clear white: the strokes' edges and the far mipmaps stay white, not darkened
	for i in number.length():
		var n := number.unicode_at(i) - 48
		img.blend_rect(at, Rect2i(n * cw, 0, cw, ch), Vector2i(i * step, 0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex
