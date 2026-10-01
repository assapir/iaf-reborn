# The original 2D cockpit of any aircraft, laid out from its converted cockpit.ibx (cockpit.json).
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
const Img := preload("res://util/img.gd")
const Tsd := preload("res://menu/tsd.gd")
const PANEL_CENTRE_X := 960.0
## HUD colour table (renderer+0x2864, COLORREFs 0x2400 … 0xbcf8): eight greens dark to bright,
## near-white, red, amber. Index 0 at the start of a run; key H cycles (idx + 1) % 11 (docs/mfd.md §2).
const HUD_COLOURS := [Color8(0, 0x24, 0), Color8(0, 0x34, 0), Color8(0, 0x54, 0), Color8(0, 0x6c, 0),
	Color8(0, 0x88, 0), Color8(0, 0xa4, 0), Color8(0, 0xe4, 0), Color8(0, 0xfc, 0),
	Color8(0xf8, 0xf4, 0xf0), Color8(0xf8, 0, 0), Color8(0xf8, 0xbc, 0)]
## Kept for the run (the original's global 0x82f4c4), not saved.
static var hud_colour_index := 0


static func hud_colour() -> Color:
	return HUD_COLOURS[hud_colour_index]

## Under assets/.
@export var cockpit_dir := "converted/cockpits/f16"

## Flight state shown by the instruments. Angles in degrees, speed in knots,
## altitude in feet, vertical speed in ft/min, fuel in lbs, rpm/throttle 0..1.
var state := {
	"speed_kt": 0.0, "mach": 0.0, "alt_ft": 0.0, "vs_fpm": 0.0,
	"pitch": 0.0, "roll": 0.0, "heading": 0.0, "aoa": 0.0, "g": 1.0,
	"rpm": 0.0, "throttle": 0.0, "fuel_lbs": 0.0,
	"world": Vector2.ZERO,  # ownship in mission world coordinates (X east, Y north, metres)
}
## The weapons snapshot for the HUD and the stores page (player_weapons.gd _publish; {} = none).
var weapons := {}
## Stores page station buttons (event 0x4c(station)), set by the flight scene.
var on_station_select: Callable
## The player's route: [{name, world: Vector2}], and the current waypoint index.
var waypoints: Array = []
var current_waypoint := 0
## The MFD TSD map (map.emf) as world-coordinate polygons: [{points, color}].
var tsd_map: Array = []
var mfds: Array = []

## Panel lights (docs/cockpit.md "Panel lights"). Indicators 0..8: master, (left) engine fire,
## right engine fire, AI, SAM, air brake, ECM, hook, autopilot; the gear handle (LIGHT009) follows
## `gear_handle_down`; SLIGHT000..002 show the gear legs, SLIGHT003 the flaps (0 up / 1 moving / 2 down).
var indicators := [false, false, false, false, false, false, false, false, false]
## The player's damage flags 0..24 (docs/damage.md §5) for the MFD damage page, and whether the jet
## has two engines (damage page ENG L / ENG R rows).
var damage_flags: Array = []
var twin_engines := false
var gear_handle_down := true
var gear_legs := [2, 2, 2]
var flaps_state := 0
var _blink := {}  # light index -> [phase, ms]
var _handle_frame := -1
var _handle_ms := 0.0
## Mission subtitle console lines (newest last), drawn at x=4, y=10+15n of the 640x480 screen in
## 12 px Arial and the HUD colour (FUN_005201b0).
var subtitles: Array[String] = []
var _console_font: SystemFont
var _counter_font: SystemFont
var _console_squeeze := 1.0
## How far the panel is raised: 0 = forward view (original MainOffsetY), 1 = full panel
## ("panel down" view). `panel_target` is where it is sliding to.
var panel_shift := 0.6
var panel_target := 0.6
const PANEL_SLIDE_SPEED := 2.5  # full travel per second
## 1.0 = the original proportions (640x480 scaled to the screen); smaller shows more world.
var zoom := 0.6
const ZOOM_MIN := 0.6
const ZOOM_MAX := 1.0

var layout := {}
var tex := {}
var mfd_font: FontFile
var dir := ""
@onready var hud: Control = $Hud


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dir = Settings.assets_dir().path_join(cockpit_dir)
	layout = Settings.load_json(dir.path_join("cockpit.json"))
	if layout.is_empty():
		push_error("cockpit: %s/cockpit.json not found — run iaf-convert cockpit" % dir)
		return
	for key in ["PANEL", "HUD", "LENHORIZON", "PANELVARIO", "PANELAOA"]:
		var file: String = layout.get(key, {}).get("FileName", "")
		if file != "":
			_add_tex(key, file, true)
	var lights_file: String = layout.get("LIGHTSON", {}).get("FileName", "")
	if lights_file != "":
		_add_tex("LIGHTS", lights_file)
	_add_tex("MFDS", "mfds.bmp")
	_load_tsd_map()
	_create_mfds()
	hud.cockpit = self


## The converted art of an original cockpit image file (lower-case .png), when present.
func _add_tex(key: String, file: String, mipmaps := false) -> void:
	var t := Img.load_texture(dir.path_join(file.get_basename().to_lower() + ".png"), mipmaps)
	if t != null:
		tex[key] = t


## map.emf points (normalised to its 12601 x 16383 frame) -> world (FUN_00531a50 inverse), in the
## TSD's world frame: u = (X + WORLD_X_SHIFT) / WORLD_W · f, v = (WORLD_H − WORLD_Y_SHIFT − Y) / WORLD_H · f
## with f = MAP_X_FACTOR (1043816 = WORLD_H − WORLD_Y_SHIFT).
func _load_tsd_map() -> void:
	var data := Settings.load_json(dir.path_join("map.json"))
	if data.is_empty():
		return
	var f: float = Tsd.MAP_X_FACTOR
	for op in data.ops:
		if op.t != "polygon" or op.brush == null:
			continue
		var pts := PackedVector2Array()
		var ring: Array = op.rings[0]
		for i in range(0, ring.size(), 2):
			pts.append(Vector2(ring[i] / f * Tsd.WORLD_W - Tsd.WORLD_X_SHIFT, Tsd.WORLD_H - Tsd.WORLD_Y_SHIFT - ring[i + 1] / f * Tsd.WORLD_H))
		tsd_map.append({"points": pts, "color": Color8(op.brush[0], op.brush[1], op.brush[2])})


## One MFD node per active [MFD] side, with the default pages of FUN_00448120: Left radar;
## 3 MFDs: Right RWR, Middle TSD; 2 MFDs: Right RWR without a panel RWR, else TSD.
func _create_mfds() -> void:
	var m: Dictionary = layout.get("MFD", {})
	var active := []
	for i in 3:
		if int(m.get(["Left", "Right", "Middle"][i] + "Active", 1)) == 1:
			active.append(i)
	var rwr_panel := int(layout.get("PANELRWR", {}).get("Active", 0)) == 1
	for i in active:
		var page := 2
		if i == 1:
			page = 7 if active.size() == 3 or not rwr_panel else 3
		elif i == 2:
			page = 3
		var node := preload("res://cockpit/mfd.gd").new()
		node.setup(self, i, page)
		add_child(node)
		mfds.append(node)


## "Activate TSD / Damage report" keys (event 0x5a): the page replaces Left, or Right when Left
## shows the radar; ignored when already shown.
func show_mfd_page(page: int) -> void:
	for m in mfds:
		if m.page == page:
			return
	if mfds.is_empty():
		return
	var target = mfds[0]
	if target.page == 2 and mfds.size() > 1:
		target = mfds[1]
	target.page = page


## The MFD showing the radar (radar keys first put the radar on the Left MFD if none shows it).
func radar_mfd() -> Node:
	for m in mfds:
		if m.page == 2:
			return m
	if mfds.is_empty():
		return null
	mfds[0].page = 2
	return mfds[0]


## Screen scale factor from the original 640x480 layout.
func ui_scale() -> float:
	return size.y / ORIGINAL_HEIGHT * zoom


## Real F-16 HUD field of view through the combiner glass, degrees.
const HUD_REAL_FOV := 25.0
## Width of the combiner glass in the original HUD art (the frame is 319 px wide).
const HUD_GLASS_PIXELS := 200.0

## Vertical field of view for the 3D world, chosen so the HUD glass spans its real ~25° of
## the world at any zoom (zooming out widens the view instead of shrinking the world).
func world_fov() -> float:
	var glass_px := HUD_GLASS_PIXELS * ui_scale()
	var px_per_rad := (glass_px / 2.0) / tan(deg_to_rad(HUD_REAL_FOV) / 2.0)
	return rad_to_deg(2.0 * atan((size.y / 2.0) / px_per_rad))


## Top of the panel in screen pixels. The forward view shows only the top part of the
## panel (pushed down by MainOffsetY, like the original); the down view shows all of it.
func panel_top() -> float:
	var p: Dictionary = layout.get("PANEL", {})
	var height: float = p.get("PanelHeight", 352)
	var shown: float = height - p.get("MainOffsetY", 190) * (1.0 - panel_shift)
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


## One PgUp/PgDn step: a tenth of the panel's travel (positive = show more panel).
const PANEL_STEP := 0.1


## Move the panel by `steps` PgUp/PgDn steps (animated).
func slide_panel(steps: int) -> void:
	panel_target = clamp(snappedf(panel_target + steps * PANEL_STEP, PANEL_STEP), 0.0, 1.0)


## V: jump to the other end of the travel (animated).
func toggle_panel() -> void:
	panel_target = 0.0 if panel_target > 0.5 else 1.0


func _process(delta: float) -> void:
	panel_shift = move_toward(panel_shift, panel_target, PANEL_SLIDE_SPEED * delta)
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

	_draw_lights(s)
	_draw_needle("SPEEDCLOCK", state.speed_kt, s)
	_draw_needle("ALTITUDELOCK", state.alt_ft, s)
	_draw_needle("RPMCLOCK", state.rpm, s)
	_draw_needle("THROTTLECLOCK", state.throttle, s)
	_draw_needle("TEMPCLOCK", lerp(0.25, 0.7, state.rpm), s)
	var fuel: Dictionary = layout.get("FUELDIGITAL", {})
	if fuel.get("Active", 0) == 1:
		var col := Color8(int(fuel.ColorR), int(fuel.ColorG), int(fuel.ColorB))
		if mfd_font == null:
			mfd_font = preload("res://cockpit/hud.gd").load_original_font("mfd")
		var font: Font = mfd_font if mfd_font != null else get_theme_default_font()
		draw_string(font, panel_to_screen(fuel.OffsetX, fuel.OffsetY + 9), "%05d" % int(state.fuel_lbs),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), col)

	_draw_decoy_counters(s)
	_draw_console()
	if tex.has("HUD"):
		var h: Dictionary = layout.HUD
		var w: float = h.Width * s
		var hh: float = h.Height * s
		draw_texture_rect(tex.HUD, Rect2(size.x / 2 - w / 2, panel_top() - hh, w, hh), false)
	_draw_weapon_line(s)


## The HUD text block's weapon row (FUN_0052ef20 pass 3): left column at the HUD centre − TxtOffX, rows
## 7 px apart from the centre + TxtOffY, row 2 = "%1d %s %s" (total of the selected store, name,
## RDY / MAL), "NAV" in HUD mode 0. On the glass, not clipped to the symbology field. (The original
## draws it with the MFD sprite font; ours with the HUD font.)
func _draw_weapon_line(s: float) -> void:
	if weapons.is_empty() or not layout.has("HUD"):
		return
	var h: Dictionary = layout.HUD
	var fs := int(8 * s)
	if fs < 1:
		return
	var centre := Vector2(size.x / 2, panel_top() - float(h.CenterY) * s)
	var line := "NAV" if int(weapons.hud_mode) == 0 else "%d %s %s" % [int(weapons.total), weapons.name, "RDY" if weapons.ready else "MAL"]
	var at := centre + Vector2(-float(h.get("TxtOffX", 82)), float(h.get("TxtOffY", 48)) + 2 * 7 + 6) * s
	var font: Font = hud.hud_font if hud.hud_font != null else get_theme_default_font()
	draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud_colour())


## Chaff / flare counters (FUN_0052eab0): "%03d" of stores stations 10 / 11 at [CHAFF] / [FLARE]
## OffX / OffY (default 36 / 36), Arial h10 w5, pale yellow 0xb3ffff = RGB(255, 255, 179), top-left.
func _draw_decoy_counters(s: float) -> void:
	if weapons.is_empty():
		return
	if _counter_font == null:
		_counter_font = Img.arial()
	var fs := int(round(10.0 / 1.15 * s))
	if fs < 1:
		return
	for pair in [["CHAFF", "chaff"], ["FLARE", "flares"]]:
		var c: Dictionary = layout.get(pair[0], {})
		var at := panel_to_screen(float(c.get("OffX", 36)), float(c.get("OffY", 36)))
		draw_string(_counter_font, at + Vector2(0, _counter_font.get_ascent(fs)), "%03d" % int(weapons.get(pair[1], 0)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(255, 255, 179))


func _draw_console() -> void:
	if subtitles.is_empty():
		return
	var s := size.y / ORIGINAL_HEIGHT
	# CreateFontA(12, 4, …, "ARIAL"): a 12 px cell (em = 12 / 1.15) with a 4 px average character
	# width: Arial squeezed horizontally to that width.
	var em := 12.0 / 1.15
	if _console_font == null:
		_console_font = Img.arial()
		var avg: float = _console_font.get_string_size("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 52.0 / 100.0 * em
		_console_squeeze = 4.0 / avg
	var fs := int(round(em * s))
	if fs < 1:
		return
	var left := size.x / 2 - 320.0 * s
	for n in subtitles.size():
		var pos := Vector2(left + 4 * s, (10 + 15 * n) * s + _console_font.get_ascent(fs))
		draw_set_transform(pos, 0.0, Vector2(_console_squeeze, 1.0))
		draw_string(_console_font, Vector2.ZERO, subtitles[n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud_colour())
	draw_set_transform(Vector2.ZERO)


## One frame of a light (frames stacked under Top in the lights bitmap) at its panel position.
func _draw_light(l: Dictionary, frame: int, s: float) -> void:
	if int(l.get("Active", 0)) != 1 or not tex.has("LIGHTS"):
		return
	var a: float = layout.get("image_scale", 1)
	var w := float(l.Right) - float(l.Left)
	var h := float(l.Bottom) - float(l.Top)
	var src := Rect2(float(l.Left), float(l.Top) + frame * h, w, h)
	draw_texture_rect_region(tex.LIGHTS, Rect2(panel_to_screen(l.OffsetX, l.OffsetY), Vector2(w, h) * s),
			Rect2(src.position * a, src.size * a))


func _draw_lights(s: float) -> void:
	var dt := get_process_delta_time() * 1000.0
	for i in 9:
		var l: Dictionary = layout.get("LIGHT%03d" % i, {})
		if l.is_empty():
			continue
		var frame := 1 if indicators[i] else 0
		if int(l.get("Blink", 0)) == 1:
			# Blinking lights alternate dark / lit every 300 ms, starting dark.
			var b: Array = _blink.get(i, [0, 0.0])
			if indicators[i]:
				b[1] += dt
				if b[1] > 300.0:
					b[1] = 0.0
					b[0] = 1 - b[0]
			else:
				b = [0, 0.0]
			_blink[i] = b
			frame = b[0]
		_draw_light(l, frame, s)
	# Gear handle: steps one frame per AnimTime / AnimFrames ms toward its end frame.
	var hl: Dictionary = layout.get("LIGHT009", {})
	if not hl.is_empty():
		var frames := maxi(1, int(hl.get("AnimFrames", 2)))
		var target := frames - 1 if gear_handle_down else 0
		if _handle_frame < 0:
			_handle_frame = target
		var step_ms := float(int(float(hl.get("AnimTime", 2000)) / frames))
		if _handle_frame != target:
			_handle_ms += dt
			if _handle_ms >= step_ms:
				_handle_ms = 0.0
				_handle_frame += signi(target - _handle_frame)
		_draw_light(hl, _handle_frame, s)
	for j in 4:
		var sl: Dictionary = layout.get("SLIGHT%03d" % j, {})
		if not sl.is_empty():
			var v: int = gear_legs[j] if j < 3 else flaps_state
			_draw_light(sl, v if v >= 0 and v <= 2 else 0, s)


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
	if h.is_empty() or h.get("OnMfd", 0) != 0 or h.get("Active", 1) != 1:
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
