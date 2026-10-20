# Ours, the "Better cockpit" items aoa_indexer, standby_instruments and warning_lamps (Settings.better_cockpit_on;
# docs/cockpit.md "Better cockpit"): instruments the original leaves as static art, made live from the art itself.
# One node per cockpit with entries in INSTRUMENTS, a child of the cockpit covering it (cockpit.gd
# _update_instruments); it draws in the cockpit's own coordinates, over the panel and the HUD frame art.
#
# * aoa_indexer: the art paints all three symbols lit. The unlit ones are drawn again from a copy of the same art
#   with their colour taken out (a pixel keeps its darkest channel), so the symbol turns to the dark glass around it.
# * standby_instruments: a needle over a dial the art paints without one, in the style of the original needles.
# * warning_lamps: the art paints the lamps unlit. A lit lamp is its own art drawn brighter.
# * ar_nws_lights: the art paints no legend in the F-16's AR status indicator; the lit AR/NWS lamp is its green
#   legend drawn in the lamp's place.
# The values come from IafFlight.better_instruments (iaf_flight::instruments) via cockpit.state.better.
extends Control

## Per converted cockpit folder (measured on the art; panel px of the 1920-px strip, HUD art px for "HUD"):
## * aoa_indexer: `boxes` = the slow (upper chevron), on-speed (donut) and fast (lower chevron) symbols.
## * standby_instruments: `centre`, `r` (needle length), `scale` = [value, clock angle (deg, 0 = 12 o'clock,
##   clockwise)] pairs in increasing value, linear between them, held at the ends; `value` = the cockpit.state key.
## * warning_lamps: `state` = the key of cockpit.state.better that lights it, `quad` = the lamp's corners.
## * ar_nws_lights: `state` as warning_lamps, `rect` = the lamp's legend (HUD px).
const INSTRUMENTS := {
	"f16":
	[
		# The AoA indexer on the HUD frame, left of the glass (T.O. GR1F-16CJ-1 fig. 1-3 item 37).
		{"item": "aoa_indexer", "boxes": [Rect2(15, 120, 15, 13), Rect2(15, 138, 15, 14), Rect2(15, 156, 15, 13)]},
		# The right glareshield lamps (fig. 1-3 items 4, 6): FLCS (the upper half of the FLCS / DBU ON lamp) and
		# TO/LDG CONFIG. DBU ON and CANOPY stay unlit: the game has no backup mode or canopy state.
		{
			"item": "warning_lamps",
			"state": "flcs",
			"quad": [Vector2(1254.8, 97.3), Vector2(1260.5, 92.0), Vector2(1275.0, 105.0), Vector2(1268.0, 111.0)]
		},
		{
			"item": "warning_lamps",
			"state": "to_ldg_config",
			"quad": [Vector2(1263.0, 120.5), Vector2(1275.0, 110.0), Vector2(1289.0, 123.0), Vector2(1276.0, 134.0)]
		},
		# The AR status indicator on the HUD frame, right of the glass (fig. 1-3 item 3): RDY / AR/NWS / DISC lamps.
		# The art paints only its two orange brackets, no legends; AR/NWS (the middle lamp, green) is drawn as its
		# legend. RDY and DISC stay dark: the game has no air refuelling.
		{"item": "ar_nws_lights", "state": "ar_nws", "rect": Rect2(290.5, 135.0, 11.0, 18.0)},
	],
	"mirage":
	# The vertical speed indicator, upper left: 0 at 9 o'clock, climb clockwise, descent anticlockwise, the
	[
		# marks 0.5, 1, 2, 4, 6 (×1000 ft/min, inferred) both ways, 6 at 3 o'clock.
		{
			"item": "standby_instruments",
			"value": "vs_fpm",
			"centre": Vector2(686.0, 159.5),
			"r": 19.0,
			"scale":
			[
				[-6000, -270],
				[-4000, -225],
				[-2000, -184],
				[-1000, -156],
				[-500, -127],
				[0, -90],
				[500, -53],
				[1000, -24],
				[2000, 4],
				[4000, 45],
				[6000, 90]
			]
		},
	],
}
## The lit lamp's brightening (of the art's colours).
const LIT := Color(1.9, 1.7, 1.5)
## The original needles' colour (NeedleColor 0xFAF6EA).
const NEEDLE := Color8(234, 246, 250)

var cockpit: Control
var specs: Array = []
## What it showed in the last draw (for the tests): the lit indexer symbol (0 none / unlit, 1 slow, 2 on speed,
## 3 fast), each needle's angle (rad, clockwise from 12 o'clock; NAN while off), each lamp state -> lit.
var indexer := 0
var needles: Array = []
var lamps := {}
var _unlit: ImageTexture  # the HUD frame art with the indexer's symbols unlit
var _indexer_spec := {}


## The entries of a cockpit folder (e.g. "f16"); [] when none.
static func instruments(folder: String) -> Array:
	return INSTRUMENTS.get(folder.to_lower(), [])


func setup(c: Control, s: Array) -> void:
	cockpit = c
	specs = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for spec in s:
		if spec.item == "aoa_indexer":
			_unlit = unlit_art(spec.boxes)


## The HUD frame art (from its file, as compass.gd: the texture may hold no image) with the `boxes` (HUD px) turned
## to their darkest channel per pixel; null without the art.
func unlit_art(boxes: Array) -> ImageTexture:
	var file := String(cockpit.layout.get("HUD", {}).get("FileName", ""))
	var img := Image.load_from_file(cockpit.dir.path_join(file.get_basename().to_lower() + ".png"))
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var k := img.get_width() / float(cockpit.layout.HUD.Width)
	for b in boxes:
		var r := Rect2i(Rect2(b.position * k, b.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := img.get_pixel(x, y)
				var m := minf(c.r, minf(c.g, c.b))
				img.set_pixel(x, y, Color(m, m, m, c.a))
	return ImageTexture.create_from_image(img)


## The clock angle (deg) of `v` on a dial's `scale` (linear between its points, held at the ends).
static func dial_angle(scale: Array, v: float) -> float:
	if v <= float(scale[0][0]):
		return float(scale[0][1])
	for i in range(1, scale.size()):
		if v <= float(scale[i][0]):
			var a: Array = scale[i - 1]
			var b: Array = scale[i]
			return lerpf(float(a[1]), float(b[1]), (v - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(scale[-1][1])


## Reads the inputs (cockpit.state, the items' flags) and redraws; cockpit.gd calls it every frame.
func refresh() -> void:
	var better: Dictionary = cockpit.state.get("better", {})
	indexer = 0
	_indexer_spec = {}
	needles.clear()
	lamps.clear()
	for spec in specs:
		var on := Settings.better_cockpit_on(spec.item)
		match spec.item:
			"aoa_indexer":
				if on:
					_indexer_spec = spec
					indexer = int(better.get("aoa_index", 0))
			"standby_instruments":
				needles.append(
					deg_to_rad(dial_angle(spec.scale, float(cockpit.state.get(spec.value, 0.0)))) if on else NAN
				)
			"warning_lamps", "ar_nws_lights":
				if on:
					lamps[spec.state] = bool(better.get(spec.state, false))
	queue_redraw()


func _draw() -> void:
	var s: float = cockpit.ui_scale()
	_draw_unlit(s)
	var n := 0
	for spec in specs:
		match spec.item:
			"standby_instruments":
				var a: float = needles[n]
				n += 1
				if not is_nan(a):
					var c: Vector2 = cockpit.panel_to_screen(spec.centre.x, spec.centre.y)
					draw_line(
						c,
						c + Vector2(sin(a), -cos(a)) * float(spec.r) * s * 0.9,
						NEEDLE * cockpit._night_mod("PANEL"),
						maxf(1.0, 2.0 * s * 0.6),
						true
					)
			"warning_lamps":
				if lamps.get(spec.state, false):
					_draw_lamp(spec.quad, s)
			"ar_nws_lights":
				if lamps.get(spec.state, false):
					_draw_legend(spec.rect, ["AR", "NWS"], s)


## The indexer's unlit symbols, from the unlit copy of the HUD frame art (the art paints them lit).
func _draw_unlit(s: float) -> void:
	if _indexer_spec.is_empty() or _unlit == null:
		return
	var h: Dictionary = cockpit.layout.HUD
	var k := _unlit.get_width() / float(h.Width)  # art px per HUD px
	var tl := Vector2(size.x / 2 - float(h.Width) * s / 2, cockpit.panel_top() - float(h.Height) * s)
	for i in 3:
		if i + 1 != indexer:
			var b: Rect2 = _indexer_spec.boxes[i]
			draw_texture_rect_region(
				_unlit,
				Rect2(tl + b.position * s, b.size * s),
				Rect2(b.position * k, b.size * k),
				cockpit._night_mod("PANEL")
			)


## A lit legend lamp on the HUD frame: `lines` in green (the real NWS light's colour), filling `rect` (HUD px).
func _draw_legend(rect: Rect2, lines: Array, s: float) -> void:
	var h: Dictionary = cockpit.layout.HUD
	var tl := Vector2(size.x / 2 - float(h.Width) * s / 2, cockpit.panel_top() - float(h.Height) * s)
	var font: Font = cockpit.digits_font()
	var r := Rect2(tl + rect.position * s, rect.size * s)
	var lh := r.size.y / lines.size()
	var fs := maxi(int(lh), 1)
	for t in lines:  # the largest size whose every line fits the width
		while fs > 1 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x:
			fs -= 1
	var col: Color = Color8(70, 235, 100) * cockpit._night_mod("LIGHTSON")
	for i in lines.size():
		var base := r.position + Vector2(0, lh * i + (lh + fs * 0.7) / 2)
		draw_string(font, base, lines[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)


## A lit lamp: its quad of the panel art drawn brighter.
func _draw_lamp(quad: Array, s: float) -> void:
	var t: Texture2D = cockpit.tex.get("PANEL")
	if t == null:
		return
	var a: float = cockpit.layout.get("image_scale", 1)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for p in quad:
		pts.append(cockpit.panel_to_screen(p.x, p.y))
		uvs.append(Vector2(p) * a / Vector2(t.get_size()))
	var col: Color = LIT * cockpit._night_mod("LIGHTSON")
	draw_polygon(pts, PackedColorArray([col, col, col, col]), uvs, t)
