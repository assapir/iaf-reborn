# The original 2D F-16 cockpit, laid out from the converted cockpit.ibx (cockpit.json).
#
# All layout values are in the original 640x480 screen space; we scale by
# screen height / 480 and centre the 1920 px panel strip, so wide screens show
# more of the strip instead of stretching it.
#
# Draw order matters: instruments that sit behind the panel's transparent holes
# (attitude ball, tapes) are drawn first, the panel on top, then needles, text
# and the HUD.
extends Control

const ORIGINAL_HEIGHT := 480.0
const PANEL_CENTRE_X := 960.0
const HUD_GREEN := Color(0.3, 1.0, 0.45)

@export var cockpit_dir := "../assets/converted/cockpits/f16"

## Flight state shown by the instruments. Angles in degrees, speed in knots,
## altitude in feet, vertical speed in ft/min, fuel in lbs, rpm/throttle 0..1.
var state := {
	"speed_kt": 0.0, "mach": 0.0, "alt_ft": 0.0, "vs_fpm": 0.0,
	"pitch": 0.0, "roll": 0.0, "heading": 0.0, "aoa": 0.0, "g": 1.0,
	"rpm": 0.0, "throttle": 0.0, "fuel_lbs": 0.0,
}
## Look down at the full panel (the original's "panel down" view) instead of the forward view.
var view_down := false
## 1.0 = the original proportions (640x480 scaled to the screen); smaller shows more world.
var zoom := 0.75
const ZOOM_MIN := 0.45
const ZOOM_MAX := 1.0

var layout := {}
var tex := {}
var dir := ""
@onready var hud: Control = $Hud


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dir = ProjectSettings.globalize_path("res://").path_join(cockpit_dir).simplify_path()
	var text := FileAccess.get_file_as_string(dir.path_join("cockpit.json"))
	if text.is_empty():
		push_error("cockpit: %s/cockpit.json not found — run iaf-convert cockpit" % dir)
		return
	layout = JSON.parse_string(text)
	for key in ["PANEL", "HUD", "LENHORIZON", "PANELVARIO", "PANELAOA"]:
		var file: String = layout.get(key, {}).get("FileName", "")
		if file != "":
			var img := Image.load_from_file(dir.path_join(file.get_basename().to_lower() + ".png"))
			if img != null:
				img.generate_mipmaps()
				tex[key] = ImageTexture.create_from_image(img)
	hud.cockpit = self


## Screen scale factor from the original 640x480 layout.
func ui_scale() -> float:
	return size.y / ORIGINAL_HEIGHT * zoom


## Vertical field of view for the 3D world: the original framing at zoom 1, wider when zoomed out
## (the panel covers less of the screen, so the world gets more of it).
func world_fov(base_fov: float) -> float:
	var half := deg_to_rad(base_fov) / 2.0
	return rad_to_deg(2.0 * atan(tan(half) / zoom))


## Top of the panel in screen pixels. The forward view shows only the top part of the
## panel (pushed down by MainOffsetY, like the original); the down view shows all of it.
func panel_top() -> float:
	var p: Dictionary = layout.get("PANEL", {})
	var height: float = p.get("PanelHeight", 352)
	var shown: float = height if view_down else height - p.get("MainOffsetY", 190)
	return size.y - shown * ui_scale()


## Panel-space point (original pixels) to screen.
func panel_to_screen(x: float, y: float) -> Vector2:
	var s := ui_scale()
	return Vector2(size.x / 2 + (x - PANEL_CENTRE_X) * s, panel_top() + y * s)


## Screen position of the HUD boresight (where the aircraft nose points).
func boresight() -> Vector2:
	var h: Dictionary = layout.get("HUD", {})
	return Vector2(size.x / 2, panel_top() - h.get("BorePositionY", 135) * ui_scale())


## Camera pitch-down (radians) that puts the aircraft's nose axis on the boresight.
func camera_pitch_offset(vertical_fov_deg: float) -> float:
	var f := (size.y / 2) / tan(deg_to_rad(vertical_fov_deg) / 2)
	return atan((size.y / 2 - boresight().y) / f)


func _process(_delta: float) -> void:
	queue_redraw()
	hud.queue_redraw()


func _draw() -> void:
	if layout.is_empty():
		return
	var s := ui_scale()
	_draw_adi(s)
	_draw_standby_horizon(s)
	_draw_tape("PANELVARIO", clamp(state.vs_fpm / 6000.0, -1.0, 1.0), s)
	_draw_tape("PANELAOA", clamp(state.aoa / 32.0, 0.0, 1.0) * 2.0 - 1.0, s)

	var p: Dictionary = layout.PANEL
	if tex.has("PANEL"):
		var tl := panel_to_screen(0, 0)
		var art_scale: float = layout.get("image_scale", 1)
		var width: float = tex.PANEL.get_width() / art_scale
		draw_texture_rect(tex.PANEL, Rect2(tl, Vector2(width, p.PanelHeight) * s), false)

	_draw_needle("SPEEDCLOCK", state.speed_kt, s)
	_draw_needle("ALTITUDELOCK", state.alt_ft, s)
	_draw_needle("RPMCLOCK", state.rpm, s)
	_draw_needle("THROTTLECLOCK", state.throttle, s)
	_draw_needle("TEMPCLOCK", lerp(0.25, 0.7, state.rpm), s)
	var fuel: Dictionary = layout.get("FUELDIGITAL", {})
	if fuel.get("Active", 0) == 1:
		var col := Color8(int(fuel.ColorR), int(fuel.ColorG), int(fuel.ColorB))
		draw_string(get_theme_default_font(), panel_to_screen(fuel.OffsetX, fuel.OffsetY + 8), "%05d" % int(state.fuel_lbs),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * s), col)

	if tex.has("HUD"):
		var h: Dictionary = layout.HUD
		var w: float = h.Width * s
		var hh: float = h.Height * s
		draw_texture_rect(tex.HUD, Rect2(size.x / 2 - w / 2, panel_top() - hh, w, hh), false)


## Attitude ball: drawn under the panel's round hole, rolled and shifted by pitch.
func _draw_adi(s: float) -> void:
	var a: Dictionary = layout.get("LENHORIZON", {})
	if a.get("Active", 0) != 1 or not tex.has("LENHORIZON"):
		return
	var centre := panel_to_screen(a.CenterX, a.CenterY)
	var r: float = a.Radius * s * 1.15
	var t: Texture2D = tex.LENHORIZON
	var px_per_deg: float = t.get_height() / 128.0 * a.Radius / a.Factor
	var src_centre := Vector2(t.get_width() / 2.0, t.get_height() / 2.0 - state.pitch * px_per_deg)
	var src_half := r / s * t.get_height() / 128.0
	draw_set_transform(centre, deg_to_rad(-state.roll))
	draw_texture_rect_region(t, Rect2(-r, -r, 2 * r, 2 * r), Rect2(src_centre - Vector2(src_half, src_half), Vector2(2 * src_half, 2 * src_half)))
	draw_set_transform(Vector2.ZERO)


## Small standby attitude indicator, drawn by the game in two flat colours (HORIZON).
func _draw_standby_horizon(s: float) -> void:
	var h: Dictionary = layout.get("HORIZON", {})
	if h.is_empty() or h.get("OnMfd", 0) != 0:
		return
	var centre := panel_to_screen(h.ClockCenterX, h.ClockCenterY)
	var r: float = h.Radius * s * 1.1
	var sky := _colorref(int(h.SkyColor))
	var ground := _colorref(int(h.GndColor))
	var offset: float = clamp(state.pitch / 90.0, -1.0, 1.0) * r * float(h.get("Scale", 1.0))
	draw_set_transform(centre, deg_to_rad(-state.roll))
	# Chords of the disc: sky above the (pitch-shifted) horizon, ground below.
	var y := -r
	while y < r:
		var half := sqrt(max(r * r - y * y, 0.0))
		draw_line(Vector2(-half, y), Vector2(half, y), sky if y < offset else ground, 1.0)
		y += 1.0
	draw_set_transform(Vector2.ZERO)


func _colorref(c: int) -> Color:
	# Win32 COLORREF is 0x00BBGGRR.
	return Color8(c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff)


## Vertical tape (vario / AOA) behind a panel window; `value` in -1..1 scrolls it.
func _draw_tape(key: String, value: float, s: float) -> void:
	var t: Dictionary = layout.get(key, {})
	if t.get("Active", 0) != 1 or not tex.has(key):
		return
	var tx: Texture2D = tex[key]
	var k := tx.get_height() / float(t.Height)
	var window: float = t.PanelHeight
	var src_y: float = (t.Height - window) / 2.0 * (1.0 - value)
	draw_texture_rect_region(tx, Rect2(panel_to_screen(t.OffsetX, t.OffsetY), Vector2(t.Width, window) * s),
			Rect2(0, src_y * k, t.Width * k, window * k))


func _draw_needle(key: String, value: float, s: float) -> void:
	var g: Dictionary = layout.get(key, {})
	if g.get("Active", 0) != 1:
		return
	var c := panel_to_screen(g.OffsetX, g.OffsetY)
	var angle: float = g.AngleOffset + value / g.FullClock * TAU
	var tip: Vector2 = c + Vector2(cos(angle), sin(angle)) * float(g.Radius) * s * 0.9
	var col := _colorref(int(g.NeedleColor))
	draw_line(c, tip, col, max(1.0, g.NeedleWidth * s * 0.6), true)
