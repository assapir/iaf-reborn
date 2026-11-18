# Ours (the F-35I, docs/f35i.md §4.3, docs/real-mfd.md "F-35I"): the panoramic cockpit display (PCD) as the real one
# lays it out, from the cockpit's [PCD] section (panel px, tools/f35i/cockpit3d.py): the black glass; the Function
# Access Button strip along its top (engine, fuel, weapons, gear, ICAWS, autopilot, SWAP, radios, recorder, MENU, the
# time and alerts); under it the two halves, each either one large portal (its other formats as tabs along its foot) or
# two portals over four small windows (LM's 5 x 5 in portals over 2.5 in windows; a window taps its format into the
# portal above), the user's simulator photo's split by default: the left half one portal, the right two over windows;
# each portal a format (pcd_formats.gd) with its name and master mode and its option legends; a portal's MENU grid;
# and the standby display (ESIS) under the glass. Layer 0 draws it all; layer 1, over it, only the glass's sheen. The
# strip's SWAP trades its halves, its MENU opens the additional MENU page as a pop-up on the portal under it, a
# portal's CNTL> its format's control page (docs/real-mfd.md "F-35I"). In the 3D cockpit (cockpit3d.gd) layer 0 draws
# the glass into its screen's SubViewport (screen_px), the sheen is the glass's own and a layer 2 draws the ESIS into
# its own. Each portal keeps an MFD node (mfd.gd, hidden) whose page follows the format, so the systems that read the
# pages (the EO camera, the M key, the full-screen MFD) work as before.
extends Control

const Formats := preload("res://shared/cockpit/pcd_formats.gd")
const F := Formats
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
const PAGE_OF := {"TSD-1": 3, "TSD-2": 3, "TSD-3": 3, "SRCH": 2, "SMS": 1, "TFLIR": 6, "TWD": 7, "EFI": 9, "ICAWS": 4}
## The format a game page shows when something else sets it (the M key, a weapon, the full-screen MFD).
const FORMAT_OF := {
	0: "TSD-1", 1: "SMS", 2: "SRCH", 3: "TSD-1", 4: "ICAWS", 5: "TFLIR", 6: "TFLIR", 7: "TWD", 9: "EFI", 10: "SMS"
}

var cockpit: Control
var layer := 0
var font: Font
var fmt: Formats
## Per portal: the main format, its two windows' formats (a full half: its tabs), the MENU grid open, the page last
## seen on its MFD node. The halves' portals are 0-1 and 2-3; a full half shows its first portal only.
const DEFAULT_MAIN := ["TSD-1", "SMS", "SRCH", "TFLIR"]
const DEFAULT_TABS := [["TSD-2", "ENG"], ["TSD-3", "ICAWS"], ["TWD", "FUEL"], ["EFI", "ENG"]]
## Per half: one large portal (true) or two portals over windows (the user's simulator photo, 2026-11-17).
const DEFAULT_FULL := [true, false]
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
var main := DEFAULT_MAIN.duplicate()
var tabs := DEFAULT_TABS.duplicate(true)
var full := DEFAULT_FULL.duplicate()
var menu_open := [false, false, false, false]
## Per portal: its CNTL page open.
var cntl_open := [false, false, false, false]
## The portal showing the strip's MENU page as a pop-up (-1 none).
var popup := -1
## SWAP: the strip's halves traded (the portals stay).
var fab_swapped := false
var _page_seen := [-1, -1, -1, -1]
## Clickable areas of the last frame: [Rect2 (screen px), Callable].
var _hits: Array = []
## Ours, the 3D cockpit (cockpit3d.gd): drawn into a SubViewport at this many px per panel px, the panel px
## screen_origin at its corner (0: on the 2D panel).
var screen_px := 0.0
var screen_origin := Vector2.ZERO


func setup(c: Control, l: int) -> void:
	cockpit = c
	layer = l
	mouse_filter = Control.MOUSE_FILTER_PASS if l == 0 else Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = Settings.display_font("narrow")
	fmt = Formats.new(self, c, font)


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


## The four portals' screen rects, left to right under the strip: a full half's first portal over the whole half
## (to the glass's foot), its second an empty rect (hidden); a split half's two over the windows.
func portals() -> Array:
	var g := glass()
	var top := g.position.y + FAB_H * _s()
	var w := g.size.x / 4.0
	var foot := g.end.y - g.size.y * WIN_FRAC
	var out := []
	for h in 2:
		var x := g.position.x + 2.0 * h * w
		if full[h]:
			out.append_array([Rect2(x, top, 2.0 * w, g.end.y - top), Rect2()])
		else:
			out.append_array([Rect2(x, top, w, foot - top), Rect2(x + w, top, w, foot - top)])
	return out


## The windows under the split halves' portals: [screen rect, portal, its tab].
func windows() -> Array:
	var g := glass()
	var w := g.size.x / 8.0
	var top := g.end.y - g.size.y * WIN_FRAC
	var out := []
	for i in 4:
		if not full[i / 2]:
			for t in 2:
				out.append([Rect2(g.position.x + (2 * i + t) * w, top, w, g.end.y - top), i, t])
	return out


## Whether portal `i` shows (a full half hides its second).
func shown(i: int) -> bool:
	return not (full[i / 2] and i % 2 == 1)


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
			var want: String = FORMAT_OF.get(int(m.page), main[i])
			if was < 0 and PAGE_OF.has(main[i]):  # the first frame: the nodes take the default layout's pages
				_set_page(i)
			elif PAGE_OF.get(main[i], -1) != int(m.page) and want != main[i]:
				if shown(i):
					_show(i, want)
				else:
					# A page set on a hidden portal shows on its half's large one (on the other half's first when that
					# one shows the radar); the hidden node keeps its page.
					var to := i - 1 if main[i - 1] != "SRCH" else (i + 1) % 4
					m.page = was
					_page_seen[i] = was
					_show(to, want)


## Portal `i` shows format `f`: a tab holding it swaps with the main format (in a full half also the hidden portal's
## format and tabs); the MFD nodes' pages follow.
func _show(i: int, f: String) -> void:
	if f == "MENU":
		menu_open[i] = true
		return
	var t: int = tabs[i].find(f)
	var j := i + 1 if i % 2 == 0 else i - 1
	if t >= 0:
		tabs[i][t] = main[i]
	elif full[i / 2] and main[j] == f:
		main[j] = main[i]
		_set_page(j)
	elif full[i / 2] and tabs[j].has(f):
		tabs[j][tabs[j].find(f)] = main[i]
	main[i] = f
	menu_open[i] = false
	cntl_open[i] = false
	if popup == i:
		popup = -1
	_set_page(i, true)


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


## The strip's MENU page's CRUS: the layout the display starts with, the strip unswapped, every page open closed.
func restore_layout() -> void:
	main = DEFAULT_MAIN.duplicate()
	tabs = DEFAULT_TABS.duplicate(true)
	full = DEFAULT_FULL.duplicate()
	menu_open = [false, false, false, false]
	cntl_open = [false, false, false, false]
	popup = -1
	fab_swapped = false
	for i in 4:
		_set_page(i)


## The strip's SWAP: its two halves trade places.
func swap_fab() -> void:
	fab_swapped = not fab_swapped


## The strip's MENU: its page as a pop-up on the shown portal under the MENU legend (at panel px `x` of the glass); a
## second tap closes it.
func fab_menu(x: float) -> void:
	if popup >= 0:
		popup = -1
		return
	var g := glass()
	var at := g.position.x + x * _s()
	var ps := portals()
	for i in 4:
		if shown(i) and at >= ps[i].position.x and at < ps[i].end.x:
			popup = i
			menu_open[i] = false
			cntl_open[i] = false


## A portal's header tapped: a pop-up there closes (the portal shows its format again), else the MENU grid opens or
## closes.
func _header(i: int) -> void:
	if popup == i:
		popup = -1
	else:
		menu_open[i] = not menu_open[i]
		cntl_open[i] = false


## A portal's CNTL> tapped: its format's control page opens or closes.
func _cntl(i: int) -> void:
	cntl_open[i] = not cntl_open[i]
	menu_open[i] = false


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
	var g := glass()
	draw_rect(g, Color.BLACK)
	_draw_fab(g)
	var ps := portals()
	for i in 4:
		if shown(i):
			_draw_portal(i, ps[i])
	for w in windows():
		_draw_window(w[0], w[1], w[2])
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
	fmt.begin(pr.position, s)
	# Frame lines between portals (grey, thin).
	if i > 0:
		fmt.line(Vector2(0, 0), Vector2(0, ph), F.DARK_GREY, F.THIN)
	if not full[i / 2]:
		fmt.line(Vector2(0, ph), Vector2(pw, ph), F.DARK_GREY, F.THIN)
	var tab_row := TAB_H if full[i / 2] else 0.0
	var name: String = main[i]
	var shown := name
	if name == "SRCH" and int(cockpit.radar.get("mode", 0)) >= 7:
		shown = "ASR"
	# The header: the format name over the master mode (tap: the MENU grid, or a pop-up closed); CNTL> on the right
	# (tap: the format's control page); a pop-up's magenta POP UP.
	fmt.text(Vector2(3.0, 6.5), ("MENU" if popup == i else shown).replace("-", ""), 5.6, F.GREEN)
	fmt.text(Vector2(3.0, 12.5), master_mode(), 4.6, F.GREEN)
	if popup == i:
		fmt.text(Vector2(30.0, 12.5), "POP UP", 4.4, F.MAGENTA)
	_hit(pr.position, Rect2(0, 0, 30, HEAD_H), func(): _header(i))
	if CNTL_OF.has(name) and popup != i:
		fmt.legend(Vector2(pw - 3.0, 6.5), "CNTL>", true, cntl_open[i])
		_hit(pr.position, Rect2(pw - 26.0, 0, 24.0, 10.0), func(): _cntl(i))
	var body := Rect2(2.0, HEAD_H + 1.0, pw - 4.0, ph - HEAD_H - tab_row - 4.0)
	if popup == i:
		var buttons: Dictionary = fmt.menu(body, "", ["CRUS"])
		_hit(pr.position, buttons.CRUS, restore_layout)
	elif menu_open[i]:
		var buttons: Dictionary = fmt.menu(body, name)
		for f in buttons:
			_hit(pr.position, buttons[f], func(): _show(i, f))
	elif cntl_open[i] and CNTL_OF.has(name):
		_draw_cntl(i, name, body, pr.position)
	else:
		_draw_format(i, name, body, pr.position, pw)
	if full[i / 2]:
		_draw_tabs(i, pr, pw, ph)
	fmt.end()


## A full half's tabs along its portal's foot (cyan, swap in on a tap): its own two, the hidden portal's format and
## its two; the corner arrows.
func _draw_tabs(i: int, pr: Rect2, pw: float, ph: float) -> void:
	var j := i + 1
	var names: Array = tabs[i] + [main[j]] + tabs[j]
	var tw := (pw - 20.0) / names.size()
	for t in names.size():
		var f: String = names[t]
		var tr := Rect2(10.0 + tw * t + 1.0, ph - TAB_H - 1.0, tw - 2.0, TAB_H - 1.5)
		fmt.box(tr, F.CYAN, F.THIN)
		fmt.text(
			Vector2(tr.position.x, tr.end.y - 2.6),
			f.replace("-", ""),
			5.0,
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


## A window under a split half's portal: its format's name and the format itself in miniature, as the simulator photo
## shows them (a tap: into the portal above; until round 6 its name and one value).
func _draw_window(r: Rect2, i: int, t: int) -> void:
	var s: float = _s()
	var pw := r.size.x / s
	var ph := r.size.y / s
	var f: String = tabs[i][t]
	fmt.begin(r.position, s)
	if t > 0 or i % 2 == 1:
		fmt.line(Vector2(0, 0), Vector2(0, ph), F.DARK_GREY, F.THIN)
	fmt.text(Vector2(2.0, 5.5), f.replace("-", ""), 4.2, F.CYAN)
	_hit(r.position, Rect2(0, 0, pw, ph), func(): _show(i, f))
	fmt.end()
	fmt.begin(r.position + Vector2(0.0, 7.0 * s), s * MINI)
	_draw_body(i, f, Rect2(1.0, 0.0, pw / MINI - 2.0, (ph - 7.0) / MINI - 1.0))
	fmt.end()


## A format's picture in `body` (the portal's frame), without its legends.
func _draw_body(i: int, name: String, body: Rect2) -> void:
	var m = cockpit.mfds[i] if i < cockpit.mfds.size() else null
	match name:
		"TSD-1", "TSD-2", "TSD-3":
			fmt.tsd(body, m.tsd_scale if m != null else 40, m.tsd_options[2] if m != null else true)
		"SRCH":
			fmt.radar(body)
		"SMS":
			fmt.sms(body)
		"TFLIR":
			fmt.tflir(body)
		"TWD":
			fmt.twd(body)
		"EFI":
			fmt.efi(body)
		"ICAWS":
			fmt.icaws(body, fmt.icaws_lines(cautions()))
		"FUEL":
			fmt.fuel(body)
		"ENG":
			fmt.engine(body)


func _draw_format(i: int, name: String, body: Rect2, origin: Vector2, pw: float) -> void:
	var m = cockpit.mfds[i] if i < cockpit.mfds.size() else null
	_draw_body(i, name, body)
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
	var buttons: Dictionary = fmt.menu(body, on, names, "CNTL")
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
	var ro := -(cx + 13.0) if fab_swapped else 0.0
	fmt.begin(g.position, s)
	fmt.line(Vector2(0, ph), Vector2(pw, ph), F.DARK_GREY, F.THIN)
	if fab_swapped:
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
	_hit(g.position, Rect2(cx - 11.0, 0.0, 22.0, ph), swap_fab)
	fmt.begin(g.position + Vector2(ro * s, 0.0), s)
	# The radios (UHF), the steering.
	fmt.text(Vector2(cx + 16, r1), "A U 1   B U 1", fs, F.GREEN)
	fmt.text(Vector2(cx + 16, r2), "C U 1", fs, F.GREEN)
	fmt.text(Vector2(cx + 50, r1), "NAV", fs, F.GREEN)
	fmt.text(Vector2(cx + 50, r2), "RTE %d" % (cockpit.current_waypoint + 1), fs, F.WHITE)
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
	_hit(g.position, Rect2(cx + 108.0 + ro, 0.0, 30.0, ph), func(): fab_menu(cx + 116.0 + ro))
	# The right block: speed / altitude / Mach, the alerts (CABIN, GCAS, ALOW), the time.
	var rx := cx + 142
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
