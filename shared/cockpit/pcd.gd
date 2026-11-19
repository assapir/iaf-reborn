# Ours (the F-35I, docs/f35i.md §4.3, docs/real-mfd.md "F-35I"): the panoramic cockpit display (PCD) as the real one
# lays it out, from the cockpit's [PCD] section (panel px, tools/f35i/cockpit3d.py): the black glass; the Function
# Access Button strip along its top (engine, fuel, weapons, gear, ICAWS, autopilot, SWAP, radios, the navigation
# source, the recorder, MENU, IFF, the time and alerts; in Modern IAF a tap opens the item's pop-up format in the portal
# under it); under it the two halves, each either one large portal (its other formats as tabs along its foot) or two
# portals over four small windows (a window taps its format into the portal above). What each portal and window shows,
# widening a portal over its half, enlarging it over its windows, SWAP, the presets, the MENU grid and the portal with
# the cursor are IafPcd's (crates/iaf-avionics/src/pcd.rs); this draws them. Each portal a format (pcd_formats.gd) with
# its name and master mode and its option legends; the standby display (ESIS) under the glass. Layer 0 draws it all;
# layer 1, over it, only the glass's sheen. In the 3D cockpit (cockpit3d.gd) layer 0 draws the glass into its screen's
# SubViewport (screen_px), the sheen is the glass's own and a layer 2 draws the ESIS into its own. Each portal keeps an
# MFD node (mfd.gd, hidden) whose page follows the format, so the systems that read the pages (the EO camera, the M
# key, the full-screen MFD) work as before. The strip's SWAP trades its halves (the portals stay), its MENU opens the
# additional MENU page (CRUS) as a pop-up on the portal under it, a portal's CNTL> its format's control page
# (docs/real-mfd.md "F-35I").
extends Control

const Formats := preload("res://shared/cockpit/pcd_formats.gd")
const F := Formats
const F16Mfd := preload("res://shared/cockpit/f16_mfd.gd")
const SKY := Color(0.16, 0.46, 0.86)
const GROUND := Color(0.50, 0.30, 0.12)
const WHITE := Color(0.94, 0.96, 0.98)
const AMBER := Color(1.0, 0.74, 0.12)
## The strip's height, panel px: 0.53 in of the 8 in glass, as the user's simulator photo shows it (round 6 of the
## F-35I cockpit, 2026-11-17; 0.9 in until then).
const FAB_H := 15.0
const TAB_H := 11.0
const HEAD_H := 15.0
## A window's height, of the glass's: 2.1 in of the 8 in glass, as the simulator photo (LM's layout: 2.5 in; 0.30 until
## round 6).
const WIN_FRAC := 0.26
## A window's format drawn at this scale of a portal's.
const MINI := 0.5
## EoSensor's FLIR mode (shared/weapons/eo_sensor.gd).
const FLIR_MODE := 2
## The game page each format drives (the hidden MFD node's page; none: the page stays).
const PAGE_OF := {
	"TSD-1": 3,
	"TSD-2": 3,
	"TSD-3": 3,
	"SRCH": 2,
	"SMS": 1,
	"WPN-A": 1,
	"WPN-S": 1,
	"TFLIR": 6,
	"TWD": 7,
	"EFI": 9,
	"ICAWS": 4
}
## The format a game page shows when something else sets it (the M key, a weapon, the full-screen MFD).
const FORMAT_OF := {
	0: "TSD-1", 1: "SMS", 2: "SRCH", 3: "TSD-1", 4: "ICAWS", 5: "TFLIR", 6: "TFLIR", 7: "TWD", 9: "EFI", 10: "SMS"
}
## The 1998 game's F-35I (reborn) keeps its eleven formats in the MENU grid; Modern IAF lists IafPcd's 20.
const OLD_FORMATS := ["TSD-1", "TSD-2", "TSD-3", "SRCH", "SMS", "TFLIR", "TWD", "EFI", "ICAWS", "FUEL", "ENG"]
## Ours, the modern F-35I's events through the weapons (player_weapons.gd mfd_event): the SMS's DOORS, the WPN-S's PRE
## step; the F-16 MFD's GPS PRE / VIS and PROF (f16_mfd.gd), the TGP's CZ.
const DOORS_EVENT := -6
const PRE_STEP_EVENT := -7

var cockpit: Control
var layer := 0
var font: Font
var fmt: Formats
## The layout (IafPcd) and its state this frame (IafPcd.state).
var lay: RefCounted
var st := {}
## Per portal: the main format; its two windows' formats; the MENU grid open (read from IafPcd).
var main: Array:
	get:
		return Array(st.get("main", []))
var tabs: Array:
	get:
		return st.get("tabs", []).map(func(t): return Array(t))
var menu_open: Array:
	get:
		return st.get("menu", [])
## The controls of a format's CNTL page (its portal's CNTL>); a format without one shows no CNTL>.
const CNTL_OF := {
	"TSD-1": ["MAP", "RNG UP", "RNG DN"],
	"TSD-2": ["MAP", "RNG UP", "RNG DN"],
	"TSD-3": ["MAP", "RNG UP", "RNG DN"],
	"SRCH": ["MODE", "RNG UP", "RNG DN"],
	"TFLIR": ["ZOOM IN", "ZOOM OUT", "WIDE", "LSR"],
}
## The left group of the strip's legends spans this many panel px from the glass's left edge (_draw_fab).
const FAB_LEFT_W := 262.0
## Per portal: its CNTL page open.
var cntl_open := [false, false, false, false]
var _page_seen := [-1, -1, -1, -1]
## Clickable areas of the last frame: [Rect2 (screen px), Callable]; the open MENU grids' buttons (portal -> {format:
## Rect2, screen px}).
var _hits: Array = []
var menu_buttons := {}
## Ours, the 3D cockpit (cockpit3d.gd): drawn into a SubViewport at this many px per panel px, the panel px
## screen_origin at its corner (0: on the 2D panel).
var screen_px := 0.0
var screen_origin := Vector2.ZERO
## Modern IAF's display: the pilot's layout changes, the pop-ups, the cursor and the formats of its own.
var modern := false
## The FCS's BIT and the DIM's LOAD started (time of day, s; -1 none).
var bit_t := -1.0
var load_t := -1.0
## IafPcd's MENU formats.
var _formats: Array = []
## The start-up checklist's flight add-on (sim_flight.gd), found once.
var _sim_flight: Node


func setup(c: Control, l: int) -> void:
	cockpit = c
	layer = l
	mouse_filter = Control.MOUSE_FILTER_PASS if l == 0 else Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = Settings.display_font("narrow")
	fmt = Formats.new(self, c, font)
	modern = Settings.modern_mfds()
	lay = ClassDB.instantiate("IafPcd")
	_formats = Array(ClassDB.class_call_static("IafPcd", "formats"))
	_refresh()


func _process(_delta: float) -> void:
	modulate = Color(0.8, 0.8, 0.8) if cockpit != null and cockpit.night else Color.WHITE  # dimmed at night
	if layer == 0 and cockpit != null:
		_follow_pages()
	queue_redraw()


## Screen px per panel px.
func _s() -> float:
	return screen_px if screen_px > 0.0 else cockpit.ui_scale()


## A rect of the [PCD] section (panel px [x, y, w, h]) on screen.
func _rect(r: Array) -> Rect2:
	var a: Vector2 = (
		(Vector2(float(r[0]), float(r[1])) - screen_origin) * screen_px
		if screen_px > 0.0
		else cockpit.panel_to_screen(float(r[0]), float(r[1]))
	)
	return Rect2(a, Vector2(float(r[2]), float(r[3])) * _s())


func glass() -> Rect2:
	return _rect(cockpit.layout.PCD.Rect)


## The glass under the strip, on screen (IafPcd's unit square).
func _area() -> Rect2:
	var g := glass()
	var top := FAB_H * _s()
	return Rect2(g.position + Vector2(0, top), g.size - Vector2(0, top))


## The windows' row, of the glass under the strip.
func _win() -> float:
	var h := float(cockpit.layout.PCD.Rect[3]) if cockpit != null and cockpit.layout.has("PCD") else 227.0
	return WIN_FRAC * h / (h - FAB_H)


func _refresh() -> void:
	st = lay.state(_win())


func _on_area(r: Rect2) -> Rect2:
	var a := _area()
	return Rect2(a.position + r.position * a.size, r.size * a.size)


## The four portals' screen rects, left to right under the strip; a hidden one (a widened half's second) empty.
func portals() -> Array:
	return st.portals.map(func(r: Rect2): return Rect2() if r.size == Vector2.ZERO else _on_area(r))


## The windows along the glass's foot: [screen rect, portal, its window].
func windows() -> Array:
	return st.windows.map(func(w): return [_on_area(w[0]), int(w[1]), int(w[2])])


## Whether portal `i` shows (a widened half hides its second).
func shown(i: int) -> bool:
	return Rect2(st.portals[i]).size != Vector2.ZERO


# --- portals and their pages ----------------------------------------------------------------------------------------


## Keeps each portal's format and its MFD node's page together: a page set elsewhere (the M key, a weapon) picks the
## matching format; a format the pilot picks sets the page.
func _follow_pages() -> void:
	for i in mini(4, cockpit.mfds.size()):
		var m = cockpit.mfds[i]
		m.visible = false
		if m.page != _page_seen[i]:
			var was: int = _page_seen[i]
			_page_seen[i] = m.page
			var cur: String = main[i]
			var want: String = FORMAT_OF.get(int(m.page), cur)
			if was < 0 and PAGE_OF.has(cur):  # the first frame: the nodes take the default layout's pages
				_set_page(i)
			elif PAGE_OF.get(cur, -1) != int(m.page) and want != cur:
				if shown(i):
					_show(i, want)
				else:
					# A page set on a hidden portal shows on its half's large one (on the other half's first when that
					# one shows the radar); the hidden node keeps its page.
					var to := i - 1 if main[i - 1] != "SRCH" else (i + 1) % 4
					m.page = was
					_page_seen[i] = was
					_show(to, want)


## Portal `i` shows format `f` (IafPcd.show: where `f` is, it takes `i`'s format in exchange); "MENU" opens the grid.
func _show(i: int, f: String) -> void:
	if f == "MENU":
		if not menu_open[i]:
			_do(func(): lay.toggle_menu(i))
		return
	_do(func(): lay.show(i, f), i)


## A layout change, then the MFD nodes' pages for the formats it moved (a moved format's CNTL page closes); `pick`
## the portal whose format the pilot chose (_set_page).
func _do(change: Callable, pick := -1) -> void:
	var was := main
	change.call()
	_refresh()
	for k in 4:
		if main[k] != was[k] or k == pick:
			if main[k] != was[k]:
				cntl_open[k] = false
			_set_page(k, k == pick)


## The MFD node's page follows portal `i`'s format. With `pick` (the pilot chose the format: a tab, a window, the
## MENU grid) TFLIR starts the camera the way the FLIR page key does (player_weapons.gd flir_on): the page alone
## leaves the picture at NO VIDEO. The layout's own TFLIR waits for the pilot (flir_key, a tap on its picture), so
## the cursor keys stay on the radar until then.
func _set_page(i: int, pick := false) -> void:
	if i >= cockpit.mfds.size() or not PAGE_OF.has(main[i]):
		return
	var m = cockpit.mfds[i]
	if pick and main[i] == "TFLIR":
		_start_flir(m)
	m.page = PAGE_OF[main[i]]
	_page_seen[i] = PAGE_OF[main[i]]


## The camera on MFD node `m`, unless it already runs (cockpit.on_flir: player_weapons.gd flir_on).
func _start_flir(m) -> bool:
	if int(cockpit.eo.get("mode", 0)) == FLIR_MODE or not cockpit.on_flir.is_valid():
		return false
	return cockpit.on_flir.call(m)


## The FLIR page key (terrain_view.gd command 90) while a shown portal already holds TFLIR: its camera starts there
## (flir_on would bring a second TFLIR). True when it started.
func flir_key() -> bool:
	for i in 4:
		if shown(i) and main[i] == "TFLIR" and i < cockpit.mfds.size():
			return _start_flir(cockpit.mfds[i])
	return false


## The strip's MENU page's CRUS: the layout the display starts with, the strip unswapped, every page open closed
## (IafPcd restore); every node's page set again.
func restore_layout() -> void:
	cntl_open = [false, false, false, false]
	_do(func(): lay.restore())
	for k in 4:
		_set_page(k)


## A portal's header tapped: a pop-up there closes (the portal shows its format again), else the MENU grid opens or
## closes.
func _header(i: int) -> void:
	cntl_open[i] = false
	if int(st.popup) == i:
		_do(func(): lay.popup(Rect2(st.portals[i]).get_center().x, main[i]))
	else:
		_do(func(): lay.toggle_menu(i))


## A portal's CNTL> tapped: its format's control page opens or closes.
func _cntl(i: int) -> void:
	cntl_open[i] = not cntl_open[i]
	if menu_open[i]:
		_do(func(): lay.toggle_menu(i))


## Ours, Modern IAF's display keys (command 300; modern-iaf/data/keys.json): 0 MENU on the cursor's portal, 1 / 2 the
## MENU cursor on / back, 3 select, 4 the next window into the portal, 5 widen, 6 enlarge, 7 the strip's SWAP, 8 the
## next preset.
func key(p1: int) -> void:
	var i := int(st.focus)
	match p1:
		0:
			_do(func(): lay.toggle_menu(i))
		1, 2:
			if not menu_open[i]:
				lay.toggle_menu(i)
			_do(func(): lay.menu_step(1 if p1 == 1 else -1))
		3:
			var picked: bool = menu_open[i]  # End with no MENU open picks nothing (a TFLIR portal's camera stays off)
			_do(func(): lay.select(), i if picked else -1)
		4:
			_do(func(): lay.cycle(i), i)
		5:
			_do(func(): lay.widen(i))
		6:
			_do(func(): lay.enlarge(i))
		7:
			_do(func(): lay.swap_bar())
		8:
			_do(func(): lay.apply(int(st.preset) + 1))


## DMS (command 240's p1: 0 up the helmet, 1 down the display, 2 / 3 the cursor's portal left / right).
func dms(dir: int) -> void:
	_do(func(): lay.dms(dir))


## The sensor of interest for the TMS keys (cockpit.gd soi_format): "FCR" the radar's SRCH / ASR, "TGP" the TFLIR,
## "" the helmet or a format with no sensor.
func soi_format() -> String:
	if not modern:
		return ""
	return {"SRCH": "FCR", "TFLIR": "TGP"}.get(String(lay.soi()), "")


func _gui_input(event: InputEvent) -> void:
	if layer != 0 or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if click(event.position):
		accept_event()


## A tap at `p` (px in this node): true when it hit a clickable area.
func click(p: Vector2) -> bool:
	for h in _hits:
		if h[0].has_point(p):
			h[1].call()
			return true
	return false


## A clickable area in the current portal transform (`r` in panel px from `origin`).
func _hit(origin: Vector2, r: Rect2, f: Callable) -> void:
	var s: float = _s()
	_hits.append([Rect2(origin + r.position * s, r.size * s), f])


# --- drawing ------------------------------------------------------------------------------------------------------


func _draw() -> void:
	if cockpit == null or not cockpit.layout.has("PCD"):
		return
	if layer == 1:
		if screen_px == 0.0:
			_draw_sheen()
		return
	if layer == 2:
		_draw_esis(_rect(cockpit.layout.PCD.Esis))
		return
	_hits.clear()
	menu_buttons.clear()
	var g := glass()
	draw_rect(g, Color.BLACK)
	_draw_fab(g)
	var ps := portals()
	for w in windows():
		_draw_window(w[0], w[1], w[2])
	for i in 4:
		if shown(i):
			_draw_portal(i, ps[i])
	# The two halves (each with its own power and processor): a dark seam down the middle.
	var s: float = _s()
	draw_line(
		Vector2(g.get_center().x, g.position.y),
		Vector2(g.get_center().x, g.end.y),
		Color(0.12, 0.13, 0.15),
		maxf(1.0, s * 0.9)
	)
	draw_rect(g, Color(0.10, 0.11, 0.13), false, maxf(1.0, s))
	if screen_px == 0.0:
		_draw_esis(_rect(cockpit.layout.PCD.Esis))


## The master mode under a portal's format name: NAV, A-A or A-S (a simulator manual), from the HUD mode.
func master_mode() -> String:
	var hm := int(cockpit.weapons.get("hud_mode", 0))
	return "A-A" if hm in [1, 2, 3] else ("A-S" if hm >= 4 else "NAV")


func _draw_portal(i: int, pr: Rect2) -> void:
	var s: float = _s()
	var pw := pr.size.x / s
	var ph := pr.size.y / s
	var tab_names: Array = Array(st.tab_rows[i])
	fmt.begin(pr.position, s)
	# Frame lines between portals (grey, thin).
	if pr.position.x > glass().position.x + 1.0:
		fmt.line(Vector2(0, 0), Vector2(0, ph), F.DARK_GREY, F.THIN)
	if tab_names.is_empty():
		fmt.line(Vector2(0, ph), Vector2(pw, ph), F.DARK_GREY, F.THIN)
	var tab_row := TAB_H if not tab_names.is_empty() else 0.0
	var name: String = main[i]
	var label := name
	if name == "SRCH" and int(cockpit.radar.get("mode", 0)) >= 7:
		label = "ASR"
	# The header: the format name over the master mode (tap: the MENU grid, or a pop-up closed); CNTL> on the right
	# (tap: the format's control page); a pop-up's magenta POP UP.
	var pop := int(st.popup) == i
	fmt.text(Vector2(3.0, 6.5), label.replace("-", ""), 5.6, F.GREEN)
	fmt.text(Vector2(3.0, 12.5), master_mode(), 4.6, F.GREEN)
	if pop:
		fmt.text(Vector2(30.0, 12.5), "POP UP", 4.4, F.MAGENTA)
	if CNTL_OF.has(name) and not pop:
		fmt.legend(Vector2(pw - 3.0, 6.5), "CNTL>", true, cntl_open[i])
		_hit(pr.position, Rect2(pw - 20.0, 0, 18.0, 10.0), func(): _cntl(i))
	var body := Rect2(2.0, HEAD_H + 1.0, pw - 4.0, ph - HEAD_H - tab_row - 4.0)
	if modern:
		_portal_controls(i, pr, pw, ph)
	_hit(pr.position, Rect2(0, 0, 30, HEAD_H), func(): _header(i))
	if name == "MENU":
		var crus: Dictionary = fmt.menu(body, "", ["CRUS"])
		_hit(pr.position, crus.CRUS, restore_layout)
	elif menu_open[i]:
		var list: Array = _formats if modern else OLD_FORMATS
		var cur: String = String(_formats[int(st.menu_cur)]) if modern and int(st.focus) == i else ""
		var buttons: Dictionary = fmt.menu(body, name, list, cur)
		menu_buttons[i] = {}
		for f in buttons:
			_hit(pr.position, buttons[f], func(): _show(i, f))
			menu_buttons[i][f] = Rect2(pr.position + buttons[f].position * s, buttons[f].size * s)
	elif cntl_open[i] and CNTL_OF.has(name):
		_draw_cntl(i, name, body, pr.position)
	else:
		_draw_format(i, name, body, pr.position, pw)
	if not tab_names.is_empty():
		_draw_tabs(i, tab_names, pr, pw, ph)
	fmt.end()
	# A tap elsewhere on the portal puts the cursor on it (after its own controls: the first hit wins).
	if modern:
		_hit(pr.position, Rect2(0, 0, pw, ph), func(): _do(func(): lay.set_focus(i)))


## Ours, Modern IAF: the portal's own controls along its header (a simulator manual p. 35: the arrows): ◄► widen over
## the half (or back), ▼ enlarge over the windows (▲ back); POP UP in magenta on a function bar pop-up; the portal with
## the cursor framed cyan (inferred: how the real display marks it is open).
func _portal_controls(i: int, pr: Rect2, pw: float, ph: float) -> void:
	var y := 6.5
	var wx := pw - 44.0
	var wide: bool = st.wide[i / 2]
	for d: float in [-1.0, 1.0]:
		var x := wx + 4.0 + d * (2.0 if wide else 4.5)
		var tip := x + d * (-2.5 if wide else 2.5)
		fmt.poly(PackedVector2Array([Vector2(tip, y - 2.5), Vector2(x, y - 5.0), Vector2(x, y)]), F.CYAN, F.THIN, true)
	_hit(pr.position, Rect2(wx - 3.0, 0, 14.0, 10.0), func(): _do(func(): lay.widen(i)))
	var ex := pw - 28.0
	var big := not Array(st.tab_rows[i]).is_empty()
	var tip_y := y - 5.0 if big else y
	var base_y := y if big else y - 5.0
	fmt.poly(
		PackedVector2Array([Vector2(ex - 2.5, base_y), Vector2(ex + 2.5, base_y), Vector2(ex, tip_y)]),
		F.CYAN,
		F.THIN,
		true
	)
	_hit(pr.position, Rect2(ex - 5.0, 0, 10.0, 10.0), func(): _do(func(): lay.enlarge(i)))
	if int(st.popup) == i:
		fmt.text(Vector2(30.0, 12.5), "POP UP", 4.4, F.MAGENTA)
	if int(st.focus) == i and not bool(st.hud_soi):
		fmt.box(Rect2(0.6, 0.6, pw - 1.2, ph - 1.2), F.CYAN, F.LINE)


## An enlarged portal's tabs along its foot (cyan, swap in on a tap): its windows' formats; a widened half's also the
## hidden portal's format and windows; the corner arrows.
func _draw_tabs(i: int, names: Array, pr: Rect2, pw: float, ph: float) -> void:
	var tw := (pw - 20.0) / names.size()
	for t in names.size():
		var f: String = names[t]
		var tr := Rect2(10.0 + tw * t + 1.0, ph - TAB_H - 1.0, tw - 2.0, TAB_H - 1.5)
		fmt.box(tr, F.CYAN, F.THIN)
		fmt.text(
			Vector2(tr.position.x, tr.end.y - 2.6),
			f.replace("-", ""),
			5.0 if tw > 22.0 else 4.2,
			F.CYAN,
			HORIZONTAL_ALIGNMENT_CENTER,
			tr.size.x
		)
		_hit(pr.position, tr, func(): _show(i, f))
	for side: float in [0.0, 1.0]:
		var x := 2.5 + side * (pw - 5.0)
		var d := 1.0 if side == 0.0 else -1.0
		fmt.poly(
			PackedVector2Array([Vector2(x, ph - 6.0), Vector2(x + 3.0 * d, ph - 9.0), Vector2(x + 3.0 * d, ph - 3.0)]),
			F.CYAN,
			F.THIN,
			true
		)


## A window under a portal: its format's name and the format itself in miniature, as the simulator photo shows them
## (a tap: into its portal, or a widened half's large one).
func _draw_window(r: Rect2, i: int, t: int) -> void:
	var s: float = _s()
	var pw := r.size.x / s
	var ph := r.size.y / s
	var f: String = tabs[i][t]
	var to := i if shown(i) else i - 1
	fmt.begin(r.position, s)
	if r.position.x > glass().position.x + 1.0:
		fmt.line(Vector2(0, 0), Vector2(0, ph), F.DARK_GREY, F.THIN)
	fmt.text(Vector2(2.0, 5.5), f.replace("-", ""), 4.2, F.CYAN)
	_hit(r.position, Rect2(0, 0, pw, ph), func(): _show(to, f))
	fmt.end()
	fmt.begin(r.position + Vector2(0.0, 7.0 * s), s * MINI)
	_draw_body(i, f, Rect2(1.0, 0.0, pw / MINI - 2.0, (ph - 7.0) / MINI - 1.0))
	fmt.end()


## A format's picture in `body` (the portal's frame), without its legends; its buttons (name -> Rect2, panel px in the
## portal) for the caller's taps.
func _draw_body(i: int, name: String, body: Rect2) -> Dictionary:
	var m = cockpit.mfds[i] if i < cockpit.mfds.size() else null
	match name:
		"TSD-1", "TSD-2", "TSD-3":
			fmt.tsd(body, m.tsd_scale if m != null else 40, m.tsd_options[2] if m != null else true)
		"SRCH":
			fmt.radar(body)
		"SMS":
			return fmt.sms(body)
		"WPN-A":
			return fmt.wpn_a(body)
		"WPN-S":
			return fmt.wpn_s(body)
		"TFLIR":
			return fmt.tflir(body)
		"DAS":
			fmt.das(body)
		"TWD":
			fmt.twd(body)
		"EFI":
			fmt.efi(body, _tacan())
		"ICAWS":
			fmt.icaws(body, fmt.icaws_lines(cautions()))
		"FUEL":
			fmt.fuel(body)
		"ENG":
			fmt.engine(body)
		"CNI":
			return fmt.cni(body, _cni())
		"FCS":
			return fmt.fcs(body, _bit())
		"PHM":
			fmt.phm(body, F16Mfd.FAULTS)
		"CHKLST":
			fmt.chklst(body, _checklist())
		"DIM":
			return fmt.dim(body, load_t >= 0.0 and _clock() - load_t < F16Mfd.DTE_LOAD_S, load_t >= 0.0)
		"HUD":
			fmt.hud_repeat(body)
		"AP":
			fmt.autopilot(body)
	return {}


func _draw_format(i: int, name: String, body: Rect2, origin: Vector2, pw: float) -> void:
	var m = cockpit.mfds[i] if i < cockpit.mfds.size() else null
	var buttons := _draw_body(i, name, body)
	for b in buttons:
		_hit(origin, buttons[b], func(): _press(name, b))
	match name:
		"TFLIR":
			# A tap on the picture starts the camera (the pilot takes the sensor; inferred).
			if m != null and int(cockpit.eo.get("mode", 0)) != FLIR_MODE:
				_hit(origin, body, func(): _start_flir(m))
		"TSD-1", "TSD-2", "TSD-3":
			var scale: int = m.tsd_scale if m != null else 40
			var map_on: bool = m.tsd_options[2] if m != null else true
			_range_legends(origin, body, "%d" % scale, func(d): _tsd_range(m, d))
			fmt.legend(Vector2(pw - 3.0, body.position.y + 26.0), "MAP", true, map_on)
			_hit(origin, Rect2(pw - 18.0, body.position.y + 20.0, 16.0, 8.0), func(): _toggle_map(m))
		"SRCH":
			var rd: Dictionary = cockpit.radar
			_range_legends(
				origin, body, "%d" % F.RANGES[clampi(int(rd.get("idx", 1)), 1, 6) - 1], func(d): _radar_range(m, d)
			)
			fmt.legend(Vector2(pw - 3.0, body.position.y + 26.0), "MODE", true)
			_hit(origin, Rect2(pw - 22.0, body.position.y + 20.0, 20.0, 8.0), func(): _radar_mode(m))


## Portal `i`'s CNTL page for format `name`: its controls as buttons (the TFLIR's WIDE / SPOT reads the field of
## view, white while on; MAP and LSR white while on).
func _draw_cntl(i: int, name: String, body: Rect2, origin: Vector2) -> void:
	var m = cockpit.mfds[i] if i < cockpit.mfds.size() else null
	var flir: Dictionary = cockpit.eo.get("flir", {})
	var names: Array = CNTL_OF[name].duplicate()
	var on := ""
	if name == "TFLIR":
		names[2] = "SPOT" if flir.get("spot", false) else "WIDE"
		on = "LSR" if flir.get("laser", false) else ""
	elif name.begins_with("TSD") and m != null and m.tsd_options[2]:
		on = "MAP"
	var buttons: Dictionary = fmt.menu(body, on, names, "", "CNTL")
	for b in buttons:
		_hit(origin, buttons[b], func(): _control(m, name, b))


## A CNTL page's button `b` of format `name` (the MFD node `m`'s page).
func _control(m, name: String, b: String) -> void:
	var ev: Callable = cockpit.on_mfd_event
	match b:
		"MAP":
			_toggle_map(m)
		"RNG UP", "RNG DN":
			var d := 1 if b == "RNG UP" else -1
			if name == "SRCH":
				_radar_range(m, d)
			else:
				_tsd_range(m, d)
		"MODE":
			_radar_mode(m)
		"ZOOM IN", "ZOOM OUT", "WIDE", "SPOT", "LSR":
			if ev.is_valid():
				ev.call({"ZOOM IN": 0x14, "ZOOM OUT": 0x15, "LSR": 0x6a}.get(b, 0x20))


## A format's button `b` tapped (its name from pcd_formats.gd's return).
func _press(name: String, b: String) -> void:
	var ev: Callable = cockpit.on_mfd_event
	var rip: Callable = cockpit.on_ripple_event
	match [name, b]:
		["SMS", "DOORS"]:
			if ev.is_valid():
				ev.call(DOORS_EVENT)
		["WPN-S", "PROF"]:
			if ev.is_valid():
				ev.call(F16Mfd.PROFILE_EVENT)
		["WPN-S", "MODE"]:
			if ev.is_valid():
				ev.call(F16Mfd.GPS_MODE_EVENT)
		["WPN-S", "STEP"]:
			if ev.is_valid():
				ev.call(PRE_STEP_EVENT)
		["WPN-S", "REL"]:
			if rip.is_valid():
				rip.call(-1, true)
		["WPN-S", "QTY"], ["WPN-S", "INT"]:
			# One tap steps the value, wrapping (IafF16Mfd.wrap_presses, as the F-16 SMS's OSBs 9 / 10).
			var q := b == "QTY"
			var v := int(cockpit.weapons.get("quantity" if q else "interval", 2 if q else 10))
			var n: int = ClassDB.class_call_static(
				"IafF16Mfd", "wrap_presses", v, 1 if q else 10, 14 if q else 200, 1 if q else 10
			)
			if rip.is_valid():
				for k in absi(n):
					rip.call(0x4a if q else 0x4b, n > 0)
		["WPN-S", "NEXT"]:
			_next_weapon(false)
		["WPN-A", "NEXT"]:
			_next_weapon(true)
		["TFLIR", "Z+"], ["TFLIR", "Z-"], ["TFLIR", "WIDE"], ["TFLIR", "LSR"], ["TFLIR", "CZ"]:
			if ev.is_valid():
				ev.call({"Z+": 0x14, "Z-": 0x15, "WIDE": 0x20, "LSR": 0x6a, "CZ": F16Mfd.TGP_CZ_EVENT}[b])
		["FCS", "BIT"]:
			if bool(cockpit.state.get("on_ground", true)):
				bit_t = _clock()
		["DIM", "LOAD"]:
			load_t = _clock()
		["CNI", _]:
			_cni_press(b)
		_:
			if name == "SMS" and b.is_valid_int() and cockpit.on_station_select.is_valid():
				cockpit.on_station_select.call(int(b))


## The next station holding another air-to-air (`aa`) or air-to-surface store (WPN-A / WPN-S's NEXT).
func _next_weapon(aa: bool) -> void:
	var wp: Dictionary = cockpit.weapons
	if wp.is_empty() or not cockpit.on_station_select.is_valid():
		return
	var sel := int(wp.get("selected", -1))
	for k in range(1, 10):
		var i := posmod(sel + k, 9)
		var s: Dictionary = wp.stations[i]
		if (
			int(s.count) > 0
			and (int(s.type) in F16Mfd.AAM_TYPES) == aa
			and String(s.name) != String(wp.get("name", ""))
		):
			cockpit.on_station_select.call(i)
			return


## The range legends down the left edge: ▲, the range, ▼ (taps step it).
func _range_legends(origin: Vector2, body: Rect2, value: String, step: Callable) -> void:
	var y := body.position.y + 20.0
	fmt.poly(PackedVector2Array([Vector2(3, y), Vector2(6, y - 4), Vector2(9, y)]), F.CYAN, F.THIN, true)
	fmt.text(Vector2(3.0, y + 8.0), value, 5.0, F.CYAN)
	fmt.poly(PackedVector2Array([Vector2(3, y + 11), Vector2(6, y + 15), Vector2(9, y + 11)]), F.CYAN, F.THIN, true)
	_hit(origin, Rect2(1, y - 6, 12, 7), func(): step.call(1))
	_hit(origin, Rect2(1, y + 10, 12, 7), func(): step.call(-1))


func _toggle_map(m) -> void:
	if m != null:
		m.tsd_options[2] = not m.tsd_options[2]


func _radar_range(m, d: int) -> void:
	if m != null:
		m.step_range(d)


func _radar_mode(m) -> void:
	if m != null:
		m.cycle_radar_mode()


func _tsd_range(m, d: int) -> void:
	if m == null:
		return
	var sc: Array = m.TSD_SCALES
	m.tsd_scale = sc[clampi(sc.find(m.tsd_scale) + d, 0, sc.size() - 1)]


func _clock() -> float:
	return float(cockpit.state.get("tod", 0.0))


## The FCS's BIT (IafF16Mfd.flcs_bit, the F-16 FLCS's: RUN for 45 s, then PASS or FAIL; "" not run).
func _bit() -> String:
	var flags: Array = cockpit.damage_flags
	var fault: bool = flags.size() > 24 and (flags[24] or flags[18])
	return ClassDB.class_call_static("IafF16Mfd", "flcs_bit", bit_t, _clock(), fault)


# --- the CNI (radios, navigation, IFF: the up-front controls' state, IafUfc) ----------------------------------------


## The TACAN station in reach with the navigation source on TACAN ({name, bearing, range_m}), {} otherwise.
func _tacan() -> Dictionary:
	if cockpit.ufc == null or not cockpit.ehsi_tcn:
		return {}
	return cockpit.ufc.tacan(cockpit.ufc_nav())


## What the CNI shows: the UFC's settings (IafUfc.state), the TACAN, the navigation source, the time of day and the
## scratchpad's line (the DED's page as the ICP keys work it); {} without the UFC (reborn).
func _cni() -> Dictionary:
	if cockpit.ufc == null:
		return {}
	var nav: Dictionary = cockpit.ufc_nav()
	var d: Dictionary = cockpit.ufc.state()
	d.tacan = cockpit.ufc.tacan(nav)
	d.source_tcn = cockpit.ehsi_tcn
	d.tod = _clock()
	d.ded = cockpit.ufc.lines(nav)
	return d


## A CNI button: the ICP's key (IafUfc.press; cockpit.gd ufc_press), the navigation source (RTE / TCN, the F-16
## EHSI's M button's command 253) or the IDENT.
func _cni_press(b: String) -> void:
	if cockpit.ufc == null:
		return
	const KEYS := {"ENTR": 10, "RCL": 11, "COM1": 13, "COM2": 14, "IFF": 15, "TCN": 1, "INC": 20, "DEC": 21, "RTN": 18}
	if b.is_valid_int():
		cockpit.ufc_press(int(b))
	elif KEYS.has(b):
		cockpit.ufc_press(KEYS[b])
	elif b == "NAV":
		cockpit.ehsi_tcn = not cockpit.ehsi_tcn
	elif b == "IDENT":
		cockpit.ufc.ident(_clock())


## The start-up checklist's steps: [label, done] (the mission's checklist, else the flight's steps by their ids).
func _checklist() -> Array:
	if _sim_flight == null:
		_sim_flight = get_tree().root.find_child("SimFlight", true, false) if is_inside_tree() else null
	if _sim_flight == null:
		return []
	var done: Array = _sim_flight.done
	var out := []
	for c in _sim_flight.checklist:
		out.append([String(c.get("en", c.get("step", ""))).to_upper(), String(c.get("step", "")) in done])
	if out.is_empty():
		for id in _sim_flight.STEP_IDS:
			out.append([String(id).replace("_", " ").to_upper(), id in done])
	return out


## The cautions the lamps / indicators raise (docs/cockpit.md "Panel lights"), worst first: [text, level].
func cautions() -> Array:
	var ind: Array = cockpit.indicators
	var out := []
	if ind[1] or ind[2]:
		out.append(["ENG FIRE", "warning"])
	if ind[0]:
		out.append(["MASTER CAUTION", "caution"])
	if ind[3]:
		out.append(["RWR AIR THREAT", "caution"])
	if ind[4]:
		out.append(["RWR SAM THREAT", "caution"])
	if ind[5]:
		out.append(["SPEED BRAKE", "advisory"])
	if ind[6]:
		out.append(["ECM ON", "advisory"])
	return out


# --- the Function Access Button strip ----------------------------------------------------------------------------


## The strip along the glass's top (a pilot: "always has a small fuel section"; the order from the Driven
## Technologies picture and a simulator manual): engine dial, fuel, weapon counts, the gear planform, ICAWS, AP / AT,
## SWAP across the halves' seam, the radios, the recorder, MENU, then the time and alerts.
func _draw_fab(g: Rect2) -> void:
	var s: float = _s()
	var pw := g.size.x / s
	var ph := FAB_H
	var st: Dictionary = cockpit.state
	var wp: Dictionary = cockpit.weapons
	# Two rows of small legends (round 6: one 0.53 in strip as the simulator photo; three rows until then).
	var r1 := 6.2
	var r2 := 12.8
	var fs := 3.9
	var cx := pw / 2.0
	# SWAP: the right group starts at the glass's left edge, the left group after the SWAP arrows, narrowed to fit.
	var swapped := bool(self.st.bar_swapped)
	var ro := -(cx + 13.0) if swapped else 0.0
	fmt.begin(g.position, s)
	fmt.line(Vector2(0, ph), Vector2(pw, ph), F.DARK_GREY, F.THIN)
	if swapped:
		fmt.begin(g.position + Vector2((cx + 11.0) * s, 0.0), s, minf(1.0, (pw - cx - 13.0) / FAB_LEFT_W))
	# Engine: the RPM dial and its value.
	var rpm := float(st.get("rpm", 0.0))
	var ab := float(st.get("afterburner", 0.0)) > 0.0
	var ec := Vector2(8, 7.5)
	draw_arc(ec, 5.5, deg_to_rad(135), deg_to_rad(405), 24, F.GREEN, F.THIN, true)
	var a := deg_to_rad(135.0 + 270.0 * clampf(rpm / 1.1, 0.0, 1.0))
	fmt.line(ec, ec + Vector2(cos(a), sin(a)) * 5.0, F.YELLOW if ab else F.GREEN, F.LINE)
	fmt.text(Vector2(15, r1), "%d" % int(round(rpm * 100.0)), fs, F.WHITE)
	if ab:
		fmt.text(Vector2(15, r2), "AB", fs, F.YELLOW)
	# Fuel: total and internal with light purple bars, external, joker.
	var total := float(st.get("fuel_lbs", 0.0))
	var internal := minf(total, float(st.get("internal_fuel_kg", total / 2.20462)) * 2.20462)
	var rows := [["T", total, F.INTERNAL_LB + 5000.0], ["I", internal, F.INTERNAL_LB]]
	for k in 2:
		var y: float = [r1, r2][k]
		fmt.text(Vector2(28, y), rows[k][0], fs, F.GREEN)
		fmt.text(Vector2(28, y), "%.1f" % (float(rows[k][1]) / 1000.0), fs, F.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 22.0)
		fmt.fill(Rect2(52, y - 3.6, 8.0 * clampf(float(rows[k][1]) / float(rows[k][2]), 0.0, 1.0) + 0.6, 4.0), F.PURPLE)
	fmt.text(Vector2(63, r1), "E %.1f" % ((total - internal) / 1000.0), fs, F.GREEN)
	fmt.text(Vector2(63, r2), "JKR %.1f" % (F.JOKER_LB / 1000.0), fs, F.WHITE if total > F.JOKER_LB else F.YELLOW)
	# Weapons: the counts, then chaff, flares and rounds.
	var bombs := 0
	for st2 in wp.get("stations", []).slice(0, 9):
		if int(st2.type) in [500, 510, 520, 530, 540, 650]:
			bombs += int(st2.count)
	fmt.text(Vector2(86, r1), "%d MRM  %d SRM" % [int(wp.get("mrm", 0)), int(wp.get("srm", 0))], fs, F.GREEN)
	fmt.text(Vector2(86, r2), "%d BOMB" % bombs, fs, F.GREEN)
	fmt.text(Vector2(118, r1), "CH %d  FL %d" % [int(wp.get("chaff", 0)), int(wp.get("flares", 0))], fs, F.WHITE)
	fmt.text(Vector2(118, r2), "GUN %d" % int(wp.get("gun", 0)), fs, F.WHITE)
	# The gear planform: green with the legs down, the legs' lights; the flaps beside it.
	var gc := Vector2(156, 7.5)
	var gpts := PackedVector2Array()
	for p in [
		Vector2(0, -9),
		Vector2(1.5, -3),
		Vector2(7, 3),
		Vector2(7, 5),
		Vector2(2, 4),
		Vector2(3, 9),
		Vector2(-3, 9),
		Vector2(-2, 4),
		Vector2(-7, 5),
		Vector2(-7, 3),
		Vector2(-1.5, -3)
	]:
		gpts.append(gc + p * 0.62)
	var legs: Array = cockpit.gear_legs
	var down := legs.all(func(v): return v == 2)
	fmt.poly(gpts, F.GREEN if down else F.GREY, F.THIN, true)
	for k in 3:
		var at: Vector2 = gc + [Vector2(0, -6), Vector2(-4, 5), Vector2(4, 5)][k] * 0.62
		var v: int = legs[k]
		if v == 2:
			fmt.fill(Rect2(at - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), F.GREEN)
		elif v == 1:
			fmt.fill(Rect2(at - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), F.RED)
	fmt.text(Vector2(164, r2), "FLAPS " + ["UP", "TR", "DN"][clampi(cockpit.flaps_state, 0, 2)], fs, F.GREEN)
	# ICAWS: the worst line.
	var lines: Array = fmt.icaws_lines(cautions())
	fmt.text(Vector2(196, r1), "ICAWS", fs, F.CYAN if lines.is_empty() else fmt.level_colour(lines[0][1]))
	if not lines.is_empty():
		fmt.text(
			Vector2(196, r2),
			lines[0][0] + ("  +%d" % (lines.size() - 1) if lines.size() > 1 else ""),
			fs,
			fmt.level_colour(lines[0][1])
		)
	# AP / AT.
	var ap_on: bool = cockpit.indicators[8]
	var mode := int(st.get("ap_mode", 0))
	var ap: String = "AP" + ([" ", " LVL", " NAV"][clampi(mode, 0, 2)] if ap_on else "")
	fmt.text(Vector2(250, r1), ap, fs, F.GREEN if ap_on else F.GREY)
	fmt.text(Vector2(250, r2), "AT", fs, F.GREY)
	# SWAP across the seam (tap: the halves trade places).
	fmt.begin(g.position, s)
	fmt.poly(PackedVector2Array([Vector2(cx - 10, 7.5), Vector2(cx - 4, 2), Vector2(cx - 4, 13)]), F.CYAN, F.THIN, true)
	fmt.poly(PackedVector2Array([Vector2(cx + 10, 7.5), Vector2(cx + 4, 2), Vector2(cx + 4, 13)]), F.CYAN, F.THIN, true)
	fmt.begin(g.position + Vector2(ro * s, 0.0), s)
	# The radios A (UHF) and B (VHF) by their presets (C: none in the sim), the navigation source and its steering: the
	# route's steerpoint or the TACAN station (Modern IAF's CNI, IafUfc; reborn: the route).
	var cni := _cni()
	var ra := "A U%d   B V%d" % [int(cni.uhf_preset), int(cni.vhf_preset)] if not cni.is_empty() else "A U 1   B U 1"
	fmt.text(Vector2(cx + 16, r1), ra, fs, F.GREEN)
	fmt.text(
		Vector2(cx + 16, r2), "%.2f" % (float(cni.uhf_khz) / 1000.0) if not cni.is_empty() else "C U 1", fs, F.GREEN
	)
	fmt.text(Vector2(cx + 50, r1), "NAV", fs, F.GREEN)
	var nav := "RTE %d" % (cockpit.current_waypoint + 1)
	if not cni.is_empty() and cni.source_tcn:
		nav = "TCN %d%s" % [int(cni.tcn_chan), "Y" if cni.tcn_y else "X"]
	fmt.text(Vector2(cx + 50, r2), nav, fs, F.WHITE)
	# The recorder.
	var rec := Settings.blackbox
	fmt.text(Vector2(cx + 74, r1), "RCDR", fs, F.CYAN)
	fmt.circle(Vector2(cx + 77, r2 - 1.6), 1.8, F.GREEN if rec else F.GREY, F.THIN)
	if rec:
		fmt.circle(Vector2(cx + 77, r2 - 1.6), 0.8, F.RED, F.LINE)
	var tod := int(st.get("tod", 0.0))
	fmt.text(Vector2(cx + 81, r2), "%02d:%02d:%02d" % [(tod / 3600) % 24, (tod / 60) % 60, tod % 60], fs, F.GREEN)
	# MENU: the grid icon.
	var mg := Rect2(cx + 110, 1.5, 12, 12)
	for k in 4:
		fmt.line(
			Vector2(mg.position.x, mg.position.y + 4.0 * k), Vector2(mg.end.x, mg.position.y + 4.0 * k), F.GREY, F.THIN
		)
		fmt.line(
			Vector2(mg.position.x + 4.0 * k, mg.position.y), Vector2(mg.position.x + 4.0 * k, mg.end.y), F.GREY, F.THIN
		)
	fmt.text(Vector2(mg.end.x + 2.0, r1), "MENU", fs, F.WHITE)
	# The right block: speed / altitude / Mach, the alerts (CABIN, GCAS, ALOW), IFF's modes and code, the time.
	var rx := cx + 142
	if not cni.is_empty():
		var on: Array = cni.xpdr_on
		var ident := _clock() < float(cni.ident_until)
		fmt.text(
			Vector2(rx + 90, r1),
			"IFF %s%04d%s" % ["M3 " if on[2] else "", int(cni.xpdr_codes[2]), " I" if ident else ""],
			fs,
			F.GREEN
		)
	fmt.text(Vector2(rx, r1), "CAS %d" % int(st.get("ias_kt", 0.0)), fs, F.WHITE)
	fmt.text(Vector2(rx, r2), "ALT %d" % int(round(float(st.get("alt_ft", 0.0)) / 10.0) * 10), fs, F.WHITE)
	fmt.text(Vector2(rx + 32, r1), "M %.2f" % float(st.get("mach", 0.0)), fs, F.WHITE)
	var low := float(st.get("agl_ft", 9999.0)) < 500.0 and not bool(st.get("on_ground", false))
	fmt.text(Vector2(rx + 56, r1), "CABIN  GCAS", fs, F.GREEN)
	fmt.text(Vector2(rx + 56, r2), "ALOW 500", fs, F.YELLOW if low else F.GREEN)
	fmt.text(
		Vector2(rx, r2),
		"%02d:%02d Z" % [(tod / 3600) % 24, (tod / 60) % 60],
		fs,
		F.WHITE,
		HORIZONTAL_ALIGNMENT_RIGHT,
		pw - rx - 3.0
	)
	fmt.end()
	_fab_hits(g, pw, cx, rx)


## The strip's taps: SWAP trades its halves, MENU opens the MENU page (CRUS) as a pop-up on the portal under it (a
## simulator manual p. 34; IafPcd swap_bar, popup); in Modern IAF also the items open their pop-ups in the portal under
## them: the engine ENG, the fuel FUEL, the weapons SMS, the planform FCS, ICAWS, AP, the radios, the navigation source
## and IFF the CNI. A swapped strip draws its left group after the seam, narrowed, and its right group from the glass's
## left edge (_draw_fab); the taps follow.
func _fab_hits(g: Rect2, pw: float, cx: float, rx: float) -> void:
	var k := minf(1.0, (pw - cx - 13.0) / FAB_LEFT_W)
	var at := func(x: float) -> float:
		if not bool(st.bar_swapped):
			return x
		return cx + 11.0 + x * k if x < cx else x - (cx + 13.0)
	_hit(g.position, Rect2(cx - 11.0, 0, 22.0, FAB_H), func(): _do(func(): lay.swap_bar()))
	var mx: float = at.call(cx + 108.0)
	_hit(g.position, Rect2(mx, 0, 30.0, FAB_H), func(): _do(func(): lay.popup((mx + 8.0) / pw, "MENU")))
	if not modern:
		return
	var items := [
		[0.0, 26.0, "ENG"],
		[26.0, 84.0, "FUEL"],
		[84.0, 148.0, "SMS"],
		[148.0, 194.0, "FCS"],
		[194.0, 248.0, "ICAWS"],
		[248.0, cx - 12.0, "AP"],
		[cx + 14.0, cx + 72.0, "CNI"],
		[rx + 88.0, pw - 2.0, "CNI"]
	]
	for it in items:
		var x0: float = at.call(float(it[0]))
		var x1: float = at.call(float(it[1]))
		var f: String = it[2]
		_hit(g.position, Rect2(x0, 0, x1 - x0, FAB_H), func(): _do(func(): lay.popup((x0 + 4.0) / pw, f)))


func _fs(px: float) -> int:
	return maxi(int(px * _s()), 4)


func _text(at: Vector2, t: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, t, align, width, _fs(size), col)


# --- the standby display ------------------------------------------------------------------------------------------


## The ESIS (electronic standby instrument): the attitude sphere as a flat sky / ground split rolled and pitched
## (2 px per degree of the 60° tall field), pitch lines every 10°, the fixed aircraft, speed and altitude boxes and
## the heading.
func _draw_esis(r: Rect2) -> void:
	var st: Dictionary = cockpit.state
	var s: float = _s()
	var c := r.get_center()
	var k := r.size.y / 60.0  # screen px per degree
	var roll := deg_to_rad(float(st.roll))
	var right := Vector2(cos(roll), -sin(roll))
	var down := Vector2(sin(roll), cos(roll))
	var h := c + down * float(st.pitch) * k  # the horizon's centre
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_rect(r, SKY)
	for poly in ground_polys(box, h, right, down):
		draw_colored_polygon(poly, GROUND)
	for p in range(-30, 31, 10):
		var w := (0.30 if p == 0 else 0.12) * r.size.x
		var m := h - down * p * k
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([m - right * w, m + right * w]), box):
			draw_polyline(seg, WHITE, maxf(1.0, s * 0.6))
	# The aircraft symbol, then the speed / altitude / heading readouts.
	var a := 0.16 * r.size.x
	draw_polyline(
		PackedVector2Array(
			[
				c + Vector2(-a, 0),
				c + Vector2(-a * 0.35, 0),
				c + Vector2(0, a * 0.25),
				c + Vector2(a * 0.35, 0),
				c + Vector2(a, 0)
			]
		),
		AMBER,
		maxf(1.5, s * 1.2)
	)
	var fs := r.size.y / s * 0.12
	var bw := r.size.x * 0.30
	var bh := r.size.y * 0.17
	for i in 2:
		var b := Rect2(Vector2(r.position.x if i == 0 else r.end.x - bw, c.y - bh / 2), Vector2(bw, bh))
		draw_rect(b, Color(0, 0, 0, 0.85))
		draw_rect(b, WHITE, false, 1.0)
		var v := "%d" % int(st.get("ias_kt", 0.0)) if i == 0 else "%d" % int(round(float(st.alt_ft) / 10.0) * 10)
		_text(Vector2(b.position.x, b.end.y - bh * 0.22), v, fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER, bw)
	var hb := Rect2(Vector2(c.x - bw * 0.5, r.end.y - bh), Vector2(bw, bh))
	draw_rect(hb, Color(0, 0, 0, 0.85))
	_text(
		Vector2(hb.position.x, hb.end.y - bh * 0.22),
		"%03d" % (int(round(float(st.heading))) % 360),
		fs,
		WHITE,
		HORIZONTAL_ALIGNMENT_CENTER,
		bw
	)
	draw_rect(r, Color(0, 0, 0), false, maxf(1.0, s))


## The ground's part of the ESIS box `box` below the horizon through `h` (along `right`, ground towards `down`). A
## horizon that grazes a corner leaves a sliver a fraction of a pixel thick that the renderer cannot triangulate
## ("Invalid polygon data"): such slivers are left out.
static func ground_polys(box: PackedVector2Array, h: Vector2, right: Vector2, down: Vector2) -> Array:
	var big := (box[2] - box[0]).length() * 2.0
	var ground := PackedVector2Array(
		[h - right * big, h + right * big, h + right * big + down * big, h - right * big + down * big]
	)
	return Geometry2D.intersect_polygons(box, ground).filter(
		func(p): return not Geometry2D.triangulate_polygon(p).is_empty()
	)


# --- layer 1: the glass ------------------------------------------------------------------------------------------


## A faint sheen over the whole glass, the canopy's light reflected near its top fading downward.
func _draw_sheen() -> void:
	var g := glass()
	var mid := g.position.y + g.size.y * 0.45
	var top := Color(0.75, 0.82, 0.95, 0.07)
	var clear := Color(0.75, 0.82, 0.95, 0.0)
	draw_polygon(
		PackedVector2Array(
			[g.position, Vector2(g.end.x, g.position.y), Vector2(g.end.x, mid), Vector2(g.position.x, mid)]
		),
		PackedColorArray([top, top, clear, clear])
	)
	# A soft diagonal streak across the left half.
	var x0 := g.position.x + g.size.x * 0.08
	var w := g.size.x * 0.10
	var streak := Color(0.85, 0.9, 1.0, 0.035)
	draw_polygon(
		PackedVector2Array(
			[
				Vector2(x0 + w, g.position.y),
				Vector2(x0 + 2.2 * w, g.position.y),
				Vector2(x0 + w * 1.2, g.end.y),
				Vector2(x0, g.end.y)
			]
		),
		PackedColorArray([streak, clear, clear, streak])
	)
