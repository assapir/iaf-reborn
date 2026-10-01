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

	_draw_weapons(s, w, font, fs, gun)
	_draw_target_box(s, w)

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
	draw_string(font, Vector2(4 * s, size.y / 2), speed_text(st, int(cockpit.weapons.get("hud_mode", 0)), cockpit.gear_handle_down),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
	draw_string(font, Vector2(size.x - 30 * s, size.y / 2), "%5d" % int(st.alt_ft), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
	# The autopilot replaces the G readout (FUN_0052efd3: ctl+0x974 1 / 2).
	var g_text: String = ["G %.1f" % st.g, "AP LVL", "AP NAV"][clampi(int(st.get("ap_mode", 0)), 0, 2)]
	draw_string(font, Vector2(4 * s, size.y - 14 * s), g_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cockpit.hud_colour())
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
	var screen_roll := deg_to_rad(-st.roll)
	var along := Vector2(cos(screen_roll), sin(screen_roll))
	for r in conformal_rungs(st.heading):
		if r[1].y >= -20 * s and r[1].y <= size.y + 20 * s:
			_draw_rung(r[1], along, r[0], s, w, font, fs)


## The conformal ladder's rungs [[angle °, centre]]: each angle at heading `heading_deg` through the camera.
func conformal_rungs(heading_deg: float) -> Array:
	var yaw := deg_to_rad(-heading_deg)
	var out := []
	for e in range(-90, 91, 5):
		var el := deg_to_rad(e)
		var dir := Vector3(0, sin(el), -cos(el)).rotated(Vector3.UP, yaw)
		if not camera.is_position_behind(camera.global_position + dir * 1000.0):
			out.append([e, _project(dir)])
	return out


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


# --- weapon symbology (docs/weapons.md §6; FUN_0052ef20, FUN_0052fa10, FUN_0052ffb0) ----------------

## The gun pipper sprite: mfds.bmp (132,792)–(164,824), colour key 0xffff00 (FUN_00530040).
var _pipper: Texture2D


func _pipper_tex() -> Texture2D:
	if _pipper == null and cockpit.tex.has("MFDS"):
		var img: Image = cockpit.tex.MFDS.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var a: float = cockpit.layout.get("image_scale", 1)
			var r := img.get_region(Rect2i(Vector2i(132, 792) * a, Vector2i(32, 32) * a))
			r.convert(Image.FORMAT_RGBA8)
			for y in r.get_height():
				for x in r.get_width():
					var c := r.get_pixel(x, y)
					if c.r > 0.9 and c.g > 0.9 and c.b < 0.1:
						r.set_pixel(x, y, Color(0, 0, 0, 0))
			_pipper = ImageTexture.create_from_image(r)
	return _pipper


## The HUD speed (FUN_005386c0, by the HUD mode S+0xfec through the table 0x538c78): NAV (0) the ground speed
## "% 3dG", the true speed "% 3dT" with the gear handle down (S+0x544); air-to-air (1 SRM, 2 MRM, 3 gun) and 9 the
## indicated airspeed "% 3d"; 4..8 the true speed "% 3dT"; above 9 nothing.
static func speed_text(st: Dictionary, hud_mode: int, gear_down: bool) -> String:
	var pick: Array
	if hud_mode == 0:
		pick = [st.tas_kt, "T"] if gear_down else [st.ground_kt, "G"]
	elif hud_mode <= 3 or hud_mode == 9:
		pick = [st.ias_kt, ""]
	elif hud_mode <= 8:
		pick = [st.tas_kt, "T"]
	else:
		return ""
	return " %3d%s" % [int(pick[0]), pick[1]]


func _draw_weapons(s: float, w: float, font: Font, fs: int, gun: Vector2) -> void:
	var wp: Dictionary = cockpit.weapons
	if wp.is_empty():
		return
	var col: Color = cockpit.hud_colour()
	var bore: Vector2 = cockpit.boresight() - position
	match int(wp.hud_mode):
		1:
			# SRM: missile circle r = size · 12 px (min 10) on the boresight; the seeker diamond ±7 px.
			var r := maxf(float(wp.circle) * 12.0, 10.0) * s
			draw_arc(bore, r, 0, TAU, 48, col, w)
			if wp.have_missiles:
				var d: Vector2 = bore + wp.seeker * s
				var k := 7.0 * s
				draw_polyline(PackedVector2Array([d + Vector2(0, -k), d + Vector2(k, 0), d + Vector2(0, k), d + Vector2(-k, 0), d + Vector2(0, -k)]), col, w)
		3, 4:
			var pip = wp.pipper
			var p = null
			if int(wp.hud_mode) == 3 and pip != null:
				p = gun + Vector2(float(int(pip.x)), float(int(pip.y))) * s
			elif pip != null and camera != null and host_world_to_scene.is_valid():
				var sp: Vector3 = host_world_to_scene.call(pip)
				if not camera.is_position_behind(sp):
					p = camera.unproject_position(sp) - position
			if p != null:
				var t := _pipper_tex()
				if t != null:
					draw_texture_rect(t, Rect2(p - Vector2(16, 16) * s, Vector2(32, 32) * s), false)
				else:
					draw_arc(p, 8 * s, 0, TAU, 24, col, w)
		5, 6:
			_draw_ag(wp.get("ag", {}), s, w, col)


## The mode-5 symbols (FUN_005302d0; px of the 640x480 HUD × s). P = the pipper's projection clipped
## to the HUD edge along the line from the flight path marker A (itself held inside the HUD). The
## symbols blink (300 ms phases) for 1 s after the last bomb.
## - CCIP (on the HUD): the fall line from the circle's edge (9 px) to A, a circle r 8, a centre dot.
## - Delayed (off the HUD): the same, plus a 20 px cue bar across the line that moves from A to P as
##   the time-to-go runs from 10 to 0 s.
## - Delayed, frozen (Space held): the circle at the frozen target, a steering line 400 px up the
##   rolled vertical, and the release cue bar on it 100·min(0.1·ttg, 1) px above the marker's level.
func _draw_ag(ag: Dictionary, s: float, w: float, col: Color) -> void:
	if ag.is_empty() or ag.get("pipper") == null or camera == null or not host_world_to_scene.is_valid():
		return
	if ag.get("blink", false) and (Time.get_ticks_msec() / 300) % 2 == 1:
		return
	var sp: Vector3 = host_world_to_scene.call(ag.pipper)
	if camera.is_position_behind(sp):
		return
	var a := _ag_anchor()
	var p := clip_toward(a, camera.unproject_position(sp) - position)
	var d := p - a
	var len := d.length()
	var u := d / len if len > 0.0 else Vector2(0, 1)
	if ag.get("off", false) and ag.get("frozen", false):
		var roll := deg_to_rad(float(cockpit.state.roll))
		var down := Vector2(sin(roll), cos(roll))
		var perp := Vector2(-down.y, down.x)
		draw_arc(p, 8 * s, 0, TAU, 24, col, w)
		draw_line(p - down * 9 * s, p - down * 400 * s, col, w)
		var k := clampf(0.1 * float(ag.ttg), 0.0, 1.0)
		var l := d.dot(down) + 100.0 * k * s
		var q := p - down * l
		draw_line(q + perp * 10 * s, q - perp * 10 * s, col, w)
		draw_rect(Rect2(p, Vector2(1, 1) * maxf(1.0, s)), col)
		return
	if ag.get("off", false):
		var n := len * clampf((10.0 - float(ag.ttg)) * 0.1, 0.0, 1.0)
		var perp := Vector2(-u.y, u.x)
		draw_line(a + u * n + perp * 10 * s, a + u * n - perp * 10 * s, col, w)
	if len > 9 * s:
		draw_line(p - u * 9 * s, a, col, w)
	draw_arc(p, 8 * s, 0, TAU, 24, col, w)
	draw_rect(Rect2(p, Vector2(1, 1) * maxf(1.0, s)), col)


## The flight path marker held inside the HUD (R+0x2780 / 0x2784), else the HUD centre.
func _ag_anchor() -> Vector2:
	var f = _fpm_position() if camera != null else null
	if f == null:
		return size / 2
	return Vector2(clampf(f.x, 0.0, size.x), clampf(f.y, 0.0, size.y))


## A point clipped to the HUD rectangle along the line from `a` (inside) (FUN_0052db30).
func clip_toward(a: Vector2, p: Vector2) -> Vector2:
	var r := Rect2(Vector2.ZERO, size)
	if r.has_point(p):
		return p
	var d := p - a
	var k := 1.0
	if d.x > 0.0:
		k = minf(k, (r.end.x - a.x) / d.x)
	elif d.x < 0.0:
		k = minf(k, (r.position.x - a.x) / d.x)
	if d.y > 0.0:
		k = minf(k, (r.end.y - a.y) / d.y)
	elif d.y < 0.0:
		k = minf(k, (r.position.y - a.y) / d.y)
	return a + d * maxf(k, 0.0)


## The mode-5 HUD test (FUN_0045d1d0 → FUN_004dc6d0, cockpit views only): {off} for a world point on
## the HUD; off it, the scene ray through the point clipped to the HUD edge (the renderer's ground
## query FUN_00401fc0 then finds the target under it).
func ccip_clip(world: Vector3) -> Dictionary:
	if camera == null or not is_visible_in_tree() or not host_world_to_scene.is_valid():
		return {"off": false}
	var sp: Vector3 = host_world_to_scene.call(world)
	var p: Vector2
	if camera.is_position_behind(sp):
		p = size / 2 + Vector2(0, size.y)
	else:
		p = camera.unproject_position(sp) - position
	if Rect2(Vector2.ZERO, size).has_point(p):
		return {"off": false}
	var c := clip_toward(_ag_anchor(), p) + position
	return {"off": true, "origin": camera.project_ray_origin(c), "dir": camera.project_ray_normal(c)}


## The target designator box (FUN_00537330): drawn with a radar lock, 15 px (10 px in GMT / MAP) at the
## locked unit's projection, held at the HUD edge with a line from the HUD centre when outside; an X
## inside for a friendly unit.
func _draw_target_box(s: float, w: float) -> void:
	var b := target_box(s)
	if b.is_empty():
		return
	var col: Color = cockpit.hud_colour()
	var p: Vector2 = b.p
	var h: float = b.h
	if b.edge:
		draw_line(size / 2, p, col, w)
	draw_rect(Rect2(p - Vector2(h, h), Vector2(2 * h, 2 * h)), col, false, w)
	if not b.hostile:
		draw_line(p - Vector2(h, h), p + Vector2(h, h), col, w)
		draw_line(p + Vector2(-h, h), p + Vector2(h, -h), col, w)


## The box: {p (HUD px), h (half size), edge (held at the HUD edge), hostile}; {} without a lock.
func target_box(s: float) -> Dictionary:
	var r: Dictionary = cockpit.radar
	var lk: Dictionary = r.get("lock", {})
	if lk.is_empty() or camera == null or not host_world_to_scene.is_valid():
		return {}
	var sp: Vector3 = host_world_to_scene.call(lk.pos)
	var centre := size / 2
	var p: Vector2
	if camera.is_position_behind(sp):
		var d := camera.global_basis.inverse() * (sp - camera.global_position)
		p = centre + Vector2(d.x, -d.y).normalized() * size.length()
	else:
		p = camera.unproject_position(sp) - position
	var h := (5.0 if int(r.get("mode", 0)) >= 7 else 7.5) * s
	var inner := Rect2(Vector2(h, h), size - Vector2(2 * h, 2 * h))
	var edge := not inner.has_point(p)
	if edge:
		var d := p - centre
		var k := minf(absf((inner.size.x / 2) / d.x) if d.x != 0.0 else INF, absf((inner.size.y / 2) / d.y) if d.y != 0.0 else INF)
		p = centre + d * k
	return {"p": p, "h": h, "edge": edge, "hostile": bool(lk.get("hostile", true))}


## World point -> scene (set by the flight scene for the AG pipper).
var host_world_to_scene: Callable
