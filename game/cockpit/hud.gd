# HUD symbology (docs/cockpit.md "HUD symbology"), drawn crisp at screen resolution in the original's
# 640x480 pixel layout (×ui scale). v1.1 FUN_00530b70 and its helpers: the field (clipped to the [HUD]
# borders) holds the pitch ladder / flight path marker (FUN_00538c90), the ILS (FUN_005309a0), the gun cross,
# waypoint marker and target box (FUN_0052f690) and the weapon symbols; the heading tape (FUN_00537cd0), the
# speed (FUN_005386c0) and altitude (FUN_005381c0) scales and the text block (FUN_0052ef20) sit on and
# beyond the field's edges and are drawn unclipped by a sibling layer (`outer`).
# The conformal ladder (projected through the camera) is our option (Extras > HUD pitch ladder); so is the Real
# HUD (Extras > HUD: an F-16 style symbology laid out by iaf_avionics::real_hud, drawn here).
extends Control

const Img := preload("res://util/img.gd")
const Mfd := preload("res://cockpit/mfd.gd")

## v1.1 ladder scale (original 640x480 pixels per degree) and rungs drawn: ±15° around the marker.
const LADDER_PX_PER_DEG := 12.0
const LADDER_RUNGS := 7
## GunRetPositionY of the five cockpits v1.1 lowered by 10 px (docs/v1.1.md "Data files"): with v1.0
## cockpit data the v1.1 value is used, so the cross sits on the v1.1 bullet line.
const GUN_RET_V10 := {"cfir": 170.0, "f15": 170.0, "f16": 150.0, "f4-2000": 155.0, "mirage": 130.0}
const GUN_RET_V11_SHIFT := -10.0
## m → NM (0x600e58) and m/s → kt (0x600e48).
const M_TO_NM := 0.00053937
const MS_TO_KT := 1.9427955

var cockpit: Control
## Camera the world is rendered with; aircraft attitude comes from `cockpit.state`.
var camera: Camera3D
## World-space velocity direction (for the flight path marker); null = along the nose.
var velocity_dir: Variant = null
## Terrain height (world z, m) at world (x, y), for the waypoint marker (FUN_00402080); set by the flight scene.
var host_ground: Callable

## The original HUD raster font (hud.fnt, 6x8): the cockpit does not use it (docs/mfd.md §2); kept for the
## weapon symbols' text.
var hud_font: FontFile
## The unclipped layer: tapes, boxes and the text block.
var outer: Control
## Arial h10 w5 (renderer +0x57c, the GDI texts) and its horizontal squeeze to the 5 px average width.
var _arial: SystemFont
var _arial_squeeze := 1.0
## The 5x5 sprite font (FUN_00525890, mfds.bmp; recoloured to the HUD colour, FUN_0052d680): per glyph x
## the lit pixels.
var _glyphs := {}
var _glyph_tex: Texture2D
## HUD centre in local pixels and the ui scale, set by _layout.
var _c := Vector2.ZERO
var _s := 1.0
## The ladder's labels of this frame ([top-right, text]): the sprite pass is not clipped (drawn by `outer`).
var _ladder_labels := []
## The gun pipper of this frame ({p (HUD px), arc (range arc angle, 0 none)} or {}): the sprite is only clipped to
## the screen (FUN_0052da80), so it is drawn by `outer`.
var _pipper_at := {}
## The Real HUD (IafRealHud) and its primitives of this frame ({field, outer}, {} with the original HUD).
var _real_hud = null
var _real := {}
var _real_frame := -1


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_font = load_original_font("hud")
	outer = Control.new()
	outer.name = "HudOuter"
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.draw.connect(_draw_outer)
	get_parent().add_child.call_deferred(outer)


func _process(_delta: float) -> void:
	if outer != null:
		outer.visible = visible
		outer.queue_redraw()


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
	# The HUD centre (cx, cy): on the panned panel, or the helmet display's fixed point.
	var centre: Vector2 = cockpit.hud_centre_screen() - cockpit.position
	position = centre - Vector2(h.LeftBorder, h.TopBorder) * s
	size = Vector2(h.LeftBorder + h.RightBorder, h.TopBorder + h.BottomBorder) * s
	_c = Vector2(h.LeftBorder, h.TopBorder) * s
	_s = s
	if outer != null:
		outer.position = position
		outer.size = size


## HUD key with the exe's default (FUN_0051ff70 GetPrivateProfileInt defaults).
func _key(k: String, default: float) -> float:
	return float(cockpit.layout.get("HUD", {}).get(k, default))


## The HUD mode S+0xfec (the weapon handler's; 0 NAV without weapons).
func _mode() -> int:
	return int(cockpit.weapons.get("hud_mode", 0))


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
	_ladder_labels.clear()
	_pipper_at = {}
	# The helmet display (R+0x2788): no ladder / marker, ILS, gun cross, mode 3–6 aiming symbols.
	var dash: bool = cockpit.dash()

	# The Real HUD (docs/real-hud.md): the jet's own symbology instead of the original's; a jet without a HUD (the F-4E's
	# and the Mirage's gunsights) shows its reticle only. The ILS, the BORE cross and the TV / HARM diamonds stay.
	var real := real_hud()
	if not real.is_empty():
		_draw_prims(self, real.field, w, real.colour)
		if real.sight:
			return
		if _mode() == 0 and cockpit.gear_handle_down:
			_draw_ils(st, w)
		if _mode() in [7, 8]:
			_draw_weapons(s, w, font, fs, gun, dash)
		if int(cockpit.radar.get("mode", 0)) == 3:
			_ln(self, Vector2(-30, 0), Vector2(30, 0), w)
			_ln(self, Vector2(0, -20), Vector2(0, 20), w)
		return
	# Ladder (ShowHorizon, R+0x2234) and flight path marker (FUN_00538c90).
	if camera != null and not dash:
		var fpm = _fpm_position()
		if _key("ShowHorizon", 1) != 0:
			if Settings.hud_ladder == "conformal":
				_draw_conformal_ladder(st, s, w, font, fs)
			elif fpm != null:
				_draw_ladder(fpm, st, s, w, font, fs)
		if fpm != null and Rect2(Vector2.ZERO, size).has_point(fpm):
			_draw_fpm(fpm, s, w)

	# NAV: the ILS with the gear handle down (FUN_005309a0).
	if _mode() == 0 and cockpit.gear_handle_down and not dash:
		_draw_ils(st, w)

	_draw_weapons(s, w, font, fs, gun, dash)
	# FUN_0052f690, every HUD mode: the target box, the gun cross with the gear handle up (GunRetPositionY:
	# −4..+5 across, −5..+10 down; not on the helmet display), the waypoint marker in NAV and the air-to-ground modes.
	_draw_target_box(s, w)
	# The radar in BORE (S+0xa04 = 3): a cross on the HUD centre, ±30 px across, ±20 px up / down.
	if int(cockpit.radar.get("mode", 0)) == 3:
		_ln(self, Vector2(-30, 0), Vector2(30, 0), w)
		_ln(self, Vector2(0, -20), Vector2(0, 20), w)
	if not cockpit.gear_handle_down and not dash:
		var g := (gun - _c) / s
		_ln(self, g + Vector2(-4, 0), g + Vector2(5, 0), w)
		_ln(self, g + Vector2(0, -5), g + Vector2(0, 10), w)
	_draw_waypoint_marker(w)


## The ILS deviation lines (FUN_005309a0).
func _draw_ils(st: Dictionary, w: float) -> void:
	var il := ils_lines(st.get("ils", Vector2.ZERO), _field())
	var hx: float = 16
	_ln(self, Vector2(-hx, il.y), Vector2(hx, il.y), w)
	_ln(self, Vector2(-hx, il.y - 1), Vector2(-hx, il.y + 2), w)
	_ln(self, Vector2(hx, il.y - 1), Vector2(hx, il.y + 2), w)
	_ln(self, Vector2(il.x, -hx), Vector2(il.x, hx), w)
	_ln(self, Vector2(il.x - 1, -hx), Vector2(il.x + 2, -hx), w)
	_ln(self, Vector2(il.x - 1, hx), Vector2(il.x + 2, hx), w)


## The field in original pixels from the HUD centre: Rect2(−LeftBorder, −TopBorder, L + R, T + B).
func _field() -> Rect2:
	var l := _key("LeftBorder", 98)
	var t := _key("TopBorder", 70)
	return Rect2(-l, -t, l + _key("RightBorder", 98), t + _key("BottomBorder", 70))


# --- drawing primitives: original pixels from the HUD centre -----------------------------------------

func _pt(p: Vector2) -> Vector2:
	return _c + p * _s


func _ln(ci: CanvasItem, a: Vector2, b: Vector2, w: float) -> void:
	ci.draw_line(_pt(a), _pt(b), cockpit.hud_colour(), w)


func _poly(ci: CanvasItem, pts: Array, w: float) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_pt(p))
	ci.draw_polyline(out, cockpit.hud_colour(), w)


## The 5x5 sprite font's lit pixels per glyph x (letters at (132,850), digits and symbols at (132,840) of
## mfds.bmp; every pixel but the colour key is lit, FUN_0052d680).
func _glyph(x: int) -> PackedVector2Array:
	var t: Texture2D = cockpit.tex.get("MFDS")
	if t != _glyph_tex:
		_glyphs.clear()
		_strokes.clear()
		_glyph_tex = t
	if _glyphs.has(x):
		return _glyphs[x]
	var px := PackedVector2Array()
	var img: Image = t.get_image() if t != null else null
	if img != null:
		if img.is_compressed():
			img.decompress()
		var a: float = cockpit.layout.get("image_scale", 1)
		var src := Vector2(132 + x, 850) if x < 130 else Vector2(132 + x - 130, 840)
		for yy in 5:
			for xx in 5:
				var c := img.get_pixel(int((src.x + xx + 0.5) * a), int((src.y + yy + 0.5) * a))
				if c.a > 0.5 and not (c.r < 0.1 and c.g > 0.9 and c.b > 0.9):
					px.append(Vector2(xx, yy))
	_glyphs[x] = px
	return px


## Sprite text with its top-left at `p` (FUN_00525a30), or ending at p.x when `right` (FUN_00525920). Ours
## draws each glyph's pixels as antialiased strokes between neighbouring lit pixels (same shapes, crisp at a
## non-integer scale; the 1998 pixels drawn as squares came out uneven, docs/deviations.md). The whole string is one
## draw_multiline (a call per segment and per pixel cost ≈ 6 ms a frame for the HUD's text); every lit pixel is also a
## short stroke of its own, the joint.
func _sprite(ci: CanvasItem, p: Vector2, text: String, right := false) -> void:
	var x0 := p.x - (5 * text.length() if right else 0)
	var wd := maxf(_s * 0.95, 1.0)
	var j := Vector2(0.5 * wd / _s * 0.5, 0.0)
	var pts := PackedVector2Array()
	for i in text.length():
		var o := Vector2(x0 + 5 * i + 0.5, p.y + 0.5)
		var g: Array = _glyph_strokes(Mfd._glyph_x(text[i]))
		for seg in g[0]:
			pts.append(_pt(o + seg[0]))
			pts.append(_pt(o + seg[1]))
		for q in g[1]:
			pts.append(_pt(o + q - j))
			pts.append(_pt(o + q + j))
	if not pts.is_empty():
		ci.draw_multiline(pts, cockpit.hud_colour(), wd, true)


## A glyph as strokes: [segments between 8-neighbouring lit pixels (a diagonal only where no orthogonal step
## joins the two), every lit pixel as a round joint].
var _strokes := {}
func _glyph_strokes(x: int) -> Array:
	if _strokes.has(x) and _glyph_tex == cockpit.tex.get("MFDS"):
		return _strokes[x]
	var px: PackedVector2Array = _glyph(x)
	var lit := {}
	for q in px:
		lit[q] = true
	var segs := []
	for q in px:
		for d in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(-1, 1)]:
			if not lit.has(q + d):
				continue
			if d.x != 0 and d.y != 0 and (lit.has(q + Vector2(d.x, 0)) or lit.has(q + Vector2(0, d.y))):
				continue
			segs.append([q, q + d])
	_strokes[x] = [segs, px]
	return _strokes[x]


## GDI text in Arial h10 w5 at baseline `p` (TA_BASELINE; TA_RIGHT when `right`).
func _gdi(ci: CanvasItem, p: Vector2, text: String, right := false, colour = null) -> void:
	var em := 10.0 / 1.15
	if _arial == null:
		_arial = Img.arial()
		var avg := _arial.get_string_size("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 52.0 / 100.0 * em
		_arial_squeeze = 5.0 / avg
	var fs := int(round(em * _s))
	if fs < 1:
		return
	var at := _pt(p)
	if right:
		at.x -= _arial.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * _arial_squeeze
	ci.draw_set_transform(at, 0.0, Vector2(_arial_squeeze, 1.0))
	ci.draw_string(_arial, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour if colour != null else cockpit.hud_colour())
	ci.draw_set_transform(Vector2.ZERO)


# --- the unclipped layer -----------------------------------------------------------------------------

func _draw_outer() -> void:
	if cockpit == null or cockpit.layout.is_empty() or not visible:
		return
	var st: Dictionary = cockpit.state
	var w := maxf(1.0, 0.6 * _s)
	var f := _field()
	var mode := _mode()
	var dash: bool = cockpit.dash()
	var scales := _key("ShowLRScales", 1) != 0 and not dash
	var nav := nav_cues(st, cockpit.waypoints, cockpit.current_waypoint)
	var vy := -_key("VertSclOffY", 150)
	var gear: bool = cockpit.gear_handle_down

	for l in _ladder_labels:
		_sprite(outer, l[0], l[1], true)
	if not _pipper_at.is_empty():
		_draw_pipper(_pipper_at.p, float(_pipper_at.arc), w)
	var real := real_hud()
	if not real.is_empty():
		_draw_prims(outer, real.outer, w, real.colour)
		return

	# Altitude (FUN_005381c0) on the right edge.
	var at := alt_value(st, mode, gear)
	var x := f.end.x
	_gdi(outer, Vector2(x + 43, vy + 4), at[1], true)
	_poly(outer, [Vector2(x, vy - 6), Vector2(x + 34, vy - 6), Vector2(x + 34, vy + 6), Vector2(x, vy + 6), Vector2(x, vy - 6)], w)
	if scales:
		var sc := alt_scale(at[0])
		_ln(outer, Vector2(x, vy - 51), Vector2(x, vy + 51), w)
		for t in sc.ticks:
			_ln(outer, Vector2(x, vy + t[0]), Vector2(x + t[1], vy + t[0]), w)
		for l in sc.labels:
			_sprite(outer, Vector2(x + 25, vy + l[0] - 7), l[1], true)

	# Speed (FUN_005386c0) on the left edge.
	var v := speed_value(st, mode, gear)
	x = f.position.x
	if v.size() > 0:
		_gdi(outer, Vector2(x - 2, vy + 4), v[1], true)
	_poly(outer, [Vector2(x, vy - 6), Vector2(x - 34, vy - 6), Vector2(x - 34, vy + 6), Vector2(x, vy + 6), Vector2(x, vy - 6)], w)
	if scales:
		var sv: float = v[0] if v.size() > 0 else 0.0
		var sc := speed_scale(sv, nav.req_kt if mode != 3 else null)
		_ln(outer, Vector2(x, vy - 51), Vector2(x, vy + 51), w)
		if sc.caret != null:
			var c: float = sc.caret
			_poly(outer, [Vector2(x + 4, vy - c - 3), Vector2(x + 1, vy - c), Vector2(x + 5, vy - c + 4)], w)
		for t in sc.ticks:
			_ln(outer, Vector2(x, vy + t[0]), Vector2(x - t[1], vy + t[0]), w)
		for l in sc.labels:
			_sprite(outer, Vector2(x - 3, vy + l[0] - 7), l[1], true)

	# Heading tape (FUN_00537cd0) on the top edge; the helmet display has the DASH symbol instead.
	if dash:
		for line in dash_symbol(st.pitch, st.roll, _dash_steady()):
			_poly(outer, line, w)
		outer.draw_arc(_pt(Vector2.ZERO), 2.0 * _s, 0, TAU, 16, cockpit.hud_colour(), w)
	else:
		var y0 := f.position.y
		var ht := heading_tape(st.heading, nav.bearing_deg)
		_ln(outer, Vector2(-57, y0), Vector2(57, y0), w)
		_ln(outer, Vector2(0, y0), Vector2(0, y0 + 4), w)
		_poly(outer, [Vector2(-11, y0), Vector2(-11, y0 - 12), Vector2(11, y0 - 12), Vector2(11, y0)], w)
		_gdi(outer, Vector2(-8, y0 - 2), ht.box)
		var cx: float = ht.caret
		_poly(outer, [Vector2(cx - 3, y0 + 4), Vector2(cx, y0 + 1), Vector2(cx + 4, y0 + 5)], w)
		for tx in ht.ticks:
			_ln(outer, Vector2(tx, y0), Vector2(tx, y0 - 2), w)
		for l in ht.labels:
			_sprite(outer, Vector2(l[0] + 6, y0 - 7), l[1], true)

	# The text block (FUN_0052ef20 pass 3): three rows each side, 7 px apart from the centre + TxtOffY.
	var rows := text_block(st, mode, nav, cockpit.weapons, cockpit.radar, cockpit.twin_engines, cockpit.damage_flags)
	var tx0 := _key("TxtOffX", 30)
	var ty0 := _key("TxtOffY", 80)
	for i in 3:
		_sprite(outer, Vector2(-tx0, ty0 + 7 * i), rows[i])
		_sprite(outer, Vector2(tx0, ty0 + 7 * i), rows[3 + i], true)


# --- the Real HUD (ours, Extras > HUD) ---------------------------------------------------------------------

## The Real HUD's primitives of this frame ({field, outer, colour, sight}; {} with the original HUD or without a
## camera; on the helmet display only for the F-35, whose display is its helmet), computed once per frame for both
## layers. Inputs: the flight state, the view (horizon, scale, marker, boresight, gun cross), the steerpoint and the
## radar's target projected on the HUD, the weapons' HUD points (seeker, LCOS / strafe / CCIP pipper, MRM steering).
func real_hud() -> Dictionary:
	if Settings.hud_style != "real" or camera == null:
		return {}
	var f35 := String(cockpit.cockpit_dir).contains("f35")
	if cockpit.dash() and not f35:
		return {}
	var fr := Engine.get_process_frames()
	if fr == _real_frame:
		return _real
	_real_frame = fr
	if _real_hud == null:
		_real_hud = ClassDB.instantiate("IafRealHud")
	var st: Dictionary = cockpit.state
	var wp: Dictionary = cockpit.weapons
	var rd: Dictionary = cockpit.radar
	var mode := _mode()
	# The level direction ahead along the view's heading and the view's scale (5° up from it).
	var fwd := -camera.global_basis.z
	var level := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var horizon := _project(level)
	var up5 := _project(level.rotated(level.cross(Vector3.UP).normalized(), deg_to_rad(5.0)))
	var fpm = _fpm_position()
	var gun: Vector2 = (gun_cross() - position - _c) / _s
	var nav := nav_cues(st, cockpit.waypoints, cockpit.current_waypoint)
	var steer := {}
	if not cockpit.waypoints.is_empty():
		var i := clampi(cockpit.current_waypoint, 0, cockpit.waypoints.size() - 1)
		var wpt: Dictionary = cockpit.waypoints[i]
		var z := 0.0
		if host_ground.is_valid():
			var g = host_ground.call(wpt.world.x, wpt.world.y)
			z = float(g) if g != null else 0.0
		var minutes := float(nav.minutes)
		steer = {"number": int(nav.index) + 1, "bearing": nav.bearing_deg, "dist_m": float(nav.dist_nm) / M_TO_NM,
			"eta_s": minutes * 60.0 if minutes < 1000.0 / 60.0 else null,
			"at": _hud_point(Vector3(wpt.world.x, wpt.world.y, z), true)}
	var lk: Dictionary = rd.get("lock", {})
	var target := {}
	if not lk.is_empty():
		target = {"range_m": float(lk.dist), "closure": float(rd.get("closure", 0.0)), "at": _hud_point(lk.pos, true),
			"aspect": lk.get("aspect")}
	var pip = null
	if mode == 4 and wp.get("pipper") != null:
		pip = _hud_point(wp.pipper, false)
	elif mode in [5, 6] and wp.get("ag", {}).get("pipper") != null:
		pip = _hud_point(wp.ag.pipper, false)
	var lcos = null
	if mode == 3 and wp.get("pipper") != null:
		lcos = gun + Vector2(wp.pipper.x, wp.pipper.y)
	var agl = st.get("agl_ft")
	_real = _real_hud.frame(_field(), {
		"cockpit": cockpit.cockpit_dir, "time": st.get("time", 0.0), "off_boresight": f35 and cockpit.dash(),
		"head_heading": fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0), "kcas": st.get("ias_kt", 0.0), "ground_kt": st.get("ground_kt", 0.0),
		"tas_ms": float(st.get("tas_kt", 0.0)) / MS_TO_KT, "alt_ft": st.get("alt_ft", 0.0), "agl_ft": agl,
		"vs_fpm": st.get("vs_fpm", 0.0), "heading": st.get("heading", 0.0), "roll": st.get("roll", 0.0),
		"mach": st.get("mach", 0.0), "g": st.get("g", 1.0), "aoa": st.get("aoa", 0.0),
		"gear_down": cockpit.gear_handle_down, "fuel_lbs": st.get("fuel_lbs", 0.0),
		"fpm": (fpm - _c) / _s if fpm != null else null, "boresight": (cockpit.boresight() - position - _c) / _s,
		"gun_cross": gun, "horizon": (horizon - _c) / _s, "px_per_deg": (up5 - horizon).length() / 5.0 / _s,
		"steerpoint": steer, "target": target, "dlz": rd.get("dlz", []) if not target.is_empty() else [],
		"weapons": {"hud_mode": mode, "selected": wp.get("total", 0), "srm": wp.get("srm", 0), "mrm": wp.get("mrm", 0),
			"seeker": wp.get("seeker") if mode == 1 and wp.get("have_missiles", false) else null, "lcos": lcos,
			"pipper": pip, "steering": _hud_point(wp.mrm_point, false) if mode == 2 and wp.get("mrm_point") != null else null,
			"circle": wp.get("circle", 5.0), "shoot": wp.get("shoot", false)}})
	return _real


## A world point (X east, Y north, Z up) in HUD pixels from the HUD centre; behind the eye: null, or with `far` a
## point far out in its direction (for symbols held on the field's edge).
func _hud_point(world: Vector3, far: bool) -> Variant:
	if not host_world_to_scene.is_valid():
		return null
	var sp: Vector3 = host_world_to_scene.call(world)
	if camera.is_position_behind(sp):
		if not far:
			return null
		var d := camera.global_basis.inverse() * (sp - camera.global_position)
		return Vector2(d.x, -d.y).normalized() * 10000.0
	return (camera.unproject_position(sp) - position - _c) / _s


## Draws Real HUD primitives (HUD pixels from the HUD centre) on `ci`, in `colour` (null: the HUD's).
func _draw_prims(ci: CanvasItem, prims: Array, w: float, colour = null) -> void:
	var col: Color = colour if colour != null else cockpit.hud_colour()
	for p in prims:
		match p.k:
			"line":
				ci.draw_line(_pt(p.a), _pt(p.b), col, w, true)
			"circle":
				ci.draw_arc(_pt(p.c), float(p.r) * _s, 0, TAU, 32, col, w, true)
			"dot":
				ci.draw_circle(_pt(p.c), maxf(float(p.r) * _s, w), col, true, -1.0, true)
			"arc":
				var a0: float = float(p.from) - PI / 2.0
				ci.draw_arc(_pt(p.c), float(p.r) * _s, a0, a0 + float(p.sweep), 24, col, w * 1.6, true)
			"text":
				var at: Vector2 = p.at
				if int(p.align) == 1:
					at.x += 2.5 * String(p.text).length()
				_gdi(ci, at, p.text, int(p.align) != 0, col)


# --- traced values (original pixels; tests/godot/test_hud.gd) -----------------------------------------

## The DASH symbol (FUN_00539ac0) as polylines in original pixels from the helmet display's centre: the aircraft
## symbol's wings and tail (LineTo ∓4 → ∓1 leaves the last pixel: 4..2 px, as the marker; its circle
## Ellipse(−2, −2, 3, 3) is drawn by the caller) and,
## when `steady`, the attitude bar (−42, 2)→(−42, 0)→(−5, 0) and its mirror, rolled by the roll and moved down
## 1.5 px per degree of pitch (held at ±40°). Pitch / roll in degrees (roll right wing down +).
static func dash_symbol(pitch_deg: float, roll_deg: float, steady: bool) -> Array:
	var r := fposmod(roll_deg, 360.0)
	var p := fposmod(pitch_deg, 360.0)
	if p > 90.0 and p < 270.0:
		p = 180.0 - p
		r += 180.0
	elif p > 270.0:
		p -= 360.0
	p = clampf(p, -40.0, 40.0)
	var sn := sin(deg_to_rad(r))
	var cs := cos(deg_to_rad(r))
	var off := 1.5 * p
	var out := [[Vector2(-4, 0), Vector2(-2, 0)], [Vector2(4, 0), Vector2(2, 0)], [Vector2(0, -4), Vector2(0, -2)]]
	if steady:
		for side in [-1.0, 1.0]:
			var line := []
			for q in [Vector2(42 * side, 2), Vector2(42 * side, 0), Vector2(5 * side, 0)]:
				line.append(Vector2(float(int(cs * q.x + sn * q.y)), float(int(off + cs * q.y - sn * q.x))))
			out.append(line)
	return out


## The bar's blink (DAT_0065d7a4 / DAT_0083e550): beyond ±40° of pitch it flips every 300 ms of the frame
## clock (R+0x574); steady inside.
var _blink := 1
var _blink_ms := 0
var _blink_last := 0


func _dash_steady() -> bool:
	var now := Time.get_ticks_msec()
	var p := fposmod(float(cockpit.state.pitch), 360.0)
	if p > 90.0 and p < 270.0:
		p = 180.0 - p
	elif p > 270.0:
		p -= 360.0
	if absf(p) > 40.0:
		_blink_ms += now - _blink_last
		if _blink_ms > 300:
			_blink = -_blink
			_blink_ms = 0
	else:
		_blink = 1
	_blink_last = now
	return _blink == 1

## The heading tape (FUN_00537cd0, scale 1): 2 px per degree, ±57 px. `ticks`: x of the 5° ticks outside
## the box (|x| 11..57, 2 px up); `labels`: [x, "%02d" tens of degrees] every 10° (sprite font ending at
## x + 6, top 7 px above the line); `box`: "%03d" of the truncated heading; `caret`: the steering caret's x
## (bearing to the waypoint S+0x58 − heading, wrapped ±180°, 2 px/deg, clamped ±57).
static func heading_tape(heading_deg: float, bearing_deg: float) -> Dictionary:
	var h := fmod(heading_deg, 360.0)
	var box := posmod(int(heading_deg), 360)
	var ticks := []
	var off := int(-h * 2.0) % 10
	for i in range(-1, 11):
		var x := off - (i - 5) * 10
		if (x < -11 and x > -57) or (x > 11 and x < 57):
			ticks.append(x)
	var labels := []
	off = int(-h * 2.0) % 20
	var t := int(h * -0.1)
	for i in range(-1, 5):
		var x := off - (i - 2) * 20
		var v := (2 - t - i) * 10
		if v < 0:
			v += 360
		if (x < -11 and x > -57) or (x > 11 and x < 57):
			labels.append([x, "%02d" % ((v % 360) / 10)])
	var d := fposmod(bearing_deg, 360.0) - h
	if d > 180.0:
		d -= 360.0
	if d < -180.0:
		d += 360.0
	return {"ticks": ticks, "labels": labels, "box": "%03d" % box, "caret": clampi(int(2.0 * d), -57, 57)}


## printf "% 3d" (a blank for the sign, width 3).
static func _sp3(v: int) -> String:
	var t := ("" if v < 0 else " ") + str(v)
	return t.lpad(3)


## The HUD speed (FUN_005386c0 @538739, by the HUD mode S+0xfec through the table 0x538c78): NAV (0) the ground speed
## "% 3dG", the true speed "% 3dT" with the gear handle down (S+0x544); air-to-air (1 SRM, 2 MRM, 3 gun) and 9 the
## indicated airspeed "% 3d"; 4..8 the true speed "% 3dT"; above 9 nothing. [value kt, text]; [] for none.
static func speed_value(st: Dictionary, hud_mode: int, gear_down: bool) -> Array:
	var pick: Array
	if hud_mode == 0:
		pick = [st.tas_kt, "T"] if gear_down else [st.ground_kt, "G"]
	elif hud_mode <= 3 or hud_mode == 9:
		pick = [st.ias_kt, ""]
	elif hud_mode <= 8:
		pick = [st.tas_kt, "T"]
	else:
		return []
	var v := maxf(float(pick[0]), 0.0)
	return [v, _sp3(int(v)) + pick[1]]


static func speed_text(st: Dictionary, hud_mode: int, gear_down: bool) -> String:
	var v := speed_value(st, hud_mode, gear_down)
	return v[1] if v.size() > 0 else ""


## The speed scale (FUN_005386c0, scale 1): 0.6 px per kt (6 px ticks of 10 kt, 102 px tall, higher speeds up).
## `ticks`: [y, length] (3 px every 50 kt, else 4, drawn leftwards); `labels`: [y, "%d"] every 50 kt ≥ 0 outside
## the box (sprite font ending 3 px left of the line, top at y − 7); `caret`: the required-speed caret's offset
## up (clamp((required − V)·0.6, ±51), truncated), null in gun mode.
static func speed_scale(v: float, req) -> Dictionary:
	var ticks := []
	var major := int(v * 0.1) % 5
	major = major + 3 if major < 2 else major - 2
	var off := int(v * 0.6) % 6
	for i in 17:
		var y := (i - 8) * 6 + off
		if i == major:
			ticks.append([y, 3])
			major += 5
		else:
			ticks.append([y, 4])
	var labels := []
	off = int(v * 0.6) % 30 + 5
	var t := int(v * -0.02)
	for i in range(-1, 3):
		var y := off + 30 * (i - 1)
		var val := (1 - t - i) * 50
		if ((y < 0 and y > 5 - 51) or (y > 10 and y < 53)) and val >= 0:
			labels.append([y, str(val)])
	var caret = null
	if req != null:
		caret = int(clampf((float(req) - v) * 6.0 * 0.1, -51.0, 51.0))
	return {"ticks": ticks, "labels": labels, "caret": caret}


## The HUD altitude (FUN_005381c0): in NAV and HUD modes 4 / 5 with the gear handle up the radar altitude (S+0x3c, ft
## above the ground, ≥ 0) "%5d R", else the barometric altitude (S+8 m · 3.28084 when above 0) "%5d B".
## [value, text].
static func alt_value(st: Dictionary, hud_mode: int, gear_down: bool) -> Array:
	var a: float
	var tag := " B"
	if (hud_mode == 0 or hud_mode == 4 or hud_mode == 5) and not gear_down:
		a = maxf(float(st.get("agl_ft", 0.0)), 0.0)
		tag = " R"
	else:
		a = float(st.alt_ft)
		if a <= 0.0:
			a /= 3.28084
	return [a, "%5d" % int(a) + tag]


## The altitude scale (FUN_005381c0, scale 1): 20 ft per px (5 px ticks of 100 ft, 102 px tall). `ticks`:
## [y, length] (3 px every 500 ft, else 4, drawn rightwards); `labels`: [y, "%4.1f" thousands] every 500 ft
## outside the box (sprite font ending 25 px right of the line, top at y − 7).
static func alt_scale(a: float) -> Dictionary:
	var ticks := []
	var off := int(a / 20.0) % 5
	var major := int(a * 0.01) % 5
	for i in 20:
		var y := (i - 10) * 5 + off
		if i == major:
			ticks.append([y, 3])
			major += 5
		else:
			ticks.append([y, 4])
	var labels := []
	off = int(a / 20.0) % 25 + 5
	var t := int(a * 0.002)
	for i in range(-1, 4):
		var y := off + 25 * (i - 2)
		if (y < 0 and y > 5 - 51) or (y > 10 and y < 53):
			labels.append([y, "%4.1f" % (t * 0.5 - (i - 2) * 0.5)])
	return {"ticks": ticks, "labels": labels}


## The NAV cues of the waypoint object (FUN_00452e60 → FUN_004459f0): S+0x58 the bearing to the current
## waypoint (°, clockwise from north), S+0x5c its 2-D distance in NM, S+0x60 the minutes to it at the ground speed
## (1000 s when not moving), S+0x324 the speed (kt) that makes its time T (0 when T has passed).
static func nav_cues(st: Dictionary, route: Array, index: int) -> Dictionary:
	var out := {"bearing_deg": 0.0, "dist_nm": 0.0, "minutes": 1000.0 / 60.0, "req_kt": 0.0, "index": index}
	if route.is_empty():
		return out
	var w: Dictionary = route[clampi(index, 0, route.size() - 1)]
	var d: Vector2 = w.world - st.get("world", Vector2.ZERO)
	out.bearing_deg = 0.0 if d == Vector2.ZERO else rad_to_deg(atan2(d.x, d.y))
	var dist := d.length()
	out.dist_nm = dist * M_TO_NM
	var vh: float = float(st.get("ground_kt", 0.0)) / MS_TO_KT
	out.minutes = (dist / vh if vh != 0.0 else 1000.0) / 60.0
	var left: float = float(w.get("t", 0.0)) - float(st.get("time", 0.0))
	out.req_kt = dist / left * MS_TO_KT if left > 0.0 else 0.0
	# The ETA (state+0x318, FUN_00452e60): the time of day at arrival, at most 10 h ahead (0x600e40).
	out.eta = float(st.get("tod", st.get("time", 0.0))) + minf(out.minutes * 60.0, 36000.0)
	return out


## The text block (FUN_0052ef20): rows 0..2 left (left-aligned at the centre − TxtOffX), 3..5 right (ending at
## the centre + TxtOffX). 0: "AB %1d" with the afterburner lit (S+0x1054, the larger of two engines), else
## "T %03d" of the rpm (S+0x1040 ×100; the format's trailing '%' prints nothing); 1: "AP LVL" / "AP NAV"
## (autopilot S+0x1028 1 / 2) or the load factor "+%3.1fG" (≥ 0) / "%4.1fG"; 2: "NAV" in NAV, else "%1d %s %s"
## (selected store total, name, RDY / MAL); 3: "R %2.1f" (radar lock range, NM) with a lock; 4: in NAV and HUD
## modes 2 and 4..8 "W%02d  %02.1f" (waypoint number and NM), in modes 1 / 3 the lock's aspect "%2dL" / "%2dR";
## 5: in NAV "%3.1f MIN" below 60 minutes, in mode 5 the bomb time-to-go "%2d SEC" / "XX SEC" (≥ 90), in modes
## 1, 2, 8 "%2d SEC" of the last launched weapon's time left (S+0x380). (Mode 4's "%2d" and "AUD", S+0x3a4, are
## not built.)
static func text_block(st: Dictionary, mode: int, nav: Dictionary, wp: Dictionary, radar: Dictionary,
		twin: bool, flags: Array) -> Array:
	var rows := ["", "", "", "", "", ""]
	var eng: PackedFloat32Array = st.get("engines", PackedFloat32Array([0, 0, 0, 0, 0, 0]))
	var dmg := func(i: int) -> bool: return i < flags.size() and bool(flags[i])
	var ab := int(st.get("afterburner", 0))
	var ab_l := 0 if dmg.call(8) or dmg.call(22) else ab
	var ab_r := 0 if dmg.call(9) or dmg.call(23) else ab
	var thr := absi(int(eng[0] * 100.0)) if eng.size() > 0 else 0
	if twin:
		ab_l = maxi(ab_l, ab_r)
		if eng.size() > 3:
			thr = maxi(thr, absi(int(eng[3] * 100.0)))
	rows[0] = "AB %1d" % ab_l if ab_l > 0 else "T %03d" % thr
	var ap := int(st.get("ap_mode", 0))
	var g := float(st.get("g", 1.0))
	rows[1] = "AP LVL" if ap == 1 else ("AP NAV" if ap == 2 else ("+%3.1fG" % g if g >= 0.0 else "%4.1fG" % g))
	if mode == 0:
		rows[2] = "NAV"
	elif not wp.is_empty():
		rows[2] = "%1d %s %s" % [int(wp.get("total", 0)), wp.get("name", ""), "RDY" if wp.get("ready", false) else "MAL"]
	var lk: Dictionary = radar.get("lock", {})
	if not lk.is_empty():
		rows[3] = "R %2.1f" % (float(lk.get("dist", 0.0)) * M_TO_NM)
	var w_row := "W%02d  %02.1f" % [int(nav.index) + 1, float(nav.dist_nm)]
	match mode:
		0:
			rows[4] = w_row
			if nav.minutes < 60.0:
				rows[5] = "%3.1f MIN" % nav.minutes
		1, 3:
			if not lk.is_empty():
				rows[4] = Mfd.aspect_text(float(lk.get("aspect", 0.0)))
		2, 4, 6, 7, 8:
			rows[4] = w_row
		5:
			rows[4] = w_row
			# The bomb time-to-go with the impact off the HUD (S+0x620 = 1, S+0x638; weapons.md §9.4).
			var ag: Dictionary = wp.get("ag", {})
			if ag.get("off", false):
				var sec := int(float(ag.get("ttg", 0.0)))
				rows[5] = "XX SEC" if sec >= 90 else "%2d SEC" % sec
	# Modes 1, 2, 8: "%2d SEC" of S+0x380, the last launched weapon's time left (FUN_00456520).
	if mode in [1, 2, 8]:
		rows[5] = "%2d SEC" % int(float(wp.get("sec", 0.0)))
	return rows


## The ILS lines (FUN_005309a0, scale 1) from the deviations (°, x localizer, y glideslope; S+0x1030 / 0x1034):
## the localizer's x = −trunc(−12·loc), the glideslope's y = −trunc(−12·gs) from the HUD centre, each held 1 px
## inside the field `f` (original pixels from the centre). Both lines are 32 px long, centred on the HUD centre's
## other coordinate, with 3 px end ticks.
static func ils_lines(dev: Vector2, f: Rect2) -> Vector2:
	var x := float(-int(-12.0 * dev.x))
	var y := float(-int(-12.0 * dev.y))
	return Vector2(clampf(x, f.position.x + 1, f.end.x - 1), clampf(y, f.position.y + 1, f.end.y - 1))


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


## One rung at `c` (FUN_00538c90, P(u, r) = u along the rung, r down the rolled vertical): above the horizon
## solid from 9 to 32 px each side with 3 px end ticks toward the horizon; the horizon from 9 to 46 px; below
## dashed (9–20, 22–25, 27–32 px) with the end ticks up; "%02d" of the angle on every 10° rung but the horizon,
## in the sprite font ending at P(±39, 0) + (5, −2), shown when that point is inside the field.
func _draw_rung(c: Vector2, along: Vector2, e: int, s: float, w: float, _font: Font, _fs: int) -> void:
	var down := Vector2(-along.y, along.x)
	var col: Color = cockpit.hud_colour()
	var at := func(u: float, r: float) -> Vector2: return c + (along * u + down * r) * s
	for side in [1.0, -1.0]:
		if e == 0:
			draw_line(at.call(9 * side, 0), at.call(46 * side, 0), col, w)
		elif e > 0:
			draw_polyline(PackedVector2Array([at.call(9 * side, 0), at.call(32 * side, 0), at.call(32 * side, 3)]), col, w)
		else:
			draw_line(at.call(9 * side, 0), at.call(20 * side, 0), col, w)
			draw_line(at.call(22 * side, 0), at.call(25 * side, 0), col, w)
			draw_polyline(PackedVector2Array([at.call(27 * side, 0), at.call(32 * side, 0), at.call(32 * side, -3)]), col, w)
		if e != 0 and e % 10 == 0:
			var p: Vector2 = (at.call(39 * side, 0) - _c) / s + Vector2(5, -2)
			if _field().has_point(p):
				_ladder_labels.append([p, "%02d" % absi(e)])


## The marker (FUN_00538c90): Ellipse(x−2, y−2, x+3, y+3) (outline pixels 2 px from the centre), wings from
## 4 to 1 px either side and a tail from 4 to 1 px up (LineTo leaves the last pixel: 4..2 px drawn).
func _draw_fpm(p: Vector2, s: float, w: float) -> void:
	draw_arc(p, 2.0 * s, 0, TAU, 16, cockpit.hud_colour(), w)
	draw_line(p + Vector2(2, 0) * s, p + Vector2(4, 0) * s, cockpit.hud_colour(), w)
	draw_line(p - Vector2(2, 0) * s, p - Vector2(4, 0) * s, cockpit.hud_colour(), w)
	draw_line(p - Vector2(0, 2) * s, p - Vector2(0, 4) * s, cockpit.hud_colour(), w)


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


func _draw_weapons(s: float, w: float, font: Font, fs: int, gun: Vector2, dash := false) -> void:
	var wp: Dictionary = cockpit.weapons
	if wp.is_empty():
		return
	var col: Color = cockpit.hud_colour()
	var mode := int(wp.hud_mode)
	if dash and mode >= 3 and mode <= 6:
		return  # FUN_00530040 / FUN_005302d0 test R+0x2788
	match mode:
		1, 2:
			# SRM / MRM (FUN_0052ffb0 / FUN_0052ff30 → FUN_00537120): the missile circle r = size · 12 px (at least
			# 10, at most the field's right / bottom extent from the HUD centre) on the HUD centre; with a radar lock
			# a caret outside it at the locked target's bearing (state+0x4c; tip on the circle, 4 px deep, 4 px wide,
			# at angle bearing + π from up, clockwise: UNCERTAIN sign of FUN_0044e770).
			var r := minf(maxf(float(wp.circle) * 12.0, 10.0) * s, minf(size.x - _c.x, size.y - _c.y))
			draw_arc(_c, r, 0, TAU, 48, col, w)
			if wp.get("bearing") != null:
				var a: float = float(wp.bearing) + PI
				var dir := Vector2(sin(a), -cos(a))
				var perp := Vector2(cos(a), sin(a))
				var base := _c + dir * (r + 4.0 * s)
				draw_polyline(PackedVector2Array([_c + dir * r, base + perp * 2.0 * s, base - perp * 2.0 * s, _c + dir * r]), col, w)
			if mode == 1 and wp.have_missiles:
				# The seeker diamond ±7 px, held inside the field along the line from the centre (FUN_0052db30).
				var d: Vector2 = _pt(waypoint_marker_point(wp.seeker, _field()))
				var k := 7.0 * s
				draw_polyline(PackedVector2Array([d + Vector2(0, -k), d + Vector2(k, 0), d + Vector2(0, k), d + Vector2(-k, 0), d + Vector2(0, -k)]), col, w)
			if mode == 2 and wp.get("mrm_point") != null:
				_draw_mrm_point(wp.mrm_point, s, w, col)
		7, 8:
			# HARM (FUN_0052fef0) / TV (FUN_0052fa10 case 7): the seeker diamond (FUN_00536ff0, ±7 px) on the selected
			# emitter's / the EO centre point's projection, held inside the field along the line from the HUD centre.
			var hp = wp.get("harm_point" if mode == 8 else "tv_point")
			if hp != null and camera != null and host_world_to_scene.is_valid():
				var sp: Vector3 = host_world_to_scene.call(hp)
				if not camera.is_position_behind(sp):
					var d := clip_toward(_c, camera.unproject_position(sp) - position)
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
				var lk: Dictionary = cockpit.radar.get("lock", {})
				_pipper_at = {"p": pipper_clamp(p, Rect2(Vector2.ZERO, size), s),
					"arc": range_arc(float(lk.dist)) if not lk.is_empty() else 0.0}
		5, 6:
			_draw_ag(wp.get("ag", {}), s, w, col)


## The gun pipper (FUN_00530040, HUD modes 3 / 4) on `outer`: the 32×32 sprite and, with a radar lock, the range arc
## (pen 2 px, r 11 px about the pipper centre) from 12 o'clock clockwise by `arc`.
func _draw_pipper(p: Vector2, arc: float, w: float) -> void:
	var col: Color = cockpit.hud_colour()
	var t := _pipper_tex()
	if t != null:
		outer.draw_texture_rect(t, Rect2(p - Vector2(16, 16) * _s, Vector2(32, 32) * _s), false)
	else:
		outer.draw_arc(p, 8 * _s, 0, TAU, 24, col, w)
	if arc > 0.0:
		outer.draw_arc(p, 11.0 * _s, -PI / 2.0, -PI / 2.0 + arc, 32, col, 2.0 * w)


## FUN_00530040: the pipper's centre is held inside the field `f` (HUD px): x in [left, right], y in
## [top, bottom − 2] (the sprite's corner clamped to −16 / −16 / −16 / −18).
static func pipper_clamp(p: Vector2, f: Rect2, s: float) -> Vector2:
	return Vector2(clampf(p.x, f.position.x, f.end.x), clampf(p.y, f.position.y, f.end.y - 2.0 * s))


## FUN_00530040's range arc: the lock range (S+0x388, NM = m × 0.00053937, at least 0) → r·0.5·2π rad; none (0) from
## 1.95 NM up or at most 0.05236 rad (3°).
static func range_arc(dist_m: float) -> float:
	var nm := maxf(dist_m * 0.00053937, 0.0)
	if nm >= 1.95:
		return 0.0
	var a := nm * 0.5 * TAU
	return a if a > 0.05235987715423107 else 0.0


## The MRM's predicted target point (FUN_00536ea0, state+0xe74): a 5×5 blob of lines; clipped to the HUD
## rectangle it blinks (300 ms phases).
func _draw_mrm_point(p_world: Vector3, s: float, w: float, col: Color) -> void:
	if camera == null or not host_world_to_scene.is_valid():
		return
	var sp: Vector3 = host_world_to_scene.call(p_world)
	if camera.is_position_behind(sp):
		return
	var p := camera.unproject_position(sp) - position
	var r := Rect2(Vector2.ZERO, size)
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	if q != p and (Time.get_ticks_msec() / 300) % 2 == 1:
		return
	for row in [[-1, 1, -2], [-2, 2, -1], [-2, 2, 0], [-2, 2, 1], [-1, 2, 2]]:
		draw_line(q + Vector2(row[0], row[2]) * s, q + Vector2(row[1], row[2]) * s, col, w)


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
	return {"off": true, "origin": camera.project_ray_origin(c), "dir": ray_normal(camera, c)}


## The camera's ray direction (scene, normalized) through viewport point `p`. Camera3D.project_ray_normal and
## project_position ignore the frustum offset of the cockpit camera (PROJECTION_FRUSTUM), so the ray comes from
## the inverse of the camera's projection matrix itself (the inverse of unproject_position).
static func ray_normal(cam: Camera3D, p: Vector2) -> Vector3:
	var vs := cam.get_viewport().get_visible_rect().size
	var ndc := Vector4(p.x / vs.x * 2.0 - 1.0, 1.0 - p.y / vs.y * 2.0, 0.5, 1.0)
	var q: Vector4 = cam.get_camera_projection().inverse() * ndc
	var local := Vector3(q.x, q.y, q.z) / q.w
	return (cam.global_basis.orthonormalized() * local).normalized()


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
	# The shoot cue (state+0x1010 in HUD modes 1 / 2): a triangle under the box, apex 2h − 6 px below its centre,
	# base 2h below, ±3 px.
	if bool(cockpit.weapons.get("shoot", false)) and _mode() in [1, 2]:
		var l := 2.0 * h
		var a := p + Vector2(0, l - 6.0 * _s)
		draw_polyline(PackedVector2Array([a, p + Vector2(3, 0) * _s + Vector2(0, l), p + Vector2(-3, 0) * _s + Vector2(0, l), a]), col, w)


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


## The waypoint marker (FUN_00537b30, S+0x102c: NAV and HUD modes 4..8, FUN_00450460): the current waypoint
## on the ground (S+0x70 at the terrain height, projected into S+0x328) as a 10 px circle, held on the field's
## edge along the line from the HUD centre (FUN_0052db30), labelled "%d" (its number) or "T" for a target
## waypoint (action 5) in Arial at (+6, +6).
func _draw_waypoint_marker(w: float) -> void:
	var m := _mode()
	if not (m == 0 or (m >= 4 and m <= 8)) or cockpit.waypoints.is_empty() or camera == null or not host_world_to_scene.is_valid():
		return
	var i := clampi(cockpit.current_waypoint, 0, cockpit.waypoints.size() - 1)
	var wpt: Dictionary = cockpit.waypoints[i]
	var z := 0.0
	if host_ground.is_valid():
		var g = host_ground.call(wpt.world.x, wpt.world.y)
		z = float(g) if g != null else 0.0
	var sp: Vector3 = host_world_to_scene.call(Vector3(wpt.world.x, wpt.world.y, z))
	var p: Vector2
	if camera.is_position_behind(sp):
		var d := camera.global_basis.inverse() * (sp - camera.global_position)
		p = Vector2(d.x, -d.y).normalized() * 10000.0
	else:
		p = (camera.unproject_position(sp) - position - _c) / _s
	p = waypoint_marker_point(p, _field())
	var c := _pt(p)
	draw_arc(c, 4.5 * _s, 0, TAU, 24, cockpit.hud_colour(), w)
	_gdi(self, p + Vector2(6, 6), "T" if int(wpt.get("action", 0)) == 5 else str(i + 1))


## FUN_0052db30: a point outside the field `f` moves along the line from the HUD centre to the field's edge.
static func waypoint_marker_point(p: Vector2, f: Rect2) -> Vector2:
	if f.has_point(p) or p == Vector2.ZERO:
		return p
	var k := 1.0
	if p.x < f.position.x:
		k = minf(k, f.position.x / p.x)
	if p.x > f.end.x:
		k = minf(k, f.end.x / p.x)
	if p.y < f.position.y:
		k = minf(k, f.position.y / p.y)
	if p.y > f.end.y:
		k = minf(k, f.end.y / p.y)
	return p * k
