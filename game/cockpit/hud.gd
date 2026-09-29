# HUD symbology, drawn crisp at screen resolution and clipped to the HUD glass.
# Conformal: pitch ladder and flight path marker are projected through the camera.
extends Control

var cockpit: Control
## Camera the world is rendered with; aircraft attitude comes from `cockpit.state`.
var camera: Camera3D
## World-space velocity direction (for the flight path marker); null = along the nose.
var velocity_dir: Variant = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	var font := get_theme_default_font()
	var fs := int(7 * s)
	var w := maxf(1.0, 0.6 * s)
	var bore: Vector2 = cockpit.boresight() - position

	# Gun cross / boresight.
	draw_line(bore - Vector2(6, 0) * s, bore + Vector2(6, 0) * s, HUD_GREEN, w)
	draw_line(bore - Vector2(0, 6) * s, bore + Vector2(0, 6) * s, HUD_GREEN, w)

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
		draw_line(Vector2(x, top + 8 * s), Vector2(x, top + 8 * s + tall), HUD_GREEN, w)
		if mark % 10 == 0:
			var label := "%02d" % int(fposmod(mark, 360) / 10)
			draw_string(font, Vector2(x - 4 * s, top + 6 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUD_GREEN)
	draw_string(font, Vector2(4 * s, size.y / 2), "%3d" % int(st.speed_kt), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUD_GREEN)
	draw_string(font, Vector2(size.x - 30 * s, size.y / 2), "%5d" % int(st.alt_ft), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUD_GREEN)
	draw_string(font, Vector2(4 * s, size.y - 14 * s), "G %.1f" % st.g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUD_GREEN)
	draw_string(font, Vector2(4 * s, size.y - 5 * s), "M %.2f" % st.mach, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUD_GREEN)


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
				draw_line(c + along * a, c + along * (a + half / 6.0), HUD_GREEN, w)
				draw_line(c - along * a, c - along * (a + half / 6.0), HUD_GREEN, w)
		else:
			draw_line(c + along * gap, c + along * (gap + half), HUD_GREEN, w)
			draw_line(c - along * gap, c - along * (gap + half), HUD_GREEN, w)
		if e != 0:
			draw_string(font, c + along * (gap + half + 2 * s) + Vector2(0, 3 * s), str(abs(e)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HUD_GREEN)


func _draw_fpm(s: float, w: float) -> void:
	var dir: Vector3 = velocity_dir if velocity_dir != null else -camera.global_basis.z
	if camera.is_position_behind(camera.global_position + dir * 1000.0):
		return
	var p := _project(dir)
	var r := 3.0 * s
	draw_arc(p, r, 0, TAU, 16, HUD_GREEN, w)
	draw_line(p + Vector2(r, 0), p + Vector2(r * 2.5, 0), HUD_GREEN, w)
	draw_line(p - Vector2(r, 0), p - Vector2(r * 2.5, 0), HUD_GREEN, w)
	draw_line(p - Vector2(0, r), p - Vector2(0, r * 2), HUD_GREEN, w)


const HUD_GREEN := Color(0.3, 1.0, 0.45)
