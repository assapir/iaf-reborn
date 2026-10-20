# Ours, the "Better cockpit" item turning_compass (Settings.better_cockpit_on; docs/cockpit.md "Turning compass /
# HSI"): a panel compass card that turns with the heading, cut from the panel art itself. In the original every
# panel compass is static art. One node per instrument, a child of the cockpit (cockpit.gd _update_compasses).
#
# The card is a disc of the panel art, turned by the heading in compass.gdshader, so the heading reads under the
# lubber line at the top. The middle (the face with its aircraft symbol) stays as painted. A dial whose pointers
# are painted on the card (the Mirage's) gets them erased from the card and drawn new: the bearing pointer to the
# current waypoint and the course pointer of the route leg.
extends Control

## Per converted cockpit folder, its compass instruments, in panel px of the 1920-px strip (measured on the art):
## * centre, r: the card's centre and outer radius; hub: the radius inside which the art stays as painted.
## * from: [cockpit folder, centre, r] of another cockpit's art of the same dial, used as the card where the own
##   art is cut off by the panel's bottom edge.
## * erase: the pointers painted on the card, [tail, tip, half width] (panel px). Their pixels take the card 30°
##   aside (the ticks and the numbers repeat every 30°), else `face`.
## * pointers: draw the bearing / course pointers (with `pointer`, `hub_colour`, `hub_r`).
## The F-15, F-16, F-4 2000, Lavi and MiG-29 panels show no compass.
const INSTRUMENTS := {
	# The Kfir's compass (bottom centre): the card ring turns, the face with the aircraft symbol stays.
	"cfir": [{"centre": Vector2(964.0, 302.0), "r": 33.0, "hub": 21.0}],
	# The F-4E's has the same dial, cut off below the panel's edge: the Kfir's card.
	"phantom":
	[{"centre": Vector2(959.2, 347.6), "r": 32.6, "hub": 20.7, "from": ["cfir", Vector2(964.0, 302.0), 33.0]}],
	"mirage":
	[
		# The Mirage's bearing-distance-heading dial (right of the HUD): the card with two painted pointers.
		{
			"centre": Vector2(1109.7, 152.8),
			"r": 33.5,
			"hub": 0.0,
			"face": Color8(14, 14, 16),
			"erase":
			[
				[Vector2(1080.0, 146.8), Vector2(1136.5, 157.8), 2.3],
				[Vector2(1102.5, 177.5), Vector2(1115.2, 123.6), 4.8]
			],
			"pointers": true,
			"pointer": Color8(226, 224, 214),
			"hub_colour": Color8(118, 120, 122),
			"hub_r": 2.4
		}
	],
	# The MiG-23's ПНП (HSI, under the ADI): the card ring turns; the face with the aircraft symbol and the К / Г bars
	# stays. The course arrow's head and tail and the lubber triangle are painted on the card: erased from it.
	"mig23":
	[
		{
			"centre": Vector2(826.0, 228.3),
			"r": 33.0,
			"hub": 16.0,
			"face": Color8(8, 8, 10),
			"erase":
			[[Vector2(826.0, 195.0), Vector2(826.0, 212.0), 2.0], [Vector2(826.0, 244.5), Vector2(826.0, 261.5), 2.0]]
		}
	],
}

var cockpit: Control
var spec: Dictionary
## The card turn (rad, clockwise = the heading); the bearing / course pointers' angles on the dial (rad).
var angle := 0.0
var bearing := 0.0
var course := 0.0
var _card: ImageTexture
var _needles: Control


## The instruments of a cockpit folder (e.g. "cfir"); [] when its panel has none.
static func instruments(folder: String) -> Array:
	return INSTRUMENTS.get(folder.to_lower(), [])


func setup(c: Control, s: Dictionary) -> void:
	cockpit = c
	spec = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material = ShaderMaterial.new()
	material.shader = preload("res://cockpit/compass.gdshader")
	material.set_shader_parameter("hub", float(s.hub) / float(s.r))
	_card = ImageTexture.create_from_image(card_image())
	if s.get("pointers", false):
		_needles = Control.new()
		_needles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_needles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_needles.draw.connect(_draw_pointers)
		add_child(_needles)


## The card: the disc of the panel art (or `from`'s) around the centre, the painted pointers erased; mipmapped.
func card_image() -> Image:
	var a: float = cockpit.layout.get("image_scale", 1)
	var centre: Vector2 = spec.centre
	var r: float = spec.r
	var folder: String = cockpit.dir
	if spec.has("from"):
		folder = Settings.assets_dir().path_join("converted/cockpits").path_join(spec.from[0])
		a = float(Settings.load_json(folder.path_join("cockpit.json")).get("image_scale", 1))
		centre = spec.from[1]
		r = spec.from[2]
	# The panel art from its file (the cockpit's texture may hold no image: headless, mipmaps).
	var file := String(Settings.load_json(folder.path_join("cockpit.json")).get("PANEL", {}).get("FileName", ""))
	var src := Image.load_from_file(folder.path_join(file.get_basename().to_lower() + ".png"))
	var n := int(round(r * a)) * 2
	var o := Vector2i((centre * a).round()) - Vector2i(n / 2, n / 2)
	var img := src.get_region(Rect2i(o, Vector2i(n, n)))
	img.convert(Image.FORMAT_RGBA8)
	var erase: Array = spec.get("erase", [])
	if not erase.is_empty():
		var out := img.duplicate()
		var face: Color = spec.get("face", Color.BLACK)
		for y in n:
			for x in n:
				var p := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(n, n) / 2.0) / a
				if not _on_pointer(p, erase):
					continue
				var c := face
				for k in [1, -1, 2, -2, 3, -3]:
					var q := p.rotated(deg_to_rad(30.0 * k))
					if not _on_pointer(q, erase):
						var at := Vector2i((q * a + Vector2(n, n) / 2.0).floor())
						if Rect2i(0, 0, n, n).has_point(at):
							c = img.get_pixelv(at)
						break
				out.set_pixel(x, y, c)
		img = out
	img.generate_mipmaps()
	return img


## True when the centre-relative panel point `p` lies on one of the painted pointers ([tail, tip, half width],
## absolute panel px; the card's centre is spec.centre).
func _on_pointer(p: Vector2, erase: Array) -> bool:
	var at: Vector2 = p + Vector2(spec.centre)
	for e in erase:
		var t: Vector2 = Geometry2D.get_closest_point_to_segment(at, e[0], e[1])
		if t.distance_to(at) <= float(e[2]):
			return true
	return false


## Places the node over its dial (panel px → the cockpit's canvas) and turns the card to the heading; the pointers
## to the current waypoint's bearing and the leg's course (degrees clockwise from north).
func update(heading_deg: float, bearing_deg: float, course_deg: float) -> void:
	var s: float = cockpit.ui_scale()
	var a: float = cockpit.layout.get("image_scale", 1)
	# The same rounding as card_image (the card's square on whole art px), so the still card covers the art exactly.
	var r := float(int(round(float(spec.r) * a))) / a
	var tl: Vector2 = cockpit.panel_to_screen(spec.centre.x, spec.centre.y) - Vector2(r, r) * s
	position = tl
	size = Vector2(2 * r, 2 * r) * s
	angle = deg_to_rad(heading_deg)
	bearing = deg_to_rad(bearing_deg - heading_deg)
	course = deg_to_rad(course_deg - heading_deg)
	material.set_shader_parameter("angle", angle)
	modulate = cockpit._night_mod("PANEL")
	queue_redraw()
	if _needles != null:
		_needles.queue_redraw()


func _draw() -> void:
	draw_texture_rect(_card, Rect2(Vector2.ZERO, size), false)


## The Mirage dial's pointers (new art in the painted ones' style): the course needle (single, pointed at its head)
## and the bearing pointer (two bars joined by an arrowhead), with the hub over them.
func _draw_pointers() -> void:
	var k := size.x / (2.0 * float(spec.r))  # canvas px per panel px
	var c := size / 2.0
	var col: Color = spec.pointer
	var dir := Vector2(sin(course), -cos(course))
	var side := Vector2(-dir.y, dir.x)
	_needles.draw_colored_polygon(
		PackedVector2Array(
			[
				c + dir * 29.5 * k,
				c + (dir * 25.0 + side * 0.7) * k,
				c + (-dir * 28.5 + side * 0.7) * k,
				c + (-dir * 28.5 - side * 0.7) * k,
				c + (dir * 25.0 - side * 0.7) * k
			]
		),
		col
	)
	dir = Vector2(sin(bearing), -cos(bearing))
	side = Vector2(-dir.y, dir.x)
	for sgn in [-1.0, 1.0]:
		var off: Vector2 = side * sgn * 1.9 * k
		_needles.draw_line(c - dir * 26.0 * k + off, c + dir * 20.0 * k + off, col, 1.0 * k, true)
	_needles.draw_colored_polygon(
		PackedVector2Array(
			[c + dir * 29.0 * k, c + dir * 20.0 * k + side * 3.3 * k, c + dir * 20.0 * k - side * 3.3 * k]
		),
		col
	)
	_needles.draw_circle(c, float(spec.hub_r) * k, spec.hub_colour, true, -1.0, true)
