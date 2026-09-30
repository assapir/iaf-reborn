# One cockpit MFD (docs/mfd.md): a 132x132 display placed on the panel at [MFD] <Side>OffsetX/Y,
# with its pages drawn from the mfds.bmp atlas, the 5x5 sprite font and GDI-style vectors, and the
# bezel buttons (OSBs) around it as click zones. Generic for every cockpit; the cockpit node
# (cockpit.gd) supplies layout, textures and the flight state.
extends Control

const SIZE := 132.0
## Bezel strips reach 16 px outside the display.
const BEZEL := 16.0
const GREEN := Color8(0, 255, 0)
const DIM_GREEN := Color8(0, 128, 0)

## Pages (state+0x504): 0 NAV, 1 stores, 2 radar, 3 TSD, 4 damage, 5 TV, 6 FLIR, 7 RWR, 8 MENU,
## 9 ADI, 10 HARM.
enum { NAV, STORES, RADAR, TSD, DAMAGE, TV, FLIR, RWR, MENU, ADI, HARM }

## mfds.bmp tiles (table 0x65d068), by page / radar mode.
const TILE_BLANK := Vector2(0, 0)
const TILE_RWR := Vector2(132, 0)
const TILE_STORES := Vector2(0, 132)
const TILE_RADAR_AA := Vector2(0, 264)
const TILE_TSD := Vector2(0, 396)
const TILE_MAP := Vector2(132, 528)
const TILE_FLIR := Vector2(0, 660)
const TILE_GMT := Vector2(132, 660)
const TILE_TV := Vector2(0, 792)

## Radar sub-modes (state+0xa04) and their labels.
const RADAR_MODES := ["OFF", "STBY", "STT", "BORE", "LRS", "TWS", "ACM", "GMT", "MAP"]
const RADAR_RANGES := [5, 10, 20, 40, 80, 160]
const TSD_SCALES := [10, 20, 40, 80]

var cockpit: Control
var index := 0  # 0 left, 1 right, 2 middle
var page := RADAR
## Radar: mode and range index (initial values UNCERTAIN: not traced in the exe).
var radar_mode := 4
var radar_range := 2
var radar_last_aa := 4
var radar_last_ag := 7
## TSD: scale (+0x279c, default 40) and the SAM / WPT / MAP / SCL options (default on).
var tsd_scale := 40
var tsd_options := [true, true, true, true]
var nav_scroll := 0
var hover_osb := -1


func setup(c: Control, idx: int, start_page: int) -> void:
	cockpit = c
	index = idx
	page = start_page
	mouse_filter = Control.MOUSE_FILTER_STOP


func _panel_offset() -> Vector2:
	var m: Dictionary = cockpit.layout.MFD
	var side: String = ["Left", "Right", "Middle"][index]
	return Vector2(float(m[side + "OffsetX"]), float(m[side + "OffsetY"]))


func _process(_delta: float) -> void:
	var s: float = cockpit.ui_scale()
	var o := _panel_offset()
	position = cockpit.panel_to_screen(o.x - BEZEL, o.y - BEZEL)
	size = Vector2.ONE * (SIZE + 2 * BEZEL) * s
	queue_redraw()


# --- drawing primitives (MFD pixels) ----------------------------------------------------------

func _atlas() -> Texture2D:
	return cockpit.tex.get("MFDS")


func _blit(src: Rect2, dest: Vector2) -> void:
	var t := _atlas()
	if t == null:
		return
	var a: float = cockpit.layout.get("image_scale", 1)
	draw_texture_rect_region(t, Rect2(dest, src.size), Rect2(src.position * a, src.size * a))


func _tile(at: Vector2) -> void:
	_blit(Rect2(at, Vector2(SIZE, SIZE)), Vector2.ZERO)


## 5x5 sprite font (FUN_00525890): letters from (132,850), digits and symbols from (132,840).
static func _glyph_x(c: String) -> int:
	var u := c.unicode_at(0)
	if u >= 65 and u <= 90:
		return 5 * (u - 65)
	if u >= 97 and u <= 122:
		return 5 * (u - 97)
	if u >= 48 and u <= 57:
		return 130 + 5 * (u - 48)
	match c:
		".": return 185
		":": return 190
		"+": return 195
		"-": return 200
		"%": return 205
	return 180


func _text(pos: Vector2, text: String) -> void:
	for i in text.length():
		var x := _glyph_x(text[i])
		var src := Rect2(132 + x, 850, 5, 5) if x < 130 else Rect2(132 + x - 130, 840, 5, 5)
		_blit(src, pos + Vector2(5 * i, 0))


func _text_right(end_x: float, y: float, text: String) -> void:
	_text(Vector2(end_x - 5 * text.length(), y), text)


func _line(a: Vector2, b: Vector2, color := GREEN) -> void:
	draw_line(a, b, color, 1.0)


# --- pages ------------------------------------------------------------------------------------

func _draw() -> void:
	if cockpit == null or cockpit.layout.is_empty():
		return
	var s: float = cockpit.ui_scale()
	draw_set_transform(Vector2(BEZEL, BEZEL) * s, 0.0, Vector2(s, s))
	match page:
		RADAR:
			_draw_radar()
		TSD:
			_draw_tsd()
		RWR:
			_tile(TILE_RWR)
		MENU:
			_draw_menu()
		NAV:
			_draw_nav()
		STORES:
			_draw_stores()
		DAMAGE:
			_draw_damage()
		ADI:
			_draw_adi()
		HARM:
			_tile(TILE_BLANK)
			_text(Vector2(17, 3), "harm")
			_text_right(114, 3, "no source")
		FLIR:
			_tile(TILE_FLIR)
		TV:
			_tile(TILE_BLANK)
	draw_set_transform(Vector2.ZERO)


func _draw_radar() -> void:
	match radar_mode:
		7: _tile(TILE_GMT)
		8: _tile(TILE_MAP)
		_:
			_tile(TILE_RADAR_AA)
			_text(Vector2(17, 3), RADAR_MODES[radar_mode])
	if radar_mode >= 3:
		_blit(Rect2(132 + 8 * radar_range, 845, 8, 5), Vector2(1, 33))
	if radar_mode <= 6 and radar_mode >= 2:
		_draw_horizon_bars()


## Artificial horizon bars (FUN_00533620): centre (66,66), rolled, 1 px per degree of pitch.
func _draw_horizon_bars() -> void:
	var st: Dictionary = cockpit.state
	var pitch := clampf(st.pitch, -40.0, 40.0)
	if absf(st.pitch) > 40.0 and int(Time.get_ticks_msec() / 300) % 2 == 1:
		return
	var rot := deg_to_rad(-st.roll)
	var centre := Vector2(66, 66 + pitch)
	for side in [-1.0, 1.0]:
		var pts := [Vector2(31 * side, 4), Vector2(31 * side, 0), Vector2(5 * side, 0)]
		for i in 2:
			_line(centre + pts[i].rotated(rot), centre + pts[i + 1].rotated(rot))


func _draw_menu() -> void:
	_tile(TILE_BLANK)
	var h: Dictionary = cockpit.layout.get("HORIZON", {})
	var rwr_panel := int(cockpit.layout.get("PANELRWR", {}).get("Active", 0)) == 1
	var left := {0xb: "", 0xd: "stores", 0xe: "" if rwr_panel else "rwr", 0xf: "radar"}
	var right := {0x11: "NAV", 0x12: "damage", 0x13: "tactical", 0x14: "adi" if int(h.get("OnMfd", 0)) == 1 else ""}
	for id in left:
		_text(Vector2(5, 22 + 20 * (id - 0xb)), left[id])
	for id in right:
		_text_right(124, 42 + 20 * (id - 0x11), right[id])


func _draw_nav() -> void:
	_tile(TILE_BLANK)
	var wps: Array = cockpit.waypoints
	var cur: int = cockpit.current_waypoint
	for row in 3:
		var i := nav_scroll + row
		if i >= wps.size():
			break
		var y := 42 + 20 * row
		_text_right(8, y, "%d" % (i + 1))
		_text(Vector2(12, y + 1), String(wps[i].name).substr(0, 12))
		if i == cur:
			draw_rect(Rect2(1, y - 2, 8, 9), GREEN, false, 1.0)
	_text(Vector2(72, 124), "ETA   :")


func _draw_stores() -> void:
	_tile(TILE_STORES)
	_text(Vector2(55, 124), "Fuel : %5dLB" % int(cockpit.state.fuel_lbs))


## Damage page rows (FUN_0052bc00): format, x, y, the damage flags that make it NOGO (cockpit state
## +0x558 + 4n = the controller's damage flags, docs/damage.md §5). "ENG %s %s" / "AB %s %s" take
## "L" on twin-engine jets (else ""); the ENG R / AB R rows appear on twin-engine jets only.
const DAMAGE_ROWS := [
	["ENG %s %s", 12, 10, [22, 16, 2]], ["AB %s %s", 72, 10, [8]], ["INS  %s", 72, 34, [11]],
	["FUEL %s", 12, 43, [10]], ["RDR  %s", 72, 43, [15]], ["AILN %s", 12, 52, [18]],
	["RWR  %s", 72, 52, [14]], ["FLTC %s", 12, 61, [24]], ["WPNS %s", 72, 61, [20]],
	["FLAP %s", 12, 70, [4]], ["GUN  %s", 72, 70, [13]], ["GEAR %s", 12, 79, [7]],
	["ECM  %s", 72, 79, [1]], ["HUD  %s", 12, 88, [12]], ["A/P  %s", 72, 88, [6]],
	["BRAK %s", 12, 97, [5]], ["ELCT %s", 72, 97, [19]], ["GNRT %s", 72, 106, [21]],
]
const DAMAGE_ROWS_TWIN := [["ENG R %s", 12, 19, [23, 17, 3]], ["AB R %s", 72, 19, [9]]]


func _draw_damage() -> void:
	_tile(TILE_BLANK)
	var flags: Array = cockpit.damage_flags
	var twin: bool = cockpit.twin_engines
	for row in DAMAGE_ROWS + (DAMAGE_ROWS_TWIN if twin else []):
		var nogo := false
		for f in row[3]:
			nogo = nogo or (f < flags.size() and flags[f])
		var state := "NOGO" if nogo else "GO"
		var fmt: String = row[0]
		_text(Vector2(row[1], row[2]), fmt % [("L" if twin else ""), state] if fmt.count("%s") == 2 else fmt % state)


## ADI page (9) for cockpits with [HORIZON] OnMfd: ball at (65,74), radius [HORIZON] Radius.
func _draw_adi() -> void:
	_tile(TILE_BLANK)
	var h: Dictionary = cockpit.layout.get("HORIZON", {})
	var r := float(h.get("Radius", 40))
	var st: Dictionary = cockpit.state
	var sky: Color = cockpit._colorref(int(h.get("SkyColor", 0x804000)))
	var gnd: Color = cockpit._colorref(int(h.get("GndColor", 0x004080)))
	var offset := clampf(st.pitch / 90.0, -1.0, 1.0) * r
	var c := Vector2(65, 74)
	var rot := deg_to_rad(-st.roll)
	var y := -r
	while y < r:
		var half := sqrt(maxf(r * r - y * y, 0.0))
		var a := c + Vector2(-half, y).rotated(rot)
		var b := c + Vector2(half, y).rotated(rot)
		draw_line(a, b, sky if y < offset else gnd, 1.0)
		y += 1.0


## TSD page (FUN_00531a50): heading-up, ownship at (65,85), 1 px = 112·scale m.
func _draw_tsd() -> void:
	_tile(TILE_TSD)
	var st: Dictionary = cockpit.state
	var own: Vector2 = st.get("world", Vector2.ZERO)
	var hdg := deg_to_rad(st.heading)
	var S := sin(hdg)
	var C := cos(hdg)
	var k := 112.0 * tsd_scale
	var to_mfd := func(w: Vector2) -> Vector2:
		var ex := w.x - own.x
		var ny := w.y - own.y
		return Vector2(65 + (ex * C - ny * S) / k, 85 - (ex * S + ny * C) / k)
	var clip := PackedVector2Array([Vector2(10, 10), Vector2(122, 10), Vector2(122, 122), Vector2(10, 122)])
	if tsd_options[2]:
		for poly in cockpit.tsd_map:
			var pts := PackedVector2Array()
			for w in poly.points:
				pts.append(to_mfd.call(w))
			for piece in Geometry2D.intersect_polygons(pts, clip):
				# Skip slivers the clipper leaves (they don't triangulate).
				if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
					draw_colored_polygon(piece, poly.color)
	# Fixed symbology: range circle r=22, ownship, outer ring r=44 with SCL.
	draw_arc(Vector2(65, 85), 22, 0, TAU, 48, GREEN, 1.0)
	if tsd_options[3]:
		draw_arc(Vector2(65, 85), 44, 0, TAU, 64, GREEN, 1.0)
	_line(Vector2(60, 81), Vector2(71, 81))
	_line(Vector2(65, 78), Vector2(65, 91))
	_line(Vector2(63, 91), Vector2(68, 91))
	# Compass letters S, E, N, W on radius 18, rotating with the heading.
	for i in 4:
		var bearing := deg_to_rad([180.0, 90.0, 0.0, 270.0][i]) - hdg
		var p := Vector2(65, 85) + Vector2(sin(bearing), -cos(bearing)) * 18
		_blit(Rect2(132 + 6 * i, 855, 6, 7), p - Vector2(3, 3))
	# Waypoints: route polyline, current one filled.
	if tsd_options[1]:
		var wps: Array = cockpit.waypoints
		var prev = null
		for i in wps.size():
			var p: Vector2 = to_mfd.call(wps[i].world)
			if prev != null:
				for seg in Geometry2D.clip_polyline_with_polygon(PackedVector2Array([prev, p]), clip):
					draw_polyline(seg, GREEN, 1.0)
			prev = p
			if Rect2(10, 10, 112, 112).has_point(p):
				var box := Rect2(p - Vector2(2, 2), Vector2(5, 5))
				if i == cockpit.current_waypoint:
					draw_rect(box, Color8(0, 255, 0))
				else:
					draw_rect(box, Color8(0, 128, 0), false, 1.0)
	# Option highlight boxes (right OSBs 0x10..0x13).
	for i in 4:
		if tsd_options[i]:
			draw_rect(Rect2(111, 20 + 20 * i, 17, 9), GREEN, false, 1.0)
	_blit(Rect2(132 + 8 * TSD_SCALES.find(tsd_scale), 845, 8, 5), Vector2(1, 33))


# --- bezel buttons (FUN_00520db0 hit test, FUN_005219e0 actions) ---------------------------------

## OSB id under an MFD-local point: top 1-5, bottom 6-10, left 11-15, right 16-20; -1 = none.
static func osb_at(p: Vector2) -> int:
	var along := -1.0
	var base := 0
	if p.y >= -16 and p.y < 0 and p.x >= 22 and p.x < 108:
		along = p.x
		base = 0
	elif p.y >= 131 and p.y < 147 and p.x >= 22 and p.x < 108:
		along = p.x
		base = 5
	elif p.x >= -16 and p.x < 0 and p.y >= 21 and p.y < 108:
		along = p.y
		base = 10
	elif p.x >= 132 and p.x < 149 and p.y >= 21 and p.y < 108:
		along = p.y
		base = 15
	if along < 0 or int(along) % 20 >= 8:
		return -1
	var n := int(along) / 20
	return base + n if n >= 1 and n <= 5 else -1


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position / cockpit.ui_scale() - Vector2(BEZEL, BEZEL)
	var osb := osb_at(p)
	if osb > 0:
		press(osb)
		accept_event()


## OSB actions.
func press(osb: int) -> void:
	if osb == 6:
		page = MENU
		return
	match page:
		MENU:
			var h: Dictionary = cockpit.layout.get("HORIZON", {})
			var rwr_panel := int(cockpit.layout.get("PANELRWR", {}).get("Active", 0)) == 1
			match osb:
				0xd: page = STORES
				0xe: if not rwr_panel: page = RWR
				0xf: page = RADAR
				0x11: page = NAV
				0x12: page = DAMAGE
				0x13: page = TSD
				0x14: if int(h.get("OnMfd", 0)) == 1: page = ADI
		RADAR:
			match osb:
				0xb: step_range(1)
				0xc: step_range(-1)
				1: cycle_radar_mode()
		TSD:
			match osb:
				0xb: tsd_scale = TSD_SCALES[mini(TSD_SCALES.find(tsd_scale) + 1, TSD_SCALES.size() - 1)]
				0xc: tsd_scale = TSD_SCALES[maxi(TSD_SCALES.find(tsd_scale) - 1, 0)]
				0x10, 0x11, 0x12, 0x13: tsd_options[osb - 0x10] = not tsd_options[osb - 0x10]
		NAV:
			match osb:
				0xb: nav_scroll = maxi(nav_scroll - 1, 0)
				0xf: nav_scroll = mini(nav_scroll + 1, maxi(0, cockpit.waypoints.size() - 3))


## Radar range one step up (+1) or down (-1) within RADAR_RANGES (OSB 0xb / 0xc, key commands 33 / 34).
func step_range(d: int) -> void:
	radar_range = clampi(radar_range + d, 0, RADAR_RANGES.size() - 1)


## Radar modes key / OSB (event 0x24): A-A 4 -> 5 -> 6 -> 4, A-G 7 <-> 8.
func cycle_radar_mode() -> void:
	if radar_mode >= 7:
		radar_mode = 8 if radar_mode == 7 else 7
		radar_last_ag = radar_mode
	elif radar_mode >= 4:
		radar_mode = 4 + (radar_mode - 4 + 1) % 3
		radar_last_aa = radar_mode
	else:
		radar_mode = radar_last_aa


## Radar on / AA / AG (event 0x2b): toggles between the last A-A and A-G modes.
func toggle_radar_aa_ag() -> void:
	if radar_mode >= 7:
		radar_mode = radar_last_aa
	else:
		radar_mode = radar_last_ag
