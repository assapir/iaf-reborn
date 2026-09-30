# HUD symbology, drawn crisp at screen resolution and clipped to the HUD glass.
# Conformal: pitch ladder and flight path marker are projected through the camera.
extends Control

var cockpit: Control
## Camera the world is rendered with; aircraft attitude comes from `cockpit.state`.
var camera: Camera3D
## World-space velocity direction (for the flight path marker); null = along the nose.
var velocity_dir: Variant = null


## The original HUD raster font (hud.fnt, 6x8), scaled with the cockpit.
var hud_font: FontFile


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_font = load_original_font("hud")


## Loads an original raster font converted by `iaf-convert fonts` (BMFont), scalable.
static func load_original_font(name: String) -> FontFile:
	var path := Settings.assets_dir().path_join("converted/fonts/%s.fnt" % name)
	var f := FontFile.new()
	if f.load_bitmap_font(path) != OK:
		return null
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	return f


func _layout() -> void:
	# The symbology field, from the HUD section (distances from the HUD centre).
	var h: Dictionary = cockpit.layout.HUD
	var s: float = cockpit.ui_scale()
	var centre := Vector2(cockpit.size.x / 2, cockpit.panel_top() - h.CenterY * s)
	position = centre - Vector2(h.LeftBorder, h.TopBorder) * s
	size = Vector2(h.LeftBorder + h.RightBorder, h.TopBorder + h.BottomBorder) * s


func _draw() -> void:
	if cockpit == null or cockpit.layout.is_empty():
		return
	_layout()
	var s: float = cockpit.ui_scale()
	var st: Dictionary = cockpit.state
	var font: Font = hud_font if hud_font != null else get_theme_default_font()
	var fs := int(8 * s)
	var w := maxf(1.0, 0.6 * s)
	var bore: Vector2 = cockpit.boresight() - position

	# Gun cross / boresight.
	draw_line(bore - Vector2(6, 0) * s, bore + Vector2(6, 0) * s, cockpit.hud_colour(), w)
	draw_line(bore - Vector2(0, 6) * s, bore + Vector2(0, 6) * s, cockpit.hud_colour(), w)

	if camera != null:
		_draw_ladder(st, s, w, font, fs)
		_draw_fpm(s, w)

	# Heading tape (top), speed (left), altitude (right), G / Mach.
	var top := 6.0 * s
	var hdg: float = fposmod(st.heading, 360.0)
	for d in range(-15, 16, 5):
		var mark := int(round(hdg / 5.0)) * 5 + d
		var x := size.x / 2 + (mark - hdg) * 3.0 * s
		var tall := 3.0 * s if mark % 10 == 0 else 1.5 * s
		draw_line(Vector2(x, top + 8 * s), Vector2(x, top + 8 * s + tall), cockpit.hud_colour(), w)
		if mark % 10 == 0:
			var label := "%02d" % int(fposmod(mark, 360) / 10)
			draw_string(font, Vector2(x - 4 * s, top + 6 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
	draw_string(font, Vector2(4 * s, size.y / 2), "%3d" % int(st.speed_kt), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
	draw_string(font, Vector2(size.x - 30 * s, size.y / 2), "%5d" % int(st.alt_ft), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
	draw_string(font, Vector2(4 * s, size.y - 14 * s), "G %.1f" % st.g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
	draw_string(font, Vector2(4 * s, size.y - 5 * s), "M %.2f" % st.mach, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())


func _project(dir: Vector3) -> Vector2:
	return camera.unproject_position(camera.global_position + dir * 1000.0) - position


## Pitch ladder: rungs every 5°, centred on the aircraft heading, rotated with the horizon.
func _draw_ladder(st: Dictionary, s: float, w: float, font: Font, fs: int) -> void:
	var yaw := deg_to_rad(-st.heading)
	var screen_roll := deg_to_rad(-st.roll)
	for e in range(-90, 91, 5):
		var el := deg_to_rad(e)
		var dir := Vector3(0, sin(el), -cos(el)).rotated(Vector3.UP, yaw)
		if camera.is_position_behind(camera.global_position + dir * 1000.0):
			continue
		var c := _project(dir)
		if c.y < -20 * s or c.y > size.y + 20 * s:
			continue
		var along := Vector2(cos(screen_roll), sin(screen_roll))
		var half := (18.0 if e == 0 else 10.0) * s
		var gap := 0.0 if e == 0 else 5.0 * s
		if e < 0:
			# Dashed negative rungs.
			for k in range(3):
				var a := gap + half * k / 3.0
				draw_line(c + along * a, c + along * (a + half / 6.0), cockpit.hud_colour(), w)
				draw_line(c - along * a, c - along * (a + half / 6.0), cockpit.hud_colour(), w)
		else:
			draw_line(c + along * gap, c + along * (gap + half), cockpit.hud_colour(), w)
			draw_line(c - along * gap, c - along * (gap + half), cockpit.hud_colour(), w)
		if e != 0:
			draw_string(font, c + along * (gap + half + 2 * s) + Vector2(0, 3 * s), str(abs(e)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())


func _draw_fpm(s: float, w: float) -> void:
	var dir: Vector3 = velocity_dir if velocity_dir != null else -camera.global_basis.z
	if camera.is_position_behind(camera.global_position + dir * 1000.0):
		return
	var p := _project(dir)
	var r := 3.0 * s
	draw_arc(p, r, 0, TAU, 16, cockpit.hud_colour(), w)
	draw_line(p + Vector2(r, 0), p + Vector2(r * 2.5, 0), cockpit.hud_colour(), w)
	draw_line(p - Vector2(r, 0), p - Vector2(r * 2.5, 0), cockpit.hud_colour(), w)
	draw_line(p - Vector2(0, r), p - Vector2(0, r * 2), cockpit.hud_colour(), w)


