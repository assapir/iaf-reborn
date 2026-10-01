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
	"rpm": 0.0, "throttle": 0.0, "fuel_lbs": 0.0, "internal_fuel_kg": 0.0, "agl_ft": 0.0,
	"world": Vector2.ZERO,  # ownship in mission world coordinates (X east, Y north, metres)
}
## The weapons snapshot for the HUD and the stores page (player_weapons.gd _publish; {} = none).
var weapons := {}
## Stores page station buttons (event 0x4c(station)), set by the flight scene.
var on_station_select: Callable
## The radar snapshot (player_weapons.gd radar_snapshot()) and its key events (radar_event(ev, arg)).
var radar := {}
var on_radar_event: Callable
## The RWR copy (FUN_00446200 → state+0xe80..: the first `count` slots): [{type, pos: Vector2, launch, active}].
var rwr: Array = []
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
## What the view draws (FUN_0051f8e0, docs/views.md §4): 0 the cockpit (types 1, 0x12, 0x16), 1 the HUD only
## (type 5), 2 only the message lines (every external view).
var view_mode := 0
## Head yaw / pitch (radians, right / up +): the panel art pans with them (FUN_0051f610, docs/cockpit.md "Pans").
var head := Vector2.ZERO
## Time compression rate (sim clock +0x48 via HUD +0x10f4): "%1dX" top right while > 1 (docs/views.md §2).
var time_factor := 1
var _console_font: SystemFont
var _counter_font: SystemFont
var _console_squeeze := 1.0
## How far the panel is raised: 0 = forward view (original MainOffsetY), 1 = full panel
## ("panel down" view). `panel_target` is where it is sliding to.
var panel_shift := 0.8
var panel_target := 0.8
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
	load_cockpit(cockpit_dir)


## Loads the cockpit `rel` (e.g. "converted/cockpits/f4-2000"): layout, art, TSD map and MFDs. A second call
## replaces the first (the flight scene loads the player's jet's cockpit once it knows the type).
func load_cockpit(rel: String) -> void:
	cockpit_dir = rel
	for m in mfds:
		m.free()
	mfds.clear()
	tex.clear()
	tsd_map.clear()
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
	_add_tex("RWRSYMB", "rwrsymb.bmp")
	_measure_view_bottom()
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


## The original 3D projection (docs/cockpit.md "3D view"): viewport 0 has a 50° field of view across
## its 640 px width (renderer+0x1ac, FUN_004d9790 → TgenAPI FUN_00403a20), so the focal length is
## 320 / tan 25° = 686.2 px of the 640x480 screen (FUN_00413f90), with square pixels.
const VIEW_FOV_DEG := 50.0
const VIEW_WIDTH := 640.0
## The cockpit camera looks this far below the nose axis (v1.1 FUN_00585270: max(head pitch − 5.5°,
## 0.1·(|head yaw| − 90°)) with the head straight ahead; v1.0 8°).
const VIEW_LOOK_DOWN_DEG := 5.5


## Focal length of the 3D view in screen pixels: the original's, scaled like the 2D art. A wider or
## taller window keeps it and shows more of the world around the original frame.
func focal_length() -> float:
	return VIEW_WIDTH / 2.0 / tan(deg_to_rad(VIEW_FOV_DEG) / 2.0) * ui_scale()


## Bottom of the original 3D viewport below the panel top (original pixels, straight-ahead view):
## the viewport ends where the panel's see-through area ends at the two screen-edge columns
## (FUN_0052e750 → FUN_0052e6a0), ((D + MainOffsetY + 7) & ~7) capped at 480 (FUN_0051f610).
var _view_bottom := 480.0


## The original viewport's projection centre: the middle of the viewport rows [0, bottom) and the
## screen's centre column (FUN_00413f90), placed like the 2D art (relative to the panel top).
func projection_centre() -> Vector2:
	var main_y: float = layout.get("PANEL", {}).get("MainOffsetY", 190)
	return Vector2(size.x / 2, panel_top() + (_view_bottom / 2.0 - main_y) * ui_scale())


## D of FUN_0052e750 for the straight-ahead pan (screen columns 0 and 640 = panel x 640 and 1280):
## per column, the panel row below its lowest transparent pixel inside its 320-px slice (slices start
## at {MaskOffsetY1, MaskOffsetY2, 0, 0, MaskOffsetY2, MaskOffsetY1}); the slice top if none.
func _measure_view_bottom() -> void:
	var p: Dictionary = layout.get("PANEL", {})
	var main_y: float = p.get("MainOffsetY", 190)
	var img: Image = tex.PANEL.get_image() if tex.has("PANEL") else null
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var a: float = layout.get("image_scale", 1)
	var y1: float = p.get("MaskOffsetY1", 0)
	var y2: float = p.get("MaskOffsetY2", 0)
	var starts := [y1, y2, 0.0, 0.0, y2, y1]
	var d := 0
	for x in [640, 1280]:
		var top := int(starts[x / 320])
		var col := top
		for y in range(int(img.get_height() / a) - 1, top - 1, -1):
			if img.get_pixel(int((x + 0.5) * a), int((y + 0.5) * a)).a < 0.5:
				col = y + 1
				break
		d = maxi(d, col)
	_view_bottom = minf(480.0, (d + int(main_y) + 7) & ~7)


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
	position = head_pan() * ui_scale() if view_mode == 0 else Vector2.ZERO
	hud.visible = view_mode != 2
	for m in mfds:
		m.visible = view_mode == 0
	queue_redraw()
	hud.queue_redraw()


## The panel's screen shift for the head angles (original pixels): pan = 1920 / AzimutAngleDeg (rad) · yaw,
## vpan = (PanelHeight + [HUD] CenterY) / ElevationAngleDeg (rad) · pitch, vpan ≥ 480 − MainOffsetY −
## PanelHeight; the panel moves left by pan and down by vpan.
func head_pan() -> Vector2:
	if head == Vector2.ZERO:
		return Vector2.ZERO
	var p: Dictionary = layout.get("PANEL", {})
	var az := deg_to_rad(float(p.get("AzimutAngleDeg", 90.0)))
	var el := deg_to_rad(float(p.get("ElevationAngleDeg", 15.0)))
	var ph := float(p.get("PanelHeight", 352))
	var pan := roundf(1920.0 / az * head.x)
	var vpan := maxf(roundf((ph + float(layout.get("HUD", {}).get("CenterY", 0))) / el * head.y),
			480.0 - float(p.get("MainOffsetY", 190)) - ph)
	return Vector2(-pan, vpan)


func _draw() -> void:
	if layout.is_empty():
		return
	if view_mode != 0:
		if _lens != null:
			_lens.visible = false
		_draw_console()
		return
	var s := ui_scale()
	_draw_adi(s)
	_draw_standby_horizon(s)
	# The tapes (FUN_005280b0 / FUN_00528270): the window shows the tape's middle at 0, moved Height / 60000 px per
	# ft/min (vario, up for a climb) and Height / 50 px per degree of AoA (S+0x50, down), truncated.
	var vario: Dictionary = layout.get("PANELVARIO", {})
	_draw_tape("PANELVARIO", -int(state.vs_fpm * float(vario.get("Height", 0)) / 60000.0), s)
	var aoa: Dictionary = layout.get("PANELAOA", {})
	_draw_tape("PANELAOA", int(float(aoa.get("Height", 0)) * 0.02 * state.aoa), s)

	var p: Dictionary = layout.PANEL
	if tex.has("PANEL"):
		var tl := panel_to_screen(0, 0)
		var art_scale: float = layout.get("image_scale", 1)
		var width: float = tex.PANEL.get_width() / art_scale
		draw_texture_rect(tex.PANEL, Rect2(tl, Vector2(width, p.PanelHeight) * s), false)

	_draw_lights(s)
	_draw_panel_rwr(s)
	_draw_needle("SPEEDCLOCK", state.speed_kt, s)
	# The altimeter (FUN_00527c10) ignores FullClock: a long needle at one turn per 1000 ft and one 3 px shorter at
	# one turn per 10,000 ft.
	_draw_needle("ALTITUDELOCK", state.alt_ft, s, 1000.0)
	_draw_needle("ALTITUDELOCK", state.alt_ft, s, 10000.0, 3.0)
	# Engine needles (@45ac00, docs/cockpit.md "Round gauges"): all from the flight model's rpm, per engine with
	# its damage flags; the second engine (the *SECONDARY needles, twin-engine cockpits) reads the same rpm.
	for e in 2:
		var n := _engine_needles(e)
		var sfx := "SECONDARY" if e == 1 else ""
		_draw_needle("THROTTLECLOCK" + sfx, n[0], s)
		_draw_needle("RPMCLOCK" + sfx, n[1], s)
		_draw_needle("TEMPCLOCK" + sfx, n[2], s)
	# Round gauges of the cockpits without the F-16's digits / tape (FUN_00527a40): FUELCLOCK "LBS x1000 TOTAL
	# INTERNAL" = total fuel / internal capacity, capped at 1 (@45acb9); VARIOCLOCK "CLIMB 1000 FT/MIN" = ft/min
	# (FUN_004459a0, m/s · 196.848).
	var cap: float = state.get("internal_fuel_kg", 0.0)
	_draw_needle("FUELCLOCK", clampf(state.fuel_lbs * 0.45359 / cap, 0.0, 1.0) if cap > 0.0 else 0.0, s)
	_draw_needle("VARIOCLOCK", state.vs_fpm, s)
	var fuel: Dictionary = layout.get("FUELDIGITAL", {})
	if fuel.get("Active", 0) == 1:
		var col := Color8(int(fuel.ColorR), int(fuel.ColorG), int(fuel.ColorB))
		var font := digits_font()
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
	# With a radar lock: "R %2.1f" (NM, ×0.00053937, 0x600f58) and, in HUD modes 1 and 3, the aspect
	# "%2dL" / "%2dR" on the waypoint row (rows 0 / 1: placement UNCERTAIN).
	var lk: Dictionary = radar.get("lock", {})
	if not lk.is_empty():
		draw_string(font, at - Vector2(0, 2 * 7) * s, "R %2.1f" % (float(lk.dist) * 0.00053937), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud_colour())
		if int(weapons.hud_mode) in [1, 3]:
			draw_string(font, at - Vector2(0, 7) * s, preload("res://cockpit/mfd.gd").aspect_text(float(lk.aspect)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud_colour())


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
	if subtitles.is_empty() and time_factor <= 1:
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
	var left := size.x / 2 - 320.0 * s - position.x  # the message lines do not pan with the panel
	for n in subtitles.size():
		var pos := Vector2(left + 4 * s, (10 + 15 * n) * s + _console_font.get_ascent(fs) - position.y)
		draw_set_transform(pos, 0.0, Vector2(_console_squeeze, 1.0))
		draw_string(_console_font, Vector2.ZERO, subtitles[n], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud_colour())
	# Time compression (FUN_005201b0 @520414): "%1dX" (0x65c6c4) with TA_RIGHT at (630, 10), same font
	# and colour, while the rate is > 1.0.
	if time_factor > 1:
		var t := "%1dX" % time_factor
		var w := _console_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * _console_squeeze
		draw_set_transform(Vector2(left + 630 * s - w, 10 * s + _console_font.get_ascent(fs) - position.y), 0.0, Vector2(_console_squeeze, 1.0))
		draw_string(_console_font, Vector2.ZERO, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hud_colour())
	draw_set_transform(Vector2.ZERO)


## rwrsymb.bmp glyph row (10 × 10 at (0, y)) per emitter bdb type code (FUN_00531470): SAM / AAA radars
## 290–390, aircraft 100–200; other types are not drawn.
const RWR_GLYPH := {290: 0, 300: 10, 310: 20, 320: 30, 330: 40, 340: 50, 360: 60, 380: 60, 390: 60, 350: 70,
	150: 80, 160: 90, 180: 100, 170: 110, 120: 120, 200: 120, 110: 130, 100: 140, 130: 150, 190: 150, 140: 160}
## The RWR distance scale: 37060 m (0x60c3d8 / 0x60c3e0) at the radius, farther emitters on the rim.
const RWR_RANGE := 37060.0


## The RWR symbols (FUN_00531470) on `ci` about `centre` with `radius` (the MFD page: (66,66) r 56; the panel
## dial: [PANELRWR] Center / Radius), `s` = canvas px per original px: heading-up, the active entries,
## launch-flag ones blinking at 300 ms.
func draw_rwr_symbols(ci: CanvasItem, centre: Vector2, radius: float, s: float) -> void:
	if not tex.has("RWRSYMB"):
		return
	var a: float = layout.get("image_scale", 1)
	var own: Vector2 = state.get("world", Vector2.ZERO)
	var hdg := deg_to_rad(float(state.heading))
	var blink_on := int(Time.get_ticks_msec() / 300) % 2 == 0
	for e in rwr:
		if not e.active or not RWR_GLYPH.has(int(e.type)):
			continue
		if e.launch and not blink_on:
			continue
		var off := rwr_offset(e.pos, own, hdg, radius)
		var src := Rect2(0, RWR_GLYPH[int(e.type)], 10, 10)
		ci.draw_texture_rect_region(tex.RWRSYMB, Rect2(centre + (off - Vector2(5, 5)) * s, Vector2(10, 10) * s),
				Rect2(src.position * a, src.size * a))


## An emitter's symbol centre from the dial centre (FUN_00531470 @53160d): heading-up, 37060 m = radius, the
## horizontal offset clamped to 37060 m, each axis truncated.
static func rwr_offset(pos: Vector2, own: Vector2, hdg: float, radius: float) -> Vector2:
	var k := RWR_RANGE / radius
	var S := sin(hdg)
	var C := cos(hdg)
	var dx: float = pos.x - own.x
	var dy: float = own.y - pos.y
	var d := sqrt(dx * dx + dy * dy)
	if d > RWR_RANGE:
		dx = dx / d * RWR_RANGE
		dy = dy / d * RWR_RANGE
	return Vector2(int((C * dx + S * dy) / k), int((C * dy - S * dx) / k))


## The panel RWR dial (FUN_00531330, [PANELRWR] Active): the symbols at Center with Radius; nothing with RWR
## damage (state+0x590 = damage flag 14).
func _draw_panel_rwr(s: float) -> void:
	var r: Dictionary = layout.get("PANELRWR", {})
	if int(r.get("Active", 0)) != 1 or (damage_flags.size() > 14 and damage_flags[14]):
		return
	draw_rwr_symbols(self, panel_to_screen(float(r.CenterX), float(r.CenterY)), float(r.Radius), s)


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


## The lens ADI ([LENHORIZON], FUN_005276f0): the ball shader (lens_adi.gdshader) on a 2R square behind the
## panel (show_behind_parent), seen through the panel's hole. Roll / pitch: the state's (S+0x10 / S+0xc).
var _lens: ColorRect


func _draw_adi(s: float) -> void:
	var a: Dictionary = layout.get("LENHORIZON", {})
	var on: bool = a.get("Active", 0) == 1 and tex.has("LENHORIZON")
	if on and _lens == null:
		_lens = ColorRect.new()
		_lens.show_behind_parent = true
		_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lens.material = ShaderMaterial.new()
		_lens.material.shader = preload("res://cockpit/lens_adi.gdshader")
		add_child(_lens)
	if _lens == null:
		return
	_lens.visible = on
	if not on:
		return
	var r := float(a.Radius)
	_lens.position = panel_to_screen(a.CenterX, a.CenterY) - Vector2(r, r) * s
	_lens.size = Vector2(2 * r, 2 * r) * s
	var m: ShaderMaterial = _lens.material
	m.set_shader_parameter("ball", tex.LENHORIZON)
	m.set_shader_parameter("radius", r)
	m.set_shader_parameter("factor", float(a.Factor))
	m.set_shader_parameter("roll", deg_to_rad(state.roll))
	m.set_shader_parameter("pitch", state.pitch)


## The panel horizon disc ([HORIZON] with OnMfd 0, FUN_005268b0): drawn under the panel, shown through its hole.
func _draw_standby_horizon(s: float) -> void:
	var h: Dictionary = layout.get("HORIZON", {})
	if h.is_empty() or int(h.get("OnMfd", 0)) != 0 or int(h.get("Active", 1)) != 1:
		return
	draw_horizon_disc(self, panel_to_screen(h.ClockCenterX, h.ClockCenterY), s)


## The horizon disc of FUN_005268b0 mode 4 (the MFD ADI page FUN_00526fe0 draws the same), on `ci` (from its
## _draw) at `c`, `px` screen px per original px. Roll and pitch in whole degrees (truncated, mod 360; a pitch past
## ±90° folds over with the roll turned 180°); with sin / cos of the roll times [HORIZON] Scale, a point (x, y)
## maps to (sin·y + cos·x, cos·y − sin·x) + pitch / 2 · (sin, cos), truncated to pixels: 0.5 px per degree of
## pitch at Scale 1. Clipped to the ±Radius square: GndColor fill, the SkyColor rectangle (−30, 0)..(30, −90) above
## the horizon, outlined, and the 12 white lines (0x65cec0: four ground perspective lines, pitch ticks every 8°).
func draw_horizon_disc(ci: CanvasItem, c: Vector2, px: float) -> void:
	var h: Dictionary = layout.get("HORIZON", {})
	var r := float(h.get("Radius", 40))
	var k := float(h.get("Scale", 1.0))
	var roll := int(state.roll) % 360
	var pitch := int(state.pitch) % 360
	if roll < 0:
		roll += 360
	if pitch < 0:
		pitch += 360
	if pitch > 90 and pitch < 270:
		pitch = 180 - pitch
		roll += 180
	elif pitch > 270:
		pitch -= 360
	var sn := sin(deg_to_rad(roll)) * k
	var cs := cos(deg_to_rad(roll)) * k
	var o := Vector2(int(pitch * sn * 0.5), int(pitch * cs * 0.5))
	var at := func(x: float, y: float) -> Vector2:
		return c + (Vector2(int(sn * y + cs * x), int(cs * y - sn * x)) + o) * px
	var box := Rect2(c - Vector2(r, r) * px, Vector2(2 * r, 2 * r) * px)
	var clip := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	ci.draw_rect(box, _colorref(int(h.get("GndColor", 0x9bb4))))
	var sky := PackedVector2Array([at.call(-30, 0), at.call(30, 0), at.call(30, -90), at.call(-30, -90)])
	for piece in Geometry2D.intersect_polygons(sky, clip):
		if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
			ci.draw_colored_polygon(piece, _colorref(int(h.get("SkyColor", 0xa06cfc))))
	var lines := [sky[0], sky[1], sky[1], sky[2], sky[2], sky[3], sky[3], sky[0]]
	for l in HORIZON_LINES:
		lines.append(at.call(l[0], l[1]))
		lines.append(at.call(l[2], l[3]))
	for i in range(0, lines.size(), 2):
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([lines[i], lines[i + 1]]), clip):
			if seg.size() >= 2:
				ci.draw_polyline(seg, Color.WHITE, maxf(1.0, px * 0.6))


## The disc's white lines (0x65cec0, x0 y0 x1 y1): ground perspective lines, then pitch ticks (4 px = 8°).
const HORIZON_LINES := [[0, 0, 20, 6], [0, 0, -20, 6], [0, 0, 15, 15], [0, 0, -15, 15],
		[-3, -4, 3, -4], [-8, -8, 8, -8], [-3, -12, 3, -12], [-8, -16, 8, -16],
		[-3, 4, 3, 4], [-8, 8, 8, 8], [-3, 12, 3, 12], [-8, 16, 8, 16]]


## The original MFD font (FUELDIGITAL, the MFD ADI page's numbers), loaded once.
func digits_font() -> Font:
	if mfd_font == null:
		mfd_font = preload("res://cockpit/hud.gd").load_original_font("mfd")
	return mfd_font if mfd_font != null else get_theme_default_font()


func _colorref(c: int) -> Color:
	# Win32 COLORREF is 0x00BBGGRR.
	return Color8(c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff)


## Vertical tape (vario / AOA) behind a panel window: the PanelHeight rows from Height / 2 − PanelHeight / 2 +
## `shift`, clamped to the tape.
func _draw_tape(key: String, shift: int, s: float) -> void:
	var t: Dictionary = layout.get(key, {})
	if t.get("Active", 0) != 1 or not tex.has(key):
		return
	var tx: Texture2D = tex[key]
	var k := tx.get_height() / float(t.Height)
	var window: int = int(t.PanelHeight)
	var src_y: int = clampi(int(t.Height / 2.0) - int(window / 2.0) + shift, 0, int(t.Height) - window)
	draw_texture_rect_region(tx, Rect2(panel_to_screen(t.OffsetX, t.OffsetY), Vector2(t.Width, window) * s),
			Rect2(0, src_y * k, t.Width * k, window * k))


## [THROTTLE, RPM, TEMP] for engine `e` (0 left, 1 right), @45ac00: THROTTLE = rpm, RPM = clamp(rpm, 0.6, 0.97),
## TEMP = clamp(rpm, 0.5, 0.8). Damage flags (docs/damage.md §5; left / right): engine cut out 2 / 3 -> RPM 0,
## fire 16 / 17 -> TEMP 0.9, permanent damage 22 / 23 -> THROTTLE and RPM 0.
func _engine_needles(e: int) -> Array:
	var rpm: float = state.rpm
	var n := [rpm, clampf(rpm, 0.6, 0.97), clampf(rpm, 0.5, 0.8)]
	var f := func(i: int) -> bool: return damage_flags.size() > i + e and damage_flags[i + e]
	if f.call(16):
		n[2] = 0.9
	if f.call(2):
		n[1] = 0.0
	if f.call(22):
		n[0] = 0.0
		n[1] = 0.0
	return n


## `full` > 0 replaces the gauge's FullClock; `shorter` px off its Radius.
func _draw_needle(key: String, value: float, s: float, full := 0.0, shorter := 0.0) -> void:
	var g: Dictionary = layout.get(key, {})
	if g.get("Active", 0) != 1:
		return
	var c := panel_to_screen(g.OffsetX, g.OffsetY)
	# FUN_00527e50: angle = max(value · 2π / FullClock, 0) + AngleOffset — no needle turns below its zero (the vario
	# rests at 0 in a descent).
	var angle: float = g.AngleOffset + maxf(value / (full if full > 0.0 else float(g.FullClock)) * TAU, 0.0)
	var tip: Vector2 = c + Vector2(cos(angle), sin(angle)) * (float(g.Radius) - shorter) * s * 0.9
	var col := _colorref(int(g.NeedleColor))
	draw_line(c, tip, col, max(1.0, g.NeedleWidth * s * 0.6), true)
