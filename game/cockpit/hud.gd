# HUD symbology, drawn crisp at screen resolution and clipped to the HUD glass (docs/cockpit.md §HUD).
# v1.1 (FUN_00538c90, producer in FUN_00448b20): the flight path marker is the perspective projection of
# the velocity vector; the pitch ladder hangs off the marker at 12 px/deg (5° rungs, rolled with the jet).
# The conformal ladder (projected through the camera) is our option (Extras > HUD pitch ladder).
extends Control

## v1.1 ladder scale (original 640x480 pixels per degree) and rungs drawn: ±15° around the marker.
const LADDER_PX_PER_DEG := 12.0
const LADDER_RUNGS := 7
## GunRetPositionY of the five cockpits v1.1 lowered by 10 px (docs/v1.1.md "Data files"): with v1.0
## cockpit data the v1.1 value is used, so the cross sits on the v1.1 bullet line.
const GUN_RET_V10 := {"cfir": 170.0, "f15": 170.0, "f16": 150.0, "f4-2000": 155.0, "mirage": 130.0}
const GUN_RET_V11_SHIFT := -10.0

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
	var gun: Vector2 = gun_cross() - position

	# Gun cross (MainOffsetY − GunRetPositionY + panel pan, as the original).
	draw_line(gun - Vector2(6, 0) * s, gun + Vector2(6, 0) * s, cockpit.hud_colour(), w)
	draw_line(gun - Vector2(0, 6) * s, gun + Vector2(0, 6) * s, cockpit.hud_colour(), w)

	if camera != null:
		var fpm = _fpm_position()
		if Settings.hud_ladder == "conformal":
			_draw_conformal_ladder(st, s, w, font, fs)
		elif fpm != null:
			_draw_ladder(fpm, st, s, w, font, fs)
		if fpm != null:
			_draw_fpm(fpm, s, w)

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


## The gun cross in screen pixels: GunRetPositionY above the panel top, on the centre line. v1.0
## cockpit data (the value v1.0 shipped) gets v1.1's −10 px.
func gun_cross() -> Vector2:
	var h: Dictionary = cockpit.layout.get("HUD", {})
	var y: float = h.get("GunRetPositionY", h.get("BorePositionY", 135))
	if GUN_RET_V10.get(cockpit.cockpit_dir.get_file(), -1.0) == y:
		y += GUN_RET_V11_SHIFT
	return Vector2(cockpit.size.x / 2, cockpit.panel_top() - y * cockpit.ui_scale())


## Flight path marker (HUD coordinates): the velocity vector projected through the camera (v1.1:
## pos + 200·dir perspective-projected into S+0x1c/0x20); null when behind the eye.
func _fpm_position() -> Variant:
	var dir: Vector3 = velocity_dir if velocity_dir != null else -camera.global_basis.z
	if camera.is_position_behind(camera.global_position + dir * 1000.0):
		return null
	return _project(dir)


## v1.1 pitch ladder (FUN_00538c90): the rung of the flight path angle γ passes through the marker,
## rung e sits (e − γ)·12 px above it along the rolled vertical; the 7 rungs from ⌊γ⌋₅ + 15° down to
## ⌊γ⌋₅ − 15°, a label on every 10° rung but the horizon.
func _draw_ladder(fpm: Vector2, st: Dictionary, s: float, w: float, font: Font, fs: int) -> void:
	var dir: Vector3 = velocity_dir if velocity_dir != null else -camera.global_basis.z
	var gamma := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	var roll := deg_to_rad(-st.roll)
	var along := Vector2(cos(roll), sin(roll))
	for r in ladder_rungs(fpm, gamma, st.roll, s):
		_draw_rung(r[1], along, r[0], s, w, font, fs)


## The v1.1 ladder's rungs [[angle °, centre]] for the marker at `fpm`, flight path angle `gamma` and
## roll `roll_deg` (right wing down positive), at ui scale `s`.
static func ladder_rungs(fpm: Vector2, gamma: float, roll_deg: float, s: float) -> Array:
	var roll := deg_to_rad(-roll_deg)
	var up := Vector2(sin(roll), -cos(roll))
	var top := int(floor(gamma / 5.0)) * 5 + 15
	var out := []
	for k in LADDER_RUNGS:
		var e := top - 5 * k
		if absi(e) <= 90:
			out.append([e, fpm + up * (e - gamma) * LADDER_PX_PER_DEG * s])
	return out


## Our conformal ladder: rungs every 5° projected through the camera, rotated with the horizon.
func _draw_conformal_ladder(st: Dictionary, s: float, w: float, font: Font, fs: int) -> void:
	var yaw := deg_to_rad(-st.heading)
	var screen_roll := deg_to_rad(-st.roll)
	var along := Vector2(cos(screen_roll), sin(screen_roll))
	for e in range(-90, 91, 5):
		var el := deg_to_rad(e)
		var dir := Vector3(0, sin(el), -cos(el)).rotated(Vector3.UP, yaw)
		if camera.is_position_behind(camera.global_position + dir * 1000.0):
			continue
		var c := _project(dir)
		if c.y < -20 * s or c.y > size.y + 20 * s:
			continue
		_draw_rung(c, along, e, s, w, font, fs)


## One rung at `c`: the horizon solid and long, positive rungs solid, negative ones dashed; the angle
## on every 10° rung.
func _draw_rung(c: Vector2, along: Vector2, e: int, s: float, w: float, font: Font, fs: int) -> void:
	var half := (18.0 if e == 0 else 10.0) * s
	var gap := 0.0 if e == 0 else 5.0 * s
	if e < 0:
		for k in range(3):
			var a := gap + half * k / 3.0
			draw_line(c + along * a, c + along * (a + half / 6.0), cockpit.hud_colour(), w)
			draw_line(c - along * a, c - along * (a + half / 6.0), cockpit.hud_colour(), w)
	else:
		draw_line(c + along * gap, c + along * (gap + half), cockpit.hud_colour(), w)
		draw_line(c - along * gap, c - along * (gap + half), cockpit.hud_colour(), w)
	if e != 0 and e % 10 == 0:
		draw_string(font, c + along * (gap + half + 2 * s) + Vector2(0, 3 * s), str(absi(e)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())


func _draw_fpm(p: Vector2, s: float, w: float) -> void:
	var r := 3.0 * s
	draw_arc(p, r, 0, TAU, 16, cockpit.hud_colour(), w)
	draw_line(p + Vector2(r, 0), p + Vector2(r * 2.5, 0), cockpit.hud_colour(), w)
	draw_line(p - Vector2(r, 0), p - Vector2(r * 2.5, 0), cockpit.hud_colour(), w)
	draw_line(p - Vector2(0, r), p - Vector2(0, r * 2), cockpit.hud_colour(), w)
