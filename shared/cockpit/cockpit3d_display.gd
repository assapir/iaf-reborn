# Ours (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit"): a small display of the 3D cockpit that FlightGear draws
# with its canvas system, drawn here from our cockpit state into a SubViewport on the model's screen
# (cockpit3d.gd _attach_display): the RWR azimuth indicator's scope (the 2D panel's RWR symbols), the EHSI (heading
# rose, bearing and range to the steerpoint), the DED's CNI page (steerpoint, time of day) and the pilot fault list
# display (the systems damage).
extends Control

const Hud := preload("res://shared/cockpit/hud.gd")
enum Kind { RWR, EHSI, DED, PFL }
## The 2D panel RWR dial's radius ([PANELRWR] of the F-16, original px): the symbols' scale against the scope.
const RWR_RADIUS := 28.0
## The scope's printed rings, the EHSI's white and the DED's green (inferred from cockpit photos).
const RING := Color(0.12, 0.45, 0.16)
const WHITE := Color(0.92, 0.95, 0.92)
const CYAN := Color(0.3, 0.85, 1.0)
const DED_GREEN := Color(0.55, 1.0, 0.3)
## The pilot fault list display's colours (FlightGear's pfd.nas, the Block 50/52's).
const PFL_BG := Color(0.0, 0.04, 0.01)
const PFL_GREEN := Color(0.45, 0.98, 0.06)
## The pilot fault list's lines by the damage flags (docs/damage.md §5.2), warnings first: [flags, class (0 FLCS
## warning, 1 FLCS, 2 ENG, 3 AV), text]. The texts are FlightGear's fault list's (failures.nas, from GR1F-F16CJ-34-1
## p. 1-475); the AB, gun and ECM lines are ours (inferred).
const FAULTS := [
	[[16, 17], 0, ">FIRE          <"],
	[[24], 0, ">FLCS BIT  FAIL<"],
	[[18], 1, " HYD  A    FAIL "],
	[[4], 1, " ISA  FLAP FAIL "],
	[[5], 1, " SPD  BRAK FAIL "],
	[[7], 1, " GEAR      FAIL "],
	[[6], 1, " FLCS A/P  FAIL "],
	[[2, 3, 22, 23], 2, " ENG       FAIL "],
	[[8, 9], 2, " ENG  AB   FAIL "],
	[[10], 2, " TANK LEAK      "],
	[[19, 21], 3, " GEN  MAIN FAIL "],
	[[21], 3, " GEN  STBY FAIL "],
	[[15], 3, " FCR       FAIL "],
	[[14], 3, " RWR  DEGR      "],
	[[12], 3, " HUD       FAIL "],
	[[11], 3, " AIR  DATA FAIL "],
	[[20], 3, " FCC       FAIL "],
	[[13], 3, " GUN       FAIL "],
	[[1], 3, " ECM       FAIL "],
]
const ROSE := ["N", "3", "6", "E", "12", "15", "S", "21", "24", "W", "30", "33"]

static var _font: Font
static var _font_of: Script  # the Settings script that gave _font (a test swaps it)
var cockpit: Control
var kind := Kind.RWR
## What the last draw showed (tests): the RWR symbols' count, the DED's lines, the EHSI's range (NM, -1 none).
var shown := {}


func _init(c: Control, k: Kind, px: Vector2i) -> void:
	cockpit = c
	kind = k
	size = px
	if _font_of != Settings.get_script():
		_font = Settings.display_font("mono")
		_font_of = Settings.get_script()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	match kind:
		Kind.RWR:
			_rwr()
		Kind.EHSI:
			_ehsi()
		Kind.DED:
			_ded()
		Kind.PFL:
			_pfl()


## The 2D panel's RWR symbols (cockpit.gd draw_rwr_symbols) about the scope's centre; none with RWR damage (14).
func _rwr() -> void:
	var c := size / 2.0
	var r := size.x * 0.45
	for k in [0.5, 1.0]:
		draw_arc(c, r * k, 0.0, TAU, 64, RING, 2.0, true)
	var flags: Array = cockpit.damage_flags
	var n := 0
	if not (flags.size() > 14 and flags[14]):
		cockpit.draw_rwr_symbols(self, c, RWR_RADIUS, r / RWR_RADIUS)
		n = cockpit.rwr.filter(func(e): return e.active).size()
	shown = {"symbols": n}


## The EHSI's NAV page: the heading rose turning with the heading under the lubber line, the bearing pointer to the
## steerpoint (hud.gd nav_cues) and its range (NM) top left.
func _ehsi() -> void:
	var st: Dictionary = cockpit.state
	var c := size / 2.0 + Vector2(0, size.y * 0.04)
	var r := size.x * 0.36
	var hdg := float(st.heading)
	var fs := int(size.x * 0.075)
	for i in 72:
		var a := deg_to_rad(i * 5.0 - hdg)
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * r, c + d * r * (0.86 if i % 2 == 0 else 0.93), WHITE, 2.0, true)
		if i % 6 == 0:
			_text(c + d * r * 0.7, ROSE[i / 6], fs, WHITE)
	draw_line(c - Vector2(0, r * 1.04), c - Vector2(0, r * 1.18), WHITE, 3.0, true)  # the lubber line
	# The ownship.
	var k := r * 0.12
	draw_line(c + Vector2(0, -k), c + Vector2(0, k * 1.3), WHITE, 2.0, true)
	draw_line(c + Vector2(-k, 0), c + Vector2(k, 0), WHITE, 2.0, true)
	draw_line(c + Vector2(-k * 0.5, k * 1.2), c + Vector2(k * 0.5, k * 1.2), WHITE, 2.0, true)
	var dist := -1.0
	if not cockpit.waypoints.is_empty():
		var nav := Hud.nav_cues(st, cockpit.waypoints, cockpit.current_waypoint)
		var b := deg_to_rad(float(nav.bearing_deg) - hdg)
		var d := Vector2(sin(b), -cos(b))
		var n := Vector2(-d.y, d.x)
		var tip := c + d * r * 1.0
		draw_colored_polygon(
			PackedVector2Array([tip, tip - d * r * 0.16 + n * r * 0.07, tip - d * r * 0.16 - n * r * 0.07]), CYAN
		)
		draw_line(c - d * r * 0.98, c - d * r * 0.84, CYAN, 3.0, true)  # its tail
		dist = float(nav.dist_nm)
		_text(Vector2(size.x * 0.13, size.y * 0.1), "%03d" % mini(roundi(dist), 999), fs, WHITE)
		_text(Vector2(size.x * 0.13, size.y * 0.18), "NM", int(fs * 0.7), WHITE)
	_text(Vector2(size.x * 0.12, size.y * 0.92), "NAV", fs, WHITE)
	shown = {"dist_nm": dist, "heading": hdg}


## The DED's CNI page, 5 lines of 24 characters: the steerpoint on line 1, the time of day on line 3.
func _ded() -> void:
	var stpt := "STPT %2d" % (cockpit.current_waypoint + 1) if not cockpit.waypoints.is_empty() else ""
	var t := int(float(cockpit.state.get("tod", 0.0))) % 86400
	var lines := [
		"%24s" % (stpt + "     "), "", "%24s" % ("%02d:%02d:%02d   " % [t / 3600, t / 60 % 60, t % 60]), "", ""
	]
	var lh := size.y / 5.0
	var fs := int(minf(lh * 0.9, size.x / 24.0 / 0.6))
	for i in 5:
		draw_string(
			_font, Vector2(size.x * 0.02, lh * (i + 0.8)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DED_GREEN
		)
	shown = {"lines": lines}


## The pilot fault list display (FlightGear's pfd.nas layout): line 1 the classes with a fault (FLCS, ENG, AV), lines
## 3-5 the first three faults, a third line framed by ▼ when more wait.
func _pfl() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PFL_BG)
	var flags: Array = cockpit.damage_flags
	var faults := []
	var classes := [false, false, false]
	for f in FAULTS:
		if f[0].any(func(i: int) -> bool: return i < flags.size() and bool(flags[i])):
			faults.append(f[2])
			classes[maxi(f[1] - 1, 0)] = true
	var lines := [
		(
			"  %s     %s     %s"
			% ["FLCS" if classes[0] else "    ", "ENG" if classes[1] else "   ", "AV" if classes[2] else "  "]
		),
		"",
	]
	for i in 3:
		lines.append(("  %s  " % faults[i]) if i < faults.size() else "")
	if faults.size() > 3:
		lines[4] = "\u25bc %s \u25bc" % faults[2]
	var fs := int(size.y * 0.1)
	for i in 5:
		draw_string(
			_font,
			Vector2(size.x * 0.215, size.y * (0.2 + 0.1 * i)),
			lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			PFL_GREEN
		)
	shown = {"lines": lines}


func _text(at: Vector2, t: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, at + Vector2(-w / 2.0, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
