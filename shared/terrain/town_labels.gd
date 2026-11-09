# Ours (Settings.town_labels; docs/scenery.md §3.5): the towns' names over the view at their places, as the Epic Fury
# reference's "שוהם" (look study proposal 3). The cities and towns of the theatre's
# places.json (`iaf-sim scenery`, the original's scenery step; [{kind, en, he, x, y}] in the theatre's frame) within
# RANGE_M are projected through the camera each frame and drawn in the UI font (Settings.display_font("ui")), in the
# game's language, fading out toward RANGE_M. A label that would overlap one already placed is left out, the cities
# first, then the nearer.
# Drawn on a canvas layer under the cockpit's (the HUD and the 2D panel over it). A label whose place is under the 2D
# panel's top is left out whole. The 3D cockpit drawn about the origin (cockpit_origin.gd) masks it per pixel by its
# picture's alpha (the panel and the canopy frame hide it, the glass lets it through).
extends Control

## The labels' range (m) and where they start to fade.
const RANGE_M := 25000.0
const FADE_M := 15000.0
const RESELECT_MS := 500
## Text sizes at a 1080-pixel-high view: cities, towns.
const SIZES := [17, 14]
const KINDS := ["city", "town"]
## The text a little above the place.
const LIFT_PX := 4.0
const COLOUR := Color(1, 1, 1, 0.92)
## A dark edge keeps the name legible over the desert's light sand.
const SHADOW := Color(0, 0, 0, 0.6)
const MASK_SHADER := """
shader_type canvas_item;
uniform sampler2D cockpit : filter_nearest;
uniform bool masked = false;
void fragment() {
	if (masked) {
		COLOR.a *= 1.0 - clamp(texture(cockpit, SCREEN_UV).a, 0.0, 1.0);
	}
}
"""

## The flight scene (terrain_view.gd): its terrain, camera, cockpit and cockpit_origin.
var host: Node
## [{"w" Vector2 the engine's world x / y, "name", "rank" 0 city / 1 town, "h" its ground height or null; "at" its
## scene position once in range}].
var places: Array[Dictionary] = []
## The labels placed this frame: [[name, screen point, size, alpha, width]] (tests read it).
var shown: Array = []
var _font: Font
var _near: Array[Dictionary] = []
var _near_t := -INF
var _masked := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Settings.display_font("ui")
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = MASK_SHADER
	material = mat
	if places.is_empty():
		places = load_places(Settings.converted(Settings.theatre_dir().path_join("places.json")))


## The cities and towns of a places.json, in the game's language.
static func load_places(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not list is Array:
		return out
	var key := "he" if Settings.language == "he" else "en"
	for p in list:
		var rank := KINDS.find(p.get("kind", ""))
		if rank >= 0:
			out.append({"w": Vector2(p.x, p.y), "name": str(p.get(key, p.en)), "rank": rank, "h": null})
	return out


static func available() -> bool:
	return Settings.has_converted(Settings.theatre_dir().path_join("places.json"))


func _process(_delta: float) -> void:
	shown.clear()
	var cam := get_viewport().get_camera_3d()
	if host == null or cam == null or places.is_empty():
		queue_redraw()
		return
	var origin = host.cockpit_origin
	# The 3D cockpit's view: masked by its picture while cockpit_origin.gd draws it (its composite quad shown).
	var c3d: bool = (
		host.cockpit_3d != null
		and host.own_bc != null
		and host.own_bc.visible
		and (origin == null or origin._quad.visible)
	)
	# ponytail: the original's 3D cockpit in the flight's world has no picture to mask by: no labels in its view.
	if c3d and origin == null:
		queue_redraw()
		return
	if c3d != _masked:
		_masked = c3d
		material.set_shader_parameter("masked", c3d)
		if c3d:
			material.set_shader_parameter("cockpit", origin.viewport.get_texture())
	var panel_y: float = INF
	if not c3d and host.in_cockpit and host.cockpit.visible and host.cockpit.view_mode == 0:
		panel_y = host.cockpit.panel_top() + host.cockpit.position.y  # the panel moves with the head pan
	var eye := cam.global_position
	# The places in range with their scene positions, chosen again every RESELECT_MS (the jet flies a few hundred
	# metres meanwhile; the world origin stays put for the flight).
	var now := Time.get_ticks_msec()
	if now - _near_t > RESELECT_MS:
		_near_t = now
		_near.clear()
		var o: Vector2 = host.terrain.world_origin
		for p in places:
			var at := Vector3(p.w.x - o.x, 0.0, o.y - p.w.y)
			if Vector2(at.x - eye.x, at.z - eye.z).length_squared() < (RANGE_M + 2000.0) ** 2:
				if p.h == null:
					p.h = host.terrain.height_at(at)
				at.y = p.h if p.h != null else 0.0
				p.at = at
				_near.append(p)
	var view := get_viewport_rect()
	var k := view.size.y / 1080.0
	var cand := []
	for p in _near:
		var at: Vector3 = p.at
		var d := Vector2(at.x - eye.x, at.z - eye.z).length()
		if d > RANGE_M or cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		if not view.has_point(s) or s.y >= panel_y:
			continue
		cand.append([p.rank, d, p, s])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
	var taken: Array[Rect2] = []
	for c in cand:
		var p: Dictionary = c[2]
		var size := int(round(SIZES[c[0]] * k))
		if p.get("size") != size:  # the text's width, measured again only when the view's height changes
			p.size = size
			p.width = _font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var r := Rect2(c[3].x - p.width / 2.0, c[3].y - LIFT_PX * k - size, p.width, size).grow(2.0 * k)
		if taken.any(func(t: Rect2) -> bool: return t.intersects(r)):
			continue
		taken.append(r)
		shown.append([p.name, c[3], size, clampf((RANGE_M - c[1]) / (RANGE_M - FADE_M), 0.0, 1.0), p.width])
	queue_redraw()


func _draw() -> void:
	var k := get_viewport_rect().size.y / 1080.0
	for l in shown:
		var size: int = l[2]
		var at := Vector2(l[1].x - l[4] / 2.0, l[1].y - LIFT_PX * k)
		var edge := int(round(maxf(3.0 * k, 1.0)))
		draw_string_outline(_font, at, l[0], 0, -1, size, edge, SHADOW * Color(1, 1, 1, l[3]))
		draw_string(_font, at, l[0], 0, -1, size, COLOUR * Color(1, 1, 1, l[3]))
