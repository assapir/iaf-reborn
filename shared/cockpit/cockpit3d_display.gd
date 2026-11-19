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
## The part of the DED's screen (texture fractions) the pilot sees from the default eye: FlightGear's DED sits 10 cm
## behind the ICP's face, so the ICP's right edge hides its left fifth, and the glareshield's lip its top and bottom
## edges (a ray cast from the eye over the model, 2026-11-17; docs/cockpit.md "3D cockpit"). The text keeps inside it.
const DED_SEEN := Rect2(0.22, 0.06, 0.75, 0.88)
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
	[[6, 32], 1, " FLCS A/P  FAIL "],
	[[33], 1, " FLCS A/P  DEGR "],
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
## What the last draw showed (tests): the RWR symbols' count, the DED's lines, the EHSI's range (NM, -1 none), heading
## bug and course (°, -1 none).
var shown := {}
## The 3D cockpit's switches (cockpit3d.gd `switches`): the EHSI's HDG and CRS knobs' settings.
var switches := {}
const HDG_BUG := "instrumentation/heading-indicator/heading-bug-deg"
const COURSE := "instrumentation/nav[0]/radials/selected-deg-knob"
const TACAN_KNOB := "instrumentation/tacan/volume"


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


## The 2D panel's RWR symbols (cockpit.gd draw_rwr_symbols) about the scope's centre; none with RWR damage (14). The
## modern F-16s draw their threat display instead (_threats).
func _rwr() -> void:
	var c := size / 2.0
	var r := size.x * 0.45
	for k in [0.5, 1.0]:
		draw_arc(c, r * k, 0.0, TAU, 64, RING, 2.0, true)
	var flags: Array = cockpit.damage_flags
	var n := 0
	if flags.size() > 14 and flags[14]:
		shown = {"symbols": 0}
	elif not cockpit.ews.is_empty():
		_threats(c, r)
	else:
		cockpit.draw_rwr_symbols(self, c, RWR_RADIUS, r / RWR_RADIUS)
		n = cockpit.rwr.filter(func(e): return e.active).size()
		shown = {"symbols": n}


## Ours, the modern F-16s' threat display (ews.gd, iaf_avionics::ews; modern-iaf/docs/ews.md): 12 ticks at 30° on the
## edge, the ownship "+", each threat's label in its frame (an aircraft's hat, AAA's box), the top threat in a diamond,
## a lock in a square, a launch in a flashing circle, a new threat flashing; the MAW's warnings as an "M" on the edge
## with the seconds to impact; SYS TEST's pattern.
func _threats(c: Vector2, r: float) -> void:
	var col := DED_GREEN
	for i in 12:
		var d := Vector2.from_angle(i * TAU / 12.0)
		draw_line(c + d * r, c + d * r * 0.93, RING, 2.0, true)
	var k := r * 0.06
	draw_line(c - Vector2(k, 0), c + Vector2(k, 0), col, 2.0, true)
	draw_line(c - Vector2(0, k), c + Vector2(0, k), col, 2.0, true)
	var blink := int(Time.get_ticks_msec() / 167) % 2 == 0  # 3 Hz (the MLU's launch light)
	# The symbols' size: the diamond 0.43 of the scope's radius wide, a lock's square 0.3, inside ews.rs's SEP (0.45).
	var fs := int(size.x * 0.06)
	var labels := []
	for sy in cockpit.ews.get("symbols", []):
		labels.append(String(sy.label))
		if (sy.new or sy.launch) and not blink:
			continue
		var p: Vector2 = c + Vector2(sy.at.x, -sy.at.y) * r * 0.86
		_text(p, String(sy.label), fs, col)
		var h := fs * 0.75
		match String(sy.kind):
			"air":
				draw_polyline(
					PackedVector2Array([p + Vector2(-h, -h * 0.7), p + Vector2(0, -h * 1.2), p + Vector2(h, -h * 0.7)]),
					col,
					2.0,
					true
				)
			"aaa":
				draw_rect(Rect2(p - Vector2(h * 0.8, h * 0.6), Vector2(h * 1.6, h * 1.2)), col, false, 1.5)
		if sy.launch:
			draw_arc(p, h * 1.5, 0.0, TAU, 24, col, 2.0, true)
		elif sy.lethal:
			draw_rect(Rect2(p - Vector2(h, h) * 1.3, Vector2(h, h) * 2.6), col, false, 2.0)
		if sy.diamond:
			var q := h * 1.9
			draw_polyline(
				PackedVector2Array(
					[p + Vector2(0, -q), p + Vector2(q, 0), p + Vector2(0, q), p + Vector2(-q, 0), p + Vector2(0, -q)]
				),
				col,
				2.0,
				true
			)
	var maw := []
	for wn in cockpit.ews.get("maw", []):
		var d := Vector2(sin(float(wn.bearing)), -cos(float(wn.bearing)))
		var p := c + d * r * 0.86
		var tti := "--" if is_inf(float(wn.tti)) else "%d" % mini(int(wn.tti), 99)
		maw.append(tti)
		if blink:
			_text(p, "M", fs, PFL_GREEN)
		_text(p + Vector2(0, fs * 1.1), tti, int(fs * 0.8), PFL_GREEN)
	shown = {
		"symbols": labels.size(),
		"labels": labels,
		"maw": maw,
		"testing": cockpit.ews.get("twd", {}).get("testing", false)
	}


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
	# Modern IAF's F-16s: the steerpoints with the markpoints, none until the INS navigates; TCN (the M button) the
	# TACAN station's bearing and range (IafUfc.tacan; no range in REC).
	var route: Array = cockpit.steer_route() if cockpit.ins_nav() else []
	# The TACAN receiver is off at its AUDIO 2 knob's OFF stop.
	var tacan_on := float(switches.get(TACAN_KNOB, 1.0)) > 0.0
	var tcn: Dictionary = (
		cockpit.ufc.tacan(cockpit.ufc_nav()) if cockpit.ufc != null and cockpit.ehsi_tcn and tacan_on else {}
	)
	if cockpit.ehsi_tcn and cockpit.ufc != null:
		route = []
		if not tcn.is_empty():
			route = [
				{
					"world":
					(
						st.world
						+ (
							Vector2(sin(deg_to_rad(tcn.bearing)), cos(deg_to_rad(tcn.bearing)))
							* maxf(float(tcn.range_m), 1.0)
						)
					)
				}
			]
	if not route.is_empty():
		var nav := Hud.nav_cues(st, route, 0 if cockpit.ehsi_tcn else cockpit.steer_index())
		var b := deg_to_rad(float(nav.bearing_deg) - hdg)
		var d := Vector2(sin(b), -cos(b))
		var n := Vector2(-d.y, d.x)
		var tip := c + d * r * 1.0
		draw_colored_polygon(
			PackedVector2Array([tip, tip - d * r * 0.16 + n * r * 0.07, tip - d * r * 0.16 - n * r * 0.07]), CYAN
		)
		draw_line(c - d * r * 0.98, c - d * r * 0.84, CYAN, 3.0, true)  # its tail
		dist = float(nav.dist_nm) if not (cockpit.ehsi_tcn and float(tcn.range_m) <= 0.0) else -1.0
		if dist >= 0.0:
			_text(Vector2(size.x * 0.13, size.y * 0.1), "%03d" % mini(roundi(dist), 999), fs, WHITE)
			_text(Vector2(size.x * 0.13, size.y * 0.18), "NM", int(fs * 0.7), WHITE)
	_text(Vector2(size.x * 0.12, size.y * 0.92), "TCN" if cockpit.ehsi_tcn else "NAV", fs, WHITE)
	# The heading bug and the course arrow where their knobs (HDG, CRS) set them, as the model shows the knobs until
	# turned: 0° (the jet's setting at a cold start is open; their shapes and colour inferred).
	var bug := float(switches.get(HDG_BUG, -1.0))
	if bug >= 0.0:
		var a := deg_to_rad(bug - hdg)
		var d := Vector2(sin(a), -cos(a))
		var n := Vector2(-d.y, d.x) * r * 0.08
		var o := c + d * r * 1.12
		var i := c + d * r * 0.98
		# A notched block astride the rose's rim.
		draw_colored_polygon(
			PackedVector2Array([i - n, o - n, o - n * 0.35, i + d * r * 0.06, o + n * 0.35, o + n, i + n]), WHITE
		)
	var crs := float(switches.get(COURSE, -1.0))
	if crs >= 0.0:
		var a := deg_to_rad(crs - hdg)
		var d := Vector2(sin(a), -cos(a))
		var n := Vector2(-d.y, d.x)
		draw_line(c + d * r * 0.4, c + d * r * 0.8, WHITE, 3.0, true)
		draw_colored_polygon(
			PackedVector2Array([c + d * r * 0.82, c + d * r * 0.68 + n * r * 0.07, c + d * r * 0.68 - n * r * 0.07]),
			WHITE
		)
		draw_line(c - d * r * 0.4, c - d * r * 0.8, WHITE, 3.0, true)  # its tail
	shown = {
		"dist_nm": dist, "heading": hdg, "hdg_bug": bug, "course": crs, "mode": "TCN" if cockpit.ehsi_tcn else "NAV"
	}


## The DED, 5 lines of 24 characters. Modern IAF's F-16s: the up-front controls' pages (cockpit.gd ded_lines,
## IafUfc; blank without the UFC's power); reborn's: the CNI page, the steerpoint on line 1, the time of day on line 3.
func _ded() -> void:
	var lines := []
	if cockpit.ufc != null:
		lines = Array(cockpit.ded_lines())
		lines.resize(5)
		lines = lines.map(func(l): return "" if l == null else String(l))
	else:
		var stpt := "STPT %2d" % (cockpit.current_waypoint + 1) if not cockpit.waypoints.is_empty() else ""
		var t := int(float(cockpit.state.get("tod", 0.0))) % 86400
		lines = [
			"%24s" % (stpt + "     "), "", "%24s" % ("%02d:%02d:%02d   " % [t / 3600, t / 60 % 60, t % 60]), "", ""
		]
	# A character per cell, so the DED's columns line up whatever the font (the sim's display font is proportional),
	# inside the part of the screen the pilot's eye sees (DED_SEEN).
	var box := Rect2(DED_SEEN.position * size, DED_SEEN.size * size)
	var lh := box.size.y / 5.0
	var cell := box.size.x / 24.0
	var fs := int(minf(lh * 0.9, cell / 0.6))
	for i in 5:
		var line: String = lines[i]
		for j in line.length():
			if line[j] != " ":
				_text(box.position + Vector2((j + 0.5) * cell, lh * (i + 0.5)), line[j], fs, DED_GREEN)
	shown = {"lines": lines}


## The pilot fault list display (FlightGear's pfd.nas layout): line 1 the classes with a fault (FLCS, ENG, AV), lines
## 3-5 the first three faults, a third line framed by ▼ when more wait.
func _pfl() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PFL_BG)
	var lines := pfl_lines(cockpit.pfl_flags(), cockpit.pfl_acked)
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


## The FAULTS rows active in the damage `flags`.
static func pfl_faults(flags: Array) -> Array:
	return FAULTS.filter(func(f): return f[0].any(func(i: int) -> bool: return i < flags.size() and bool(flags[i])))


## The fault list's five lines for the damage `flags` (_pfl; the HUD's DED DATA at PFL, cockpit.gd hud_panel_input):
## the system codes of every active fault, the faults not in `acked` (F-ACK's, cockpit3d.gd fault_ack).
static func pfl_lines(flags: Array, acked := []) -> Array:
	var faults := []
	var classes := [false, false, false]
	for f in pfl_faults(flags):
		classes[maxi(f[1] - 1, 0)] = true
		if not acked.has(f[2]):
			faults.append(f[2])
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
	return lines


func _text(at: Vector2, t: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, at + Vector2(-w / 2.0, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
